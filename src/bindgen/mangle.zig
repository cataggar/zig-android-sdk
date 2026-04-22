//! Identifier sanitization + overload name mangling for bindgen.

const std = @import("std");

/// Zig reserved words we'll need to escape when a Java identifier collides.
const zig_keywords = [_][]const u8{
    "addrspace",       "align",      "allowzero",  "and",           "anyframe",    "anytype",     "asm",          "async",
    "await",           "break",      "callconv",   "catch",         "comptime",    "const",       "continue",     "defer",
    "else",            "enum",       "errdefer",   "error",         "export",      "extern",      "fn",           "for",
    "if",              "inline",     "linksection","noalias",       "noinline",    "nosuspend",   "null",         "opaque",
    "or",              "orelse",     "packed",     "pub",           "resume",      "return",      "struct",       "suspend",
    "switch",          "test",       "threadlocal","true",          "try",         "undefined",   "union",        "unreachable",
    "usingnamespace",  "var",        "volatile",   "while",         "false",       "void",
};

/// Zig primitive types/values — not reserved words, but shadow errors at
/// declaration sites. We escape them the same way.
const zig_primitives = [_][]const u8{
    "type",       "anyerror", "anyopaque", "anytype",
    "bool",       "comptime_int", "comptime_float",
    "f16",        "f32", "f64", "f80", "f128",
    "i0", "i8", "i16", "i32", "i64", "i128",
    "u0", "u8", "u16", "u32", "u64", "u128",
    "isize",      "usize", "c_char", "c_short", "c_ushort",
    "c_int",      "c_uint", "c_long", "c_ulong", "c_longlong", "c_ulonglong", "c_longdouble",
};

pub fn isZigKeyword(s: []const u8) bool {
    for (zig_keywords) |k| if (std.mem.eql(u8, s, k)) return true;
    for (zig_primitives) |k| if (std.mem.eql(u8, s, k)) return true;
    return false;
}

/// Sanitize a Java identifier into a valid Zig identifier:
///   - replace '$' with '_' (inner-class separator in JVM)
///   - prepend '_' if the name starts with a digit
///   - wrap in `@"..."` if it's a Zig keyword
///   - keep '<init>' / '<clinit>' mapped to `init` / `clinit`
pub fn sanitize(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, name, "<init>")) return try allocator.dupe(u8, "init");
    if (std.mem.eql(u8, name, "<clinit>")) return try allocator.dupe(u8, "clinit");

    var buf: std.ArrayList(u8) = .empty;
    if (name.len == 0) return Error.EmptyIdentifier;
    if (std.ascii.isDigit(name[0])) try buf.append(allocator, '_');
    for (name) |c| try buf.append(allocator, if (c == '$') '_' else c);
    const inner = try buf.toOwnedSlice(allocator);

    if (isZigKeyword(inner)) {
        defer allocator.free(inner);
        return try std.fmt.allocPrint(allocator, "@\"{s}\"", .{inner});
    }
    return inner;
}

pub const Error = error{
    EmptyIdentifier,
} || std.mem.Allocator.Error;

/// Short, human-readable single-type mangle: `I → i32`, `J → i64`,
/// `Ljava/lang/String; → String`, `Landroid/view/View; → View`, `[B → byteArr`.
/// Used to disambiguate overloads in the emitted Zig fn name.
fn shortType(allocator: std.mem.Allocator, descriptor: []const u8, i: *usize) ![]const u8 {
    if (i.* >= descriptor.len) return error.EmptyIdentifier;
    const c = descriptor[i.*];
    i.* += 1;
    return switch (c) {
        'V' => try allocator.dupe(u8, "void"),
        'Z' => try allocator.dupe(u8, "bool"),
        'B' => try allocator.dupe(u8, "byte"),
        'C' => try allocator.dupe(u8, "char"),
        'S' => try allocator.dupe(u8, "short"),
        'I' => try allocator.dupe(u8, "int"),
        'J' => try allocator.dupe(u8, "long"),
        'F' => try allocator.dupe(u8, "float"),
        'D' => try allocator.dupe(u8, "double"),
        'L' => blk: {
            const start = i.*;
            while (i.* < descriptor.len and descriptor[i.*] != ';') : (i.* += 1) {}
            if (i.* >= descriptor.len) return error.EmptyIdentifier;
            const name = descriptor[start..i.*];
            i.* += 1;
            const last = std.mem.lastIndexOfScalar(u8, name, '/') orelse 0;
            const simple = if (last == 0) name else name[last + 1 ..];
            // Replace '$' — common for inner classes.
            var out: std.ArrayList(u8) = .empty;
            for (simple) |ch| try out.append(allocator, if (ch == '$') '_' else ch);
            break :blk try out.toOwnedSlice(allocator);
        },
        '[' => blk: {
            const inner = try shortType(allocator, descriptor, i);
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "{s}Arr", .{inner});
        },
        else => try allocator.dupe(u8, "unknown"),
    };
}

