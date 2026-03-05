// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadMetadata _$UploadMetadataFromJson(Map<String, dynamic> json) =>
    UploadMetadata(
      sdkVersion: json['sdk_version'] as String,
      platform: json['platform'] as String,
      capabilityLevel: json['capability_level'] as String,
      orgId: json['org_id'] as String?,
    );

Map<String, dynamic> _$UploadMetadataToJson(UploadMetadata instance) =>
    <String, dynamic>{
      'sdk_version': instance.sdkVersion,
      'platform': instance.platform,
      'capability_level': instance.capabilityLevel,
      'org_id': instance.orgId,
    };

UploadRequest _$UploadRequestFromJson(Map<String, dynamic> json) =>
    UploadRequest(
      userId: json['user_id'] as String,
      metadata: UploadMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      snapshots: (json['snapshots'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
    );

Map<String, dynamic> _$UploadRequestToJson(UploadRequest instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'metadata': instance.metadata.toJson(),
      'snapshots': instance.snapshots,
    };

UploadResponse _$UploadResponseFromJson(Map<String, dynamic> json) =>
    UploadResponse(
      success: json['success'] as bool?,
      batchId: json['batch_id'] as String?,
      snapshotIds: (json['snapshot_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      s3Keys: (json['s3_keys'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      message: json['message'] as String?,
      status: json['status'] as String?,
      snapshotId: json['snapshot_id'] as String?,
      timestamp: (json['timestamp'] as num?)?.toInt(),
    );

Map<String, dynamic> _$UploadResponseToJson(UploadResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'batch_id': instance.batchId,
      'snapshot_ids': instance.snapshotIds,
      's3_keys': instance.s3Keys,
      'message': instance.message,
      'status': instance.status,
      'snapshot_id': instance.snapshotId,
      'timestamp': instance.timestamp,
    };

UploadErrorResponse _$UploadErrorResponseFromJson(Map<String, dynamic> json) =>
    UploadErrorResponse(
      error: json['error'] == null
          ? null
          : UploadErrorDetail.fromJson(
              json['error'] as Map<String, dynamic>,
            ),
      status: json['status'] as String?,
      code: json['code'] as String?,
      message: json['message'] as String?,
      retryAfter: (json['retry_after'] as num?)?.toInt(),
    );

Map<String, dynamic> _$UploadErrorResponseToJson(
  UploadErrorResponse instance,
) =>
    <String, dynamic>{
      'error': instance.error?.toJson(),
      'status': instance.status,
      'code': instance.code,
      'message': instance.message,
      'retry_after': instance.retryAfter,
    };

UploadErrorDetail _$UploadErrorDetailFromJson(Map<String, dynamic> json) =>
    UploadErrorDetail(
      code: json['code'] as String,
      message: json['message'] as String,
      details: json['details'] as String?,
    );

Map<String, dynamic> _$UploadErrorDetailToJson(UploadErrorDetail instance) =>
    <String, dynamic>{
      'code': instance.code,
      'message': instance.message,
      'details': instance.details,
    };
