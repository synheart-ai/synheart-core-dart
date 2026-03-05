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
  /// Present in 202 response (new API)
  final bool? success;

  @JsonKey(name: 'batch_id')
  final String? batchId;

  @JsonKey(name: 'snapshot_ids')
  final List<String>? snapshotIds;

  @JsonKey(name: 's3_keys')
  final List<String>? s3Keys;

  final String? message;

  /// Legacy 200 response fields (kept for backward compatibility)
  final String? status;

  @JsonKey(name: 'snapshot_id')
  final String? snapshotId;

  final int? timestamp;

  UploadResponse({
    this.success,
    this.batchId,
    this.snapshotIds,
    this.s3Keys,
    this.message,
    this.status,
    this.snapshotId,
    this.timestamp,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      _$UploadResponseFromJson(json);
  Map<String, dynamic> toJson() => _$UploadResponseToJson(this);
}

@JsonSerializable()
class UploadErrorResponse {
  /// Nested error object (API returns { "error": { "code", "message", "details?" } })
  final UploadErrorDetail? error;

  /// Legacy top-level fields (for older API or when error is at root)
  final String? status;
  final String? code;
  final String? message;

  @JsonKey(name: 'retry_after')
  final int? retryAfter; // For 429 responses

  UploadErrorResponse({
    this.error,
    this.status,
    this.code,
    this.message,
    this.retryAfter,
  });

  /// Code from error object or top-level
  String get errorCode => error?.code ?? code ?? 'unknown';

  /// Message from error object or top-level
  String get errorMessage => error?.message ?? message ?? 'Unknown error';

  factory UploadErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$UploadErrorResponseFromJson(json);
  Map<String, dynamic> toJson() => _$UploadErrorResponseToJson(this);
}

@JsonSerializable()
class UploadErrorDetail {
  final String code;
  final String message;
  final String? details;

  UploadErrorDetail({
    required this.code,
    required this.message,
    this.details,
  });

  factory UploadErrorDetail.fromJson(Map<String, dynamic> json) =>
      _$UploadErrorDetailFromJson(json);
  Map<String, dynamic> toJson() => _$UploadErrorDetailToJson(this);
}
