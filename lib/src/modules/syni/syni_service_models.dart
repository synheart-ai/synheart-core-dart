import 'package:flutter/foundation.dart';

/// One non-streaming request to Synheart's device-signed Syni service.
@immutable
class SyniServiceChatRequest {
  const SyniServiceChatRequest({
    required this.message,
    this.sessionId,
    this.personaId,
    this.persona,
    this.modelId,
    this.includeState = false,
    this.context,
  });

  final String message;
  final String? sessionId;
  final String? personaId;
  final String? persona;
  final String? modelId;
  final bool includeState;
  final Map<String, dynamic>? context;

  Map<String, dynamic> toJson() => {
    'message': message,
    if (sessionId != null) 'session_id': sessionId,
    if (personaId != null) 'persona_id': personaId,
    if (personaId == null && persona != null) 'persona': persona,
    if (modelId != null) 'model_id': modelId,
    if (includeState) 'include_state': true,
    if (context != null) 'context': context,
  };
}

/// Model selection metadata returned by the Syni service.
@immutable
class SyniServiceModelInfo {
  const SyniServiceModelInfo({this.id, this.fallback = false, this.raw});

  final String? id;
  final bool fallback;
  final Map<String, dynamic>? raw;

  factory SyniServiceModelInfo.fromJson(Map<String, dynamic> json) =>
      SyniServiceModelInfo(
        id: _string(json['id']) ?? _string(json['model_id']),
        fallback: json['fallback'] == true,
        raw: Map.unmodifiable(json),
      );
}

/// Completed non-streaming Syni service chat turn.
@immutable
class SyniServiceChatResponse {
  const SyniServiceChatResponse({
    required this.sessionId,
    required this.reply,
    this.model,
    this.state,
    required this.raw,
  });

  final String sessionId;
  final String reply;
  final SyniServiceModelInfo? model;
  final Map<String, dynamic>? state;
  final Map<String, dynamic> raw;

  bool get usedModelFallback => model?.fallback ?? false;

  factory SyniServiceChatResponse.fromJson(Map<String, dynamic> json) {
    final sessionId = _string(json['session_id']);
    final reply = _string(json['reply']);
    if (sessionId == null || sessionId.isEmpty || reply == null) {
      throw const FormatException(
        'Syni chat response is missing session_id or reply',
      );
    }
    final rawModel = json['model'];
    final rawState = json['state'];
    return SyniServiceChatResponse(
      sessionId: sessionId,
      reply: reply,
      model: rawModel is Map
          ? SyniServiceModelInfo.fromJson(Map<String, dynamic>.from(rawModel))
          : null,
      state: rawState is Map ? Map<String, dynamic>.from(rawState) : null,
      raw: Map.unmodifiable(json),
    );
  }
}

/// One server-side Syni conversation session.
///
/// The service may add fields over time; common fields are typed and [raw]
/// preserves the complete forward-compatible payload.
@immutable
class SyniServiceSession {
  const SyniServiceSession({
    required this.id,
    this.createdAt,
    this.updatedAt,
    this.status,
    this.personaId,
    this.modelId,
    required this.raw,
  });

  final String id;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? status;
  final String? personaId;
  final String? modelId;
  final Map<String, dynamic> raw;

  factory SyniServiceSession.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']) ?? _string(json['session_id']);
    if (id == null || id.isEmpty) {
      throw const FormatException('Syni session is missing id');
    }
    return SyniServiceSession(
      id: id,
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      status: _string(json['status']),
      personaId: _string(json['persona_id']),
      modelId: _string(json['model_id']),
      raw: Map.unmodifiable(json),
    );
  }
}

/// One message in a Syni service session.
@immutable
class SyniServiceMessage {
  const SyniServiceMessage({
    this.id,
    required this.role,
    required this.content,
    this.createdAt,
    required this.raw,
  });

  final String? id;
  final String role;
  final String content;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  bool get isUser => role == 'user';

  factory SyniServiceMessage.fromJson(Map<String, dynamic> json) {
    final role = _string(json['role']);
    final content = _string(json['content']) ?? _string(json['message']);
    if (role == null || content == null) {
      throw const FormatException('Syni message is missing role or content');
    }
    return SyniServiceMessage(
      id: _string(json['id']) ?? _string(json['message_id']),
      role: role,
      content: content,
      createdAt: _date(json['created_at']),
      raw: Map.unmodifiable(json),
    );
  }
}

@immutable
class SyniServiceMessagesPage {
  const SyniServiceMessagesPage({
    required this.sessionId,
    required this.messages,
    required this.count,
    required this.raw,
  });

  final String sessionId;
  final List<SyniServiceMessage> messages;
  final int count;
  final Map<String, dynamic> raw;

  factory SyniServiceMessagesPage.fromJson(Map<String, dynamic> json) {
    final sessionId = _string(json['session_id']);
    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException(
        'Syni messages response is missing session_id',
      );
    }
    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
              .whereType<Map>()
              .map(
                (value) => SyniServiceMessage.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false)
        : const <SyniServiceMessage>[];
    return SyniServiceMessagesPage(
      sessionId: sessionId,
      messages: messages,
      count: (json['count'] as num?)?.toInt() ?? messages.length,
      raw: Map.unmodifiable(json),
    );
  }
}

enum SyniServiceErrorCode {
  invalidInput,
  notFound,
  authentication,
  network,
  unsupported,
  unavailable,
  unknown,
}

/// Typed failure returned by the runtime's `{ "error": ... }` envelope.
class SyniServiceException implements Exception {
  const SyniServiceException({
    required this.code,
    required this.message,
    this.rawError,
  });

  final SyniServiceErrorCode code;
  final String message;
  final String? rawError;

  /// The runtime could not determine whether the non-idempotent turn landed.
  /// Callers must reconcile session messages before offering a resend.
  bool get deliveryUnknown =>
      rawError?.toLowerCase().contains('delivery unknown') ?? false;

  bool get quotaExceeded =>
      rawError?.toLowerCase().contains('quota exceeded') ?? false;

  factory SyniServiceException.fromError(String error) {
    final upper = error.toUpperCase();
    final code = switch (upper) {
      _ when upper.startsWith('ERR_INVALID_INPUT') =>
        SyniServiceErrorCode.invalidInput,
      _ when upper.startsWith('ERR_NOT_FOUND') => SyniServiceErrorCode.notFound,
      _ when upper.startsWith('ERR_AUTH') =>
        SyniServiceErrorCode.authentication,
      _
          when upper.contains('REQUIRES A REGISTERED DEVICE') ||
              upper.contains('HMAC CREDENTIALS') =>
        SyniServiceErrorCode.authentication,
      _ when upper.startsWith('ERR_NETWORK') => SyniServiceErrorCode.network,
      _ when upper.startsWith('ERR_UNSUPPORTED') =>
        SyniServiceErrorCode.unsupported,
      _ when upper.startsWith('ERR_UNAVAILABLE') =>
        SyniServiceErrorCode.unavailable,
      _ => SyniServiceErrorCode.unknown,
    };
    final separator = error.indexOf(':');
    final message = separator >= 0
        ? error.substring(separator + 1).trim()
        : error;
    return SyniServiceException(code: code, message: message, rawError: error);
  }

  @override
  String toString() => 'SyniServiceException(${code.name}): $message';
}

String? _string(Object? value) => value is String ? value : null;

DateTime? _date(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return null;
}
