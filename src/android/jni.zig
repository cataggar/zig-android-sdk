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
/// Typed variant that returns a `jni.String` handle — use this when
/// passing strings to call/callStatic so the signature comes out as
/// `Ljava/lang/String;` rather than the generic `Ljava/lang/Object;`.
pub inline fn newString(env: *JNIEnv, s: [*:0]const u8) String {
    return .{ .handle = envTable(env).NewStringUTF.?(env, s) };
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

// ===========================================================================
// Issue #2: full JNINativeInterface wrapper coverage. The wrappers below
// follow the existing `envTable(env).Name.?(env, …)` pattern so every field
// in the struct has a Zig-friendly entry point.
// ===========================================================================

// -- ABI sanity -------------------------------------------------------------

comptime {
    // `JNINativeInterface` is 233 pointer-sized slots (4 reserved + 229 fn
    // pointers per jni.h). `JNIInvokeInterface` is 8 pointer-sized slots
    // (3 reserved + 5 fn pointers). Both are expected to be layout-compatible
    // with a `void*[N]` on every ABI.
    std.debug.assert(@sizeOf(JNINativeInterface) == 233 * @sizeOf(usize));
    std.debug.assert(@sizeOf(JNIInvokeInterface) == 8 * @sizeOf(usize));
    std.debug.assert(@alignOf(JNINativeInterface) == @alignOf(usize));
    std.debug.assert(@alignOf(JNIInvokeInterface) == @alignOf(usize));
}

test "JNINativeInterface ABI size" {
    try std.testing.expectEqual(233 * @sizeOf(usize), @sizeOf(JNINativeInterface));
    try std.testing.expectEqual(8 * @sizeOf(usize), @sizeOf(JNIInvokeInterface));
    try std.testing.expectEqual(@alignOf(usize), @alignOf(JNINativeInterface));
    try std.testing.expectEqual(@alignOf(usize), @alignOf(JNIInvokeInterface));
}

// -- Misc env helpers -------------------------------------------------------

pub inline fn getVersion(env: *JNIEnv) jint {
    return envTable(env).GetVersion.?(env);
}

/// Fetch the `*JavaVM` attached to `env`. Returns `error.GetJavaVMFailed` on
/// a non-zero status from JNI.
pub fn getJavaVM(env: *JNIEnv) !*JavaVM {
    var out: ?*JavaVM = null;
    const rc = envTable(env).GetJavaVM.?(env, @as([*c]?*JavaVM, @ptrCast(&out)));
    if (rc != JNI_OK) return error.GetJavaVMFailed;
    return out orelse error.GetJavaVMFailed;
}

pub inline fn defineClass(env: *JNIEnv, name: [*:0]const u8, loader: jobject, buf: []const u8) jclass {
    return envTable(env).DefineClass.?(env, name, loader, @as([*c]const jbyte, @ptrCast(buf.ptr)), @as(jsize, @intCast(buf.len)));
}

// -- Reflection -------------------------------------------------------------

pub inline fn fromReflectedMethod(env: *JNIEnv, method: jobject) jmethodID {
    return envTable(env).FromReflectedMethod.?(env, method);
}
pub inline fn fromReflectedField(env: *JNIEnv, field: jobject) jfieldID {
    return envTable(env).FromReflectedField.?(env, field);
}
pub inline fn toReflectedMethod(env: *JNIEnv, clazz: jclass, mid: jmethodID, is_static: bool) jobject {
    return envTable(env).ToReflectedMethod.?(env, clazz, mid, @intFromBool(is_static));
}
pub inline fn toReflectedField(env: *JNIEnv, clazz: jclass, fid: jfieldID, is_static: bool) jobject {
    return envTable(env).ToReflectedField.?(env, clazz, fid, @intFromBool(is_static));
}

// -- Global / weak / local refs ---------------------------------------------

pub inline fn newGlobalRef(env: *JNIEnv, obj: jobject) jobject {
    return envTable(env).NewGlobalRef.?(env, obj);
}
pub inline fn deleteGlobalRef(env: *JNIEnv, obj: jobject) void {
    envTable(env).DeleteGlobalRef.?(env, obj);
}
pub inline fn newWeakGlobalRef(env: *JNIEnv, obj: jobject) jweak {
    return envTable(env).NewWeakGlobalRef.?(env, obj);
}
pub inline fn deleteWeakGlobalRef(env: *JNIEnv, wref: jweak) void {
    envTable(env).DeleteWeakGlobalRef.?(env, wref);
}
pub inline fn newLocalRef(env: *JNIEnv, obj: jobject) jobject {
    return envTable(env).NewLocalRef.?(env, obj);
}
pub inline fn ensureLocalCapacity(env: *JNIEnv, capacity: jint) jint {
    return envTable(env).EnsureLocalCapacity.?(env, capacity);
}
pub inline fn pushLocalFrame(env: *JNIEnv, capacity: jint) jint {
    return envTable(env).PushLocalFrame.?(env, capacity);
}
pub inline fn popLocalFrame(env: *JNIEnv, result: jobject) jobject {
    return envTable(env).PopLocalFrame.?(env, result);
}
pub inline fn isSameObject(env: *JNIEnv, a: jobject, b: jobject) bool {
    return envTable(env).IsSameObject.?(env, a, b) != 0;
}

// -- Object / class / reflection --------------------------------------------

pub inline fn getObjectClass(env: *JNIEnv, obj: jobject) jclass {
    return envTable(env).GetObjectClass.?(env, obj);
}
pub inline fn getSuperclass(env: *JNIEnv, clazz: jclass) jclass {
    return envTable(env).GetSuperclass.?(env, clazz);
}
pub inline fn isInstanceOf(env: *JNIEnv, obj: jobject, clazz: jclass) bool {
    return envTable(env).IsInstanceOf.?(env, obj, clazz) != 0;
}
pub inline fn isAssignableFrom(env: *JNIEnv, sub: jclass, sup: jclass) bool {
    return envTable(env).IsAssignableFrom.?(env, sub, sup) != 0;
}
pub inline fn getObjectRefType(env: *JNIEnv, obj: jobject) jobjectRefType {
    return envTable(env).GetObjectRefType.?(env, obj);
}
pub inline fn allocObject(env: *JNIEnv, clazz: jclass) jobject {
    return envTable(env).AllocObject.?(env, clazz);
}
pub inline fn newObjectA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jobject {
    return envTable(env).NewObjectA.?(env, clazz, mid, args);
}

// -- Exceptions -------------------------------------------------------------

pub inline fn throw(env: *JNIEnv, thr: jthrowable) jint {
    return envTable(env).Throw.?(env, thr);
}
pub inline fn throwNew(env: *JNIEnv, clazz: jclass, msg: [*:0]const u8) jint {
    return envTable(env).ThrowNew.?(env, clazz, msg);
}
pub inline fn exceptionOccurred(env: *JNIEnv) jthrowable {
    return envTable(env).ExceptionOccurred.?(env);
}
pub inline fn fatalError(env: *JNIEnv, msg: [*:0]const u8) noreturn {
    envTable(env).FatalError.?(env, msg);
    unreachable;
}

// -- Field access -----------------------------------------------------------

pub inline fn getFieldID(env: *JNIEnv, clazz: jclass, name: [*:0]const u8, sig: [*:0]const u8) jfieldID {
    return envTable(env).GetFieldID.?(env, clazz, name, sig);
}
pub inline fn getStaticFieldID(env: *JNIEnv, clazz: jclass, name: [*:0]const u8, sig: [*:0]const u8) jfieldID {
    return envTable(env).GetStaticFieldID.?(env, clazz, name, sig);
}

pub inline fn getObjectField(env: *JNIEnv, obj: jobject, fid: jfieldID) jobject {
    return envTable(env).GetObjectField.?(env, obj, fid);
}
pub inline fn getBooleanField(env: *JNIEnv, obj: jobject, fid: jfieldID) bool {
    return envTable(env).GetBooleanField.?(env, obj, fid) != 0;
}
pub inline fn getByteField(env: *JNIEnv, obj: jobject, fid: jfieldID) jbyte {
    return envTable(env).GetByteField.?(env, obj, fid);
}
pub inline fn getCharField(env: *JNIEnv, obj: jobject, fid: jfieldID) jchar {
    return envTable(env).GetCharField.?(env, obj, fid);
}
pub inline fn getShortField(env: *JNIEnv, obj: jobject, fid: jfieldID) jshort {
    return envTable(env).GetShortField.?(env, obj, fid);
}
pub inline fn getIntField(env: *JNIEnv, obj: jobject, fid: jfieldID) jint {
    return envTable(env).GetIntField.?(env, obj, fid);
}
pub inline fn getLongField(env: *JNIEnv, obj: jobject, fid: jfieldID) jlong {
    return envTable(env).GetLongField.?(env, obj, fid);
}
pub inline fn getFloatField(env: *JNIEnv, obj: jobject, fid: jfieldID) jfloat {
    return envTable(env).GetFloatField.?(env, obj, fid);
}
pub inline fn getDoubleField(env: *JNIEnv, obj: jobject, fid: jfieldID) jdouble {
    return envTable(env).GetDoubleField.?(env, obj, fid);
}

pub inline fn setObjectField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jobject) void {
    envTable(env).SetObjectField.?(env, obj, fid, v);
}
pub inline fn setBooleanField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: bool) void {
    envTable(env).SetBooleanField.?(env, obj, fid, @intFromBool(v));
}
pub inline fn setByteField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jbyte) void {
    envTable(env).SetByteField.?(env, obj, fid, v);
}
pub inline fn setCharField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jchar) void {
    envTable(env).SetCharField.?(env, obj, fid, v);
}
pub inline fn setShortField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jshort) void {
    envTable(env).SetShortField.?(env, obj, fid, v);
}
pub inline fn setIntField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jint) void {
    envTable(env).SetIntField.?(env, obj, fid, v);
}
pub inline fn setLongField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jlong) void {
    envTable(env).SetLongField.?(env, obj, fid, v);
}
pub inline fn setFloatField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jfloat) void {
    envTable(env).SetFloatField.?(env, obj, fid, v);
}
pub inline fn setDoubleField(env: *JNIEnv, obj: jobject, fid: jfieldID, v: jdouble) void {
    envTable(env).SetDoubleField.?(env, obj, fid, v);
}

