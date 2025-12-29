import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../consent/consent_module.dart';
import '../hsi_runtime/hsi_runtime_module.dart';
import '../../config/synheart_config.dart';
import '../../models/hsv.dart';
import '../../models/hsi_export.dart';
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
  final HSIRuntimeModule _hsiRuntime;
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
    required HSIRuntimeModule hsiRuntime,
    required CloudConfig config,
  }) : _capabilities = capabilities,
       _consent = consent,
       _hsiRuntime = hsiRuntime,
       _config = config;

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[CloudConnector] Initializing Cloud Connector...');

    // 1. Initialize components
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

    // 2. Load persisted queue
    await _uploadQueue.loadFromStorage();

    SynheartLogger.log('[CloudConnector] Cloud Connector initialized');
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[CloudConnector] Starting Cloud Connector...');

    // 1. Subscribe to HSV stream
    _hsvSubscription = _hsiRuntime.hsiStream.listen(_handleHSVUpdate);

    // 2. Subscribe to network changes
    _networkSubscription = _networkMonitor.connectivityStream.listen(
      _handleNetworkChange,
    );

    // 3. Attempt to flush queue if online
    if (_networkMonitor.isOnline) {
      await flushQueue();
    }

    SynheartLogger.log('[CloudConnector] Cloud Connector started');
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[CloudConnector] Stopping Cloud Connector...');

    await _hsvSubscription?.cancel();
    await _networkSubscription?.cancel();
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[CloudConnector] Disposing Cloud Connector...');

    await _uploadQueue.persistToStorage();
    _uploadClient.dispose();
    _networkMonitor.dispose();
  }

  void _handleHSVUpdate(HumanStateVector hsv) async {
    // Check consent
    if (!_consent.current().cloudUpload) {
      return; // Silent return - no upload
    }

    // Check rate limit
    if (!_rateLimiter.canUpload(hsv.meta.embedding.windowType)) {
      return; // Silent return - rate limited
    }

    // Enqueue for upload
    await _uploadQueue.enqueue(hsv);

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
      // Convert to HSI 1.0
      final hsi10Snapshots = batch
          .map(
            (hsv) => hsv.toHSI10(
              producerName: 'Synheart Core SDK',
              producerVersion: '1.0.0',
              instanceId: _config.instanceId,
            ),
          )
          .toList();

      // Create upload payload
      final payload = UploadRequest(
        subject: Subject(
          subjectType: _config.subjectType,
          subjectId: _config.subjectId,
        ),
        snapshots: hsi10Snapshots.map((h) => h.toJson()).toList(),
      );

      // Sign and upload
      final response = await _uploadClient.upload(
        payload: payload,
        signer: _hmacSigner,
        tenantId: _config.tenantId,
      );

      // Success - remove from queue
      _uploadQueue.confirmBatch(batch);

      // Update rate limiter
      _rateLimiter.recordUpload(
        batch.first.meta.embedding.windowType,
        batchSize: batch.length,
      );

      SynheartLogger.log(
        '[CloudConnector] Upload successful: ${response.status}',
      );
    } catch (e) {
      // Re-enqueue batch on failure
      await _uploadQueue.requeueBatch(batch);

      // Log error (but don't throw - this is background operation)
      SynheartLogger.log('[CloudConnector] Upload failed: $e', error: e);
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
  Future<void> flushQueue() async {
    while (_uploadQueue.hasItems && _networkMonitor.isOnline) {
      await _attemptUpload();
      await Future.delayed(const Duration(milliseconds: 100)); // Throttle
    }
  }
}
