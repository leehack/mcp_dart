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
        outputSchema: const ToolOutputSchema(
          properties: {
            'result': {'type': 'string'},
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredContent(
            structuredContent: {'result': 'success'},
          );
        },
      );

      await mcpServer.connect(transport);
      _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        callParams: const CallToolRequestParams(name: 'valid_tool'),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcResponse>());
      final successResponse = response as JsonRpcResponse;
      final result = CallToolResult.fromJson(successResponse.result);
      expect(result.structuredContent['result'], equals('success'));
    });

    test('invalid output fails validation', () async {
      mcpServer.registerTool(
        'invalid_tool',
        outputSchema: const ToolOutputSchema(
          properties: {
            'result': {'type': 'string'},
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          // Missing 'result' property
          return CallToolResult.fromStructuredContent(
            structuredContent: {'wrong': 'value'},
          );
        },
      );

      await mcpServer.connect(transport);
      _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        callParams: const CallToolRequestParams(name: 'invalid_tool'),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(errorResponse.error.message, contains('Output validation error'));
    });

    test('invalid type in output fails validation', () async {
      mcpServer.registerTool(
        'invalid_type_tool',
        outputSchema: const ToolOutputSchema(
          properties: {
            'count': {'type': 'integer'},
          },
          required: ['count'],
        ),
        callback: (args, extra) async {
          return CallToolResult.fromStructuredContent(
            structuredContent: {'count': 'not_an_integer'},
          );
        },
      );

      await mcpServer.connect(transport);
      _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        callParams: const CallToolRequestParams(name: 'invalid_type_tool'),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(errorResponse.error.message, contains('Output validation error'));
    });

    test('execution error skips output validation', () async {
      mcpServer.registerTool(
        'error_tool',
        outputSchema: const ToolOutputSchema(
          properties: {
            'result': {'type': 'string'},
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          // Return an error result explicitly
          return CallToolResult.fromContent(
            content: [const TextContent(text: 'Something went wrong')],
            isError: true,
          );
        },
      );

      await mcpServer.connect(transport);
      _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        callParams: const CallToolRequestParams(name: 'error_tool'),
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
        outputSchema: const ToolOutputSchema(
          properties: {
            'result': {'type': 'string'},
          },
          required: ['result'],
        ),
        callback: (args, extra) async {
          // Returning unstructured content means structuredContent is {}
          return CallToolResult.fromContent(
            content: [const TextContent(text: 'text result')],
          );
        },
      );

      await mcpServer.connect(transport);
      _sendInit(transport);

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        callParams: const CallToolRequestParams(name: 'unstructured_tool'),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
      final errorResponse = response as JsonRpcError;
      expect(errorResponse.error.code, equals(ErrorCode.invalidParams.value));
      expect(errorResponse.error.message, contains('Output validation error'));
    });
  });
}

void _sendInit(MockTransport transport) {
  final initRequest = JsonRpcInitializeRequest(
    id: 1,
    initParams: const InitializeRequestParams(
      protocolVersion: latestProtocolVersion,
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
    ),
  );
  transport.receiveMessage(initRequest);
}