pub inline fn getStaticObjectField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jobject {
    return envTable(env).GetStaticObjectField.?(env, clazz, fid);
}
pub inline fn getStaticBooleanField(env: *JNIEnv, clazz: jclass, fid: jfieldID) bool {
    return envTable(env).GetStaticBooleanField.?(env, clazz, fid) != 0;
}
pub inline fn getStaticByteField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jbyte {
    return envTable(env).GetStaticByteField.?(env, clazz, fid);
}
pub inline fn getStaticCharField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jchar {
    return envTable(env).GetStaticCharField.?(env, clazz, fid);
}
pub inline fn getStaticShortField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jshort {
    return envTable(env).GetStaticShortField.?(env, clazz, fid);
}
pub inline fn getStaticIntField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jint {
    return envTable(env).GetStaticIntField.?(env, clazz, fid);
}
pub inline fn getStaticLongField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jlong {
    return envTable(env).GetStaticLongField.?(env, clazz, fid);
}
pub inline fn getStaticFloatField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jfloat {
    return envTable(env).GetStaticFloatField.?(env, clazz, fid);
}
pub inline fn getStaticDoubleField(env: *JNIEnv, clazz: jclass, fid: jfieldID) jdouble {
    return envTable(env).GetStaticDoubleField.?(env, clazz, fid);
}

