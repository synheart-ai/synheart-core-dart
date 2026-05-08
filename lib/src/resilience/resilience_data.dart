// SPDX-License-Identifier: Apache-2.0
//
// Source-aware data composition for the resilience engine.
//
// Hosts have HRV in three different aggregation levels depending on
// which wearable / API they're integrated with:
//
//   • raw beat-to-beat RR  — Polar H10, persisted Garmin BBI streams
//   • per-epoch RMSSD      — HealthKit `HKHeartRateVariabilitySDNN`
//   • per-night RMSSD      — Whoop recovery, Garmin daily, derived AH
//
// The resilience engine in `synheart-resilience` knows how to handle
// all three (since the per-kind config + dominant-kind detection
// landed). This module exposes a small abstraction that lets the
// SDK and host apps **compose** sources without each of them having
// to know the schema of the others — a Whoop-only user composes a
// `WhoopRecoverySamples` source, an HK user adds
// `HealthKitHrvSamples`, and a Polar user adds
// `BleHrmSessionSamples`. Each source declares its kind so the
// engine routes correctly.
//
// Concrete `HrvSampleSource` implementations live in the consumer
// app (pulse-focus / Mirror) — they know what storage their
// canonical-event store uses and can query it directly. The SDK
// only ships the contract + a couple of generic compose helpers.

import 'dart:async';

import '../modules/baselines/baselines.dart' show Baselines;
import '../synheart.dart' show Synheart;
import 'synheart_resilience.dart';

/// A pull-based source of HRV samples within a time range.
///
/// Implementations should normalize their vendor's payload to
/// [HrvSample] with the appropriate [HrvSampleKind]. They may
/// return an empty list — composers must tolerate this.
///
/// Side-effect-free: implementations should not mutate the engine
/// or any shared state. Calling [samples] multiple times for the
/// same range should return the same data.
abstract class HrvSampleSource {
  /// Identifier used for diagnostics / "where did this score come
  /// from" UI surfaces. Examples: `whoop_recovery`, `healthkit_hrv`,
  /// `polar_h10_session`.
  String get id;

  /// The aggregation level this source produces. Reported up-front
  /// so composers can route or weight by kind without having to
  /// inspect every returned sample.
  HrvSampleKind get kind;

  /// Pull samples for the range `[from, to]`. Sorting is not
  /// required — the engine sorts internally before filtering by
  /// sleep window. Implementations should bound work proportional
  /// to the date range; long ranges across years should be
  /// capped at the call site, not here.
  Future<List<HrvSample>> samples({
    required DateTime from,
    required DateTime to,
  });
}

/// A pull-based source of sleep windows.
///
/// Most hosts have one source of truth here ([Baselines]'s nightly
/// ledger), but the abstraction is symmetric with [HrvSampleSource]
/// so a future host can plug in something different (e.g. Apple
/// Health raw `HKCategoryValueSleepAnalysis` segments).
abstract class SleepWindowSource {
  String get id;

  Future<List<SleepWindow>> windows({
    required DateTime from,
    required DateTime to,
  });
}

/// SDK-provided source: pulls per-night RMSSD aggregates from
/// `Baselines._recentOvernight` + sleep windows from
/// `_recentNights`. Covers the Whoop / Garmin / Apple Health
/// vendor-sleep flow that the Baselines facade already ingests.
///
/// Hosts that *only* have vendor-sleep data can use this alone; the
/// resilience engine will compute a NightlyRmssd CV over the
/// available nights.
class BaselinesNightlyHrvSource implements HrvSampleSource {
  const BaselinesNightlyHrvSource();

  @override
  String get id => 'baselines_nightly';

  @override
  HrvSampleKind get kind => HrvSampleKind.nightlyRmssd;

  @override
  Future<List<HrvSample>> samples({
    required DateTime from,
    required DateTime to,
  }) async {
    // Baselines.recentHrvSamples returns synchronously and is
    // already capped at the SDK's prior-window. The from/to range
    // is currently advisory: in practice the recent ring is
    // always shorter than 7 days, which matches the resilience
    // engine's default lookback.
    return Baselines.recentHrvSamples
        .where(
          (s) =>
              s.tsMs >= from.millisecondsSinceEpoch &&
              s.tsMs <= to.millisecondsSinceEpoch,
        )
        .toList(growable: false);
  }
}

/// SDK-provided source: pulls sleep windows from the Baselines
/// nightly ledger. Same semantics as [BaselinesNightlyHrvSource].
class BaselinesSleepWindowSource implements SleepWindowSource {
  const BaselinesSleepWindowSource();

