//! JVMS §4.7.16–§4.7.24 annotation + MethodParameters attributes.
//!
//! We decode the full tree so bindgen can inspect arbitrary annotations,
//! but the primary consumers (@Deprecated, @RequiresApi, @Nullable,
//! @NonNull, @FunctionalInterface) just need presence + scalar args.
//!
//! All slices alias either the input bytes or the caller's arena (for
//! nested arrays / nested annotations / parameter lists).

const std = @import("std");
const reader_mod = @import("reader.zig");
const Reader = reader_mod.Reader;
const cp = @import("constant_pool.zig");
const attribute = @import("attribute.zig");

pub const ParseError = attribute.ParseError || error{BadAnnotation};

pub const Annotation = struct {
    /// Field/type descriptor of the annotation type,
    /// e.g. `"Ljava/lang/Deprecated;"`.
    type_descriptor: []const u8,
    elements: []ElementPair,
};

pub const ElementPair = struct {
    name: []const u8,
    value: ElementValue,
};

/// JVMS §4.7.16.1 `element_value`.
pub const ElementValue = union(enum) {
    /// Primitive constant (B/C/D/F/I/J/S/Z) resolved from the constant pool.
    byte: i32,
    char: i32,
    short: i32,
    boolean: i32,
    int: i32,
    long: i64,
    float: f32,
    double: f64,
    /// `s` tag — UTF-8 string constant.
    string: []const u8,
    /// `e` tag — enum constant reference.
    enum_const: EnumConstant,
    /// `c` tag — class literal; the descriptor form of the class, e.g.
    /// `"Ljava/lang/String;"` or `"I"` or `"[Ljava/lang/Object;"`.
    class: []const u8,
    /// `@` tag — nested annotation.
    annotation: Annotation,
    /// `[` tag — array of element values (all same tag in well-formed jars).
    array: []ElementValue,
};

pub const EnumConstant = struct {
    /// Field descriptor for the enum type, e.g. `"Landroid/view/View$Foo;"`.
    type_descriptor: []const u8,
    /// Simple name of the enum constant.
    const_name: []const u8,
};

pub const MethodParameter = struct {
    /// null if the entry uses `name_index = 0` (the JVMS "unnamed" sentinel).
    name: ?[]const u8,
    access_flags: u16,
};

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/// Decode a `RuntimeVisibleAnnotations` or `RuntimeInvisibleAnnotations`
/// attribute body into a slice of annotations.
pub fn decodeAnnotations(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    raw: attribute.Raw,
) ParseError![]Annotation {
    var r = Reader.init(raw.bytes);
    return try readAnnotationList(allocator, pool, &r);
}

/// Decode a `RuntimeVisibleParameterAnnotations` /
/// `RuntimeInvisibleParameterAnnotations` body: one annotation list per
/// parameter, in declaration order.
pub fn decodeParameterAnnotations(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    raw: attribute.Raw,
) ParseError![][]Annotation {
    var r = Reader.init(raw.bytes);
    const n = try r.readU8();
    const out = try allocator.alloc([]Annotation, n);
    for (out) |*slot| slot.* = try readAnnotationList(allocator, pool, &r);
    return out;
}

/// Decode a `MethodParameters` attribute (JVMS §4.7.24).
pub fn decodeMethodParameters(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    raw: attribute.Raw,
) ParseError![]MethodParameter {
    var r = Reader.init(raw.bytes);
    const n = try r.readU8();
    const out = try allocator.alloc(MethodParameter, n);
    for (out) |*p| {
        const name_idx = try r.readU16();
        const flags = try r.readU16();
        p.* = .{
            .name = if (name_idx == 0) null else try pool.getUtf8(name_idx),
            .access_flags = flags,
        };
    }
    return out;
}

// ---------------------------------------------------------------------------
// Presence helpers (bindgen's hot path)
// ---------------------------------------------------------------------------

/// True iff any annotation in `attrs` has the given type descriptor
/// (e.g. `"Ljava/lang/Deprecated;"`). Checks both visible and invisible
/// annotation lists.
pub fn hasAnnotation(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    attrs: []const attribute.Raw,
    type_descriptor: []const u8,
) ParseError!bool {
    inline for (&[_][]const u8{ "RuntimeVisibleAnnotations", "RuntimeInvisibleAnnotations" }) |aname| {
        if (attribute.find(attrs, aname)) |raw| {
            const list = try decodeAnnotations(allocator, pool, raw.*);
            for (list) |ann| {
                if (std.mem.eql(u8, ann.type_descriptor, type_descriptor)) return true;
            }
        }
    }
    return false;
}

