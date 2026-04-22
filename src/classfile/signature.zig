//! JVMS §4.7.9.1 `Signature` attribute parser — preserves the generic
//! type info that the erased descriptor format (JVMS §4.3) throws away.
//!
//! Grammar (simplified):
//!
//!   JavaTypeSignature    := ReferenceTypeSignature | BaseType
//!   BaseType             := B|C|D|F|I|J|S|Z
//!   ReferenceTypeSignature := ClassTypeSignature | TypeVariableSignature | ArrayTypeSignature
//!   ClassTypeSignature   := 'L' [PkgSpec] SimpleClassTypeSig {'.' SimpleClassTypeSig} ';'
//!   PkgSpec              := Identifier '/' {PkgSpec}
//!   SimpleClassTypeSig   := Identifier [TypeArguments]
//!   TypeArguments        := '<' TypeArgument+ '>'
//!   TypeArgument         := [WildcardIndicator] RefTypeSig | '*'
//!   WildcardIndicator    := '+' | '-'
//!   TypeVariableSignature := 'T' Identifier ';'
//!   ArrayTypeSignature   := '[' JavaTypeSignature
//!   ClassSignature       := [TypeParameters] SuperclassSig {SuperinterfaceSig}
//!   TypeParameters       := '<' TypeParameter+ '>'
//!   TypeParameter        := Identifier ClassBound {InterfaceBound}
//!   ClassBound           := ':' [RefTypeSig]
//!   InterfaceBound       := ':' RefTypeSig
//!   MethodSignature      := [TypeParameters] '(' JavaTypeSignature* ')' Result ThrowsSig*
//!   Result               := JavaTypeSignature | 'V'
//!   ThrowsSignature      := '^' (ClassTypeSig | TypeVariableSig)
//!   FieldSignature       := ReferenceTypeSignature
//!
//! All slice fields (Identifiers, class names) alias the input `src`. Tree
//! nodes are allocated with the caller's allocator (typically an arena).

const std = @import("std");

pub const Error = error{
    UnexpectedEnd,
    UnexpectedChar,
    BadBaseType,
} || std.mem.Allocator.Error;

pub const BaseType = enum(u8) {
    byte = 'B',
    char = 'C',
    double = 'D',
    float = 'F',
    int = 'I',
    long = 'J',
    short = 'S',
    boolean = 'Z',
};

pub const Wildcard = enum { invariant, covariant, contravariant };

/// A parsed Java type expression — covers both `JavaTypeSignature` (when
/// it can be a base type) and `ReferenceTypeSignature`. Use `asReference`
/// to project out the reference-only subset where needed.
pub const TypeSig = union(enum) {
    base: BaseType,
    class: ClassType,
    type_var: []const u8, // identifier after 'T', without the trailing ';'
    array: *TypeSig,

    pub fn isReference(self: TypeSig) bool {
        return self != .base;
    }
};

/// Class-or-inner-class chain. `name` is the fully qualified outer name
/// (e.g. `"java/util/Map"`); `inner` is the suffix chain produced by the
/// `.Entry` dot-separated inner class notation (rare but present in
/// android.jar, e.g. `Ljava/util/Map<...>.Entry<...>;`).
pub const ClassType = struct {
    name: []const u8,
    type_args: []TypeArgument,
    inner: []InnerClass,
};

pub const InnerClass = struct {
    name: []const u8,
    type_args: []TypeArgument,
};

pub const TypeArgument = union(enum) {
    any, // '*'
    typed: struct { wildcard: Wildcard, type_sig: TypeSig },
};

pub const TypeParameter = struct {
    name: []const u8,
    class_bound: ?TypeSig, // reference type; optional per JVMS
    interface_bounds: []TypeSig,
};

pub const ClassSignature = struct {
    type_params: []TypeParameter,
    superclass: ClassType,
    superinterfaces: []ClassType,
};

pub const MethodSignature = struct {
    type_params: []TypeParameter,
    params: []TypeSig,
    return_type: ?TypeSig, // null for 'V' (void)
    throws: []TypeSig, // each is either ClassType or type_var
};

