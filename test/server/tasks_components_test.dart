import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

// Mock Transport
class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);

    // Simulate generic client response for requests
    if (message is JsonRpcRequest) {
      if (message.method == 'elicitation/create') {
        // Auto-reply for test
        // In real flow, this goes to client, client replies.
        // Here we just intercept.
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

void main() {
  group('InMemoryTaskMessageQueue', () {
    late InMemoryTaskMessageQueue queue;

    setUp(() {
      queue = InMemoryTaskMessageQueue();
    });

    tearDown(() {
      queue.dispose();
    });

    test('enqueue and dequeue', () async {
      final msg = QueuedMessage(
        type: 'test',
        message: const JsonRpcNotification(method: 'test'),
        timestamp: 0,
      );
      await queue.enqueue('task1', msg, null);

      final dequeued = await queue.dequeue('task1');
      expect(dequeued, equals(msg));
      expect(await queue.dequeue('task1'), isNull);
    });

    test('waitForMessage completes when message enqueued', () async {
      final msg = QueuedMessage(
        type: 'test',
        message: const JsonRpcNotification(method: 'test'),
        timestamp: 0,
      );

      final future = queue.waitForMessage('task1');
      await queue.enqueue('task1', msg, null);

      await expectLater(future, completes);
    });

    test('waitForMessage completes immediately if queue not empty', () async {
      final msg = QueuedMessage(
        type: 'test',
        message: const JsonRpcNotification(method: 'test'),
        timestamp: 0,
      );
      await queue.enqueue('task1', msg, null);

      await expectLater(queue.waitForMessage('task1'), completes);
    });
  });

  group('TaskSession', () {
    late McpServer server;
    late MockTransport transport;
    late TaskSession session;
    late InMemoryTaskStore store;
    late InMemoryTaskMessageQueue queue;

    setUp(() async {
      server = McpServer(const Implementation(name: 'test', version: '1.0'));
      transport = MockTransport();
      await server.connect(transport);

      store = InMemoryTaskStore();
      queue = InMemoryTaskMessageQueue();

      final task = await store.createTask(
        const TaskCreationParams(),
        123,
        {'name': 'test_tool'},
        'session1',
      );

      session = TaskSession(server, task.taskId, store, queue);
    });

    test('elicit enqueues request and waits', () async {
      final future = session.elicit('message', {'type': 'string'});

      // Allow async code to run
      await Future.delayed(Duration.zero);

      // Check queue
      final msg = await queue.dequeue(session.taskId);
      expect(msg, isNotNull);
      expect(msg!.type, 'request');
      expect(msg, isA<ServerQueuedMessage>());
      final serverMsg = msg as ServerQueuedMessage;
      expect(serverMsg.resolver, isNotNull);

      // Check status update
      final task = await store.getTask(session.taskId);
      expect(task?.status, TaskStatus.inputRequired);

      // Resolve
      serverMsg.resolver!
          .complete(const ElicitResult(action: 'accept', content: {}).toJson());

      await expectLater(future, completes);

      // Check status update back
      final taskAfter = await store.getTask(session.taskId);
      expect(taskAfter?.status, TaskStatus.working);
    });

    test('createMessage enqueues request and waits', () async {
      final future = session.createMessage([], 100);

      // Allow async code to run
      await Future.delayed(Duration.zero);

      final msg = await queue.dequeue(session.taskId);
      expect(msg, isNotNull);
      expect(msg!.type, 'request');
      final serverMsg = msg as ServerQueuedMessage;

      serverMsg.resolver!.complete(
        const CreateMessageResult(
          model: 'test',
          role: SamplingMessageRole.assistant,
          content: SamplingTextContent(text: 'response'),
        ).toJson(),
      );

      await expectLater(future, completes);
    });
  });

  group('TaskResultHandler', () {
    late McpServer server;
    late MockTransport transport;
    late InMemoryTaskStore store;
    late InMemoryTaskMessageQueue queue;
    late TaskResultHandler handler;

    setUp(() async {
      server = McpServer(const Implementation(name: 'test', version: '1.0'));
      transport = MockTransport();
      await server.connect(transport);

      store = InMemoryTaskStore();
      queue = InMemoryTaskMessageQueue();
      handler = TaskResultHandler(store, queue, server);
    });

    tearDown(() {
      handler.dispose();
      queue.dispose();
      store.dispose();
    });

    test('handle waits for task completion and returns result', () async {
      final task = await store.createTask(
        const TaskCreationParams(),
        123,
        {'name': 'test_tool'},
        'session1',
      );

      final future = handler.handle(task.taskId);

      // Verify it's waiting
      await Future.delayed(const Duration(milliseconds: 10));

      // Complete task
      await store.storeTaskResult(
        task.taskId,
        TaskStatus.completed,
        CallToolResult.fromContent(content: [const TextContent(text: 'Done')]),
      );

      final result = await future;
      expect(result.content.first, isA<TextContent>());
      expect((result.content.first as TextContent).text, 'Done');
    });

    test('handle processes queued requests (elicit)', () async {
      final task = await store.createTask(
        const TaskCreationParams(),
        123,
        {'name': 'test_tool'},
        'session1',
      );

      final future = handler.handle(task.taskId);

      // Enqueue a request (simulating task asking for input)
      final completer = Completer<Map<String, dynamic>>();
      await queue.enqueue(
        task.taskId,
        ServerQueuedMessage(
          type: 'request',
          message: JsonRpcRequest(
            id: 1,
            method: 'elicitation/create',
            params:
                const ElicitRequestParams(message: 'Hi', requestedSchema: {})
                    .toJson(),
          ),
          timestamp: 0,
          resolver: completer,
          originalRequestId: '1',
        ),
        null,
      );

      // Since we need the server to actually handle the request (via experimental.elicitForTask),
      // we need to mock that response.
      // But `elicitForTask` sends a request over transport. `MockTransport` stores it.
      // We need `MockTransport` to reply if we want full loop.
      // Or we can rely on `server.request` logic.
      // `server.request` returns a Future. MockTransport needs to simulate response.
      // But `TaskResultHandler` calls `server.experimental.elicitForTask`.
      // `elicitForTask` calls `server.server.request`.
      // `server.server.request` sends message and waits for response.
      // Our `MockTransport` doesn't automatically reply.
      // So `completer` will wait forever unless we make `MockTransport` reply or mock `elicitForTask`.

      // Let's stub `server.experimental.elicitForTask` if possible? No it's an extension wrapper.
      // We can intercept at transport level.
      // But `MockTransport` needs to know ID to reply to.
      // We can check `sentMessages`.

      // We'll run a loop to check sent messages and reply.
      Future<void> autoReply() async {
        while (!completer.isCompleted) {
          await Future.delayed(const Duration(milliseconds: 10));
          final reqs =
              transport.sentMessages.whereType<JsonRpcRequest>().toList();
          for (final req in reqs) {
            // If it's the elicit request
            if (req.method == 'elicitation/create') {
              // Fake reply coming back from client
              server.server.transport?.onmessage?.call(
                JsonRpcResponse(
                  id: req.id,
                  result: const ElicitResult(action: 'accept', content: {})
                      .toJson(),
                ),
              );
              // Clear it so we don't reply again
              transport.sentMessages.remove(req);
            }
          }
        }
      }

      autoReply();

      final response = await completer.future;
      expect(response, isNotNull);
      expect(ElicitResult.fromJson(response).action, 'accept');

      // Complete task to finish handler
      await store.storeTaskResult(
        task.taskId,
        TaskStatus.completed,
        CallToolResult.fromContent(content: [const TextContent(text: 'Done')]),
      );
      await future;
    });

    test('handle throws if task not found', () async {
      expect(() => handler.handle('non-existent'), throwsA(isA<McpError>()));
    });
  });
}
