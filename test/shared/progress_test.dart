import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// A mock transport implementation for testing the protocol layer
class MockTransport implements Transport {
  final List<JsonRpcMessage> sentMessages = [];
  final StreamController<JsonRpcMessage> _incomingMessages =
      StreamController<JsonRpcMessage>.broadcast();
  bool _started = false;
  bool _closed = false;
  String? _sessionId;

  final Completer<void> _startCompleter = Completer<void>();

  @override
  String? get sessionId => _sessionId;

  set sessionId(String? value) {
    _sessionId = value;
  }

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Clears the list of sent messages - useful between tests
  void clearSentMessages() {
    sentMessages.clear();
  }

  /// Simulates receiving a message from the remote end
  void receiveMessage(JsonRpcMessage message) {
    if (_closed) {
      return;
    }

    if (onmessage != null) {
      // print('MockTransport: Receiving message ${message.toJson()}');
      onmessage!(message);
    } else {
      print('MockTransport: No onmessage handler set!');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    if (!_startCompleter.isCompleted) {
      _startCompleter.complete();
    }

    onclose?.call();
    await _incomingMessages.close();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closed) {
      throw StateError('Transport is closed');
    }
    // print('MockTransport: Sending message ${message.toJson()}');
    sentMessages.add(message);
  }

  @override
  Future<void> start() async {
    if (_closed) {
      throw StateError('Cannot start a closed transport');
    }
    if (_started) return _startCompleter.future;
    _started = true;

    if (!_startCompleter.isCompleted) {
      _startCompleter.complete();
    }

    return _startCompleter.future;
  }
}

/// A concrete implementation of Protocol for testing
class TestProtocol extends Protocol {
  TestProtocol([ProtocolOptions? options])
      : super(options ?? const ProtocolOptions());

  @override
  void assertCapabilityForMethod(String method) {}

  @override
  void assertNotificationCapability(String method) {}

  @override
  void assertRequestHandlerCapability(String method) {}

  @override
  void assertTaskCapability(String method) {}

  @override
  void assertTaskHandlerCapability(String method) {}
}

class TestResult implements BaseResultData {
  final String value;

  @override
  final Map<String, dynamic>? meta;

  TestResult({required this.value, this.meta});

  @override
  Map<String, dynamic> toJson() => {'value': value};
}

void main() {
  group('Progress Notification Tests', () {
    late TestProtocol protocol;
    late MockTransport transport;

    setUp(() async {
      transport = MockTransport();
      protocol = TestProtocol();
      protocol.onerror = (e) => print('Protocol Error: $e');
      await protocol.connect(transport);
    });

    tearDown(() async {
      await protocol.close();
      await transport.close();
    });

    test('Client receives progress notifications', () async {
      final completer = Completer<void>();
      final receivedProgress = <Progress>[];

      // 1. Client starts a request with onprogress
      final requestFuture = protocol.request<TestResult>(
        const JsonRpcRequest(id: 1, method: 'test/progress'),
        (json) => TestResult(value: json['value']),
        RequestOptions(
          onprogress: (progress) {
            receivedProgress.add(progress);
            if (receivedProgress.length == 2) {
              completer.complete();
            }
          },
        ),
      );

      // Verify request sent with progress token
      expect(transport.sentMessages.length, 1);
      final sentRequest = transport.sentMessages.first as JsonRpcRequest;
      final requestId = sentRequest.id; // Capture the real ID

      expect(sentRequest.meta, isNotNull);
      expect(sentRequest.meta!['progressToken'], isNotNull);
      final progressToken = sentRequest.meta!['progressToken'];

      // 2. Simulate server sending progress (injecting into transport)
      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: ProgressNotification(
            progressToken: progressToken,
            progress: 50,
            total: 100,
            message: 'Halfway there',
          ),
        ),
      );

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: ProgressNotification(
            progressToken: progressToken,
            progress: 100,
            total: 100,
            message: 'Done',
          ),
        ),
      );

      // Yield to allow microtasks (progress handlers) to run before response
      await Future.delayed(Duration.zero);

      // 3. Simulate final response
      transport.receiveMessage(
        JsonRpcResponse(id: requestId, result: {'value': 'done'}),
      );

      final result = await requestFuture;
      expect(result.value, 'done');

      // Verify progress callbacks
      await completer.future; // Ensure callbacks finished
      expect(receivedProgress.length, 2);
      expect(receivedProgress[0].progress, 50);
      expect(receivedProgress[0].total, 100);
      expect(receivedProgress[0].message, 'Halfway there');
      expect(receivedProgress[1].progress, 100);
      expect(receivedProgress[1].message, 'Done');
    });

    test('Server sends progress using RequestHandlerExtra.sendProgress',
        () async {
      // 1. Setup server handler
      protocol.setRequestHandler<JsonRpcRequest>(
        'test/long-task',
        (request, extra) async {
          // Simulate work and send progress
          await extra.sendProgress(10, total: 100, message: 'Starting');
          await extra.sendProgress(100, total: 100, message: 'Finished');
          return TestResult(value: 'success');
        },
        (id, params, meta) => JsonRpcRequest(
          id: id,
          method: 'test/long-task',
          params: params,
          meta: meta,
        ),
      );

      // 2. Simulate client sending a request with a progress token
      final progressToken = 12345;
      transport.receiveMessage(
        JsonRpcRequest(
          id: 99,
          method: 'test/long-task',
          meta: {'progressToken': progressToken},
        ),
      );

      // Wait for async operations to complete (microtasks)
      await Future.delayed(const Duration(milliseconds: 50));

      // 3. Verify server sent progress notifications
      // Expected messages: Progress(10), Progress(100), Response
      expect(transport.sentMessages.length, 3);

      final msg1 = transport.sentMessages[0];
      expect(msg1, isA<JsonRpcNotification>());
      expect((msg1 as JsonRpcNotification).method, 'notifications/progress');
      expect(msg1.params, isNotNull);
      expect(msg1.params!['progressToken'], progressToken);
      expect(msg1.params!['progress'], 10);
      expect(msg1.params!['message'], 'Starting');

      final msg2 = transport.sentMessages[1];
      expect(msg2, isA<JsonRpcNotification>());
      expect((msg2 as JsonRpcNotification).method, 'notifications/progress');
      expect(msg2.params!['progress'], 100);
      expect(msg2.params!['message'], 'Finished');

      final msg3 = transport.sentMessages[2];
      expect(msg3, isA<JsonRpcResponse>());
    });

    test('Server ignores sendProgress if no token provided', () async {
      // 1. Setup server handler
      protocol.setRequestHandler<JsonRpcRequest>(
        'test/no-token',
        (request, extra) async {
          // Should not crash, just do nothing or log warning
          await extra.sendProgress(50);
          return TestResult(value: 'ok');
        },
        (id, params, meta) => JsonRpcRequest(
          id: id,
          method: 'test/no-token',
          params: params,
          meta: meta,
        ),
      );

      // 2. Simulate client sending a request WITHOUT progress token
      transport.receiveMessage(
        const JsonRpcRequest(id: 100, method: 'test/no-token'),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // 3. Verify only response is sent, no progress
      expect(transport.sentMessages.length, 1);
      expect(transport.sentMessages.first, isA<JsonRpcResponse>());
    });
  });
}
