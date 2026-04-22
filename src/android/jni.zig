//! Typed JNI bridge for Android. Zig 0.16+.
//!
//! Provides:
//!   - Full `JNINativeInterface` extern struct (ABI-exact for arm64/armv7).
//!   - Full `JNIInvokeInterface` extern struct for JavaVM.
//!   - Comptime Java-type-signature builder: `sigOfFn(F) -> "(II)V"`.
//!   - One-shot typed invoker: `call(env, obj, class_name, method_name, F, args)`.
//!   - Cached method handle: `Method(class, name, F).call(env, obj, args)`.
//!   - `callStatic` / `StaticMethod` equivalents.
//!
//! Java signature mapping:
//!   bool/jboolean -> Z   u8/jbyte -> B   u16/jchar -> C
//!   i16/jshort -> S   i32/jint -> I   i64/jlong -> J
//!   f32/jfloat -> F   f64/jdouble -> D   void -> V
//!   A custom class-ref struct type has a pub const java_sig = "Lcom/foo/Bar;".
//!   ?jobject / jstring default to Ljava/lang/Object; / Ljava/lang/String;.

const std = @import("std");

// -- Primitive types --------------------------------------------------------

pub const jboolean = u8;
pub const jbyte = i8;
pub const jchar = u16;
pub const jshort = i16;
pub const jint = i32;
pub const jlong = i64;
pub const jfloat = f32;
pub const jdouble = f64;
pub const jsize = jint;

pub const jobject = ?*anyopaque;
pub const jclass = jobject;
pub const jstring = jobject;
pub const jarray = jobject;
pub const jobjectArray = jarray;
pub const jbooleanArray = jarray;
pub const jbyteArray = jarray;
pub const jcharArray = jarray;
pub const jshortArray = jarray;
pub const jintArray = jarray;
pub const jlongArray = jarray;
pub const jfloatArray = jarray;
pub const jdoubleArray = jarray;
pub const jthrowable = jobject;
pub const jweak = jobject;

pub const jmethodID = ?*opaque {};
pub const jfieldID = ?*opaque {};

pub const jobjectRefType = c_int;

pub const jvalue = extern union {
    z: jboolean,
    b: jbyte,
    c: jchar,
    s: jshort,
    i: jint,
    j: jlong,
    f: jfloat,
    d: jdouble,
    l: jobject,
};

pub const JNINativeMethod = extern struct {
    name: [*c]const u8,
    signature: [*c]const u8,
    fnPtr: ?*anyopaque,
};

pub const JNI_OK: jint = 0;
pub const JNI_ERR: jint = -1;
pub const JNI_EDETACHED: jint = -2;
pub const JNI_EVERSION: jint = -3;

pub const JNI_VERSION_1_6: jint = 0x00010006;

pub const JNIEnv = opaque {};
pub const JavaVM = opaque {};

