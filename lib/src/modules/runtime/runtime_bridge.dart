import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// --- C function typedefs (native signatures) ---

typedef _RuntimeNewC = Pointer<Void> Function(Pointer<Utf8> configJson);
typedef _RuntimeNewDart = Pointer<Void> Function(Pointer<Utf8> configJson);

typedef _RuntimeFreeC = Void Function(Pointer<Void> handle);
typedef _RuntimeFreeDart = void Function(Pointer<Void> handle);

typedef _RuntimePushRrC = Void Function(
  Pointer<Void> handle,
  Int64 tsMs,
  Double rrMs,
);
typedef _RuntimePushRrDart = void Function(
  Pointer<Void> handle,
  int tsMs,
  double rrMs,
);

typedef _RuntimePushHrC = Void Function(
  Pointer<Void> handle,
  Int64 tsMs,
  Double bpm,
);
typedef _RuntimePushHrDart = void Function(
  Pointer<Void> handle,
  int tsMs,
  double bpm,
);

typedef _RuntimePushAccelC = Void Function(
  Pointer<Void> handle,
  Int64 tsMs,
  Double x,
  Double y,
  Double z,
);
typedef _RuntimePushAccelDart = void Function(
  Pointer<Void> handle,
  int tsMs,
  double x,
  double y,
  double z,
);

typedef _RuntimePushBehaviorC = Void Function(
  Pointer<Void> handle,
  Int64 tsMs,
  Int32 eventType,
  Double value,
);
typedef _RuntimePushBehaviorDart = void Function(
  Pointer<Void> handle,
  int tsMs,
  int eventType,
  double value,
);

typedef _RuntimeTickC = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Int64 nowMs,
);
typedef _RuntimeTickDart = Pointer<Utf8> Function(
  Pointer<Void> handle,
  int nowMs,
);

typedef _RuntimeLastQualityC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeLastQualityDart = Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeFrameCountC = Uint64 Function(Pointer<Void> handle);
typedef _RuntimeFrameCountDart = int Function(Pointer<Void> handle);

typedef _RuntimeResetC = Void Function(Pointer<Void> handle);
typedef _RuntimeResetDart = void Function(Pointer<Void> handle);

typedef _RuntimeFreeStringC = Void Function(Pointer<Utf8> ptr);
typedef _RuntimeFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef _RuntimeVersionC = Pointer<Utf8> Function();
typedef _RuntimeVersionDart = Pointer<Utf8> Function();

// --- Config ---

/// Configuration passed to `synheart_runtime_new` as JSON.
class RuntimeConfig {
  final int windowMs;
  final int stepMs;
  final String subjectId;
  final String sessionId;

  RuntimeConfig({
    this.windowMs = 60000,
    this.stepMs = 5000,
    required this.subjectId,
    required this.sessionId,
  });

  Map<String, dynamic> toJson() => {
        'window_ms': windowMs,
        'step_ms': stepMs,
        'subject_id': subjectId,
        'session_id': sessionId,
      };
}

// --- RuntimeBridge ---

/// dart:ffi wrapper that binds to the `synheart_runtime_*` C ABI functions.
///
/// Use [createIfAvailable] to attempt loading the native library. If the
/// library is not present on this platform the factory returns `null` and the
/// pipeline is gracefully inert.
class RuntimeBridge {
  final DynamicLibrary _lib;
  final Pointer<Void> _handle;

  late final _RuntimeFreeDart _runtimeFree;
  late final _RuntimePushRrDart _pushRrFfi;
  late final _RuntimePushHrDart _pushHrFfi;
  late final _RuntimePushAccelDart _pushAccelFfi;
  late final _RuntimePushBehaviorDart _pushBehaviorFfi;
  late final _RuntimeTickDart _tickFfi;
  late final _RuntimeLastQualityDart _lastQualityFfi;
  late final _RuntimeFrameCountDart _frameCountFfi;
  late final _RuntimeResetDart _resetFfi;
  late final _RuntimeFreeStringDart _freeString;

