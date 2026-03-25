import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../config/synheart_mode.dart';
import '../core/logger.dart';
import '../models/metric_event.dart';

/// Record representing a session row in the catalog.
class SessionRecord {
  final String sessionId;
  final String subjectId;
  final String mode;
  final int createdAtUtc;
  final int startUtc;
  final int? endUtc;
  final String appId;
  final String appVersion;
  final String deviceId;
  final String platform;
  final String state;
  final String syncedState;

  const SessionRecord({
    required this.sessionId,
    required this.subjectId,
    required this.mode,
    required this.createdAtUtc,
    required this.startUtc,
    this.endUtc,
    required this.appId,
    required this.appVersion,
    required this.deviceId,
    required this.platform,
    this.state = 'active',
    this.syncedState = 'disabled',
  });

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'subject_id': subjectId,
        'mode': mode,
        'created_at_utc': createdAtUtc,
        'start_utc': startUtc,
        'end_utc': endUtc,
        'app_id': appId,
        'app_version': appVersion,
        'device_id': deviceId,
        'platform': platform,
        'state': state,
        'synced_state': syncedState,
      };

  factory SessionRecord.fromMap(Map<String, dynamic> map) => SessionRecord(
        sessionId: map['session_id'] as String,
        subjectId: map['subject_id'] as String,
        mode: map['mode'] as String,
        createdAtUtc: map['created_at_utc'] as int,
        startUtc: map['start_utc'] as int,
        endUtc: map['end_utc'] as int?,
        appId: map['app_id'] as String,
        appVersion: map['app_version'] as String,
        deviceId: map['device_id'] as String,
        platform: map['platform'] as String,
        state: map['state'] as String,
        syncedState: map['synced_state'] as String,
      );
}

/// Record representing an artifact row in the catalog.
class ArtifactRecord {
  final String artifactId;
  final String? sessionId;
  final String subjectId;
  final String type;
  final String schemaName;
  final String schemaVersion;
  final int startMs;
  final int endMs;
  final int? seq;
  final int createdAtMs;
  final String encAlg;
  final Uint8List payload;
  final String payloadSha256;
  final String syncState;

  const ArtifactRecord({
    required this.artifactId,
    this.sessionId,
    required this.subjectId,
    required this.type,
    required this.schemaName,
    required this.schemaVersion,
    required this.startMs,
    required this.endMs,
    this.seq,
    required this.createdAtMs,
    required this.encAlg,
    required this.payload,
    required this.payloadSha256,
    this.syncState = 'pending',
  });

  Map<String, dynamic> toMap() => {
        'artifact_id': artifactId,
        'session_id': sessionId,
        'subject_id': subjectId,
        'type': type,
        'schema_name': schemaName,
        'schema_version': schemaVersion,
        'start_ms': startMs,
        'end_ms': endMs,
        'seq': seq,
        'created_at_ms': createdAtMs,
        'enc_alg': encAlg,
        'payload': payload,
        'payload_sha256': payloadSha256,
        'sync_state': syncState,
      };

  factory ArtifactRecord.fromMap(Map<String, dynamic> map) => ArtifactRecord(
        artifactId: map['artifact_id'] as String,
        sessionId: map['session_id'] as String?,
        subjectId: map['subject_id'] as String,
        type: map['type'] as String,
        schemaName: map['schema_name'] as String,
        schemaVersion: map['schema_version'] as String,
        startMs: map['start_ms'] as int,
        endMs: map['end_ms'] as int,
        seq: map['seq'] as int?,
        createdAtMs: map['created_at_ms'] as int,
        encAlg: map['enc_alg'] as String,
        payload: map['payload'] as Uint8List,
        payloadSha256: map['payload_sha256'] as String,
        syncState: map['sync_state'] as String? ?? 'pending',
      );
}

/// SQLite-based artifact and session storage.
///
/// See RFC-CORE-0004 for the full storage specification.
class StorageManager {
  Database? _db;
  final String _basePath;

