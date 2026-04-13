/// Synchronous platform crypto hooks for [CoreRuntimeBridge.setSdkCryptoCallbacks].
///
/// Core Runtime invokes these from worker threads during device registration and proof
/// assembly. Implementations must not block on async platform channels; use a
/// native FFI plugin or other synchronous bridge.
library;

import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'sdk_ffi.dart';

/// Host-provided crypto for core-runtime device auth (`synheart_core_sdk_*`).
abstract class SynheartCoreCryptoCallbacks {
  /// Returns JWK JSON: `{ "x": "<b64url>", "y": "<b64url>" }`.
  String generateKeyJwk(String deviceId);

  /// Returns base64url (or base64) signature bytes for [data].
  String signBytesBase64Url(String deviceId, Uint8List data);

  /// Returns `{ "format": "...", "blob": "..." }` for [challengeHash].
  ///
  /// For Android Play Integrity, `blob` must be the raw compact JOSE token
  /// from the client API (do not re-encode/wrap/truncate).
  String getAttestationJson(String deviceId, Uint8List challengeHash);

  bool keyExists(String deviceId);

  /// Returns true on success.
  bool deleteKey(String deviceId);
}

SynheartCoreCryptoCallbacks? _synheartCoreCrypto;

/// Set the global delegate used by FFI trampolines (call before [CoreRuntimeBridge.setSdkCryptoCallbacks]).
void synheartSdkCryptoAttach(SynheartCoreCryptoCallbacks? callbacks) {
  _synheartCoreCrypto = callbacks;
}

Pointer<Utf8> synheartTrampolineGenerateKey(Pointer<Utf8> deviceIdPtr) {
  final cb = _synheartCoreCrypto;
  if (cb == null || deviceIdPtr == nullptr) return nullptr;
  try {
    final json = cb.generateKeyJwk(deviceIdPtr.toDartString());
    return json.toNativeUtf8();
  } catch (e, st) {
    developer.log(
      'generateKeyJwk callback failed: $e',
      name: 'synheart_core.sdk_crypto',
      stackTrace: st,
    );
    return nullptr;
  }
}

Pointer<Utf8> synheartTrampolineSignBytes(
  Pointer<Utf8> deviceIdPtr,
  Pointer<Uint8> dataPtr,
  int dataLen,
) {
  final cb = _synheartCoreCrypto;
  if (cb == null || deviceIdPtr == nullptr) return nullptr;
  try {
    final bytes = dataLen <= 0
        ? Uint8List(0)
        : Uint8List.fromList(dataPtr.asTypedList(dataLen));
    final sig = cb.signBytesBase64Url(deviceIdPtr.toDartString(), bytes);
    return sig.toNativeUtf8();
  } catch (e, st) {
    developer.log(
      'signBytesBase64Url callback failed: $e',
      name: 'synheart_core.sdk_crypto',
      stackTrace: st,
    );
    return nullptr;
  }
}

Pointer<Utf8> synheartTrampolineGetAttestation(
  Pointer<Utf8> deviceIdPtr,
  Pointer<Uint8> hashPtr,
  int hashLen,
) {
  final cb = _synheartCoreCrypto;
  if (cb == null || deviceIdPtr == nullptr) return nullptr;
  try {
    final hash = hashLen <= 0
        ? Uint8List(0)
        : Uint8List.fromList(hashPtr.asTypedList(hashLen));
    final json = cb.getAttestationJson(deviceIdPtr.toDartString(), hash);
    return json.toNativeUtf8();
  } catch (e, st) {
    developer.log(
      'getAttestationJson callback failed: $e',
      name: 'synheart_core.sdk_crypto',
      stackTrace: st,
    );
    return nullptr;
  }
}

int synheartTrampolineKeyExists(Pointer<Utf8> deviceIdPtr) {
  final cb = _synheartCoreCrypto;
  if (cb == null || deviceIdPtr == nullptr) return 0;
  try {
    return cb.keyExists(deviceIdPtr.toDartString()) ? 1 : 0;
  } catch (e, st) {
    developer.log(
      'keyExists callback failed: $e',
      name: 'synheart_core.sdk_crypto',
      stackTrace: st,
    );
    return 0;
  }
}

int synheartTrampolineDeleteKey(Pointer<Utf8> deviceIdPtr) {
  final cb = _synheartCoreCrypto;
  if (cb == null || deviceIdPtr == nullptr) return 1;
  try {
    return cb.deleteKey(deviceIdPtr.toDartString()) ? 0 : 1;
  } catch (e, st) {
    developer.log(
      'deleteKey callback failed: $e',
      name: 'synheart_core.sdk_crypto',
      stackTrace: st,
    );
    return 1;
  }
}

/// Fills [out] with native function pointers; [out] must remain allocated for
/// the lifetime of the core handle after [set_crypto_callbacks] is called.
void synheartFillSdkCryptoStruct(Pointer<SynheartSdkCryptoCallbacks> out) {
  out.ref
    ..generate_key = Pointer.fromFunction(synheartTrampolineGenerateKey)
    ..sign_bytes = Pointer.fromFunction(synheartTrampolineSignBytes)
    ..get_attestation = Pointer.fromFunction(synheartTrampolineGetAttestation)
    ..key_exists = Pointer.fromFunction(synheartTrampolineKeyExists, 0)
    ..delete_key = Pointer.fromFunction(synheartTrampolineDeleteKey, 1);
}
