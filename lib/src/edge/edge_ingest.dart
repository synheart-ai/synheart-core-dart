// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';

import 'edge_models.dart';

/// Transport-independent, **pure-Dart** consumer of the Synheart edge wire
/// contract (watch → phone). This is the phone-side counterpart to the watch
/// producer; it exists so every Flutter app stops re-implementing watch→phone
/// ingest — the canonical parse/validate/dedupe/ack logic lives here once.
///
/// It is the Dart member of the cross-platform `EdgeIngest` matrix and mirrors
/// the Kotlin (`ai.synheart.core.edge.EdgeIngest`) and Swift
/// (`SynheartCore.EdgeIngest`) implementations for behaviour parity: same
/// callback names, same dedupe-by-`artifact_id`, same lowercase-hex SHA-256
/// hash policy, same absent/out-of-set `hsi_version` flagging, and the same
/// `{ "command": "artifact_ack", "artifact_ids": [...] }` ACK body shape.
///
/// It holds **no** Flutter import so it compiles and unit-tests standalone
/// (`dart test` / `flutter test`). Logging goes through `dart:developer log`
/// by default, overridable via [logSink] so a host can route into
/// `SynheartLogger` without this core taking a Flutter dependency.
///
/// ## Contract mapping (`EDGE-WIRE-CONTRACT.md` in the synheart-edge repo)
///  - §3.1 `hr_sample`    → [EdgeIngestListener.onHrSample] / [HrEvent]
///  - §3.2 `bio_sample`   → [EdgeIngestListener.onBioSample] / [BioEvent]
///  - §3.3 `hsi_artifact` → validate hash (§5) + version (§0), dedupe (§5),
///    then [EdgeIngestListener.onArtifact] / [ArtifactEvent]
///  - §3.4 / events       → [EdgeIngestListener.onSessionEvent] /
///    [SessionEventWrap]
///  - §4/§5 ACK           → [drainPendingAcks] / [buildAckBody] /
///    [drainAckBody]
///
/// Malformed or unknown bodies are dropped + logged; this class never throws.
class EdgeIngest {
  /// EDGE-WIRE-CONTRACT.md §0 — supported inner HSI payload versions for consumers in
  /// this generation. A payload outside this set (or absent) is flagged/logged
  /// as producer drift but still surfaced.
  static const Set<String> supportedHsiVersions = {'1.1', '1.2', '1.3'};

  /// After this many hash mismatches for the SAME `artifact_id`, the
  /// artifact is dead-lettered (hard error + ack-to-discard) so a
  /// deterministically-corrupt artifact stops resending forever (contract §5).
  static const int poisonPillThreshold = 3;

  /// Cap of the seen-artifact LRU. Re-acking a long-evicted
  /// stray is harmless per contract §5, so eviction is safe.
  static const int seenLruCapacity = 4096;

  // Body `type` discriminators (EDGE-WIRE-CONTRACT.md §1 table + §3).
  static const String typeHrSample = 'hr_sample';
  static const String typeBioSample = 'bio_sample';
  static const String typeHsiArtifact = 'hsi_artifact';

  // §4 command body.
  static const String commandArtifactAck = 'artifact_ack';

  // Wire keys (EDGE-WIRE-CONTRACT.md §2, §3.1–§3.3, §4).
  static const String _keyType = 'type';
  static const String _keyBpm = 'bpm';
  static const String _keyTimestampMs = 'timestamp_ms';
  static const String _keySource = 'source';
  static const String _keyRrIntervalsMs = 'rr_intervals_ms';
  static const String _keyAccel = 'accel';
  static const String _keyArtifactId = 'artifact_id';
  static const String _keySessionId = 'session_id';
  static const String _keySeq = 'seq';
  static const String _keyCreatedAtMs = 'created_at_ms';
  static const String _keySchemaVersion = 'schema_version';
  static const String _keyHsiVersion = 'hsi_version';
  static const String _keyPayloadHash = 'payload_hash_sha256';
  static const String _keyPayloadJson = 'payload_json';
  static const String _keyDeliveryMode = 'delivery_mode';
  static const String _keySessionOrigin = 'session_origin';
  static const String _keySessionKind = 'session_kind';
  static const String _keyCommand = 'command';
  static const String _keyArtifactIds = 'artifact_ids';

