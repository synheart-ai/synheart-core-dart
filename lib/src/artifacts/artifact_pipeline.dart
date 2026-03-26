import 'dart:convert';

import 'artifact_header.dart';
import 'baseline_snapshot.dart';
import 'hsi_window.dart';
import 'session_summary.dart';
import '../config/synheart_mode.dart';
import '../crypto/artifact_crypto.dart';
import '../crypto/smk.dart';
import '../storage/storage_manager.dart';
import '../storage/storage_policy.dart';

/// Bridges runtime HSI output to the artifact model and storage layer.
///
/// Accumulates HSI frames into 30-second windows, encrypts, and persists.
/// Produces SessionSummary on session close.
class ArtifactPipeline {
  final StorageManager _storage;
  final StoragePolicy _policy;
  final SMK _smk;
  final String _subjectId;
  final String _appId;
  final String _appVersion;
  final String _deviceId;
  final String _platform;

  static const int _windowSizeMs = 30000;

  // Current window accumulation state
  String? _currentSessionId;
  SynheartMode? _currentMode;
  int? _windowStartMs;
  int? _windowEndMs;
  final List<Map<String, dynamic>> _windowHsiFrames = [];
  int _windowSeq = 0;

  ArtifactPipeline({
    required StorageManager storage,
    required StoragePolicy policy,
    required SMK smk,
    required String subjectId,
    required String appId,
    required String appVersion,
    required String deviceId,
    required String platform,
  })  : _storage = storage,
        _policy = policy,
        _smk = smk,
        _subjectId = subjectId,
        _appId = appId,
        _appVersion = appVersion,
        _deviceId = deviceId,
        _platform = platform;

  /// Call when a session starts.
  void onSessionStart(String sessionId, SynheartMode mode) {
    _currentSessionId = sessionId;
    _currentMode = mode;
    _windowStartMs = null;
    _windowEndMs = null;
    _windowHsiFrames.clear();
    _windowSeq = 0;
  }

  /// Ingest an HSI JSON frame from the runtime tick.
  ///
  /// Accumulates frames. When the window duration reaches [_windowSizeMs],
  /// finalizes and persists an HSIWindow artifact.
  Future<HSIWindowArtifact?> ingestHsiFrame(
    String hsiJson,
    int timestampMs,
  ) async {
    if (_currentSessionId == null) return null;
    if (!_policy.canPersistArtifact('hsi_window')) return null;

    final hsiMap = jsonDecode(hsiJson) as Map<String, dynamic>;
    _windowHsiFrames.add(hsiMap);

    _windowStartMs ??= timestampMs;
    _windowEndMs = timestampMs;

    // Check if window is complete
    final elapsed = _windowEndMs! - _windowStartMs!;
    if (elapsed >= _windowSizeMs) {
      return _finalizeWindow();
    }
    return null;
  }

  /// Flush any partial window (called on session stop).
  Future<HSIWindowArtifact?> flushPendingWindow() async {
    if (_windowHsiFrames.isEmpty) return null;
    return _finalizeWindow();
  }

  Future<HSIWindowArtifact?> _finalizeWindow() async {
    if (_windowHsiFrames.isEmpty || _currentSessionId == null) return null;

    final startMs = _windowStartMs!;
    final endMs = _windowEndMs!;

    // Merge HSI frames — use the last frame as representative
    final mergedHsi = _windowHsiFrames.last;

    final artifact = HSIWindowArtifact.create(
      subjectId: _subjectId,
      sessionId: _currentSessionId!,
      startMs: startMs,
      endMs: endMs,
      hsi: mergedHsi,
      provenance: Provenance(
        source: _platform,
        deviceId: _deviceId,
        appId: _appId,
        runtimeVersion: '1.0.0',
      ),
    );

    // Encrypt and persist
    final encrypted = await ArtifactCrypto.encrypt(_smk, artifact.toJson());
    await _storage.insertArtifact(ArtifactRecord(
      artifactId: artifact.header.artifactId,
      sessionId: _currentSessionId,
      subjectId: _subjectId,
      type: 'hsi_window',
      schemaName: artifact.header.schema.name,
      schemaVersion: artifact.header.schema.version,
      startMs: startMs,
      endMs: endMs,
      seq: _windowSeq,
      createdAtMs: artifact.header.createdAtMs,
      encAlg: encrypted.encAlg,
      payload: encrypted.ciphertext,
      payloadSha256: encrypted.sha256,
    ));

    _windowSeq++;
    _windowHsiFrames.clear();
    _windowStartMs = null;
    _windowEndMs = null;

    return artifact;
  }