pub inline fn setStaticObjectField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jobject) void {
    envTable(env).SetStaticObjectField.?(env, clazz, fid, v);
}
pub inline fn setStaticBooleanField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: bool) void {
    envTable(env).SetStaticBooleanField.?(env, clazz, fid, @intFromBool(v));
}
pub inline fn setStaticByteField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jbyte) void {
    envTable(env).SetStaticByteField.?(env, clazz, fid, v);
}
pub inline fn setStaticCharField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jchar) void {
    envTable(env).SetStaticCharField.?(env, clazz, fid, v);
}
pub inline fn setStaticShortField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jshort) void {
    envTable(env).SetStaticShortField.?(env, clazz, fid, v);
}
pub inline fn setStaticIntField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jint) void {
    envTable(env).SetStaticIntField.?(env, clazz, fid, v);
}
pub inline fn setStaticLongField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jlong) void {
    envTable(env).SetStaticLongField.?(env, clazz, fid, v);
}
pub inline fn setStaticFloatField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jfloat) void {
    envTable(env).SetStaticFloatField.?(env, clazz, fid, v);
}
pub inline fn setStaticDoubleField(env: *JNIEnv, clazz: jclass, fid: jfieldID, v: jdouble) void {
    envTable(env).SetStaticDoubleField.?(env, clazz, fid, v);
}