  /// Optional typed callbacks (parity with the Swift `Delegate` / Kotlin
  /// `Listener`). All hooks are optional.
  final EdgeIngestListener? listener;

  /// Inner HSI payload versions this consumer understands (§0).
  final Set<String> _supported;

  /// Log routing override; defaults to `dart:developer log`. A Flutter host can
  /// pass `SynheartLogger.log` to unify logging without this core importing
  /// Flutter.
  final void Function(String message) _log;

  // §5 — dedupe / ACK state. Single-isolate by design; ordered via
  // insertion-order `LinkedHashSet`. `_seenArtifactIds` is a bounded LRU:
  // insertion order is treated as recency by [_recordSeen]
  // (re-insert to refresh, evict eldest over [seenLruCapacity]).
  final Set<String> _seenArtifactIds = <String>{};
  final Set<String> _pendingAckIds = <String>{};

  /// Per-id hash-mismatch counter for poison-pill detection.
  final Map<String, int> _mismatchCounts = <String, int>{};

  final StreamController<EdgeEvent> _events =
      StreamController<EdgeEvent>.broadcast();

  EdgeIngest({
    this.listener,
    Set<String> supportedHsiVersions = EdgeIngest.supportedHsiVersions,
    void Function(String message)? logSink,
  }) : _supported = supportedHsiVersions,
       _log = logSink ?? _defaultLog;

  static void _defaultLog(String message) =>
      developer.log(message, name: 'synheart.edge');

  /// Broadcast stream of typed edge events (Flutter ergonomics). Fires in
  /// lock-step with the [listener] callbacks.
  ///
  /// NOT AUTHORITATIVE: the synchronous [listener] is the source of truth for
  /// "received"; `acked + seen` state is updated independently of whether any
  /// stream subscriber is attached (a broadcast `Stream` drops events when there
  /// is no listener). This stream is an additive,
  /// best-effort convenience.
  Stream<EdgeEvent> get events => _events.stream;

  /// Consume one decoded wire body. Routes by `type` (§1). Never throws:
  /// malformed/unknown bodies return [Dropped] and are logged.
  EdgeOutcome ingest(Map<String, dynamic> body) {
    try {
      final typeRaw = body[_keyType];
      if (typeRaw is! String || typeRaw.isEmpty) {
        return _drop('missing/blank `type` field');
      }
      switch (typeRaw) {
        case typeHrSample:
          return _ingestHrSample(body);
        case typeBioSample:
          return _ingestBioSample(body);
        case typeHsiArtifact:
          return _ingestArtifact(body);
        default:
          // §3.4 — not a sample/artifact discriminator → session event.
          final event = EdgeSessionEvent(type: typeRaw, body: body);
          listener?.onSessionEvent(event);
          _emit(SessionEventWrap(event));
          return SessionEventOutcome(typeRaw);
      }
    } catch (e) {
      // Contract: never throw on malformed input. Drop + log.
      return _drop('malformed body: $e');
    }
  }

