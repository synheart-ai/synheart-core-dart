/// A Synsync operation with its own native prerequisites.
enum SyncOperation {
  createSpace,
  joinSpace,
  recoverSpace,
  generatePairing,
  syncNow,
  leaveSpace,
  listDevices,
  revokeDevice,
  deleteSpace,
  clearLocalSpace,
}

/// Stable reason why a Synsync operation can or cannot run.
enum SyncReadinessCode {
  ready,
  featureNotActivated,
  cloudConsentRequired,
  capabilityNotAllowed,
  nativeRuntimeUnavailable,
  configurationMissing,
  storageUnavailable,
  deviceRevoked,
  deviceRegistrationRequired,
  activeSpaceRequired,
  srkUnavailable,
}

/// Operation-specific Synsync readiness composed from SDK authorization and
/// the native runtime readiness snapshot.
class SyncReadiness {
  const SyncReadiness({
    required this.operation,
    required this.isReady,
    required this.code,
    this.nativeState,
    this.nativeSnapshot,
  });

  final SyncOperation operation;
  final bool isReady;
  final SyncReadinessCode code;

  /// Primary state reported by `synheart_core_sync_readiness`, when present.
  final String? nativeState;

  /// Raw snapshot retained for diagnostics and forward-compatible host UIs.
  final Map<String, dynamic>? nativeSnapshot;

  /// Compose readiness without consulting collection-session state.
  ///
  /// Create, Join, and Recover bootstrap the native sync engine themselves, so
  /// they do not require an initialized engine, active space, or loaded SRK.
  /// Pairing and Sync require both a space and SRK. Management operations need
  /// a space but do not need artifact-encryption key material.
  static SyncReadiness evaluate({
    required SyncOperation operation,
    required bool activated,
    required bool cloudConsentGranted,
    required bool capabilityAllowed,
    required Map<String, dynamic>? nativeSnapshot,
  }) {
    SyncReadiness blocked(SyncReadinessCode code) => SyncReadiness(
      operation: operation,
      isReady: false,
      code: code,
      nativeState: nativeSnapshot?['state']?.toString(),
      nativeSnapshot: nativeSnapshot,
    );

    if (!activated) {
      return blocked(SyncReadinessCode.featureNotActivated);
    }
    if (!cloudConsentGranted) {
      return blocked(SyncReadinessCode.cloudConsentRequired);
    }
    if (!capabilityAllowed) {
      return blocked(SyncReadinessCode.capabilityNotAllowed);
    }
    if (nativeSnapshot == null) {
      return blocked(SyncReadinessCode.nativeRuntimeUnavailable);
    }
    if (nativeSnapshot['configured'] != true) {
      return blocked(SyncReadinessCode.configurationMissing);
    }
    if (nativeSnapshot['storage_present'] != true) {
      return blocked(SyncReadinessCode.storageUnavailable);
    }
    if (nativeSnapshot['device_revoked'] == true) {
      return blocked(SyncReadinessCode.deviceRevoked);
    }
    if (nativeSnapshot['device_registered'] != true) {
      return blocked(SyncReadinessCode.deviceRegistrationRequired);
    }

    final requiresActiveSpace = switch (operation) {
      SyncOperation.createSpace ||
      SyncOperation.joinSpace ||
      SyncOperation.recoverSpace => false,
      _ => true,
    };
    if (requiresActiveSpace && nativeSnapshot['active_space'] != true) {
      return blocked(SyncReadinessCode.activeSpaceRequired);
    }

    final requiresSrk = switch (operation) {
      SyncOperation.generatePairing || SyncOperation.syncNow => true,
      _ => false,
    };
    if (requiresSrk && nativeSnapshot['srk_ready'] != true) {
      return blocked(SyncReadinessCode.srkUnavailable);
    }

    return SyncReadiness(
      operation: operation,
      isReady: true,
      code: SyncReadinessCode.ready,
      nativeState: nativeSnapshot['state']?.toString(),
      nativeSnapshot: nativeSnapshot,
    );
  }
}