// -- Call*MethodA thin wrappers ---------------------------------------------

pub inline fn callObjectMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jobject {
    return envTable(env).CallObjectMethodA.?(env, obj, mid, args);
}
pub inline fn callBooleanMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) bool {
    return envTable(env).CallBooleanMethodA.?(env, obj, mid, args) != 0;
}
pub inline fn callByteMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jbyte {
    return envTable(env).CallByteMethodA.?(env, obj, mid, args);
}
pub inline fn callCharMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jchar {
    return envTable(env).CallCharMethodA.?(env, obj, mid, args);
}
pub inline fn callShortMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jshort {
    return envTable(env).CallShortMethodA.?(env, obj, mid, args);
}
pub inline fn callIntMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jint {
    return envTable(env).CallIntMethodA.?(env, obj, mid, args);
}
pub inline fn callLongMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jlong {
    return envTable(env).CallLongMethodA.?(env, obj, mid, args);
}
pub inline fn callFloatMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jfloat {
    return envTable(env).CallFloatMethodA.?(env, obj, mid, args);
}
pub inline fn callDoubleMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) jdouble {
    return envTable(env).CallDoubleMethodA.?(env, obj, mid, args);
}
pub inline fn callVoidMethodA(env: *JNIEnv, obj: jobject, mid: jmethodID, args: [*c]const jvalue) void {
    envTable(env).CallVoidMethodA.?(env, obj, mid, args);
}

