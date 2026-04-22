//! JVMS §4.7 attributes.
//!
//! In Phase 1 we only decode `ConstantValue`. Everything else is kept as
//! `{ name_utf8, bytes }` so later phases can decode `Signature`,
//! `RuntimeVisibleAnnotations`, `MethodParameters`, etc., without having
//! to re-walk the class file.

const std = @import("std");
const reader_mod = @import("reader.zig");
const Reader = reader_mod.Reader;
const cp = @import("constant_pool.zig");

pub const Raw = struct {
    name: []const u8,
    bytes: []const u8,
};

pub const ConstantValue = union(enum) {
    integer: i32,
    float: f32,
    long: i64,
    double: f64,
    string: []const u8, // already resolved from the cp
};

pub const ParseError = cp.ParseError || reader_mod.Error || error{BadAttribute};

/// Read `attributes_count` attributes into an arena-backed slice of `Raw`.
pub fn parseList(
    allocator: std.mem.Allocator,
    r: *Reader,
    pool: cp.Pool,
    count: u16,
) ParseError![]Raw {
    const out = try allocator.alloc(Raw, count);
    for (out) |*a| {
        const name_index = try r.readU16();
        const length = try r.readU32();
        const bytes = try r.readSlice(length);
        a.* = .{
            .name = try pool.getUtf8(name_index),
            .bytes = bytes,
        };
    }
    return out;
}

/// Decode a `ConstantValue` attribute (JVMS §4.7.2). `raw.bytes` must be the
/// 2-byte `constantvalue_index`; returns the resolved literal.
pub fn decodeConstantValue(pool: cp.Pool, raw: Raw) ParseError!ConstantValue {
    if (raw.bytes.len != 2) return error.BadAttribute;
    const idx = std.mem.readInt(u16, raw.bytes[0..2], .big);
    const e = try pool.get(idx);
    return switch (e.*) {
        .integer => |v| .{ .integer = v },
        .float => |v| .{ .float = v },
        .long => |v| .{ .long = v },
        .double => |v| .{ .double = v },
        .string => |s| .{ .string = try pool.getUtf8(s.utf8_index) },
        else => error.UnexpectedEntryType,
    };
}

/// Find the first attribute with the given name. Returns null if absent.
pub fn find(attrs: []const Raw, name: []const u8) ?*const Raw {
    for (attrs) |*a| if (std.mem.eql(u8, a.name, name)) return a;
    return null;
}

/// Decode a `Signature` attribute (JVMS §4.7.9) to its referenced Utf8
/// string. Works for class, field, and method Signatures (all three have
/// the same 2-byte `signature_index` payload).
pub fn decodeSignature(pool: cp.Pool, raw: Raw) ParseError![]const u8 {
    if (raw.bytes.len != 2) return error.BadAttribute;
    const idx = std.mem.readInt(u16, raw.bytes[0..2], .big);
    return try pool.getUtf8(idx);
}

/// Convenience: find a `Signature` attribute in `attrs` and decode it,
/// returning null if absent.
pub fn findSignature(pool: cp.Pool, attrs: []const Raw) ParseError!?[]const u8 {
    const raw = find(attrs, "Signature") orelse return null;
    return try decodeSignature(pool, raw.*);
}
