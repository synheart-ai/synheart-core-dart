import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'sdk_crypto_callbacks.dart';
import 'sdk_ffi.dart';

typedef _NativeGenerateKey = Pointer<Utf8> Function(Pointer<Utf8> deviceId);
typedef _NativeSignBytes = Pointer<Utf8> Function(
  Pointer<Utf8> deviceId,
  Pointer<Uint8> data,
  IntPtr dataLen,
);
typedef _NativeGetAttestation = Pointer<Utf8> Function(
  Pointer<Utf8> deviceId,
  Pointer<Uint8> challengeHash,
  IntPtr hashLen,
);
typedef _NativeKeyExists = Int32 Function(Pointer<Utf8> deviceId);
typedef _NativeDeleteKey = Int32 Function(Pointer<Utf8> deviceId);

/// SDK-owned bridge to process-exported native crypto callbacks.
///
/// Expected native symbols:
/// - `synheart_native_generate_key`
/// - `synheart_native_sign_bytes`
/// - `synheart_native_get_attestation`
/// - `synheart_native_key_exists`
/// - `synheart_native_delete_key`
class PlatformNativeSdkCryptoCallbacks extends SynheartCoreCryptoCallbacks {
  PlatformNativeSdkCryptoCallbacks._({
    required Pointer<Utf8> Function(Pointer<Utf8>) generateKey,
    required Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Uint8>, int) signBytes,
    required Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Uint8>, int)
    getAttestation,
    required int Function(Pointer<Utf8>) keyExists,
    required int Function(Pointer<Utf8>) deleteKey,
  }) : _generateKey = generateKey,
       _signBytes = signBytes,
       _getAttestation = getAttestation,
       _keyExists = keyExists,
       _deleteKey = deleteKey;

  final Pointer<Utf8> Function(Pointer<Utf8>) _generateKey;
  final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Uint8>, int) _signBytes;
  final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Uint8>, int)
  _getAttestation;
  final int Function(Pointer<Utf8>) _keyExists;
  final int Function(Pointer<Utf8>) _deleteKey;

  /// Optional direct C-struct pointer generation, bypassing Dart entirely.
  /// Resolves the symbols and populates [SynheartSdkCryptoCallbacks] natively.
  static Pointer<SynheartSdkCryptoCallbacks>? tryCreateRawTable() {
    try {
      final lib = _openNativeLib();
      final table = calloc<SynheartSdkCryptoCallbacks>();
      table.ref.generate_key = lib.lookup<NativeFunction<SynheartGenerateKeyNative>>('synheart_native_generate_key');
      table.ref.sign_bytes = lib.lookup<NativeFunction<SynheartSignBytesNative>>('synheart_native_sign_bytes');
      table.ref.get_attestation = lib.lookup<NativeFunction<SynheartGetAttestationNative>>('synheart_native_get_attestation');
      table.ref.key_exists = lib.lookup<NativeFunction<SynheartKeyExistsNative>>('synheart_native_key_exists');
      table.ref.delete_key = lib.lookup<NativeFunction<SynheartDeleteKeyNative>>('synheart_native_delete_key');
      return table;
    } catch (_) {
      return null;
    }
  }

  /// Returns null when required process symbols are unavailable.
  ///
  /// On Android, symbols live in a separate .so loaded via System.loadLibrary,
  /// so we must use DynamicLibrary.open(). On iOS, @_cdecl symbols are in the
  /// main binary, so DynamicLibrary.process() works.
  static PlatformNativeSdkCryptoCallbacks? tryCreate() {
    try {
      final lib = _openNativeLib();
      final generateKey = lib.lookupFunction<_NativeGenerateKey,
          Pointer<Utf8> Function(Pointer<Utf8>)>('synheart_native_generate_key');
      final signBytes = lib.lookupFunction<_NativeSignBytes,
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Uint8>, int)>(
        'synheart_native_sign_bytes',
      );
      final getAttestation = lib.lookupFunction<_NativeGetAttestation,
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Uint8>, int)>(
        'synheart_native_get_attestation',
      );
      final keyExists = lib.lookupFunction<_NativeKeyExists,
          int Function(Pointer<Utf8>)>('synheart_native_key_exists');
      final deleteKey = lib.lookupFunction<_NativeDeleteKey,
          int Function(Pointer<Utf8>)>('synheart_native_delete_key');
      return PlatformNativeSdkCryptoCallbacks._(
        generateKey: generateKey,
        signBytes: signBytes,
        getAttestation: getAttestation,
        keyExists: keyExists,
        deleteKey: deleteKey,
      );
    } catch (_) {
      return null;
    }
  }

  /// Open the native library containing synheart_native_* symbols.
  ///
  /// Android: symbols are in libsynheart_native_crypto.so (loaded by
  /// System.loadLibrary in SynheartAuthPlugin). DynamicLibrary.process()
  /// can't see them because they're in a separate linker namespace.
  ///
  /// iOS: @_cdecl symbols are linked into the main binary, so
  /// DynamicLibrary.process() finds them directly.
  static DynamicLibrary _openNativeLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libsynheart_native_crypto.so');
    }
    return DynamicLibrary.process();
  }

  @override
  String generateKeyJwk(String deviceId) {
    final idPtr = deviceId.toNativeUtf8();
    try {
      final outPtr = _generateKey(idPtr);
      if (outPtr == nullptr) {
        throw StateError('native generate_key returned null');
      }
      try {
        return outPtr.toDartString();
      } finally {
        calloc.free(outPtr);
      }
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  String signBytesBase64Url(String deviceId, Uint8List data) {
    final idPtr = deviceId.toNativeUtf8();
    final dataPtr = calloc<Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      final outPtr = _signBytes(idPtr, dataPtr, data.length);
      if (outPtr == nullptr) {
        throw StateError('native sign_bytes returned null');
      }
      try {
        return outPtr.toDartString();
      } finally {
        calloc.free(outPtr);
      }
    } finally {
      calloc.free(dataPtr);
      calloc.free(idPtr);
    }
  }

  @override
  String getAttestationJson(String deviceId, Uint8List challengeHash) {
    final idPtr = deviceId.toNativeUtf8();
    final hashPtr = calloc<Uint8>(challengeHash.length);
    try {
      hashPtr.asTypedList(challengeHash.length).setAll(0, challengeHash);
      final outPtr = _getAttestation(idPtr, hashPtr, challengeHash.length);
      if (outPtr == nullptr) {
        throw StateError('native get_attestation returned null');
      }
      try {
        return outPtr.toDartString();
      } finally {
        calloc.free(outPtr);
      }
    } finally {
      calloc.free(hashPtr);
      calloc.free(idPtr);
    }
  }

  @override
  bool keyExists(String deviceId) {
    final idPtr = deviceId.toNativeUtf8();
    try {
      return _keyExists(idPtr) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  bool deleteKey(String deviceId) {
    final idPtr = deviceId.toNativeUtf8();
    try {
      return _deleteKey(idPtr) == 0;
    } finally {
      calloc.free(idPtr);
    }
  }
}
