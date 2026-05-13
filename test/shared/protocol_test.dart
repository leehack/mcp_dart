import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// A mock transport implementation for testing the protocol layer
class MockTransport implements Transport, RequestIdAwareTransport {
  final List<JsonRpcMessage> sentMessages = [];
  final List<RequestId?> relatedRequestIds = [];
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
    relatedRequestIds.clear();
  }

  /// Simulates receiving a message from the remote end
  void receiveMessage(JsonRpcMessage message) {
    if (_closed) {
      return;
    }

    if (onmessage != null) {
      onmessage!(message);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    // Make sure we fulfill the start promise if it's still pending
    if (!_startCompleter.isCompleted) {
      _startCompleter.complete();
    }

    // Save these before closing as they'll be null after
    final closeHandler = onclose;

    // Clear handlers first
    onclose = null;
    onmessage = null;
    onerror = null;

    // Call close handler before closing the stream
    if (closeHandler != null) {
      try {
        closeHandler();
      } catch (e) {
        print('Error in close handler: $e');
      }
    }

    // Close the stream
    await _incomingMessages.close();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) {
    return sendWithRequestId(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    if (_closed) {
      throw StateError('Transport is closed');
    }
    sentMessages.add(message);
    relatedRequestIds.add(relatedRequestId);
  }

  @override
  Future<void> start() async {
    if (_closed) {
      throw StateError('Cannot start a closed transport');
    }
    if (_started) return _startCompleter.future;
    _started = true;

    // Complete immediately to avoid test delays
    if (!_startCompleter.isCompleted) {
      _startCompleter.complete();
    }

    return _startCompleter.future;
  }

  /// Creates a shutdown error to test error handling
  void simulateError(Error error) {
    onerror?.call(error);
  }
}

Future<void> waitForSentMessages(
  MockTransport transport,
  int count, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (transport.sentMessages.length < count &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (transport.sentMessages.length < count) {
    fail(
      'Timed out waiting for $count sent messages; '
      'only saw ${transport.sentMessages.length}.',
    );
  }
}

/// A concrete implementation of Protocol for testing
class TestProtocol extends Protocol {
  // Properly structure capabilities as nested Maps
  final Map<String, Map<String, bool>> _capabilities = {
    'requests': {
      'test/method': true,
      'ping': true,
    },
    'notifications': {
      'test/notification': true,
      'notifications/cancelled': true,
      'notifications/progress': true,
    },
  };

  /// Constructs a TestProtocol with optional configuration
  TestProtocol([ProtocolOptions? options])
      : super(options ?? const ProtocolOptions());

  @override
  void assertCapabilityForMethod(String method) {
    if (_capabilities['requests']?[method] != true) {
      throw McpError(
        ErrorCode.methodNotFound.value,
        'Method not supported: $method',
      );
    }
  }

  @override
  void assertNotificationCapability(String method) {
    if (_capabilities['notifications']?[method] != true) {
      throw McpError(
        ErrorCode.methodNotFound.value,
        'Notification not supported: $method',
      );
    }
  }

  @override
  void assertRequestHandlerCapability(String method) {
    // For this test implementation, assume any method can be handled
  }

  @override
  void assertTaskCapability(String method) {
    // Mock implementation
  }

  @override
  void assertTaskHandlerCapability(String method) {
    // Mock implementation
  }
}

/// Custom result data for testing
class TestResult implements BaseResultData {
  final String value;

  @override
  final Map<String, dynamic>? meta;

  TestResult({required this.value, this.meta});

  @override
  Map<String, dynamic> toJson() => {'value': value};
}

void main() {
  group('Protocol tests', () {
    late TestProtocol protocol;
    late MockTransport transport;

    setUp(() async {
      transport = MockTransport();
      protocol = TestProtocol();
    });

    tearDown(() async {
      // Clean tear down, in reverse order
      try {
        await protocol.close();
      } catch (_) {
        // Ignore errors during test teardown
      }

      try {
        await transport.close();
      } catch (_) {
        // Ignore errors during test teardown
      }
    });

    test('initializes with default and custom options', () {
      // Default options test
      final defaultProtocol = TestProtocol();
      expect(defaultProtocol, isNotNull);

      // Custom options test
      final customProtocol = TestProtocol(
        const ProtocolOptions(enforceStrictCapabilities: true),
      );
      expect(customProtocol, isNotNull);
    });

    test('connects to transport successfully', () async {
      await protocol.connect(transport);
      expect(protocol.transport, equals(transport));
      expect(transport._started, isTrue);
    });

    test('handles connection close', () async {
      final completer = Completer<void>();

      await protocol.connect(transport);
      protocol.onclose = () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      };

      await transport.close();
      await completer.future.timeout(const Duration(seconds: 5));
      expect(completer.isCompleted, isTrue);
      expect(protocol.transport, isNull);
    });

    test('sends outgoing requests and handles responses', () async {
      await protocol.connect(transport);

      // Start a request
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0, // Will be replaced by internal ID
              method: 'test/method',
              params: {'param': 'value'},
            ),
            (json) => TestResult(value: json['value'] as String),
          )
          .timeout(const Duration(seconds: 5));

      // Verify message was sent
      expect(transport.sentMessages.length, equals(1));
      final sentMessage = transport.sentMessages.first;
      expect(sentMessage, isA<JsonRpcRequest>());
      expect((sentMessage as JsonRpcRequest).method, equals('test/method'));
      expect(sentMessage.params?['param'], equals('value'));

      // Simulate response
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentMessage.id,
          result: {'value': 'response-data'},
        ),
      );

      // Verify the response was processed
      final result = await requestFuture;
      expect(result, isA<TestResult>());
      expect(result.value, equals('response-data'));
    });

    test('routes handler notifications for string request IDs', () async {
      await protocol.connect(transport);

      protocol.setRequestHandler<JsonRpcRequest>(
        'test/string-id',
        (request, extra) async {
          await extra.sendNotification(
            const JsonRpcNotification(method: 'test/notification'),
          );
          return TestResult(value: 'ok');
        },
        (id, params, meta) => JsonRpcRequest(
          id: id,
          method: 'test/string-id',
          params: params,
          meta: meta,
        ),
      );

      transport.receiveMessage(
        const JsonRpcRequest(id: 'client-req-1', method: 'test/string-id'),
      );

      await waitForSentMessages(transport, 2);

      expect(transport.sentMessages, hasLength(2));
      expect(transport.sentMessages[0], isA<JsonRpcNotification>());
      expect(transport.relatedRequestIds[0], 'client-req-1');
      expect(transport.sentMessages[1], isA<JsonRpcResponse>());
      expect((transport.sentMessages[1] as JsonRpcResponse).id, 'client-req-1');
    });

    test('routes handler requests for string request IDs', () async {
      await protocol.connect(transport);

      protocol.setRequestHandler<JsonRpcRequest>(
        'test/string-id/request',
        (request, extra) async {
          final nestedResult = await extra.sendRequest<TestResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            (json) => TestResult(value: json['value'] as String),
            const RequestOptions(timeout: Duration(seconds: 1)),
          );
          return TestResult(value: nestedResult.value);
        },
        (id, params, meta) => JsonRpcRequest(
          id: id,
          method: 'test/string-id/request',
          params: params,
          meta: meta,
        ),
      );

      transport.receiveMessage(
        const JsonRpcRequest(
          id: 'client-req-2',
          method: 'test/string-id/request',
        ),
      );

      await waitForSentMessages(transport, 1);

      expect(transport.sentMessages[0], isA<JsonRpcRequest>());
      expect(transport.relatedRequestIds[0], 'client-req-2');

      final nestedRequest = transport.sentMessages[0] as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: nestedRequest.id,
          result: {'value': 'nested-ok'},
        ),
      );

      await waitForSentMessages(transport, 2);

      expect(transport.sentMessages[1], isA<JsonRpcResponse>());
      final response = transport.sentMessages[1] as JsonRpcResponse;
      expect(response.id, 'client-req-2');
      expect(response.result['value'], 'nested-ok');
    });

    test('routes nested cancellation notifications for string request IDs',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      protocol.setRequestHandler<JsonRpcRequest>(
        'test/cancel-nested',
        (request, extra) async {
          final result = await extra
              .sendRequest<TestResult>(
                const JsonRpcRequest(id: 0, method: 'test/nested-cancel'),
                (json) => TestResult(value: json['value'] as String),
                RequestOptions(signal: controller.signal),
              )
              .catchError((_) => TestResult(value: 'cancelled'));
          return result;
        },
        (id, params, meta) => JsonRpcRequest(
          id: id,
          method: 'test/cancel-nested',
          params: params,
          meta: meta,
        ),
      );

      transport.receiveMessage(
        const JsonRpcRequest(id: 'client-req-3', method: 'test/cancel-nested'),
      );

      await waitForSentMessages(transport, 1);
      controller.abort('User cancelled');

      await waitForSentMessages(transport, 2);
      final cancellationIndex = transport.sentMessages.indexWhere(
        (message) =>
            message is JsonRpcNotification &&
            message.method == 'notifications/cancelled',
      );

      expect(cancellationIndex, isNot(-1));
      expect(transport.relatedRequestIds[cancellationIndex], 'client-req-3');
    });

    test('dispatches generated integer progress tokens', () async {
      await protocol.connect(transport);

      final progressUpdates = <Progress>[];
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(
              onprogress: progressUpdates.add,
              timeout: const Duration(seconds: 1),
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(1));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      final progressToken = sentRequest.meta?['progressToken'];
      expect(progressToken, isA<int>());

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: ProgressNotification(
            progressToken: progressToken,
            progress: 25,
          ),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(progressUpdates, hasLength(1));
      expect(progressUpdates.single.progress, 25);

      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'value': 'response-data'},
        ),
      );

      final result = await requestFuture;
      expect(result.value, 'response-data');
    });

    test('dispatches string progress tokens from request metadata', () async {
      await protocol.connect(transport);

      final progressUpdates = <Progress>[];
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'progress-token-1'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(
              onprogress: progressUpdates.add,
              timeout: const Duration(seconds: 1),
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(1));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      expect(sentRequest.meta?['progressToken'], 'progress-token-1');

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'progress-token-1',
            progress: 50,
            total: 100,
            message: 'halfway',
          ),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(progressUpdates, hasLength(1));
      expect(progressUpdates.single.progress, 50);
      expect(progressUpdates.single.total, 100);
      expect(progressUpdates.single.message, 'halfway');

      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'value': 'response-data'},
        ),
      );

      final result = await requestFuture;
      expect(result.value, 'response-data');
    });

    test('custom integer progress tokens survive unrelated request cleanup',
        () async {
      await protocol.connect(transport);

      final unrelatedRequestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            (json) => TestResult(value: json['value'] as String),
          )
          .timeout(const Duration(seconds: 5));

      final progressUpdates = <Progress>[];
      final progressRequestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 0},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: progressUpdates.add),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(2));
      final unrelatedRequest = transport.sentMessages[0] as JsonRpcRequest;
      final progressRequest = transport.sentMessages[1] as JsonRpcRequest;
      expect(unrelatedRequest.id, 0);
      expect(progressRequest.id, 1);
      expect(progressRequest.meta?['progressToken'], 0);

      transport.receiveMessage(
        JsonRpcResponse(
          id: unrelatedRequest.id,
          result: {'value': 'unrelated'},
        ),
      );
      expect((await unrelatedRequestFuture).value, 'unrelated');

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 0,
            progress: 75,
          ),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(progressUpdates, hasLength(1));
      expect(progressUpdates.single.progress, 75);

      transport.receiveMessage(
        JsonRpcResponse(
          id: progressRequest.id,
          result: {'value': 'with-progress'},
        ),
      );
      expect((await progressRequestFuture).value, 'with-progress');
    });

    test('rejects invalid request progress tokens when progress handler is set',
        () async {
      await protocol.connect(transport);

      await expectLater(
        protocol.request<TestResult>(
          const JsonRpcRequest(
            id: 0,
            method: 'test/method',
            meta: {'progressToken': false},
          ),
          (json) => TestResult(value: json['value'] as String),
          RequestOptions(onprogress: (_) {}),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(transport.sentMessages, isEmpty);
    });

    test('handles outgoing request errors', () async {
      await protocol.connect(transport);

      // Start a request
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              params: {'param': 'value'},
            ),
            (json) => TestResult(value: json['value'] as String),
          )
          .timeout(const Duration(seconds: 5));

      // Get the sent message ID
      expect(transport.sentMessages.length, equals(1));
      final sentId = (transport.sentMessages.first as JsonRpcRequest).id;

      // Simulate error response
      transport.receiveMessage(
        JsonRpcError(
          id: sentId,
          error: JsonRpcErrorData(
            code: ErrorCode.internalError.value,
            message: 'Test error message',
          ),
        ),
      );

      // Verify the error was processed
      try {
        await requestFuture;
        fail('Expected request to throw an error');
      } catch (e) {
        expect(e, isA<McpError>());
        final mcpError = e as McpError;
        expect(mcpError.code, equals(ErrorCode.internalError.value));
        expect(mcpError.message, equals('Test error message'));
      }
    });

    test('handles timeouts for requests', () async {
      // Use a very short timeout to make the test run quickly
      await protocol.connect(transport);

      final shortTimeout = const Duration(milliseconds: 50);
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(timeout: shortTimeout),
          )
          .timeout(const Duration(seconds: 5));

      try {
        await requestFuture;
        fail('Expected request to time out');
      } catch (e) {
        expect(e, isA<McpError>());
        final mcpError = e as McpError;
        expect(mcpError.code, equals(ErrorCode.requestTimeout.value));
        expect(mcpError.message, contains('timed out'));
      }
    });

    test('handles request cancellation', () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestOptions = RequestOptions(signal: controller.signal);

      // Start a request that can be cancelled
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            (json) => TestResult(value: json['value'] as String),
            requestOptions,
          )
          .timeout(const Duration(seconds: 5));

      // Cancel the request right away
      controller.abort('User cancelled');

      // Verify the cancellation
      try {
        await requestFuture;
        fail('Expected request to be cancelled');
      } catch (e) {
        expect(e.toString(), contains('User cancelled'));

        // Verify a cancellation notification was sent
        expect(transport.sentMessages.length, greaterThan(1));
        bool foundCancellation = false;
        for (final message in transport.sentMessages) {
          if (message is JsonRpcNotification &&
              message.method == 'notifications/cancelled') {
            foundCancellation = true;
            break;
          }
        }
        expect(
          foundCancellation,
          isTrue,
          reason: 'Should have sent a cancellation notification',
        );
      }
    });

    test('enforces strict capabilities when enabled', () {
      // We avoid using a transport connection in this test and just verify the capability check directly
      final strictProtocol = TestProtocol(
        const ProtocolOptions(enforceStrictCapabilities: true),
      );

      // Test that the capability checking works directly
      expect(
        () => strictProtocol.assertCapabilityForMethod('test/method'),
        returnsNormally,
      );
      expect(
        () => strictProtocol.assertCapabilityForMethod('unsupported/method'),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'error code',
            equals(ErrorCode.methodNotFound.value),
          ),
        ),
      );
    });
  });
}
