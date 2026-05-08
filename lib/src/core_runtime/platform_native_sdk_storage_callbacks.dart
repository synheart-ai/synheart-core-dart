import 'dart:ffi';
import 'dart:io' show Platform;

import 'sdk_ffi.dart';

/// Resolves host-provided secure-storage symbols (`synheart_native_secure_*`)
/// and exposes the three C function pointers the core runtime wants for
/// `synheart_core_set_storage_callbacks`.
///
/// Mirrors [PlatformNativeSdkCryptoCallbacks] but for the three
/// store / load / delete symbols:
///
/// - `synheart_native_secure_store(service, key, value) -> int32`
/// - `synheart_native_secure_load(service, key) -> char*`  (caller owns)
/// - `synheart_native_secure_delete(service, key) -> int32`
///
/// Android: symbols live in `libsynheart_native_crypto.so` (the existing
/// auth native lib; we reuse it for secure-storage too).
/// iOS/macOS: `@_cdecl` symbols are statically linked into the app and reached
/// via `DynamicLibrary.process()`.
abstract final class PlatformNativeSdkStorageCallbacks {
  /// Returns a resolved triple of native function pointers, or null if any
  /// are missing (in which case the core runs without persisted storage).
  static _ResolvedStorageTriple? tryResolveTriple() {
    try {
      final lib = _openNativeLib();
      final store = lib.lookup<NativeFunction<SynheartSecureStoreNative>>(
        'synheart_native_secure_store',
      );
      final load = lib.lookup<NativeFunction<SynheartSecureLoadNative>>(
        'synheart_native_secure_load',
      );
      final del = lib.lookup<NativeFunction<SynheartSecureDeleteNative>>(
        'synheart_native_secure_delete',
      );
      return _ResolvedStorageTriple(store: store, load: load, delete: del);
    } catch (_) {
      return null;
    }
  }

  static DynamicLibrary _openNativeLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libsynheart_native_crypto.so');
    }
    return DynamicLibrary.process();
  }
}

class _ResolvedStorageTriple {
  _ResolvedStorageTriple({
    required this.store,
    required this.load,
    required this.delete,
  });

  final Pointer<NativeFunction<SynheartSecureStoreNative>> store;
  final Pointer<NativeFunction<SynheartSecureLoadNative>> load;
  final Pointer<NativeFunction<SynheartSecureDeleteNative>> delete;
}

/// Type alias exposed for the bridge layer; keeps callers from importing
/// the private class directly.
typedef ResolvedStorageTriple = _ResolvedStorageTriple;
