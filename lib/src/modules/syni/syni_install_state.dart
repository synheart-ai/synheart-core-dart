/// Installation lifecycle of the Syni client.
///
/// `Activation` (one of the four authorities in `SynheartFeature`'s
/// operational model) is gated on this reaching [SyniInstalled]. Until then,
/// `Synheart.syni.chat()` throws.
library;

sealed class SyniInstallState {
  const SyniInstallState();
}

/// No model downloaded, no persona materialized. Default state.
class SyniNotInstalled extends SyniInstallState {
  const SyniNotInstalled();

  @override
  String toString() => 'SyniNotInstalled';
}

/// Install in progress. [progress] is in `[0.0, 1.0]`; the description in
/// [stage] explains which sub-step is running (download / verify /
/// materialize-persona / load-engine).
class SyniInstalling extends SyniInstallState {
  const SyniInstalling({required this.stage, required this.progress});

  final SyniInstallStage stage;
  final double progress;

  @override
  String toString() =>
      'SyniInstalling(stage: $stage, progress: ${(progress * 100).toStringAsFixed(1)}%)';
}

/// Successfully installed. The runtime engine has loaded the model and is
/// ready to receive `chat()` calls.
class SyniInstalled extends SyniInstallState {
  const SyniInstalled({
    required this.personaId,
    required this.modelPath,
    required this.runtimeVersion,
  });

  final String personaId;
  final String modelPath;
  final String runtimeVersion;

  @override
  String toString() =>
      'SyniInstalled(personaId: $personaId, runtime: $runtimeVersion)';
}

/// Install failed. [reason] is human-readable; [cause] is the underlying
/// exception when available.
class SyniInstallFailed extends SyniInstallState {
  const SyniInstallFailed({required this.reason, this.cause});

  final String reason;
  final Object? cause;

  @override
  String toString() => 'SyniInstallFailed(reason: $reason)';
}

enum SyniInstallStage {
  /// Pre-flight checks: consent grant, capability, free disk.
  preflight,

  /// Model download from CDN.
  downloadingModel,

  /// SHA-256 verification of the downloaded model.
  verifyingModel,

  /// Persona spec resolution (from bundled assets or core-spec cache).
  materializingPersona,

  /// libsyni_ffi engine spawn + model load on the worker isolate.
  loadingEngine,
}
