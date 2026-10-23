const std = @import("std");

pub fn builtinModule(b: *std.Build, package_name: std.Build.LazyPath) *std.Build.Module {
    const dep = b.dependencyFromBuildZig(@import("../../build.zig"), .{});
    const run = b.addRunArtifact(dep.artifact("android-build-tool"));
    run.addFileArg(package_name);
    return b.createModule(.{
        .root_source_file = run.captureStdOut(.{ .basename = "android_builtin.zig" }),
    });
}
