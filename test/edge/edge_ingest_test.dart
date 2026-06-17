// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// Helper: build a valid `hsi_artifact` body whose hash matches its payload.
Map<String, dynamic> artifactBody({
  required String artifactId,
  String payloadJson = '{"hsi_version":"1.3","score":0.42}',
  String? hsiVersion = '1.3',
  String? overrideHash,
}) {
  final body = <String, dynamic>{
    'type': 'hsi_artifact',
    'artifact_id': artifactId,
    'session_id': 'sess_1',
    'seq': 0,
    'created_at_ms': 1718900000000,
    'schema_version': '1.1',
    'payload_hash_sha256': overrideHash ?? EdgeIngest.sha256Hex(payloadJson),
    'payload_json': payloadJson,
    'delivery_mode': 'REALTIME',
    'session_origin': 'PHONE',
    'session_kind': 'FOCUS',
  };
  if (hsiVersion != null) body['hsi_version'] = hsiVersion;
  return body;
}

/// Recording listener to verify callback parity with Swift/Kotlin.
class _Recorder with EdgeIngestListener {
  final hr = <HrSample>[];
  final bio = <BioSample>[];
  final artifacts = <HsiArtifact>[];
  final events = <EdgeSessionEvent>[];
  final poisonPills = <MapEntry<String, int>>[];

  @override
  void onHrSample(HrSample sample) => hr.add(sample);
  @override
  void onBioSample(BioSample sample) => bio.add(sample);
  @override
  void onArtifact(HsiArtifact artifact) => artifacts.add(artifact);
  @override
  void onSessionEvent(EdgeSessionEvent event) => events.add(event);
  @override
  void onPoisonPill(
    String artifactId,
    String expected,
    String actual,
    int attempts,
  ) => poisonPills.add(MapEntry(artifactId, attempts));
}

