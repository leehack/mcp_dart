import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

// Mock Transport
class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];

  @override
  Future<void> send(JsonRpcMessage message) async {
    sentMessages.add(message);
    if (message is JsonRpcRequest) {
      if (message.method == 'elicitation/create') {
        // Echo back success
        onmessage?.call(JsonRpcResponse(
            id: message.id,
            result: ElicitResult(action: 'accept', content: {}).toJson()));
      } else if (message.method == 'sampling/createMessage') {
        onmessage?.call(JsonRpcResponse(
            id: message.id,
            result: CreateMessageResult(
                    model: 'test',
                    role: SamplingMessageRole.assistant,
                    content: SamplingTextContent(text: 'mock response'))
                .toJson()));
      }
    }
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> close() async {}
  @override
  String? get sessionId => 'mock-session';
}

// Mock TaskStore
class MockTaskStore implements TaskStore {
  final Map<String, Task> _tasks = {};
  final Map<String, CallToolResult> _results = {};
  final _updateControllers = <String, StreamController<void>>{};

  @override
  Future<Task?> getTask(String taskId) async => _tasks[taskId];

  @override
  Future<CallToolResult?> getTaskResult(String taskId) async =>
      _results[taskId];

  @override
  Future<void> updateTaskStatus(String taskId, TaskStatus status,
      [String? message]) async {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = Task(
        taskId: taskId,
        status: status,
        statusMessage: message ?? task.statusMessage,
        createdAt: task.createdAt,
      );
      _notifyUpdate(taskId);
    }
  }

  void addTask(Task task) {
    _tasks[task.taskId] = task;
  }

  void completeTask(String taskId, CallToolResult result) {
    _results[taskId] = result;
    updateTaskStatus(taskId, TaskStatus.completed);
  }

  @override
  Future<void> waitForUpdate(String taskId) {
    // Return a future that completes when update happens
    // For testing, we can just return a delayed future or use a controller
    final controller = _updateControllers.putIfAbsent(
        taskId, () => StreamController<void>.broadcast());
    return controller.stream.first;
  }

  void _notifyUpdate(String taskId) {
    if (_updateControllers.containsKey(taskId)) {
      _updateControllers[taskId]!.add(null);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TaskMessageQueue', () {
    late TaskMessageQueue queue;

    setUp(() {
      queue = TaskMessageQueue();
    });

    tearDown(() {
      queue.dispose();
    });

    test('enqueue and dequeue', () {
      final msg = QueuedMessage(
          type: 'test',
          message: JsonRpcNotification(method: 'test'),
          timestamp: 0);
      queue.enqueue('task1', msg);

      final dequeued = queue.dequeue('task1');
      expect(dequeued, equals(msg));
      expect(queue.dequeue('task1'), isNull);
    });

    test('waitForMessage completes when message enqueued', () async {
      final msg = QueuedMessage(
          type: 'test',
          message: JsonRpcNotification(method: 'test'),
          timestamp: 0);

      final future = queue.waitForMessage('task1');
      queue.enqueue('task1', msg);

      await expectLater(future, completes);
    });

    test('waitForMessage completes immediately if queue not empty', () async {
      final msg = QueuedMessage(
          type: 'test',
          message: JsonRpcNotification(method: 'test'),
          timestamp: 0);
      queue.enqueue('task1', msg);

      await expectLater(queue.waitForMessage('task1'), completes);
    });
  });

  group('TaskSession', () {
    late McpServer server;
    late MockTransport transport;
    late TaskSession session;
    late MockTaskStore store;
    late TaskMessageQueue queue;

    setUp(() async {
      server = McpServer(Implementation(name: 'test', version: '1.0'));
      transport = MockTransport();
      await server.connect(transport); // Helper to connect

      store = MockTaskStore();
      queue = TaskMessageQueue();
      store.addTask(
          Task(taskId: 'task1', status: TaskStatus.working, createdAt: 'now'));

      session = TaskSession(server, 'task1', store, queue);
    });

    test('elicit enqueues request and waits', () async {
      final future = session.elicit('message', {'type': 'string'});

      // Allow async code to run
      await Future.delayed(Duration.zero);

      // Check queue
      final msg = queue.dequeue('task1');
      expect(msg, isNotNull);
      expect(msg!.type, 'request');
      expect(msg.resolver, isNotNull);

      // Check status update
      final task = await store.getTask('task1');
      expect(task?.status, TaskStatus.inputRequired);

      // Resolve
      msg.resolver!
          .complete(const ElicitResult(action: 'accept', content: {}).toJson());

      await expectLater(future, completes);

      // Check status update back
      final taskAfter = await store.getTask('task1');
      expect(taskAfter?.status, TaskStatus.working);
    });

    test('createMessage enqueues request and waits', () async {
      final future = session.createMessage([], 100);

      // Allow async code to run
      await Future.delayed(Duration.zero);

      final msg = queue.dequeue('task1');
      expect(msg, isNotNull);
      expect(msg!.type, 'request');

      msg.resolver!.complete(CreateMessageResult(
              model: 'test',
              role: SamplingMessageRole.assistant,
              content: SamplingTextContent(text: 'response'))
          .toJson());

      await expectLater(future, completes);
    });
  });

  group('TaskResultHandler', () {
    late McpServer server;
    late MockTransport transport;
    late MockTaskStore store;
    late TaskMessageQueue queue;
    late TaskResultHandler handler;

    setUp(() async {
      server = McpServer(Implementation(name: 'test', version: '1.0'));
      transport = MockTransport();
      await server.connect(transport);

      store = MockTaskStore();
      queue = TaskMessageQueue();
      handler = TaskResultHandler(store, queue, server);
    });

    tearDown(() {
      handler.dispose();
      queue.dispose();
    });

    test('handle waits for task completion and returns result', () async {
      store.addTask(
          Task(taskId: 'task1', status: TaskStatus.working, createdAt: 'now'));

      final future = handler.handle('task1');

      // Verify it's waiting
      await Future.delayed(Duration(milliseconds: 10));

      // Complete task
      store.completeTask('task1',
          CallToolResult.fromContent(content: [TextContent(text: 'Done')]));

      final result = await future;
      expect(result.content.first, isA<TextContent>());
      expect((result.content.first as TextContent).text, 'Done');
    });

    test('handle processes queued requests (elicit)', () async {
      store.addTask(
          Task(taskId: 'task1', status: TaskStatus.working, createdAt: 'now'));

      final future = handler.handle('task1');

      // Enqueue a request (simulating task asking for input)
      final completer = Completer<Map<String, dynamic>>();
      queue.enqueue(
          'task1',
          QueuedMessage(
              type: 'request',
              message: JsonRpcRequest(
                  id: 1,
                  method: 'elicitation/create',
                  params:
                      ElicitRequestParams(message: 'Hi', requestedSchema: {})
                          .toJson()),
              timestamp: 0,
              resolver: completer,
              originalRequestId: 1));

      // The handler should pick this up, call server.request (which goes to mock transport),
      // and complete the resolver.

      final response = await completer.future;
      expect(response, isNotNull);
      expect(ElicitResult.fromJson(response).action, 'accept');

      // Complete task to finish handler
      store.completeTask('task1',
          CallToolResult.fromContent(content: [TextContent(text: 'Done')]));
      await future;
    });

    test('handle throws if task not found', () async {
      expect(() => handler.handle('non-existent'), throwsA(isA<McpError>()));
    });
  });
}