/// Extract the first matching annotation (visible, then invisible) with
/// the given type descriptor, or null if absent.
pub fn findAnnotation(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    attrs: []const attribute.Raw,
    type_descriptor: []const u8,
) ParseError!?Annotation {
    inline for (&[_][]const u8{ "RuntimeVisibleAnnotations", "RuntimeInvisibleAnnotations" }) |aname| {
        if (attribute.find(attrs, aname)) |raw| {
            const list = try decodeAnnotations(allocator, pool, raw.*);
            for (list) |ann| {
                if (std.mem.eql(u8, ann.type_descriptor, type_descriptor)) return ann;
            }
        }
    }
    return null;
}

/// Get a `@RequiresApi` minimum SDK int, if present on `attrs`. Checks
/// both the `android.annotation.*` and `androidx.annotation.*` flavors.
pub fn requiresApi(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    attrs: []const attribute.Raw,
) ParseError!?i32 {
    inline for (&[_][]const u8{
        "Landroid/annotation/RequiresApi;",
        "Landroidx/annotation/RequiresApi;",
    }) |td| {
        if (try findAnnotation(allocator, pool, attrs, td)) |ann| {
            // @RequiresApi has two aliases: `value` and `api`; both are int.
            for (ann.elements) |el| {
                if ((std.mem.eql(u8, el.name, "value") or std.mem.eql(u8, el.name, "api")) and el.value == .int) {
                    return el.value.int;
                }
            }
        }
    }
    return null;
}

/// Nullability inferred from Android's annotation set. Maps
/// `@NonNull`/`@RecentlyNonNull` → `non_null` and
/// `@Nullable`/`@RecentlyNullable` → `nullable`.
pub const Nullability = enum { non_null, nullable, unspecified };

pub fn nullability(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    attrs: []const attribute.Raw,
) ParseError!Nullability {
    inline for (&[_][]const u8{
        "Landroid/annotation/NonNull;",
        "Landroidx/annotation/NonNull;",
        "Landroidx/annotation/RecentlyNonNull;",
    }) |td| {
        if (try hasAnnotation(allocator, pool, attrs, td)) return .non_null;
    }
    inline for (&[_][]const u8{
        "Landroid/annotation/Nullable;",
        "Landroidx/annotation/Nullable;",
        "Landroidx/annotation/RecentlyNullable;",
    }) |td| {
        if (try hasAnnotation(allocator, pool, attrs, td)) return .nullable;
    }
    return .unspecified;
}

/// True iff `@Deprecated` is present (Java-language annotation; the
/// `ACC_DEPRECATED` access flag is a separate, weaker signal).
pub fn isDeprecated(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    attrs: []const attribute.Raw,
) ParseError!bool {
    return try hasAnnotation(allocator, pool, attrs, "Ljava/lang/Deprecated;");
}

// ---------------------------------------------------------------------------
// Internal readers
// ---------------------------------------------------------------------------

fn readAnnotationList(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    r: *Reader,
) ParseError![]Annotation {
    const n = try r.readU16();
    const out = try allocator.alloc(Annotation, n);
    for (out) |*a| a.* = try readAnnotation(allocator, pool, r);
    return out;
}

fn readAnnotation(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    r: *Reader,
) ParseError!Annotation {
    const type_idx = try r.readU16();
    const npairs = try r.readU16();
    const pairs = try allocator.alloc(ElementPair, npairs);
    for (pairs) |*p| {
        const name_idx = try r.readU16();
        p.* = .{
            .name = try pool.getUtf8(name_idx),
            .value = try readElementValue(allocator, pool, r),
        };
    }
    return .{
        .type_descriptor = try pool.getUtf8(type_idx),
        .elements = pairs,
    };
}