  /// Convenience: parse a raw JSON string body and dispatch. Never throws.
  EdgeOutcome ingestRaw(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (e) {
      return _drop('unparseable JSON body: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      return _drop('JSON body is not an object');
    }
    return ingest(decoded);
  }

  // --- §3.1 hr_sample ----------------------------------------------------

  EdgeOutcome _ingestHrSample(Map<String, dynamic> body) {
    final bpm = _toDouble(body[_keyBpm]);
    if (bpm == null) return _drop('hr_sample missing/invalid `bpm`');
    final ts = _toInt(body[_keyTimestampMs]);
    if (ts == null) return _drop('hr_sample missing/invalid `timestamp_ms`');

    final sample = HrSample(
      bpm: bpm,
      timestampMs: ts,
      source: _nonEmptyString(body[_keySource]),
    );
    listener?.onHrSample(sample);
    _emit(HrEvent(sample));
    return HrSampleOutcome(sample);
  }

  // --- §3.2 bio_sample ---------------------------------------------------

  EdgeOutcome _ingestBioSample(Map<String, dynamic> body) {
    final bpm = _toDouble(body[_keyBpm]);
    if (bpm == null) return _drop('bio_sample missing/invalid `bpm`');
    final ts = _toInt(body[_keyTimestampMs]);
    if (ts == null) return _drop('bio_sample missing/invalid `timestamp_ms`');

    final sample = BioSample(
      bpm: bpm,
      timestampMs: ts,
      rrIntervalsMs: _toDoubleList(body[_keyRrIntervalsMs]),
      accel: _parseAccel(body[_keyAccel]),
      source: _nonEmptyString(body[_keySource]),
    );
    listener?.onBioSample(sample);
    _emit(BioEvent(sample));
    return BioSampleOutcome(sample);
  }

  // --- §3.3 hsi_artifact -------------------------------------------------

  EdgeOutcome _ingestArtifact(Map<String, dynamic> body) {
    final artifactId = _nonEmptyString(body[_keyArtifactId]);
    if (artifactId == null) {
      return _drop('hsi_artifact missing/invalid `artifact_id`');
    }
    final payloadJson = _nonEmptyString(body[_keyPayloadJson]);
    if (payloadJson == null) {
      return _drop('hsi_artifact missing `payload_json` (id=$artifactId)');
    }
    final declaredHash = _nonEmptyString(body[_keyPayloadHash]);
    if (declaredHash == null) {
      return _drop(
        'hsi_artifact missing `payload_hash_sha256` (id=$artifactId)',
      );
    }

    // §5 — verify payload_hash_sha256 == sha256(payload_json).
    final computed = sha256Hex(payloadJson);
    if (computed.toLowerCase() != declaredHash.toLowerCase()) {
      // A deterministically-corrupt artifact would otherwise be
      // rejected-without-ack forever and starve the delete-on-ACK outbox. Count
      // per-id mismatches; after [poisonPillThreshold], dead-letter it (hard
      // error + ack-to-discard). The first/normal mismatch keeps the old
      // behaviour: reject, don't surface, don't ack, don't record as seen.
      final attempts = (_mismatchCounts[artifactId] ?? 0) + 1;
      _mismatchCounts[artifactId] = attempts;
      if (attempts >= poisonPillThreshold) {
        _log(
          '[EdgeIngest] artifact $artifactId hash mismatch x$attempts '
          '(declared=$declaredHash computed=$computed) — dead-lettering: '
          'ack-to-discard so it stops blocking the outbox',
        );
        _mismatchCounts.remove(artifactId);
        _recordSeen(artifactId);
        _pendingAckIds.add(artifactId);
        listener?.onPoisonPill(artifactId, declaredHash, computed, attempts);
        return ArtifactDeadLettered(artifactId);
      }
      _log(
        '[EdgeIngest] artifact $artifactId rejected (attempt $attempts): '
        'payload_hash_sha256 mismatch (declared=$declaredHash computed=$computed)',
      );
      return ArtifactHashMismatch(artifactId);
    }

    // §5 — dedupe by artifact_id. On a duplicate, DO NOT re-surface, but STILL
    // queue the id for ACK (idempotent set) and return: the watch outbox
    // is delete-on-ACK, so a lost ACK makes it resend forever; re-acking
    // duplicates is the whole point.
    if (_seenArtifactIds.contains(artifactId)) {
      _log(
        '[EdgeIngest] artifact $artifactId duplicate — re-acking, not re-surfacing',
      );
      _pendingAckIds.add(artifactId);
      _recordSeen(artifactId); // refresh LRU recency
      return ArtifactDuplicate(artifactId);
    }
    _recordSeen(artifactId);
    _pendingAckIds.add(artifactId);

    // §0 — hsi_version: prefer the envelope key, fall back to the payload's
    // own `hsi_version` (parity with Kotlin's `extractHsiVersionFromPayload`).
    // Flag both an out-of-set value AND an absent one (parity with Kotlin/Swift,
    // which both flag absent), but still surface.
    final hsiVersion =
        _nonEmptyString(body[_keyHsiVersion]) ??
        _extractHsiVersionFromPayload(payloadJson);
    final supported = hsiVersion != null && _supported.contains(hsiVersion);
    if (!supported) {
      final shown = hsiVersion ?? '(absent)';
      _log(
        '[EdgeIngest] artifact $artifactId hsi_version "$shown" outside '
        'supported set $_supported — producer drift, surfacing anyway',
      );
    }

    final artifact = HsiArtifact(
      artifactId: artifactId,
      sessionId: _nonEmptyString(body[_keySessionId]),
      seq: _toInt(body[_keySeq]),
      createdAtMs: _toInt(body[_keyCreatedAtMs]),
      schemaVersion: _nonEmptyString(body[_keySchemaVersion]),
      hsiVersion: hsiVersion,
      payloadHashSha256: declaredHash,
      payloadJson: payloadJson,
      deliveryMode: _nonEmptyString(body[_keyDeliveryMode]),
      sessionOrigin: _nonEmptyString(body[_keySessionOrigin]),
      sessionKind: _nonEmptyString(body[_keySessionKind]),
      hsiVersionSupported: supported,
    );
    listener?.onArtifact(artifact);
    _emit(ArtifactEvent(artifact));
    return ArtifactAccepted(artifact);
  }

  // --- §4/§5 ACK ---------------------------------------------------------

  /// Snapshot the ids accepted since the last drain and clear the pending set,
  /// in arrival order. Use with [buildAckBody] (or [drainAckBody]) to send the
  /// ACK on the command channel; ids are considered handed off once drained.
  List<String> drainPendingAcks() {
    if (_pendingAckIds.isEmpty) return const <String>[];
    final ids = _pendingAckIds.toList(growable: false);
    _pendingAckIds.clear();
    return ids;
  }

  /// Build the §4/§5 ACK command body for [artifactIds]:
  /// `{ "command": "artifact_ack", "artifact_ids": [...] }`. Returns null when
  /// [artifactIds] is empty (nothing to ack).
  Map<String, dynamic>? buildAckBody(List<String> artifactIds) {
    if (artifactIds.isEmpty) return null;
    return <String, dynamic>{
      _keyCommand: commandArtifactAck,
      _keyArtifactIds: List<String>.from(artifactIds),
    };
  }

  /// Drain pending acks and build the ACK body in one step. Null when empty.
  Map<String, dynamic>? drainAckBody() => buildAckBody(drainPendingAcks());

  /// Number of distinct artifact ids seen (accepted) so far.
  int seenCount() => _seenArtifactIds.length;

  /// Ids accepted but not yet drained into an ACK (read-only snapshot).
  List<String> get pendingAckIds => _pendingAckIds.toList(growable: false);

  /// Release the broadcast stream controller. Idempotent.
  Future<void> dispose() => _events.close();

  // --- helpers -----------------------------------------------------------

  /// Insert [artifactId] into the bounded LRU [_seenArtifactIds], refreshing
  /// recency (re-insert moves it to the most-recent position) and evicting the
  /// eldest while over [seenLruCapacity].
  void _recordSeen(String artifactId) {
    _seenArtifactIds
      ..remove(artifactId)
      ..add(artifactId);
    while (_seenArtifactIds.length > seenLruCapacity) {
      _seenArtifactIds.remove(_seenArtifactIds.first);
    }
  }

  void _emit(EdgeEvent event) {
    // Best-effort only — the listener is authoritative (see [events]). A
    // broadcast Stream silently drops when no subscriber is attached; that must
    // never affect acked/seen state.
    if (!_events.isClosed) _events.add(event);
  }

  EdgeOutcome _drop(String reason) {
    _log('[EdgeIngest] dropped body: $reason');
    return Dropped(reason);
  }

  /// Lowercase hex SHA-256 of the UTF-8 bytes of [payloadJson] — identical to
  /// the producer's `HsiArtifactEnvelope.wrap` (and the Kotlin/Swift
  /// `sha256Hex`): `sha256(payload_json_bytes)`.
  static String sha256Hex(String payloadJson) {
    final digest = sha256.convert(utf8.encode(payloadJson));
    return digest.toString(); // crypto Digest.toString() is lowercase hex.
  }

  // Tolerant numeric coercion (parity with Swift's `double`/`int64` helpers).
  static double? _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) {
      final i = int.tryParse(value);
      if (i != null) return i;
      final d = double.tryParse(value);
      return d?.toInt();
    }
    return null;
  }

  static List<double> _toDoubleList(Object? value) {
    if (value is! List) return const <double>[];
    final out = <double>[];
    for (final e in value) {
      final d = _toDouble(e);
      if (d != null) out.add(d);
    }
    return out;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// Parity with Kotlin `extractHsiVersionFromPayload`: read `hsi_version` from
  /// the opaque payload when the envelope omits it. Returns null on any parse
  /// failure or absence.
  static String? _extractHsiVersionFromPayload(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map) return _nonEmptyString(decoded['hsi_version']);
    } catch (_) {
      // Opaque payload may not be JSON; treat as absent.
    }
    return null;
  }

  static Accel? _parseAccel(Object? value) {
    if (value is! Map) return null;
    final x = _toDouble(value['x']);
    final y = _toDouble(value['y']);
    final z = _toDouble(value['z']);
    // Accel requires all three axes (§2); a partial object is treated as absent.
    if (x == null || y == null || z == null) return null;
    return Accel(x: x, y: y, z: z);
  }
}