pub const FieldSignature = TypeSig;

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const Parser = struct {
    src: []const u8,
    pos: usize,
    gpa: std.mem.Allocator,

    fn peek(p: *Parser) Error!u8 {
        if (p.pos >= p.src.len) return Error.UnexpectedEnd;
        return p.src[p.pos];
    }

    fn eat(p: *Parser, c: u8) Error!void {
        if (p.pos >= p.src.len) return Error.UnexpectedEnd;
        if (p.src[p.pos] != c) return Error.UnexpectedChar;
        p.pos += 1;
    }

    fn advance(p: *Parser) Error!u8 {
        if (p.pos >= p.src.len) return Error.UnexpectedEnd;
        const c = p.src[p.pos];
        p.pos += 1;
        return c;
    }

    /// Consume up to (but not including) any char in `stops`. Returns the
    /// sliced identifier. Used for both simple identifiers and slash-
    /// separated class names.
    fn takeUntil(p: *Parser, comptime stops: []const u8) []const u8 {
        const start = p.pos;
        while (p.pos < p.src.len) : (p.pos += 1) {
            inline for (stops) |s| {
                if (p.src[p.pos] == s) return p.src[start..p.pos];
            }
        }
        return p.src[start..p.pos];
    }

    fn parseJavaType(p: *Parser) Error!TypeSig {
        const c = try p.peek();
        return switch (c) {
            'B', 'C', 'D', 'F', 'I', 'J', 'S', 'Z' => blk: {
                p.pos += 1;
                break :blk TypeSig{ .base = @enumFromInt(c) };
            },
            else => try p.parseRefType(),
        };
    }

    fn parseRefType(p: *Parser) Error!TypeSig {
        const c = try p.peek();
        return switch (c) {
            'L' => .{ .class = try p.parseClassType() },
            'T' => blk: {
                p.pos += 1;
                const name = p.takeUntil(";");
                try p.eat(';');
                break :blk TypeSig{ .type_var = name };
            },
            '[' => blk: {
                p.pos += 1;
                const inner = try p.gpa.create(TypeSig);
                inner.* = try p.parseJavaType();
                break :blk TypeSig{ .array = inner };
            },
            else => Error.UnexpectedChar,
        };
    }

    fn parseClassType(p: *Parser) Error!ClassType {
        try p.eat('L');
        // Outer qualified name: runs of identifier chars separated by '/'.
        // Ends at one of '<', '.', ';'.
        const name = p.takeUntil(&[_]u8{ '<', '.', ';' });

        var type_args: []TypeArgument = &.{};
        if ((try p.peek()) == '<') type_args = try p.parseTypeArgs();

        // Optional inner class chain. Each '.' introduces a
        // SimpleClassTypeSignature relative to the enclosing class.
        var inner_list: std.ArrayList(InnerClass) = .empty;
        while ((try p.peek()) == '.') {
            p.pos += 1;
            const iname = p.takeUntil(&[_]u8{ '<', '.', ';' });
            var iargs: []TypeArgument = &.{};
            if ((try p.peek()) == '<') iargs = try p.parseTypeArgs();
            try inner_list.append(p.gpa, .{ .name = iname, .type_args = iargs });
        }
        try p.eat(';');

        return .{
            .name = name,
            .type_args = type_args,
            .inner = try inner_list.toOwnedSlice(p.gpa),
        };
    }

    fn parseTypeArgs(p: *Parser) Error![]TypeArgument {
        try p.eat('<');
        var args: std.ArrayList(TypeArgument) = .empty;
        while ((try p.peek()) != '>') {
            const c = try p.peek();
            if (c == '*') {
                p.pos += 1;
                try args.append(p.gpa, .any);
                continue;
            }
            var wc: Wildcard = .invariant;
            if (c == '+') {
                wc = .covariant;
                p.pos += 1;
            } else if (c == '-') {
                wc = .contravariant;
                p.pos += 1;
            }
            const ts = try p.parseRefType();
            try args.append(p.gpa, .{ .typed = .{ .wildcard = wc, .type_sig = ts } });
        }
        try p.eat('>');
        return try args.toOwnedSlice(p.gpa);
    }

    fn parseTypeParams(p: *Parser) Error![]TypeParameter {
        if ((try p.peek()) != '<') return &.{};
        try p.eat('<');
        var list: std.ArrayList(TypeParameter) = .empty;
        while ((try p.peek()) != '>') {
            const name = p.takeUntil(":");
            try p.eat(':');

            // ClassBound — optional RefTypeSig after the colon (may be
            // absent, in which case the next char is either ':' for an
            // interface bound or the next TypeParameter's identifier).
            var class_bound: ?TypeSig = null;
            const after = try p.peek();
            if (after != ':' and after != '>') {
                class_bound = try p.parseRefType();
            }

            var ibounds: std.ArrayList(TypeSig) = .empty;
            while ((try p.peek()) == ':') {
                p.pos += 1;
                try ibounds.append(p.gpa, try p.parseRefType());
            }
            try list.append(p.gpa, .{
                .name = name,
                .class_bound = class_bound,
                .interface_bounds = try ibounds.toOwnedSlice(p.gpa),
            });
        }
        try p.eat('>');
        return try list.toOwnedSlice(p.gpa);
    }
};