fn readElementValue(
    allocator: std.mem.Allocator,
    pool: cp.Pool,
    r: *Reader,
) ParseError!ElementValue {
    const tag = try r.readU8();
    return switch (tag) {
        'B', 'C', 'I', 'S', 'Z' => blk: {
            const idx = try r.readU16();
            const e = try pool.get(idx);
            if (e.* != .integer) return error.BadAnnotation;
            const v = e.integer;
            break :blk switch (tag) {
                'B' => .{ .byte = v },
                'C' => .{ .char = v },
                'I' => .{ .int = v },
                'S' => .{ .short = v },
                'Z' => .{ .boolean = v },
                else => unreachable,
            };
        },
        'J' => blk: {
            const idx = try r.readU16();
            const e = try pool.get(idx);
            if (e.* != .long) return error.BadAnnotation;
            break :blk .{ .long = e.long };
        },
        'F' => blk: {
            const idx = try r.readU16();
            const e = try pool.get(idx);
            if (e.* != .float) return error.BadAnnotation;
            break :blk .{ .float = e.float };
        },
        'D' => blk: {
            const idx = try r.readU16();
            const e = try pool.get(idx);
            if (e.* != .double) return error.BadAnnotation;
            break :blk .{ .double = e.double };
        },
        's' => .{ .string = try pool.getUtf8(try r.readU16()) },
        'e' => blk: {
            const type_idx = try r.readU16();
            const const_idx = try r.readU16();
            break :blk .{ .enum_const = .{
                .type_descriptor = try pool.getUtf8(type_idx),
                .const_name = try pool.getUtf8(const_idx),
            } };
        },
        'c' => .{ .class = try pool.getUtf8(try r.readU16()) },
        '@' => .{ .annotation = try readAnnotation(allocator, pool, r) },
        '[' => blk: {
            const n = try r.readU16();
            const arr = try allocator.alloc(ElementValue, n);
            for (arr) |*slot| slot.* = try readElementValue(allocator, pool, r);
            break :blk .{ .array = arr };
        },
        else => error.BadAnnotation,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

// Build a synthetic attribute body for testing. We build a tiny constant
// pool inline with the bytes it needs.
fn buildPool(a: std.mem.Allocator, entries: []const cp.Entry) !cp.Pool {
    const full = try a.alloc(cp.Entry, entries.len + 1);
    full[0] = .unused;
    @memcpy(full[1..], entries);
    return .{ .entries = full };
}

test "decodeMethodParameters: named + unnamed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const pool = try buildPool(a, &.{
        .{ .utf8 = "x" },
        .{ .utf8 = "y" },
    });

    //   parameters_count = 3; [name=1 flags=0x10] [name=0 flags=0] [name=2 flags=0]
    var buf: [1 + 3 * 4]u8 = undefined;
    buf[0] = 3;
    std.mem.writeInt(u16, buf[1..3], 1, .big);
    std.mem.writeInt(u16, buf[3..5], 0x0010, .big);
    std.mem.writeInt(u16, buf[5..7], 0, .big);
    std.mem.writeInt(u16, buf[7..9], 0, .big);
    std.mem.writeInt(u16, buf[9..11], 2, .big);
    std.mem.writeInt(u16, buf[11..13], 0, .big);

    const params = try decodeMethodParameters(a, pool, .{ .name = "MethodParameters", .bytes = &buf });
    try testing.expectEqual(@as(usize, 3), params.len);
    try testing.expectEqualStrings("x", params[0].name.?);
    try testing.expectEqual(@as(u16, 0x0010), params[0].access_flags);
    try testing.expect(params[1].name == null);
    try testing.expectEqualStrings("y", params[2].name.?);
}

test "decodeAnnotations: @Deprecated (no elements) and @RequiresApi(int)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // cp:
    //   1 Utf8 "Ljava/lang/Deprecated;"
    //   2 Utf8 "Landroid/annotation/RequiresApi;"
    //   3 Utf8 "value"
    //   4 Integer 29
    const pool = try buildPool(a, &.{
        .{ .utf8 = "Ljava/lang/Deprecated;" },
        .{ .utf8 = "Landroid/annotation/RequiresApi;" },
        .{ .utf8 = "value" },
        .{ .integer = 29 },
    });

    // num_annotations=2
    //   ann1 { type=1, 0 pairs }
    //   ann2 { type=2, 1 pair { name=3, 'I' const=4 } }
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    try list.appendNTimes(a, 0, 2);
    std.mem.writeInt(u16, list.items[0..2], 2, .big);
    // ann1
    try list.appendSlice(a, &[_]u8{ 0, 1, 0, 0 });
    // ann2
    try list.appendSlice(a, &[_]u8{ 0, 2, 0, 1, 0, 3, 'I', 0, 4 });

    const anns = try decodeAnnotations(a, pool, .{ .name = "RVA", .bytes = list.items });
    try testing.expectEqual(@as(usize, 2), anns.len);
    try testing.expectEqualStrings("Ljava/lang/Deprecated;", anns[0].type_descriptor);
    try testing.expectEqual(@as(usize, 0), anns[0].elements.len);
    try testing.expectEqualStrings("Landroid/annotation/RequiresApi;", anns[1].type_descriptor);
    try testing.expectEqual(@as(i32, 29), anns[1].elements[0].value.int);

    const attrs = [_]attribute.Raw{.{ .name = "RuntimeVisibleAnnotations", .bytes = list.items }};
    try testing.expect(try hasAnnotation(a, pool, &attrs, "Ljava/lang/Deprecated;"));
    try testing.expect(!try hasAnnotation(a, pool, &attrs, "Ljava/lang/Override;"));
    try testing.expectEqual(@as(?i32, 29), try requiresApi(a, pool, &attrs));
}
