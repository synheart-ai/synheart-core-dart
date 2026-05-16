class TimeRange {
  final int startMs;
  final int endMs;

  const TimeRange({required this.startMs, required this.endMs});

  Map<String, dynamic> toJson() => {'start_ms': startMs, 'end_ms': endMs};

  factory TimeRange.fromJson(Map<String, dynamic> json) =>
      TimeRange(startMs: json['start_ms'] as int, endMs: json['end_ms'] as int);
}

class SchemaRef {
  final String name;
  final String version;

  const SchemaRef({required this.name, required this.version});

  Map<String, dynamic> toJson() => {'name': name, 'version': version};

  factory SchemaRef.fromJson(Map<String, dynamic> json) => SchemaRef(
    name: json['name'] as String,
    version: json['version'] as String,
  );
}

class ArtifactHeader {
  final int version;
  final String type;
  final String artifactId;
  final String subjectId;
  final String? sessionId;
  final TimeRange timeRange;
  final int seq;
  final SchemaRef schema;
  final int createdAtMs;

  ArtifactHeader({
    this.version = 1,
    required this.type,
    this.artifactId = '',
    required this.subjectId,
    this.sessionId,
    required this.timeRange,
    this.seq = 0,
    required this.schema,
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'version': version,
    'type': type,
    'artifact_id': artifactId,
    'subject_id': subjectId,
    'session_id': sessionId,
    'time_range': timeRange.toJson(),
    'seq': seq,
    'schema': schema.toJson(),
    'created_at_ms': createdAtMs,
  };

  factory ArtifactHeader.fromJson(Map<String, dynamic> json) => ArtifactHeader(
    version: (json['version'] as num?)?.toInt() ?? 1,
    type: json['type'] as String,
    artifactId: json['artifact_id'] as String? ?? '',
    subjectId: json['subject_id'] as String,
    sessionId: json['session_id'] as String?,
    timeRange: TimeRange.fromJson(json['time_range'] as Map<String, dynamic>),
    seq: (json['seq'] as num?)?.toInt() ?? 0,
    schema: SchemaRef.fromJson(json['schema'] as Map<String, dynamic>),
    createdAtMs: (json['created_at_ms'] as num).toInt(),
  );
}
