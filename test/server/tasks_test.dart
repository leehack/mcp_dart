import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/server/tasks/handler.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
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
    if (message is JsonRpcInitializeRequest) {
      Future<void>.delayed(Duration.zero, () {
        onmessage?.call(const JsonRpcInitializedNotification());
      });
    }
  }
}

class _ResultHandler extends CancelTaskResultHandler {
  var cancelWithResultCalls = 0;

  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async =>
      const CreateTaskResult(
        task: Task(
          taskId: 'task1',
          status: TaskStatus.working,
          createdAt: '2026-05-14T10:00:00Z',
          lastUpdatedAt: '2026-05-14T10:00:00Z',
          ttl: null,
        ),
      );

  @override
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra) async => Task(
        taskId: taskId,
        status: TaskStatus.cancelled,
        createdAt: '2026-05-14T10:00:00Z',
        lastUpdatedAt: '2026-05-14T10:05:00Z',
        ttl: null,
      );

  @override
  Future<Task> cancelTaskWithResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) async {
    cancelWithResultCalls++;
    return getTask(taskId, extra);
  }

  @override
  Future<CallToolResult> getTaskResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) async =>
      const CallToolResult(content: []);
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
      mcpServer.experimental.onCancelTaskWithResult(
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
          protocolVersion: stableProtocolVersion2025_11_25,
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

    test('registerToolTask advertises tasks.requests.tools.call', () {
      mcpServer.experimental.registerToolTask(
        'task_tool',
        inputSchema: const ToolInputSchema(),
        handler: _ResultHandler(),
      );

      final taskCapabilities = mcpServer.server.getCapabilities().tasks;
      expect(taskCapabilities, isNotNull);
      expect(taskCapabilities!.requests?.tools?.call, isNotNull);
    });

    test('registerToolTask duplicate does not mutate capabilities', () {
      mcpServer.registerTool(
        'duplicate_tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      expect(
        () => mcpServer.experimental.registerToolTask(
          'duplicate_tool',
          inputSchema: const ToolInputSchema(),
          handler: _ResultHandler(),
        ),
        throwsArgumentError,
      );
      expect(
        mcpServer.server.getCapabilities().tasks?.requests?.tools?.call,
        isNull,
      );
    });

    test('registerToolTask reuses pre-advertised capability after connect',
        () async {
      final connectedServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
            tasks: ServerCapabilitiesTasks(
              requests: ServerCapabilitiesTasksRequests(
                tools: ServerCapabilitiesTasksTools(
                  call: ServerCapabilitiesTasksToolsCall(),
                ),
              ),
            ),
          ),
        ),
      );
      connectedServer.experimental.registerToolTask(
        'initial_task_tool',
        inputSchema: const ToolInputSchema(),
        handler: _ResultHandler(),
      );
      await connectedServer.connect(transport);

      expect(
        () => connectedServer.experimental.registerToolTask(
          'late_task_tool',
          inputSchema: const ToolInputSchema(),
          handler: _ResultHandler(),
        ),
        returnsNormally,
      );
    });

    test('registerToolTask after connect requires pre-advertised capability',
        () async {
      await mcpServer.connect(transport);

      expect(
        () => mcpServer.experimental.registerToolTask(
          'late_task_tool',
          inputSchema: const ToolInputSchema(),
          handler: _ResultHandler(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('tasks.requests.tools.call'),
              contains('before connect()'),
            ),
          ),
        ),
      );
    });

    test('handles cancel task request with final task result', () async {
      var cancelledTaskId = '';

      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      mcpServer.experimental.onCancelTaskWithResult((taskId, extra) async {
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
          protocolVersion: stableProtocolVersion2025_11_25,
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

    test('legacy onCancelTask returns final task via onGetTask', () async {
      var cancelledTaskId = '';
      Task task = const Task(
        taskId: 'task123',
        status: TaskStatus.working,
        createdAt: '2026-05-14T10:00:00Z',
        lastUpdatedAt: '2026-05-14T10:00:00Z',
        ttl: null,
      );

      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      // ignore: deprecated_member_use_from_same_package
      mcpServer.experimental.onCancelTask((taskId, extra) async {
        cancelledTaskId = taskId;
        task = Task(
          taskId: taskId,
          status: TaskStatus.cancelled,
          statusMessage: 'Task cancelled',
          createdAt: task.createdAt,
          lastUpdatedAt: '2026-05-14T10:05:00Z',
          ttl: task.ttl,
        );
      });
      mcpServer.experimental.onGetTask((taskId, extra) async => task);

      await mcpServer.connect(transport);

      transport.receiveMessage(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: stableProtocolVersion2025_11_25,
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

      expect(cancelledTaskId, 'task123');
      final response = transport.sentMessages
          .whereType<JsonRpcResponse>()
          .firstWhere((r) => r.id == 2);
      expect(response.result['taskId'], 'task123');
      expect(response.result['status'], 'cancelled');
      expect(response.result, containsPair('ttl', null));
    });

    test('rejects cancel task callback results that are not cancelled',
        () async {
      mcpServer.experimental
          .onListTasks((extra) async => const ListTasksResult(tasks: []));
      mcpServer.experimental.onCancelTaskWithResult((taskId, extra) async {
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
          protocolVersion: stableProtocolVersion2025_11_25,
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
      mcpServer.experimental.onCancelTaskWithResult((taskId, extra) async {
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
            protocolVersion: stableProtocolVersion2025_11_25,
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

    test(
        'tasks/result preserves result metadata and adds related task metadata',
        () async {
      mcpServer.experimental.onTaskResult(
        (taskId, extra) async => const CallToolResult(
          content: [TextContent(text: 'Done')],
          meta: {
            'source': 'handler',
            relatedTaskMetadataKey: {'taskId': 'stale-task'},
            legacyRelatedTaskMetadataKey: {'taskId': 'stale-task'},
          },
        ),
      );

      await mcpServer.connect(transport);

      transport.receiveMessage(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: stableProtocolVersion2025_11_25,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 10));

      transport.receiveMessage(
        JsonRpcTaskResultRequest(
          id: 2,
          resultParams: const TaskResultRequestParams(taskId: 'task123'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages
          .whereType<JsonRpcResponse>()
          .firstWhere((r) => r.id == 2);
      final meta = response.result['_meta'] as Map<String, dynamic>;
      expect(meta['source'], 'handler');
      expect(meta[relatedTaskMetadataKey]?['taskId'], 'task123');
      expect(meta[legacyRelatedTaskMetadataKey]?['taskId'], 'task123');
    });

    test('CancelTaskResultHandler legacy method delegates to result method',
        () async {
      final handler = _ResultHandler();

      // ignore: deprecated_member_use_from_same_package
      await handler.cancelTask('task123', null);

      expect(handler.cancelWithResultCalls, 1);
    });

    test('throws error if tasks handlers not registered but requested',
        () async {
      // Do not register tasks handlers

      await mcpServer.connect(transport);

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: stableProtocolVersion2025_11_25,
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
