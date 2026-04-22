//! Big-endian, bounds-checked slice reader for Java `.class` files.
//!
//! The class file format (JVMS §4) is big-endian and has no internal padding,
//! so a flat byte slice + an advancing cursor is the cleanest representation.
//! All reads return `error.EndOfStream` if they would read past the end.

const std = @import("std");

pub const Error = error{EndOfStream};

pub const Reader = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn init(buf: []const u8) Reader {
        return .{ .buf = buf };
    }

    pub fn remaining(self: Reader) usize {
        return self.buf.len - self.pos;
    }

    pub fn skip(self: *Reader, n: usize) Error!void {
        if (n > self.remaining()) return error.EndOfStream;
        self.pos += n;
    }

    pub fn readSlice(self: *Reader, n: usize) Error![]const u8 {
        if (n > self.remaining()) return error.EndOfStream;
        const s = self.buf[self.pos .. self.pos + n];
        self.pos += n;
        return s;
    }

    pub fn readU8(self: *Reader) Error!u8 {
        if (self.remaining() < 1) return error.EndOfStream;
        const v = self.buf[self.pos];
        self.pos += 1;
        return v;
    }

    pub fn readU16(self: *Reader) Error!u16 {
        const s = try self.readSlice(2);
        return std.mem.readInt(u16, s[0..2], .big);
    }

    pub fn readU32(self: *Reader) Error!u32 {
        const s = try self.readSlice(4);
        return std.mem.readInt(u32, s[0..4], .big);
    }

    pub fn readU64(self: *Reader) Error!u64 {
        const s = try self.readSlice(8);
        return std.mem.readInt(u64, s[0..8], .big);
    }

    pub fn readI32(self: *Reader) Error!i32 {
        return @bitCast(try self.readU32());
    }

    pub fn readI64(self: *Reader) Error!i64 {
        return @bitCast(try self.readU64());
    }

    pub fn readF32(self: *Reader) Error!f32 {
        return @bitCast(try self.readU32());
    }

    pub fn readF64(self: *Reader) Error!f64 {
        return @bitCast(try self.readU64());
    }
};

test "Reader: big-endian u16/u32 + bounds" {
    var r = Reader.init(&[_]u8{ 0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x01 });
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), try r.readU32());
    try std.testing.expectEqual(@as(u16, 1), try r.readU16());
    try std.testing.expectError(error.EndOfStream, r.readU8());
}

test "Reader: skip + slice" {
    var r = Reader.init(&[_]u8{ 0xAA, 0xBB, 0xCC, 0xDD });
    try r.skip(1);
    const s = try r.readSlice(2);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xBB, 0xCC }, s);
    try std.testing.expectEqual(@as(usize, 1), r.remaining());
}
