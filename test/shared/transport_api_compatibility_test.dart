import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class LegacyTransport implements Transport {
  JsonRpcMessage? lastMessage;
  int? lastRelatedRequestId;

  @override
  Future<void> close() async {}

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    lastMessage = message;
    lastRelatedRequestId = relatedRequestId;
  }

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {}
}

class StringAwareTransport extends LegacyTransport
    implements RequestIdAwareTransport {
  RequestId? lastRequestIdAwareRelatedRequestId;

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    lastMessage = message;
    lastRequestIdAwareRelatedRequestId = relatedRequestId;
  }
}

void main() {
  group('Transport request ID compatibility', () {
    test('legacy transports keep compiling with int relatedRequestId',
        () async {
      final transport = LegacyTransport();

      await transport.sendPreservingRequestId(
        const JsonRpcNotification(method: 'test/notification'),
        relatedRequestId: 'client-req-1',
      );

      expect(transport.lastMessage, isA<JsonRpcNotification>());
      expect(transport.lastRelatedRequestId, isNull);
    });

    test('request-id-aware transports preserve string relatedRequestId',
        () async {
      final transport = StringAwareTransport();

      await transport.sendPreservingRequestId(
        const JsonRpcNotification(method: 'test/notification'),
        relatedRequestId: 'client-req-1',
      );

      expect(transport.lastMessage, isA<JsonRpcNotification>());
      expect(transport.lastRelatedRequestId, isNull);
      expect(transport.lastRequestIdAwareRelatedRequestId, 'client-req-1');
    });
  });
}
