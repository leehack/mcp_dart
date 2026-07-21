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

Future<JsonRpcMessage> _receiveResponse(
  MockTransport transport,
  JsonRpcRequest request,
) async {
  transport.receiveMessage(request);
  for (var attempt = 0; attempt < 100; attempt++) {
    for (final message in transport.sentMessages.reversed) {
      if (message case JsonRpcResponse(:final id) when id == request.id) {
        return message;
      }
      if (message case JsonRpcError(:final id) when id == request.id) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('No response received for request ${request.id}');
}

Future<void> _initializeServer(
  MockTransport transport, {
  String protocolVersion = latestInitializationProtocolVersion,
}) async {
  final response = await _receiveResponse(
    transport,
    JsonRpcInitializeRequest(
      id: 'initialize-$protocolVersion',
      initParams: InitializeRequestParams(
        protocolVersion: protocolVersion,
        capabilities: const ClientCapabilities(),
        clientInfo: const Implementation(
          name: 'TestClient',
          version: '1.0.0',
        ),
      ),
    ),
  );
  expect(response, isA<JsonRpcResponse>());
  await Future<void>.delayed(Duration.zero);
}

class _ResultHandler extends CancelTaskResultHandler {
  var createTaskCalls = 0;
  var cancelWithResultCalls = 0;

  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    createTaskCalls++;
    return const CreateTaskResult(
      task: Task(
        taskId: 'task1',
        status: TaskStatus.working,
        createdAt: '2026-05-14T10:00:00Z',
        lastUpdatedAt: '2026-05-14T10:00:00Z',
        ttl: null,
      ),
    );
  }

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
          protocolVersion: latestInitializationProtocolVersion,
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

    test('registerStatelessToolTask returns a full-schema handle', () {
      final outputSchema = JsonSchema.array(items: JsonSchema.string());
      final registeredTool = mcpServer.experimental.registerStatelessToolTask(
        'stateless_task_tool',
        outputJsonSchema: outputSchema,
        handler: _ResultHandler(),
      );

      expect(registeredTool, isA<RegisteredStatelessTool>());
      expect(registeredTool.outputJsonSchema, same(outputSchema));
      expect(registeredTool.outputSchema, isNull);
      expect(registeredTool.statelessCallback, isNull);
      expect(registeredTool.callback, isA<InterfaceToolCallback>());

      final updatedSchema = JsonSchema.string();
      registeredTool.updateStateless(outputJsonSchema: updatedSchema);
      expect(registeredTool.outputJsonSchema, same(updatedSchema));
    });

    test('invalid task input is rejected before task acceptance', () async {
      final handler = _ResultHandler();
      mcpServer.experimental.registerToolTask(
        'task_tool',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        handler: handler,
      );
      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final response = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'invalid-task-input',
          params: {
            'name': 'task_tool',
            'arguments': {'count': 'many'},
            'task': {'ttl': 60000},
          },
        ),
      );
      expect(response, isA<JsonRpcError>());
      final error = response as JsonRpcError;
      expect(error.error.code, ErrorCode.invalidParams.value);
      expect(
        error.error.message,
        contains("Invalid arguments for tool 'task_tool'"),
      );
      expect(handler.createTaskCalls, 0);
    });

    test('tasks/result validates the originating tool output schema', () async {
      final handler = _ResultHandler();
      mcpServer.experimental.registerToolTask(
        'validated_task_tool',
        outputSchema: ToolOutputSchema(
          properties: {'result': JsonSchema.string()},
          required: ['result'],
        ),
        handler: handler,
      );
      mcpServer.experimental.onTaskResult(
        (taskId, extra) async =>
            CallToolResult.fromStructuredContent({'wrong': 'field'}),
      );

      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final createResponse = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'create-validated-task',
          params: {
            'name': 'validated_task_tool',
            'task': {'ttl': 60000},
          },
        ),
      );
      expect(createResponse, isA<JsonRpcResponse>());
      expect(handler.createTaskCalls, 1);

      final resultResponse = await _receiveResponse(
        transport,
        JsonRpcTaskResultRequest(
          id: 'validated-task-result',
          resultParams: const TaskResultRequest(taskId: 'task1'),
          // Initialization-era metadata must not override the negotiated
          // session version or downgrade modern error semantics.
          meta: {McpMetaKey.protocolVersion: '2025-06-18'},
        ),
      );
      expect(resultResponse, isA<JsonRpcError>());
      final error = resultResponse as JsonRpcError;
      expect(error.error.code, ErrorCode.internalError.value);
      expect(
        error.error.message,
        "Tool 'validated_task_tool' returned structured content that does not match its output schema.",
      );
    });

    test('tasks/result uses the schema captured when the task was accepted',
        () async {
      final handler = _ResultHandler();
      final registeredTool = mcpServer.experimental.registerToolTask(
        'snapshot_task_tool',
        outputSchema: ToolOutputSchema(
          properties: {'result': JsonSchema.string()},
          required: ['result'],
        ),
        handler: handler,
      );
      mcpServer.experimental.onTaskResult(
        (taskId, extra) async =>
            CallToolResult.fromStructuredContent({'result': 'accepted'}),
      );

      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final createResponse = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'create-snapshot-task',
          params: {
            'name': 'snapshot_task_tool',
            'task': {'ttl': 60000},
          },
        ),
      );
      expect(createResponse, isA<JsonRpcResponse>());

      registeredTool.update(
        name: 'renamed_snapshot_task_tool',
        outputSchema: ToolOutputSchema(
          properties: {'count': JsonSchema.integer()},
          required: ['count'],
        ),
      );

      final resultResponse = await _receiveResponse(
        transport,
        JsonRpcTaskResultRequest(
          id: 'snapshot-task-result',
          resultParams: const TaskResultRequest(taskId: 'task1'),
        ),
      );
      expect(resultResponse, isA<JsonRpcResponse>());
      final result = CallToolResult.fromJson(
        (resultResponse as JsonRpcResponse).result,
      );
      expect(result.structuredContent, {'result': 'accepted'});
    });

    test('unexpected transport close clears captured task output schemas',
        () async {
      final oldContractHandler = _ResultHandler();
      final freshTaskHandler = _ResultHandler();
      mcpServer.experimental.registerToolTask(
        'old_contract_task',
        outputSchema: ToolOutputSchema(
          properties: {'result': JsonSchema.string()},
          required: ['result'],
        ),
        handler: oldContractHandler,
      );
      mcpServer.experimental.registerToolTask(
        'fresh_task',
        handler: freshTaskHandler,
      );
      mcpServer.experimental.onTaskResult(
        (taskId, extra) async =>
            CallToolResult.fromStructuredContent({'count': 1}),
      );

      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final firstCreateResponse = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'create-task-before-disconnect',
          params: {
            'name': 'old_contract_task',
            'task': {'ttl': 60000},
          },
        ),
      );
      expect(firstCreateResponse, isA<JsonRpcResponse>());
      expect(oldContractHandler.createTaskCalls, 1);

      // Simulate the transport closing independently of McpServer.close().
      // Both handlers deliberately return task1, so the fresh schema-free task
      // would pick up the previous session's validator if it leaked.
      await transport.close();
      expect(mcpServer.isConnected, isFalse);

      final reconnectedTransport = MockTransport();
      try {
        await mcpServer.connect(reconnectedTransport);
        await _initializeServer(reconnectedTransport);

        final secondCreateResponse = await _receiveResponse(
          reconnectedTransport,
          const JsonRpcCallToolRequest(
            id: 'create-task-after-reconnect',
            params: {
              'name': 'fresh_task',
              'task': {'ttl': 60000},
            },
          ),
        );
        expect(secondCreateResponse, isA<JsonRpcResponse>());
        expect(freshTaskHandler.createTaskCalls, 1);

        final resultResponse = await _receiveResponse(
          reconnectedTransport,
          JsonRpcTaskResultRequest(
            id: 'task-result-after-reconnect',
            resultParams: const TaskResultRequest(taskId: 'task1'),
          ),
        );
        expect(resultResponse, isA<JsonRpcResponse>());
        final result = CallToolResult.fromJson(
          (resultResponse as JsonRpcResponse).result,
        );
        expect(result.structuredContent, {'count': 1});
      } finally {
        await mcpServer.close();
      }
    });

    test('required task mode is checked before input schema', () async {
      final handler = _ResultHandler();
      mcpServer.experimental.registerToolTask(
        'task_tool',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        handler: handler,
      );
      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final response = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'missing-task-mode',
          params: {
            'name': 'task_tool',
            'arguments': {'count': 'many'},
          },
        ),
      );
      expect(response, isA<JsonRpcError>());
      final error = response as JsonRpcError;
      expect(error.error.code, ErrorCode.methodNotFound.value);
      expect(
        error.error.message,
        contains("requires task augmentation (taskSupport: 'required')"),
      );
      expect(handler.createTaskCalls, 0);
    });

    test('forbidden task mode returns methodNotFound', () async {
      mcpServer.experimental.registerToolTask(
        'task_tool',
        inputSchema: const ToolInputSchema(),
        handler: _ResultHandler(),
      );
      var callbackCalled = false;
      mcpServer.registerTool(
        'regular_tool',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        callback: (args, extra) async {
          callbackCalled = true;
          return const CallToolResult(content: []);
        },
      );
      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final response = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'forbidden-task-mode',
          params: {
            'name': 'regular_tool',
            'arguments': {'count': 'many'},
            'task': {'ttl': 60000},
          },
        ),
      );
      expect(response, isA<JsonRpcError>());
      final error = response as JsonRpcError;
      expect(error.error.code, ErrorCode.methodNotFound.value);
      expect(
        error.error.message,
        contains(
          "does not support task augmentation (taskSupport: 'forbidden')",
        ),
      );
      expect(callbackCalled, isFalse);
    });

    test('server without task capability ignores task augmentation', () async {
      var callbackCalled = false;
      mcpServer.registerTool(
        'regular_tool',
        callback: (args, extra) async {
          callbackCalled = true;
          return const CallToolResult(content: []);
        },
      );
      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final response = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'ignored-task-mode',
          params: {
            'name': 'regular_tool',
            'task': {'ttl': 60000},
          },
        ),
      );

      expect(response, isA<JsonRpcResponse>());
      expect(callbackCalled, isTrue);
    });

    test('malformed negotiated task metadata is invalidParams', () async {
      final handler = _ResultHandler();
      mcpServer.experimental.registerToolTask(
        'task_tool',
        inputSchema: const ToolInputSchema(),
        handler: handler,
      );
      await mcpServer.connect(transport);
      await _initializeServer(transport);

      final response = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'malformed-task-mode',
          params: {'name': 'task_tool', 'task': 'not-an-object'},
        ),
      );

      expect(response, isA<JsonRpcError>());
      final error = response as JsonRpcError;
      expect(error.error.code, ErrorCode.invalidParams.value);
      expect(error.error.message, contains('Failed to parse task params'));
      expect(handler.createTaskCalls, 0);
    });

    test('older protocols retain forbidden-task invalidParams', () async {
      mcpServer.experimental.registerToolTask(
        'task_tool',
        inputSchema: const ToolInputSchema(),
        handler: _ResultHandler(),
      );
      mcpServer.registerTool(
        'regular_tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      await mcpServer.connect(transport);
      await _initializeServer(transport, protocolVersion: '2025-06-18');

      final response = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'legacy-forbidden-task-mode',
          params: {
            'name': 'regular_tool',
            'task': {'ttl': 60000},
          },
        ),
      );

      expect(response, isA<JsonRpcError>());
      expect(
        (response as JsonRpcError).error.code,
        ErrorCode.invalidParams.value,
      );
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
          protocolVersion: latestInitializationProtocolVersion,
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
            protocolVersion: latestInitializationProtocolVersion,
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
          protocolVersion: latestInitializationProtocolVersion,
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
            protocolVersion: latestInitializationProtocolVersion,
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
            protocolVersion: latestInitializationProtocolVersion,
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
          protocolVersion: latestInitializationProtocolVersion,
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
