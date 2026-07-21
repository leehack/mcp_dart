import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
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
  group('McpServer - Output Validation', () {
    late McpServer mcpServer;
    late MockTransport transport;

    setUp(() {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      transport = MockTransport();
    });

    test('valid output passes validation', () async {
      mcpServer.registerTool(
        'valid_tool',
        outputSchema: JsonObject(
          properties: {
            'result': JsonSchema.string(),
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredContent({'result': 'success'});
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'valid_tool').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      final result = CallToolResult.fromJson(successResponse.result);
      final structured = result.structuredContent as Map<String, dynamic>;
      expect(structured['result'], equals('success'));
    });

    test('non-object output schema validates for MCP 2026 calls', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredArray(['alpha', 'beta']);
        },
      );

      await mcpServer.connect(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'array_tool').toJson(),
        meta: _statelessMeta(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      final result = CallToolResult.fromJson(successResponse.result);
      expect(result.structuredContentJson?.toJson(), equals(['alpha', 'beta']));
    });

    test('non-object output schema validation failures are rejected', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'invalid_array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredArray(['alpha', 1]);
        },
      );

      await mcpServer.connect(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'invalid_array_tool').toJson(),
        meta: _statelessMeta(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.internalError.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'invalid_array_tool' returned structured content that does not match its output schema.",
        ),
      );
    });

    test('MCP 2026 completed task output uses its accepted schema snapshot',
        () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      final registeredTool = mcpServer.registerStatelessTool(
        'task_array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async => const CreateTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'output-task',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:00Z',
            ttlMs: null,
          ),
        ),
      );

      var taskReads = 0;
      mcpServer.server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async {
          taskReads++;
          if (taskReads == 1) {
            return const GetTaskExtensionResult(
              task: TaskExtensionTask(
                taskId: 'output-task',
                status: TaskStatus.working,
                createdAt: '2026-07-28T00:00:00Z',
                lastUpdatedAt: '2026-07-28T00:00:00Z',
                ttlMs: null,
              ),
            );
          }
          return GetTaskExtensionResult(
            task: TaskExtensionTask(
              taskId: 'output-task',
              status: TaskStatus.completed,
              createdAt: '2026-07-28T00:00:00Z',
              lastUpdatedAt: '2026-07-28T00:01:00Z',
              ttlMs: null,
              result: CallToolResult.fromStructuredArray([1]).toJson(),
            ),
          );
        },
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );

      await mcpServer.connect(transport);
      final statelessMeta = _statelessMeta()
        ..[McpMetaKey.clientCapabilities] = const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ).toJson();
      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 'create-output-task',
          params: const CallToolRequest(name: 'task_array_tool').toJson(),
          meta: statelessMeta,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
      expect(taskReads, 1);

      // Updating the registration must not change an already accepted task's
      // output contract or the name used in its diagnostics.
      registeredTool.updateStateless(
        name: 'renamed_task_array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.integer()),
      );
      transport.sentMessages.clear();
      transport.receiveMessage(
        JsonRpcGetTaskRequest(
          id: 'read-output-task',
          getParams: const GetTaskRequest(taskId: 'output-task'),
          meta: _statelessMeta(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        "Tool 'task_array_tool' returned structured content that does not match its output schema.",
      );
    });

    test('MCP 2026 rejects invalid output in an immediately completed task',
        () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'immediate_task_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async => CreateTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'immediate-output-task',
            status: TaskStatus.completed,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:00Z',
            ttlMs: null,
            result: CallToolResult.fromStructuredArray([1]).toJson(),
          ),
        ),
      );
      mcpServer.server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async => const GetTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'immediate-output-task',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:00Z',
            ttlMs: null,
          ),
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );

      await mcpServer.connect(transport);
      final statelessMeta = _statelessMeta()
        ..[McpMetaKey.clientCapabilities] = const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ).toJson();
      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 'create-completed-output-task',
          params: const CallToolRequest(name: 'immediate_task_tool').toJson(),
          meta: statelessMeta,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        "Tool 'immediate_task_tool' returned structured content that does not match its output schema.",
      );
    });

    test('MCP 2026 validates completed task notification output', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      late RequestHandlerExtra toolExtra;
      mcpServer.registerStatelessTool(
        'notified_task_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async {
          toolExtra = extra;
          return const CreateTaskExtensionResult(
            task: TaskExtensionTask(
              taskId: 'notified-output-task',
              status: TaskStatus.working,
              createdAt: '2026-07-28T00:00:00Z',
              lastUpdatedAt: '2026-07-28T00:00:00Z',
              ttlMs: null,
            ),
          );
        },
      );
      mcpServer.server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async => const GetTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'notified-output-task',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:00Z',
            ttlMs: null,
          ),
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );

      await mcpServer.connect(transport);
      final statelessMeta = _statelessMeta()
        ..[McpMetaKey.clientCapabilities] = const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ).toJson();
      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 'create-notified-output-task',
          params: const CallToolRequest(name: 'notified_task_tool').toJson(),
          meta: statelessMeta,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());

      transport.sentMessages.clear();
      await expectLater(
        toolExtra.sendNotification(
          JsonRpcTaskNotification(
            task: TaskExtensionTask(
              taskId: 'notified-output-task',
              status: TaskStatus.completed,
              createdAt: '2026-07-28T00:00:00Z',
              lastUpdatedAt: '2026-07-28T00:01:00Z',
              ttlMs: null,
              result: CallToolResult.fromStructuredArray([1]).toJson(),
            ),
          ),
        ),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.internalError.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains("Tool 'notified_task_tool'"),
              ),
        ),
      );
      expect(transport.sentMessages, isEmpty);
    });

    test('nullable output schema rejects omitted structured content', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'missing_null_tool',
        outputJsonSchema: JsonSchema.nullValue(),
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      await mcpServer.connect(transport);
      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          params: const CallToolRequest(name: 'missing_null_tool').toJson(),
          meta: _statelessMeta(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        "Tool 'missing_null_tool' did not return structuredContent required by its output schema.",
      );
    });

    test('nullable output schema accepts explicit structured null', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'explicit_null_tool',
        outputJsonSchema: JsonSchema.nullValue(),
        callback: (args, extra) async => CallToolResult.fromStructuredNull(),
      );

      await mcpServer.connect(transport);
      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          params: const CallToolRequest(name: 'explicit_null_tool').toJson(),
          meta: _statelessMeta(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.result, contains('structuredContent'));
      expect(response.result['structuredContent'], isNull);
    });

    test('MCP 2026 calls enforce full 2020-12 output schemas', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'advanced_schema_tool',
        outputJsonSchema: JsonSchema.fromJson({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$defs': {
            'name': {'type': 'string', 'minLength': 1},
          },
          'type': 'object',
          'properties': {
            'name': {r'$ref': r'#/$defs/name'},
          },
          'required': ['name'],
          'unevaluatedProperties': false,
        }),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredContent({
            'name': 'Ada',
            'unexpected': true,
          });
        },
      );

      await mcpServer.connect(transport);
      transport.receiveMessage(
        JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
      );
      await Future<void>.delayed(Duration.zero);

      final listResponse = transport.sentMessages.last as JsonRpcResponse;
      final tools = listResponse.result['tools'] as List<dynamic>;
      final outputSchema =
          (tools.single as Map<String, dynamic>)['outputSchema'] as Map;
      expect(outputSchema[r'$defs'], isNotNull);
      expect(outputSchema['unevaluatedProperties'], isFalse);

      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          params: const CallToolRequest(name: 'advanced_schema_tool').toJson(),
          meta: _statelessMeta(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        contains('does not match its output schema'),
      );
    });

    test('stable tools/list omits non-object output schemas', () async {
      mcpServer.registerStatelessTool(
        'array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredArray(['alpha', 'beta']);
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      transport.receiveMessage(const JsonRpcListToolsRequest(id: 2));
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      final tools = successResponse.result['tools'] as List<dynamic>;
      final tool = tools.single as Map<String, dynamic>;
      expect(tool.containsKey('outputSchema'), isFalse);
    });

    test('MCP 2026 tools/list includes non-object output schemas', () async {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      mcpServer.registerStatelessTool(
        'array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredArray(['alpha', 'beta']);
        },
      );

      await mcpServer.connect(transport);

      transport.receiveMessage(
        JsonRpcListToolsRequest(
          id: 2,
          meta: _statelessMeta(),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      final tools = successResponse.result['tools'] as List<dynamic>;
      final tool = tools.single as Map<String, dynamic>;
      expect(tool['outputSchema']['type'], equals('array'));
      expect(tool['outputSchema']['items']['type'], equals('string'));
    });

    test('stable tool calls omit non-object structured content', () async {
      mcpServer.registerStatelessTool(
        'array_tool',
        outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredArray(['alpha', 'beta']);
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'array_tool').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      expect(successResponse.result.containsKey('structuredContent'), isFalse);
      expect(successResponse.result['content'], isA<List<dynamic>>());
    });

    test('invalid output fails validation', () async {
      mcpServer.registerTool(
        'invalid_tool',
        outputSchema: JsonObject(
          properties: {
            'result': JsonSchema.string(),
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          // Missing 'result' property
          return CallToolResult.fromStructuredContent({'wrong': 'value'});
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'invalid_tool').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.internalError.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'invalid_tool' returned structured content that does not match its output schema.",
        ),
      );
    });

    test('invalid output schema is reported as a server contract error',
        () async {
      var handlerInvoked = false;
      mcpServer.registerTool(
        'invalid_output_schema_tool',
        outputSchema: JsonObject.fromJson({
          r'$schema': 'https://example.com/unsupported-schema',
          'type': 'object',
        }),
        callback: (args, extra) async {
          handlerInvoked = true;
          return CallToolResult.fromStructuredContent({});
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          params: const CallToolRequest(
            name: 'invalid_output_schema_tool',
          ).toJson(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        "Tool 'invalid_output_schema_tool' has an invalid or unsupported output schema.",
      );
      expect(handlerInvoked, isFalse);
    });

    test('older protocols retain invalidParams for invalid output', () async {
      mcpServer.registerTool(
        'legacy_invalid_tool',
        outputSchema: JsonObject(
          properties: {'result': JsonSchema.string()},
          required: ['result'],
        ),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredContent({'wrong': 'value'});
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport, protocolVersion: '2025-06-18');

      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          params: const CallToolRequest(name: 'legacy_invalid_tool').toJson(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
    });

    test('older protocols classify invalid output schemas as invalidParams',
        () async {
      var handlerInvoked = false;
      mcpServer.registerTool(
        'legacy_invalid_output_schema_tool',
        outputSchema: JsonObject.fromJson({
          r'$schema': 'https://example.com/unsupported-schema',
          'type': 'object',
        }),
        callback: (args, extra) async {
          handlerInvoked = true;
          return CallToolResult.fromStructuredContent({});
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport, protocolVersion: '2025-06-18');

      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          params: const CallToolRequest(
            name: 'legacy_invalid_output_schema_tool',
          ).toJson(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(
        response.error.message,
        "Tool 'legacy_invalid_output_schema_tool' has an invalid or unsupported output schema.",
      );
      expect(handlerInvoked, isFalse);
    });

    test('invalid type in output fails validation', () async {
      mcpServer.registerTool(
        'invalid_type_tool',
        outputSchema: JsonObject(
          properties: {
            'count': JsonSchema.integer(),
          },
          required: ['count'],
        ),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredContent(
            {'count': 'not_an_integer'},
          );
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'invalid_type_tool').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.internalError.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'invalid_type_tool' returned structured content that does not match its output schema.",
        ),
      );
    });

    test('execution error skips output validation', () async {
      mcpServer.registerTool(
        'error_tool',
        outputSchema: JsonObject(
          properties: {
            'result': JsonSchema.string(),
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          // Return an error result explicitly
          return const CallToolResult(
            content: [TextContent(text: 'Something went wrong')],
            isError: true,
          );
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'error_tool').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      // Should be a success response (protocol level) but with isError=true in result
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      final result = CallToolResult.fromJson(successResponse.result);
      expect(result.isError, isTrue);
      // Message should be the original error, not validation error
      final textContent = result.content.first as TextContent;
      expect(textContent.text, contains('Something went wrong'));
    });

    test('unstructured content fails validation if schema requires properties',
        () async {
      mcpServer.registerTool(
        'unstructured_tool',
        outputSchema: JsonObject(
          properties: {
            'result': JsonSchema.string(),
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          // Returning unstructured content omits structuredContent entirely.
          return const CallToolResult(
            content: [TextContent(text: 'text result')],
          );
        },
      );

      await mcpServer.connect(transport);
      await _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'unstructured_tool').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.internalError.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'unstructured_tool' did not return structuredContent required by its output schema.",
        ),
      );
    });
  });
}

Map<String, dynamic> _statelessMeta() => {
      McpMetaKey.protocolVersion: previewProtocolVersion,
      McpMetaKey.clientInfo:
          const Implementation(name: 'TestClient', version: '1.0.0').toJson(),
      McpMetaKey.clientCapabilities: const ClientCapabilities().toJson(),
    };

Future<void> _sendInit(
  MockTransport transport, {
  String protocolVersion = latestInitializationProtocolVersion,
}) async {
  final initRequest = JsonRpcInitializeRequest(
    id: 1,
    initParams: InitializeRequestParams(
      protocolVersion: protocolVersion,
      capabilities: const ClientCapabilities(),
      clientInfo: const Implementation(name: 'TestClient', version: '1.0.0'),
    ),
  );
  transport.receiveMessage(initRequest);
  await Future<void>.delayed(Duration.zero);
  transport.receiveMessage(const JsonRpcInitializedNotification());
  await Future<void>.delayed(Duration.zero);
}
