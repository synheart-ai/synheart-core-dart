/// Dart-side wire models for the customer-facing GDPR Article 17 endpoints.
///
/// The cloud side returns these as JSON (`/v1/customer/data-deletions`); the
/// Flutter bridge round-trips the JSON through FFI as a UTF-8 string. These
/// helpers parse the resulting [Map] into typed objects.
library;

/// Lifecycle of a deletion request as reported by the cloud.
enum DataDeletionStatus {
  pending,
  inProgress,
  completed,
  failed,
  unknown;

  static DataDeletionStatus fromWire(String? value) {
    switch (value) {
      case 'pending':
        return DataDeletionStatus.pending;
      case 'in_progress':
        return DataDeletionStatus.inProgress;
      case 'completed':
        return DataDeletionStatus.completed;
      case 'failed':
        return DataDeletionStatus.failed;
      default:
        return DataDeletionStatus.unknown;
    }
  }

  /// `true` when the request has reached a terminal state (completed/failed).
  bool get isTerminal =>
      this == DataDeletionStatus.completed || this == DataDeletionStatus.failed;
}

/// A single GDPR Article 17 deletion request returned by the platform.
class DataDeletionRequest {
  const DataDeletionRequest({
    required this.requestId,
    required this.orgId,
    required this.tenantId,
    required this.userId,
    required this.status,
    required this.statusRaw,
    required this.dryRun,
    required this.createdAt,
    this.reason,
    this.contact,
    this.result,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
    this.failedAt,
  });

  /// Opaque public identifier (e.g. `ddr_01HX...`). Use this for status polls.
  final String requestId;
  final String orgId;
  final String tenantId;
  final String userId;

  /// Parsed status; never null. Falls back to [DataDeletionStatus.unknown]
  /// when the cloud returns a value we don't recognize (forward-compatible).
  final DataDeletionStatus status;

  /// Raw status string from the wire — useful for logging unknown values.
  final String statusRaw;

  final bool dryRun;
  final String? reason;
  final String? contact;

  /// Per-layer purge stats once `status == completed`. Shape is intentionally
  /// flexible (the cloud adds fields independently of this SDK) — typically:
  /// `{s3: {total_deleted, total_bytes, deleted_by_prefix}, warehouse: {...}}`.
  final Map<String, dynamic>? result;

  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;

  factory DataDeletionRequest.fromJson(Map<String, dynamic> json) {
    DateTime parseTs(String key, {bool required = false}) {
      final raw = json[key];
      if (raw is String && raw.isNotEmpty) {
        return DateTime.parse(raw).toUtc();
      }
      if (required) {
        throw FormatException('DataDeletionRequest: missing $key');
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    DateTime? parseOptional(String key) {
      final raw = json[key];
      if (raw is String && raw.isNotEmpty) {
        try {
          return DateTime.parse(raw).toUtc();
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final rawStatus = json['status']?.toString() ?? 'unknown';
    return DataDeletionRequest(
      requestId: json['request_id']?.toString() ?? '',
      orgId: json['org_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      status: DataDeletionStatus.fromWire(rawStatus),
      statusRaw: rawStatus,
      dryRun: json['dry_run'] == true,
      reason: (json['reason'] as String?)?.trim().isEmpty == false
          ? json['reason'] as String
          : null,
      contact: (json['contact'] as String?)?.trim().isEmpty == false
          ? json['contact'] as String
          : null,
      result: (json['result'] as Map?)?.cast<String, dynamic>(),
      errorMessage: (json['error_message'] as String?)?.trim().isEmpty == false
          ? json['error_message'] as String
          : null,
      createdAt: parseTs('created_at', required: true),
      startedAt: parseOptional('started_at'),
      completedAt: parseOptional('completed_at'),
      failedAt: parseOptional('failed_at'),
    );
  }

  @override
  String toString() =>
      'DataDeletionRequest($requestId, status=$statusRaw, userId=$userId)';
}

/// Page of deletion requests returned by `GET /v1/customer/data-deletions`.
class DataDeletionList {
  const DataDeletionList({required this.requests, required this.total});

  final List<DataDeletionRequest> requests;
  final int total;
}
