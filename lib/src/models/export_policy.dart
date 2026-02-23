/// Export policy aligned with synheart-flux HSV.
///
/// Mirrors Flux `ExportPolicy` — controls which domains, axes, and
/// confidence thresholds appear in exported HSI payloads.

/// Controls what data is included when exporting HSV to HSI 1.0.
///
/// Pass an [ExportPolicy] to filter readings by domain, confidence
/// threshold, or purpose. The default policy exports all available
/// domains with no confidence filtering.
class ExportPolicy {
  /// Include physiology domain readings in the export.
  final bool includePhysiology;

  /// Include behavior domain readings in the export.
  final bool includeBehavior;

  /// Include context domain readings in the export.
  final bool includeContext;

  /// Include the 64D embedding vector in the export.
  final bool includeEmbedding;

  /// Minimum confidence threshold for axis readings.
  /// Readings below this confidence are excluded from HSI output.
  final double minConfidence;

  /// Intended purposes for this export (e.g., "analytics", "display").
  /// Empty list means no purpose restriction.
  final List<String> purposes;

  /// Include additional metadata in the HSI `meta` block.
  final bool includeMeta;

  const ExportPolicy({
    this.includePhysiology = true,
    this.includeBehavior = true,
    this.includeContext = true,
    this.includeEmbedding = true,
    this.minConfidence = 0.0,
    this.purposes = const [],
    this.includeMeta = true,
  });

  /// Default policy: export everything, no filtering.
  static const ExportPolicy defaultPolicy = ExportPolicy();

  /// Minimal policy: physiology only, no embedding.
  static const ExportPolicy physiologyOnly = ExportPolicy(
    includeBehavior: false,
    includeContext: false,
    includeEmbedding: false,
  );
}