/// Optional typed callbacks for parsed, validated edge messages. Parity with
/// the Swift `EdgeIngest.Delegate` and Kotlin `EdgeIngest.Listener`.
abstract mixin class EdgeIngestListener {
  /// §3.1 — scalar HR sample.
  void onHrSample(HrSample sample) {}

  /// §3.2 — full raw biosignal sample.
  void onBioSample(BioSample sample) {}

  /// §3.3 — an accepted (hash-verified, non-duplicate) HSI artifact. Its id is
  /// already recorded as needing ACK ([EdgeIngest.drainPendingAcks]).
  void onArtifact(HsiArtifact artifact) {}

  /// §3.4 — a session event whose `type` is not a sample/artifact type.
  void onSessionEvent(EdgeSessionEvent event) {}

  /// §5 — a deterministically-corrupt artifact: the same `artifact_id`
  /// mismatched its hash [EdgeIngest.poisonPillThreshold] times. It is
  /// dead-lettered — surfaced here as a hard error AND ack-to-discarded so it
  /// stops blocking the watch's delete-on-ACK outbox. Optional.
  void onPoisonPill(
    String artifactId,
    String expected,
    String actual,
    int attempts,
  ) {}
}

/// The outcome of consuming one body (parity with Swift's `Outcome`). Returned
/// in addition to firing the listener/stream so an adapter and tests can branch
/// without state.
sealed class EdgeOutcome {
  const EdgeOutcome();
}