pub const JNINativeInterface = extern struct {
    reserved0: ?*anyopaque,
    reserved1: ?*anyopaque,
    reserved2: ?*anyopaque,
    reserved3: ?*anyopaque,
    GetVersion: ?*const fn(*JNIEnv) callconv(.c) jint,
    DefineClass: ?*const fn(*JNIEnv, [*c]const u8, jobject, [*c]const jbyte, jsize) callconv(.c) jclass,
    FindClass: ?*const fn(*JNIEnv, [*c]const u8) callconv(.c) jclass,
    FromReflectedMethod: ?*const fn(*JNIEnv, jobject) callconv(.c) jmethodID,
    FromReflectedField: ?*const fn(*JNIEnv, jobject) callconv(.c) jfieldID,
    ToReflectedMethod: ?*const fn(*JNIEnv, jclass, jmethodID, jboolean) callconv(.c) jobject,
    GetSuperclass: ?*const fn(*JNIEnv, jclass) callconv(.c) jclass,
    IsAssignableFrom: ?*const fn(*JNIEnv, jclass, jclass) callconv(.c) jboolean,
    ToReflectedField: ?*const fn(*JNIEnv, jclass, jfieldID, jboolean) callconv(.c) jobject,
    Throw: ?*const fn(*JNIEnv, jthrowable) callconv(.c) jint,
    ThrowNew: ?*const fn(*JNIEnv, jclass, [*c]const u8) callconv(.c) jint,
    ExceptionOccurred: ?*const fn(*JNIEnv) callconv(.c) jthrowable,
    ExceptionDescribe: ?*const fn(*JNIEnv) callconv(.c) void,
    ExceptionClear: ?*const fn(*JNIEnv) callconv(.c) void,
    FatalError: ?*const fn(*JNIEnv, [*c]const u8) callconv(.c) void,
    PushLocalFrame: ?*const fn(*JNIEnv, jint) callconv(.c) jint,
    PopLocalFrame: ?*const fn(*JNIEnv, jobject) callconv(.c) jobject,
    NewGlobalRef: ?*const fn(*JNIEnv, jobject) callconv(.c) jobject,
    DeleteGlobalRef: ?*const fn(*JNIEnv, jobject) callconv(.c) void,
    DeleteLocalRef: ?*const fn(*JNIEnv, jobject) callconv(.c) void,
    IsSameObject: ?*const fn(*JNIEnv, jobject, jobject) callconv(.c) jboolean,
    NewLocalRef: ?*const fn(*JNIEnv, jobject) callconv(.c) jobject,
    EnsureLocalCapacity: ?*const fn(*JNIEnv, jint) callconv(.c) jint,
    AllocObject: ?*const fn(*JNIEnv, jclass) callconv(.c) jobject,
    NewObject: ?*anyopaque,
    NewObjectV: ?*anyopaque,
    NewObjectA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jobject,
    GetObjectClass: ?*const fn(*JNIEnv, jobject) callconv(.c) jclass,
    IsInstanceOf: ?*const fn(*JNIEnv, jobject, jclass) callconv(.c) jboolean,
    GetMethodID: ?*const fn(*JNIEnv, jclass, [*c]const u8, [*c]const u8) callconv(.c) jmethodID,
    CallObjectMethod: ?*anyopaque,
    CallObjectMethodV: ?*anyopaque,
    CallObjectMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jobject,
    CallBooleanMethod: ?*anyopaque,
    CallBooleanMethodV: ?*anyopaque,
    CallBooleanMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jboolean,
    CallByteMethod: ?*anyopaque,
    CallByteMethodV: ?*anyopaque,
    CallByteMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jbyte,
    CallCharMethod: ?*anyopaque,
    CallCharMethodV: ?*anyopaque,
    CallCharMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jchar,
    CallShortMethod: ?*anyopaque,
    CallShortMethodV: ?*anyopaque,
    CallShortMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jshort,
    CallIntMethod: ?*anyopaque,
    CallIntMethodV: ?*anyopaque,
    CallIntMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jint,
    CallLongMethod: ?*anyopaque,
    CallLongMethodV: ?*anyopaque,
    CallLongMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jlong,
    CallFloatMethod: ?*anyopaque,
    CallFloatMethodV: ?*anyopaque,
    CallFloatMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jfloat,
    CallDoubleMethod: ?*anyopaque,
    CallDoubleMethodV: ?*anyopaque,
    CallDoubleMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) jdouble,
    CallVoidMethod: ?*anyopaque,
    CallVoidMethodV: ?*anyopaque,
    CallVoidMethodA: ?*const fn(*JNIEnv, jobject, jmethodID, [*c]const jvalue) callconv(.c) void,
    CallNonvirtualObjectMethod: ?*anyopaque,
    CallNonvirtualObjectMethodV: ?*anyopaque,
    CallNonvirtualObjectMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jobject,
    CallNonvirtualBooleanMethod: ?*anyopaque,
    CallNonvirtualBooleanMethodV: ?*anyopaque,
    CallNonvirtualBooleanMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jboolean,
    CallNonvirtualByteMethod: ?*anyopaque,
    CallNonvirtualByteMethodV: ?*anyopaque,
    CallNonvirtualByteMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jbyte,
    CallNonvirtualCharMethod: ?*anyopaque,
    CallNonvirtualCharMethodV: ?*anyopaque,
    CallNonvirtualCharMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jchar,
    CallNonvirtualShortMethod: ?*anyopaque,
    CallNonvirtualShortMethodV: ?*anyopaque,
    CallNonvirtualShortMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jshort,
    CallNonvirtualIntMethod: ?*anyopaque,
    CallNonvirtualIntMethodV: ?*anyopaque,
    CallNonvirtualIntMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jint,
    CallNonvirtualLongMethod: ?*anyopaque,
    CallNonvirtualLongMethodV: ?*anyopaque,
    CallNonvirtualLongMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jlong,
    CallNonvirtualFloatMethod: ?*anyopaque,
    CallNonvirtualFloatMethodV: ?*anyopaque,
    CallNonvirtualFloatMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jfloat,
    CallNonvirtualDoubleMethod: ?*anyopaque,
    CallNonvirtualDoubleMethodV: ?*anyopaque,
    CallNonvirtualDoubleMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) jdouble,
    CallNonvirtualVoidMethod: ?*anyopaque,
    CallNonvirtualVoidMethodV: ?*anyopaque,
    CallNonvirtualVoidMethodA: ?*const fn(*JNIEnv, jobject, jclass, jmethodID, [*c]const jvalue) callconv(.c) void,
    GetFieldID: ?*const fn(*JNIEnv, jclass, [*c]const u8, [*c]const u8) callconv(.c) jfieldID,
    GetObjectField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jobject,
    GetBooleanField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jboolean,
    GetByteField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jbyte,
    GetCharField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jchar,
    GetShortField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jshort,
    GetIntField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jint,
    GetLongField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jlong,
    GetFloatField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jfloat,
    GetDoubleField: ?*const fn(*JNIEnv, jobject, jfieldID) callconv(.c) jdouble,
    SetObjectField: ?*const fn(*JNIEnv, jobject, jfieldID, jobject) callconv(.c) void,
    SetBooleanField: ?*const fn(*JNIEnv, jobject, jfieldID, jboolean) callconv(.c) void,
    SetByteField: ?*const fn(*JNIEnv, jobject, jfieldID, jbyte) callconv(.c) void,
    SetCharField: ?*const fn(*JNIEnv, jobject, jfieldID, jchar) callconv(.c) void,
    SetShortField: ?*const fn(*JNIEnv, jobject, jfieldID, jshort) callconv(.c) void,
    SetIntField: ?*const fn(*JNIEnv, jobject, jfieldID, jint) callconv(.c) void,
    SetLongField: ?*const fn(*JNIEnv, jobject, jfieldID, jlong) callconv(.c) void,
    SetFloatField: ?*const fn(*JNIEnv, jobject, jfieldID, jfloat) callconv(.c) void,
    SetDoubleField: ?*const fn(*JNIEnv, jobject, jfieldID, jdouble) callconv(.c) void,
    GetStaticMethodID: ?*const fn(*JNIEnv, jclass, [*c]const u8, [*c]const u8) callconv(.c) jmethodID,
    CallStaticObjectMethod: ?*anyopaque,
    CallStaticObjectMethodV: ?*anyopaque,
    CallStaticObjectMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jobject,
    CallStaticBooleanMethod: ?*anyopaque,
    CallStaticBooleanMethodV: ?*anyopaque,
    CallStaticBooleanMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jboolean,
    CallStaticByteMethod: ?*anyopaque,
    CallStaticByteMethodV: ?*anyopaque,
    CallStaticByteMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jbyte,
    CallStaticCharMethod: ?*anyopaque,
    CallStaticCharMethodV: ?*anyopaque,
    CallStaticCharMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jchar,
    CallStaticShortMethod: ?*anyopaque,
    CallStaticShortMethodV: ?*anyopaque,
    CallStaticShortMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jshort,
    CallStaticIntMethod: ?*anyopaque,
    CallStaticIntMethodV: ?*anyopaque,
    CallStaticIntMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jint,
    CallStaticLongMethod: ?*anyopaque,
    CallStaticLongMethodV: ?*anyopaque,
    CallStaticLongMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jlong,
    CallStaticFloatMethod: ?*anyopaque,
    CallStaticFloatMethodV: ?*anyopaque,
    CallStaticFloatMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jfloat,
    CallStaticDoubleMethod: ?*anyopaque,
    CallStaticDoubleMethodV: ?*anyopaque,
    CallStaticDoubleMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) jdouble,
    CallStaticVoidMethod: ?*anyopaque,
    CallStaticVoidMethodV: ?*anyopaque,
    CallStaticVoidMethodA: ?*const fn(*JNIEnv, jclass, jmethodID, [*c]const jvalue) callconv(.c) void,
    GetStaticFieldID: ?*const fn(*JNIEnv, jclass, [*c]const u8, [*c]const u8) callconv(.c) jfieldID,
    GetStaticObjectField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jobject,
    GetStaticBooleanField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jboolean,
    GetStaticByteField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jbyte,
    GetStaticCharField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jchar,
    GetStaticShortField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jshort,
    GetStaticIntField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jint,
    GetStaticLongField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jlong,
    GetStaticFloatField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jfloat,
    GetStaticDoubleField: ?*const fn(*JNIEnv, jclass, jfieldID) callconv(.c) jdouble,
    SetStaticObjectField: ?*const fn(*JNIEnv, jclass, jfieldID, jobject) callconv(.c) void,
    SetStaticBooleanField: ?*const fn(*JNIEnv, jclass, jfieldID, jboolean) callconv(.c) void,
    SetStaticByteField: ?*const fn(*JNIEnv, jclass, jfieldID, jbyte) callconv(.c) void,
    SetStaticCharField: ?*const fn(*JNIEnv, jclass, jfieldID, jchar) callconv(.c) void,
    SetStaticShortField: ?*const fn(*JNIEnv, jclass, jfieldID, jshort) callconv(.c) void,
    SetStaticIntField: ?*const fn(*JNIEnv, jclass, jfieldID, jint) callconv(.c) void,
    SetStaticLongField: ?*const fn(*JNIEnv, jclass, jfieldID, jlong) callconv(.c) void,
    SetStaticFloatField: ?*const fn(*JNIEnv, jclass, jfieldID, jfloat) callconv(.c) void,
    SetStaticDoubleField: ?*const fn(*JNIEnv, jclass, jfieldID, jdouble) callconv(.c) void,
    NewString: ?*const fn(*JNIEnv, [*c]const jchar, jsize) callconv(.c) jstring,
    GetStringLength: ?*const fn(*JNIEnv, jstring) callconv(.c) jsize,
    GetStringChars: ?*const fn(*JNIEnv, jstring, [*c]jboolean) callconv(.c) [*c]const jchar,
    ReleaseStringChars: ?*const fn(*JNIEnv, jstring, [*c]const jchar) callconv(.c) void,
    NewStringUTF: ?*const fn(*JNIEnv, [*c]const u8) callconv(.c) jstring,
    GetStringUTFLength: ?*const fn(*JNIEnv, jstring) callconv(.c) jsize,
    GetStringUTFChars: ?*const fn(*JNIEnv, jstring, [*c]jboolean) callconv(.c) [*c]const u8,
    ReleaseStringUTFChars: ?*const fn(*JNIEnv, jstring, [*c]const u8) callconv(.c) void,
    GetArrayLength: ?*const fn(*JNIEnv, jarray) callconv(.c) jsize,
    NewObjectArray: ?*const fn(*JNIEnv, jsize, jclass, jobject) callconv(.c) jobjectArray,
    GetObjectArrayElement: ?*const fn(*JNIEnv, jobjectArray, jsize) callconv(.c) jobject,
    SetObjectArrayElement: ?*const fn(*JNIEnv, jobjectArray, jsize, jobject) callconv(.c) void,
    NewBooleanArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jbooleanArray,
    NewByteArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jbyteArray,
    NewCharArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jcharArray,
    NewShortArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jshortArray,
    NewIntArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jintArray,
    NewLongArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jlongArray,
    NewFloatArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jfloatArray,
    NewDoubleArray: ?*const fn(*JNIEnv, jsize) callconv(.c) jdoubleArray,
    GetBooleanArrayElements: ?*const fn(*JNIEnv, jbooleanArray, [*c]jboolean) callconv(.c) [*c]jboolean,
    GetByteArrayElements: ?*const fn(*JNIEnv, jbyteArray, [*c]jboolean) callconv(.c) [*c]jbyte,
    GetCharArrayElements: ?*const fn(*JNIEnv, jcharArray, [*c]jboolean) callconv(.c) [*c]jchar,
    GetShortArrayElements: ?*const fn(*JNIEnv, jshortArray, [*c]jboolean) callconv(.c) [*c]jshort,
    GetIntArrayElements: ?*const fn(*JNIEnv, jintArray, [*c]jboolean) callconv(.c) [*c]jint,
    GetLongArrayElements: ?*const fn(*JNIEnv, jlongArray, [*c]jboolean) callconv(.c) [*c]jlong,
    GetFloatArrayElements: ?*const fn(*JNIEnv, jfloatArray, [*c]jboolean) callconv(.c) [*c]jfloat,
    GetDoubleArrayElements: ?*const fn(*JNIEnv, jdoubleArray, [*c]jboolean) callconv(.c) [*c]jdouble,
    ReleaseBooleanArrayElements: ?*const fn(*JNIEnv, jbooleanArray, [*c]jboolean, jint) callconv(.c) void,
    ReleaseByteArrayElements: ?*const fn(*JNIEnv, jbyteArray, [*c]jbyte, jint) callconv(.c) void,
    ReleaseCharArrayElements: ?*const fn(*JNIEnv, jcharArray, [*c]jchar, jint) callconv(.c) void,
    ReleaseShortArrayElements: ?*const fn(*JNIEnv, jshortArray, [*c]jshort, jint) callconv(.c) void,
    ReleaseIntArrayElements: ?*const fn(*JNIEnv, jintArray, [*c]jint, jint) callconv(.c) void,
    ReleaseLongArrayElements: ?*const fn(*JNIEnv, jlongArray, [*c]jlong, jint) callconv(.c) void,
    ReleaseFloatArrayElements: ?*const fn(*JNIEnv, jfloatArray, [*c]jfloat, jint) callconv(.c) void,
    ReleaseDoubleArrayElements: ?*const fn(*JNIEnv, jdoubleArray, [*c]jdouble, jint) callconv(.c) void,
    GetBooleanArrayRegion: ?*const fn(*JNIEnv, jbooleanArray, jsize, jsize, [*c]jboolean) callconv(.c) void,
    GetByteArrayRegion: ?*const fn(*JNIEnv, jbyteArray, jsize, jsize, [*c]jbyte) callconv(.c) void,
    GetCharArrayRegion: ?*const fn(*JNIEnv, jcharArray, jsize, jsize, [*c]jchar) callconv(.c) void,
    GetShortArrayRegion: ?*const fn(*JNIEnv, jshortArray, jsize, jsize, [*c]jshort) callconv(.c) void,
    GetIntArrayRegion: ?*const fn(*JNIEnv, jintArray, jsize, jsize, [*c]jint) callconv(.c) void,
    GetLongArrayRegion: ?*const fn(*JNIEnv, jlongArray, jsize, jsize, [*c]jlong) callconv(.c) void,
    GetFloatArrayRegion: ?*const fn(*JNIEnv, jfloatArray, jsize, jsize, [*c]jfloat) callconv(.c) void,
    GetDoubleArrayRegion: ?*const fn(*JNIEnv, jdoubleArray, jsize, jsize, [*c]jdouble) callconv(.c) void,
    SetBooleanArrayRegion: ?*const fn(*JNIEnv, jbooleanArray, jsize, jsize, [*c]const jboolean) callconv(.c) void,
    SetByteArrayRegion: ?*const fn(*JNIEnv, jbyteArray, jsize, jsize, [*c]const jbyte) callconv(.c) void,
    SetCharArrayRegion: ?*const fn(*JNIEnv, jcharArray, jsize, jsize, [*c]const jchar) callconv(.c) void,
    SetShortArrayRegion: ?*const fn(*JNIEnv, jshortArray, jsize, jsize, [*c]const jshort) callconv(.c) void,
    SetIntArrayRegion: ?*const fn(*JNIEnv, jintArray, jsize, jsize, [*c]const jint) callconv(.c) void,
    SetLongArrayRegion: ?*const fn(*JNIEnv, jlongArray, jsize, jsize, [*c]const jlong) callconv(.c) void,
    SetFloatArrayRegion: ?*const fn(*JNIEnv, jfloatArray, jsize, jsize, [*c]const jfloat) callconv(.c) void,
    SetDoubleArrayRegion: ?*const fn(*JNIEnv, jdoubleArray, jsize, jsize, [*c]const jdouble) callconv(.c) void,
    RegisterNatives: ?*const fn(*JNIEnv, jclass, [*c]const JNINativeMethod, jint) callconv(.c) jint,
    UnregisterNatives: ?*const fn(*JNIEnv, jclass) callconv(.c) jint,
    MonitorEnter: ?*const fn(*JNIEnv, jobject) callconv(.c) jint,
    MonitorExit: ?*const fn(*JNIEnv, jobject) callconv(.c) jint,
    GetJavaVM: ?*const fn(*JNIEnv, [*c]?*JavaVM) callconv(.c) jint,
    GetStringRegion: ?*const fn(*JNIEnv, jstring, jsize, jsize, [*c]jchar) callconv(.c) void,
    GetStringUTFRegion: ?*const fn(*JNIEnv, jstring, jsize, jsize, [*c]u8) callconv(.c) void,
    GetPrimitiveArrayCritical: ?*const fn(*JNIEnv, jarray, [*c]jboolean) callconv(.c) ?*anyopaque,
    ReleasePrimitiveArrayCritical: ?*const fn(*JNIEnv, jarray, ?*anyopaque, jint) callconv(.c) void,
    GetStringCritical: ?*const fn(*JNIEnv, jstring, [*c]jboolean) callconv(.c) [*c]const jchar,
    ReleaseStringCritical: ?*const fn(*JNIEnv, jstring, [*c]const jchar) callconv(.c) void,
    NewWeakGlobalRef: ?*const fn(*JNIEnv, jobject) callconv(.c) jweak,
    DeleteWeakGlobalRef: ?*const fn(*JNIEnv, jweak) callconv(.c) void,
    ExceptionCheck: ?*const fn(*JNIEnv) callconv(.c) jboolean,
    NewDirectByteBuffer: ?*const fn(*JNIEnv, ?*anyopaque, jlong) callconv(.c) jobject,
    GetDirectBufferAddress: ?*const fn(*JNIEnv, jobject) callconv(.c) ?*anyopaque,
    GetDirectBufferCapacity: ?*const fn(*JNIEnv, jobject) callconv(.c) jlong,
    GetObjectRefType: ?*const fn(*JNIEnv, jobject) callconv(.c) jobjectRefType,
};

