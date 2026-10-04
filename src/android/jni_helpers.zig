//! Ergonomic wrappers around the lowest-level JNI surface in `jni.zig`.
//!
//! These helpers exist so downstream apps can register native methods and
//! grab a `*JNIEnv` from a `*JavaVM` without copy/pasting the same
//! findClass+exception-clear+register dance into every `JNI_OnLoad`.
//!
//! All wrappers stay zero-cost: they decay to the same handful of
//! function-pointer dispatches that the raw `jni.zig` API would do.

const std = @import("std");
const jni = @import("jni.zig");

pub const JNINativeMethod = jni.JNINativeMethod;
pub const JNIEnv = jni.JNIEnv;
pub const JavaVM = jni.JavaVM;

/// Build a `JNINativeMethod` literal at comptime. Using this instead of an
/// inline struct literal keeps the call sites tidy and lets the compiler
/// catch typos in the field names.
///
///     const methods = [_]jni.JNINativeMethod{
///         h.method("nativeCommitText", "(Ljava/lang/String;I)V", &nativeCommitText),
///         h.method("nativeKey",        "(III)V",                  &nativeKey),
///     };
pub fn method(
    name: [*:0]const u8,
    sig: [*:0]const u8,
    fn_ptr: *const anyopaque,
) JNINativeMethod {
    return .{
        .name = name,
        .signature = sig,
        .fnPtr = @constCast(fn_ptr),
    };
}

/// `FindClass` + `RegisterNatives` + local-ref cleanup in one call.
///
/// On any JNI failure (class not found, register failed) any pending
/// exception is cleared and an `error.RegisterNativesFailed` /
/// `error.ClassNotFound` is returned. Local refs are always released.
pub fn registerNativesFor(
    env: *JNIEnv,
    class_name: [*:0]const u8,
    methods: []const JNINativeMethod,
) !void {
    const clazz = jni.findClass(env, class_name);
    if (clazz == null or jni.exceptionCheck(env)) {
        if (jni.exceptionCheck(env)) jni.exceptionClear(env);
        return error.ClassNotFound;
    }
    defer jni.deleteLocalRef(env, clazz);

    jni.registerNatives(env, clazz, methods) catch |err| {
        if (jni.exceptionCheck(env)) jni.exceptionClear(env);
        return err;
    };
}

/// Get a `*JNIEnv` for the calling thread. Returns `error.JniGetEnvFailed`
/// if the thread is not attached to the VM (in which case the caller
/// should `attachCurrentThread`).
pub fn getEnv(vm: *JavaVM) !*JNIEnv {
    var raw: ?*anyopaque = null;
    const rc = jni.getEnv(vm, &raw, jni.JNI_VERSION_1_6);
    if (rc != jni.JNI_OK) return error.JniGetEnvFailed;
    return @as(*JNIEnv, @ptrCast(raw orelse return error.JniGetEnvFailed));
}

/// Attach the calling thread to `vm` and return its `*JNIEnv`.
/// The caller is responsible for `detachCurrentThread` before exiting
/// the thread, otherwise the VM will abort on shutdown.
pub fn attachCurrentThread(vm: *JavaVM) !*JNIEnv {
    var raw: ?*JNIEnv = null;
    const rc = jni.attachCurrentThread(vm, &raw);
    if (rc != jni.JNI_OK) return error.JniAttachFailed;
    return raw orelse error.JniAttachFailed;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "method() builder fills JNINativeMethod fields" {
    const dummy = struct {
        fn f() callconv(.c) void {}
    };
    const m = method("nativeFoo", "()V", &dummy.f);
    try std.testing.expectEqualStrings("nativeFoo", std.mem.sliceTo(m.name, 0));
    try std.testing.expectEqualStrings("()V", std.mem.sliceTo(m.signature, 0));
    try std.testing.expectEqual(
        @as(?*anyopaque, @constCast(@as(*const anyopaque, &dummy.f))),
        m.fnPtr,
    );
}

test "typed JNI signatures and argument dispatch" {
    const F = fn (i32, bool, jni.String) i64;
    try std.testing.expectEqualStrings("(IZLjava/lang/String;)J", comptime jni.sigOfFn(F));
    const callbacks = struct {
        fn call(_: *jni.JNIEnv, _: jni.jobject, _: jni.jmethodID, args: [*c]const jni.jvalue) callconv(.c) jni.jlong {
            std.debug.assert(args[0].i == 42);
            std.debug.assert(args[1].z == 1);
            std.debug.assert(args[2].l == null);
            return 73;
        }
    };
    var table: jni.JNINativeInterface = std.mem.zeroes(jni.JNINativeInterface);
    table.CallLongMethodA = &callbacks.call;
    table.CallStaticLongMethodA = &callbacks.call;
    var table_ptr: *const jni.JNINativeInterface = &table;
    const env: *jni.JNIEnv = @ptrCast(&table_ptr);
    const args = .{ @as(i32, 42), true, jni.String{ .handle = null } };
    try std.testing.expectEqual(@as(i64, 73), jni.callInstanceByID(F, env, null, null, args));
    try std.testing.expectEqual(@as(i64, 73), jni.callStaticByID(F, env, null, null, args));
}
