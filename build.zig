const std = @import("std");

const androidbuild = @import("src/androidbuild/androidbuild.zig");
pub const ApiLevel = androidbuild.ApiLevel;
pub const standardTargets = androidbuild.standardTargets;
pub const resolveTargets = androidbuild.resolveTargets;
pub const Apk = @import("src/androidbuild/Apk.zig");
pub const Sdk = @import("src/androidbuild/tools.zig");

// Deprecated exposed fields

/// Deprecated: Use ApiLevel
pub const APILevel = @compileError("use android.ApiLevel instead of android.APILevel");
/// Deprecated: Use Sdk instead
pub const Tools = @compileError("Use android.Sdk instead of android.Tools");
/// Deprecated: Use Apk.Options instead.
pub const ToolsOptions = @compileError("Use android.Sdk.Options instead of android.Apk.Options with the Sdk.createApk method");
/// Deprecated: Use Sdk.CreateKey instead.
pub const CreateKey = @compileError("Use android.Sdk.CreateKey instead of android.CreateKey. Change 'android_tools.createKeyStore(android.CreateKey.example())' to 'android_sdk.createKeyStore(.example)'");
/// Deprecated: Use Apk not APK
pub const APK = @compileError("Use android.Apk instead of android.APK");

/// NOTE: As well as providing the "android" module this declaration is required so this can be imported by other build.zig files
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create stub of builtin options.
    // This is discovered and then replaced by "Apk" in the build process
    const android_builtin_options = std.Build.addOptions(b);
    android_builtin_options.addOption([:0]const u8, "package_name", "");
    const android_builtin_module = android_builtin_options.createModule();

    // Create android module
    const android_module = b.addModule("android", .{
        .root_source_file = b.path("src/android/android.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ndk_module = b.createModule(.{
        .root_source_file = b.path("src/android/ndk/ndk.zig"),
        .target = target,
        .optimize = optimize,
    });
    android_module.addImport("ndk", ndk_module);
    android_module.addImport("android_builtin", android_builtin_module);

    android_module.linkSystemLibrary("log", .{});

    // Classfile parser — pure-Zig `.class` / `.jar` reader used by binding
    // generation. Independent of the `android` module so it can be consumed
    // standalone (e.g. by host-side build-time tooling).
    const classfile_module = b.addModule("classfile", .{
        .root_source_file = b.path("src/classfile/classfile.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Host-side `classdump` CLI: `zig build classdump -- path/to/Foo.class`.
    const classdump_exe = b.addExecutable(.{
        .name = "classdump",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/classdump/main.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "classfile", .module = classfile_module }},
        }),
    });
    b.installArtifact(classdump_exe);
    const run_classdump = b.addRunArtifact(classdump_exe);
    if (b.args) |args| run_classdump.addArgs(args);
    const classdump_step = b.step("classdump", "Dump a single .class file (smoke test for the classfile parser)");
    classdump_step.dependOn(&run_classdump.step);

    // Tests for the classfile parser.
    const classfile_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/classfile/classfile.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const run_classfile_tests = b.addRunArtifact(classfile_tests);
    const test_step = b.step("test-classfile", "Run classfile parser tests");
    test_step.dependOn(&run_classfile_tests.step);
}
