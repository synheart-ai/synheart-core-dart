class UploadMetadata {
  final String sdkVersion;
  final String platform;
  final String capabilityLevel;
  final String? orgId;

  UploadMetadata({
    required this.sdkVersion,
    required this.platform,
    required this.capabilityLevel,
    this.orgId,
  });

  factory UploadMetadata.fromJson(Map<String, dynamic> json) => UploadMetadata(
        sdkVersion: json['sdk_version'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        capabilityLevel: json['capability_level'] as String? ?? '',
        orgId: json['org_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'sdk_version': sdkVersion,
        'platform': platform,
        'capability_level': capabilityLevel,
        if (orgId != null) 'org_id': orgId,
      };
}

class UploadRequest {
  final String userId;
  final UploadMetadata metadata;
  final List<Map<String, dynamic>> snapshots;

  UploadRequest({
    required this.userId,
    required this.metadata,
    required this.snapshots,
  });

  factory UploadRequest.fromJson(Map<String, dynamic> json) => UploadRequest(
        userId: json['user_id'] as String,
        metadata: UploadMetadata.fromJson(
            json['metadata'] as Map<String, dynamic>),
        snapshots: (json['snapshots'] as List<dynamic>)
            .cast<Map<String, dynamic>>(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'metadata': metadata.toJson(),
        'snapshots': snapshots,
      };
}

class UploadResponse {
  final bool? success;
  final String? batchId;
  final List<String>? snapshotIds;
  final List<String>? s3Keys;
  final String? message;

  UploadResponse({
    this.success,
    this.batchId,
    this.snapshotIds,
    this.s3Keys,
    this.message,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      UploadResponse(
        success: json['success'] as bool?,
        batchId: json['batch_id'] as String?,
        snapshotIds: (json['snapshot_ids'] as List<dynamic>?)
            ?.cast<String>(),
        s3Keys: (json['s3_keys'] as List<dynamic>?)?.cast<String>(),
        message: json['message'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (success != null) 'success': success,
        if (batchId != null) 'batch_id': batchId,
        if (snapshotIds != null) 'snapshot_ids': snapshotIds,
        if (s3Keys != null) 's3_keys': s3Keys,
        if (message != null) 'message': message,
      };
}

class UploadErrorResponse {
  final UploadErrorDetail? error;
  final int? retryAfter;

  UploadErrorResponse({this.error, this.retryAfter});

  String get errorCode => error?.code ?? 'unknown';
  String get errorMessage => error?.message ?? 'Unknown error';

  factory UploadErrorResponse.fromJson(Map<String, dynamic> json) =>
      UploadErrorResponse(
        error: json['error'] is Map
            ? UploadErrorDetail.fromJson(
                json['error'] as Map<String, dynamic>)
            : null,
        retryAfter: json['retry_after'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (error != null) 'error': error!.toJson(),
        if (retryAfter != null) 'retry_after': retryAfter,
      };
}

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
      UploadErrorDetail(
        code: json['code'] as String,
        message: json['message'] as String,
        details: json['details'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (details != null) 'details': details,
      };
}