pub const JNIInvokeInterface = extern struct {
    reserved0: ?*anyopaque,
    reserved1: ?*anyopaque,
    reserved2: ?*anyopaque,
    DestroyJavaVM: ?*const fn(*JavaVM) callconv(.c) jint,
    AttachCurrentThread: ?*const fn(*JavaVM, *?*JNIEnv, ?*anyopaque) callconv(.c) jint,
    DetachCurrentThread: ?*const fn(*JavaVM) callconv(.c) jint,
    GetEnv: ?*const fn(*JavaVM, *?*anyopaque, jint) callconv(.c) jint,
    AttachCurrentThreadAsDaemon: ?*const fn(*JavaVM, *?*JNIEnv, ?*anyopaque) callconv(.c) jint,
};

// -- Vtable access ----------------------------------------------------------
// JNIEnv* is a pointer-to-pointer-to-JNINativeInterface; JavaVM* is a
// pointer-to-pointer-to-JNIInvokeInterface.

inline fn envTable(env: *JNIEnv) *const JNINativeInterface {
    return @as(*const *const JNINativeInterface, @ptrCast(@alignCast(env))).*;
}
inline fn vmTable(vm: *JavaVM) *const JNIInvokeInterface {
    return @as(*const *const JNIInvokeInterface, @ptrCast(@alignCast(vm))).*;
}