  @override
  String get id => 'baselines_nightly';

  @override
  Future<List<SleepWindow>> windows({
    required DateTime from,
    required DateTime to,
  }) async {
    return Baselines.recentSleepWindows
        .where(
          (w) =>
              w.endMs >= from.millisecondsSinceEpoch &&
              w.startMs <= to.millisecondsSinceEpoch,
        )
        .toList(growable: false);
  }
}

/// SDK-provided HRV source that queries the canonical event store
/// directly for a specific vendor's recovery records, bypassing the
/// Baselines lockstep ring entirely.
///
/// Why this exists alongside [BaselinesNightlyHrvSource]: Baselines
/// tracks a per-night ledger keyed on sleep payloads, and HRV from
/// recovery payloads only fills slots that match an existing sleep
/// night. With multiple providers on different sync cadences, some
/// nights' HRV stays detached from the ledger even though the data
/// is on disk in the canonical store. This source reads the store
/// directly: every recovery event with HRV becomes a sample, even
/// if its night never landed in `_recentNights`.
///
/// Composes additively with [BaselinesNightlyHrvSource]: the
/// resilience engine's `dominant_kind` filter handles the de-dup
/// at compute time (both sources emit `nightlyRmssd`), so users
/// with WHOOP + Garmin + Apple Health don't have a single bottleneck
/// at the Baselines layer.
class CanonicalEventStoreHrvSource implements HrvSampleSource {
  /// Build a source for one specific provider (`'whoop'`,
  /// `'garmin'`, etc.). The provider name matches the canonical
  /// event store's `provider` column — the same one used by
  /// `Synheart.queryVendorEvents(provider: ...)`.
  const CanonicalEventStoreHrvSource({required this.provider});

  final String provider;

  @override
  String get id => 'canonical_${provider}_recovery';

  @override
  HrvSampleKind get kind => HrvSampleKind.nightlyRmssd;

  @override
  Future<List<HrvSample>> samples({
    required DateTime from,
    required DateTime to,
  }) async {
    // Query the canonical type — what the storage row's `type` column
    // actually holds after `WearableEventProcessor` normalization.
    // The RAMEN-side `recovery.updated` is mapped to
    // `recovery.summary.recorded` before insert, so the older query
    // string returned empty.
    final events = Synheart.queryVendorEvents(
      provider: provider,
      type: 'recovery.summary.recorded',
      start: from,
      end: to,
      limit: 200,
    );
    if (events == null || events.isEmpty) return const [];

    final out = <HrvSample>[];
    for (final ev in events) {
      if (ev is! Map) continue;
      final observedAtMs = (ev['observed_at_ms'] as num?)?.toInt();
      if (observedAtMs == null) continue;
      final payload = ev['payload'] is Map
          ? Map<String, dynamic>.from(ev['payload'] as Map)
          : <String, dynamic>{};

      // Try top-level (flattened) first, then provider-nested
      // raw-vendor blob. Same shape-aware fallback the Baselines
      // facade uses, kept in lockstep so a payload that worked there
      // works here.
      double? hrv = _readDouble(payload['hrv_rmssd_ms']);
      if (hrv == null) {
        final raw = payload['${provider}_data'];
        if (raw is Map) {
          final score = raw['score'] is Map ? raw['score'] as Map : raw;
          hrv =
              _readDouble(score['hrv_rmssd_milli']) ??
              _readDouble(score['hrv_rmssd_ms']);
        }
      }
      if (hrv == null || hrv <= 0) continue;

      out.add(
        HrvSample(
          tsMs: observedAtMs,
          rmssdMs: hrv,
          kind: HrvSampleKind.nightlyRmssd,
        ),
      );
    }
    return out;
  }

  static double? _readDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Materialized inputs to a single resilience compute.
class ResilienceInput {
  const ResilienceInput({
    required this.samples,
    required this.sleepWindows,
    this.config = const ResilienceConfig(),
  });

