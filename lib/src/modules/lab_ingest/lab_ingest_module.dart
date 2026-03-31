import 'dart:convert';
import 'dart:typed_data';

import '../base/synheart_module.dart';
import '../consent/consent_module.dart';
import '../cloud/hmac_signer.dart';
import '../../config/api_endpoints.dart';
import '../../config/platform_ingest_config.dart';
import 'platform_ingest_client.dart';

/// Module for custom platform session and metadata ingestion.
///
/// Wraps [PlatformIngestClient] with consent gating via [ConsentModule].
/// Uploads are on-demand (not streaming), so [onStart]/[onStop] are no-ops.
///
/// When [PlatformIngestConfig.authProvider] is set (e.g., via DeviceAuthProvider),
/// requests are signed with device credentials instead of HMAC.
class PlatformIngestModule extends BaseSynheartModule {
  @override
  final String moduleId = 'platform_ingest';

  final ConsentModule _consentModule;
  final PlatformIngestConfig _config;

  HMACSigner? _signer;
  late final PlatformIngestClient _client;

  PlatformIngestModule({
    required ConsentModule consentModule,
    required PlatformIngestConfig config,
  })  : _consentModule = consentModule,
        _config = config;

  /// The underlying client — exposed for standalone/background usage.
  PlatformIngestClient get client => _client;

  @override
  Future<void> onInitialize() async {
    if (_config.hmacSecret != null) {
      _signer = HMACSigner(hmacSecret: _config.hmacSecret!);
    }
    _client = PlatformIngestClient(
      baseUrl: _config.baseUrl,
      timeout: _config.timeout,
      maxRetries: _config.maxRetries,
    );
  }

  @override
  Future<void> onStart() async {
    // On-demand uploads — nothing to start.
  }

  @override
  Future<void> onStop() async {
    // On-demand uploads — nothing to stop.
  }

  @override
  Future<void> onDispose() async {
    _client.dispose();
  }

  /// Ingest a session payload. Requires behavior consent (digital_activity channel).
  Future<PlatformIngestResponse> ingestSession(
    Map<String, dynamic> payload,
  ) async {
    final consent = _consentModule.current();
    if (!consent.allowsChannel('behavior.digital_activity')) {
      return const PlatformIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Behavior consent not granted',
      );
    }

    final token = _consentModule.getCurrentToken();
    final authProvider = _config.authProvider;

    if (authProvider != null) {
      final bodyJson = jsonEncode(payload);
      final authHeaders = await authProvider.signRequest(
        method: 'POST',
        path: ApiEndpoints.platformSessionIngestPath,
        bodyBytes: Uint8List.fromList(utf8.encode(bodyJson)),
      );
      return _client.ingestSession(
        payload: payload,
        authHeaders: authHeaders,
        consentToken: token?.token,
      );
    }

    return _client.ingestSession(
      payload: payload,
      signer: _signer,
      apiKey: _config.apiKey,
      consentToken: token?.token,
    );
  }

  /// Ingest a metadata payload. Requires biosignals consent (vitals channel).
  Future<PlatformIngestResponse> ingestMetadata(
    Map<String, dynamic> payload,
  ) async {
    final consent = _consentModule.current();
    if (!consent.allowsChannel('biosignals.vitals')) {
      return const PlatformIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Biosignals consent not granted',
      );
    }

    final token = _consentModule.getCurrentToken();
    final authProvider = _config.authProvider;

    if (authProvider != null) {
      final bodyJson = jsonEncode(payload);
      final authHeaders = await authProvider.signRequest(
        method: 'POST',
        path: ApiEndpoints.platformMetadataIngestPath,
        bodyBytes: Uint8List.fromList(utf8.encode(bodyJson)),
      );
      return _client.ingestMetadata(
        payload: payload,
        authHeaders: authHeaders,
        consentToken: token?.token,
      );
    }

    return _client.ingestMetadata(
      payload: payload,
      signer: _signer,
      apiKey: _config.apiKey,
      consentToken: token?.token,
    );
  }
}
