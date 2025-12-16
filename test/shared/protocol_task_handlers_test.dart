import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock TaskStore for testing protocol task handlers
class MockTaskStore implements TaskStore {
  final Map<String, Task> tasks = {};
  final Map<String, BaseResultData> results = {};

  @override
  Future<Task> createTask(
    TaskCreationParams taskParams,
    RequestId requestId,
    Map<String, dynamic> requestData,
    String? sessionId,
  ) async {
    final taskId = 'task-${tasks.length + 1}';
    final task = Task(
      taskId: taskId,
      status: TaskStatus.working,
    );
    tasks[taskId] = task;
    return task;
  }

  @override
  Future<Task?> getTask(String taskId, [String? sessionId]) async {
    return tasks[taskId];
  }

  @override
  Future<void> storeTaskResult(
    String taskId,
    TaskStatus status,
    BaseResultData result, [
    String? sessionId,
  ]) async {
    results[taskId] = result;
    if (tasks.containsKey(taskId)) {
      tasks[taskId] = Task(taskId: taskId, status: status);
    }
  }

  @override
  Future<BaseResultData> getTaskResult(
    String taskId, [
    String? sessionId,
  ]) async {
    return results[taskId] ?? const EmptyResult();
  }

  @override
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
    String? sessionId,
  ]) async {
    if (tasks.containsKey(taskId)) {
      tasks[taskId] = Task(
        taskId: taskId,
        status: status,
        statusMessage: statusMessage,
      );
    }
  }

  @override
  Future<ListTasksResult> listTasks(String? cursor, [String? sessionId]) async {
    return ListTasksResult(tasks: tasks.values.toList());
  }
}

/// Mock TaskMessageQueue for testing
class MockTaskMessageQueue implements TaskMessageQueue {
  final Map<String, List<QueuedMessage>> queues = {};

  @override
  Future<void> enqueue(
    String taskId,
    QueuedMessage message,
    String? sessionId, [
    int? maxSize,
  ]) async {
    queues.putIfAbsent(taskId, () => []);
    queues[taskId]!.add(message);
  }

  @override
  Future<QueuedMessage?> dequeue(String taskId, [String? sessionId]) async {
    final queue = queues[taskId];
    if (queue == null || queue.isEmpty) return null;
    return queue.removeAt(0);
  }

  @override
  Future<List<QueuedMessage>> dequeueAll(
    String taskId, [
    String? sessionId,
  ]) async {
    final queue = queues.remove(taskId);
    return queue ?? [];
  }
}

/// Mock transport for testing
class TaskTestMockTransport implements Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool _closed = false;

  @override
  String? get sessionId => 'test-session';

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  void receiveMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }

  @override
  Future<void> close() async {
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
  }
}

/// Test protocol implementation with task support
class TaskTestProtocol extends Protocol {
  TaskTestProtocol({TaskStore? taskStore, TaskMessageQueue? taskMessageQueue})
      : super(
          ProtocolOptions(
            taskStore: taskStore,
            taskMessageQueue: taskMessageQueue,
          ),
        );

  @override
  void assertCapabilityForMethod(String method) {
    // Allow all methods for testing
  }

  @override
  void assertNotificationCapability(String method) {
    // Allow all notifications for testing
  }

  @override
  void assertRequestHandlerCapability(String method) {
    // Allow all request handlers
  }

  @override
  void assertTaskCapability(String method) {
    // Allow task capability
  }

  @override
  void assertTaskHandlerCapability(String method) {
    // Allow task handler capability
  }
}