  /// Compute and persist a SessionSummary artifact. Called on session stop.
  Future<SessionSummaryArtifact?> finalizeSession(
    int sessionStartMs,
    int sessionEndMs,
  ) async {
    if (_currentSessionId == null || _currentMode == null) return null;
    if (!_policy.canPersistArtifact('session_summary')) return null;

    // Flush any remaining window
    await flushPendingWindow();

    // Query all HSI windows for this session
    final windowRecords = await _storage.getArtifactsBySession(
      _currentSessionId!,
      type: 'hsi_window',
    );

    // Decrypt and aggregate
    final List<Map<String, dynamic>> hsiPayloads = [];
    for (final record in windowRecords) {
      try {
        final payload = await ArtifactCrypto.decrypt(_smk, record.payload);
        hsiPayloads.add(payload);
      } catch (_) {
        // Skip corrupt records
      }
    }

    final aggregates = _computeAggregates(hsiPayloads);

    final includeMetrics = _policy.canIncludeMetrics();

    // Aggregate metrics if available
    List<AppMetric> appMetrics = [];
    if (includeMetrics) {
      try {
        final metricAggs =
            await _storage.aggregateMetrics(_currentSessionId!);
        appMetrics = metricAggs
            .map<AppMetric>((m) => AppMetric(
                  name: m['name'] as String,
                  mean: (m['mean'] as num?)?.toDouble() ?? 0.0,
                  count: (m['count'] as num?)?.toInt() ?? 0,
                ))
            .toList();
      } catch (_) {}
    }

    final artifact = SessionSummaryArtifact.create(
      subjectId: _subjectId,
      sessionId: _currentSessionId!,
      startMs: sessionStartMs,
      endMs: sessionEndMs,
      mode: _currentMode!.name,
      totalWindows: windowRecords.length,
      aggregates: aggregates,
      insightMetrics: includeMetrics
          ? InsightMetrics(appMetrics: appMetrics)
          : const InsightMetrics(),
    );

    final encrypted = await ArtifactCrypto.encrypt(_smk, artifact.toJson());
    await _storage.insertArtifact(ArtifactRecord(
      artifactId: artifact.header.artifactId,
      sessionId: _currentSessionId,
      subjectId: _subjectId,
      type: 'session_summary',
      schemaName: artifact.header.schema.name,
      schemaVersion: artifact.header.schema.version,
      startMs: sessionStartMs,
      endMs: sessionEndMs,
      createdAtMs: artifact.header.createdAtMs,
      encAlg: encrypted.encAlg,
      payload: encrypted.ciphertext,
      payloadSha256: encrypted.sha256,
    ));

    // Cache the summary JSON for fast reads
    await _storage.insertSummaryCache(
      sessionId: _currentSessionId!,
      artifactId: artifact.header.artifactId,
      summaryJson: jsonEncode(artifact.toJson()),
    );

    // Update session state
    await _storage.updateSession(
      _currentSessionId!,
      state: 'closed',
      endUtc: sessionEndMs ~/ 1000,
    );

    final sessionId = _currentSessionId;
    _currentSessionId = null;
    _currentMode = null;

    return artifact;
  }

  /// Produce a BaselineSnapshot artifact from a native runtime SRM export.
  ///
  /// [srmSnapshotJson] is the JSON string from `RuntimeBridge.exportSrmSnapshot()`.
  /// Called after session ends or on a periodic schedule.
  Future<BaselineSnapshotArtifact?> produceBaselineSnapshot(
    String srmSnapshotJson,
  ) async {
    if (!_policy.canPersistArtifact('baseline_snapshot')) return null;

    final srmData = jsonDecode(srmSnapshotJson) as Map<String, dynamic>;

    // Extract axis stats from SRM snapshot
    // The native runtime exports: { strata: { rest: { reference: { hr_mean: {median, mad}, ... }, count, days } } }
    final axes = _extractAxesFromSrm(srmData);
    if (axes == null) return null;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Coverage spans from the earliest data to now
    final coverageStartMs = (srmData['created_at_ms'] as int?) ??
        (nowMs - const Duration(days: 7).inMilliseconds);

    final totalWindows = _countSrmWindows(srmData);

    final baseline = BaselineData(
      coverage: BaselineCoverage(
        startMs: coverageStartMs,
        endMs: nowMs,
        totalWindows: totalWindows,
      ),
      axes: axes,
      model: ModelRef(
        modelId: (srmData['srm_version'] as String?) ?? 'srm_v1',
        modelVersion: '1.0.0',
      ),
    );

    final artifact = BaselineSnapshotArtifact.create(
      subjectId: _subjectId,
      baseline: baseline,
    );

    final encrypted = await ArtifactCrypto.encrypt(_smk, artifact.toJson());
    await _storage.insertArtifact(ArtifactRecord(
      artifactId: artifact.header.artifactId,
      subjectId: _subjectId,
      type: 'baseline_snapshot',
      schemaName: artifact.header.schema.name,
      schemaVersion: artifact.header.schema.version,
      startMs: coverageStartMs,
      endMs: nowMs,
      createdAtMs: artifact.header.createdAtMs,
      encAlg: encrypted.encAlg,
      payload: encrypted.ciphertext,
      payloadSha256: encrypted.sha256,
    ));

    return artifact;
  }

