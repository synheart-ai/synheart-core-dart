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

/// Real-time status update for a deletion request, pushed from the cloud
/// over the RAMEN stream. Narrower than [DataDeletionRequest] — only the
/// fields the cloud emits on each lifecycle transition plus the envelope
/// fields RAMEN routes by.
///
/// Subscribe via [Synheart.onDataDeletionUpdate] to avoid polling
/// `dataDeletionStatus` after [Synheart.requestDataDeletion].
class DataDeletionEvent {
  const DataDeletionEvent({
    required this.requestId,
    required this.userId,
    required this.appId,
    required this.orgId,
    required this.tenantId,
    required this.status,
    required this.statusRaw,
    required this.emittedAt,
    this.result,
    this.errorMessage,
  });

  final String requestId;
  final String userId;
  final String appId;
  final String orgId;
  final String tenantId;

  /// Parsed status; never null. [DataDeletionStatus.unknown] for any wire
  /// value this SDK version doesn't recognize.
  final DataDeletionStatus status;

  /// Raw wire string — log this when [status] is [DataDeletionStatus.unknown].
  final String statusRaw;

  /// Per-layer purge stats — present when [status] is
  /// [DataDeletionStatus.completed]. Same shape as
  /// [DataDeletionRequest.result].
  final Map<String, dynamic>? result;

  /// Set when [status] is [DataDeletionStatus.failed].
  final String? errorMessage;

  /// Timestamp the cloud emitted the event (best-effort, UTC).
  final DateTime emittedAt;

  /// Parse from the JSON the runtime delivers from a RAMEN stream callback.
  /// `envelope` is the top-level event map (`event_type`, `payload_json`,
  /// `created_at`, …); `payload` is the parsed inner payload.
  ///
  /// `appId` and `userId` come from the RAMEN connection-level identifiers
  /// captured by [Synheart.startVendorSync] — the runtime event envelope
  /// only carries event-level fields.
  factory DataDeletionEvent.fromRuntimeJson({
    required Map<String, dynamic> envelope,
    required Map<String, dynamic> payload,
    required String appId,
    required String userId,
  }) {
    DateTime emittedAt;
    final raw = envelope['created_at']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        emittedAt = DateTime.parse(raw).toUtc();
      } catch (_) {
        emittedAt = DateTime.now().toUtc();
      }
    } else {
      emittedAt = DateTime.now().toUtc();
    }

    final rawStatus = payload['status']?.toString() ?? 'unknown';
    return DataDeletionEvent(
      requestId: payload['request_id']?.toString() ?? '',
      userId: userId,
      appId: appId,
      orgId: payload['org_id']?.toString() ?? '',
      tenantId: payload['tenant_id']?.toString() ?? '',
      status: DataDeletionStatus.fromWire(rawStatus),
      statusRaw: rawStatus,
      result: (payload['result'] as Map?)?.cast<String, dynamic>(),
      errorMessage:
          (payload['error_message'] as String?)?.trim().isEmpty == false
          ? payload['error_message'] as String
          : null,
      emittedAt: emittedAt,
    );
  }

  @override
  String toString() =>
      'DataDeletionEvent($requestId, status=$statusRaw, userId=$userId)';
}
