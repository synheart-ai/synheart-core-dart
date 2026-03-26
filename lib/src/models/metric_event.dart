import 'dart:convert';

/// An app-level metric event recorded during a session (RFC-CORE-0007 §4).
///
/// Only persisted in Insight and Research modes. In Personal mode,
/// the call succeeds silently but the data is dropped.
class MetricEvent {
  final String name;
  final int timestampMs;
  final dynamic value; // number | string | bool
  final Map<String, String>? tags;

  const MetricEvent({
    required this.name,
    required this.timestampMs,
    required this.value,
    this.tags,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'timestamp_ms': timestampMs,
        'value': value,
        if (tags != null) 'tags': tags,
      };

  factory MetricEvent.fromJson(Map<String, dynamic> json) => MetricEvent(
        name: json['name'] as String,
        timestampMs: (json['timestamp_ms'] as num).toInt(),
        value: json['value'],
        tags: (json['tags'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v.toString())),
      );

  /// Encode the value as a JSON string for SQLite storage.
  String get valueEncoded => jsonEncode(value);

  /// Encode the tags as a JSON string for SQLite storage.
  String? get tagsEncoded => tags != null ? jsonEncode(tags) : null;
}

/// Result of a storage usage query.
class StorageUsage {
  final int totalBytes;
  final Map<String, int> bySessionBytes;

  const StorageUsage({
    required this.totalBytes,
    required this.bySessionBytes,
  });
}

/// Result of an account deletion request.
class DeletionRequestResult {
  final String status;
  final String message;

  const DeletionRequestResult({
    required this.status,
    required this.message,
  });
}

/// Optional filter for listing sessions.
class SessionRange {
  final int? startMs;
  final int? endMs;
  final String? mode;

  const SessionRange({this.startMs, this.endMs, this.mode});
}

/// Optional filter for querying HSI windows.
class WindowRange {
  final int? startMs;
  final int? endMs;
  final int? limit;

  const WindowRange({this.startMs, this.endMs, this.limit});
}
