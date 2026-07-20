import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class MockTransport extends Transport
    implements ToolParameterHeaderAwareTransport {
  final List<JsonRpcMessage> sentMessages = [];
  ServerCapabilities serverCapabilities;
  List<Tool> advertisedTools;
  final List<List<Tool>>? advertisedToolPages;
  ToolParameterHeaderMappings toolParameterHeaderMappings = const {};
  int headerMismatchResponsesRemaining;
  int toolCallRequestCount = 0;
  int toolListRequestCount = 0;
  final bool useStatelessDiscovery;
  final bool repeatToolListCursor;
  final String initializationProtocolVersion;

  MockTransport({
    this.serverCapabilities = const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
    List<Tool>? advertisedTools,
    this.advertisedToolPages,
    this.headerMismatchResponsesRemaining = 0,
    this.useStatelessDiscovery = false,
    this.repeatToolListCursor = false,
    this.initializationProtocolVersion = latestInitializationProtocolVersion,
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
      if (useStatelessDiscovery) {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: DiscoverResult(
              supportedVersions: const [previewProtocolVersion],
              capabilities: serverCapabilities,
              serverInfo:
                  const Implementation(name: 'MockServer', version: '1.0.0'),
              ttlMs: 0,
              cacheScope: CacheScope.private,
            ).toJson(),
          ),
        );
        return;
      }
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
            protocolVersion: initializationProtocolVersion,
            capabilities: serverCapabilities,
            serverInfo:
                const Implementation(name: 'MockServer', version: '1.0.0'),
          ).toJson(),
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.toolsList) {
      toolListRequestCount += 1;
      final cursor = message.params?['cursor'];
      final pageIndex = cursor == null ? 0 : int.parse(cursor as String);
      final pages = advertisedToolPages;
      final tools = pages == null ? advertisedTools : pages[pageIndex];
      final nextCursor = repeatToolListCursor
          ? cursor as String? ?? '0'
          : pages != null && pageIndex + 1 < pages.length
              ? '${pageIndex + 1}'
              : null;
      _respond(
        JsonRpcResponse(
          id: message.id,
          result: {
            if (useStatelessDiscovery) 'resultType': resultTypeComplete,
            ...ListToolsResult(
              tools: tools,
              nextCursor: nextCursor,
              ttlMs: useStatelessDiscovery ? 0 : null,
              cacheScope: useStatelessDiscovery ? CacheScope.private : null,
            ).toJson(),
          },
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.toolsCall) {
      toolCallRequestCount += 1;
      if (headerMismatchResponsesRemaining > 0) {
        headerMismatchResponsesRemaining -= 1;
        _respond(
          JsonRpcError(
            id: message.id,
            error: const JsonRpcErrorData(
              code: -32020,
              message: 'Header mismatch',
            ),
          ),
        );
        return;
      }
      final name = message.params?['name'];
      if (name == 'validated_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(
              CallToolResult.fromStructuredContent({'result': 'success'}),
            ),
          ),
        );
      } else if (name == 'array_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(
              CallToolResult.fromStructuredArray(['alpha', 'beta']),
            ),
          ),
        );
      } else if (name == 'broken_array_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(
              CallToolResult.fromStructuredArray(['alpha', 1]),
            ),
          ),
        );
      } else if (name == 'advanced_broken_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(
              CallToolResult.fromStructuredArray([1, 'extra']),
            ),
          ),
        );
      } else if (name == 'missing_null_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(const CallToolResult(content: [])),
          ),
        );
      } else if (name == 'explicit_null_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(CallToolResult.fromStructuredNull()),
          ),
        );
      } else if (name == 'broken_tool') {
        // Returns data that violates the schema (missing 'result')
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(
              CallToolResult.fromStructuredContent({'wrong': 'field'}),
            ),
          ),
        );
      } else if (name == 'header_retry_tool') {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(const CallToolResult(content: [])),
          ),
        );
      } else {
        _respond(
          JsonRpcResponse(
            id: message.id,
            result: _toolResultJson(const CallToolResult(content: [])),
          ),
        );
      }
    }
  }

  Map<String, dynamic> _toolResultJson(CallToolResult result) => {
        if (useStatelessDiscovery) 'resultType': resultTypeComplete,
        ...result.toJson(),
      };

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
      Tool(
        name: 'advanced_broken_tool',
        inputSchema: const ToolInputSchema(),
        outputSchema: JsonSchema.fromJson({
          'type': 'array',
          'prefixItems': [
            {'type': 'integer'},
          ],
          'items': false,
        }),
      ),
      Tool(
        name: 'missing_null_tool',
        inputSchema: const ToolInputSchema(),
        outputSchema: JsonSchema.nullValue(),
      ),
      Tool(
        name: 'explicit_null_tool',
        inputSchema: const ToolInputSchema(),
        outputSchema: JsonSchema.nullValue(),
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
          Tool.fromJson({
            'name': 'items_header',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'values': {
                  'type': 'array',
                  'items': {
                    'type': 'string',
                    'x-mcp-header': 'Item',
                  },
                },
              },
            },
          }),
          Tool.fromJson({
            'name': 'composition_header',
            'inputSchema': {
              'type': 'object',
              'allOf': [
                {
                  'properties': {
                    'region': {
                      'type': 'string',
                      'x-mcp-header': 'Region',
                    },
                  },
                },
              ],
            },
          }),
          Tool.fromJson({
            'name': 'definition_header',
            'inputSchema': {
              'type': 'object',
              r'$defs': {
                'region': {
                  'type': 'string',
                  'x-mcp-header': 'Region',
                },
              },
            },
          }),
        ],
      );

      await client.connect(transport);
      final result = await client.listTools();

      expect(result.tools.map((tool) => tool.name), [
        'valid_headers',
      ]);
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
        hasLength(9),
      );
    });

    test('callTool refreshes tools/list once after HeaderMismatch', () async {
      transport = MockTransport(
        headerMismatchResponsesRemaining: 1,
        useStatelessDiscovery: true,
        advertisedTools: [
          Tool(
            name: 'header_retry_tool',
            inputSchema: JsonSchema.object(
              properties: {
                'region': JsonSchema.string(mcpHeader: 'Region'),
              },
            ),
          ),
        ],
      );

      await client.connect(transport);
      final result = await client.callTool(
        const CallToolRequest(
          name: 'header_retry_tool',
          arguments: {'region': 'us-east1'},
        ),
      );

      expect(result.content, isEmpty);
      expect(transport.toolCallRequestCount, 2);
      expect(transport.toolListRequestCount, 1);
      expect(transport.toolParameterHeaderMappings, {
        'header_retry_tool': {'region': 'Region'},
      });
    });

    test('callTool finds paginated tool metadata after HeaderMismatch',
        () async {
      transport = MockTransport(
        headerMismatchResponsesRemaining: 1,
        useStatelessDiscovery: true,
        advertisedToolPages: [
          [
            Tool(
              name: 'first_page_tool',
              inputSchema: JsonSchema.object(
                properties: {
                  'tenant': JsonSchema.string(mcpHeader: 'Tenant'),
                },
              ),
            ),
          ],
          [
            Tool(
              name: 'header_retry_tool',
              inputSchema: JsonSchema.object(
                properties: {
                  'region': JsonSchema.string(mcpHeader: 'Region'),
                },
              ),
            ),
          ],
        ],
      );

      await client.connect(transport);
      final result = await client.callTool(
        const CallToolRequest(
          name: 'header_retry_tool',
          arguments: {'region': 'us-east1'},
        ),
      );

      expect(result.content, isEmpty);
      expect(transport.toolCallRequestCount, 2);
      expect(transport.toolListRequestCount, 2);
      expect(transport.toolParameterHeaderMappings, {
        'first_page_tool': {'tenant': 'Tenant'},
        'header_retry_tool': {'region': 'Region'},
      });
    });

    test('listTools retains validation metadata across pagination', () async {
      transport = MockTransport(
        advertisedToolPages: [
          [
            ...MockTransport._defaultAdvertisedTools(),
            Tool(
              name: 'first_page_header',
              inputSchema: JsonSchema.object(
                properties: {
                  'tenant': JsonSchema.string(mcpHeader: 'Tenant'),
                },
              ),
            ),
          ],
          [
            Tool(
              name: 'second_page_header',
              inputSchema: JsonSchema.object(
                properties: {
                  'region': JsonSchema.string(mcpHeader: 'Region'),
                },
              ),
            ),
          ],
        ],
      );

      await client.connect(transport);
      final firstPage = await client.listTools();
      await client.listTools(
        params: ListToolsRequest(cursor: firstPage.nextCursor),
      );

      expect(transport.toolParameterHeaderMappings, {
        'first_page_header': {'tenant': 'Tenant'},
        'second_page_header': {'region': 'Region'},
      });
      await expectLater(
        client.callTool(const CallToolRequest(name: 'broken_tool')),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('Structured content does not match'),
          ),
        ),
      );
      await expectLater(
        client.callTool(const CallToolRequest(name: 'task_required_tool')),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('requires task-based execution'),
          ),
        ),
      );

      await client.listTools();
      expect(transport.toolParameterHeaderMappings, {
        'first_page_header': {'tenant': 'Tenant'},
      });
    });

    test('close clears negotiated and tool metadata before reconnect',
        () async {
      transport = MockTransport(
        useStatelessDiscovery: true,
        advertisedTools: [
          ...MockTransport._defaultAdvertisedTools(),
          Tool(
            name: 'header_tool',
            inputSchema: JsonSchema.object(
              properties: {
                'tenant': JsonSchema.string(mcpHeader: 'Tenant'),
              },
            ),
          ),
        ],
      );
      await client.connect(transport);
      await client.listTools();

      expect(client.getServerCapabilities(), isNotNull);
      expect(client.getServerVersion(), isNotNull);
      expect(client.getProtocolVersion(), previewProtocolVersion);
      expect(transport.toolParameterHeaderMappings, {
        'header_tool': {'tenant': 'Tenant'},
      });
      await expectLater(
        client.callTool(const CallToolRequest(name: 'task_required_tool')),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('requires task-based execution'),
          ),
        ),
      );

      await client.close();

      expect(client.getServerCapabilities(), isNull);
      expect(client.getServerVersion(), isNull);
      expect(client.getInstructions(), isNull);
      expect(client.getProtocolVersion(), isNull);

      final secondTransport = MockTransport(advertisedTools: const []);
      await client.connect(secondTransport);

      final taskResult = await client.callTool(
        const CallToolRequest(name: 'task_required_tool'),
      );
      final schemaResult = await client.callTool(
        const CallToolRequest(name: 'broken_tool'),
      );

      expect(taskResult.content, isEmpty);
      expect(
        schemaResult.structuredContentJson?.toJson(),
        {'wrong': 'field'},
      );
      expect(secondTransport.toolCallRequestCount, 2);
      expect(secondTransport.toolParameterHeaderMappings, isEmpty);

      await client.close();
    });

    test('HeaderMismatch refresh stops on a repeated pagination cursor',
        () async {
      transport = MockTransport(
        headerMismatchResponsesRemaining: 2,
        useStatelessDiscovery: true,
        repeatToolListCursor: true,
        advertisedToolPages: [
          [
            const Tool(
              name: 'unrelated_tool',
              inputSchema: ToolInputSchema(),
            ),
          ],
        ],
      );

      await client.connect(transport);
      await expectLater(
        client.callTool(
          const CallToolRequest(name: 'header_retry_tool'),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.headerMismatch.value,
          ),
        ),
      );

      expect(transport.toolListRequestCount, 2);
      expect(transport.toolCallRequestCount, 2);
    });

    test('callTool does not loop on repeated HeaderMismatch', () async {
      transport = MockTransport(
        headerMismatchResponsesRemaining: 2,
        useStatelessDiscovery: true,
        advertisedTools: [
          const Tool(
            name: 'header_retry_tool',
            inputSchema: ToolInputSchema(),
          ),
        ],
      );

      await client.connect(transport);

      await expectLater(
        client.callTool(
          const CallToolRequest(name: 'header_retry_tool'),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.headerMismatch.value,
          ),
        ),
      );
      expect(transport.toolCallRequestCount, 2);
      expect(transport.toolListRequestCount, 1);
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
      transport = MockTransport(useStatelessDiscovery: true);
      await client.connect(transport);
      await client.listTools();

      final result = await client.callTool(
        const CallToolRequest(name: 'array_tool'),
      );

      expect(result.structuredContentJson?.toJson(), equals(['alpha', 'beta']));
    });

    test('legacy protocols ignore non-object output schemas and values',
        () async {
      for (final protocolVersion in const [
        latestInitializationProtocolVersion,
        '2025-06-18',
      ]) {
        transport = MockTransport(
          initializationProtocolVersion: protocolVersion,
        );
        client = Client(
          const Implementation(name: 'TestClient', version: '1.0.0'),
          options: McpClientOptions(protocolVersion: protocolVersion),
        );

        await client.connect(transport);
        await client.listTools();

        final result = await client.callTool(
          const CallToolRequest(name: 'broken_array_tool'),
        );

        expect(result.hasStructuredContent, isFalse, reason: protocolVersion);
        expect(result.structuredContentJson, isNull, reason: protocolVersion);
        expect(
          (result.content.single as TextContent).text,
          '["alpha",1]',
          reason: protocolVersion,
        );

        await client.close();
      }
    });

    test('output schema rejects omitted structured content', () async {
      transport = MockTransport(useStatelessDiscovery: true);
      await client.connect(transport);
      await client.listTools();

      expect(
        () => client.callTool(
          const CallToolRequest(name: 'missing_null_tool'),
        ),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.invalidParams.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Structured content does not match'),
              ),
        ),
      );
    });

    test('output schema accepts explicit structured null', () async {
      transport = MockTransport(useStatelessDiscovery: true);
      await client.connect(transport);
      await client.listTools();

      final result = await client.callTool(
        const CallToolRequest(name: 'explicit_null_tool'),
      );

      expect(result.hasStructuredContent, isTrue);
      expect(result.structuredContentJson?.toJson(), isNull);
    });

    test('throws when non-object tool output validation fails', () async {
      transport = MockTransport(useStatelessDiscovery: true);
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

    test('enforces 2020-12 keywords in advertised output schemas', () async {
      transport = MockTransport(useStatelessDiscovery: true);
      await client.connect(transport);
      await client.listTools();

      expect(
        () => client.callTool(
          const CallToolRequest(name: 'advanced_broken_tool'),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
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
          isA<McpError>()
              .having(
                (e) => e.code,
                'code',
                ErrorCode.methodNotFound.value,
              )
              .having(
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
          isA<McpError>()
              .having(
                (e) => e.code,
                'code',
                ErrorCode.methodNotFound.value,
              )
              .having(
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