// -- Thin wrappers used by the typed bridge ---------------------------------

pub inline fn findClass(env: *JNIEnv, name: [*:0]const u8) jclass {
    return envTable(env).FindClass.?(env, name);
}
pub inline fn getMethodID(env: *JNIEnv, clazz: jclass, name: [*:0]const u8, sig: [*:0]const u8) jmethodID {
    return envTable(env).GetMethodID.?(env, clazz, name, sig);
}
pub inline fn getStaticMethodID(env: *JNIEnv, clazz: jclass, name: [*:0]const u8, sig: [*:0]const u8) jmethodID {
    return envTable(env).GetStaticMethodID.?(env, clazz, name, sig);
}
pub inline fn deleteLocalRef(env: *JNIEnv, obj: jobject) void {
    envTable(env).DeleteLocalRef.?(env, obj);
}
pub inline fn exceptionCheck(env: *JNIEnv) bool {
    return envTable(env).ExceptionCheck.?(env) != 0;
}
pub inline fn exceptionClear(env: *JNIEnv) void {
    envTable(env).ExceptionClear.?(env);
}
pub inline fn exceptionDescribe(env: *JNIEnv) void {
    envTable(env).ExceptionDescribe.?(env);
}
pub inline fn newStringUTF(env: *JNIEnv, s: [*:0]const u8) jstring {
    return envTable(env).NewStringUTF.?(env, s);
}
pub inline fn getStringUTFChars(env: *JNIEnv, s: jstring) [*c]const u8 {
    return envTable(env).GetStringUTFChars.?(env, s, null);
}
pub inline fn releaseStringUTFChars(env: *JNIEnv, s: jstring, chars: [*c]const u8) void {
    envTable(env).ReleaseStringUTFChars.?(env, s, chars);
}