void main() {
  group('Protocol Task Handlers', () {
    late MockTaskStore taskStore;
    late MockTaskMessageQueue messageQueue;
    late TaskTestProtocol protocol;
    late TaskTestMockTransport transport;

    setUp(() {
      taskStore = MockTaskStore();
      messageQueue = MockTaskMessageQueue();
      protocol = TaskTestProtocol(
        taskStore: taskStore,
        taskMessageQueue: messageQueue,
      );
      transport = TaskTestMockTransport();
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('tasks/get handler returns task when found', () async {
      await protocol.connect(transport);

      // Pre-populate a task
      taskStore.tasks['task-1'] = const Task(
        taskId: 'task-1',
        status: TaskStatus.working,
        statusMessage: 'In progress',
      );

      // Simulate tasks/get request
      final request = JsonRpcGetTaskRequest(
        id: 1,
        getParams: const GetTaskRequestParams(taskId: 'task-1'),
      );

      transport.receiveMessage(request);

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify response was sent
      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());

      final jsonResponse = response as JsonRpcResponse;
      expect(jsonResponse.result['taskId'], equals('task-1'));
      expect(jsonResponse.result['status'], equals('working'));
    });

    test('tasks/get handler throws error when task not found', () async {
      await protocol.connect(transport);

      // Request a non-existent task
      final request = JsonRpcGetTaskRequest(
        id: 1,
        getParams: const GetTaskRequestParams(taskId: 'non-existent'),
      );

      transport.receiveMessage(request);

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify error response was sent
      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());

      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
    });

    test('tasks/list handler returns all tasks', () async {
      await protocol.connect(transport);

      // Pre-populate tasks
      taskStore.tasks['task-1'] = const Task(
        taskId: 'task-1',
        status: TaskStatus.working,
      );
      taskStore.tasks['task-2'] = const Task(
        taskId: 'task-2',
        status: TaskStatus.completed,
      );

      // Simulate tasks/list request
      final request = JsonRpcListTasksRequest(id: 2);

      transport.receiveMessage(request);

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify response was sent
      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());

      final jsonResponse = response as JsonRpcResponse;
      final tasks = jsonResponse.result['tasks'] as List;
      expect(tasks.length, equals(2));
    });

    test('tasks/cancel handler cancels working task', () async {
      await protocol.connect(transport);

      // Pre-populate a working task
      taskStore.tasks['task-1'] = const Task(
        taskId: 'task-1',
        status: TaskStatus.working,
      );

      // Simulate tasks/cancel request
      final request = JsonRpcCancelTaskRequest(
        id: 3,
        cancelParams: const CancelTaskRequestParams(taskId: 'task-1'),
      );

      transport.receiveMessage(request);

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify response was sent
      expect(transport.sentMessages.length, greaterThan(0));

      // Verify task was cancelled
      expect(taskStore.tasks['task-1']?.status, equals(TaskStatus.cancelled));
    });

    test('tasks/cancel handler rejects cancellation of completed task',
        () async {
      await protocol.connect(transport);

      // Pre-populate a completed task
      taskStore.tasks['task-1'] = const Task(
        taskId: 'task-1',
        status: TaskStatus.completed,
      );

      // Simulate tasks/cancel request
      final request = JsonRpcCancelTaskRequest(
        id: 4,
        cancelParams: const CancelTaskRequestParams(taskId: 'task-1'),
      );

      transport.receiveMessage(request);

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify error response was sent
      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());

      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(errorResponse.error.message, contains('terminal status'));
    });

    test('tasks/cancel handler clears message queue', () async {
      await protocol.connect(transport);

      // Pre-populate a working task and queue
      taskStore.tasks['task-1'] = const Task(
        taskId: 'task-1',
        status: TaskStatus.working,
      );

      // Add messages to queue
      await messageQueue.enqueue(
        'task-1',
        QueuedMessage(
          type: 'notification',
          message: const JsonRpcNotification(method: 'test', params: {}),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        'test-session',
      );

      expect(messageQueue.queues['task-1']?.length, equals(1));

      // Simulate tasks/cancel request
      final request = JsonRpcCancelTaskRequest(
        id: 5,
        cancelParams: const CancelTaskRequestParams(taskId: 'task-1'),
      );

      transport.receiveMessage(request);

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify queue was cleared
      expect(messageQueue.queues.containsKey('task-1'), isFalse);
    });
  });

  group('Protocol Task Message Queuing', () {
    late MockTaskStore taskStore;
    late MockTaskMessageQueue messageQueue;
    late TaskTestProtocol protocol;
    late TaskTestMockTransport transport;

    setUp(() {
      taskStore = MockTaskStore();
      messageQueue = MockTaskMessageQueue();
      protocol = TaskTestProtocol(
        taskStore: taskStore,
        taskMessageQueue: messageQueue,
      );
      transport = TaskTestMockTransport();
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('notification with relatedTask enqueues to message queue', () async {
      await protocol.connect(transport);

      // Create a task first
      taskStore.tasks['task-1'] = const Task(
        taskId: 'task-1',
        status: TaskStatus.working,
      );

      // Send notification with relatedTask
      await protocol.notification(
        const JsonRpcNotification(
          method: 'notifications/progress',
          params: {'progress': 50, 'total': 100},
        ),
        relatedTask: const RelatedTaskMetadata(taskId: 'task-1'),
      );

      // Verify message was queued instead of sent directly
      expect(messageQueue.queues['task-1']?.length, equals(1));
      expect(messageQueue.queues['task-1']?.first.type, equals('notification'));
    });
  });

  group('Protocol Edge Cases', () {
    late TaskTestMockTransport transport;

    test('handles non-integer response ID gracefully', () async {
      final protocol = TaskTestProtocol();
      transport = TaskTestMockTransport();

      await protocol.connect(transport);

      // Capture errors
      Error? receivedError;
      protocol.onerror = (error) => receivedError = error;

      // Simulate a response with non-integer ID
      transport.receiveMessage(
        const JsonRpcResponse(
          id: 'string-id', // Non-integer ID
          result: {'value': 'test'},
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Should have received an error
      expect(receivedError, isNotNull);
      expect(receivedError, isA<ArgumentError>());

      await protocol.close();
    });
  });
}
