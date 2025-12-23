import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock transport implementation for testing
class MockTransportForCoverage implements Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool _started = false;
  bool _closed = false;

  @override
  String? get sessionId => 'test-session-id';

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  void receiveMessage(JsonRpcMessage message) {
    if (_closed) return;
    onmessage?.call(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closed) throw StateError('Transport is closed');
    sentMessages.add(message);
  }

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Cannot start closed transport');
    _started = true;
  }

  bool get isStarted => _started;
}

/// Test protocol implementation for coverage
class CoverageTestProtocol extends Protocol {
  CoverageTestProtocol([super.options]);

  @override
  void assertCapabilityForMethod(String method) {
    // Allow all methods
  }

  @override
  void assertNotificationCapability(String method) {
    // Allow all notifications
  }

  @override
  void assertRequestHandlerCapability(String method) {
    // Allow all request handlers
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

/// Result implementation for testing
class CoverageTestResult implements BaseResultData {
  final String value;

  @override
  final Map<String, dynamic>? meta;

  CoverageTestResult({required this.value, this.meta});

  @override
  Map<String, dynamic> toJson() => {'value': value};
}

void main() {
  group('ProtocolOptions Coverage', () {
    test('ProtocolOptions with all fields set', () {
      const options = ProtocolOptions(
        enforceStrictCapabilities: true,
        debouncedNotificationMethods: ['notifications/test'],
        defaultTaskPollInterval: 1000,
        maxTaskQueueSize: 100,
      );

      expect(options.enforceStrictCapabilities, isTrue);
      expect(options.debouncedNotificationMethods, isNotNull);
      expect(options.debouncedNotificationMethods!.length, equals(1));
      expect(options.defaultTaskPollInterval, equals(1000));
      expect(options.maxTaskQueueSize, equals(100));
    });

    test('ProtocolOptions default values', () {
      const options = ProtocolOptions();
      expect(options.enforceStrictCapabilities, isFalse);
      expect(options.debouncedNotificationMethods, isNull);
      expect(options.taskStore, isNull);
      expect(options.taskMessageQueue, isNull);
      expect(options.defaultTaskPollInterval, isNull);
      expect(options.maxTaskQueueSize, isNull);
    });
  });

  group('RequestOptions Coverage', () {
    test('RequestOptions with task creation params', () {
      const taskParams = TaskCreationParams(ttl: 3600);
      const relatedTask = RelatedTaskMetadata(taskId: 'task-123');

      const options = RequestOptions(
        task: taskParams,
        relatedTask: relatedTask,
        timeout: Duration(seconds: 30),
        maxTotalTimeout: Duration(minutes: 5),
        resetTimeoutOnProgress: true,
      );

      expect(options.task, isNotNull);
      expect(options.task!.ttl, equals(3600));
      expect(options.relatedTask, isNotNull);
      expect(options.relatedTask!.taskId, equals('task-123'));
      expect(options.resetTimeoutOnProgress, isTrue);
    });

    test('RequestOptions with abort signal', () {
      final controller = BasicAbortController();

      final options = RequestOptions(
        signal: controller.signal,
      );

      expect(options.signal, isNotNull);
      expect(options.signal!.aborted, isFalse);

      controller.abort('Test abort');
      expect(options.signal!.aborted, isTrue);
    });

    test('RequestOptions with progress callback', () {
      final progressUpdates = <Progress>[];

      final options = RequestOptions(
        onprogress: (progress) => progressUpdates.add(progress),
      );

      options.onprogress!(const Progress(progress: 50, total: 100));
      expect(progressUpdates.length, equals(1));
      expect(progressUpdates[0].progress, equals(50));
    });
  });

  group('RequestHandlerExtra Coverage', () {
    test('RequestHandlerExtra with all fields', () async {
      final controller = BasicAbortController();

      Future<void> sendNotification(
        JsonRpcNotification notification, {
        RelatedTaskMetadata? relatedTask,
      }) async {}

      Future<T> sendRequest<T extends BaseResultData>(
        JsonRpcRequest request,
        T Function(Map<String, dynamic>) resultFactory,
        RequestOptions options,
      ) async {
        return resultFactory({'value': 'test'});
      }

      void closeSSE() {}
      void closeStandaloneSSE() {}

      final extra = RequestHandlerExtra(
        signal: controller.signal,
        sessionId: 'session-abc',
        requestId: 42,
        meta: {'key': 'value'},
        taskId: 'task-xyz',
        taskRequestedTtl: 3600,
        sendNotification: sendNotification,
        sendRequest: sendRequest,
        closeSSEStream: closeSSE,
        closeStandaloneSSEStream: closeStandaloneSSE,
      );

      expect(extra.signal, isNotNull);
      expect(extra.sessionId, equals('session-abc'));
      expect(extra.requestId, equals(42));
      expect(extra.meta, isNotNull);
      expect(extra.meta!['key'], equals('value'));
      expect(extra.taskId, equals('task-xyz'));
      expect(extra.taskRequestedTtl, equals(3600));
      expect(extra.closeSSEStream, isNotNull);
      expect(extra.closeStandaloneSSEStream, isNotNull);
    });

    test('RequestHandlerExtra minimal fields', () async {
      final controller = BasicAbortController();

      final extra = RequestHandlerExtra(
        signal: controller.signal,
        requestId: 1,
        sendNotification: (notification, {relatedTask}) async {},
        sendRequest: <T extends BaseResultData>(
          JsonRpcRequest request,
          T Function(Map<String, dynamic>) resultFactory,
          RequestOptions options,
        ) async {
          return resultFactory({});
        },
      );

      expect(extra.sessionId, isNull);
      expect(extra.meta, isNull);
      expect(extra.authInfo, isNull);
      expect(extra.requestInfo, isNull);
      expect(extra.taskId, isNull);
      expect(extra.taskStore, isNull);
      expect(extra.taskRequestedTtl, isNull);
      expect(extra.closeSSEStream, isNull);
      expect(extra.closeStandaloneSSEStream, isNull);
    });
  });

  group('Protocol Request Handler Coverage', () {
    late CoverageTestProtocol protocol;
    late MockTransportForCoverage transport;

    setUp(() {
      protocol = CoverageTestProtocol();
      transport = MockTransportForCoverage();
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('handles incoming request with registered handler', () async {
      await protocol.connect(transport);

      // Register a custom handler for a known request type
      protocol.setRequestHandler<JsonRpcPingRequest>(
        'ping',
        (request, extra) async {
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcPingRequest(id: id),
      );

      // Simulate receiving a ping request
      transport.receiveMessage(const JsonRpcPingRequest(id: 1));

      // Wait for async handling
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify response was sent
      expect(transport.sentMessages.length, equals(1));
      expect(transport.sentMessages[0], isA<JsonRpcResponse>());
    });

    test('handles incoming request returning error', () async {
      await protocol.connect(transport);

      // Register a handler that throws McpError
      protocol.setRequestHandler<JsonRpcPingRequest>(
        'ping',
        (request, extra) async {
          throw McpError(
            ErrorCode.internalError.value,
            'Test error message',
            {'detail': 'extra data'},
          );
        },
        (id, params, meta) => JsonRpcPingRequest(id: id),
      );

      transport.receiveMessage(const JsonRpcPingRequest(id: 2));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(transport.sentMessages.length, equals(1));
      expect(transport.sentMessages[0], isA<JsonRpcError>());

      final errorResponse = transport.sentMessages[0] as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.internalError.value));
      expect(errorResponse.error.message, equals('Test error message'));
    });

    test('handles request for unregistered method', () async {
      await protocol.connect(transport);

      // Remove the default ping handler to simulate unregistered method
      protocol.removeRequestHandler('ping');

      transport.receiveMessage(const JsonRpcPingRequest(id: 3));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(transport.sentMessages.length, equals(1));
      expect(transport.sentMessages[0], isA<JsonRpcError>());

      final errorResponse = transport.sentMessages[0] as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.methodNotFound.value));
    });
  });

  group('Protocol Notification Handler Coverage', () {
    late CoverageTestProtocol protocol;
    late MockTransportForCoverage transport;

    setUp(() {
      protocol = CoverageTestProtocol();
      transport = MockTransportForCoverage();
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('setNotificationHandler and removeNotificationHandler', () async {
      await protocol.connect(transport);

      var handlerCalled = false;

      protocol.setNotificationHandler<JsonRpcProgressNotification>(
        'custom/notification',
        (notification) async {
          handlerCalled = true;
        },
        (params, meta) => JsonRpcProgressNotification(
          progressParams: ProgressNotificationParams.fromJson(params ?? {}),
        ),
      );

      // Remove the handler
      protocol.removeNotificationHandler('custom/notification');

      // Now the handler should not be called
      expect(handlerCalled, isFalse);
    });
  });

  group('Protocol send notification Coverage', () {
    late CoverageTestProtocol protocol;
    late MockTransportForCoverage transport;

    setUp(() async {
      protocol = CoverageTestProtocol();
      transport = MockTransportForCoverage();
      await protocol.connect(transport);
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('sends notification successfully', () async {
      await protocol.notification(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotificationParams(
            progressToken: 1,
            progress: 50,
            total: 100,
          ),
        ),
      );

      expect(transport.sentMessages.length, equals(1));
      expect(transport.sentMessages[0], isA<JsonRpcNotification>());
    });
  });

  group('DefaultRequestTimeout', () {
    test('defaultRequestTimeout is 60 seconds', () {
      expect(
        defaultRequestTimeout,
        equals(const Duration(milliseconds: 60000)),
      );
    });
  });
}
