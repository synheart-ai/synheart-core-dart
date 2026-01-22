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
      status: json['status'] as String,
      snapshotId: json['snapshot_id'] as String?,
      timestamp: (json['timestamp'] as num).toInt(),
    );

Map<String, dynamic> _$UploadResponseToJson(UploadResponse instance) =>
    <String, dynamic>{
      'status': instance.status,
      'snapshot_id': instance.snapshotId,
      'timestamp': instance.timestamp,
    };

UploadErrorResponse _$UploadErrorResponseFromJson(Map<String, dynamic> json) =>
    UploadErrorResponse(
      status: json['status'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      retryAfter: (json['retry_after'] as num?)?.toInt(),
    );

Map<String, dynamic> _$UploadErrorResponseToJson(
  UploadErrorResponse instance,
) => <String, dynamic>{
  'status': instance.status,
  'code': instance.code,
  'message': instance.message,
  'retry_after': instance.retryAfter,
};
