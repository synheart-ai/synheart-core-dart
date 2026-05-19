import 'dart:async';

import 'baseline_envelope.dart';
import 'baseline_kind.dart';
import 'baseline_payloads.dart';

/// Hook signature for "read every latest baseline envelope per kind
/// for the configured subject from local storage". No network — pure
/// SQLite + decryption. Wired by `Synheart` at SDK init from the
/// runtime bridge.
typedef BaselineLocalHydrator = Future<Map<String, dynamic>?> Function();

/// Host-facing facade for typed baseline-snapshot access.
///
/// Exposed via `Synheart.baselineSnapshots`. Replaces the
/// `Map<String, dynamic>`-shaped legacy access pattern with synchronous
/// per-kind typed getters:
///
/// ```dart
/// final wear = Synheart.baselineSnapshots.latestLongitudinalWear();
/// if (wear != null) {
///   print('HRV baseline: ${wear.reference.dimensions['hrv_rmssd_ms']}');
/// }
/// ```
///
/// ## Cache model
///
/// In-memory cache keyed by [BaselineKind], last-write-wins per kind.
/// Populated by:
/// - The on-device producer (engine state → envelope writer) via [cache].
/// - [hydrateFromLocal] on cold-start, reading the latest of each kind
///   from on-device storage (including envelopes synced from other
///   devices via the sync engine).
///
/// ## Cross-device transport
///
/// Baselines do **not** have their own cloud client on this facade.
/// They ride the existing sync engine: a baseline envelope written
/// here lands in the local `artifacts` table with `sync_state='pending'`
/// and the sync engine pushes it on its normal cadence. Envelopes
/// pulled from other devices land in the same table and are picked up
/// by [hydrateFromLocal] on init (or by any explicit re-hydrate).
class BaselineSnapshots {
  /// Singleton instance returned by `Synheart.baselineSnapshots`.
  /// Direct construction is allowed for tests.
  BaselineSnapshots();

  final Map<BaselineKind, BaselineEnvelope> _cache = {};
  BaselineLocalHydrator? _localHydrator;

  /// The most recent envelope for [kind], or `null` if no producer
  /// has cached one yet. Synchronous — reads in-memory state.
  BaselineEnvelope? envelopeFor(BaselineKind kind) => _cache[kind];

  /// Latest `session.hsi_axes` baseline, or `null` if none cached.
  HsiAxesBaseline? latestHsiAxes() {
    final env = _cache[BaselineKind.sessionHsiAxes];
    return env?.payloadHsiAxes();
  }

  /// Latest `session.srm_metrics` baseline, or `null` if none cached.
  SessionSrmMetricsBaseline? latestSrmMetrics() {
    final env = _cache[BaselineKind.sessionSrmMetrics];
    return env?.payloadSrmMetrics();
  }

  /// Latest `longitudinal.wear` baseline, or `null` if none cached.
  LongitudinalWearBaseline? latestLongitudinalWear() {
    final env = _cache[BaselineKind.longitudinalWear];
    return env?.payloadLongitudinalWear();
  }

  /// Unmodifiable snapshot of every kind that currently has a cached
  /// envelope. Powers the first-launch hydration UI ("show me one
  /// summary per baseline kind the user has on file").
  Map<BaselineKind, BaselineEnvelope> envelopesByKind() =>
      Map.unmodifiable(_cache);

  /// Push an envelope into the cache. Called by the on-device producer
  /// (engine state → envelope writer) after each successful local
  /// snapshot, and by [hydrateFromLocal] after a storage read.
  /// Last-write-wins per kind.
  void cache(BaselineEnvelope envelope) {
    _cache[envelope.kind] = envelope;
  }

  /// Forget every cached envelope. Called on logout / user switch.
  void reset() {
    _cache.clear();
  }

  // ---- Local hydration ------------------------------------------------

  /// Inject the local-storage hydrator. Called by `Synheart` after the
  /// runtime bridge is configured. Pass `null` to clear (e.g. after
  /// disposing the bridge).
  void wireLocalHydrator(BaselineLocalHydrator? hydrator) {
    _localHydrator = hydrator;
  }

  /// Populate the in-memory cache from locally-persisted artifacts.
  /// Called by `Synheart` on bridge construction so the typed getters
  /// ([latestHsiAxes], [latestSrmMetrics], [latestLongitudinalWear])
  /// return real data immediately after app cold-start, without
  /// requiring a producer to run first.
  ///
  /// No-op when the hydrator hasn't been wired (older runtime binaries
  /// that don't ship the hydrate FFI). Returns the list of envelopes
  /// that successfully landed in the cache (empty when nothing was on
  /// disk). Envelopes whose `kind` this SDK can't decode are silently
  /// skipped — forward-compat for kinds added in a newer runtime.
  Future<List<BaselineEnvelope>> hydrateFromLocal() async {
    final hydrator = _localHydrator;
    if (hydrator == null) return const [];
    final resp = await hydrator();
    if (resp == null) return const [];
    if (resp['error'] is String) return const [];

    final raw = resp['snapshots'];
    if (raw is! List) return const [];

    final out = <BaselineEnvelope>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        final envelope = BaselineEnvelope.fromJson(
          entry.cast<String, dynamic>(),
        );
        cache(envelope);
        out.add(envelope);
      } on FormatException {
        // Forward-compat: skip envelopes the SDK can't decode.
        continue;
      }
    }
    return out;
  }
}
