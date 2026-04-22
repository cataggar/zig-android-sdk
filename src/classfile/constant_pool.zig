//! JVMS §4.4 constant pool.
//!
//! The pool is 1-indexed. `Long` and `Double` entries consume two slots
//! (the slot after them is unusable) — a JVM 1.0 design bug that the
//! spec has preserved forever. We represent the unused slot as `.unused`.

const std = @import("std");
const reader_mod = @import("reader.zig");
const Reader = reader_mod.Reader;

pub const Tag = enum(u8) {
    utf8 = 1,
    integer = 3,
    float = 4,
    long = 5,
    double = 6,
    class = 7,
    string = 8,
    fieldref = 9,
    methodref = 10,
    interface_methodref = 11,
    name_and_type = 12,
    method_handle = 15,
    method_type = 16,
    dynamic = 17,
    invoke_dynamic = 18,
    module = 19,
    package = 20,
    _,
};

pub const Entry = union(enum) {
    unused, // placeholder for the slot after Long/Double
    utf8: []const u8, // raw bytes (modified UTF-8); ASCII subset is identical to UTF-8
    integer: i32,
    float: f32,
    long: i64,
    double: f64,
    class: struct { name_index: u16 },
    string: struct { utf8_index: u16 },
    fieldref: struct { class_index: u16, name_and_type_index: u16 },
    methodref: struct { class_index: u16, name_and_type_index: u16 },
    interface_methodref: struct { class_index: u16, name_and_type_index: u16 },
    name_and_type: struct { name_index: u16, descriptor_index: u16 },
    method_handle: struct { reference_kind: u8, reference_index: u16 },
    method_type: struct { descriptor_index: u16 },
    dynamic: struct { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
    invoke_dynamic: struct { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
    module: struct { name_index: u16 },
    package: struct { name_index: u16 },
    unknown: struct { tag: u8 },
};

pub const ParseError = error{
    BadConstantPoolIndex,
    BadConstantPoolTag,
    Utf8TooLong,
    UnexpectedEntryType,
} || reader_mod.Error || std.mem.Allocator.Error;

pub const Pool = struct {
    /// Indexed 1..count-1. Slot 0 is `.unused` so indexing is natural.
    entries: []Entry,

    pub fn get(self: Pool, idx: u16) ParseError!*const Entry {
        if (idx == 0 or idx >= self.entries.len) return error.BadConstantPoolIndex;
        const e = &self.entries[idx];
        if (e.* == .unused) return error.BadConstantPoolIndex;
        return e;
    }

    pub fn getUtf8(self: Pool, idx: u16) ParseError![]const u8 {
        const e = try self.get(idx);
        return switch (e.*) {
            .utf8 => |s| s,
            else => error.UnexpectedEntryType,
        };
    }

    /// Returns the internal (slash-separated) name of a CONSTANT_Class entry.
    pub fn getClassName(self: Pool, idx: u16) ParseError![]const u8 {
        const e = try self.get(idx);
        return switch (e.*) {
            .class => |c| self.getUtf8(c.name_index),
            else => error.UnexpectedEntryType,
        };
    }
};

/// Parse `count` entries (the `constant_pool_count` field from the header;
/// the real number of slots is `count`, with valid indices 1..count-1).
/// Allocated with `allocator`. Caller owns the returned `entries` slice;
/// the Utf8 byte slices alias `source_bytes`, so keep `source_bytes` alive.
pub fn parse(
    allocator: std.mem.Allocator,
    r: *Reader,
    count: u16,
) ParseError!Pool {
    const entries = try allocator.alloc(Entry, count);
    @memset(entries, .unused);

    var i: u16 = 1;
    while (i < count) {
        const tag_byte = try r.readU8();
        const tag: Tag = @enumFromInt(tag_byte);
        entries[i] = switch (tag) {
            .utf8 => blk: {
                const len = try r.readU16();
                const bytes = try r.readSlice(len);
                break :blk .{ .utf8 = bytes };
            },
            .integer => .{ .integer = try r.readI32() },
            .float => .{ .float = try r.readF32() },
            .long => .{ .long = try r.readI64() },
            .double => .{ .double = try r.readF64() },
            .class => .{ .class = .{ .name_index = try r.readU16() } },
            .string => .{ .string = .{ .utf8_index = try r.readU16() } },
            .fieldref => .{ .fieldref = .{
                .class_index = try r.readU16(),
                .name_and_type_index = try r.readU16(),
            } },
            .methodref => .{ .methodref = .{
                .class_index = try r.readU16(),
                .name_and_type_index = try r.readU16(),
            } },
            .interface_methodref => .{ .interface_methodref = .{
                .class_index = try r.readU16(),
                .name_and_type_index = try r.readU16(),
            } },
            .name_and_type => .{ .name_and_type = .{
                .name_index = try r.readU16(),
                .descriptor_index = try r.readU16(),
            } },
            .method_handle => .{ .method_handle = .{
                .reference_kind = try r.readU8(),
                .reference_index = try r.readU16(),
            } },
            .method_type => .{ .method_type = .{ .descriptor_index = try r.readU16() } },
            .dynamic => .{ .dynamic = .{
                .bootstrap_method_attr_index = try r.readU16(),
                .name_and_type_index = try r.readU16(),
            } },
            .invoke_dynamic => .{ .invoke_dynamic = .{
                .bootstrap_method_attr_index = try r.readU16(),
                .name_and_type_index = try r.readU16(),
            } },
            .module => .{ .module = .{ .name_index = try r.readU16() } },
            .package => .{ .package = .{ .name_index = try r.readU16() } },
            _ => return error.BadConstantPoolTag,
        };

        // JVMS §4.4.5: Long/Double take two slots.
        i += switch (tag) {
            .long, .double => 2,
            else => 1,
        };
    }

    return .{ .entries = entries };
}