void main() {
  group('EdgeIngest hsi_artifact', () {
    test('dedupe: same artifact_id twice -> one accept, one duplicate', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);

      final first = ingest.ingest(artifactBody(artifactId: 'hsi_a_0'));
      final second = ingest.ingest(artifactBody(artifactId: 'hsi_a_0'));

      expect(first, isA<ArtifactAccepted>());
      expect(second, isA<ArtifactDuplicate>());
      expect(rec.artifacts.length, 1);
      expect(ingest.seenCount(), 1);
      // Only the accepted one is pending an ack.
      expect(ingest.pendingAckIds, ['hsi_a_0']);
    });

    test('hash mismatch: rejected, not surfaced, not acked, not seen', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);

      final outcome = ingest.ingest(
        artifactBody(artifactId: 'hsi_bad_0', overrideHash: 'deadbeef'),
      );

      expect(outcome, isA<ArtifactHashMismatch>());
      expect(rec.artifacts, isEmpty);
      expect(ingest.seenCount(), 0);
      expect(ingest.drainPendingAcks(), isEmpty);
    });

    test('unsupported hsi_version is flagged but still surfaced', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);

      // payload carries an out-of-set version; keep envelope hsi_version too.
      const payload = '{"hsi_version":"9.9"}';
      final outcome = ingest.ingest(
        artifactBody(
          artifactId: 'hsi_v_0',
          payloadJson: payload,
          hsiVersion: '9.9',
        ),
      );

      expect(outcome, isA<ArtifactAccepted>());
      expect(rec.artifacts.single.hsiVersionSupported, isFalse);
      expect(rec.artifacts.single.hsiVersion, '9.9');
    });

    test('absent hsi_version is flagged (parity with Kotlin/Swift)', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);

      // No envelope hsi_version AND payload has none either.
      final outcome = ingest.ingest(
        artifactBody(
          artifactId: 'hsi_noV_0',
          payloadJson: '{"score":0.1}',
          hsiVersion: null,
        ),
      );

      expect(outcome, isA<ArtifactAccepted>());
      expect(rec.artifacts.single.hsiVersionSupported, isFalse);
      expect(rec.artifacts.single.hsiVersion, isNull);
    });

    test('supported hsi_version sets hsiVersionSupported = true', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);

      ingest.ingest(artifactBody(artifactId: 'hsi_ok_0', hsiVersion: '1.2'));
      expect(rec.artifacts.single.hsiVersionSupported, isTrue);
      expect(rec.artifacts.single.hsiVersion, '1.2');
    });

    test('typed envelope fields are decoded', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest(artifactBody(artifactId: 'hsi_full_0'));
      final a = rec.artifacts.single;
      expect(a.artifactId, 'hsi_full_0');
      expect(a.sessionId, 'sess_1');
      expect(a.seq, 0);
      expect(a.createdAtMs, 1718900000000);
      expect(a.schemaVersion, '1.1');
      expect(a.deliveryMode, 'REALTIME');
      expect(a.sessionOrigin, 'PHONE');
      expect(a.sessionKind, 'FOCUS');
    });
  });

  group('EdgeIngest hr_sample / bio_sample', () {
    test('hr_sample parses with source', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      final outcome = ingest.ingest({
        'type': 'hr_sample',
        'bpm': 72.0,
        'timestamp_ms': 1718900000000,
        'source': 'healthkit',
      });
      expect(outcome, isA<HrSampleOutcome>());
      expect(
        rec.hr.single,
        const HrSample(
          bpm: 72.0,
          timestampMs: 1718900000000,
          source: 'healthkit',
        ),
      );
    });

    test('hr_sample omitted source -> null', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest({'type': 'hr_sample', 'bpm': 60, 'timestamp_ms': 1});
      expect(rec.hr.single.source, isNull);
      expect(rec.hr.single.bpm, 60.0); // int coerced to double
    });

    test('bio_sample full parse', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest({
        'type': 'bio_sample',
        'bpm': 72.0,
        'timestamp_ms': 1718900000000,
        'rr_intervals_ms': [820.0, 835.0],
        'accel': {'x': 0.01, 'y': -0.02, 'z': 0.98},
        'source': 'healthkit',
      });
      final b = rec.bio.single;
      expect(b.bpm, 72.0);
      expect(b.rrIntervalsMs, [820.0, 835.0]);
      expect(b.accel, const Accel(x: 0.01, y: -0.02, z: 0.98));
      expect(b.source, 'healthkit');
    });

    test('bio_sample omitted optionals: empty rr, null accel, null source', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest({
        'type': 'bio_sample',
        'bpm': 72.0,
        'timestamp_ms': 1718900000000,
      });
      final b = rec.bio.single;
      expect(b.rrIntervalsMs, isEmpty);
      expect(b.accel, isNull);
      expect(b.source, isNull);
    });

    test('partial accel object is treated as absent (never fabricated)', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest({
        'type': 'bio_sample',
        'bpm': 72.0,
        'timestamp_ms': 1,
        'accel': {'x': 0.01, 'y': -0.02}, // missing z
      });
      expect(rec.bio.single.accel, isNull);
    });
  });

  group('EdgeIngest routing & robustness', () {
    test('unknown type routes to session event', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      final outcome = ingest.ingest({
        'type': 'session_started',
        'session_id': 's1',
      });
      expect(outcome, isA<SessionEventOutcome>());
      expect(rec.events.single.type, 'session_started');
      expect(rec.events.single.body['session_id'], 's1');
    });

    test('malformed body does not throw and is dropped', () {
      final ingest = EdgeIngest();
      expect(ingest.ingest({}), isA<Dropped>()); // no type
      expect(ingest.ingest({'type': ''}), isA<Dropped>()); // blank type
      // hr_sample missing required keys.
      expect(ingest.ingest({'type': 'hr_sample'}), isA<Dropped>());
      // artifact missing payload.
      expect(
        ingest.ingest({'type': 'hsi_artifact', 'artifact_id': 'x'}),
        isA<Dropped>(),
      );
    });

    test('ingestRaw handles unparseable + non-object JSON', () {
      final ingest = EdgeIngest();
      expect(ingest.ingestRaw('not json'), isA<Dropped>());
      expect(ingest.ingestRaw('[1,2,3]'), isA<Dropped>());
    });

    test('ingestRaw parses a valid hr_sample JSON string', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      final outcome = ingest.ingestRaw(
        jsonEncode({'type': 'hr_sample', 'bpm': 80.0, 'timestamp_ms': 5}),
      );
      expect(outcome, isA<HrSampleOutcome>());
      expect(rec.hr.single.bpm, 80.0);
    });

    test('broadcast stream emits typed events', () async {
      final ingest = EdgeIngest();
      final received = <EdgeEvent>[];
      final sub = ingest.events.listen(received.add);
      ingest.ingest({'type': 'hr_sample', 'bpm': 70.0, 'timestamp_ms': 1});
      ingest.ingest(artifactBody(artifactId: 'hsi_stream_0'));
      await Future<void>.delayed(Duration.zero);
      expect(received[0], isA<HrEvent>());
      expect(received[1], isA<ArtifactEvent>());
      await sub.cancel();
      await ingest.dispose();
    });
  });

  group('EdgeIngest ACK', () {
    test('ack body shape is exact', () {
      final ingest = EdgeIngest();
      ingest.ingest(artifactBody(artifactId: 'hsi_ack_0'));
      ingest.ingest(artifactBody(artifactId: 'hsi_ack_1'));
      final body = ingest.drainAckBody();
      expect(body, {
        'command': 'artifact_ack',
        'artifact_ids': ['hsi_ack_0', 'hsi_ack_1'],
      });
      // Drained -> nothing left.
      expect(ingest.drainPendingAcks(), isEmpty);
      expect(ingest.drainAckBody(), isNull);
    });

    test('buildAckBody returns null for empty ids', () {
      final ingest = EdgeIngest();
      expect(ingest.buildAckBody(const []), isNull);
    });
  });

  group('sha256 known vector (producer parity)', () {
    test('sha256Hex matches a precomputed lowercase-hex digest', () {
      const payload = '{"hsi_version":"1.3","score":0.42}';
      expect(
        EdgeIngest.sha256Hex(payload),
        'fd7d93ee8a4ea13b7f9f46053ff46febde1e284ba0cc522251af324c744f4692',
      );
    });

    test('payload-fallback version extraction (parity with Kotlin)', () {
      // Envelope omits hsi_version but the opaque payload carries a supported
      // one -> the Dart EdgeIngest falls back to the payload (Kotlin parity)
      // and marks it supported.
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest(
        artifactBody(
          artifactId: 'hsi_fb_0',
          payloadJson: '{"hsi_version":"1.3"}',
          hsiVersion: null, // present in payload, absent in envelope
        ),
      );
      expect(rec.artifacts.single.hsiVersion, '1.3');
      expect(rec.artifacts.single.hsiVersionSupported, isTrue);
    });

    test('payload-fallback to an out-of-set version is flagged', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      ingest.ingest(
        artifactBody(
          artifactId: 'hsi_fb_1',
          payloadJson: '{"hsi_version":"9.9"}',
          hsiVersion: null,
        ),
      );
      expect(rec.artifacts.single.hsiVersion, '9.9');
      expect(rec.artifacts.single.hsiVersionSupported, isFalse);
    });
  });

  // A duplicate must still be re-acked (delete-on-ACK outbox).
  group('EdgeIngest duplicate re-ack', () {
    test('duplicate is re-acked, not re-surfaced', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      // First accept, then drain (simulates a sent ACK the watch never saw).
      ingest.ingest(artifactBody(artifactId: 'hsi_dup_0'));
      expect(ingest.drainPendingAcks(), ['hsi_dup_0']);

      // Watch resends: must NOT re-surface, MUST re-queue for ACK.
      final second = ingest.ingest(artifactBody(artifactId: 'hsi_dup_0'));
      expect(second, isA<ArtifactDuplicate>());
      expect(rec.artifacts.length, 1, reason: 'duplicate must not re-surface');
      expect(ingest.drainPendingAcks(), [
        'hsi_dup_0',
      ], reason: 'duplicate must be re-queued for ACK');
    });

    test('duplicate ack is idempotent (not double-queued)', () {
      final ingest = EdgeIngest();
      ingest.ingest(artifactBody(artifactId: 'hsi_dup_1')); // accept
      ingest.ingest(artifactBody(artifactId: 'hsi_dup_1')); // dup
      expect(ingest.pendingAckIds, ['hsi_dup_1']);
    });
  });

  // Dead-letter a deterministically-corrupt artifact after K=3.
  group('EdgeIngest poison pill', () {
    test('dead-lettered after three hash mismatches', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      final bad = artifactBody(
        artifactId: 'hsi_poison_0',
        overrideHash: 'deadbeef',
      );

      // Attempts 1 + 2: normal rejection — not surfaced, not acked, no dead-letter.
      expect(ingest.ingest(bad), isA<ArtifactHashMismatch>());
      expect(ingest.ingest(bad), isA<ArtifactHashMismatch>());
      expect(rec.poisonPills, isEmpty);
      expect(
        ingest.drainPendingAcks(),
        isEmpty,
        reason: 'sub-threshold mismatches must not be acked',
      );

      // Attempt 3: dead-letter — hard error + ack-to-discard.
      expect(ingest.ingest(bad), isA<ArtifactDeadLettered>());
      expect(rec.poisonPills.length, 1);
      expect(rec.poisonPills.single.value, 3);
      expect(
        rec.artifacts,
        isEmpty,
        reason: 'poison pill must never surface as a valid artifact',
      );
      expect(
        ingest.drainPendingAcks(),
        ['hsi_poison_0'],
        reason: 'dead-lettered id must be ack-to-discarded',
      );
    });

    test('poison pill threshold is three', () {
      expect(EdgeIngest.poisonPillThreshold, 3);
    });
  });

  // The seen set is bounded (LRU eviction).
  group('EdgeIngest dedupe bounded', () {
    test('seen set is bounded and evicts oldest', () {
      final ingest = EdgeIngest();
      final cap = EdgeIngest.seenLruCapacity;
      for (var i = 0; i < cap + 100; i++) {
        ingest.ingest(artifactBody(artifactId: 'hsi_$i'));
      }
      // Never exceeds the cap.
      expect(ingest.seenCount(), cap);
      // The eldest id ('hsi_0') was evicted → re-sending it accepts again
      // (harmless per contract §5).
      final outcome = ingest.ingest(artifactBody(artifactId: 'hsi_0'));
      expect(
        outcome,
        isA<ArtifactAccepted>(),
        reason: 'evicted id should accept again, proving the set is bounded',
      );
      expect(ingest.seenCount(), cap);
      // A recently-seen id is still deduped.
      expect(
        ingest.ingest(artifactBody(artifactId: 'hsi_${cap + 99}')),
        isA<ArtifactDuplicate>(),
      );
    });
  });

  // empty-`type` parity — dropped (already Kotlin/Dart behaviour; locked in).
  group('EdgeIngest empty type parity', () {
    test('empty type is dropped', () {
      final rec = _Recorder();
      final ingest = EdgeIngest(listener: rec);
      expect(ingest.ingest({'type': '', 'session_id': 's1'}), isA<Dropped>());
      expect(
        rec.events,
        isEmpty,
        reason: 'empty type must not surface as a session event',
      );
    });
  });
}