pub inline fn callStaticObjectMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jobject {
    return envTable(env).CallStaticObjectMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticBooleanMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) bool {
    return envTable(env).CallStaticBooleanMethodA.?(env, clazz, mid, args) != 0;
}
pub inline fn callStaticByteMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jbyte {
    return envTable(env).CallStaticByteMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticCharMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jchar {
    return envTable(env).CallStaticCharMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticShortMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jshort {
    return envTable(env).CallStaticShortMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticIntMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jint {
    return envTable(env).CallStaticIntMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticLongMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jlong {
    return envTable(env).CallStaticLongMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticFloatMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jfloat {
    return envTable(env).CallStaticFloatMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticDoubleMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jdouble {
    return envTable(env).CallStaticDoubleMethodA.?(env, clazz, mid, args);
}
pub inline fn callStaticVoidMethodA(env: *JNIEnv, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) void {
    envTable(env).CallStaticVoidMethodA.?(env, clazz, mid, args);
}

pub inline fn callNonvirtualObjectMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jobject {
    return envTable(env).CallNonvirtualObjectMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualBooleanMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) bool {
    return envTable(env).CallNonvirtualBooleanMethodA.?(env, obj, clazz, mid, args) != 0;
}
pub inline fn callNonvirtualByteMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jbyte {
    return envTable(env).CallNonvirtualByteMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualCharMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jchar {
    return envTable(env).CallNonvirtualCharMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualShortMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jshort {
    return envTable(env).CallNonvirtualShortMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualIntMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jint {
    return envTable(env).CallNonvirtualIntMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualLongMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jlong {
    return envTable(env).CallNonvirtualLongMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualFloatMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jfloat {
    return envTable(env).CallNonvirtualFloatMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualDoubleMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) jdouble {
    return envTable(env).CallNonvirtualDoubleMethodA.?(env, obj, clazz, mid, args);
}
pub inline fn callNonvirtualVoidMethodA(env: *JNIEnv, obj: jobject, clazz: jclass, mid: jmethodID, args: [*c]const jvalue) void {
    envTable(env).CallNonvirtualVoidMethodA.?(env, obj, clazz, mid, args);
}

// -- Array APIs --------------------------------------------------------------

/// JNI array-release modes. `.commit_and_free` corresponds to the `0` mode
/// (copy back, then free). See JNI docs for `Release*ArrayElements`.
pub const ArrayReleaseMode = enum(jint) {
    commit_and_free = 0,
    commit = JNI_COMMIT,
    abort = JNI_ABORT,
};

pub inline fn getArrayLength(env: *JNIEnv, array: jarray) jsize {
    return envTable(env).GetArrayLength.?(env, array);
}
pub inline fn newObjectArray(env: *JNIEnv, len: jsize, element_clazz: jclass, initial: jobject) jobjectArray {
    return envTable(env).NewObjectArray.?(env, len, element_clazz, initial);
}
pub inline fn getObjectArrayElement(env: *JNIEnv, arr: jobjectArray, i: jsize) jobject {
    return envTable(env).GetObjectArrayElement.?(env, arr, i);
}
pub inline fn setObjectArrayElement(env: *JNIEnv, arr: jobjectArray, i: jsize, val: jobject) void {
    envTable(env).SetObjectArrayElement.?(env, arr, i, val);
}

pub inline fn newBooleanArray(env: *JNIEnv, len: jsize) jbooleanArray {
    return envTable(env).NewBooleanArray.?(env, len);
}
pub inline fn newByteArray(env: *JNIEnv, len: jsize) jbyteArray {
    return envTable(env).NewByteArray.?(env, len);
}
pub inline fn newCharArray(env: *JNIEnv, len: jsize) jcharArray {
    return envTable(env).NewCharArray.?(env, len);
}
pub inline fn newShortArray(env: *JNIEnv, len: jsize) jshortArray {
    return envTable(env).NewShortArray.?(env, len);
}
pub inline fn newIntArray(env: *JNIEnv, len: jsize) jintArray {
    return envTable(env).NewIntArray.?(env, len);
}
pub inline fn newLongArray(env: *JNIEnv, len: jsize) jlongArray {
    return envTable(env).NewLongArray.?(env, len);
}
pub inline fn newFloatArray(env: *JNIEnv, len: jsize) jfloatArray {
    return envTable(env).NewFloatArray.?(env, len);
}
pub inline fn newDoubleArray(env: *JNIEnv, len: jsize) jdoubleArray {
    return envTable(env).NewDoubleArray.?(env, len);
}

pub inline fn getBooleanArrayElements(env: *JNIEnv, arr: jbooleanArray, is_copy: ?*jboolean) [*c]jboolean {
    return envTable(env).GetBooleanArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getByteArrayElements(env: *JNIEnv, arr: jbyteArray, is_copy: ?*jboolean) [*c]jbyte {
    return envTable(env).GetByteArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getCharArrayElements(env: *JNIEnv, arr: jcharArray, is_copy: ?*jboolean) [*c]jchar {
    return envTable(env).GetCharArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getShortArrayElements(env: *JNIEnv, arr: jshortArray, is_copy: ?*jboolean) [*c]jshort {
    return envTable(env).GetShortArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getIntArrayElements(env: *JNIEnv, arr: jintArray, is_copy: ?*jboolean) [*c]jint {
    return envTable(env).GetIntArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getLongArrayElements(env: *JNIEnv, arr: jlongArray, is_copy: ?*jboolean) [*c]jlong {
    return envTable(env).GetLongArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getFloatArrayElements(env: *JNIEnv, arr: jfloatArray, is_copy: ?*jboolean) [*c]jfloat {
    return envTable(env).GetFloatArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn getDoubleArrayElements(env: *JNIEnv, arr: jdoubleArray, is_copy: ?*jboolean) [*c]jdouble {
    return envTable(env).GetDoubleArrayElements.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}

pub inline fn releaseBooleanArrayElements(env: *JNIEnv, arr: jbooleanArray, elems: [*c]jboolean, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseBooleanArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseByteArrayElements(env: *JNIEnv, arr: jbyteArray, elems: [*c]jbyte, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseByteArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseCharArrayElements(env: *JNIEnv, arr: jcharArray, elems: [*c]jchar, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseCharArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseShortArrayElements(env: *JNIEnv, arr: jshortArray, elems: [*c]jshort, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseShortArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseIntArrayElements(env: *JNIEnv, arr: jintArray, elems: [*c]jint, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseIntArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseLongArrayElements(env: *JNIEnv, arr: jlongArray, elems: [*c]jlong, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseLongArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseFloatArrayElements(env: *JNIEnv, arr: jfloatArray, elems: [*c]jfloat, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseFloatArrayElements.?(env, arr, elems, @intFromEnum(mode));
}
pub inline fn releaseDoubleArrayElements(env: *JNIEnv, arr: jdoubleArray, elems: [*c]jdouble, mode: ArrayReleaseMode) void {
    envTable(env).ReleaseDoubleArrayElements.?(env, arr, elems, @intFromEnum(mode));
}

pub inline fn getBooleanArrayRegion(env: *JNIEnv, arr: jbooleanArray, start: jsize, len: jsize, buf: [*c]jboolean) void {
    envTable(env).GetBooleanArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getByteArrayRegion(env: *JNIEnv, arr: jbyteArray, start: jsize, len: jsize, buf: [*c]jbyte) void {
    envTable(env).GetByteArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getCharArrayRegion(env: *JNIEnv, arr: jcharArray, start: jsize, len: jsize, buf: [*c]jchar) void {
    envTable(env).GetCharArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getShortArrayRegion(env: *JNIEnv, arr: jshortArray, start: jsize, len: jsize, buf: [*c]jshort) void {
    envTable(env).GetShortArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getIntArrayRegion(env: *JNIEnv, arr: jintArray, start: jsize, len: jsize, buf: [*c]jint) void {
    envTable(env).GetIntArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getLongArrayRegion(env: *JNIEnv, arr: jlongArray, start: jsize, len: jsize, buf: [*c]jlong) void {
    envTable(env).GetLongArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getFloatArrayRegion(env: *JNIEnv, arr: jfloatArray, start: jsize, len: jsize, buf: [*c]jfloat) void {
    envTable(env).GetFloatArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn getDoubleArrayRegion(env: *JNIEnv, arr: jdoubleArray, start: jsize, len: jsize, buf: [*c]jdouble) void {
    envTable(env).GetDoubleArrayRegion.?(env, arr, start, len, buf);
}

pub inline fn setBooleanArrayRegion(env: *JNIEnv, arr: jbooleanArray, start: jsize, len: jsize, buf: [*c]const jboolean) void {
    envTable(env).SetBooleanArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setByteArrayRegion(env: *JNIEnv, arr: jbyteArray, start: jsize, len: jsize, buf: [*c]const jbyte) void {
    envTable(env).SetByteArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setCharArrayRegion(env: *JNIEnv, arr: jcharArray, start: jsize, len: jsize, buf: [*c]const jchar) void {
    envTable(env).SetCharArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setShortArrayRegion(env: *JNIEnv, arr: jshortArray, start: jsize, len: jsize, buf: [*c]const jshort) void {
    envTable(env).SetShortArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setIntArrayRegion(env: *JNIEnv, arr: jintArray, start: jsize, len: jsize, buf: [*c]const jint) void {
    envTable(env).SetIntArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setLongArrayRegion(env: *JNIEnv, arr: jlongArray, start: jsize, len: jsize, buf: [*c]const jlong) void {
    envTable(env).SetLongArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setFloatArrayRegion(env: *JNIEnv, arr: jfloatArray, start: jsize, len: jsize, buf: [*c]const jfloat) void {
    envTable(env).SetFloatArrayRegion.?(env, arr, start, len, buf);
}
pub inline fn setDoubleArrayRegion(env: *JNIEnv, arr: jdoubleArray, start: jsize, len: jsize, buf: [*c]const jdouble) void {
    envTable(env).SetDoubleArrayRegion.?(env, arr, start, len, buf);
}

pub inline fn getPrimitiveArrayCritical(env: *JNIEnv, arr: jarray, is_copy: ?*jboolean) ?*anyopaque {
    return envTable(env).GetPrimitiveArrayCritical.?(env, arr, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn releasePrimitiveArrayCritical(env: *JNIEnv, arr: jarray, carr: ?*anyopaque, mode: ArrayReleaseMode) void {
    envTable(env).ReleasePrimitiveArrayCritical.?(env, arr, carr, @intFromEnum(mode));
}

// -- String APIs (round out the set) ----------------------------------------

/// Create a Java string from a UTF-16 buffer. (UTF-8 creation is
/// `newStringUTF` above.)
pub inline fn newStringU16(env: *JNIEnv, chars: [*c]const jchar, len: jsize) jstring {
    return envTable(env).NewString.?(env, chars, len);
}
pub inline fn getStringLength(env: *JNIEnv, s: jstring) jsize {
    return envTable(env).GetStringLength.?(env, s);
}
pub inline fn getStringChars(env: *JNIEnv, s: jstring, is_copy: ?*jboolean) [*c]const jchar {
    return envTable(env).GetStringChars.?(env, s, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn releaseStringChars(env: *JNIEnv, s: jstring, chars: [*c]const jchar) void {
    envTable(env).ReleaseStringChars.?(env, s, chars);
}
pub inline fn getStringUTFLength(env: *JNIEnv, s: jstring) jsize {
    return envTable(env).GetStringUTFLength.?(env, s);
}
pub inline fn getStringRegion(env: *JNIEnv, s: jstring, start: jsize, len: jsize, buf: [*c]jchar) void {
    envTable(env).GetStringRegion.?(env, s, start, len, buf);
}
pub inline fn getStringUTFRegion(env: *JNIEnv, s: jstring, start: jsize, len: jsize, buf: [*c]u8) void {
    envTable(env).GetStringUTFRegion.?(env, s, start, len, buf);
}
pub inline fn getStringCritical(env: *JNIEnv, s: jstring, is_copy: ?*jboolean) [*c]const jchar {
    return envTable(env).GetStringCritical.?(env, s, @as([*c]jboolean, @ptrCast(is_copy)));
}
pub inline fn releaseStringCritical(env: *JNIEnv, s: jstring, chars: [*c]const jchar) void {
    envTable(env).ReleaseStringCritical.?(env, s, chars);
}

// -- Native method registration ---------------------------------------------

pub fn registerNatives(env: *JNIEnv, clazz: jclass, methods: []const JNINativeMethod) !void {
    const rc = envTable(env).RegisterNatives.?(env, clazz, methods.ptr, @as(jint, @intCast(methods.len)));
    if (rc != JNI_OK) return error.RegisterNativesFailed;
}
pub fn unregisterNatives(env: *JNIEnv, clazz: jclass) !void {
    const rc = envTable(env).UnregisterNatives.?(env, clazz);
    if (rc != JNI_OK) return error.UnregisterNativesFailed;
}

// -- Monitor ----------------------------------------------------------------

pub fn monitorEnter(env: *JNIEnv, obj: jobject) !void {
    if (envTable(env).MonitorEnter.?(env, obj) != JNI_OK) return error.MonitorEnterFailed;
}
pub fn monitorExit(env: *JNIEnv, obj: jobject) !void {
    if (envTable(env).MonitorExit.?(env, obj) != JNI_OK) return error.MonitorExitFailed;
}

// -- Direct ByteBuffer ------------------------------------------------------

pub inline fn newDirectByteBuffer(env: *JNIEnv, addr: ?*anyopaque, capacity: jlong) jobject {
    return envTable(env).NewDirectByteBuffer.?(env, addr, capacity);
}
pub inline fn getDirectBufferAddress(env: *JNIEnv, buf: jobject) ?*anyopaque {
    return envTable(env).GetDirectBufferAddress.?(env, buf);
}
pub inline fn getDirectBufferCapacity(env: *JNIEnv, buf: jobject) jlong {
    return envTable(env).GetDirectBufferCapacity.?(env, buf);
}

// -- JNI release-mode constants (exposed for callers that want raw mode) ---

pub const JNI_COMMIT: jint = 1;
pub const JNI_ABORT: jint = 2;

// -- Typed field access (comptime-generic convenience) ----------------------

fn fieldGetterFor(comptime T: type) fn (*JNIEnv, jobject, jfieldID) T {
    return switch (T) {
        bool => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) bool {
                return getBooleanField(env, o, f);
            }
        }.g,
        jbyte => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jbyte {
                return getByteField(env, o, f);
            }
        }.g,
        jchar => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jchar {
                return getCharField(env, o, f);
            }
        }.g,
        jshort => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jshort {
                return getShortField(env, o, f);
            }
        }.g,
        jint => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jint {
                return getIntField(env, o, f);
            }
        }.g,
        jlong => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jlong {
                return getLongField(env, o, f);
            }
        }.g,
        jfloat => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jfloat {
                return getFloatField(env, o, f);
            }
        }.g,
        jdouble => struct {
            fn g(env: *JNIEnv, o: jobject, f: jfieldID) jdouble {
                return getDoubleField(env, o, f);
            }
        }.g,
        else => @compileError("jni.getField: unsupported type " ++ @typeName(T)),
    };
}

/// Comptime-dispatch field accessor. For primitives, returns the primitive
/// value. For `jobject`, returns the raw handle. For `ClassRef`-like types
/// (those exposing `pub const java_sig`), wraps the raw handle in the
/// target type.
pub fn getField(comptime T: type, env: *JNIEnv, obj: jobject, fid: jfieldID) T {
    if (T == jobject) return getObjectField(env, obj, fid);
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasDecl(T, "java_sig")) {
        return .{ .handle = getObjectField(env, obj, fid) };
    }
    return fieldGetterFor(T)(env, obj, fid);
}

pub fn setField(comptime T: type, env: *JNIEnv, obj: jobject, fid: jfieldID, v: T) void {
    if (T == jobject) return setObjectField(env, obj, fid, v);
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasDecl(T, "java_sig")) {
        return setObjectField(env, obj, fid, v.handle);
    }
    switch (T) {
        bool => setBooleanField(env, obj, fid, v),
        jbyte => setByteField(env, obj, fid, v),
        jchar => setCharField(env, obj, fid, v),
        jshort => setShortField(env, obj, fid, v),
        jint => setIntField(env, obj, fid, v),
        jlong => setLongField(env, obj, fid, v),
        jfloat => setFloatField(env, obj, fid, v),
        jdouble => setDoubleField(env, obj, fid, v),
        else => @compileError("jni.setField: unsupported type " ++ @typeName(T)),
    }
}

pub fn getStaticField(comptime T: type, env: *JNIEnv, clazz: jclass, fid: jfieldID) T {
    if (T == jobject) return getStaticObjectField(env, clazz, fid);
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasDecl(T, "java_sig")) {
        return .{ .handle = getStaticObjectField(env, clazz, fid) };
    }
    return switch (T) {
        bool => getStaticBooleanField(env, clazz, fid),
        jbyte => getStaticByteField(env, clazz, fid),
        jchar => getStaticCharField(env, clazz, fid),
        jshort => getStaticShortField(env, clazz, fid),
        jint => getStaticIntField(env, clazz, fid),
        jlong => getStaticLongField(env, clazz, fid),
        jfloat => getStaticFloatField(env, clazz, fid),
        jdouble => getStaticDoubleField(env, clazz, fid),
        else => @compileError("jni.getStaticField: unsupported type " ++ @typeName(T)),
    };
}

pub fn setStaticField(comptime T: type, env: *JNIEnv, clazz: jclass, fid: jfieldID, v: T) void {
    if (T == jobject) return setStaticObjectField(env, clazz, fid, v);
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasDecl(T, "java_sig")) {
        return setStaticObjectField(env, clazz, fid, v.handle);
    }
    switch (T) {
        bool => setStaticBooleanField(env, clazz, fid, v),
        jbyte => setStaticByteField(env, clazz, fid, v),
        jchar => setStaticCharField(env, clazz, fid, v),
        jshort => setStaticShortField(env, clazz, fid, v),
        jint => setStaticIntField(env, clazz, fid, v),
        jlong => setStaticLongField(env, clazz, fid, v),
        jfloat => setStaticFloatField(env, clazz, fid, v),
        jdouble => setStaticDoubleField(env, clazz, fid, v),
        else => @compileError("jni.setStaticField: unsupported type " ++ @typeName(T)),
    }
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

/// Pre-declared `java.lang.String` handle. Use with `newString` to get the
/// correct `Ljava/lang/String;` signature in call()/callStatic().
pub const String = ClassRef("Ljava/lang/String;");

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
