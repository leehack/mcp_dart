import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock transport for testing McpServer
class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool isStarted = false;
  bool isClosed = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    isClosed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
  }

  @override
  Future<void> start() async {
    isStarted = true;
  }

  /// Simulate receiving a message from the client
  void receiveMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

void main() {
  group('McpServer - Tasks API', () {
    late McpServer mcpServer;
    late MockTransport transport;

    setUp(() {
      mcpServer =
          McpServer(const Implementation(name: 'TestServer', version: '1.0.0'));
      transport = MockTransport();
    });

    test('registers tasks handlers and handles list request', () async {
      var listCallbackInvoked = false;

      mcpServer.experimental.onListTasks((extra) async {
        listCallbackInvoked = true;
        return const ListTasksResult(
          tasks: [
            Task(
              taskId: 'task1',
              status: TaskStatus.working,
              statusMessage: 'Processing...',
              createdAt: '2026-05-14T10:00:00Z',
              lastUpdatedAt: '2026-05-14T10:00:00Z',
              ttl: 3600,
            ),
          ],
        );
      });
      mcpServer.experimental.onCancelTask(
        (taskId, extra) async => Task(
          taskId: taskId,
          status: TaskStatus.cancelled,
          createdAt: '2026-05-14T10:00:00Z',
          lastUpdatedAt: '2026-05-14T10:00:00Z',
          ttl: null,
        ),
      );

      await mcpServer.connect(transport);

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
        ),
      );
      transport.receiveMessage(initRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final listRequest = JsonRpcListTasksRequest(id: 2);
      transport.receiveMessage(listRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(listCallbackInvoked, isTrue);
      final response = transport.sentMessages
          .whereType<JsonRpcResponse>()
          .firstWhere((r) => r.id == 2);
      final result = ListTasksResult.fromJson(response.result);
      expect(result.tasks.length, 1);
      expect(result.tasks.first.taskId, 'task1');
    });

    test('handles cancel task request with final task result', () async {
      var cancelledTaskId = '';

      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      mcpServer.experimental.onCancelTask((taskId, extra) async {
        cancelledTaskId = taskId;
        return Task(
          taskId: taskId,
          status: TaskStatus.cancelled,
          statusMessage: 'Task cancelled',
          createdAt: '2026-05-14T10:00:00Z',
          lastUpdatedAt: '2026-05-14T10:05:00Z',
          ttl: null,
        );
      });

      await mcpServer.connect(transport);

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
        ),
      );
      transport.receiveMessage(initRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final cancelRequest = JsonRpcCancelTaskRequest(
        id: 2,
        cancelParams: const CancelTaskRequestParams(taskId: 'task123'),
      );
      transport.receiveMessage(cancelRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(cancelledTaskId, 'task123');
      final response = transport.sentMessages
          .whereType<JsonRpcResponse>()
          .firstWhere((r) => r.id == 2);
      expect(response.result['taskId'], 'task123');
      expect(response.result['status'], 'cancelled');
      expect(response.result['statusMessage'], 'Task cancelled');
      expect(response.result, containsPair('ttl', null));
      expect(response.result, isNot(contains('pollInterval')));
      expect(response.result['createdAt'], '2026-05-14T10:00:00Z');
      expect(response.result['lastUpdatedAt'], '2026-05-14T10:05:00Z');
    });

    test('rejects cancel task callback results that are not cancelled',
        () async {
      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      mcpServer.experimental.onCancelTask((taskId, extra) async {
        return Task(
          taskId: taskId,
          status: TaskStatus.completed,
          createdAt: '2026-05-14T10:00:00Z',
          lastUpdatedAt: '2026-05-14T10:05:00Z',
          ttl: null,
        );
      });

      await mcpServer.connect(transport);

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
        ),
      );
      transport.receiveMessage(initRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final cancelRequest = JsonRpcCancelTaskRequest(
        id: 2,
        cancelParams: const CancelTaskRequestParams(taskId: 'task123'),
      );
      transport.receiveMessage(cancelRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final errorResponse = transport.sentMessages
          .whereType<JsonRpcError>()
          .firstWhere((r) => r.id == 2);
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(
        errorResponse.error.message,
        contains('must return a cancelled task'),
      );
    });

    test('rejects cancel task callback results with mismatched taskId',
        () async {
      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      mcpServer.experimental.onCancelTask((taskId, extra) async {
        return const Task(
          taskId: 'different-task',
          status: TaskStatus.cancelled,
          createdAt: '2026-05-14T10:00:00Z',
          lastUpdatedAt: '2026-05-14T10:05:00Z',
          ttl: null,
        );
      });

      await mcpServer.connect(transport);

      transport.receiveMessage(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: latestProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 10));

      transport.receiveMessage(
        JsonRpcCancelTaskRequest(
          id: 2,
          cancelParams: const CancelTaskRequestParams(taskId: 'task123'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 10));

      final errorResponse = transport.sentMessages
          .whereType<JsonRpcError>()
          .firstWhere((r) => r.id == 2);
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(errorResponse.error.message, contains('mismatched taskId'));
    });

    test('throws error if tasks handlers not registered but requested',
        () async {
      // Do not register tasks handlers

      await mcpServer.connect(transport);

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
        ),
      );
      transport.receiveMessage(initRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Request list tasks
      final listRequest = JsonRpcListTasksRequest(id: 2);
      transport.receiveMessage(listRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final errorResponse = transport.sentMessages
          .whereType<JsonRpcError>()
          .firstWhere((r) => r.id == 2);
      expect(errorResponse.error.code, equals(ErrorCode.methodNotFound.value));
    });
  });
}
