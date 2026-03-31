import 'dart:convert';
import 'dart:typed_data';

import '../base/synheart_module.dart';
import '../consent/consent_module.dart';
import '../interfaces/auth_provider.dart';
import '../../config/api_endpoints.dart';
import '../../config/lab_ingest_config.dart';
import 'lab_ingest_client.dart';

/// Module for custom platform session and metadata ingestion.
///
/// Wraps [LabIngestClient] with consent gating via [ConsentModule].
/// Uploads are on-demand (not streaming), so [onStart]/[onStop] are no-ops.
///
/// Auth model (post security rewrite):
///   Authorization: Bearer {consentToken}   — standard JWT from ConsentModule
///   + device signature headers              — defense-in-depth via AuthProvider
///
/// HMAC signing removed — device attestation at token issuance replaces it.
class LabIngestModule extends BaseSynheartModule {
  @override
  final String moduleId = 'lab_ingest';

  final ConsentModule _consentModule;
  final LabIngestConfig _config;

  late final LabIngestClient _client;

  LabIngestModule({
    required ConsentModule consentModule,
    required LabIngestConfig config,
  })  : _consentModule = consentModule,
        _config = config;

  /// The underlying client — exposed for standalone/background usage.
  LabIngestClient get client => _client;

  @override
  Future<void> onInitialize() async {
    _client = LabIngestClient(
      baseUrl: _config.baseUrl,
      timeout: _config.timeout,
      maxRetries: _config.maxRetries,
    );
  }

  @override
  Future<void> onStart() async {
    // On-demand uploads — no background work to start.
  }

  @override
  Future<void> onStop() async {}

  @override
  Future<void> onDispose() async {
    _client.dispose();
  }

  /// Ingest a session payload. Requires behavior consent (digital_activity channel).
  Future<LabIngestResponse> ingestSession(
    Map<String, dynamic> payload,
  ) async {
    final consent = _consentModule.current();
    if (!consent.allowsChannel('behavior.digital_activity')) {
      return const LabIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Behavior consent not granted',
      );
    }

    final token = _consentModule.getCurrentToken();
    final deviceHeaders = await _getDeviceHeaders(
      'POST', ApiEndpoints.labSessionIngestPath, payload,
    );

    return _client.ingestSession(
      payload: payload,
      consentToken: token?.token,
      deviceHeaders: deviceHeaders,
    );
  }

  /// Ingest a metadata payload. Requires biosignals consent (vitals channel).
  Future<LabIngestResponse> ingestMetadata(
    Map<String, dynamic> payload,
  ) async {
    final consent = _consentModule.current();
    if (!consent.allowsChannel('biosignals.vitals')) {
      return const LabIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Biosignals consent not granted',
      );
    }

    final token = _consentModule.getCurrentToken();
    final deviceHeaders = await _getDeviceHeaders(
      'POST', ApiEndpoints.labMetadataIngestPath, payload,
    );

    return _client.ingestMetadata(
      payload: payload,
      consentToken: token?.token,
      deviceHeaders: deviceHeaders,
    );
  }

  /// Get device signature headers if authProvider is configured.
  Future<Map<String, String>?> _getDeviceHeaders(
    String method, String path, Map<String, dynamic> payload,
  ) async {
    final authProvider = _config.authProvider;
    if (authProvider == null) return null;

    final bodyJson = jsonEncode(payload);
    return await authProvider.signRequest(
      method: method,
      path: path,
      bodyBytes: Uint8List.fromList(utf8.encode(bodyJson)),
    );
  }
}