pub fn parseField(gpa: std.mem.Allocator, src: []const u8) Error!FieldSignature {
    var p = Parser{ .src = src, .pos = 0, .gpa = gpa };
    return try p.parseRefType();
}

pub fn parseClass(gpa: std.mem.Allocator, src: []const u8) Error!ClassSignature {
    var p = Parser{ .src = src, .pos = 0, .gpa = gpa };
    const type_params = try p.parseTypeParams();
    const superclass = try p.parseClassType();
    var ifaces: std.ArrayList(ClassType) = .empty;
    while (p.pos < p.src.len) {
        try ifaces.append(p.gpa, try p.parseClassType());
    }
    return .{
        .type_params = type_params,
        .superclass = superclass,
        .superinterfaces = try ifaces.toOwnedSlice(p.gpa),
    };
}

pub fn parseMethod(gpa: std.mem.Allocator, src: []const u8) Error!MethodSignature {
    var p = Parser{ .src = src, .pos = 0, .gpa = gpa };
    const type_params = try p.parseTypeParams();
    try p.eat('(');
    var params: std.ArrayList(TypeSig) = .empty;
    while ((try p.peek()) != ')') {
        try params.append(p.gpa, try p.parseJavaType());
    }
    try p.eat(')');

    var ret: ?TypeSig = null;
    if ((try p.peek()) == 'V') {
        p.pos += 1;
    } else {
        ret = try p.parseJavaType();
    }

    var throws: std.ArrayList(TypeSig) = .empty;
    while (p.pos < p.src.len and p.src[p.pos] == '^') {
        p.pos += 1;
        try throws.append(p.gpa, try p.parseRefType());
    }

    return .{
        .type_params = type_params,
        .params = try params.toOwnedSlice(p.gpa),
        .return_type = ret,
        .throws = try throws.toOwnedSlice(p.gpa),
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "field signature: simple generic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // List<String>
    const ts = try parseField(arena.allocator(), "Ljava/util/List<Ljava/lang/String;>;");
    try testing.expect(ts == .class);
    try testing.expectEqualStrings("java/util/List", ts.class.name);
    try testing.expectEqual(@as(usize, 1), ts.class.type_args.len);
    const arg = ts.class.type_args[0];
    try testing.expect(arg == .typed);
    try testing.expectEqual(Wildcard.invariant, arg.typed.wildcard);
    try testing.expectEqualStrings("java/lang/String", arg.typed.type_sig.class.name);
}

test "field signature: wildcards and arrays" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Map<? extends K, ? super V>
    const ts = try parseField(
        arena.allocator(),
        "Ljava/util/Map<+TK;-TV;>;",
    );
    try testing.expectEqual(@as(usize, 2), ts.class.type_args.len);
    try testing.expectEqual(Wildcard.covariant, ts.class.type_args[0].typed.wildcard);
    try testing.expectEqual(Wildcard.contravariant, ts.class.type_args[1].typed.wildcard);
    try testing.expectEqualStrings("K", ts.class.type_args[0].typed.type_sig.type_var);
}

