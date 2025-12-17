import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcRequest && message.method == Method.initialize) {
      _respond(
        JsonRpcResponse(
          id: message.id,
          result: const InitializeResult(
            protocolVersion: latestProtocolVersion,
            capabilities: ServerCapabilities(
              tools: ServerCapabilitiesTools(),
            ),
            serverInfo: Implementation(name: 'MockServer', version: '1.0.0'),
          ).toJson(),
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.toolsList) {
      _respond(
        JsonRpcResponse(
          id: message.id,
          result: ListToolsResult(
            tools: [
              Tool(
                name: 'validated_tool',
                inputSchema: JsonSchema.object(properties: {}),
                outputSchema: ToolOutputSchema(
                  properties: {
                    'result': JsonSchema.string(),
                  },
                  required: ['result'],
                ),
              ),
              Tool(
                name: 'broken_tool', // Tool that returns invalid data
                inputSchema: const ToolInputSchema(),
                outputSchema: ToolOutputSchema(
                  properties: {
                    'result': JsonSchema.string(),
                  },
                  required: ['result'],
                ),
              ),
              const Tool(
                name: 'task_required_tool',
                inputSchema: ToolInputSchema(),
                execution: ToolExecution(taskSupport: 'required'),
              ),
            ],
          ).toJson(),
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.toolsCall) {
      final name = message.params?['name'];
      if (name == 'validated_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: CallToolResult.fromStructuredContent({'result': 'success'})
                .toJson(),
          ),
        );
      } else if (name == 'broken_tool') {
        // Returns data that violates the schema (missing 'result')
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: CallToolResult.fromStructuredContent({'wrong': 'field'})
                .toJson(),
          ),
        );
      }
    }
  }

  void _respond(JsonRpcMessage message) {
    scheduleMicrotask(() {
      onmessage?.call(message);
    });
  }

  @override
  Future<void> start() async {}
}

void main() {
  group('Client - Tool Validation', () {
    late Client client;
    late MockTransport transport;

    setUp(() {
      transport = MockTransport();
      client = Client(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
    });

    test('validates tool output schema successfully', () async {
      await client.connect(transport);
      await client.listTools();

      final result = await client.callTool(
        const CallToolRequest(name: 'validated_tool'),
      );

      expect(result.structuredContent?['result'], equals('success'));
    });

    test('throws when tool output validation fails', () async {
      await client.connect(transport);
      await client.listTools();

      expect(
        () => client.callTool(
          const CallToolRequest(name: 'broken_tool'),
        ),
        throwsA(
          isA<McpError>().having(
            (e) => e.message,
            'message',
            contains('Structured content does not match'),
          ),
        ),
      );
    });

    test('throws when calling a task-required tool directly', () async {
      await client.connect(transport);
      await client.listTools();

      expect(
        () => client.callTool(
          const CallToolRequest(name: 'task_required_tool'),
        ),
        throwsA(
          isA<McpError>().having(
            (e) => e.message,
            'message',
            contains('requires task-based execution'),
          ),
        ),
      );
    });
  });
}
