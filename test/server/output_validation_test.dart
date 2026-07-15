import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
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
      mcpServer.registerTool(
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
      mcpServer.registerTool(
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
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'invalid_array_tool' returned structured content that does not match its output schema.",
        ),
      );
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
      mcpServer.registerTool(
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
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(
        response.error.message,
        contains('does not match its output schema'),
      );
    });

    test('stable tools/list omits non-object output schemas', () async {
      mcpServer.registerTool(
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
      mcpServer.registerTool(
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
      mcpServer.registerTool(
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
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'invalid_tool' returned structured content that does not match its output schema.",
        ),
      );
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
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
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
          // Returning unstructured content means structuredContent is {}
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
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(
        errorResponse.error.message,
        equals(
          "Tool 'unstructured_tool' returned structured content that does not match its output schema.",
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

Future<void> _sendInit(MockTransport transport) async {
  final initRequest = JsonRpcInitializeRequest(
    id: 1,
    initParams: const InitializeRequestParams(
      protocolVersion: latestInitializationProtocolVersion,
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
    ),
  );
  transport.receiveMessage(initRequest);
  await Future<void>.delayed(Duration.zero);
  transport.receiveMessage(const JsonRpcInitializedNotification());
  await Future<void>.delayed(Duration.zero);
}