pub inline fn attachCurrentThread(vm: *JavaVM, out_env: *?*JNIEnv) jint {
    return vmTable(vm).AttachCurrentThread.?(vm, out_env, null);
}
pub inline fn detachCurrentThread(vm: *JavaVM) jint {
    return vmTable(vm).DetachCurrentThread.?(vm);
}
pub inline fn getEnv(vm: *JavaVM, out_env: *?*anyopaque, version: jint) jint {
    return vmTable(vm).GetEnv.?(vm, out_env, version);
}

// -- Comptime signature builder ---------------------------------------------

/// Returns the one-character JNI descriptor for a primitive Zig type,
/// or the full "Lfoo/bar;" string if `T` is a struct with `pub const java_sig`.
pub fn sigOf(comptime T: type) []const u8 {
    return switch (T) {
        void => "V",
        bool, u8 => "Z", // u8 = jboolean
        i8 => "B", // = jbyte
        u16 => "C", // = jchar
        i16 => "S", // = jshort
        i32 => "I", // = jint
        i64 => "J", // = jlong
        f32 => "F", // = jfloat
        f64 => "D", // = jdouble
        else => blk: {
            const info = @typeInfo(T);
            if (info == .optional and info.optional.child == *anyopaque) break :blk "Ljava/lang/Object;";
            if (T == jobject) break :blk "Ljava/lang/Object;";
            if (@hasDecl(T, "java_sig")) break :blk @as([]const u8, T.java_sig);
            @compileError("jni.sigOf: unsupported Zig type " ++ @typeName(T));
        },
    };
}