/// Given `name` + method descriptor `desc` like `(ILjava/lang/String;)V`,
/// produce an overload-mangled identifier like `foo__int_String`.
/// Void return is dropped from the mangle to keep names short.
pub fn overloadMangle(
    allocator: std.mem.Allocator,
    name: []const u8,
    desc: []const u8,
) ![]const u8 {
    // Build the raw mangled identifier first (no keyword-quoting), then
    // sanitize once at the very end. Otherwise for names that are Zig
    // keywords (e.g. `await`) we would emit `@"await"__0`, which is not
    // a valid identifier syntax.
    const raw_base: []const u8 = if (std.mem.eql(u8, name, "<init>"))
        "init"
    else if (std.mem.eql(u8, name, "<clinit>"))
        "clinit"
    else
        name;

    var out_buf: std.ArrayList(u8) = .empty;
    defer out_buf.deinit(allocator);
    if (raw_base.len == 0) return Error.EmptyIdentifier;
    if (std.ascii.isDigit(raw_base[0])) try out_buf.append(allocator, '_');
    for (raw_base) |c| try out_buf.append(allocator, if (c == '$') '_' else c);

    if (desc.len == 0 or desc[0] != '(') {
        return sanitize(allocator, out_buf.items);
    }

    var parts: std.ArrayList([]const u8) = .empty;
    defer {
        for (parts.items) |p| allocator.free(p);
        parts.deinit(allocator);
    }

    var i: usize = 1;
    while (i < desc.len and desc[i] != ')') {
        try parts.append(allocator, try shortType(allocator, desc, &i));
    }

    try out_buf.appendSlice(allocator, "__");
    if (parts.items.len == 0) {
        try out_buf.append(allocator, '0');
    } else {
        for (parts.items, 0..) |p, idx| {
            if (idx > 0) try out_buf.append(allocator, '_');
            try out_buf.appendSlice(allocator, p);
        }
    }
    return sanitize(allocator, out_buf.items);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "sanitize: basic, keyword, dollar, digit" {
    const a = testing.allocator;
    {
        const s = try sanitize(a, "hello");
        defer a.free(s);
        try testing.expectEqualStrings("hello", s);
    }
    {
        const s = try sanitize(a, "type");
        defer a.free(s);
        try testing.expectEqualStrings("@\"type\"", s);
    }
    {
        const s = try sanitize(a, "Outer$Inner");
        defer a.free(s);
        try testing.expectEqualStrings("Outer_Inner", s);
    }
    {
        const s = try sanitize(a, "9arg");
        defer a.free(s);
        try testing.expectEqualStrings("_9arg", s);
    }
    {
        const s = try sanitize(a, "<init>");
        defer a.free(s);
        try testing.expectEqualStrings("init", s);
    }
}

test "overloadMangle: drawText variants" {
    const a = testing.allocator;
    // drawText(String, float, float, Paint)
    {
        const m = try overloadMangle(a, "drawText", "(Ljava/lang/String;FFLandroid/graphics/Paint;)V");
        defer a.free(m);
        try testing.expectEqualStrings("drawText__String_float_float_Paint", m);
    }
    // drawText(char[], int, int, float, float, Paint)
    {
        const m = try overloadMangle(a, "drawText", "([CIIFFLandroid/graphics/Paint;)V");
        defer a.free(m);
        try testing.expectEqualStrings("drawText__charArr_int_int_float_float_Paint", m);
    }
    // no-arg
    {
        const m = try overloadMangle(a, "foo", "()V");
        defer a.free(m);
        try testing.expectEqualStrings("foo__0", m);
    }
}
