//! Top-level Java class file parser — JVMS §4.1.
//!
//! Scope (Phase 1): produce exactly enough to drive JNI binding generation.
//!   - header (magic, version)
//!   - constant pool
//!   - class/super/interfaces resolved to their internal names
//!   - fields: access, name, descriptor, and `ConstantValue` (for static
//!     final primitive/string initializers)
//!   - methods: access, name, descriptor
//!   - class-level and member-level `attributes_raw` preserved for Phase 2+
//!
//! `descriptor` strings are returned verbatim — class files already store
//! them in JNI wire format (`(II)V`, `Ljava/lang/String;`, `[B`), so no
//! translation is required.

const std = @import("std");

pub const reader_mod = @import("reader.zig");
pub const cp = @import("constant_pool.zig");
pub const attribute = @import("attribute.zig");
pub const jar = @import("jar.zig");
pub const signature = @import("signature.zig");

pub const MAGIC: u32 = 0xCAFEBABE;

pub const ClassAccess = packed struct(u16) {
    public: bool,
    private: bool,
    protected: bool,
    static: bool,
    final: bool,
    super_or_synchronized: bool, // ACC_SUPER on class, ACC_SYNCHRONIZED on method
    volatile_or_bridge: bool, // ACC_VOLATILE on field, ACC_BRIDGE on method
    transient_or_varargs: bool, // ACC_TRANSIENT on field, ACC_VARARGS on method
    native: bool,
    interface: bool,
    abstract: bool,
    strict: bool,
    synthetic: bool,
    annotation: bool,
    enum_: bool,
    module: bool,
};

pub const Field = struct {
    access: ClassAccess,
    name: []const u8,
    descriptor: []const u8,
    /// Raw `Signature` attribute text (JVMS §4.7.9), or null if absent.
    /// Parse with `signature.parseField`.
    signature: ?[]const u8,
    constant_value: ?attribute.ConstantValue,
    attributes_raw: []attribute.Raw,
};

pub const Method = struct {
    access: ClassAccess,
    name: []const u8,
    descriptor: []const u8,
    /// Raw `Signature` attribute text, or null if absent. Parse with
    /// `signature.parseMethod`.
    signature: ?[]const u8,
    attributes_raw: []attribute.Raw,
};

pub const ClassFile = struct {
    arena: std.heap.ArenaAllocator,
    major: u16,
    minor: u16,
    access: ClassAccess,
    this_name: []const u8,
    super_name: ?[]const u8, // only null for java/lang/Object and module-info
    interfaces: [][]const u8,
    fields: []Field,
    methods: []Method,
    attributes_raw: []attribute.Raw,
    /// Raw `Signature` attribute text for the class, or null if absent.
    /// Parse with `signature.parseClass`.
    signature: ?[]const u8,
    pool: cp.Pool,

    pub fn deinit(self: *ClassFile) void {
        self.arena.deinit();
    }
};

pub const Error = error{
    BadMagic,
    Truncated,
} || cp.ParseError || attribute.ParseError;

