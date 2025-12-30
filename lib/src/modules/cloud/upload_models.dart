import 'package:json_annotation/json_annotation.dart';

part 'upload_models.g.dart';

@JsonSerializable()
class Subject {
  @JsonKey(name: 'subject_type')
  final String subjectType;

  @JsonKey(name: 'subject_id')
  final String subjectId;

  Subject({required this.subjectType, required this.subjectId});

  factory Subject.fromJson(Map<String, dynamic> json) =>
      _$SubjectFromJson(json);
  Map<String, dynamic> toJson() => _$SubjectToJson(this);
}

@JsonSerializable(explicitToJson: true)
class UploadRequest {
  final Subject subject;
  final List<Map<String, dynamic>> snapshots; // Array of HSI 1.0 payloads

  UploadRequest({required this.subject, required this.snapshots});

  factory UploadRequest.fromJson(Map<String, dynamic> json) =>
      _$UploadRequestFromJson(json);
  Map<String, dynamic> toJson() => _$UploadRequestToJson(this);
}

@JsonSerializable()
class UploadResponse {
  final String status;

  @JsonKey(name: 'snapshot_id')
  final String? snapshotId;

  final int timestamp;

  UploadResponse({
    required this.status,
    this.snapshotId,
    required this.timestamp,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      _$UploadResponseFromJson(json);
  Map<String, dynamic> toJson() => _$UploadResponseToJson(this);
}

@JsonSerializable()
class UploadErrorResponse {
  final String status;
  final String code;
  final String message;

  @JsonKey(name: 'retry_after')
  final int? retryAfter; // For 429 responses

  UploadErrorResponse({
    required this.status,
    required this.code,
    required this.message,
    this.retryAfter,
  });

  factory UploadErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$UploadErrorResponseFromJson(json);
  Map<String, dynamic> toJson() => _$UploadErrorResponseToJson(this);
}
