//! `bindgen` CLI: generates a Zig binding tree from `android.jar`.
//!
//! Usage:
//!   bindgen --jar <path> --out <dir> [--sdk <label>] [--filter <prefix>]...

const std = @import("std");
const bindgen = @import("bindgen");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var args_it = init.minimal.args.iterate();
    _ = args_it.next();

    var jar_path: ?[]const u8 = null;
    var out_dir: ?[]const u8 = null;
    var sdk_label: []const u8 = "android-?";
    var android_import: []const u8 = "android";
    var filters: std.ArrayList([]const u8) = .empty;

    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--jar")) {
            jar_path = args_it.next() orelse return usage();
        } else if (std.mem.eql(u8, arg, "--out")) {
            out_dir = args_it.next() orelse return usage();
        } else if (std.mem.eql(u8, arg, "--sdk")) {
            sdk_label = args_it.next() orelse return usage();
        } else if (std.mem.eql(u8, arg, "--android-import")) {
            android_import = args_it.next() orelse return usage();
        } else if (std.mem.eql(u8, arg, "--filter")) {
            const v = args_it.next() orelse return usage();
            try filters.append(gpa, v);
        } else {
            std.debug.print("bindgen: unknown arg '{s}'\n", .{arg});
            return usage();
        }
    }

    const jp = jar_path orelse return usage();
    const od = out_dir orelse return usage();

    var buf: [8192]u8 = undefined;
    var out_writer = std.Io.File.stdout().writerStreaming(init.io, &buf);
    const w = &out_writer.interface;

    try w.print(
        "bindgen: jar={s} out={s} sdk={s} android_import={s} filters={d}\n",
        .{ jp, od, sdk_label, android_import, filters.items.len },
    );
    try w.flush();

    const stats = try bindgen.run(gpa, init.io, .{
        .jar_path = jp,
        .out_dir = od,
        .compile_sdk = sdk_label,
        .android_import = android_import,
        .filter_prefixes = if (filters.items.len == 0) null else filters.items,
    }, w);

    try w.print(
        "\nemitted: {d}\nfiltered: {d}\nerrors: {d}\n",
        .{ stats.emitted, stats.skipped_filter, stats.skipped_errors },
    );
    try w.flush();
    if (stats.skipped_errors != 0) return error.SomeClassesFailed;
}

fn usage() !void {
    std.debug.print(
        \\usage: bindgen --jar <jar> --out <dir> [--sdk <label>] [--android-import <name>] [--filter <prefix>]...
        \\
        \\  --filter may be given multiple times; a class is emitted only
        \\           if its internal name starts with one of the prefixes
        \\           (e.g. --filter android/os --filter android/view).
        \\
    , .{});
    return error.Usage;
}