test "field signature: nested inner class with generics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Map<K, V>.Entry<K, V>
    const ts = try parseField(
        arena.allocator(),
        "Ljava/util/Map<TK;TV;>.Entry<TK;TV;>;",
    );
    try testing.expectEqualStrings("java/util/Map", ts.class.name);
    try testing.expectEqual(@as(usize, 1), ts.class.inner.len);
    try testing.expectEqualStrings("Entry", ts.class.inner[0].name);
    try testing.expectEqual(@as(usize, 2), ts.class.inner[0].type_args.len);
}

test "field signature: array of wildcard" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // List<?>[]
    const ts = try parseField(arena.allocator(), "[Ljava/util/List<*>;");
    try testing.expect(ts == .array);
    try testing.expect(ts.array.* == .class);
    try testing.expect(ts.array.class.type_args[0] == .any);
}

test "class signature: generic class with bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // class Foo<T extends Number & Comparable<T>> extends Bar<T> implements Baz
    const cs = try parseClass(
        arena.allocator(),
        "<T:Ljava/lang/Number;:Ljava/lang/Comparable<TT;>;>Lcom/x/Bar<TT;>;Lcom/x/Baz;",
    );
    try testing.expectEqual(@as(usize, 1), cs.type_params.len);
    try testing.expectEqualStrings("T", cs.type_params[0].name);
    try testing.expect(cs.type_params[0].class_bound != null);
    try testing.expectEqualStrings("java/lang/Number", cs.type_params[0].class_bound.?.class.name);
    try testing.expectEqual(@as(usize, 1), cs.type_params[0].interface_bounds.len);
    try testing.expectEqualStrings("com/x/Bar", cs.superclass.name);
    try testing.expectEqual(@as(usize, 1), cs.superinterfaces.len);
}

test "class signature: empty class bound" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // class Foo<T:> extends Object     (class bound omitted)
    const cs = try parseClass(
        arena.allocator(),
        "<T::Ljava/lang/Comparable<TT;>;>Ljava/lang/Object;",
    );
    try testing.expect(cs.type_params[0].class_bound == null);
    try testing.expectEqual(@as(usize, 1), cs.type_params[0].interface_bounds.len);
}

test "method signature: generic method with void return" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // <T> void foo(List<T>, int)
    const ms = try parseMethod(
        arena.allocator(),
        "<T:Ljava/lang/Object;>(Ljava/util/List<TT;>;I)V",
    );
    try testing.expectEqual(@as(usize, 1), ms.type_params.len);
    try testing.expectEqual(@as(usize, 2), ms.params.len);
    try testing.expect(ms.params[0] == .class);
    try testing.expect(ms.params[1] == .base);
    try testing.expectEqual(BaseType.int, ms.params[1].base);
    try testing.expect(ms.return_type == null);
}

test "method signature: generic return + throws" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // <T> T foo() throws IOException, T
    const ms = try parseMethod(
        arena.allocator(),
        "<T:Ljava/lang/Throwable;>()TT;^Ljava/io/IOException;^TT;",
    );
    try testing.expect(ms.return_type.? == .type_var);
    try testing.expectEqualStrings("T", ms.return_type.?.type_var);
    try testing.expectEqual(@as(usize, 2), ms.throws.len);
    try testing.expect(ms.throws[0] == .class);
    try testing.expect(ms.throws[1] == .type_var);
}

test "method signature: non-generic baseline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // int bar(String)
    const ms = try parseMethod(arena.allocator(), "(Ljava/lang/String;)I");
    try testing.expectEqual(@as(usize, 0), ms.type_params.len);
    try testing.expectEqual(@as(usize, 1), ms.params.len);
    try testing.expectEqual(BaseType.int, ms.return_type.?.base);
}
