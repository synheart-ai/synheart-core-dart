import 'dart:async';

import 'baseline_envelope.dart';
import 'baseline_kind.dart';
import 'baseline_payloads.dart';

/// Host-facing facade for typed baseline-snapshot access.
///
/// Exposed via `Synheart.baselineSnapshots`. Replaces the
/// `Map<String, dynamic>`-shaped legacy access pattern with typed
/// per-kind getters:
///
/// ```dart
/// final wear = Synheart.baselineSnapshots.latestLongitudinalWear();
/// if (wear != null) {
///   print('HRV baseline: ${wear.reference.dimensions['hrv_rmssd_ms']}');
/// }
/// ```
///
/// ## Cache model (Phase 1 — local-only)
///
/// In-memory cache populated by the on-device producer (engine state
/// → envelope writer). One row per [BaselineKind], last-write-wins.
///
/// What does NOT live in the cache yet:
/// - Cloud-fetched envelopes (cross-device restore). Hitting the cloud
///   needs a signed-device HTTP path that the Rust runtime owns; an
///   FFI bridge for the baseline endpoints arrives in a follow-up.
///   [restoreAll] and [upload] throw [UnimplementedError] until then.
class BaselineSnapshots {
  /// Singleton instance returned by `Synheart.baselineSnapshots`.
  /// Direct construction is allowed for tests.
  BaselineSnapshots();

  final Map<BaselineKind, BaselineEnvelope> _cache = {};

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
  ///
  /// Order is undefined — sort by `envelope.computedAtMs` if needed.
  Map<BaselineKind, BaselineEnvelope> envelopesByKind() =>
      Map.unmodifiable(_cache);

  /// Push an envelope into the cache. Called by the on-device
  /// producer (engine state → envelope writer) after each successful
  /// local snapshot. Last-write-wins per kind.
  void cache(BaselineEnvelope envelope) {
    _cache[envelope.kind] = envelope;
  }

  /// Forget every cached envelope. Called on logout / user switch.
  void reset() {
    _cache.clear();
  }

  // ---- Cloud paths (deferred — Phase 2) --------------------------------

  /// Hydrate the local cache from the cloud — one envelope per kind
  /// the user has on file. Used by the first-launch restore flow on a
  /// new device.
  ///
  /// **Not yet implemented.** Cloud restore needs a signed-device HTTP
  /// path; the runtime currently owns all signed-device HTTP, and an
  /// FFI bridge for the baseline endpoints arrives in a follow-up.
  /// Throws [UnimplementedError] until that bridge lands.
  Future<List<BaselineEnvelope>> restoreAll({required String subjectId}) {
    throw UnimplementedError(
      'BaselineSnapshots.restoreAll is not wired yet. '
      'It will land alongside the runtime FFI for the signed-device '
      'baseline upload/restore endpoints.',
    );
  }

  /// Push a locally-built envelope to the cloud so it can be restored
  /// on another device. The producer typically calls [cache] first
  /// (synchronous, makes the envelope readable via the typed getters)
  /// and then [upload] in the background.
  ///
  /// **Not yet implemented.** Same reason as [restoreAll].
  Future<void> upload(BaselineEnvelope envelope) {
    throw UnimplementedError(
      'BaselineSnapshots.upload is not wired yet. '
      'It will land alongside the runtime FFI for the signed-device '
      'baseline upload/restore endpoints.',
    );
  }
}
