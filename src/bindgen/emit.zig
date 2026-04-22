//! Per-class emitter. Takes a parsed `ClassFile` + a classpath lookup
//! and writes one `.zig` file containing typed wrappers over the existing
//! `jni.call` / `jni.callStatic` helpers.
//!
//! Design choices (per rubber-duck review):
//!   * One file per class; inner classes become their own files.
//!   * Refs are nullable in v1 — we return `jobject` / `ClassRef` (nullable
//!     handle); we do NOT encode `@NonNull` in the type system until
//!     `ClassRef` itself is made non-null.
//!   * Arrays are erased to `jni.jobject`.
//!   * Overload names use human-readable mangling (`drawText__String_float_float_Paint`).
//!   * Synthetic / bridge methods are skipped.
//!   * Constructors → `new__<mangle>` returning a Ref.
//!   * No generic specialization; Signature is preserved as a doc
//!     comment only.
//!   * Process-global jclass/jmethodID caches are OUT OF SCOPE for v1 —
//!     we emit straight `jni.call` / `jni.callStatic`. Caching can be
//!     layered on later without changing call sites.

const std = @import("std");
const classfile = @import("classfile");
const typemap = @import("typemap.zig");
const mangle = @import("mangle.zig");

pub const Options = struct {
    /// Namespace prefix for the generated tree, used only in top-of-file
    /// doc comment. The actual import paths are relative.
    compile_sdk: []const u8 = "android-?",
    /// Internal name of the JNI root module (e.g. `"android"`). Emitted
    /// as `const jni = @import("android").jni;`.
    android_import: []const u8 = "android",
    /// If non-null, only emit classes whose internal name starts with
    /// one of these prefixes.
    filter_prefixes: ?[]const []const u8 = null,
};

pub const EmitError = error{
    WriteFailed,
} || std.mem.Allocator.Error || typemap.Error || mangle.Error || std.Io.Dir.CreateDirPathError || std.Io.Dir.OpenError || std.Io.File.OpenError;