/// Builds "(args...)ret" for the function-type F.
pub fn sigOfFn(comptime F: type) [:0]const u8 {
    const fi = @typeInfo(F).@"fn";
    comptime var s: []const u8 = "(";
    inline for (fi.params) |p| s = s ++ sigOf(p.type.?);
    s = s ++ ")" ++ sigOf(fi.return_type.?);
    // Ensure a null terminator for use with [*:0]const u8.
    return (s ++ "\x00")[0..s.len :0];
}

// -- Typed dispatch ---------------------------------------------------------

fn dispatchInstance(comptime Ret: type) @TypeOf(&_dispatchVoid) {
    _ = Ret;
    @compileError("not used");
}

fn _dispatchVoid() void {}

/// Invoke a method by its cached jmethodID. `args` is a tuple matching `F`'s parameters.
/// Chooses the correct Call*MethodA via comptime on `Ret`.
pub fn callInstanceByID(comptime F: type, env: *JNIEnv, obj: jobject, mid: jmethodID, args: anytype) @typeInfo(F).@"fn".return_type.? {
    const Ret = @typeInfo(F).@"fn".return_type.?;
    var jargs: [@typeInfo(F).@"fn".params.len]jvalue = undefined;
    inline for (@typeInfo(F).@"fn".params, 0..) |p, i| {
        jargs[i] = toJValue(p.type.?, args[i]);
    }
    const tbl = envTable(env);
    const argp: [*c]const jvalue = if (jargs.len == 0) null else &jargs;
    return switch (Ret) {
        void => tbl.CallVoidMethodA.?(env, obj, mid, argp),
        bool, u8 => tbl.CallBooleanMethodA.?(env, obj, mid, argp) != 0,
        i8 => tbl.CallByteMethodA.?(env, obj, mid, argp),
        u16 => tbl.CallCharMethodA.?(env, obj, mid, argp),
        i16 => tbl.CallShortMethodA.?(env, obj, mid, argp),
        i32 => tbl.CallIntMethodA.?(env, obj, mid, argp),
        i64 => tbl.CallLongMethodA.?(env, obj, mid, argp),
        f32 => tbl.CallFloatMethodA.?(env, obj, mid, argp),
        f64 => tbl.CallDoubleMethodA.?(env, obj, mid, argp),
        else => objectReturn(Ret, tbl.CallObjectMethodA.?(env, obj, mid, argp)),
    };
}