class HrSampleOutcome extends EdgeOutcome {
  final HrSample sample;
  const HrSampleOutcome(this.sample);
}

class BioSampleOutcome extends EdgeOutcome {
  final BioSample sample;
  const BioSampleOutcome(this.sample);
}

/// Artifact accepted (verified + not a duplicate).
class ArtifactAccepted extends EdgeOutcome {
  final HsiArtifact artifact;
  const ArtifactAccepted(this.artifact);
}

/// Artifact ignored: its `artifact_id` was already seen (§5).
class ArtifactDuplicate extends EdgeOutcome {
  final String artifactId;
  const ArtifactDuplicate(this.artifactId);
}

/// Artifact rejected: `payload_hash_sha256` != sha256(payload_json) (§5).
/// First/normal mismatch — NOT surfaced, NOT acked, NOT recorded as seen.
class ArtifactHashMismatch extends EdgeOutcome {
  final String artifactId;
  const ArtifactHashMismatch(this.artifactId);
}

/// Artifact dead-lettered after [EdgeIngest.poisonPillThreshold] hash
/// mismatches for the same id: surfaced as a hard error via
/// [EdgeIngestListener.onPoisonPill] AND ack-to-discarded so it stops blocking
/// the outbox.
class ArtifactDeadLettered extends EdgeOutcome {
  final String artifactId;
  const ArtifactDeadLettered(this.artifactId);
}

/// Body recognised as a non-sample/-artifact session event (§3.4).
class SessionEventOutcome extends EdgeOutcome {
  final String type;
  const SessionEventOutcome(this.type);
}

/// Body dropped: missing/invalid `type`, missing required fields, or otherwise
/// malformed. Never crashes.
class Dropped extends EdgeOutcome {
  final String reason;
  const Dropped(this.reason);
}
