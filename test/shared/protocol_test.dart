import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
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

  bool failSends = false;
  Duration? failSendDelay;

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    if (failSends) {
      final delay = failSendDelay;
      if (delay != null) {
        await Future<void>.delayed(delay);
      }
      throw StateError('Transport send failed');
    }
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

class _StubTaskStore implements TaskStore {
  @override
  Future<Task> createTask(
    TaskCreationParams taskParams,
    RequestId requestId,
    Map<String, dynamic> requestData,
    String? sessionId,
  ) async =>
      const Task(
        taskId: 'stub-task',
        status: TaskStatus.working,
        createdAt: '2026-05-16T00:00:00Z',
        lastUpdatedAt: '2026-05-16T00:00:00Z',
        ttl: null,
      );

  @override
  Future<Task?> getTask(String taskId, [String? sessionId]) async => null;

  @override
  Future<BaseResultData> getTaskResult(
    String taskId, [
    String? sessionId,
  ]) async =>
      const EmptyResult();

  @override
  Future<ListTasksResult> listTasks(
    String? cursor, [
    String? sessionId,
  ]) async =>
      const ListTasksResult(tasks: []);

  @override
  Future<void> storeTaskResult(
    String taskId,
    TaskStatus status,
    BaseResultData result, [
    String? sessionId,
  ]) async {}

  @override
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
    String? sessionId,
  ]) async {}
}

class _FailingTaskMessageQueue implements TaskMessageQueue {
  static const Duration _delay = Duration(milliseconds: 20);

  @override
  Future<void> enqueue(
    String taskId,
    QueuedMessage message,
    String? sessionId, [
    int? maxSize,
  ]) async {
    await Future<void>.delayed(_delay);
    throw StateError('Task queue enqueue failed');
  }

  @override
  Future<QueuedMessage?> dequeue(String taskId, [String? sessionId]) async =>
      null;

  @override
  Future<List<QueuedMessage>> dequeueAll(
    String taskId, [
    String? sessionId,
  ]) async =>
      const [];
}