pub fn callStaticByID(comptime F: type, env: *JNIEnv, clazz: jclass, mid: jmethodID, args: anytype) @typeInfo(F).@"fn".return_type.? {
    const Ret = @typeInfo(F).@"fn".return_type.?;
    var jargs: [@typeInfo(F).@"fn".params.len]jvalue = undefined;
    inline for (@typeInfo(F).@"fn".params, 0..) |p, i| {
        jargs[i] = toJValue(p.type.?, args[i]);
    }
    const tbl = envTable(env);
    const argp: [*c]const jvalue = if (jargs.len == 0) null else &jargs;
    return switch (Ret) {
        void => tbl.CallStaticVoidMethodA.?(env, clazz, mid, argp),
        bool, u8 => tbl.CallStaticBooleanMethodA.?(env, clazz, mid, argp) != 0,
        i8 => tbl.CallStaticByteMethodA.?(env, clazz, mid, argp),
        u16 => tbl.CallStaticCharMethodA.?(env, clazz, mid, argp),
        i16 => tbl.CallStaticShortMethodA.?(env, clazz, mid, argp),
        i32 => tbl.CallStaticIntMethodA.?(env, clazz, mid, argp),
        i64 => tbl.CallStaticLongMethodA.?(env, clazz, mid, argp),
        f32 => tbl.CallStaticFloatMethodA.?(env, clazz, mid, argp),
        f64 => tbl.CallStaticDoubleMethodA.?(env, clazz, mid, argp),
        else => objectReturn(Ret, tbl.CallStaticObjectMethodA.?(env, clazz, mid, argp)),
    };
}

