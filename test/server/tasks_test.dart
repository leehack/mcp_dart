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
  Future<void> send(JsonRpcMessage message) async {
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
              ttl: 3600,
            ),
          ],
        );
      });
      mcpServer.experimental.onCancelTask((taskId, extra) async {});

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

    test('handles cancel task request', () async {
      var cancelledTaskId = '';

      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      mcpServer.experimental.onCancelTask((taskId, extra) async {
        cancelledTaskId = taskId;
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
      expect(response.result, isEmpty); // EmptyResult
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