  /// If non-null, used as the exact database path (e.g. [inMemoryDatabasePath] for tests).
  final String? _dbPathOverride;

  StorageManager({required String basePath, String? dbPathOverride})
      : _basePath = basePath,
        _dbPathOverride = dbPathOverride;

  bool get isOpen => _db != null;

  Future<void> open() async {
    final dbPath =
        _dbPathOverride ?? p.join(_basePath, 'synheart', 'v1', 'catalog.sqlite');
    try {
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
        onConfigure: (db) async {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA foreign_keys=ON');
        },
      );
    } catch (e, st) {
      SynheartLogger.log(
        '[StorageManager] Database open failed, attempting recovery: $e',
        error: e,
        stackTrace: st,
      );
      // Delete corrupt database and retry once
      try {
        final file = File(dbPath);
        if (await file.exists()) await file.delete();
        // Also remove WAL/SHM journal files if present
        final wal = File('$dbPath-wal');
        final shm = File('$dbPath-shm');
        if (await wal.exists()) await wal.delete();
        if (await shm.exists()) await shm.delete();
      } catch (cleanupError) {
        SynheartLogger.log(
          '[StorageManager] Failed to delete corrupt database: $cleanupError',
          error: cleanupError,
        );
      }
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
        onConfigure: (db) async {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA foreign_keys=ON');
        },
      );
      SynheartLogger.log('[StorageManager] Recovery succeeded — fresh database created');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        mode TEXT NOT NULL,
        created_at_utc INTEGER NOT NULL,
        start_utc INTEGER NOT NULL,
        end_utc INTEGER NULL,
        app_id TEXT NOT NULL,
        app_version TEXT NOT NULL,
        device_id TEXT NOT NULL,
        platform TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'active',
        synced_state TEXT NOT NULL DEFAULT 'disabled'
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_sessions_start ON sessions(start_utc)');

