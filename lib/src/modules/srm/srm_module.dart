import '../../core/logger.dart';
import '../base/synheart_module.dart';
import 'srm_config.dart';
import 'srm_stratum.dart';
import 'srm_baseline_status.dart';
import 'srm_buffer.dart';
import 'srm_snapshot.dart';
import 'srm_types.dart';

/// SRM (Synheart Reference Model) module.
///
/// Maintains per-stratum bounded buffers of quality-gated candidate windows
/// and computes robust reference statistics (median/MAD) for each tracked
/// metric. This enables baseline-relative scoring when status reaches READY.
///
/// Implements RFC-CORE-0006 §3.3 and SRM.pdf.
class SRMModule extends BaseSynheartModule {
  @override
  String get moduleId => 'srm';

  final SRMConfig _config;

  /// Per-stratum buffers.
  final Map<SRMStratum, SRMBuffer> _buffers = {};

  SRMModule({SRMConfig config = const SRMConfig()}) : _config = config;

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[SRM] Initializing SRM module...');
    for (final stratum in SRMStratum.values) {
      _buffers[stratum] = SRMBuffer(stratum: stratum, config: _config);
    }
    SynheartLogger.log('[SRM] SRM module initialized (${_buffers.length} strata)');
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[SRM] SRM module started');
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[SRM] SRM module stopped');
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[SRM] Disposing SRM module...');
    _buffers.clear();
  }

  /// Submit a candidate window for SRM consideration.
  ///
  /// The window is quality-gated, outlier-checked, and (if accepted) added
  /// to the stratum buffer. Returns an [SRMResult] with acceptance status,
  /// baseline status, and current reference values.
  SRMResult submitCandidate(CandidateWindow candidate) {
    final buffer = _buffers[candidate.stratum];
    if (buffer == null) {
      return SRMResult(
        accepted: false,
        rejectionReason: 'unknown_stratum',
        baselineStatus: SRMBaselineStatus.empty,
        srmSnapshotId: 'srm_unknown_0',
        srmVersion: _config.srmVersion,
      );
    }
    return buffer.submit(candidate);
  }

  /// Query the current reference for a stratum.
  SRMReference? queryReference(SRMStratum stratum) {
    final buffer = _buffers[stratum];
    if (buffer == null || buffer.count == 0) return null;
    return SRMReference(
      stratum: stratum,
      status: buffer.baselineStatus,
      metrics: buffer.reference,
      bufferCount: buffer.count,
      distinctDays: buffer.distinctDays,
    );
  }

  /// Get baseline status for a stratum.
  SRMBaselineStatus baselineStatus(SRMStratum stratum) {
    return _buffers[stratum]?.baselineStatus ?? SRMBaselineStatus.empty;
  }

  /// Get the overall baseline status (worst across all strata with data).
  SRMBaselineStatus get overallBaselineStatus {
    var worst = SRMBaselineStatus.ready;
    var hasData = false;
    for (final buffer in _buffers.values) {
      if (buffer.count > 0) {
        hasData = true;
        final s = buffer.baselineStatus;
        if (s.index < worst.index) worst = s;
      }
    }
    return hasData ? worst : SRMBaselineStatus.empty;
  }

  /// Total number of accepted windows across all strata.
  int get totalAcceptedWindows {
    var total = 0;
    for (final buffer in _buffers.values) {
      total += buffer.count;
    }
    return total;
  }

  /// Total distinct calendar days across all strata.
  int get totalDistinctDays {
    final days = <String>{};
    for (final buffer in _buffers.values) {
      for (final entry in buffer.entries) {
        days.add(entry.dayKey);
      }
    }
    return days.length;
  }

  /// Take an in-memory snapshot of all SRM state.
  SRMSnapshot snapshot() {
    final strata = <SRMStratum, StratumSnapshot>{};
    for (final entry in _buffers.entries) {
      final buffer = entry.value;
      strata[entry.key] = StratumSnapshot(
        stratum: entry.key,
        status: buffer.baselineStatus,
        entries: List.from(buffer.entries),
        reference: Map.from(buffer.reference),
        distinctDays: buffer.distinctDays,
      );
    }
    return SRMSnapshot(
      srmVersion: _config.srmVersion,
      createdAtUtc: DateTime.now().toUtc(),
      strata: strata,
    );
  }

  /// Restore SRM state from a snapshot.
  void restoreSnapshot(SRMSnapshot snapshot) {
    if (snapshot.srmVersion != _config.srmVersion) {
      SynheartLogger.log(
        '[SRM] Warning: snapshot version ${snapshot.srmVersion} '
        'differs from config version ${_config.srmVersion}',
      );
    }
    for (final entry in snapshot.strata.entries) {
      final buffer = _buffers[entry.key];
      if (buffer != null) {
        buffer.restore(entry.value.entries);
      }
    }
    SynheartLogger.log('[SRM] Restored snapshot (${snapshot.strata.length} strata)');
  }

  /// Reset all buffers.
  void reset() {
    for (final buffer in _buffers.values) {
      buffer.reset();
    }
    SynheartLogger.log('[SRM] All buffers reset');
  }

  /// Access to config (for integration modules that need thresholds).
  SRMConfig get config => _config;
}
