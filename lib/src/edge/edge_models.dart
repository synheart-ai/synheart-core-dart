// SPDX-License-Identifier: Apache-2.0

/// Typed models for the Synheart **edge wire contract** (watch → phone).
///
/// These mirror the Kotlin (`EdgeIngest.HrSample/BioSample/HsiArtifact`) and
/// Swift (`EdgeIngest.HrSample/BioSample/Artifact`) reference implementations
/// exactly, expressed idiomatically in pure Dart so the edge core unit-tests
/// without any Flutter dependency.
///
/// Wire keys / units (see `EDGE-WIRE-CONTRACT.md` §2–§3, in the synheart-edge repo):
///  - timestamps are epoch **milliseconds**, `_ms` suffix;
///  - HR `bpm` is a double;
///  - `rr_intervals_ms` is an array of doubles, empty when omitted;
///  - `accel` is `{x,y,z}` in g, null when omitted (never fabricated).
library;

/// §3.1 — a scalar HR sample.
class HrSample {
  /// Beats per minute.
  final double bpm;

  /// Sample time, epoch milliseconds.
  final int timestampMs;

  /// Producer source (e.g. `healthkit`); null when omitted.
  final String? source;

  const HrSample({
    required this.bpm,
    required this.timestampMs,
    this.source,
  });

  @override
  bool operator ==(Object other) =>
      other is HrSample &&
      other.bpm == bpm &&
      other.timestampMs == timestampMs &&
      other.source == source;

  @override
  int get hashCode => Object.hash(bpm, timestampMs, source);

  @override
  String toString() =>
      'HrSample(bpm: $bpm, timestampMs: $timestampMs, source: $source)';
}

/// §2 — three-axis acceleration, in g.
class Accel {
  final double x;
  final double y;
  final double z;

  const Accel({required this.x, required this.y, required this.z});

  @override
  bool operator ==(Object other) =>
      other is Accel && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Accel(x: $x, y: $y, z: $z)';
}

/// §3.2 — a full raw biosignal sample (HR + RR + optional accel).
class BioSample {
  /// Beats per minute.
  final double bpm;

  /// Sample time, epoch milliseconds.
  final int timestampMs;

  /// RR intervals in ms; empty when the producer omitted/emptied them (§2).
  final List<double> rrIntervalsMs;

  /// Optional accel triple in g; null when omitted (§2).
  final Accel? accel;

  /// Producer source; null when omitted.
  final String? source;

  const BioSample({
    required this.bpm,
    required this.timestampMs,
    required this.rrIntervalsMs,
    this.accel,
    this.source,
  });

  @override
  String toString() => 'BioSample(bpm: $bpm, timestampMs: $timestampMs, '
      'rrIntervalsMs: $rrIntervalsMs, accel: $accel, source: $source)';
}

/// §3.3 — an accepted (hash-verified, non-duplicate) HSI artifact envelope.
///
/// [payloadJson] is the opaque HSI JSON; [hsiVersionSupported] reflects the §0
/// version check. The artifact is still surfaced when [hsiVersionSupported] is
/// false — producer drift is flagged, not dropped.
class HsiArtifact {
  final String artifactId;
  final String? sessionId;
  final int? seq;
  final int? createdAtMs;
  final String? schemaVersion;
  final String? hsiVersion;
  final String payloadHashSha256;
  final String payloadJson;
  final String? deliveryMode;
  final String? sessionOrigin;
  final String? sessionKind;

  /// True when [hsiVersion] is present AND inside the supported set (§0).
  final bool hsiVersionSupported;

  const HsiArtifact({
    required this.artifactId,
    this.sessionId,
    this.seq,
    this.createdAtMs,
    this.schemaVersion,
    this.hsiVersion,
    required this.payloadHashSha256,
    required this.payloadJson,
    this.deliveryMode,
    this.sessionOrigin,
    this.sessionKind,
    required this.hsiVersionSupported,
  });

  @override
  String toString() => 'HsiArtifact(artifactId: $artifactId, '
      'hsiVersion: $hsiVersion, hsiVersionSupported: $hsiVersionSupported, '
      'payloadHashSha256: $payloadHashSha256)';
}

/// A session event whose `type` is none of the three sample/artifact
/// discriminators (e.g. `session_started`, `session_frame`,
/// `session_summary`; contract §3.4). The raw body is passed through unparsed
/// so the host can route by `type` without this core depending on every event
/// shape.
class EdgeSessionEvent {
  /// The wire `type` value.
  final String type;

  /// The raw decoded body.
  final Map<String, dynamic> body;

  const EdgeSessionEvent({required this.type, required this.body});

  @override
  String toString() => 'EdgeSessionEvent(type: $type)';
}

/// Sealed family of typed edge events emitted on [EdgeIngest.events].
///
/// Use exhaustive `switch` for ergonomic consumption:
/// ```dart
/// ingest.events.listen((event) {
///   switch (event) {
///     case HrEvent(:final sample): ...
///     case BioEvent(:final sample): ...
///     case ArtifactEvent(:final artifact): ...
///     case SessionEventWrap(:final event): ...
///   }
/// });
/// ```
sealed class EdgeEvent {
  const EdgeEvent();
}

/// §3.1 — an HR sample was parsed.
class HrEvent extends EdgeEvent {
  final HrSample sample;
  const HrEvent(this.sample);
}

/// §3.2 — a biosignal sample was parsed.
class BioEvent extends EdgeEvent {
  final BioSample sample;
  const BioEvent(this.sample);
}

/// §3.3 — an artifact was accepted (verified + non-duplicate).
class ArtifactEvent extends EdgeEvent {
  final HsiArtifact artifact;
  const ArtifactEvent(this.artifact);
}

/// §3.4 — a non-sample/-artifact session event.
class SessionEventWrap extends EdgeEvent {
  final EdgeSessionEvent event;
  const SessionEventWrap(this.event);
}
