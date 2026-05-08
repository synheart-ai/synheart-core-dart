// SPDX-License-Identifier: Apache-2.0
//
// Public types for the multi-source priority resolver.
//
// Mirrors the native runtime's `ingest/priority/types.rs`. When
// the runtime is loaded, calls are routed via FFI; in tests the same
// types drive a pure-Dart in-memory resolver.

/// Metric types that can have per-metric priority overrides.
///
/// String form is the wire format used by the FFI layer. **Stable —
/// changing it requires a runtime migration.**
enum PriorityMetric {
  heartRate('heart_rate'),
  hrv('hrv'),
  steps('steps'),
  sleep('sleep'),
  calories('calories'),
  spo2('spo2'),
  temperature('temperature'),
  stress('stress');

  const PriorityMetric(this.wireName);

  final String wireName;

  static PriorityMetric? fromWire(String name) {
    for (final m in PriorityMetric.values) {
      if (m.wireName == name) return m;
    }
    return null;
  }
}

/// Outcome of a single priority resolution.
class SourceResolution {
  const SourceResolution({
    required this.winner,
    required this.rank,
    required this.alsoRan,
  });

  /// The provider whose samples should be used.
  final String winner;

  /// Effective rank used to pick the winner.
  final int rank;

  /// Other providers that submitted samples for this metric, with
  /// their effective ranks. Sorted ascending by rank, then by name.
  final List<({String provider, int rank})> alsoRan;
}

/// Sentinel rank for unknown providers — matches the runtime's
/// [`ProviderRank::UNRANKED`] (32-bit max int).
const int kPriorityUnranked = 0x7fffffff;
