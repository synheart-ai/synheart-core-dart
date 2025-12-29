// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Subject _$SubjectFromJson(Map<String, dynamic> json) => Subject(
      subjectType: json['subject_type'] as String,
      subjectId: json['subject_id'] as String,
    );

Map<String, dynamic> _$SubjectToJson(Subject instance) => <String, dynamic>{
      'subject_type': instance.subjectType,
      'subject_id': instance.subjectId,
    };

UploadRequest _$UploadRequestFromJson(Map<String, dynamic> json) =>
    UploadRequest(
      subject: Subject.fromJson(json['subject'] as Map<String, dynamic>),
      snapshots: (json['snapshots'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
    );

Map<String, dynamic> _$UploadRequestToJson(UploadRequest instance) =>
    <String, dynamic>{
      'subject': instance.subject.toJson(),
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
) =>
    <String, dynamic>{
      'status': instance.status,
      'code': instance.code,
      'message': instance.message,
      'retry_after': instance.retryAfter,
    };
