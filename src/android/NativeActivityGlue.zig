//! Comptime-driven glue that binds user-defined `AndroidApp` methods to the
//! ANativeActivity callback table. Requires Zig 0.16+.
//!
//! Usage (from an example or an app):
//!
//!     const android = @import("android");
//!     const bind = @import("android-bind");
//!
//!     export fn ANativeActivity_onCreate(activity: *bind.ANativeActivity, saved: ?*anyopaque, saved_size: usize) callconv(.c) void {
//!         _ = saved; _ = saved_size;
//!         const app = std.heap.c_allocator.create(AndroidApp) catch @panic("oom");
//!         app.* = AndroidApp.init();
//!         activity.instance = app;
//!         activity.callbacks.* = android.makeNativeActivityGlue(AndroidApp, bind.ANativeActivityCallbacks);
//!     }
//!
//! For each field `foo` of `Callbacks`:
//!   - If `AndroidApp` declares `foo`, a C thunk is installed that calls
//!     `AndroidApp.foo(self, extra_args...)`. The App method's signature is
//!     checked against the NDK shape at compile time by virtue of tuple call.
//!   - Otherwise the field is left null.
//!
//! Special cases:
//!   - `onDestroy` is always installed. It calls `AndroidApp.deinit(self)` if
//!     present, then `std.heap.c_allocator.destroy(self)`.
//!   - `onSaveInstanceState`, if declared, must have signature
//!     `fn(self: *App, allocator: std.mem.Allocator) ?[]u8`. The returned slice
//!     must be allocated with `c_allocator` (NDK will free it with free(3)).

const std = @import("std");

const log = std.log.scoped(.android);

/// Build a fully-populated `Callbacks` value that forwards to methods on `App`.
pub fn make(comptime App: type, comptime Callbacks: type) Callbacks {
    comptime {
        if (@typeInfo(Callbacks) != .@"struct")
            @compileError("makeNativeActivityGlue: Callbacks must be a struct");
    }
    var cbs: Callbacks = std.mem.zeroes(Callbacks);
    inline for (@typeInfo(Callbacks).@"struct".fields) |field| {
        @field(cbs, field.name) = comptime makeField(App, field);
    }
    return cbs;
}

fn makeField(comptime App: type, comptime field: std.builtin.Type.StructField) field.type {
    const OptFn = field.type;
    if (@typeInfo(OptFn) != .optional)
        @compileError("makeNativeActivityGlue: field " ++ field.name ++ " is not optional");
    const FnPtr = @typeInfo(OptFn).optional.child;
    if (@typeInfo(FnPtr) != .pointer)
        @compileError("makeNativeActivityGlue: field " ++ field.name ++ " is not a fn pointer");
    const FnT = @typeInfo(FnPtr).pointer.child;
    const fi = @typeInfo(FnT);
    if (fi != .@"fn")
        @compileError("makeNativeActivityGlue: field " ++ field.name ++ " is not a fn");
    const params = fi.@"fn".params;
    if (params.len < 1) @compileError("callback must take *ANativeActivity");
    const Activity = params[0].type.?;

    if (std.mem.eql(u8, field.name, "onDestroy")) {
        return &DestroyThunk(App, Activity).cb;
    }
    if (std.mem.eql(u8, field.name, "onSaveInstanceState")) {
        if (!@hasDecl(App, "onSaveInstanceState")) return null;
        const SizePtr = params[1].type.?;
        return &SaveThunk(App, Activity, SizePtr).cb;
    }

    if (!@hasDecl(App, field.name)) return null;

    return switch (params.len) {
        1 => &Thunk1(App, field.name, Activity).cb,
        2 => &Thunk2(App, field.name, Activity, params[1].type.?).cb,
        3 => &Thunk3(App, field.name, Activity, params[1].type.?, params[2].type.?).cb,
        else => @compileError("unsupported callback arity for " ++ field.name),
    };
}

fn appFromActivity(comptime App: type, activity: anytype) ?*App {
    const instance = activity.instance orelse return null;
    return @ptrCast(@alignCast(instance));
}

fn handleReturn(comptime name: []const u8, result: anytype) void {
    const R = @TypeOf(result);
    comptime {
        const ok = R == void or @typeInfo(R) == .error_union or @typeInfo(R) == .error_set;
        if (!ok) @compileError("App." ++ name ++ " must return void, !void, or an error set");
    }
    if (comptime @typeInfo(R) == .error_union) {
        result catch |err| log.err("{s}: {s}", .{ name, @errorName(err) });
    } else if (comptime @typeInfo(R) == .error_set) {
        log.err("{s}: {s}", .{ name, @errorName(result) });
    }
}

fn Thunk1(comptime App: type, comptime name: []const u8, comptime Activity: type) type {
    return struct {
        fn cb(activity: Activity) callconv(.c) void {
            const app = appFromActivity(App, activity) orelse return;
            handleReturn(name, @call(.auto, @field(App, name), .{app}));
        }
    };
}

fn Thunk2(comptime App: type, comptime name: []const u8, comptime Activity: type, comptime A1: type) type {
    return struct {
        fn cb(activity: Activity, a1: A1) callconv(.c) void {
            const app = appFromActivity(App, activity) orelse return;
            // c_int for "hasFocus" gets forwarded as bool for ergonomics when
            // the App method opts into bool; otherwise pass the raw value.
            const Method = @TypeOf(@field(App, name));
            const mp = @typeInfo(Method).@"fn".params;
            if (mp.len == 2 and mp[1].type == bool and A1 == c_int) {
                handleReturn(name, @call(.auto, @field(App, name), .{ app, a1 != 0 }));
            } else {
                handleReturn(name, @call(.auto, @field(App, name), .{ app, a1 }));
            }
        }
    };
}

fn Thunk3(comptime App: type, comptime name: []const u8, comptime Activity: type, comptime A1: type, comptime A2: type) type {
    return struct {
        fn cb(activity: Activity, a1: A1, a2: A2) callconv(.c) void {
            const app = appFromActivity(App, activity) orelse return;
            handleReturn(name, @call(.auto, @field(App, name), .{ app, a1, a2 }));
        }
    };
}

fn DestroyThunk(comptime App: type, comptime Activity: type) type {
    return struct {
        fn cb(activity: Activity) callconv(.c) void {
            const app = appFromActivity(App, activity) orelse return;
            if (comptime @hasDecl(App, "deinit")) app.deinit();
            std.heap.c_allocator.destroy(app);
        }
    };
}

fn SaveThunk(comptime App: type, comptime Activity: type, comptime SizePtr: type) type {
    return struct {
        fn cb(activity: Activity, out_size: SizePtr) callconv(.c) ?[*]u8 {
            out_size.* = 0;
            const app = appFromActivity(App, activity) orelse return null;
            const optional_slice: ?[]u8 = app.onSaveInstanceState(std.heap.c_allocator);
            if (optional_slice) |slice| {
                out_size.* = slice.len;
                return slice.ptr;
            }
            return null;
        }
    };
}
