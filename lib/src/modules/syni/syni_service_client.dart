import 'dart:async';
import 'dart:convert';

import '../../core_runtime/core_runtime_bridge.dart';
import 'syni_service_models.dart';

/// Testable transport boundary for the native Syni service calls.
abstract interface class SyniServiceTransport {
  bool get isAvailable;

  Future<Map<String, dynamic>> chat(Map<String, dynamic> request);

  Future<Map<String, dynamic>> listSessions({int limit = 0});

  Future<Map<String, dynamic>> getSession(String sessionId);

  Future<Map<String, dynamic>> getSessionMessages(
    String sessionId, {
    int limit = 0,
  });

  Future<Map<String, dynamic>> closeSession(String sessionId);
}

/// Native transport backed by the registered Synheart Core runtime handle.
class CoreRuntimeSyniServiceTransport implements SyniServiceTransport {
  const CoreRuntimeSyniServiceTransport(this._runtime);

  final CoreRuntimeBridge _runtime;

  @override
  bool get isAvailable => _runtime.isSyniServiceAvailable;

  @override
  Future<Map<String, dynamic>> chat(Map<String, dynamic> request) =>
      _runtime.syniChatJson(jsonEncode(request));

  @override
  Future<Map<String, dynamic>> listSessions({int limit = 0}) =>
      _runtime.syniListSessionsJson(limit: limit);

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) =>
      _runtime.syniGetSessionJson(sessionId);

  @override
  Future<Map<String, dynamic>> getSessionMessages(
    String sessionId, {
    int limit = 0,
  }) => _runtime.syniGetSessionMessagesJson(sessionId, limit: limit);

  @override
  Future<Map<String, dynamic>> closeSession(String sessionId) =>
      _runtime.syniCloseSessionJson(sessionId);
}

/// Device-signed, non-streaming client for Synheart's Syni service.
///
/// Chat calls are serialized because they are non-idempotent and session order
/// matters. Session reads may run concurrently; the native runtime already
/// retries those idempotent operations.
class SyniServiceClient {
  SyniServiceClient(this._transport);

  final SyniServiceTransport _transport;
  Future<void> _chatTail = Future.value();
  String? _sessionId;

  bool get isAvailable => _transport.isAvailable;
  String? get sessionId => _sessionId;

  void useSession(String? sessionId) {
    if (sessionId != null) _validateSessionId(sessionId);
    _sessionId = sessionId;
  }

  void startNewSession() => _sessionId = null;

  Future<SyniServiceChatResponse> chat(
    String message, {
    String? sessionId,
    String? personaId,
    String? persona,
    String? modelId,
    bool includeState = false,
    Map<String, dynamic>? context,
  }) {
    final completer = Completer<SyniServiceChatResponse>();
    final previous = _chatTail;
    _chatTail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed prior turn must not poison the serialization queue.
      }
      try {
        final effectiveSession = sessionId ?? _sessionId;
        final request = SyniServiceChatRequest(
          message: message,
          sessionId: effectiveSession,
          personaId: personaId,
          persona: persona,
          modelId: modelId,
          includeState: includeState,
          context: context,
        );
        _validateRequest(request);
        final json = await _transport.chat(request.toJson());
        _throwIfError(json);
        final response = SyniServiceChatResponse.fromJson(json);
        _sessionId = response.sessionId;
        completer.complete(response);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<List<SyniServiceSession>> listSessions({int limit = 0}) async {
    _validateLimit(limit);
    final json = await _transport.listSessions(limit: limit);
    _throwIfError(json);
    final sessions = json['sessions'];
    if (sessions is! List) return const [];
    return sessions
        .whereType<Map>()
        .map(
          (value) =>
              SyniServiceSession.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false);
  }

  Future<SyniServiceSession> getSession(String sessionId) async {
    _validateSessionId(sessionId);
    final json = await _transport.getSession(sessionId);
    _throwIfError(json);
    return SyniServiceSession.fromJson(json);
  }

  Future<SyniServiceMessagesPage> getSessionMessages(
    String sessionId, {
    int limit = 0,
  }) async {
    _validateSessionId(sessionId);
    _validateLimit(limit);
    final json = await _transport.getSessionMessages(sessionId, limit: limit);
    _throwIfError(json);
    return SyniServiceMessagesPage.fromJson(json);
  }

  Future<void> closeSession(String sessionId) async {
    _validateSessionId(sessionId);
    final json = await _transport.closeSession(sessionId);
    _throwIfError(json);
    if (_sessionId == sessionId) _sessionId = null;
  }

  static void _validateRequest(SyniServiceChatRequest request) {
    if (request.message.trim().isEmpty) {
      throw const SyniServiceException(
        code: SyniServiceErrorCode.invalidInput,
        message: 'message must not be empty',
      );
    }
    final sessionId = request.sessionId;
    if (sessionId != null) _validateSessionId(sessionId);
  }

  static void _validateSessionId(String sessionId) {
    if (sessionId.isEmpty || RegExp(r'[/\s?#]').hasMatch(sessionId)) {
      throw const SyniServiceException(
        code: SyniServiceErrorCode.invalidInput,
        message: 'session_id contains an invalid character',
      );
    }
  }

  static void _validateLimit(int limit) {
    if (limit < -0x80000000 || limit > 0x7fffffff) {
      throw const SyniServiceException(
        code: SyniServiceErrorCode.invalidInput,
        message: 'limit must fit in a signed 32-bit integer',
      );
    }
  }

  static void _throwIfError(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is String && error.isNotEmpty) {
      throw SyniServiceException.fromError(error);
    }
  }
}
