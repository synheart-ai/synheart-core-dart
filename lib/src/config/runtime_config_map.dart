import 'api_endpoints.dart';
import 'synheart_config.dart';

/// Builds the JSON config handed to `synheart_core_new`.
///
/// Pure and side-effect free so it can be unit-tested without a native runtime.
/// It exists because the same map was previously spelled out three times —
/// `Synheart._configure`, `Synheart.ensureRuntimeBridge`, and
/// `SynheartInstance._buildConfigMap` — and they had already drifted apart:
/// `SynheartInstance` gated `device_auth.enabled` on the config while the other
/// two hardcoded `true`.
///
/// That drift was not cosmetic. Both `Synheart` paths also hardcoded
/// `ingest.enabled: true`, so a host with no [CloudConfig] hit
///
///   ERR_NOT_CONFIGURED: cloud connector org_id must not be empty when HSI
///   ingest is enabled
///
/// inside `synheart_core_new`. The handle came back null, `_coreRuntime` stayed
/// null, and the SDK carried on to log "Initialization complete" — with no HSI,
/// no consent store, and no storage. Local-only operation, which the SDK
/// documents as supported, could not initialise at all.
///
/// Keep this the single source of truth. Both gates below are load-bearing:
///
/// - `ingest.*` requires a non-empty `org_id`, so it is enabled only when a
///   [CloudConfig] supplies one.
/// - `device_auth.enabled` requires a [DeviceAuthConfig]; enabling it without
///   one makes the runtime reject crypto-callback registration with
///   `ERR_NOT_CONFIGURED: device_auth not enabled`.
Map<String, dynamic> buildRuntimeConfigMap(
  SynheartConfig config, {
  String? dataDir,
}) {
  final orgId = config.cloudConfig?.orgId ?? '';

  /// Cloud ingest is only legal with a non-empty org id.
  final cloudReady = orgId.isNotEmpty;

  final deviceAuthEnabled = config.deviceAuthConfig != null;

  return <String, dynamic>{
    'app_id': config.appId,
    'org_id': orgId,
    'subject_id': config.subjectId,
    // The runtime derives the device identity's subject from client_id, and
    // rejects the config when device_auth is enabled without one.
    'client_id': config.subjectId,
    // API gateway origin for consent / ingest / platform calls.
    //
    // Resolved here rather than passed through raw. `SyncConfig.baseUrl`
    // defaults to `ApiEndpoints.defaultAuthBaseUrl`, which is a const alias for
    // the SYNHEART_AUTH_BASE_URL dart-define and is EMPTY unless the host sets
    // it. An empty value makes the runtime fall back to its own hardcoded
    // production URL — so a dev build with no dart-defines silently talked to
    // production, which is the exact hazard the SynheartInstance config comment
    // warns about. `resolvedAuthBaseUrl` applies the documented fallback chain
    // explicitly instead.
    'api_base_url': config.sync.baseUrl.isNotEmpty
        ? config.sync.baseUrl
        : ApiEndpoints.resolvedAuthBaseUrl,
    'mode': config.mode.name,
    'device_id': config.deviceId,
    'app_version': config.appVersion,
    'platform': config.platform,
    if (dataDir != null) 'data_dir': dataDir,
    'storage': {'enabled': config.storage.enabled},
    'ingest': {'enabled': cloudReady, 'hsi': cloudReady, 'lab': cloudReady},
    'device_auth': {
      'enabled': deviceAuthEnabled,
      'auth_base_url': config.deviceAuthConfig?.authBaseUrl ?? '',
      'package_name': config.deviceAuthConfig?.packageName ?? '',
    },
    'sync': {'enabled': config.sync.enabled, 'base_url': config.sync.baseUrl},
    'privacy': {'allow_research': config.privacy.allowResearch},
  };
}
