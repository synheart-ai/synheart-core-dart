import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Computes a deterministic artifact ID from canonical fields.
///
/// The canonical string format is:
///   {type}|v1|{subject_id}|{session_id_or_~}|{start_ms}|{end_ms}|{schema_name}@{schema_version}
///
/// The artifact_id is the lowercase hex SHA-256 of that string.
///
/// See RFC-CORE-0006 Section 5 for the full specification.
String computeArtifactId({
  required String type,
  required String subjectId,
  String? sessionId,
  required int startMs,
  required int endMs,
  required String schemaName,
  required String schemaVersion,
}) {
  _validateField('type', type);
  _validateField('subjectId', subjectId);
  if (sessionId != null) _validateField('sessionId', sessionId);
  _validateField('schemaName', schemaName);
  _validateField('schemaVersion', schemaVersion);

  final sessionField = sessionId ?? '~';
  final canonical =
      '$type|v1|$subjectId|$sessionField|$startMs|$endMs|$schemaName@$schemaVersion';

  final bytes = utf8.encode(canonical);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

void _validateField(String name, String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  if (value.contains('|')) {
    throw ArgumentError.value(value, name, 'must not contain "|"');
  }
}
