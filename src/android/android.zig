const std = @import("std");
const builtin = @import("builtin");

const ndk = @import("ndk");
const compat = @import("compat.zig");
const Logger = @import("Logger.zig");
const Level = ndk.Level;

const NativeActivityGlue = @import("NativeActivityGlue.zig");

/// Build an `ANativeActivityCallbacks` table that dispatches to methods on
/// `App` via comptime reflection. See `NativeActivityGlue.zig` for details.
pub const makeNativeActivityGlue = NativeActivityGlue.make;

/// Typed JNI bridge. See `jni.zig`.
pub const jni = @import("jni.zig");

/// Cast an erased pointer to `*T`, combining the required `@alignCast` with
/// the `@ptrCast`. Using this helper guarantees the `@alignCast` never gets
/// dropped by accident (a footgun that previously required a patch in the
/// `makeNativeActivityGlue` example).
///
///     const app: *AndroidApp = android.asPtr(AndroidApp, activity.instance);
pub inline fn asPtr(comptime T: type, p: anytype) *T {
    return @ptrCast(@alignCast(p));
}

/// Alternate panic implementation that calls __android_log_write so that you can see the logging via "adb logcat"
pub const panic = std.debug.FullPanic(compat.panic);

/// Alternate log function implementation that calls __android_log_write so that you can see the logging via "adb logcat"
pub const logFn = compat.wrapLogFn(androidLogFn);

fn androidLogFn(
    comptime message_level: std.log.Level,
    comptime scope_prefix_text: [:0]const u8,
    comptime format: []const u8,
    args: anytype,
) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const android_log_level: Level = switch (message_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    };

    const fields_info = args_type_info.@"struct".fields;
    if (fields_info.len == 0 and
        comptime std.mem.indexOfScalar(u8, format, '{') == null)
    {
        // If no formatting, log string directly with Android logging
        _ = Logger.logString(android_log_level, scope_prefix_text ++ format);
        return;
    }
    var buffer: [8192]u8 = undefined;
    var logger = Logger.init(android_log_level, &buffer);
    nosuspend {
        logger.writer.print(scope_prefix_text ++ format ++ "\n", args) catch return;
        logger.writer.flush() catch return;
    }
}
