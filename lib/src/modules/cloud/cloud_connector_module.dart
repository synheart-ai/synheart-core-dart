import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../consent/consent_module.dart';
import '../runtime/runtime_module.dart';
import '../../config/synheart_config.dart';
import 'hmac_signer.dart';
import 'upload_client.dart';
import 'upload_queue.dart';
import 'rate_limiter.dart';
import 'network_monitor.dart';
import 'upload_models.dart';
import 'cloud_exceptions.dart';
import 'platform_impl_stub.dart'
    if (dart.library.io) 'platform_impl_io.dart'
    as platform_impl;

class CloudConnectorModule extends BaseSynheartModule {
  @override
  String get moduleId => 'cloud';

  final CapabilityProvider _capabilities;
  final ConsentModule _consent;
  final RuntimeModule _hsiRuntime;
  final CloudConfig _config;

  // Components
  HMACSigner? _hmacSigner;
  late final UploadClient _uploadClient;
  late final UploadQueue _uploadQueue;
  late final RateLimiter _rateLimiter;
  late final NetworkMonitor _networkMonitor;

  StreamSubscription? _hsvSubscription;
  StreamSubscription? _networkSubscription;

  /// Last successful upload batch id (from API response).
  String? _lastUploadBatchId;

  /// When the last successful upload completed.
  DateTime? _lastUploadAt;

  /// Last upload failure message (null after a success).
  String? _lastUploadError;

  /// When the last upload attempt (success or failure) occurred.
  DateTime? _lastUploadAttemptAt;

  /// Pending snapshots in the upload queue.
  int get uploadQueueLength => _uploadQueue.length;

  /// Batch id from the last successful ingest (null if none yet).
  String? get lastUploadBatchId => _lastUploadBatchId;

  /// Time of the last successful ingest (null if none yet).
  DateTime? get lastUploadAt => _lastUploadAt;

  /// Last upload error message (null when last attempt succeeded or no attempt yet).
  String? get lastUploadError => _lastUploadError;

  /// Time of the last upload attempt (success or failure); null if no attempt yet.
  DateTime? get lastUploadAttemptAt => _lastUploadAttemptAt;

  CloudConnectorModule({
    required CapabilityProvider capabilities,
    required ConsentModule consent,
    required RuntimeModule hsiRuntime,
    required CloudConfig config,
  }) : _capabilities = capabilities,
       _consent = consent,
       _hsiRuntime = hsiRuntime,
       _config = config;

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[CloudConnector] Initializing Cloud Connector...');

    if (_config.hmacSecret != null) {
      _hmacSigner = HMACSigner(hmacSecret: _config.hmacSecret!);
    }
    _uploadClient = UploadClient(baseUrl: _config.baseUrl);
    _uploadQueue = UploadQueue(
      maxSize: _config.maxQueueSize,
      storage: const FlutterSecureStorage(),
    );
    _rateLimiter = RateLimiter(
      capabilityLevel: _capabilities.capability(Module.cloud),
    );
    _networkMonitor = NetworkMonitor();

    await _uploadQueue.loadFromStorage();

    SynheartLogger.log('[CloudConnector] Cloud Connector initialized');
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[CloudConnector] Starting Cloud Connector...');

    _hsvSubscription = _hsiRuntime.hsiStream.listen(_handleHSIUpdate);

    _networkSubscription = _networkMonitor.connectivityStream.listen(
      _handleNetworkChange,
    );

    if (_networkMonitor.isOnline) {
      flushQueue().catchError((error) {
        SynheartLogger.log(
          '[CloudConnector] Error flushing queue during start (non-blocking): $error',
          error: error,
        );
        // Don't rethrow - allow initialization to complete
      });
    }

    SynheartLogger.log('[CloudConnector] Cloud Connector started');
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[CloudConnector] Stopping Cloud Connector...');

    // Cancel subscriptions first to stop receiving new data
    await _hsvSubscription?.cancel();
    await _networkSubscription?.cancel();

