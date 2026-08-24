import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  group('SyniServiceClient', () {
    test('starts a session and reuses it on the next turn', () async {
      final transport = _FakeTransport();
      final client = SyniServiceClient(transport);

      final first = await client.chat(
        'How am I doing?',
        personaId: 'focus.coach.v1',
      );
      expect(first.sessionId, 'session-1');
      expect(client.sessionId, 'session-1');
      expect(transport.chatRequests.first, {
        'message': 'How am I doing?',
        'persona_id': 'focus.coach.v1',
      });

      await client.chat('And compared with yesterday?');
      expect(transport.chatRequests.last['session_id'], 'session-1');
    });

    test('serializes non-idempotent chat turns', () async {
      final firstGate = Completer<void>();
      final transport = _FakeTransport(firstChatGate: firstGate.future);
      final client = SyniServiceClient(transport);

      final first = client.chat('first');
      final second = client.chat('second');
      await Future<void>.delayed(Duration.zero);
      expect(transport.chatRequests.map((e) => e['message']), ['first']);

      firstGate.complete();
      await Future.wait([first, second]);
      expect(transport.chatRequests.map((e) => e['message']), [
        'first',
        'second',
      ]);
    });

    test('a failed turn does not poison the serialized chat queue', () async {
      final transport = _FakeTransport(
        chatError: 'ERR_NETWORK: temporary failure',
        chatErrorCount: 1,
      );
      final client = SyniServiceClient(transport);

      final first = client.chat('first');
      final second = client.chat('second');

      await expectLater(first, throwsA(isA<SyniServiceException>()));
      expect((await second).reply, 'Hello back');
      expect(transport.chatRequests.map((e) => e['message']), [
        'first',
        'second',
      ]);
    });

    test('surfaces delivery-unknown as a typed network exception', () async {
      final transport = _FakeTransport(
        chatError:
            'ERR_NETWORK: syni POST /v1/chat failed and was not retried '
            '(delivery unknown — do not blindly resend)',
      );
      final client = SyniServiceClient(transport);

      await expectLater(
        client.chat('hello'),
        throwsA(
          isA<SyniServiceException>()
              .having(
                (error) => error.code,
                'code',
                SyniServiceErrorCode.network,
              )
              .having(
                (error) => error.deliveryUnknown,
                'deliveryUnknown',
                isTrue,
              ),
        ),
      );
    });

    test('validates empty messages and unsafe session ids locally', () async {
      final transport = _FakeTransport();
      final client = SyniServiceClient(transport);

      await expectLater(
        client.chat('   '),
        throwsA(
          isA<SyniServiceException>().having(
            (error) => error.code,
            'code',
            SyniServiceErrorCode.invalidInput,
          ),
        ),
      );
      expect(transport.chatRequests, isEmpty);
      expect(
        () => client.useSession('bad/session'),
        throwsA(isA<SyniServiceException>()),
      );
    });

    test(
      'parses sessions and message pages without losing raw fields',
      () async {
        final transport = _FakeTransport();
        final client = SyniServiceClient(transport);

        final sessions = await client.listSessions(limit: 10);
        expect(sessions.single.id, 'session-1');
        expect(sessions.single.raw['custom'], 42);

        final page = await client.getSessionMessages('session-1', limit: 20);
        expect(page.count, 2);
        expect(page.messages.first.isUser, isTrue);
        expect(page.messages.last.content, 'Hello back');
      },
    );

    test('closing the active session clears sticky state', () async {
      final transport = _FakeTransport();
      final client = SyniServiceClient(transport);
      await client.chat('hello');
      expect(client.sessionId, 'session-1');

      await client.closeSession('session-1');
      expect(client.sessionId, isNull);
      expect(transport.closedSessionIds, ['session-1']);
    });
  });

  test('chat response exposes model fallback metadata', () {
    final response = SyniServiceChatResponse.fromJson(const {
      'session_id': 's1',
      'reply': 'Hi',
      'model': {'id': 'model-1', 'fallback': true},
      'state': {'focus': 0.7},
    });

    expect(response.reply, 'Hi');
    expect(response.model?.id, 'model-1');
    expect(response.usedModelFallback, isTrue);
    expect(response.state?['focus'], 0.7);
  });

  test('classifies the runtime authentication prerequisite error', () {
    final error = SyniServiceException.fromError(
      'syni requires a registered device (Mode A) or HMAC credentials (Mode B)',
    );

    expect(error.code, SyniServiceErrorCode.authentication);
  });

  test('SyniModule resolves a service that becomes available later', () {
    final transport = _FakeTransport();
    final client = SyniServiceClient(transport);
    SyniServiceClient? availableClient;
    final module = SyniModule(serviceProvider: () => availableClient);

    expect(module.service, isNull);
    availableClient = client;
    expect(module.service, same(client));
  });
}

class _FakeTransport implements SyniServiceTransport {
  _FakeTransport({this.firstChatGate, this.chatError, int chatErrorCount = 1})
    : _remainingChatErrors = chatError == null ? 0 : chatErrorCount;

  final Future<void>? firstChatGate;
  final String? chatError;
  int _remainingChatErrors;
  final List<Map<String, dynamic>> chatRequests = [];
  final List<String> closedSessionIds = [];

  @override
  bool get isAvailable => true;

  @override
  Future<Map<String, dynamic>> chat(Map<String, dynamic> request) async {
    chatRequests.add(Map<String, dynamic>.from(request));
    if (chatRequests.length == 1 && firstChatGate != null) {
      await firstChatGate;
    }
    if (_remainingChatErrors > 0) {
      _remainingChatErrors--;
      return {'error': chatError};
    }
    return {
      'session_id': request['session_id'] ?? 'session-1',
      'reply': 'Hello back',
      'model': {'id': 'default', 'fallback': false},
    };
  }

  @override
  Future<Map<String, dynamic>> closeSession(String sessionId) async {
    closedSessionIds.add(sessionId);
    return {'status': 'closed'};
  }

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) async => {
    'id': sessionId,
    'status': 'active',
  };

  @override
  Future<Map<String, dynamic>> getSessionMessages(
    String sessionId, {
    int limit = 0,
  }) async => {
    'session_id': sessionId,
    'messages': [
      {'role': 'user', 'content': 'Hello'},
      {'role': 'assistant', 'content': 'Hello back'},
    ],
    'count': 2,
  };

  @override
  Future<Map<String, dynamic>> listSessions({int limit = 0}) async => {
    'sessions': [
      {'id': 'session-1', 'custom': 42},
    ],
  };
}