  RuntimeBridge._(this._lib, this._handle) {
    _runtimeFree = _lib
        .lookupFunction<_RuntimeFreeC, _RuntimeFreeDart>(
          'synheart_runtime_free',
        );
    _pushRrFfi = _lib
        .lookupFunction<_RuntimePushRrC, _RuntimePushRrDart>(
          'synheart_runtime_push_rr',
        );
    _pushHrFfi = _lib
        .lookupFunction<_RuntimePushHrC, _RuntimePushHrDart>(
          'synheart_runtime_push_hr',
        );
    _pushAccelFfi = _lib
        .lookupFunction<_RuntimePushAccelC, _RuntimePushAccelDart>(
          'synheart_runtime_push_accel',
        );
    _pushBehaviorFfi = _lib
        .lookupFunction<_RuntimePushBehaviorC, _RuntimePushBehaviorDart>(
          'synheart_runtime_push_behavior',
        );
    _tickFfi = _lib
        .lookupFunction<_RuntimeTickC, _RuntimeTickDart>(
          'synheart_runtime_tick',
        );
    _lastQualityFfi = _lib
        .lookupFunction<_RuntimeLastQualityC, _RuntimeLastQualityDart>(
          'synheart_runtime_last_quality',
        );
    _frameCountFfi = _lib
        .lookupFunction<_RuntimeFrameCountC, _RuntimeFrameCountDart>(
          'synheart_runtime_frame_count',
        );
    _resetFfi = _lib
        .lookupFunction<_RuntimeResetC, _RuntimeResetDart>(
          'synheart_runtime_reset',
        );
    _freeString = _lib
        .lookupFunction<_RuntimeFreeStringC, _RuntimeFreeStringDart>(
          'synheart_runtime_free_string',
        );
  }

  /// Create a [RuntimeBridge] if the native library is available, otherwise null.
  static RuntimeBridge? createIfAvailable(RuntimeConfig config) {
    try {
      final lib = _loadLibrary();
      if (lib == null) return null;

      final runtimeNew = lib
          .lookupFunction<_RuntimeNewC, _RuntimeNewDart>(
            'synheart_runtime_new',
          );

      final configJson = jsonEncode(config.toJson());
      final configNative = configJson.toNativeUtf8();
      Pointer<Void> handle;
      try {
        handle = runtimeNew(configNative);
      } finally {
        malloc.free(configNative);
      }

      if (handle == nullptr) return null;

      return RuntimeBridge._(lib, handle);
    } catch (_) {
      return null;
    }
  }

  static DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return DynamicLibrary.open('libsynheart_runtime.so');
      } else if (Platform.isIOS) {
        return DynamicLibrary.process();
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libsynheart_runtime.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('synheart_runtime.dll');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Push an RR-interval sample into the runtime.
  void pushRr(int tsMs, double rrMs) {
    _pushRrFfi(_handle, tsMs, rrMs);
  }

  /// Push a heart-rate sample into the runtime.
  void pushHr(int tsMs, double bpm) {
    _pushHrFfi(_handle, tsMs, bpm);
  }

  /// Push a 3-axis accelerometer sample into the runtime.
  void pushAccel(int tsMs, double x, double y, double z) {
    _pushAccelFfi(_handle, tsMs, x, y, z);
  }

  /// Push a behavioral event into the runtime.
  void pushBehavior(int tsMs, int eventType, double value) {
    _pushBehaviorFfi(_handle, tsMs, eventType, value);
  }

  /// Advance the runtime clock and return HSI JSON if a new frame was produced.
  ///
  /// Returns `null` when the runtime has not accumulated enough data to emit
  /// a new frame since the last tick.
  String? tick(int nowMs) {
    final resultPtr = _tickFfi(_handle, nowMs);
    if (resultPtr == nullptr) return null;
    final json = resultPtr.toDartString();
    _freeString(resultPtr);
    return json;
  }

  /// Return the latest quality-assessment JSON, or `null` if unavailable.
  String? lastQuality() {
    final resultPtr = _lastQualityFfi(_handle);
    if (resultPtr == nullptr) return null;
    final json = resultPtr.toDartString();
    _freeString(resultPtr);
    return json;
  }

  /// Number of HSI frames produced so far.
  int frameCount() {
    return _frameCountFfi(_handle);
  }

  /// Reset the runtime state (clears all internal buffers).
  void reset() {
    _resetFfi(_handle);
  }

  /// Release the native runtime handle. Must be called when the bridge
  /// is no longer needed to avoid leaking native memory.
  void dispose() {
    _runtimeFree(_handle);
  }

  /// Return the native library version string.
  ///
  /// This is a static helper that loads the library solely to read the version.
  /// Returns `null` if the library is unavailable.
  static String? version() {
    try {
      final lib = _loadLibrary();
      if (lib == null) return null;
      final versionFfi = lib
          .lookupFunction<_RuntimeVersionC, _RuntimeVersionDart>(
            'synheart_runtime_version',
          );
      final ptr = versionFfi();
      if (ptr == nullptr) return null;
      final v = ptr.toDartString();
      // Note: version string is expected to be static — no free needed.
      return v;
    } catch (_) {
      return null;
    }
  }
}
