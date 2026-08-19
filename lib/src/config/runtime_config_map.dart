import 'api_endpoints.dart';
import 'synheart_config.dart';

/// Builds the JSON config handed to `synheart_core_new`.
///
/// Pure and side-effect free, so it can be unit-tested without a native
/// runtime, and single-sourced so the facade and secondary instances cannot
/// drift apart.
///
/// Both gates below are load-bearing:
///
/// - `ingest.*` requires a non-empty `org_id`. Enabling it without one makes
///   the runtime reject the entire configuration, which surfaces as a null
///   handle rather than a targeted error — so ingest is enabled only when a
///   [CloudConfig] supplies an org id, leaving local-only hosts working.
/// - `device_auth.enabled` requires a [DeviceAuthConfig]. Enabling it without
///   one makes crypto-callback registration fail.
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
    // Resolved rather than passed through raw: `SyncConfig.baseUrl` defaults to
    // a dart-define that is empty unless the host sets it, and an empty value
    // makes the runtime fall back to its own built-in default. Resolving here
    // keeps the chosen endpoint explicit.
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
      'allow_unattested_dev_registration':
          config.deviceAuthConfig?.allowUnattestedDevRegistration ?? false,
    },
    'sync': {'enabled': config.sync.enabled, 'base_url': config.sync.baseUrl},
    'privacy': {'allow_research': config.privacy.allowResearch},
  };
}
