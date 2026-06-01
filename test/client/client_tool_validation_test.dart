import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class MockTransport extends Transport
    implements ToolParameterHeaderAwareTransport {
  final List<JsonRpcMessage> sentMessages = [];
  ServerCapabilities serverCapabilities;
  List<Tool> advertisedTools;
  ToolParameterHeaderMappings toolParameterHeaderMappings = const {};

  MockTransport({
    this.serverCapabilities = const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
    List<Tool>? advertisedTools,
  }) : advertisedTools = advertisedTools ?? _defaultAdvertisedTools();

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcRequest && message.method == Method.serverDiscover) {
      _respond(
        JsonRpcError(
          id: message.id,
          error: const JsonRpcErrorData(
            code: -32601,
            message: 'Method not found',
          ),
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.initialize) {
      _respond(
        JsonRpcResponse(
          id: message.id,
          result: InitializeResult(
            protocolVersion: latestProtocolVersion,
            capabilities: serverCapabilities,
            serverInfo:
                const Implementation(name: 'MockServer', version: '1.0.0'),
          ).toJson(),
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.toolsList) {
      _respond(
        JsonRpcResponse(
          id: message.id,
          result: ListToolsResult(tools: advertisedTools).toJson(),
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
      } else if (name == 'array_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: CallToolResult.fromStructuredContent(['alpha', 'beta'])
                .toJson(),
          ),
        );
      } else if (name == 'broken_array_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: CallToolResult.fromStructuredContent(['alpha', 1]).toJson(),
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

  @override
  void setToolParameterHeaderMappings(
    ToolParameterHeaderMappings mappings,
  ) {
    toolParameterHeaderMappings = {
      for (final entry in mappings.entries)
        entry.key: Map.unmodifiable(Map<String, String>.from(entry.value)),
    };
  }

  static List<Tool> _defaultAdvertisedTools() {
    return [
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
      Tool(
        name: 'array_tool',
        inputSchema: const ToolInputSchema(),
        outputSchema: JsonSchema.array(items: JsonSchema.string()),
      ),
      Tool(
        name: 'broken_array_tool',
        inputSchema: const ToolInputSchema(),
        outputSchema: JsonSchema.array(items: JsonSchema.string()),
      ),
      const Tool(
        name: 'task_required_tool',
        inputSchema: ToolInputSchema(),
        execution: ToolExecution(taskSupport: 'required'),
      ),
    ];
  }
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

    test('listTools filters invalid x-mcp-header definitions', () async {
      final warnings = <String>[];
      setMcpLogHandler((loggerName, level, message) {
        if (level == LogLevel.warn) {
          warnings.add(message);
        }
      });
      addTearDown(resetMcpLogHandler);

      transport = MockTransport(
        advertisedTools: [
          Tool(
            name: 'valid_headers',
            inputSchema: JsonSchema.object(
              properties: {
                'region': JsonSchema.string(mcpHeader: 'Region'),
                'limit': JsonSchema.integer(mcpHeader: 'Limit'),
                'dryRun': JsonSchema.boolean(mcpHeader: 'Dry-Run'),
                'count': JsonSchema.integer(mcpHeader: 'Count'),
                'auth': JsonSchema.object(
                  properties: {
                    'tenant': JsonSchema.string(mcpHeader: 'Tenant'),
                  },
                ),
              },
            ),
          ),
          Tool(
            name: 'number_header',
            inputSchema: JsonSchema.object(
              properties: {
                'ratio': JsonSchema.number(mcpHeader: 'Ratio'),
              },
            ),
          ),
          Tool(
            name: 'duplicate_headers',
            inputSchema: JsonSchema.object(
              properties: {
                'primary': JsonSchema.string(mcpHeader: 'Region'),
                'secondary': JsonSchema.string(mcpHeader: 'region'),
              },
            ),
          ),
          Tool(
            name: 'empty_header',
            inputSchema: JsonSchema.object(
              properties: {
                'region': JsonSchema.string(mcpHeader: ''),
              },
            ),
          ),
          Tool(
            name: 'separator_header',
            inputSchema: JsonSchema.object(
              properties: {
                'region': JsonSchema.string(mcpHeader: 'Bad/Header'),
              },
            ),
          ),
          Tool.fromJson({
            'name': 'non_string_header',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'region': {
                  'type': 'string',
                  'x-mcp-header': 1,
                },
              },
            },
          }),
          Tool.fromJson({
            'name': 'object_header',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'payload': {
                  'type': 'object',
                  'x-mcp-header': 'Payload',
                },
              },
            },
          }),
        ],
      );

      await client.connect(transport);
      final result = await client.listTools();

      expect(result.tools.map((tool) => tool.name), ['valid_headers']);
      expect(transport.toolParameterHeaderMappings, {
        'valid_headers': {
          'region': 'Region',
          'limit': 'Limit',
          'dryRun': 'Dry-Run',
          'count': 'Count',
          '/auth/tenant': 'Tenant',
        },
      });
      expect(
        warnings.where((message) => message.contains('Rejecting tool')),
        hasLength(6),
      );
    });

    test('validates tool output schema successfully', () async {
      await client.connect(transport);
      await client.listTools();

      final result = await client.callTool(
        const CallToolRequest(name: 'validated_tool'),
      );

      final structured = result.structuredContent as Map<String, dynamic>;
      expect(structured['result'], equals('success'));
    });

    test('validates non-object tool output schemas successfully', () async {
      await client.connect(transport);
      await client.listTools();

      final result = await client.callTool(
        const CallToolRequest(name: 'array_tool'),
      );

      expect(result.structuredContent, equals(['alpha', 'beta']));
    });

    test('throws when non-object tool output validation fails', () async {
      await client.connect(transport);
      await client.listTools();

      expect(
        () => client.callTool(
          const CallToolRequest(name: 'broken_array_tool'),
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
    test('assertTaskCapability requires tools/call task subcapability',
        () async {
      transport = MockTransport(
        serverCapabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          tasks: ServerCapabilitiesTasks(),
        ),
      );
      await client.connect(transport);

      expect(
        () => client.assertTaskCapability(Method.toolsCall),
        throwsA(
          isA<McpError>().having(
            (e) => e.message,
            'message',
            contains('tasks.requests.tools.call'),
          ),
        ),
      );
    });

    test('assertTaskCapability rejects unsupported task-augmented methods',
        () async {
      transport = MockTransport(
        serverCapabilities: const ServerCapabilities(
          tasks: ServerCapabilitiesTasks(),
        ),
      );
      await client.connect(transport);

      expect(
        () => client.assertTaskCapability(Method.completionComplete),
        throwsA(
          isA<McpError>().having(
            (e) => e.message,
            'message',
            contains('tasks.requests.completion/complete'),
          ),
        ),
      );
    });

    test('assertTaskCapability allows declared tools/call task subcapability',
        () async {
      transport = MockTransport(
        serverCapabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          tasks: ServerCapabilitiesTasks(
            requests: ServerCapabilitiesTasksRequests(
              tools: ServerCapabilitiesTasksTools(
                call: ServerCapabilitiesTasksToolsCall(),
              ),
            ),
          ),
        ),
      );
      await client.connect(transport);

      expect(
        () => client.assertTaskCapability(Method.toolsCall),
        returnsNormally,
      );
    });

    test('assertTaskHandlerCapability rejects unsupported task handlers', () {
      client = Client(
        const Implementation(name: 'TestClient', version: '1.0.0'),
        options: const McpClientOptions(
          capabilities: ClientCapabilities(
            tasks: ClientCapabilitiesTasks(),
          ),
        ),
      );

      expect(
        () => client.assertTaskHandlerCapability(Method.rootsList),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('tasks.requests.roots/list'),
          ),
        ),
      );
    });
  });
}
