import 'package:json_annotation/json_annotation.dart';

part 'upload_models.g.dart';

@JsonSerializable()
class UploadMetadata {
  @JsonKey(name: 'sdk_version')
  final String sdkVersion;

  final String platform;

  @JsonKey(name: 'capability_level')
  final String capabilityLevel;

  @JsonKey(name: 'org_id')
  final String? orgId;

  UploadMetadata({
    required this.sdkVersion,
    required this.platform,
    required this.capabilityLevel,
    this.orgId,
  });

  factory UploadMetadata.fromJson(Map<String, dynamic> json) =>
      _$UploadMetadataFromJson(json);
  Map<String, dynamic> toJson() => _$UploadMetadataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class UploadRequest {
  @JsonKey(name: 'user_id')
  final String userId;

  final UploadMetadata metadata;
  final List<Map<String, dynamic>>
  snapshots; // Array of snapshot objects with hsi, focus, emotion, timestamp

  UploadRequest({
    required this.userId,
    required this.metadata,
    required this.snapshots,
  });

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