    await db.execute('''
      CREATE TABLE artifacts (
        artifact_id TEXT PRIMARY KEY,
        session_id TEXT,
        subject_id TEXT NOT NULL,
        type TEXT NOT NULL,
        schema_name TEXT NOT NULL,
        schema_version TEXT NOT NULL,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        seq INTEGER,
        created_at_ms INTEGER NOT NULL,
        enc_alg TEXT NOT NULL,
        payload BLOB NOT NULL,
        payload_sha256 TEXT NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY(session_id) REFERENCES sessions(session_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_artifacts_session ON artifacts(session_id)');
    await db
        .execute('CREATE INDEX idx_artifacts_type ON artifacts(type)');
    await db.execute(
        'CREATE INDEX idx_artifacts_time ON artifacts(start_ms, end_ms)');

    await db.execute('''
      CREATE TABLE summaries (
        session_id TEXT PRIMARY KEY,
        artifact_id TEXT NOT NULL,
        summary_json TEXT NOT NULL,
        computed_at_utc INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES sessions(session_id),
        FOREIGN KEY(artifact_id) REFERENCES artifacts(artifact_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE tombstones (
        artifact_id TEXT PRIMARY KEY,
        target_artifact_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        deleted_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tombstones_target ON tombstones(target_artifact_id)');

    await db.execute('''
      CREATE TABLE metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        name TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        value TEXT NOT NULL,
        tags TEXT,
        FOREIGN KEY(session_id) REFERENCES sessions(session_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_metrics_session ON metrics(session_id)');

    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wearable_events (
        event_id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        event_class TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_record_id TEXT,
        observed_at TEXT NOT NULL,
        ingested_at TEXT NOT NULL,
        effective_start TEXT,
        effective_end TEXT,
        payload BLOB NOT NULL,
        provenance TEXT,
        confidence REAL NOT NULL,
        source_fidelity TEXT NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_we_type_observed ON wearable_events(event_type, observed_at)');
    await db.execute(
        'CREATE INDEX idx_we_subject ON wearable_events(subject_id)');
  }

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('StorageManager is not open');
    return db;
  }

  // --- Sessions ---

  Future<void> insertSession(SessionRecord session) async {
    await _database.insert('sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateSession(
    String sessionId, {
    String? state,
    int? endUtc,
  }) async {
    final values = <String, dynamic>{};
    if (state != null) values['state'] = state;
    if (endUtc != null) values['end_utc'] = endUtc;
    if (values.isEmpty) return;
    await _database.update('sessions', values,
        where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<List<SessionRecord>> listSessions({
    int? startMs,
    int? endMs,
    SynheartMode? mode,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    if (startMs != null) {
      where.add('start_utc >= ?');
      args.add(startMs);
    }
    if (endMs != null) {
      where.add('start_utc <= ?');
      args.add(endMs);
    }
    if (mode != null) {
      where.add('mode = ?');
      args.add(mode.name);
    }
    where.add("state != 'deleted'");

    final rows = await _database.query('sessions',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'start_utc DESC');
    return rows.map(SessionRecord.fromMap).toList();
  }

  // --- Artifacts ---

  Future<void> insertArtifact(ArtifactRecord artifact) async {
    await _database.insert('artifacts', artifact.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<ArtifactRecord?> getArtifact(String artifactId) async {
    final rows = await _database.query('artifacts',
        where: 'artifact_id = ?', whereArgs: [artifactId]);
    if (rows.isEmpty) return null;
    return ArtifactRecord.fromMap(rows.first);
  }

  Future<List<ArtifactRecord>> getArtifactsBySession(
    String sessionId, {
    String? type,
  }) async {
    final where = ['session_id = ?'];
    final args = <dynamic>[sessionId];
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    // Exclude tombstoned artifacts
    where.add(
        'artifact_id NOT IN (SELECT target_artifact_id FROM tombstones)');

    final rows = await _database.query('artifacts',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'start_ms ASC');
    return rows.map(ArtifactRecord.fromMap).toList();
  }

  Future<List<ArtifactRecord>> getArtifactsByTimeRange(
    int startMs,
    int endMs, {
    String? type,
  }) async {
    final where = ['start_ms >= ?', 'end_ms <= ?'];
    final args = <dynamic>[startMs, endMs];
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    where.add(
        'artifact_id NOT IN (SELECT target_artifact_id FROM tombstones)');

    final rows = await _database.query('artifacts',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'start_ms ASC');
    return rows.map(ArtifactRecord.fromMap).toList();
  }

  // --- Tombstones ---

  Future<void> insertTombstone({
    required String artifactId,
    required String targetArtifactId,
    required String reason,
    required int deletedAtMs,
  }) async {
    await _database.insert(
        'tombstones',
        {
          'artifact_id': artifactId,
          'target_artifact_id': targetArtifactId,
          'reason': reason,
          'deleted_at_ms': deletedAtMs,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> isDeleted(String artifactId) async {
    final rows = await _database.query('tombstones',
        where: 'target_artifact_id = ?',
        whereArgs: [artifactId],
        limit: 1);
    return rows.isNotEmpty;
  }

  // --- Summaries ---

  Future<void> insertSummaryCache({
    required String sessionId,
    required String artifactId,
    required String summaryJson,
  }) async {
    await _database.insert(
        'summaries',
        {
          'session_id': sessionId,
          'artifact_id': artifactId,
          'summary_json': summaryJson,
          'computed_at_utc':
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSummaryJson(String sessionId) async {
    final rows = await _database.query('summaries',
        columns: ['summary_json'],
        where: 'session_id = ?',
        whereArgs: [sessionId]);
    if (rows.isEmpty) return null;
    return rows.first['summary_json'] as String;
  }

  // --- Metrics ---

  Future<void> insertMetric(String sessionId, MetricEvent event) async {
    await _database.insert('metrics', {
      'session_id': sessionId,
      'name': event.name,
      'timestamp_ms': event.timestampMs,
      'value': event.valueEncoded,
      'tags': event.tagsEncoded,
    });
  }

  Future<void> insertMetrics(
      String sessionId, List<MetricEvent> events) async {
    final batch = _database.batch();
    for (final event in events) {
      batch.insert('metrics', {
        'session_id': sessionId,
        'name': event.name,
        'timestamp_ms': event.timestampMs,
        'value': event.valueEncoded,
        'tags': event.tagsEncoded,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<MetricEvent>> getMetrics(String sessionId) async {
    final rows = await _database.query('metrics',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp_ms ASC');
    return rows.map((row) => MetricEvent(
          name: row['name'] as String,
          timestampMs: row['timestamp_ms'] as int,
          value: jsonDecode(row['value'] as String),
          tags: row['tags'] != null
              ? (jsonDecode(row['tags'] as String) as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, v.toString()))
              : null,
        )).toList();
  }

  /// Aggregate metrics for a session into {name: {mean, count}} pairs.
  Future<List<Map<String, dynamic>>> aggregateMetrics(
      String sessionId) async {
    final rows = await _database.rawQuery('''
      SELECT name, COUNT(*) as cnt, AVG(CAST(value AS REAL)) as avg_val
      FROM metrics
      WHERE session_id = ?
      GROUP BY name
    ''', [sessionId]);
    return rows
        .map((row) => {
              'name': row['name'],
              'count': row['cnt'],
              'mean': row['avg_val'],
            })
        .toList();
  }

  // --- Storage usage ---

  Future<StorageUsage> getStorageUsage() async {
    final rows = await _database.rawQuery('''
      SELECT session_id, SUM(LENGTH(payload)) as bytes
      FROM artifacts
      GROUP BY session_id
    ''');
    int total = 0;
    final bySession = <String, int>{};
    for (final row in rows) {
      final sid = row['session_id'] as String? ?? '~';
      final bytes = (row['bytes'] as num?)?.toInt() ?? 0;
      bySession[sid] = bytes;
      total += bytes;
    }
    return StorageUsage(totalBytes: total, bySessionBytes: bySession);
  }

  // --- Retention ---

  /// Delete sessions and their artifacts older than [cutoffMs].
  /// Creates tombstones for each deleted artifact.
  Future<int> enforceRetention(int cutoffMs) async {
    final cutoffUtc = cutoffMs ~/ 1000;
    // Find sessions to delete
    final sessionRows = await _database.query('sessions',
        columns: ['session_id'],
        where: "start_utc < ? AND state != 'deleted'",
        whereArgs: [cutoffUtc]);

    int deleted = 0;
    for (final row in sessionRows) {
      final sid = row['session_id'] as String;
      await deleteSession(sid, createTombstones: true);
      deleted++;
    }
    return deleted;
  }

  // --- Deletion ---

  Future<void> deleteSession(String sessionId,
      {bool createTombstones = false}) async {
    await _database.transaction((txn) async {
      if (createTombstones) {
        final artifacts = await txn.query('artifacts',
            columns: ['artifact_id'],
            where: 'session_id = ?',
            whereArgs: [sessionId]);
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        for (final row in artifacts) {
          final aid = row['artifact_id'] as String;
          final tombId = 'tombstone_$aid';
          await txn.insert(
              'tombstones',
              {
                'artifact_id': tombId,
                'target_artifact_id': aid,
                'reason': 'session_deleted',
                'deleted_at_ms': nowMs,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          // Insert tombstone as a syncable artifact so it gets pushed during sync
          await txn.insert(
              'artifacts',
              {
                'artifact_id': tombId,
                'session_id': sessionId,
                'subject_id': (await txn.query('sessions',
                        columns: ['subject_id'],
                        where: 'session_id = ?',
                        whereArgs: [sessionId]))
                    .first['subject_id'] as String,
                'type': 'tombstone',
                'schema_name': 'tombstone',
                'schema_version': '1.0',
                'start_ms': nowMs,
                'end_ms': nowMs,
                'created_at_ms': nowMs,
                'enc_alg': 'none',
                'payload': Uint8List.fromList(
                    utf8.encode('{"target":"$aid","reason":"session_deleted"}')),
                'payload_sha256': '',
                'sync_state': 'pending',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      await txn.delete('metrics',
          where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('summaries',
          where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('artifacts',
          where: "session_id = ? AND type != 'tombstone'", whereArgs: [sessionId]);
      await txn.update('sessions', {'state': 'deleted'},
          where: 'session_id = ?', whereArgs: [sessionId]);
    });
  }

  // --- Sync State ---

  Future<void> setSyncState(String key, String value) async {
    await _database.insert(
      'sync_state',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSyncState(String key) async {
    final rows = await _database.query('sync_state',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> markSynced(String artifactId) async {
    await _database.update(
      'artifacts',
      {'sync_state': 'synced'},
      where: 'artifact_id = ?',
      whereArgs: [artifactId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedArtifacts({int limit = 50}) async {
    return await _database.query('artifacts',
        where: "sync_state = 'pending'",
        limit: limit,
        orderBy: 'created_at_ms ASC');
  }

  Future<int> getUnsyncedCount() async {
    final result = await _database.rawQuery(
        "SELECT COUNT(*) as cnt FROM artifacts WHERE sync_state = 'pending'");
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> insertSyncedArtifact({
    required String artifactId,
    required String subjectId,
    String? sessionId,
    required String type,
    required String schemaName,
    required String schemaVersion,
    required int startMs,
    required int endMs,
    int? seq,
    required Uint8List payload,
    required String payloadSha256,
    required Uint8List smkBytes,
  }) async {
    // Store the already-decrypted payload directly (caller handles re-encryption)
    await insertArtifact(ArtifactRecord(
      artifactId: artifactId,
      sessionId: sessionId,
      subjectId: subjectId,
      type: type,
      schemaName: schemaName,
      schemaVersion: schemaVersion,
      startMs: startMs,
      endMs: endMs,
      seq: seq,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      encAlg: 'xchacha20poly1305',
      payload: payload,
      payloadSha256: payloadSha256,
      syncState: 'synced',
    ));
  }

  /// Find the smallest artifact_id matching the given merge key.
  ///
  /// Merge key: (session_id, type, start_ms, schema_version).
  /// Used for conflict resolution per RFC-CORE-0006.
  Future<String?> findSmallestArtifactIdByMergeKey({
    required String? sessionId,
    required String type,
    required int startMs,
    required String schemaVersion,
  }) async {
    final where = <String>['type = ?', 'start_ms = ?', 'schema_version = ?'];
    final args = <dynamic>[type, startMs, schemaVersion];

    if (sessionId != null) {
      where.add('session_id = ?');
      args.add(sessionId);
    } else {
      where.add('session_id IS NULL');
    }

    final rows = await _database.query(
      'artifacts',
      columns: ['artifact_id'],
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'artifact_id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['artifact_id'] as String?;
  }

  // --- Wearable Events ---

  Future<void> insertWearableEvent(Map<String, dynamic> record) async {
    await _database.insert('wearable_events', record,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> queryWearableEvents({
    required String eventType,
    required String startDate,
    required String endDate,
  }) async {
    return await _database.query('wearable_events',
        where: 'event_type = ? AND observed_at >= ? AND observed_at <= ?',
        whereArgs: [eventType, startDate, endDate],
        orderBy: 'observed_at ASC');
  }

  Future<int> wearableEventCount() async {
    final result = await _database
        .rawQuery('SELECT COUNT(*) as cnt FROM wearable_events');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> wipeAll() async {
    await _database.transaction((txn) async {
      await txn.delete('metrics');
      await txn.delete('tombstones');
      await txn.delete('summaries');
      await txn.delete('artifacts');
      await txn.delete('sessions');
      await txn.delete('sync_state');
      await txn.delete('wearable_events');
    });
  }

  // --- Lifecycle ---

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
