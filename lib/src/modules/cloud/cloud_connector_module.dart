import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class CloudConnectorModule extends BaseSynheartModule {
  @override
  String get moduleId => 'cloud';

  final CapabilityProvider _capabilities;
  final ConsentModule _consent;
  final RuntimeModule _hsiRuntime;
  final CloudConfig _config;

  // Components
  late final HMACSigner _hmacSigner;
  late final UploadClient _uploadClient;
  late final UploadQueue _uploadQueue;
  late final RateLimiter _rateLimiter;
  late final NetworkMonitor _networkMonitor;

  StreamSubscription? _hsvSubscription;
  StreamSubscription? _networkSubscription;

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

    _hmacSigner = HMACSigner(hmacSecret: _config.hmacSecret);
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

      // HSI JSON strings are already the canonical format from synheart-runtime
      final snapshots = batch.map((hsiJson) {
        return {
          'hsi_json': hsiJson,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };
      }).toList();

      // Create upload payload
      final payload = UploadRequest(
        userId: _config.subjectId,
        metadata: UploadMetadata(
          sdkVersion: '1.0.0',
          platform: 'dart',
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
      );

      // Success - remove from queue
      _uploadQueue.confirmBatch(batch);

      SynheartLogger.log(
        '[CloudConnector] Upload successful: ${response.status}',
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

      // Re-enqueue batch on failure
      await _uploadQueue.requeueBatch(batch);

      // Log error (but don't throw - this is background operation)
      // Errors are logged but do not propagate to prevent blocking initialization
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