  BaselineAxes? _extractAxesFromSrm(Map<String, dynamic> srmData) {
    // The native runtime SRM export format includes reference metrics per stratum.
    // We map the "rest" stratum's reference metrics to baseline axes.
    final strata = srmData['strata'] as Map<String, dynamic>?;
    if (strata == null || strata.isEmpty) return null;

    // Use rest stratum if available, otherwise first available
    final restStratum = (strata['rest'] ?? strata.values.first) as Map<String, dynamic>?;
    if (restStratum == null) return null;

    final ref = restStratum['reference'] as Map<String, dynamic>? ?? {};

    double extractMean(String key) {
      final metric = ref[key] as Map<String, dynamic>?;
      return (metric?['median'] as num?)?.toDouble() ?? 0.0;
    }

    double extractStd(String key) {
      final metric = ref[key] as Map<String, dynamic>?;
      return (metric?['mad'] as num?)?.toDouble() ?? 0.0;
    }

    final count = (restStratum['count'] as int?) ?? 0;
    final confidence = count >= 50 ? 1.0 : count / 50.0;

    return BaselineAxes(
      sleep: AxisStats(mean: extractMean('sleep'), std: extractStd('sleep'), confidence: confidence),
      capacity: AxisStats(mean: extractMean('capacity'), std: extractStd('capacity'), confidence: confidence),
      arousal: AxisStats(mean: extractMean('arousal'), std: extractStd('arousal'), confidence: confidence),
      focus: AxisStats(mean: extractMean('focus'), std: extractStd('focus'), confidence: confidence),
    );
  }

  int _countSrmWindows(Map<String, dynamic> srmData) {
    final strata = srmData['strata'] as Map<String, dynamic>?;
    if (strata == null) return 0;
    int total = 0;
    for (final stratum in strata.values) {
      if (stratum is Map<String, dynamic>) {
        total += (stratum['count'] as int?) ?? 0;
      }
    }
    return total;
  }

  SessionAggregates _computeAggregates(List<Map<String, dynamic>> hsiPayloads) {
    if (hsiPayloads.isEmpty) {
      return const SessionAggregates(
        focus: AggregateAxis(mean: 0, min: 0, max: 0),
        arousal: AggregateAxis(mean: 0, min: 0, max: 0),
        capacity: AggregateAxis(mean: 0, min: 0, max: 0),
        sleep: AggregateAxis(mean: 0, min: 0, max: 0),
      );
    }

    // Extract axis values from HSI window payloads
    double focusSum = 0, focusMin = double.infinity, focusMax = double.negativeInfinity;
    double arousalSum = 0, arousalMin = double.infinity, arousalMax = double.negativeInfinity;
    double capacitySum = 0, capacityMin = double.infinity, capacityMax = double.negativeInfinity;
    double sleepSum = 0, sleepMin = double.infinity, sleepMax = double.negativeInfinity;
    int count = 0;

    for (final payload in hsiPayloads) {
      final window = payload['window'] as Map<String, dynamic>?;
      if (window == null) continue;
      final hsi = window['hsi'] as Map<String, dynamic>?;
      if (hsi == null) continue;

      count++;
      final f = (hsi['focus'] as num?)?.toDouble() ?? 0;
      final a = (hsi['arousal'] as num?)?.toDouble() ?? 0;
      final c = (hsi['capacity'] as num?)?.toDouble() ?? 0;
      final s = (hsi['sleep'] as num?)?.toDouble() ?? 0;

      focusSum += f; focusMin = f < focusMin ? f : focusMin; focusMax = f > focusMax ? f : focusMax;
      arousalSum += a; arousalMin = a < arousalMin ? a : arousalMin; arousalMax = a > arousalMax ? a : arousalMax;
      capacitySum += c; capacityMin = c < capacityMin ? c : capacityMin; capacityMax = c > capacityMax ? c : capacityMax;
      sleepSum += s; sleepMin = s < sleepMin ? s : sleepMin; sleepMax = s > sleepMax ? s : sleepMax;
    }

    if (count == 0) {
      return const SessionAggregates(
        focus: AggregateAxis(mean: 0, min: 0, max: 0),
        arousal: AggregateAxis(mean: 0, min: 0, max: 0),
        capacity: AggregateAxis(mean: 0, min: 0, max: 0),
        sleep: AggregateAxis(mean: 0, min: 0, max: 0),
      );
    }

    return SessionAggregates(
      focus: AggregateAxis(mean: focusSum / count, min: focusMin, max: focusMax),
      arousal: AggregateAxis(mean: arousalSum / count, min: arousalMin, max: arousalMax),
      capacity: AggregateAxis(mean: capacitySum / count, min: capacityMin, max: capacityMax),
      sleep: AggregateAxis(mean: sleepSum / count, min: sleepMin, max: sleepMax),
    );
  }
}
