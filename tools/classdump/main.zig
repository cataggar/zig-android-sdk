//! Minimal `classdump` — reads a single `.class` file and prints a
//! javap-ish summary, or with `-r JAR` walks a whole JAR and verifies
//! every `.class` entry parses without error.
//!
//! Usage:
//!   classdump <path/to/Class.class>
//!   classdump -r <path/to/foo.jar>

const std = @import("std");
const classfile = @import("classfile");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var args_it = init.minimal.args.iterate();
    _ = args_it.next(); // argv[0]

    const first = args_it.next() orelse {
        std.debug.print("usage: classdump <Class.class> | -r <jar>\n", .{});
        return error.MissingArgument;
    };

    var stdout_buf: [16 * 1024]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writerStreaming(init.io, &stdout_buf);
    const w = &stdout_writer.interface;

    if (std.mem.eql(u8, first, "-r")) {
        const jar_path = args_it.next() orelse {
            std.debug.print("usage: classdump -r <jar>\n", .{});
            return error.MissingArgument;
        };
        try dumpJar(gpa, init.io, jar_path, w);
    } else {
        try dumpClass(gpa, init.io, first, w);
    }

    try w.flush();
}

fn dumpClass(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    w: *std.Io.Writer,
) !void {
    const cwd = std.Io.Dir.cwd();
    const bytes = try cwd.readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);

    var cf = try classfile.parseClass(gpa, bytes);
    defer cf.deinit();

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
}

const JarStats = struct {
    ok: usize = 0,
    failed: usize = 0,
    sigs: usize = 0,
    sigs_failed: usize = 0,
    anns: usize = 0,
    anns_failed: usize = 0,
    params: usize = 0,
    params_failed: usize = 0,
    requires_api: usize = 0,
    w: *std.Io.Writer,
    gpa: std.mem.Allocator,
};

fn tryDecodeAnns(stats: *JarStats, a: std.mem.Allocator, pool: classfile.cp.Pool, attrs: []const classfile.attribute.Raw, where: []const u8, entry_name: []const u8) !void {
    inline for (&[_][]const u8{ "RuntimeVisibleAnnotations", "RuntimeInvisibleAnnotations" }) |aname| {
        if (classfile.attribute.find(attrs, aname)) |raw| {
            _ = classfile.annotation.decodeAnnotations(a, pool, raw.*) catch |err| {
                stats.anns_failed += 1;
                try stats.w.print("ANN FAIL {s}.{s} ({s}): {s}\n", .{ entry_name, where, aname, @errorName(err) });
                return;
            };
            stats.anns += 1;
        }
    }
}

fn jarCallback(stats: *JarStats, entry: classfile.jar.Entry) anyerror!void {
    var cf = classfile.parseClass(stats.gpa, entry.bytes) catch |err| {
        stats.failed += 1;
        try stats.w.print("FAIL  {s}: {s}\n", .{ entry.name, @errorName(err) });
        return;
    };
    defer cf.deinit();
    stats.ok += 1;

    var arena = std.heap.ArenaAllocator.init(stats.gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // Signatures ------------------------------------------------------------
    if (cf.signature) |s| {
        _ = classfile.signature.parseClass(a, s) catch |err| {
            stats.sigs_failed += 1;
            try stats.w.print("SIG-CLASS FAIL {s}: {s}  sig={s}\n", .{ entry.name, @errorName(err), s });
        };
        stats.sigs += 1;
    }
    for (cf.fields) |f| if (f.signature) |s| {
        _ = classfile.signature.parseField(a, s) catch |err| {
            stats.sigs_failed += 1;
            try stats.w.print("SIG-FIELD FAIL {s}.{s}: {s}  sig={s}\n", .{ entry.name, f.name, @errorName(err), s });
        };
        stats.sigs += 1;
    };
    for (cf.methods) |m| if (m.signature) |s| {
        _ = classfile.signature.parseMethod(a, s) catch |err| {
            stats.sigs_failed += 1;
            try stats.w.print("SIG-METHOD FAIL {s}.{s}: {s}  sig={s}\n", .{ entry.name, m.name, @errorName(err), s });
        };
        stats.sigs += 1;
    };

    // Annotations -----------------------------------------------------------
    try tryDecodeAnns(stats, a, cf.pool, cf.attributes_raw, "<class>", entry.name);
    for (cf.fields) |f| try tryDecodeAnns(stats, a, cf.pool, f.attributes_raw, f.name, entry.name);
    for (cf.methods) |m| {
        try tryDecodeAnns(stats, a, cf.pool, m.attributes_raw, m.name, entry.name);

        // MethodParameters
        if (classfile.attribute.find(m.attributes_raw, "MethodParameters")) |raw| {
            _ = classfile.annotation.decodeMethodParameters(a, cf.pool, raw.*) catch |err| {
                stats.params_failed += 1;
                try stats.w.print("PARAM FAIL {s}.{s}: {s}\n", .{ entry.name, m.name, @errorName(err) });
            };
            stats.params += 1;
        }

        // Parameter annotations
        inline for (&[_][]const u8{ "RuntimeVisibleParameterAnnotations", "RuntimeInvisibleParameterAnnotations" }) |pname| {
            if (classfile.attribute.find(m.attributes_raw, pname)) |raw| {
                _ = classfile.annotation.decodeParameterAnnotations(a, cf.pool, raw.*) catch |err| {
                    stats.anns_failed += 1;
                    try stats.w.print("PARAM-ANN FAIL {s}.{s}: {s}\n", .{ entry.name, m.name, @errorName(err) });
                };
                stats.anns += 1;
            }
        }

        if (try classfile.annotation.requiresApi(a, cf.pool, m.attributes_raw)) |_| {
            stats.requires_api += 1;
        }
    }

    if ((stats.ok & 0x3ff) == 0) {
        try stats.w.print("... {d} classes parsed\n", .{stats.ok});
        try stats.w.flush();
    }
}

fn dumpJar(
    gpa: std.mem.Allocator,
    io: std.Io,
    jar_path: []const u8,
    w: *std.Io.Writer,
) !void {
    var stats = JarStats{ .w = w, .gpa = gpa };
    try classfile.jar.walkClasses(gpa, io, jar_path, &stats, jarCallback);
    try w.print(
        "\nparsed {d} classes ({d} failed)\n  signatures: {d} ({d} failed)\n  annotation lists: {d} ({d} failed)\n  MethodParameters: {d} ({d} failed)\n  @RequiresApi method hits: {d}\n",
        .{ stats.ok, stats.failed, stats.sigs, stats.sigs_failed, stats.anns, stats.anns_failed, stats.params, stats.params_failed, stats.requires_api },
    );
    if (stats.failed != 0 or stats.sigs_failed != 0 or stats.anns_failed != 0 or stats.params_failed != 0) return error.SomeClassesFailed;
}
