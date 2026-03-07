import '../config/synheart_mode.dart';

/// Controls what may be persisted based on the current operational mode.
///
/// See RFC-CORE-0003 Section 6.
abstract class StoragePolicy {
  /// Whether this artifact type may be persisted.
  bool canPersistArtifact(String type);

  /// Whether this stream type may be persisted.
  bool canPersistStream(String streamType);

  /// Whether app metrics may be included in session summaries.
  bool canIncludeMetrics();

  /// Get the storage policy for the given mode.
  factory StoragePolicy.forMode(SynheartMode mode) {
    switch (mode) {
      case SynheartMode.personal:
        return const _PersonalPolicy();
      case SynheartMode.insight:
        return const _InsightPolicy();
      case SynheartMode.research:
        return const _ResearchPolicy();
    }
  }
}

class _PersonalPolicy implements StoragePolicy {
  const _PersonalPolicy();

  @override
  bool canPersistArtifact(String type) =>
      type == 'hsi_window' ||
      type == 'session_summary' ||
      type == 'baseline_snapshot' ||
      type == 'tombstone';

  @override
  bool canPersistStream(String streamType) => streamType == 'hsi.snapshot';

  @override
  bool canIncludeMetrics() => false;
}

class _InsightPolicy implements StoragePolicy {
  const _InsightPolicy();

  @override
  bool canPersistArtifact(String type) =>
      type == 'hsi_window' ||
      type == 'session_summary' ||
      type == 'baseline_snapshot' ||
      type == 'tombstone';

  @override
  bool canPersistStream(String streamType) =>
      streamType == 'hsi.snapshot' ||
      streamType == 'app.metrics' ||
      streamType == 'behavior.events';

  @override
  bool canIncludeMetrics() => true;
}

class _ResearchPolicy implements StoragePolicy {
  const _ResearchPolicy();

  @override
  bool canPersistArtifact(String type) => true;

  @override
  bool canPersistStream(String streamType) => true;

  @override
  bool canIncludeMetrics() => true;
}
