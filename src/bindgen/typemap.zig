//! Translate JNI field/method descriptors to source-form Zig type
//! expressions used by the emitter. Pure text transformation — we don't
//! touch the actual Zig type system here.
//!
//! Input is the raw descriptor from `Field.descriptor` / `Method.descriptor`
//! (which *is* JNI wire format since §4.3.2 descriptors match the JNI spec).
//!
//! Arrays are **erased to `jni.jobject`** in v1 — rubber-duck recommended
//! keeping v1 small, and typed arrays need a helper layer we haven't
//! built yet.

const std = @import("std");

pub const Parsed = struct {
    params: []const []const u8,
    ret: []const u8,
    /// Class internal-names (e.g. `"android/os/VibrationEffect"`) referenced
    /// by params or return. The emitter imports these.
    class_refs: []const []const u8,
};

pub const Error = error{
    BadDescriptor,
} || std.mem.Allocator.Error;

/// Parse a method descriptor `(args...)ret` into Zig source-text.
///
/// `class_alias_for(ctx, internal_name)` returns the Zig alias the
/// caller uses to refer to a given class (e.g. `"VibrationEffect_c"`);
/// the caller is expected to emit a matching
/// `const VibrationEffect_c = @import("...")` line.
pub fn parseMethod(
    allocator: std.mem.Allocator,
    descriptor: []const u8,
    context: anytype,
    comptime class_alias_for: fn (ctx: @TypeOf(context), internal_name: []const u8) anyerror![]const u8,
) Error!Parsed {
    if (descriptor.len < 3 or descriptor[0] != '(') return Error.BadDescriptor;
    var i: usize = 1;

    var params: std.ArrayList([]const u8) = .empty;
    var refs: std.ArrayList([]const u8) = .empty;

    while (i < descriptor.len and descriptor[i] != ')') {
        const t = typeAt(allocator, descriptor, &i, context, class_alias_for, &refs) catch |err| {
            return mapErr(err);
        };
        try params.append(allocator, t);
    }
    if (i >= descriptor.len or descriptor[i] != ')') return Error.BadDescriptor;
    i += 1;

    const ret = typeAt(allocator, descriptor, &i, context, class_alias_for, &refs) catch |err| {
        return mapErr(err);
    };
    if (i != descriptor.len) return Error.BadDescriptor;

    return .{
        .params = try params.toOwnedSlice(allocator),
        .ret = ret,
        .class_refs = try refs.toOwnedSlice(allocator),
    };
}

pub fn parseField(
    allocator: std.mem.Allocator,
    descriptor: []const u8,
    context: anytype,
    comptime class_alias_for: fn (ctx: @TypeOf(context), internal_name: []const u8) anyerror![]const u8,
) Error!struct { ty: []const u8, class_refs: []const []const u8 } {
    var refs: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    const ty = typeAt(allocator, descriptor, &i, context, class_alias_for, &refs) catch |err| {
        return mapErr(err);
    };
    if (i != descriptor.len) return Error.BadDescriptor;
    return .{ .ty = ty, .class_refs = try refs.toOwnedSlice(allocator) };
}

fn mapErr(e: anyerror) Error {
    return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.BadDescriptor => error.BadDescriptor,
        else => error.BadDescriptor,
    };
}

fn typeAt(
    allocator: std.mem.Allocator,
    src: []const u8,
    i: *usize,
    context: anytype,
    comptime class_alias_for: fn (ctx: @TypeOf(context), internal_name: []const u8) anyerror![]const u8,
    refs: *std.ArrayList([]const u8),
) !([]const u8) {
    if (i.* >= src.len) return error.BadDescriptor;
    const c = src[i.*];
    i.* += 1;
    return switch (c) {
        'V' => "void",
        'Z' => "bool",
        'B' => "i8",
        'C' => "u16",
        'S' => "i16",
        'I' => "i32",
        'J' => "i64",
        'F' => "f32",
        'D' => "f64",
        'L' => blk: {
            const start = i.*;
            while (i.* < src.len and src[i.*] != ';') : (i.* += 1) {}
            if (i.* >= src.len) return error.BadDescriptor;
            const name = src[start..i.*];
            i.* += 1;
            if (std.mem.eql(u8, name, "java/lang/String")) break :blk "jni.String";
            try refs.append(allocator, name);
            const alias = class_alias_for(context, name) catch return error.BadDescriptor;
            break :blk try std.fmt.allocPrint(allocator, "{s}.Ref", .{alias});
        },
        '[' => blk: {
            try skipType(src, i);
            break :blk "jni.jobject";
        },
        else => return error.BadDescriptor,
    };
}