Map<String, dynamic> taskJson(String taskId, TaskStatus status) => {
      'taskId': taskId,
      'status': status.name,
      'ttl': null,
      'createdAt': '2026-05-16T00:00:00Z',
      'lastUpdatedAt': '2026-05-16T00:00:01Z',
    };

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

    test('task options serialize as task-augmented request params', () async {
      await protocol.connect(transport);

      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              params: {'original': 'value'},
              meta: {'progressToken': 'task-shape-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              onprogress: (_) {},
              task: const TaskCreation(ttl: 1234),
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(1));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      expect(sentRequest.params?['original'], 'value');
      expect(sentRequest.params?['task'], {'ttl': 1234});
      expect(sentRequest.meta?['task'], isNull);
      expect(sentRequest.meta?['progressToken'], 'task-shape-token');
      expect(sentRequest.toJson()['params'], {
        'original': 'value',
        'task': {'ttl': 1234},
        '_meta': {'progressToken': 'task-shape-token'},
      });

      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('shape-task', TaskStatus.completed),
          },
        ),
      );
      expect((await requestFuture).task.taskId, 'shape-task');
    });

    test('progress notifications reset timeout for custom tokens', () async {
      await protocol.connect(transport);

      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'reset-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(
              onprogress: (_) {},
              timeout: const Duration(milliseconds: 80),
              resetTimeoutOnProgress: true,
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(1));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;

      await Future<void>.delayed(const Duration(milliseconds: 50));
      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'reset-token',
            progress: 50,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'value': 'response-data'},
        ),
      );

      final result = await requestFuture;
      expect(result.value, 'response-data');
    });

    test('progress notifications keep request alive when reset is enabled',
        () async {
      await protocol.connect(transport);

      final progressUpdates = <Progress>[];
      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'keep-alive-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(
              onprogress: progressUpdates.add,
              timeout: const Duration(milliseconds: 60),
              resetTimeoutOnProgress: true,
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(1));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;

      for (final progress in [25.0, 50.0, 75.0]) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        transport.receiveMessage(
          JsonRpcProgressNotification(
            progressParams: ProgressNotification(
              progressToken: 'keep-alive-token',
              progress: progress,
            ),
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 40));
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'value': 'completed-after-progress'},
        ),
      );

      final result = await requestFuture;
      expect(result.value, 'completed-after-progress');
      expect(
        progressUpdates.map((progress) => progress.progress),
        [25, 50, 75],
      );
    });

    test('progress notifications do not reset timeout when disabled', () async {
      await protocol.connect(transport);

      final requestFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'no-reset-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(
              onprogress: (_) {},
              timeout: const Duration(milliseconds: 80),
              resetTimeoutOnProgress: false,
            ),
          )
          .timeout(const Duration(seconds: 5));

      await Future<void>.delayed(const Duration(milliseconds: 40));
      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'no-reset-token',
            progress: 50,
          ),
        ),
      );

      await expectLater(
        requestFuture,
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.requestTimeout.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('timed out'),
              ),
        ),
      );
    });

    test('maxTotalTimeout aborts despite progress notifications', () async {
      await protocol.connect(transport);

      final progressTimer = Timer.periodic(
        const Duration(milliseconds: 30),
        (_) {
          transport.receiveMessage(
            JsonRpcProgressNotification(
              progressParams: const ProgressNotification(
                progressToken: 'max-total-token',
                progress: 1,
              ),
            ),
          );
        },
      );
      addTearDown(progressTimer.cancel);

      final requestFuture = protocol.request<TestResult>(
        const JsonRpcRequest(
          id: 0,
          method: 'test/method',
          meta: {'progressToken': 'max-total-token'},
        ),
        (json) => TestResult(value: json['value'] as String),
        RequestOptions(
          onprogress: (_) {},
          timeout: const Duration(seconds: 1),
          resetTimeoutOnProgress: false,
          maxTotalTimeout: const Duration(milliseconds: 120),
        ),
      );

      await expectLater(
        requestFuture.timeout(const Duration(milliseconds: 500)),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.requestTimeout.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('timed out'),
              ),
        ),
      );
    });

    test('maxTotalTimeout caps progress-based timeout resets', () async {
      await protocol.connect(transport);

      final progressUpdates = <Progress>[];
      final requestFuture = protocol.request<TestResult>(
        const JsonRpcRequest(
          id: 0,
          method: 'test/method',
          meta: {'progressToken': 'capped-reset-token'},
        ),
        (json) => TestResult(value: json['value'] as String),
        RequestOptions(
          onprogress: progressUpdates.add,
          timeout: const Duration(seconds: 1),
          resetTimeoutOnProgress: true,
          maxTotalTimeout: const Duration(milliseconds: 120),
        ),
      );

      final progressTimer = Timer.periodic(
        const Duration(milliseconds: 30),
        (_) {
          transport.receiveMessage(
            JsonRpcProgressNotification(
              progressParams: const ProgressNotification(
                progressToken: 'capped-reset-token',
                progress: 1,
              ),
            ),
          );
        },
      );
      addTearDown(progressTimer.cancel);

      await expectLater(
        requestFuture.timeout(const Duration(milliseconds: 500)),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.requestTimeout.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('timed out'),
              ),
        ),
      );
      expect(progressUpdates, isNotEmpty);
    });

    test('custom progress token can be reused after timeout cleanup', () async {
      await protocol.connect(transport);

      final firstFuture = protocol.request<TestResult>(
        const JsonRpcRequest(
          id: 0,
          method: 'test/method',
          meta: {'progressToken': 'reusable-after-timeout'},
        ),
        (json) => TestResult(value: json['value'] as String),
        RequestOptions(
          onprogress: (_) {},
          timeout: const Duration(milliseconds: 50),
        ),
      );

      await expectLater(
        firstFuture.timeout(const Duration(seconds: 5)),
        throwsA(isA<McpError>()),
      );

      final secondFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'reusable-after-timeout'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(
              onprogress: (_) {},
              timeout: const Duration(seconds: 1),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequests = transport.sentMessages.whereType<JsonRpcRequest>();
      expect(sentRequests, hasLength(2));
      final secondRequest = sentRequests.last;
      transport.receiveMessage(
        JsonRpcResponse(
          id: secondRequest.id,
          result: {'value': 'reused'},
        ),
      );

      expect((await secondFuture).value, 'reused');
    });

    test('rejects duplicate progress tokens for in-flight requests', () async {
      await protocol.connect(transport);

      final firstFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'shared-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      await expectLater(
        protocol.request<TestResult>(
          const JsonRpcRequest(
            id: 0,
            method: 'test/method',
            meta: {'progressToken': 'shared-token'},
          ),
          (json) => TestResult(value: json['value'] as String),
          RequestOptions(onprogress: (_) {}),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(transport.sentMessages, hasLength(1));
      final firstRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: firstRequest.id,
          result: {'value': 'response-data'},
        ),
      );
      expect((await firstFuture).value, 'response-data');
    });

    test('generated progress tokens avoid active custom integer tokens',
        () async {
      await protocol.connect(transport);

      final customProgressUpdates = <Progress>[];
      final generatedProgressUpdates = <Progress>[];
      final customFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 1},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: customProgressUpdates.add),
          )
          .timeout(const Duration(seconds: 5));
      final generatedFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: generatedProgressUpdates.add),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(2));
      final customRequest = transport.sentMessages[0] as JsonRpcRequest;
      final generatedRequest = transport.sentMessages[1] as JsonRpcRequest;
      expect(customRequest.id, 0);
      expect(customRequest.meta?['progressToken'], 1);
      expect(generatedRequest.id, 1);
      expect(generatedRequest.meta?['progressToken'], 2);

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 1,
            progress: 25,
          ),
        ),
      );
      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 2,
            progress: 50,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(customProgressUpdates.single.progress, 25);
      expect(generatedProgressUpdates.single.progress, 50);

      transport.receiveMessage(
        JsonRpcResponse(
          id: customRequest.id,
          result: {'value': 'custom'},
        ),
      );
      transport.receiveMessage(
        JsonRpcResponse(
          id: generatedRequest.id,
          result: {'value': 'generated'},
        ),
      );
      expect((await customFuture).value, 'custom');
      expect((await generatedFuture).value, 'generated');
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

    test('keeps task-augmented progress tokens until terminal task status',
        () async {
      await protocol.connect(transport);

      final progressUpdates = <Progress>[];
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'task-progress-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              onprogress: progressUpdates.add,
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.sentMessages, hasLength(1));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('task-progress-1', TaskStatus.working),
          },
        ),
      );

      final createResult = await requestFuture;
      expect(createResult.task.taskId, 'task-progress-1');

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'task-progress-token',
            progress: 60,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(progressUpdates, hasLength(1));
      expect(progressUpdates.single.progress, 60);

      transport.receiveMessage(
        JsonRpcTaskStatusNotification(
          statusParams: TaskStatusNotification.fromJson(
            taskJson('task-progress-1', TaskStatus.completed),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'task-progress-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-terminal'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-terminal');
    });

    test('cleans preserved task progress when transport closes', () async {
      await protocol.connect(transport);

      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'close-cleanup-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'task': taskJson('close-cleanup-task', TaskStatus.working)},
        ),
      );
      expect((await requestFuture).task.taskId, 'close-cleanup-task');

      await protocol.close();
      final nextTransport = MockTransport();
      await protocol.connect(nextTransport);

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'close-cleanup-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = nextTransport.sentMessages.single as JsonRpcRequest;
      nextTransport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-close'},
        ),
      );

      expect((await reuseFuture).value, 'reused-after-close');
    });

    test(
        'cleans task progress when terminal status arrives before awaiting task',
        () async {
      await protocol.connect(transport);

      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'fast-terminal-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('fast-terminal-task', TaskStatus.working),
          },
        ),
      );
      transport.receiveMessage(
        JsonRpcTaskStatusNotification(
          statusParams: TaskStatusNotification.fromJson(
            taskJson('fast-terminal-task', TaskStatus.completed),
          ),
        ),
      );

      expect((await requestFuture).task.taskId, 'fast-terminal-task');

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'fast-terminal-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-fast-terminal'},
        ),
      );

      expect((await reuseFuture).value, 'reused-after-fast-terminal');
    });

    test('does not let unrelated early terminal status poison later task',
        () async {
      await protocol.connect(transport);

      final firstFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            CreateTaskResult.fromJson,
            const RequestOptions(task: TaskCreation()),
          )
          .timeout(const Duration(seconds: 5));

      final firstRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcTaskStatusNotification(
          statusParams: TaskStatusNotification.fromJson(
            taskJson('unrelated-terminal-task', TaskStatus.completed),
          ),
        ),
      );
      transport.receiveMessage(
        JsonRpcResponse(
          id: firstRequest.id,
          result: {'task': taskJson('first-task', TaskStatus.working)},
        ),
      );
      expect((await firstFuture).task.taskId, 'first-task');

      final progressUpdates = <Progress>[];
      final secondFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'poison-check-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              onprogress: progressUpdates.add,
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final secondRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: secondRequest.id,
          result: {
            'task': taskJson('unrelated-terminal-task', TaskStatus.working),
          },
        ),
      );
      expect((await secondFuture).task.taskId, 'unrelated-terminal-task');

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'poison-check-token',
            progress: 40,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(progressUpdates.single.progress, 40);
    });

    test('prunes unrelated terminal status after concurrent tasks identify',
        () async {
      await protocol.connect(transport);

      final firstFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            CreateTaskResult.fromJson,
            const RequestOptions(task: TaskCreation()),
          )
          .timeout(const Duration(seconds: 5));
      final secondFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            CreateTaskResult.fromJson,
            const RequestOptions(task: TaskCreation()),
          )
          .timeout(const Duration(seconds: 5));

      final firstRequest = transport.sentMessages[0] as JsonRpcRequest;
      final secondRequest = transport.sentMessages[1] as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcTaskStatusNotification(
          statusParams: TaskStatusNotification.fromJson(
            taskJson('concurrent-unrelated-task', TaskStatus.completed),
          ),
        ),
      );
      transport.receiveMessage(
        JsonRpcResponse(
          id: firstRequest.id,
          result: {
            'task': taskJson('concurrent-first-task', TaskStatus.working),
          },
        ),
      );
      transport.receiveMessage(
        JsonRpcResponse(
          id: secondRequest.id,
          result: {
            'task': taskJson('concurrent-second-task', TaskStatus.working),
          },
        ),
      );
      expect((await firstFuture).task.taskId, 'concurrent-first-task');
      expect((await secondFuture).task.taskId, 'concurrent-second-task');

      final progressUpdates = <Progress>[];
      final thirdFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'concurrent-poison-check-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              onprogress: progressUpdates.add,
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));
      final thirdRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: thirdRequest.id,
          result: {
            'task': taskJson('concurrent-unrelated-task', TaskStatus.working),
          },
        ),
      );
      expect((await thirdFuture).task.taskId, 'concurrent-unrelated-task');

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'concurrent-poison-check-token',
            progress: 30,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(progressUpdates.single.progress, 30);
    });

    test('aborting task after response but before awaiting sends tasks/cancel',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'fast-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('fast-cancel-task', TaskStatus.working),
          },
        ),
      );
      controller.abort('User cancelled task');

      await expectLater(
        requestFuture,
        throwsA(equals('User cancelled task')),
      );
      await waitForSentMessages(transport, 2);

      final cancelRequest =
          transport.sentMessages.last as JsonRpcCancelTaskRequest;
      expect(cancelRequest.method, Method.tasksCancel);
      expect(cancelRequest.cancelParams.taskId, 'fast-cancel-task');

      await expectLater(
        protocol.request<TestResult>(
          const JsonRpcRequest(
            id: 0,
            method: 'test/method',
            meta: {'progressToken': 'fast-cancel-token'},
          ),
          (json) => TestResult(value: json['value'] as String),
          RequestOptions(onprogress: (_) {}),
        ),
        throwsA(isA<ArgumentError>()),
      );

      transport.receiveMessage(
        JsonRpcResponse(
          id: cancelRequest.id,
          result: taskJson('fast-cancel-task', TaskStatus.cancelled),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'fast-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-cancelled'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-cancelled');
    });

    test(
        'aborting task before creation waits for task id and sends tasks/cancel',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-create-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      controller.abort('User cancelled before task id');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(transport.sentMessages, hasLength(1));
      expect(
        transport.sentMessages.whereType<JsonRpcNotification>().where(
              (message) => message.method == Method.notificationsCancelled,
            ),
        isEmpty,
      );

      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('pre-create-cancel-task', TaskStatus.working),
          },
        ),
      );

      await expectLater(
        requestFuture,
        throwsA(equals('User cancelled before task id')),
      );
      await waitForSentMessages(transport, 2);

      final cancelRequest =
          transport.sentMessages.last as JsonRpcCancelTaskRequest;
      expect(cancelRequest.method, Method.tasksCancel);
      expect(cancelRequest.cancelParams.taskId, 'pre-create-cancel-task');

      transport.receiveMessage(
        JsonRpcResponse(
          id: cancelRequest.id,
          result: taskJson('pre-create-cancel-task', TaskStatus.cancelled),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-create-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-cancel-result'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-cancel-result');
    });

    test('pre-task-id abort preserves cancellation reason over peer error',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-error-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      final errorExpectation = expectLater(
        requestFuture,
        throwsA(equals('pre-error user abort')),
      );
      controller.abort('pre-error user abort');
      transport.receiveMessage(
        JsonRpcError(
          id: sentRequest.id,
          error: JsonRpcErrorData(
            code: ErrorCode.internalError.value,
            message: 'Peer failed after abort',
          ),
        ),
      );

      await errorExpectation;
      expect(transport.sentMessages.length, 1);

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/reuse',
              meta: {'progressToken': 'pre-error-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-peer-error'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-peer-error');
    });

    test(
        'pre-task-id abort distinguishes caller timeout-shaped reason from timeout',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final callerReason = McpError(
        ErrorCode.requestTimeout.value,
        'caller supplied timeout-shaped abort',
      );
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'caller-timeout-shaped-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final errorExpectation = expectLater(
        requestFuture,
        throwsA(same(callerReason)),
      );
      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      controller.abort(callerReason);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('caller-timeout-shaped-task', TaskStatus.working),
          },
        ),
      );

      await waitForSentMessages(transport, 2);
      final cancelRequest = transport.sentMessages.last as JsonRpcRequest;
      expect(cancelRequest.method, 'tasks/cancel');
      expect(cancelRequest.params?['taskId'], 'caller-timeout-shaped-task');
      await errorExpectation;
    });

    test(
        'pre-task-id abort preserves cancellation reason over malformed result',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-malformed-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      controller.abort('pre-malformed user abort');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'unexpected': 'payload'},
        ),
      );

      await expectLater(
        requestFuture,
        throwsA(equals('pre-malformed user abort')),
      );

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/reuse',
              meta: {'progressToken': 'pre-malformed-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-malformed-result'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-malformed-result');
    });

    test('pre-task-id abort preserves cancellation reason over send failure',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      transport
        ..failSends = true
        ..failSendDelay = const Duration(milliseconds: 20);
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-send-failure-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      controller.abort('pre-send user abort');

      await expectLater(requestFuture, throwsA(equals('pre-send user abort')));
      transport
        ..failSends = false
        ..failSendDelay = null;

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/reuse',
              meta: {'progressToken': 'pre-send-failure-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-send-request-failure'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-send-request-failure');
    });

    test(
        'pre-task-id abort preserves cancellation reason over related enqueue failure',
        () async {
      protocol = TestProtocol(
        ProtocolOptions(
          taskStore: _StubTaskStore(),
          taskMessageQueue: _FailingTaskMessageQueue(),
        ),
      );
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-enqueue-failure-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
              relatedTask: const RelatedTaskMetadata(taskId: 'parent-task'),
            ),
          )
          .timeout(const Duration(seconds: 5));

      controller.abort('pre-enqueue user abort');

      await expectLater(
        requestFuture,
        throwsA(equals('pre-enqueue user abort')),
      );

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/reuse',
              meta: {'progressToken': 'pre-enqueue-failure-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-enqueue-failure'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-enqueue-failure');
    });

    test(
        'task creation timeout fails when task id never arrives and cleans state',
        () async {
      await protocol.connect(transport);

      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'task-create-timeout-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              timeout: const Duration(milliseconds: 5),
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      await expectLater(
        requestFuture,
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.requestTimeout.value,
          ),
        ),
      );

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'task-create-timeout-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-task-create-timeout'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-task-create-timeout');
    });

    test('pre-task-id abort preserves first cancellation reason across timeout',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'pre-timeout-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              timeout: const Duration(milliseconds: 5),
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      controller.abort('first user abort');

      await expectLater(requestFuture, throwsA(equals('first user abort')));
      expect(transport.sentMessages, hasLength(1));

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/reuse',
              meta: {'progressToken': 'pre-timeout-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));

      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-pre-timeout-cancel'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-pre-timeout-cancel');
    });

    test('aborted signal response race preserves caller cancellation reason',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      controller.abort('race user abort');
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('abort-race-task', TaskStatus.working),
          },
        ),
      );

      await expectLater(requestFuture, throwsA(equals('race user abort')));
      await waitForSentMessages(transport, 2);
      final cancelRequest =
          transport.sentMessages.last as JsonRpcCancelTaskRequest;
      expect(cancelRequest.cancelParams.taskId, 'abort-race-task');
    });

    test('aborting before terminal task creation rejects without tasks/cancel',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'terminal-pre-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      controller.abort('terminal user abort');
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('terminal-pre-cancel-task', TaskStatus.completed),
          },
        ),
      );

      await expectLater(requestFuture, throwsA(equals('terminal user abort')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transport.sentMessages, hasLength(1));

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'terminal-pre-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-terminal-pre-cancel'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-terminal-pre-cancel');
    });

    test(
        'aborting task-augmented request after task creation sends tasks/cancel',
        () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(id: 0, method: 'test/method'),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('task-cancel-1', TaskStatus.working),
          },
        ),
      );
      expect((await requestFuture).task.taskId, 'task-cancel-1');

      controller.abort('User cancelled task');
      await waitForSentMessages(transport, 2);

      final cancellationMessages = transport.sentMessages.skip(1).toList();
      expect(
        cancellationMessages.whereType<JsonRpcNotification>().where(
              (message) => message.method == Method.notificationsCancelled,
            ),
        isEmpty,
      );
      final cancelRequest =
          cancellationMessages.single as JsonRpcCancelTaskRequest;
      expect(cancelRequest.method, Method.tasksCancel);
      expect(cancelRequest.cancelParams.taskId, 'task-cancel-1');
    });

    test('reports task cancellation response errors', () async {
      await protocol.connect(transport);
      final errors = <Error>[];
      protocol.onerror = errors.add;

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'cancel-error-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'task': taskJson('cancel-error-task', TaskStatus.working)},
        ),
      );
      expect((await requestFuture).task.taskId, 'cancel-error-task');

      controller.abort('User cancelled task');
      await waitForSentMessages(transport, 2);
      final cancelRequest =
          transport.sentMessages.last as JsonRpcCancelTaskRequest;
      transport.receiveMessage(
        JsonRpcError(
          id: cancelRequest.id,
          error: JsonRpcErrorData(
            code: ErrorCode.invalidParams.value,
            message: 'Cancellation rejected',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(errors, hasLength(1));
      expect(errors.single, isA<McpError>());
      expect((errors.single as McpError).message, 'Cancellation rejected');

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'cancel-error-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-cancel-error'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-cancel-error');
    });

    test('reports malformed task cancellation responses', () async {
      await protocol.connect(transport);
      final errors = <Error>[];
      protocol.onerror = errors.add;

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'malformed-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('malformed-cancel-task', TaskStatus.working),
          },
        ),
      );
      expect((await requestFuture).task.taskId, 'malformed-cancel-task');

      controller.abort('User cancelled task');
      await waitForSentMessages(transport, 2);
      final cancelRequest =
          transport.sentMessages.last as JsonRpcCancelTaskRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: cancelRequest.id,
          result: {'unexpected': 'payload'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(
        errors.single.toString(),
        contains('Failed to parse task cancellation result'),
      );

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'malformed-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-malformed'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-malformed');
    });

    test('reports mismatched task cancellation responses and cleans state',
        () async {
      await protocol.connect(transport);
      final errors = <Error>[];
      protocol.onerror = errors.add;

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'mismatched-cancel-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {
            'task': taskJson('mismatched-cancel-task', TaskStatus.working),
          },
        ),
      );
      expect((await requestFuture).task.taskId, 'mismatched-cancel-task');

      controller.abort('User cancelled task');
      await waitForSentMessages(transport, 2);
      final cancelRequest =
          transport.sentMessages.last as JsonRpcCancelTaskRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: cancelRequest.id,
          result: taskJson('wrong-cancel-task', TaskStatus.cancelled),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(
        errors.single.toString(),
        contains('Task cancellation response taskId mismatch'),
      );

      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'mismatched-cancel-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-mismatch'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-mismatch');
    });

    test('reports task cancellation send failures', () async {
      await protocol.connect(transport);
      final errors = <Error>[];
      protocol.onerror = errors.add;

      final controller = BasicAbortController();
      final requestFuture = protocol
          .request<CreateTaskResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'send-failure-token'},
            ),
            CreateTaskResult.fromJson,
            RequestOptions(
              signal: controller.signal,
              onprogress: (_) {},
              task: const TaskCreation(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      final sentRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: sentRequest.id,
          result: {'task': taskJson('send-failure-task', TaskStatus.working)},
        ),
      );
      expect((await requestFuture).task.taskId, 'send-failure-task');

      transport.failSends = true;
      controller.abort('User cancelled task');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(
        errors.single.toString(),
        contains('Failed to send task cancellation for task send-failure-task'),
      );

      transport.failSends = false;
      final reuseFuture = protocol
          .request<TestResult>(
            const JsonRpcRequest(
              id: 0,
              method: 'test/method',
              meta: {'progressToken': 'send-failure-token'},
            ),
            (json) => TestResult(value: json['value'] as String),
            RequestOptions(onprogress: (_) {}),
          )
          .timeout(const Duration(seconds: 5));
      final reuseRequest = transport.sentMessages.last as JsonRpcRequest;
      transport.receiveMessage(
        JsonRpcResponse(
          id: reuseRequest.id,
          result: {'value': 'reused-after-send-failure'},
        ),
      );
      expect((await reuseFuture).value, 'reused-after-send-failure');
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