  final List<HrvSample> samples;
  final List<SleepWindow> sleepWindows;
  final ResilienceConfig config;
}

/// Compose multiple HRV / sleep sources into one [ResilienceInput].
///
/// Default sources cover the multi-provider case for vendor sleep:
/// `BaselinesNightlyHrvSource` (the in-memory ring) plus a
/// `CanonicalEventStoreHrvSource` per supported provider that
/// queries the canonical event store directly. The per-provider
/// sources catch HRV the Baselines lockstep missed (e.g. a Whoop
/// recovery event that landed before its matching sleep night was
/// ingested). The engine's `dominant_kind` filter handles de-dup
/// at compute time.
///
/// Hosts with raw RR (Polar H10 sessions) or 5-minute epoch HRV
/// (HealthKit) can append additional sources; the composer just
/// concatenates and the engine routes by kind.
///
/// Sources are queried in parallel; per-source failures degrade to
/// empty lists rather than aborting the snapshot — partial data is
/// strictly better than no data for the resilience engine.
class ResilienceData {
  ResilienceData({
    Iterable<HrvSampleSource> hrvSources = _defaultHrvSources,
    Iterable<SleepWindowSource> sleepSources = const [
      BaselinesSleepWindowSource(),
    ],
    this.config = const ResilienceConfig(),
  }) : _hrvSources = List.unmodifiable(hrvSources),
       _sleepSources = List.unmodifiable(sleepSources);

  /// Default HRV source list. The Baselines ring is canonical for
  /// the matched-sleep-night case; the per-provider event-store
  /// sources pick up unmatched recoveries. New providers are added
  /// here as the SDK supports them.
  static const List<HrvSampleSource> _defaultHrvSources = [
    BaselinesNightlyHrvSource(),
    CanonicalEventStoreHrvSource(provider: 'whoop'),
    CanonicalEventStoreHrvSource(provider: 'garmin'),
  ];

  final List<HrvSampleSource> _hrvSources;
  final List<SleepWindowSource> _sleepSources;
  final ResilienceConfig config;

  /// Pull samples + windows over the configured lookback and
  /// return a [ResilienceInput] ready to feed to
  /// [SynheartResilience.compute].
  Future<ResilienceInput> snapshot({Duration? window}) async {
    final to = DateTime.now();
    final from = to.subtract(window ?? Duration(days: config.lookbackDays));

    // Hydrate `Baselines._recentOvernight` from the canonical event
    // store before reading. Closes the lockstep gap where a recovery
    // event landed in the store before its matching sleep night
    // (or vice-versa), leaving `_recentOvernight[i]` empty even
    // though the data was on disk. Cheap (one query) and idempotent.
    // Skipped silently if the runtime isn't initialised.
    await Baselines.hydrateOvernightFromEventStore(
      window: window ?? Duration(days: config.lookbackDays + 1),
    );

    Future<List<HrvSample>> safeSamples(HrvSampleSource s) async {
      try {
        return await s.samples(from: from, to: to);
      } catch (_) {
        return const [];
      }
    }

    Future<List<SleepWindow>> safeWindows(SleepWindowSource s) async {
      try {
        return await s.windows(from: from, to: to);
      } catch (_) {
        return const [];
      }
    }

    final samplesByList = await Future.wait(_hrvSources.map(safeSamples));
    final windowsByList = await Future.wait(_sleepSources.map(safeWindows));

    // De-duplicate samples that appear from multiple sources for the
    // same night. The Baselines ring and the canonical event-store
    // source overlap heavily for Whoop / Garmin nights — without
    // this, the resilience CV would see "two identical samples for
    // night N" → zero deviation contribution → inflated denominator
    // → artificially low CV → artificially high score.
    //
    // Dedup key: `(kind, calendar-day-of-tsMs)`. Two samples for the
    // same night and kind are the same night's reading from different
    // sources — keep the first. Different kinds or different days
    // pass through.
    const dayMs = 86_400_000;
    final seen = <String>{};
    final deduped = <HrvSample>[];
    for (final s in samplesByList.expand((xs) => xs)) {
      final dayKey = s.tsMs ~/ dayMs;
      final key = '${s.kind.wire}:$dayKey';
      if (seen.add(key)) {
        deduped.add(s);
      }
    }

    // Sleep windows: same overlap risk, dedup by start-day so a
    // night appearing in the ring AND a future event-store source
    // doesn't double-count toward `min_days_required`.
    final seenWindows = <int>{};
    final dedupedWindows = <SleepWindow>[];
    for (final w in windowsByList.expand((xs) => xs)) {
      final dayKey = w.startMs ~/ dayMs;
      if (seenWindows.add(dayKey)) {
        dedupedWindows.add(w);
      }
    }

    return ResilienceInput(
      samples: List.unmodifiable(deduped),
      sleepWindows: List.unmodifiable(dedupedWindows),
      config: config,
    );
  }
}