fn skipType(src: []const u8, i: *usize) !void {
    if (i.* >= src.len) return error.BadDescriptor;
    const c = src[i.*];
    i.* += 1;
    switch (c) {
        'V', 'Z', 'B', 'C', 'S', 'I', 'J', 'F', 'D' => {},
        'L' => {
            while (i.* < src.len and src[i.*] != ';') : (i.* += 1) {}
            if (i.* >= src.len) return error.BadDescriptor;
            i.* += 1;
        },
        '[' => try skipType(src, i),
        else => return error.BadDescriptor,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

const TestCtx = struct {
    arena: std.mem.Allocator,
};

fn testAlias(ctx: *TestCtx, name: []const u8) anyerror![]const u8 {
    const last_slash = std.mem.lastIndexOfScalar(u8, name, '/') orelse 0;
    const simple = if (last_slash == 0) name else name[last_slash + 1 ..];
    return try std.fmt.allocPrint(ctx.arena, "{s}_c", .{simple});
}

test "parseMethod: primitives" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var ctx = TestCtx{ .arena = arena.allocator() };
    const p = try parseMethod(arena.allocator(), "(JI)V", &ctx, testAlias);
    try testing.expectEqual(@as(usize, 2), p.params.len);
    try testing.expectEqualStrings("i64", p.params[0]);
    try testing.expectEqualStrings("i32", p.params[1]);
    try testing.expectEqualStrings("void", p.ret);
    try testing.expectEqual(@as(usize, 0), p.class_refs.len);
}

test "parseMethod: String + user class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var ctx = TestCtx{ .arena = arena.allocator() };
    const p = try parseMethod(
        arena.allocator(),
        "(Ljava/lang/String;)Landroid/os/VibrationEffect;",
        &ctx,
        testAlias,
    );
    try testing.expectEqualStrings("jni.String", p.params[0]);
    try testing.expectEqualStrings("VibrationEffect_c.Ref", p.ret);
    try testing.expectEqual(@as(usize, 1), p.class_refs.len);
    try testing.expectEqualStrings("android/os/VibrationEffect", p.class_refs[0]);
}

test "parseMethod: arrays erased" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var ctx = TestCtx{ .arena = arena.allocator() };
    const p = try parseMethod(arena.allocator(), "([B[[I)[Ljava/lang/String;", &ctx, testAlias);
    try testing.expectEqualStrings("jni.jobject", p.params[0]);
    try testing.expectEqualStrings("jni.jobject", p.params[1]);
    try testing.expectEqualStrings("jni.jobject", p.ret);
}

test "parseField: scalar and class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var ctx = TestCtx{ .arena = arena.allocator() };
    const f1 = try parseField(arena.allocator(), "I", &ctx, testAlias);
    try testing.expectEqualStrings("i32", f1.ty);
    const f2 = try parseField(arena.allocator(), "Landroid/os/Vibrator;", &ctx, testAlias);
    try testing.expectEqualStrings("Vibrator_c.Ref", f2.ty);
}

test "parseMethod: malformed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var ctx = TestCtx{ .arena = arena.allocator() };
    try testing.expectError(Error.BadDescriptor, parseMethod(arena.allocator(), "JI)V", &ctx, testAlias));
    try testing.expectError(Error.BadDescriptor, parseMethod(arena.allocator(), "(Ljava/lang/String", &ctx, testAlias));
    try testing.expectError(Error.BadDescriptor, parseMethod(arena.allocator(), "()X", &ctx, testAlias));
}
