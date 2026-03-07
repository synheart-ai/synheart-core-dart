import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synheart_core/src/config/synheart_mode.dart';
import 'package:synheart_core/src/storage/storage_manager.dart';

/// Initialise sqflite FFI for desktop/CI testing.
void _initFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

void main() {
  _initFfi();

  late StorageManager storage;

  setUp(() async {
    // Use in-memory database for tests
    storage = StorageManager(
      basePath: '',
      dbPathOverride: inMemoryDatabasePath,
    );
    await storage.open();
  });

  tearDown(() async {
    await storage.close();
  });

  group('StorageManager — Sessions', () {
    test('insert and list session', () async {
      final session = SessionRecord(
        sessionId: 'sess_001',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      );

      await storage.insertSession(session);
      final sessions = await storage.listSessions();

      expect(sessions, hasLength(1));
      expect(sessions.first.sessionId, 'sess_001');
      expect(sessions.first.subjectId, 'usr_abc');
      expect(sessions.first.mode, 'personal');
      expect(sessions.first.state, 'active');
    });

    test('update session state and endUtc', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_002',
        subjectId: 'usr_abc',
        mode: 'insight',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      await storage.updateSession('sess_002',
          state: 'closed', endUtc: 1700001000);

      final sessions = await storage.listSessions();
      expect(sessions.first.state, 'closed');
      expect(sessions.first.endUtc, 1700001000);
    });

    test('list sessions filters by mode', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 's1',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));
      await storage.insertSession(SessionRecord(
        sessionId: 's2',
        subjectId: 'usr_abc',
        mode: 'insight',
        createdAtUtc: 1700000001,
        startUtc: 1700000001,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      final personal =
          await storage.listSessions(mode: SynheartMode.personal);
      expect(personal, hasLength(1));
      expect(personal.first.sessionId, 's1');

      final insight = await storage.listSessions(mode: SynheartMode.insight);
      expect(insight, hasLength(1));
      expect(insight.first.sessionId, 's2');
    });

    test('deleted sessions are excluded from list', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 's_del',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      await storage.deleteSession('s_del');

      final sessions = await storage.listSessions();
      expect(sessions, isEmpty);
    });
  });

  group('StorageManager — Artifacts', () {
    test('insert and get artifact', () async {
      // Need a session first (foreign key)
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_a',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      await storage.insertArtifact(ArtifactRecord(
        artifactId: 'art_001',
        sessionId: 'sess_a',
        subjectId: 'usr_abc',
        type: 'hsi_window',
        schemaName: 'hsi_window',
        schemaVersion: '1',
        startMs: 1700000000000,
        endMs: 1700000030000,
        seq: 0,
        createdAtMs: 1700000030000,
        encAlg: 'xchacha20poly1305',
        payload: payload,
        payloadSha256: 'abc123',
      ));

      final artifact = await storage.getArtifact('art_001');
      expect(artifact, isNotNull);
      expect(artifact!.artifactId, 'art_001');
      expect(artifact.type, 'hsi_window');
      expect(artifact.payload, payload);
    });

    test('get artifacts by session', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_b',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      for (var i = 0; i < 3; i++) {
        await storage.insertArtifact(ArtifactRecord(
          artifactId: 'art_b_$i',
          sessionId: 'sess_b',
          subjectId: 'usr_abc',
          type: 'hsi_window',
          schemaName: 'hsi_window',
          schemaVersion: '1',
          startMs: 1700000000000 + i * 30000,
          endMs: 1700000000000 + (i + 1) * 30000,
          seq: i,
          createdAtMs: 1700000000000 + (i + 1) * 30000,
          encAlg: 'xchacha20poly1305',
          payload: Uint8List.fromList([i]),
          payloadSha256: 'hash_$i',
        ));
      }

      final artifacts = await storage.getArtifactsBySession('sess_b');
      expect(artifacts, hasLength(3));
      expect(artifacts.first.seq, 0);
      expect(artifacts.last.seq, 2);
    });

    test('get artifacts by time range', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_t',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      await storage.insertArtifact(ArtifactRecord(
        artifactId: 'art_t1',
        sessionId: 'sess_t',
        subjectId: 'usr_abc',
        type: 'hsi_window',
        schemaName: 'hsi_window',
        schemaVersion: '1',
        startMs: 100,
        endMs: 200,
        createdAtMs: 200,
        encAlg: 'xchacha20poly1305',
        payload: Uint8List(1),
        payloadSha256: 'h1',
      ));
      await storage.insertArtifact(ArtifactRecord(
        artifactId: 'art_t2',
        sessionId: 'sess_t',
        subjectId: 'usr_abc',
        type: 'hsi_window',
        schemaName: 'hsi_window',
        schemaVersion: '1',
        startMs: 300,
        endMs: 400,
        createdAtMs: 400,
        encAlg: 'xchacha20poly1305',
        payload: Uint8List(1),
        payloadSha256: 'h2',
      ));

      final inRange = await storage.getArtifactsByTimeRange(100, 400);
      expect(inRange, hasLength(2));

      final partial = await storage.getArtifactsByTimeRange(100, 200);
      expect(partial, hasLength(1));
      expect(partial.first.artifactId, 'art_t1');
    });
  });

  group('StorageManager — Tombstones', () {
    test('tombstoned artifacts excluded from session query', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_ts',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      await storage.insertArtifact(ArtifactRecord(
        artifactId: 'art_keep',
        sessionId: 'sess_ts',
        subjectId: 'usr_abc',
        type: 'hsi_window',
        schemaName: 'hsi_window',
        schemaVersion: '1',
        startMs: 100,
        endMs: 200,
        createdAtMs: 200,
        encAlg: 'xchacha20poly1305',
        payload: Uint8List(1),
        payloadSha256: 'h1',
      ));
      await storage.insertArtifact(ArtifactRecord(
        artifactId: 'art_del',
        sessionId: 'sess_ts',
        subjectId: 'usr_abc',
        type: 'hsi_window',
        schemaName: 'hsi_window',
        schemaVersion: '1',
        startMs: 200,
        endMs: 300,
        createdAtMs: 300,
        encAlg: 'xchacha20poly1305',
        payload: Uint8List(1),
        payloadSha256: 'h2',
      ));

      await storage.insertTombstone(
        artifactId: 'tomb_1',
        targetArtifactId: 'art_del',
        reason: 'user_delete',
        deletedAtMs: 999,
      );

      expect(await storage.isDeleted('art_del'), isTrue);
      expect(await storage.isDeleted('art_keep'), isFalse);

      final artifacts = await storage.getArtifactsBySession('sess_ts');
      expect(artifacts, hasLength(1));
      expect(artifacts.first.artifactId, 'art_keep');
    });
  });

  group('StorageManager — Summaries', () {
    test('insert and get summary cache', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_sum',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      await storage.insertSummaryCache(
        sessionId: 'sess_sum',
        artifactId: 'art_sum',
        summaryJson: '{"focus":0.7}',
      );

      final json = await storage.getSummaryJson('sess_sum');
      expect(json, '{"focus":0.7}');
    });

    test('missing summary returns null', () async {
      final json = await storage.getSummaryJson('nonexistent');
      expect(json, isNull);
    });
  });

  group('StorageManager — wipeAll', () {
    test('removes all data', () async {
      await storage.insertSession(SessionRecord(
        sessionId: 'sess_w',
        subjectId: 'usr_abc',
        mode: 'personal',
        createdAtUtc: 1700000000,
        startUtc: 1700000000,
        appId: 'com.test',
        appVersion: '1.0.0',
        deviceId: 'dev_1',
        platform: 'flutter',
      ));

      await storage.wipeAll();

      final sessions = await storage.listSessions();
      expect(sessions, isEmpty);
    });
  });
}