/// Emit one .zig file for `cf` under `out_dir`. The file is placed at
/// `<out_dir>/<internal_name>.zig` with directories created as needed.
pub fn emitClass(
    gpa: std.mem.Allocator,
    io: std.Io,
    out_dir_path: []const u8,
    cf: *const classfile.ClassFile,
    opts: Options,
) !void {
    if (!shouldEmit(cf.this_name, opts)) return;

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Collect imports: unique set of class internal names referenced.
    // StringArrayHashMapUnmanaged preserves insertion order so the
    // generated imports block is deterministic across runs.
    var imports: std.StringArrayHashMapUnmanaged(void) = .empty;

    // First pass: mangle method names (disambiguate overloads).
    const EmittedMethod = struct {
        zig_name: []const u8,
        raw_name: []const u8,
        desc: []const u8,
        signature: ?[]const u8,
        is_static: bool,
        is_ctor: bool,
        is_deprecated: bool,
    };
    var methods: std.ArrayList(EmittedMethod) = .empty;

    // Count method-name occurrences for overload detection.
    var name_count = std.StringHashMap(usize).init(arena);
    for (cf.methods) |m| {
        if (isSkippable(m.access)) continue;
        const gop = try name_count.getOrPut(m.name);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;
    }

    for (cf.methods) |m| {
        if (isSkippable(m.access)) continue;
        const is_ctor = std.mem.eql(u8, m.name, "<init>");
        const is_static = m.access.static;

        const base_name = if (is_ctor) "new" else m.name;
        const collision_count = name_count.get(m.name) orelse 0;
        var zig_name = if (collision_count > 1)
            try mangle.overloadMangle(arena, base_name, m.descriptor)
        else
            try mangle.sanitize(arena, base_name);

        // Post-disambiguate: if overload mangling still collides (e.g.
        // two parameter classes share a simple name in distinct packages),
        // append `__N`.
        var n: u32 = 2;
        while (true) {
            var dup = false;
            for (methods.items) |prev| {
                if (std.mem.eql(u8, prev.zig_name, zig_name)) {
                    dup = true;
                    break;
                }
            }
            if (!dup) break;
            zig_name = try std.fmt.allocPrint(arena, "{s}__{d}", .{ zig_name, n });
            n += 1;
        }

        const is_dep = try classfile.annotation.isDeprecated(arena, cf.pool, m.attributes_raw);

        try methods.append(arena, .{
            .zig_name = zig_name,
            .raw_name = m.name,
            .desc = m.descriptor,
            .signature = m.signature,
            .is_static = is_static,
            .is_ctor = is_ctor,
            .is_deprecated = is_dep,
        });
    }

    // --- Build the emission buffer ----------------------------------------
    var out_buf: std.ArrayList(u8) = .empty;
    const W = struct {
        buf: *std.ArrayList(u8),
        a: std.mem.Allocator,
        fn print(self: @This(), comptime fmt: []const u8, args: anytype) !void {
            try self.buf.print(self.a, fmt, args);
        }
        fn writeAll(self: @This(), s: []const u8) !void {
            try self.buf.appendSlice(self.a, s);
        }
        fn writeByte(self: @This(), b: u8) !void {
            try self.buf.append(self.a, b);
        }
    };
    const w = W{ .buf = &out_buf, .a = arena };

    try w.print(
        \\// AUTOGENERATED by bindgen from {s}. Do not edit by hand.
        \\// See src/bindgen/emit.zig.
        \\
        \\const std = @import("std");
        \\const jni = @import("{s}").jni;
        \\
        \\pub const class_name: [:0]const u8 = "{s}";
        \\pub const Ref = jni.ClassRef("L{s};");
        \\
        \\
    , .{ opts.compile_sdk, opts.android_import, cf.this_name, cf.this_name });

    // --- Fields ---
    for (cf.fields) |f| {
        if (isSkippable(f.access)) continue;

        // Only static-final primitive/string constants get inlined via
        // ConstantValue. Other fields we skip in v1 — JNI field getters
        // need a separate code path with their own mid caching, and
        // fields are rarer than methods in the APIs apk1 cares about.
        if (!(f.access.static and f.access.final)) continue;
        if (f.constant_value == null) continue;

        const sane = try mangle.sanitize(arena, f.name);
        switch (f.constant_value.?) {
            .integer => |v| try w.print("pub const {s}: i32 = {d};\n", .{ sane, v }),
            .long => |v| try w.print("pub const {s}: i64 = {d};\n", .{ sane, v }),
            .float => |v| {
                if (std.math.isNan(v)) {
                    try w.print("pub const {s}: f32 = std.math.nan(f32);\n", .{sane});
                } else if (std.math.isPositiveInf(v)) {
                    try w.print("pub const {s}: f32 = std.math.inf(f32);\n", .{sane});
                } else if (std.math.isNegativeInf(v)) {
                    try w.print("pub const {s}: f32 = -std.math.inf(f32);\n", .{sane});
                } else {
                    try w.print("pub const {s}: f32 = {d};\n", .{ sane, v });
                }
            },
            .double => |v| {
                if (std.math.isNan(v)) {
                    try w.print("pub const {s}: f64 = std.math.nan(f64);\n", .{sane});
                } else if (std.math.isPositiveInf(v)) {
                    try w.print("pub const {s}: f64 = std.math.inf(f64);\n", .{sane});
                } else if (std.math.isNegativeInf(v)) {
                    try w.print("pub const {s}: f64 = -std.math.inf(f64);\n", .{sane});
                } else {
                    try w.print("pub const {s}: f64 = {d};\n", .{ sane, v });
                }
            },
            .string => |s| {
                try w.print("pub const {s}: []const u8 = \"", .{sane});
                try writeEscaped(w, s);
                try w.writeAll("\";\n");
            },
        }
    }
    if (cf.fields.len > 0) try w.writeAll("\n");

    // --- Methods ---
    const Imp = struct {
        imports_map: *std.StringArrayHashMapUnmanaged(void),
        arena: std.mem.Allocator,
    };
    var imp = Imp{ .imports_map = &imports, .arena = arena };

    const aliasFor = struct {
        fn f(ctx: *Imp, internal: []const u8) anyerror![]const u8 {
            _ = try ctx.imports_map.getOrPut(ctx.arena, internal);
            // Use the FULL internal path to guarantee uniqueness when two
            // different packages declare the same simple class name
            // (e.g. android/icu/util/Currency vs java/util/Currency).
            var buf: std.ArrayList(u8) = .empty;
            for (internal) |ch| {
                const repl: u8 = switch (ch) {
                    '/', '$' => '_',
                    else => ch,
                };
                try buf.append(ctx.arena, repl);
            }
            try buf.appendSlice(ctx.arena, "_c");
            return try buf.toOwnedSlice(ctx.arena);
        }
    }.f;

    // Methods body goes into a separate buffer, so we can write the
    // (now-known) imports at the top after the method body is rendered.
    var body: std.ArrayList(u8) = .empty;
    const bw = W{ .buf = &body, .a = arena };

    for (methods.items) |m| {
        const parsed = try typemap.parseMethod(arena, m.desc, &imp, aliasFor);

        try bw.print("/// {s}  {s}\n", .{ m.raw_name, m.desc });
        if (m.signature) |s| try bw.print("/// signature: {s}\n", .{s});
        if (m.is_deprecated) try bw.writeAll("/// Deprecated.\n");

        try bw.print("pub fn {s}(", .{m.zig_name});

        // Arg list.
        if (m.is_static or m.is_ctor) {
            try bw.writeAll("env: *jni.JNIEnv");
        } else {
            try bw.writeAll("env: *jni.JNIEnv, self: Ref");
        }
        for (parsed.params, 0..) |p, i| {
            try bw.print(", arg{d}: {s}", .{ i, p });
        }
        try bw.writeAll(") !");

        // Constructors ignore the descriptor's V return and yield Ref.
        if (m.is_ctor) {
            try bw.writeAll("Ref");
        } else {
            try bw.writeAll(parsed.ret);
        }
        try bw.writeAll(" {\n");

        if (m.is_ctor) {
            // Constructors need NewObjectA — not yet in jni.zig. Emit
            // @compileError first so the function body has no unused
            // locals if someone tries to reference it.
            try bw.writeAll("    _ = env;\n");
            for (parsed.params, 0..) |_, i| {
                try bw.print("    _ = arg{d};\n", .{i});
            }
            try bw.writeAll("    @compileError(\"constructor wrappers are not yet emitted — use jni.findClass + NewObjectA directly\");\n");
            try bw.writeAll("}\n\n");
            continue;
        }

        // Emit the fn-type for sigOfFn.
        try bw.writeAll("    const F = fn (");
        for (parsed.params, 0..) |p, i| {
            if (i > 0) try bw.writeAll(", ");
            try bw.print("{s}", .{p});
        }
        try bw.writeAll(") ");
        try bw.writeAll(parsed.ret);
        try bw.writeAll(";\n");

        // Arg tuple.
        try bw.writeAll("    const args = .{");
        for (parsed.params, 0..) |_, i| {
            if (i > 0) try bw.writeAll(", ");
            try bw.print("arg{d}", .{i});
        }
        try bw.writeAll("};\n");

        if (m.is_static) {
            try bw.print(
                "    return try jni.callStatic(F, env, class_name, \"{s}\", args);\n",
                .{m.raw_name},
            );
        } else {
            try bw.print(
                "    return try jni.call(F, env, self.handle, class_name, \"{s}\", args);\n",
                .{m.raw_name},
            );
        }
        try bw.writeAll("}\n\n");

        // `parsed` may have allocated slices — but the arena reclaims all.
    }

    // --- Imports header ---
    // Compute relative import path for each referenced class. For the class
    // itself, emit a `@This()` alias so self-references in parameter/return
    // types resolve to the in-file `Ref`.
    var imp_it = imports.iterator();
    while (imp_it.next()) |e| {
        const target = e.key_ptr.*;
        const alias = try aliasName(arena, target);
        if (std.mem.eql(u8, target, cf.this_name)) {
            try w.print("const {s} = @This();\n", .{alias});
        } else {
            const rel = try relativePath(arena, cf.this_name, target);
            try w.print("const {s} = @import(\"{s}\");\n", .{ alias, rel });
        }
    }
    if (imports.count() > 0) try w.writeAll("\n");

    try w.writeAll(body.items);

    // --- Write to disk -----------------------------------------------------
    try writeOutput(gpa, io, out_dir_path, cf.this_name, out_buf.items);
}

