import 'artifact_header.dart';

class TombstoneData {
  final String targetArtifactId;
  final String reason;
  final int deletedAtMs;

  const TombstoneData({
    required this.targetArtifactId,
    required this.reason,
    required this.deletedAtMs,
  });

  Map<String, dynamic> toJson() => {
    'target_artifact_id': targetArtifactId,
    'reason': reason,
    'deleted_at_ms': deletedAtMs,
  };

  factory TombstoneData.fromJson(Map<String, dynamic> json) => TombstoneData(
    targetArtifactId: json['target_artifact_id'] as String,
    reason: json['reason'] as String,
    deletedAtMs: json['deleted_at_ms'] as int,
  );
}

/// Propagates deletion across devices/apps.
class TombstoneArtifact {
  final ArtifactHeader header;
  final TombstoneData tombstone;

  TombstoneArtifact({required this.header, required this.tombstone});

  Map<String, dynamic> toJson() => {
    ...header.toJson(),
    'tombstone': tombstone.toJson(),
  };

  factory TombstoneArtifact.fromJson(Map<String, dynamic> json) =>
      TombstoneArtifact(
        header: ArtifactHeader.fromJson(json['header'] as Map<String, dynamic>),
        tombstone: TombstoneData.fromJson(
          json['tombstone'] as Map<String, dynamic>,
        ),
      );
}