/// Parse `bytes` into a `ClassFile`. The returned value owns an arena that
/// is freed by `deinit()`. Field slices (`name`, `descriptor`, `utf8` entries)
/// alias the input `bytes`; keep them alive for the lifetime of the result.
pub fn parseClass(
    parent_allocator: std.mem.Allocator,
    bytes: []const u8,
) Error!ClassFile {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    var r = reader_mod.Reader.init(bytes);

    const magic = r.readU32() catch return error.Truncated;
    if (magic != MAGIC) return error.BadMagic;
    const minor = try r.readU16();
    const major = try r.readU16();

    const cp_count = try r.readU16();
    const pool = try cp.parse(a, &r, cp_count);

    const access: ClassAccess = @bitCast(try r.readU16());
    const this_index = try r.readU16();
    const super_index = try r.readU16();

    const this_name = try pool.getClassName(this_index);
    const super_name: ?[]const u8 = if (super_index == 0) null else try pool.getClassName(super_index);

    const interfaces_count = try r.readU16();
    const interfaces = try a.alloc([]const u8, interfaces_count);
    for (interfaces) |*iface| {
        const idx = try r.readU16();
        iface.* = try pool.getClassName(idx);
    }

    const fields_count = try r.readU16();
    const fields = try a.alloc(Field, fields_count);
    for (fields) |*f| {
        const facc: ClassAccess = @bitCast(try r.readU16());
        const name_idx = try r.readU16();
        const desc_idx = try r.readU16();
        const attrs_count = try r.readU16();
        const attrs = try attribute.parseList(a, &r, pool, attrs_count);

        var cv: ?attribute.ConstantValue = null;
        if (attribute.find(attrs, "ConstantValue")) |raw| {
            cv = try attribute.decodeConstantValue(pool, raw.*);
        }

        f.* = .{
            .access = facc,
            .name = try pool.getUtf8(name_idx),
            .descriptor = try pool.getUtf8(desc_idx),
            .signature = try attribute.findSignature(pool, attrs),
            .constant_value = cv,
            .attributes_raw = attrs,
        };
    }

    const methods_count = try r.readU16();
    const methods = try a.alloc(Method, methods_count);
    for (methods) |*m| {
        const macc: ClassAccess = @bitCast(try r.readU16());
        const name_idx = try r.readU16();
        const desc_idx = try r.readU16();
        const attrs_count = try r.readU16();
        const attrs = try attribute.parseList(a, &r, pool, attrs_count);
        m.* = .{
            .access = macc,
            .name = try pool.getUtf8(name_idx),
            .descriptor = try pool.getUtf8(desc_idx),
            .signature = try attribute.findSignature(pool, attrs),
            .attributes_raw = attrs,
        };
    }

    const cls_attrs_count = try r.readU16();
    const cls_attrs = try attribute.parseList(a, &r, pool, cls_attrs_count);

    return .{
        .arena = arena,
        .major = major,
        .minor = minor,
        .access = access,
        .this_name = this_name,
        .super_name = super_name,
        .interfaces = interfaces,
        .fields = fields,
        .methods = methods,
        .attributes_raw = cls_attrs,
        .signature = try attribute.findSignature(pool, cls_attrs),
        .pool = pool,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test {
    std.testing.refAllDecls(@This());
    _ = @import("reader.zig");
    _ = @import("constant_pool.zig");
    _ = @import("attribute.zig");
    _ = @import("signature.zig");
}

/// Build a minimal but fully valid `.class` representing:
///
///     public final class Foo {
///         public static final int X = 42;
///         public static int bar(java.lang.String s) { ... }
///     }
///
/// We skip emitting a `Code` attribute (methods are allowed to have no Code
/// if `ACC_NATIVE` or `ACC_ABSTRACT` is set, which we set here) so the file
/// stays tiny — we never parse Code anyway.
fn buildFixture(a: std.mem.Allocator) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const w = struct {
        fn u8v(b: *std.ArrayList(u8), al: std.mem.Allocator, v: u8) !void {
            try b.append(al, v);
        }
        fn u16v(b: *std.ArrayList(u8), al: std.mem.Allocator, v: u16) !void {
            try b.appendSlice(al, &std.mem.toBytes(std.mem.nativeToBig(u16, v)));
        }
        fn u32v(b: *std.ArrayList(u8), al: std.mem.Allocator, v: u32) !void {
            try b.appendSlice(al, &std.mem.toBytes(std.mem.nativeToBig(u32, v)));
        }
        fn i32v(b: *std.ArrayList(u8), al: std.mem.Allocator, v: i32) !void {
            try b.appendSlice(al, &std.mem.toBytes(std.mem.nativeToBig(i32, v)));
        }
        fn utf8(b: *std.ArrayList(u8), al: std.mem.Allocator, s: []const u8) !void {
            try u8v(b, al, 1); // tag = CONSTANT_Utf8
            try u16v(b, al, @intCast(s.len));
            try b.appendSlice(al, s);
        }
    };

    // Header: magic, minor=0, major=52 (Java 8)
    try w.u32v(&buf, a, MAGIC);
    try w.u16v(&buf, a, 0);
    try w.u16v(&buf, a, 52);

    // constant_pool_count = (last valid index) + 1
    // We will use indices 1..10, so count = 11.
    try w.u16v(&buf, a, 11);
    // 1: Utf8 "Foo"
    try w.utf8(&buf, a, "Foo");
    // 2: Class #1
    try w.u8v(&buf, a, 7);
    try w.u16v(&buf, a, 1);
    // 3: Utf8 "java/lang/Object"
    try w.utf8(&buf, a, "java/lang/Object");
    // 4: Class #3
    try w.u8v(&buf, a, 7);
    try w.u16v(&buf, a, 3);
    // 5: Utf8 "X"
    try w.utf8(&buf, a, "X");
    // 6: Utf8 "I"
    try w.utf8(&buf, a, "I");
    // 7: Utf8 "ConstantValue"
    try w.utf8(&buf, a, "ConstantValue");
    // 8: Integer 42
    try w.u8v(&buf, a, 3);
    try w.i32v(&buf, a, 42);
    // 9: Utf8 "bar"
    try w.utf8(&buf, a, "bar");
    // 10: Utf8 "(Ljava/lang/String;)I"
    try w.utf8(&buf, a, "(Ljava/lang/String;)I");

    // access_flags: ACC_PUBLIC | ACC_FINAL | ACC_SUPER = 0x0031
    try w.u16v(&buf, a, 0x0031);
    // this_class = #2, super_class = #4
    try w.u16v(&buf, a, 2);
    try w.u16v(&buf, a, 4);
    // interfaces_count = 0
    try w.u16v(&buf, a, 0);

    // fields_count = 1
    try w.u16v(&buf, a, 1);
    // field: ACC_PUBLIC | ACC_STATIC | ACC_FINAL = 0x0019, name=#5, desc=#6, attrs=1
    try w.u16v(&buf, a, 0x0019);
    try w.u16v(&buf, a, 5);
    try w.u16v(&buf, a, 6);
    try w.u16v(&buf, a, 1);
    //   attr: name=#7 ("ConstantValue"), length=2, constantvalue_index=#8
    try w.u16v(&buf, a, 7);
    try w.u32v(&buf, a, 2);
    try w.u16v(&buf, a, 8);

    // methods_count = 1
    try w.u16v(&buf, a, 1);
    // method: ACC_PUBLIC | ACC_STATIC | ACC_NATIVE = 0x0109, name=#9, desc=#10, attrs=0
    try w.u16v(&buf, a, 0x0109);
    try w.u16v(&buf, a, 9);
    try w.u16v(&buf, a, 10);
    try w.u16v(&buf, a, 0);

    // class attributes_count = 0
    try w.u16v(&buf, a, 0);

    return try buf.toOwnedSlice(a);
}

test "parseClass: minimal fixture (Foo with ConstantValue + native method)" {
    const a = std.testing.allocator;
    const bytes = try buildFixture(a);
    defer a.free(bytes);

    var cf = try parseClass(a, bytes);
    defer cf.deinit();

    try std.testing.expectEqual(@as(u16, 52), cf.major);
    try std.testing.expectEqualStrings("Foo", cf.this_name);
    try std.testing.expect(cf.super_name != null);
    try std.testing.expectEqualStrings("java/lang/Object", cf.super_name.?);
    try std.testing.expectEqual(@as(usize, 0), cf.interfaces.len);

    try std.testing.expect(cf.access.public);
    try std.testing.expect(cf.access.final);
    try std.testing.expect(cf.access.super_or_synchronized);

    try std.testing.expectEqual(@as(usize, 1), cf.fields.len);
    const f = cf.fields[0];
    try std.testing.expectEqualStrings("X", f.name);
    try std.testing.expectEqualStrings("I", f.descriptor);
    try std.testing.expect(f.access.public);
    try std.testing.expect(f.access.static);
    try std.testing.expect(f.access.final);
    try std.testing.expect(f.constant_value != null);
    try std.testing.expectEqual(@as(i32, 42), f.constant_value.?.integer);

    try std.testing.expectEqual(@as(usize, 1), cf.methods.len);
    const m = cf.methods[0];
    try std.testing.expectEqualStrings("bar", m.name);
    try std.testing.expectEqualStrings("(Ljava/lang/String;)I", m.descriptor);
    try std.testing.expect(m.access.public);
    try std.testing.expect(m.access.static);
    try std.testing.expect(m.access.native);
}

test "parseClass: bad magic rejected" {
    const a = std.testing.allocator;
    const bad = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF } ++ ([_]u8{0} ** 16);
    try std.testing.expectError(error.BadMagic, parseClass(a, &bad));
}
