//! Binding generator root: walks a JAR, filters by package prefix, and
//! emits one Zig file per class under an output directory.

const std = @import("std");
const classfile = @import("classfile");

pub const emit = @import("emit.zig");
pub const typemap = @import("typemap.zig");
pub const mangle = @import("mangle.zig");

pub const RunOptions = struct {
    jar_path: []const u8,
    out_dir: []const u8,
    compile_sdk: []const u8 = "android-?",
    android_import: []const u8 = "android",
    filter_prefixes: ?[]const []const u8 = null,
};

pub const Stats = struct {
    emitted: usize = 0,
    skipped_filter: usize = 0,
    skipped_errors: usize = 0,
};

const Ctx = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    opts: RunOptions,
    stats: Stats = .{},
    log: *std.Io.Writer,
};

fn classCb(ctx: *Ctx, entry: classfile.jar.Entry) anyerror!void {
    var cf = classfile.parseClass(ctx.gpa, entry.bytes) catch |err| {
        ctx.stats.skipped_errors += 1;
        try ctx.log.print("  parse fail {s}: {s}\n", .{ entry.name, @errorName(err) });
        return;
    };
    defer cf.deinit();

    const opts = emit.Options{
        .compile_sdk = ctx.opts.compile_sdk,
        .android_import = ctx.opts.android_import,
        .filter_prefixes = ctx.opts.filter_prefixes,
    };
    if (!passesFilter(cf.this_name, ctx.opts.filter_prefixes)) {
        ctx.stats.skipped_filter += 1;
        return;
    }

    emit.emitClass(ctx.gpa, ctx.io, ctx.opts.out_dir, &cf, opts) catch |err| {
        ctx.stats.skipped_errors += 1;
        try ctx.log.print("  emit fail {s}: {s}\n", .{ cf.this_name, @errorName(err) });
        return;
    };
    ctx.stats.emitted += 1;
    if ((ctx.stats.emitted & 0xff) == 0) {
        try ctx.log.print("  ... {d} classes emitted\n", .{ctx.stats.emitted});
        try ctx.log.flush();
    }
}

fn passesFilter(name: []const u8, filter: ?[]const []const u8) bool {
    const f = filter orelse return true;
    for (f) |p| if (std.mem.startsWith(u8, name, p)) return true;
    return false;
}

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    opts: RunOptions,
    log: *std.Io.Writer,
) !Stats {
    var ctx = Ctx{ .gpa = gpa, .io = io, .opts = opts, .log = log };
    try classfile.jar.walkClasses(gpa, io, opts.jar_path, &ctx, classCb);
    return ctx.stats;
}
