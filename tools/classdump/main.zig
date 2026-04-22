//! Minimal `classdump` — reads a single `.class` file and prints a
//! javap-ish summary. Used to smoke-test the parser against real class
//! files from `android.jar` without a JAR walker yet.
//!
//! Usage: classdump <path/to/Class.class>

const std = @import("std");
const classfile = @import("classfile");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var args_it = init.minimal.args.iterate();
    _ = args_it.next(); // argv[0]

    const path = args_it.next() orelse {
        std.debug.print("usage: classdump <Class.class>\n", .{});
        return error.MissingArgument;
    };

    const cwd = std.Io.Dir.cwd();
    const bytes = try cwd.readFileAlloc(init.io, path, gpa, .unlimited);
    defer gpa.free(bytes);

    var cf = try classfile.parseClass(gpa, bytes);
    defer cf.deinit();

    var stdout_buf: [4096]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writerStreaming(init.io, &stdout_buf);
    const w = &stdout_writer.interface;

    try w.print("class {s}", .{cf.this_name});
    if (cf.super_name) |sup| try w.print(" extends {s}", .{sup});
    if (cf.interfaces.len > 0) {
        try w.writeAll(" implements");
        for (cf.interfaces, 0..) |iface, i| {
            try w.print("{s} {s}", .{ if (i == 0) "" else ",", iface });
        }
    }
    try w.print(" (major={d}, {d} fields, {d} methods, {d} class-attrs)\n", .{
        cf.major, cf.fields.len, cf.methods.len, cf.attributes_raw.len,
    });

    for (cf.fields) |f| {
        try w.print("  field {s}: {s}", .{ f.name, f.descriptor });
        if (f.constant_value) |cv| try w.print(" = {any}", .{cv});
        try w.writeAll("\n");
    }
    for (cf.methods) |m| {
        try w.print("  method {s}{s}\n", .{ m.name, m.descriptor });
    }

    try w.flush();
}
