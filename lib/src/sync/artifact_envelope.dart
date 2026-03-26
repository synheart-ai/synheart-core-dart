import 'dart:convert';
import 'dart:typed_data';

/// Wire format for E2EE artifact sync (RFC-CORE-0005 §4).
class ArtifactEnvelope {
  final String envelopeVersion;
  final String artifactId;
  final String subjectId;
  final String? sessionId;
  final String type;
  final int startMs;
  final int endMs;
  final int? seq;
  final String schemaName;
  final String schemaVersion;
  final String cryptoAlg;
  final String nonceB64;
  final String compression;
  final String payloadSha256;
  final String ciphertextB64;

  const ArtifactEnvelope({
    this.envelopeVersion = '1',
    required this.artifactId,
    required this.subjectId,
    this.sessionId,
    required this.type,
    required this.startMs,
    required this.endMs,
    this.seq,
    required this.schemaName,
    required this.schemaVersion,
    this.cryptoAlg = 'XCHACHA20POLY1305',
    required this.nonceB64,
    this.compression = 'none',
    required this.payloadSha256,
    required this.ciphertextB64,
  });

  Map<String, dynamic> toJson() => {
        'envelope_version': envelopeVersion,
        'artifact_id': artifactId,
        'subject_id': subjectId,
        if (sessionId != null) 'session_id': sessionId,
        'type': type,
        'time_range': {'start_ms': startMs, 'end_ms': endMs},
        if (seq != null) 'seq': seq,
        'schema': {'name': schemaName, 'version': schemaVersion},
        'crypto': {'alg': cryptoAlg, 'nonce_b64': nonceB64},
        'compression': compression,
        'payload_sha256': payloadSha256,
        'ciphertext_b64': ciphertextB64,
      };

  factory ArtifactEnvelope.fromJson(Map<String, dynamic> json) {
    final timeRange = json['time_range'] as Map<String, dynamic>;
    final schema = json['schema'] as Map<String, dynamic>;
    final crypto = json['crypto'] as Map<String, dynamic>;

    return ArtifactEnvelope(
      envelopeVersion: json['envelope_version'] as String? ?? '1',
      artifactId: json['artifact_id'] as String,
      subjectId: json['subject_id'] as String,
      sessionId: json['session_id'] as String?,
      type: json['type'] as String,
      startMs: timeRange['start_ms'] as int,
      endMs: timeRange['end_ms'] as int,
      seq: json['seq'] as int?,
      schemaName: schema['name'] as String,
      schemaVersion: schema['version'] as String,
      cryptoAlg: crypto['alg'] as String? ?? 'XCHACHA20POLY1305',
      nonceB64: crypto['nonce_b64'] as String,
      compression: json['compression'] as String? ?? 'none',
      payloadSha256: json['payload_sha256'] as String,
      ciphertextB64: json['ciphertext_b64'] as String,
    );
  }
}

/// Result of a sync operation.
class SyncResult {
  final int pushed;
  final int pulled;
  final int conflictsResolved;
  final List<String> errors;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.conflictsResolved = 0,
    this.errors = const [],
  });
}

/// Current sync status.
class SyncStatus {
  final bool enabled;
  final int? lastSuccessMs;
  final int pendingUploadCount;
  final int pendingDownloadCount;
  final String? cursor;

  const SyncStatus({
    required this.enabled,
    this.lastSuccessMs,
    this.pendingUploadCount = 0,
    this.pendingDownloadCount = 0,
    this.cursor,
  });
}