fn aliasName(a: std.mem.Allocator, internal: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (internal) |ch| {
        const repl: u8 = switch (ch) {
            '/', '$' => '_',
            else => ch,
        };
        try buf.append(a, repl);
    }
    try buf.appendSlice(a, "_c");
    return try buf.toOwnedSlice(a);
}

/// Compute a relative import path from the source class to the target
/// class, both specified as internal names like `"android/os/Build"`.
fn relativePath(a: std.mem.Allocator, from: []const u8, to: []const u8) ![]const u8 {
    // Count directory components in `from` (slashes). Each one becomes
    // a `../` we must climb out of.
    var slashes: usize = 0;
    for (from) |c| if (c == '/') {
        slashes += 1;
    };
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < slashes) : (i += 1) try buf.appendSlice(a, "../");
    try buf.appendSlice(a, to);
    // `$` stays in the file name since we keep inner-class file names as
    // e.g. `Build$VERSION.zig` on disk for round-trip fidelity. But `$`
    // inside `@import(...)` is fine.
    try buf.appendSlice(a, ".zig");
    return try buf.toOwnedSlice(a);
}

fn writeOutput(
    gpa: std.mem.Allocator,
    io: std.Io,
    out_dir: []const u8,
    internal_name: []const u8,
    contents: []const u8,
) !void {
    var path_buf: std.ArrayList(u8) = .empty;
    defer path_buf.deinit(gpa);
    try path_buf.appendSlice(gpa, out_dir);
    if (out_dir.len > 0 and out_dir[out_dir.len - 1] != '/') try path_buf.append(gpa, '/');
    try path_buf.appendSlice(gpa, internal_name);
    try path_buf.appendSlice(gpa, ".zig");

    const full = path_buf.items;
    const last_slash = std.mem.lastIndexOfScalar(u8, full, '/') orelse return error.WriteFailed;
    const dir_part = full[0..last_slash];
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, dir_part);
    var f = try cwd.createFile(io, full, .{});
    defer f.close(io);
    try f.writeStreamingAll(io, contents);
}

fn shouldEmit(name: []const u8, opts: Options) bool {
    const prefixes = opts.filter_prefixes orelse return true;
    for (prefixes) |p| if (std.mem.startsWith(u8, name, p)) return true;
    return false;
}

fn isSkippable(a: classfile.ClassAccess) bool {
    // ACC_SYNTHETIC (0x1000) — compiler-generated; hide from the public
    // surface. Bridge methods (ACC_BRIDGE = ACC_VOLATILE when on a method)
    // are a pain to distinguish without Method vs Field context; for v1
    // we rely on ACC_SYNTHETIC covering most of them.
    // Private members are not useful from JNI bindings consumers.
    return a.synthetic or a.private;
}

fn writeEscaped(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0...8, 11, 12, 14...31 => try w.print("\\x{x:0>2}", .{c}),
            else => try w.writeByte(c),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test {
    _ = @import("typemap.zig");
    _ = @import("mangle.zig");
}