    // Attempt to flush remaining queue before stopping (with timeout)
    // This ensures important data is uploaded, but doesn't block indefinitely
    if (_uploadQueue.hasItems && _networkMonitor.isOnline) {
      SynheartLogger.log(
        '[CloudConnector] Attempting to flush queue before stopping...',
      );
      try {
        // Flush with timeout - don't wait forever
        await flushQueue().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            SynheartLogger.log(
              '[CloudConnector] Queue flush timeout reached. Remaining items will be persisted and uploaded on next start.',
            );
          },
        );
      } catch (e) {
        SynheartLogger.log(
          '[CloudConnector] Error flushing queue during stop: $e',
          error: e,
        );
        // Continue with stop even if flush fails
      }
    }

    SynheartLogger.log('[CloudConnector] Cloud Connector stopped');
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[CloudConnector] Disposing Cloud Connector...');

    await _uploadQueue.persistToStorage();
    _uploadClient.dispose();
    _networkMonitor.dispose();
  }

  void _handleHSIUpdate(String hsiJson) async {
    // Check consent
    if (!_consent.current().cloudUpload) {
      return; // Silent return - no upload
    }

    // Enqueue for upload (raw HSI JSON string)
    await _uploadQueue.enqueue(hsiJson);

    // Try immediate upload if online
    if (_networkMonitor.isOnline) {
      await _attemptUpload();
    }
  }

  void _handleNetworkChange(bool isOnline) async {
    if (isOnline) {
      await flushQueue();
    }
  }

  static const _validInferenceModes = {
    'deterministic',
    'probabilistic',
    'composite',
  };
  static const _validWindowAggregations = {'instant', 'windowed', 'cumulative'};
  static const _validAxisCategories = {
    'behavior',
    'engagement',
    'physiological',
  };

  /// Patch raw HSI map to be compliant with hsi-1.1.schema.json.
  /// Ensures every axis entry has `evidence_source_ids` and a valid
  /// `inference_mode`, and that `producer.instance_id` is present.
  Map<String, dynamic> _patchHsiV1_1(Map<String, dynamic> hsi) {
    final defaultSourceId = 'src_${const Uuid().v4().replaceAll('-', '')}';

    // Some runtime shapes include unsupported root fields for hsi-1.1.
    hsi.remove('window_ids');

    // --- meta.provenance.sources (ensure >= 1 source) ---
    final meta =
        (hsi['meta'] is Map<String, dynamic>)
            ? (hsi['meta'] as Map<String, dynamic>)
            : <String, dynamic>{};
    hsi['meta'] = meta;

    final provenance =
        (meta['provenance'] is Map<String, dynamic>)
            ? (meta['provenance'] as Map<String, dynamic>)
            : <String, dynamic>{};
    meta['provenance'] = provenance;

    final sources =
        (provenance['sources'] is Map<String, dynamic>)
            ? (provenance['sources'] as Map<String, dynamic>)
            : <String, dynamic>{};
    provenance['sources'] = sources;

    if (sources.isEmpty) {
      sources[defaultSourceId] = <String, dynamic>{
        'type': 'derived',
        'quality': 0.0,
        'degraded': false,
      };
    }

    final canonicalSourceId = sources.keys.first;

    // --- axes ---
    final axes = hsi['axes'];
    if (axes is Map<String, dynamic>) {
      // Drop non-schema categories, e.g. "affect".
      final keysToRemove =
          axes.keys
              .where((key) => !_validAxisCategories.contains(key))
              .toList();
      for (final key in keysToRemove) {
        axes.remove(key);
      }

      for (final category in axes.keys) {
        final entries = axes[category];
        if (entries is List) {
          for (var i = 0; i < entries.length; i++) {
            final entry = entries[i];
            if (entry is Map<String, dynamic>) {
              final sourceIds = entry['evidence_source_ids'];
              if (sourceIds is List) {
                final normalized =
                    sourceIds
                        .whereType<Object>()
                        .map((value) => value.toString())
                        .where((value) => value.isNotEmpty)
                        .toList();
                entry['evidence_source_ids'] =
                    normalized.isEmpty ? [canonicalSourceId] : normalized;
              } else {
                entry['evidence_source_ids'] = [canonicalSourceId];
              }

              final mode = entry['inference_mode'];
              if (mode == null || !_validInferenceModes.contains(mode)) {
                entry['inference_mode'] = 'deterministic';
              }
            }
          }
        }
      }
    }

    // --- windows.aggregation ---
    final windows = hsi['windows'];
    if (windows is Map<String, dynamic>) {
      for (final windowId in windows.keys) {
        final window = windows[windowId];
        if (window is Map<String, dynamic>) {
          final aggregation = window['aggregation']?.toString();
          if (aggregation == null ||
              !_validWindowAggregations.contains(aggregation)) {
            window['aggregation'] = 'windowed';
          }
        }
      }
    }

    // --- privacy.consent ---
    final privacy = hsi['privacy'];
    if (privacy is Map<String, dynamic>) {
      final consent = privacy['consent'];
      if (consent is Map<String, dynamic>) {
        consent['level'] = consent['level']?.toString() ?? 'explicit';
        consent['embedding'] = consent['embedding'] == true;
        consent['raw_biosignals'] = consent['raw_biosignals'] == true;
        consent['derived_metrics'] = consent['derived_metrics'] != false;
      } else {
        privacy['consent'] = <String, dynamic>{
          'level': consent?.toString() ?? 'explicit',
          'embedding': true,
          'raw_biosignals': false,
          'derived_metrics': true,
        };
      }
    }

    // --- producer.instance_id ---
    final producer = hsi['producer'];
    if (producer is Map<String, dynamic>) {
      producer.putIfAbsent('instance_id', () => const Uuid().v4());
    }

    return hsi;
  }

  Future<void> _attemptUpload() async {
    // Get batch from queue
    final batch = _uploadQueue.dequeueBatch(_rateLimiter.batchSize);
    if (batch.isEmpty) return;

    try {
      final capabilityLevel = _capabilities.capability(Module.cloud);
      final capabilityLevelStr = capabilityLevel
          .toString()
          .split('.')
          .last; // Convert enum to string

      // Build snapshots per API guide: each snapshot has "hsi" (object) and "timestamp" (ISO 8601).
      // Use observed_at_utc or computed_at_utc from HSI when present; otherwise fallback to now.
      final snapshots = <Map<String, dynamic>>[];
      for (final hsiJson in batch) {
        final hsiMap = jsonDecode(hsiJson) as Map<String, dynamic>;
        _patchHsiV1_1(hsiMap);
        final timestamp =
            (hsiMap['observed_at_utc'] as String?) ??
            (hsiMap['computed_at_utc'] as String?) ??
            DateTime.now().toUtc().toIso8601String();
        snapshots.add({'hsi': hsiMap, 'timestamp': timestamp});
      }

      SynheartLogger.log(
        '[CloudConnector] Uploading ${snapshots.length} HSI snapshots (v1.1 patched)',
      );

      // Create upload payload
      final payload = UploadRequest(
        userId: _config.subjectId,
        metadata: UploadMetadata(
          sdkVersion: '1.0.0',
          platform: platform_impl.currentIngestPlatform,
          capabilityLevel: capabilityLevelStr,
          orgId: _config.orgId,
        ),
        snapshots: snapshots,
      );

      // Get consent token if available
      final consentToken = _consent.getCurrentToken();

      // Sign and upload
      final response = await _uploadClient.upload(
        payload: payload,
        signer: _hmacSigner,
        apiKey: _config.apiKey,
        consentToken: consentToken,
        authProvider: _config.authProvider,
      );

      // Success - remove from queue
      _uploadQueue.confirmBatch(batch);

      _lastUploadBatchId = response.batchId;
      _lastUploadAt = DateTime.now();
      _lastUploadError = null;
      _lastUploadAttemptAt = DateTime.now();

      SynheartLogger.log(
        '[CloudConnector] Upload successful: ${response.batchId ?? response.message ?? "ok"}',
      );
    } catch (e) {
      // Handle token expiration - try to refresh
      if (e is TokenExpiredError) {
        SynheartLogger.log(
          '[CloudConnector] Token expired, attempting refresh...',
        );
        try {
          await _consent.refreshTokenIfNeeded();
          // Retry upload with new token (will happen on next HSI update)
          await _uploadQueue.requeueBatch(batch);
          return;
        } catch (refreshError) {
          SynheartLogger.log(
            '[CloudConnector] Token refresh failed: $refreshError',
            error: refreshError,
          );
        }
      }

      _lastUploadError = e.toString();
      _lastUploadAttemptAt = DateTime.now();

      if (e is SchemaValidationError) {
        _uploadQueue.confirmBatch(batch);
        SynheartLogger.log(
          '[CloudConnector] Schema validation failed — dropping ${batch.length} snapshots to avoid infinite retry',
        );
      } else {
        await _uploadQueue.requeueBatch(batch);
      }

      SynheartLogger.log(
        '[CloudConnector] Upload failed (non-blocking): $e',
        error: e,
      );

      // Don't rethrow - all errors are handled gracefully
      // Network errors and connector exceptions are expected and handled
      // The queue will be retried later when network conditions improve
    }
  }

  // Public API

  /// Enqueue raw HSI JSON strings collected externally (e.g. from a foreground
  /// session that ended before the Cloud Connector flushed) so they are
  /// included in the next [uploadNow] / [flushQueue] call.
  Future<void> enqueueSnapshots(List<String> hsiJsons) async {
    if (!_consent.current().cloudUpload) return;
    for (final hsiJson in hsiJsons) {
      await _uploadQueue.enqueue(hsiJson);
    }
    SynheartLogger.log(
      '[CloudConnector] Enqueued ${hsiJsons.length} external HSI snapshots; queue=${_uploadQueue.length}',
    );
  }

  /// Force upload of queued snapshots now
  Future<void> uploadNow() async {
    if (!_consent.current().cloudUpload) {
      throw ConsentRequiredError('cloudUpload consent required');
    }
    await _attemptUpload();
  }

  /// Flush entire upload queue
  ///
  /// This method will attempt to upload all queued items.
  /// It handles errors gracefully and does not throw exceptions.
  /// Upload failures are logged but do not prevent the queue from being processed.
  Future<void> flushQueue() async {
    int attempts = 0;
    const maxAttempts = 100; // Prevent infinite loops
    const throttleDelay = Duration(milliseconds: 100);

    while (_uploadQueue.hasItems &&
        _networkMonitor.isOnline &&
        attempts < maxAttempts) {
      attempts++;
      try {
        await _attemptUpload();
      } catch (e) {
        // Log error but continue processing queue
        SynheartLogger.log(
          '[CloudConnector] Upload attempt failed during flush (non-blocking): $e',
          error: e,
        );
        // If we hit a persistent error (like network failure), break early
        // to avoid wasting resources
        if (e is NetworkError || e is CloudConnectorException) {
          SynheartLogger.log(
            '[CloudConnector] Stopping flush due to persistent error. Queue will be retried later.',
          );
          break;
        }
      }
      await Future.delayed(throttleDelay); // Throttle between attempts
    }

    if (attempts >= maxAttempts) {
      SynheartLogger.log(
        '[CloudConnector] Flush stopped after $maxAttempts attempts. Remaining items will be retried later.',
      );
    }
  }

  /// Clear upload queue
  Future<void> clearQueue() async {
    await _uploadQueue.clear();
    SynheartLogger.log('[CloudConnector] Upload queue cleared');
  }
}