fn toJValue(comptime T: type, v: T) jvalue {
    return switch (T) {
        void => unreachable,
        bool => .{ .z = if (v) 1 else 0 },
        u8 => .{ .z = v },
        i8 => .{ .b = v },
        u16 => .{ .c = v },
        i16 => .{ .s = v },
        i32 => .{ .i = v },
        i64 => .{ .j = v },
        f32 => .{ .f = v },
        f64 => .{ .d = v },
        else => blk: {
            if (comptime isClassRef(T)) break :blk .{ .l = v.handle };
            break :blk .{ .l = v };
        },
    };
}

/// A struct opts into being a typed Java object reference by declaring
///     pub const java_sig = "Lfoo/bar/Baz;";
/// and exposing a single field `handle: jobject`.
pub fn isClassRef(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    return @hasDecl(T, "java_sig");
}

/// Convenience: declare a typed handle to a Java class.
///     const Vibrator = jni.ClassRef("Landroid/os/Vibrator;");
pub fn ClassRef(comptime sig: [:0]const u8) type {
    return extern struct {
        handle: jobject,
        pub const java_sig = sig;
    };
}

inline fn objectReturn(comptime Ret: type, raw: jobject) Ret {
    if (Ret == jobject) return raw;
    if (comptime isClassRef(Ret)) return .{ .handle = raw };
    @compileError("cannot construct " ++ @typeName(Ret) ++ " from jobject");
}

/// One-shot instance call: looks up class + method, invokes, does NOT delete the class ref.
/// Prefer `Method(...)` for hot paths to avoid the per-call lookup.
pub fn call(comptime F: type, env: *JNIEnv, obj: jobject, comptime class_name: [:0]const u8, comptime method_name: [:0]const u8, args: anytype) !@typeInfo(F).@"fn".return_type.? {
    const sig = comptime sigOfFn(F);
    const clazz = findClass(env, class_name.ptr) orelse return error.ClassNotFound;
    defer deleteLocalRef(env, clazz);
    const mid = getMethodID(env, clazz, method_name.ptr, sig.ptr) orelse return error.MethodNotFound;
    const result = callInstanceByID(F, env, obj, mid, args);
    if (exceptionCheck(env)) {
        exceptionDescribe(env);
        exceptionClear(env);
        return error.JavaException;
    }
    return result;
}

pub fn callStatic(comptime F: type, env: *JNIEnv, comptime class_name: [:0]const u8, comptime method_name: [:0]const u8, args: anytype) !@typeInfo(F).@"fn".return_type.? {
    const sig = comptime sigOfFn(F);
    const clazz = findClass(env, class_name.ptr) orelse return error.ClassNotFound;
    defer deleteLocalRef(env, clazz);
    const mid = getStaticMethodID(env, clazz, method_name.ptr, sig.ptr) orelse return error.MethodNotFound;
    const result = callStaticByID(F, env, clazz, mid, args);
    if (exceptionCheck(env)) {
        exceptionDescribe(env);
        exceptionClear(env);
        return error.JavaException;
    }
    return result;
}

/// Cached method handle. Resolve once; call many times.
pub fn Method(comptime class_name: [:0]const u8, comptime method_name: [:0]const u8, comptime F: type) type {
    return struct {
        clazz: jclass = null,
        mid: jmethodID = null,

        const Self = @This();
        const Ret = @typeInfo(F).@"fn".return_type.?;

        pub fn resolve(self: *Self, env: *JNIEnv) !void {
            const local = findClass(env, class_name.ptr) orelse return error.ClassNotFound;
            // Promote to global ref so the cached class survives local-frame pops.
            const global = envTable(env).NewGlobalRef.?(env, local) orelse {
                deleteLocalRef(env, local);
                return error.NoGlobalRef;
            };
            deleteLocalRef(env, local);
            const sig = comptime sigOfFn(F);
            const mid = getMethodID(env, global, method_name.ptr, sig.ptr) orelse {
                envTable(env).DeleteGlobalRef.?(env, global);
                return error.MethodNotFound;
            };
            self.clazz = global;
            self.mid = mid;
        }

        pub fn release(self: *Self, env: *JNIEnv) void {
            if (self.clazz) |c| envTable(env).DeleteGlobalRef.?(env, c);
            self.clazz = null;
            self.mid = null;
        }

        pub fn call(self: *const Self, env: *JNIEnv, obj: jobject, args: anytype) !Ret {
            const result = callInstanceByID(F, env, obj, self.mid, args);
            if (exceptionCheck(env)) {
                exceptionDescribe(env);
                exceptionClear(env);
                return error.JavaException;
            }
            return result;
        }
    };
}
