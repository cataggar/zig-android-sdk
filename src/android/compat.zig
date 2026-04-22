//! Zig 0.16+ compatibility shims for the Android logger and panic handler.
//!
//! Previously lived in three per-version submodules (zig014, zig015, zig016)
//! to straddle @Type(.enum_literal) / @EnumLiteral() and panic-signature
//! churn. This module drops pre-0.16 support to consolidate them.

const std = @import("std");
const builtin = @import("builtin");
const ndk = @import("ndk");

const android_builtin = @import("android_builtin");
const package_name: ?[*:0]const u8 = if (android_builtin.package_name.len > 0) android_builtin.package_name else null;

const LogFunction = fn (
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void;

pub fn wrapLogFn(comptime logFn: fn (
    comptime message_level: std.log.Level,
    comptime scope_prefix_text: [:0]const u8,
    comptime format: []const u8,
    args: anytype,
) void) LogFunction {
    return struct {
        fn standardLogFn(
            comptime message_level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            // NOTE(jae): 2024-09-11
            // Zig has a colon ": " or "): " for scoped but Android logs just do that after being flushed
            // so we don't do that here.
            const scope_prefix_text = if (scope == .default) "" else @tagName(scope) ++ ": ";
            return logFn(message_level, scope_prefix_text, format, args);
        }
    }.standardLogFn;
}

pub fn panic(message: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);
    if (comptime !builtin.abi.isAndroid()) @compileError("do not use Android panic for non-Android builds");

    const android_log_level: c_int = @intFromEnum(ndk.Level.fatal);

    trace: {
        _ = ndk.__android_log_print(android_log_level, package_name, "panic: %.*s", message.len, message.ptr);

        if (@errorReturnTrace()) |t| if (t.index > 0) {
            logFatal("error return context:");
            writeStackTrace(t) catch break :trace;
            logFatal("\nstack trace:\n");
        };
        if (!std.options.allow_stack_tracing) {
            logFatal("Cannot print stack trace: stack tracing is disabled");
            return;
        } else {
            _ = ndk.__android_log_print(android_log_level, package_name, "  at address: 0x%X", first_trace_addr orelse @returnAddress());
            logFatal("  (stack trace printing not supported in Zig 0.16.X+ for Android SDK)");
        }
    }

    @trap();
}

/// Write a previously captured stack trace to the Android log, annotated with source locations.
pub fn writeStackTrace(st: *const std.builtin.StackTrace) !void {
    if (!std.options.allow_stack_tracing) {
        logFatal("Cannot print stack trace: stack tracing is disabled");
        return;
    }

    const n_frames = st.index;
    if (n_frames == 0) return logFatal("(empty stack trace)");

    const captured_frames = @min(n_frames, st.instruction_addresses.len);
    logFatal("(stack trace support unimplemented for Zig 0.16.X+)");

    if (n_frames > captured_frames) {
        _ = ndk.__android_log_print(
            @intFromEnum(ndk.Level.fatal),
            package_name,
            "(%d additional stack frames skipped...)",
            n_frames - captured_frames,
        );
    }
}

inline fn logFatal(text: []const u8) void {
    _ = ndk.__android_log_print(
        @intFromEnum(ndk.Level.fatal),
        package_name,
        "%.*s",
        text.len,
        text.ptr,
    );
}
