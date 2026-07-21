import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock transport for McpServer tests
class McpServerTestTransport
    implements Transport, ToolParameterHeaderAwareTransport {
  final String initializationProtocolVersion;
  final bool initializeOnStart;
  final List<JsonRpcMessage> sentMessages = [];
  final List<ToolParameterHeaderMappings> toolParameterHeaderMappings = [];
  bool _closed = false;

  McpServerTestTransport({
    this.initializationProtocolVersion = latestInitializationProtocolVersion,
    this.initializeOnStart = true,
  });

  @override
  String? get sessionId => 'test-session';

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  void receiveMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }

  @override
  Future<void> close() async {
    _closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closed) throw StateError('Transport is closed');
    sentMessages.add(message);
  }

  @override
  void setToolParameterHeaderMappings(
    ToolParameterHeaderMappings mappings,
  ) {
    toolParameterHeaderMappings.add(mappings);
  }

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Cannot start closed transport');
    if (!initializeOnStart) return;
    onmessage?.call(
      JsonRpcInitializeRequest(
        id: 0,
        initParams: InitializeRequest(
          protocolVersion: initializationProtocolVersion,
          capabilities: const ClientCapabilities(),
          clientInfo:
              const Implementation(name: 'test-client', version: '1.0.0'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    onmessage?.call(const JsonRpcInitializedNotification());
    await Future<void>.delayed(Duration.zero);
  }
}

Future<JsonRpcMessage> _receiveResponse(
  McpServerTestTransport transport,
  JsonRpcRequest request,
) async {
  final sentCount = transport.sentMessages.length;
  transport.receiveMessage(request);
  for (var attempt = 0; attempt < 100; attempt++) {
    for (var index = transport.sentMessages.length - 1;
        index >= sentCount;
        index--) {
      final message = transport.sentMessages[index];
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

Map<String, dynamic> _statelessMeta() => buildProtocolRequestMeta(
      protocolVersion: previewProtocolVersion,
      clientInfo: const Implementation(name: 'test-client', version: '1.0.0'),
      clientCapabilities: const ClientCapabilities(),
    );

bool _containsMcpHeader(Object? value) {
  if (value is Map) {
    return value.containsKey('x-mcp-header') ||
        value.values.any(_containsMcpHeader);
  }
  if (value is Iterable) {
    return value.any(_containsMcpHeader);
  }
  return false;
}

void main() {
  group('McpServer Tool Registration', () {
    late McpServer server;
    late McpServerTestTransport transport;

    setUp(() {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      transport = McpServerTestTransport();
    });

    tearDown(() async {
      await server.close();
    });

    test('registerTool creates a tool that can be listed', () async {
      server.registerTool(
        'test-tool',
        description: 'A test tool',
        inputSchema: ToolInputSchema.fromJson({
          'properties': {
            'input': {'type': 'string'},
          },
          'required': ['input'],
        }),
        callback: (args, extra) async {
          return CallToolResult(
            content: [TextContent(text: 'Result: ${args['input']}')],
          );
        },
      );

      await server.connect(transport);

      // Request tool list
      final request = const JsonRpcListToolsRequest(id: 1);
      transport.receiveMessage(request);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      expect(tools.length, equals(1));
      expect(tools.first['name'], equals('test-tool'));
    });

    test('legacy tool schema shims preserve boolean subschemas', () async {
      server.tool(
        'legacy-boolean-schema-tool',
        inputSchemaProperties: {
          'allowed': true,
          'denied': false,
          'named': {'type': 'string'},
        },
        outputSchemaProperties: {
          'allowed': true,
          'denied': false,
        },
        callback: ({args, extra}) async => const CallToolResult(content: []),
      );

      await server.connect(transport);

      transport.receiveMessage(const JsonRpcListToolsRequest(id: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      final tool = tools.single as Map;
      final inputSchema = tool['inputSchema'] as Map;
      final outputSchema = tool['outputSchema'] as Map;

      expect(inputSchema['properties'], {
        'allowed': true,
        'denied': false,
        'named': {'type': 'string'},
      });
      expect(outputSchema['properties'], {
        'allowed': true,
        'denied': false,
      });
    });

    test('connect syncs tool parameter header mappings to transports',
        () async {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerTool(
        'header-tool',
        inputSchema: const ToolInputSchema(
          properties: {
            'dryRun': JsonBoolean(mcpHeader: 'Dry-Run'),
            'region': JsonString(mcpHeader: 'Region'),
            'count': JsonInteger(mcpHeader: 'Count'),
            'auth': JsonObject(
              properties: {
                'tenant': JsonString(mcpHeader: 'Tenant'),
              },
            ),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      transport = McpServerTestTransport(initializeOnStart: false);
      await server.connect(transport);

      expect(transport.toolParameterHeaderMappings, isNotEmpty);
      expect(
        transport.toolParameterHeaderMappings.last,
        equals(
          const {
            'header-tool': {
              'dryRun': 'Dry-Run',
              'region': 'Region',
              'count': 'Count',
              '/auth/tenant': 'Tenant',
            },
          },
        ),
      );

      transport.receiveMessage(
        JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      final tool = tools.single as Map;
      final inputSchema = tool['inputSchema'] as Map;
      final properties = inputSchema['properties'] as Map;
      final authProperties = (properties['auth'] as Map)['properties'] as Map;
      expect((properties['region'] as Map)['x-mcp-header'], 'Region');
      expect((properties['count'] as Map)['x-mcp-header'], 'Count');
      expect((authProperties['tenant'] as Map)['x-mcp-header'], 'Tenant');
    });

    test('tool updates refresh parameter header mappings on transports',
        () async {
      final registeredTool = server.registerTool(
        'header-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      await server.connect(transport);
      transport.toolParameterHeaderMappings.clear();

      registeredTool.update(
        inputSchema: const ToolInputSchema(
          properties: {
            'dryRun': JsonBoolean(mcpHeader: 'Dry-Run'),
          },
        ),
      );

      expect(transport.toolParameterHeaderMappings, isNotEmpty);
      expect(
        transport.toolParameterHeaderMappings.last,
        equals(
          const {
            'header-tool': {'dryRun': 'Dry-Run'},
          },
        ),
      );

      registeredTool.disable();

      expect(transport.toolParameterHeaderMappings.last, isEmpty);
    });

    test('invalid tool parameter header metadata is not synced', () async {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerTool(
        'non-string-header-tool',
        inputSchema: ToolInputSchema(
          properties: {
            'value': JsonSchema.fromJson(
              {'type': 'string', 'x-mcp-header': 1},
            ),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      server.registerTool(
        'invalid-header-tool',
        inputSchema: const ToolInputSchema(
          properties: {
            'value': JsonString(mcpHeader: 'Bad:Header'),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      server.registerTool(
        'separator-header-tool',
        inputSchema: const ToolInputSchema(
          properties: {
            'value': JsonString(mcpHeader: 'Bad/Header'),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      server.registerTool(
        'duplicate-header-tool',
        inputSchema: const ToolInputSchema(
          properties: {
            'primary': JsonString(mcpHeader: 'Region'),
            'secondary': JsonString(mcpHeader: 'region'),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      server.registerTool(
        'non-primitive-header-tool',
        inputSchema: ToolInputSchema(
          properties: {
            'value': JsonSchema.fromJson(
              {'type': 'object', 'x-mcp-header': 'Value'},
            ),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      server.registerTool(
        'number-header-tool',
        inputSchema: const ToolInputSchema(
          properties: {
            'value': JsonNumber(mcpHeader: 'Value'),
          },
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      transport = McpServerTestTransport(initializeOnStart: false);
      await server.connect(transport);

      expect(transport.toolParameterHeaderMappings, isNotEmpty);
      expect(transport.toolParameterHeaderMappings.last, isEmpty);

      transport.receiveMessage(
        JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final message = transport.sentMessages.last;
      if (message is JsonRpcError) {
        fail(
          'tools/list failed: ${message.error.message}\n${message.error.data}',
        );
      }
      final response = message as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      expect(tools, hasLength(6));
      for (final tool in tools.cast<Map>()) {
        expect(_containsMcpHeader(tool['inputSchema']), isFalse);
      }
    });

    test('invalid stateless header metadata is stripped from nested schemas',
        () async {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerTool(
        'nested-header-tool',
        inputSchema: ToolInputSchema.fromJson({
          'type': 'object',
          'properties': {
            'invalidArray': {
              'type': 'array',
              'items': {
                'type': 'string',
                'x-mcp-header': 'Item',
              },
            },
            'objectMap': {
              'type': 'object',
              'additionalProperties': {
                'type': 'string',
                'x-mcp-header': 'Additional',
              },
            },
            'combined': {
              'allOf': [
                true,
                {
                  'type': 'string',
                  'x-mcp-header': 'All',
                },
              ],
              'anyOf': [
                false,
                {
                  'type': 'integer',
                  'x-mcp-header': 'Any',
                },
              ],
              'oneOf': [
                {
                  'type': 'boolean',
                  'x-mcp-header': 'One',
                },
              ],
              'not': {
                'type': 'string',
                'x-mcp-header': 'Not',
              },
            },
            'literalData': {
              'default': {
                'x-mcp-header': 'not schema metadata',
              },
            },
            'preservedAny': {
              'properties': {
                'flag': true,
              },
            },
            'conditional': {
              'if': {
                'properties': {
                  'region': {
                    'type': 'string',
                    'x-mcp-header': 'Conditional',
                  },
                },
              },
            },
          },
          r'$defs': {
            'region': {
              'type': 'string',
              'x-mcp-header': 'Definition',
            },
          },
          'patternProperties': {
            '^region': {
              'type': 'string',
              'x-mcp-header': 'Pattern',
            },
          },
        }),
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      transport = McpServerTestTransport(initializeOnStart: false);
      await server.connect(transport);

      transport.receiveMessage(
        JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final message = transport.sentMessages.last;
      if (message is JsonRpcError) {
        fail(
          'tools/list failed: ${message.error.message}\n${message.error.data}',
        );
      }
      final response = message as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      final tool = tools.single as Map;
      final inputSchema = tool['inputSchema'] as Map;
      final properties = inputSchema['properties'] as Map;
      final invalidArray = properties['invalidArray'] as Map;
      final objectMap = properties['objectMap'] as Map;
      final combined = properties['combined'] as Map;
      final allOf = combined['allOf'] as List;
      final anyOf = combined['anyOf'] as List;
      final oneOf = combined['oneOf'] as List;
      final literalData = properties['literalData'] as Map;
      final preservedAny = properties['preservedAny'] as Map;
      final conditional = properties['conditional'] as Map;
      final definitions = inputSchema[r'$defs'] as Map;
      final patternProperties = inputSchema['patternProperties'] as Map;

      expect(
        (invalidArray['items'] as Map).containsKey('x-mcp-header'),
        isFalse,
      );
      expect(
        (objectMap['additionalProperties'] as Map).containsKey('x-mcp-header'),
        isFalse,
      );
      expect((allOf[1] as Map).containsKey('x-mcp-header'), isFalse);
      expect((anyOf[1] as Map).containsKey('x-mcp-header'), isFalse);
      expect((oneOf.single as Map).containsKey('x-mcp-header'), isFalse);
      expect((combined['not'] as Map).containsKey('x-mcp-header'), isFalse);
      final ifProperties = (conditional['if'] as Map)['properties'] as Map;
      expect(
        (ifProperties['region'] as Map).containsKey('x-mcp-header'),
        isFalse,
      );
      expect(
        (definitions['region'] as Map).containsKey('x-mcp-header'),
        isFalse,
      );
      expect(
        (patternProperties['^region'] as Map).containsKey('x-mcp-header'),
        isFalse,
      );
      expect(
        (literalData['default'] as Map)['x-mcp-header'],
        'not schema metadata',
      );
      expect(((preservedAny['properties'] as Map)['flag'] as bool), isTrue);
    });

    test('registerTool can be updated', () async {
      final registeredTool = server.registerTool(
        'updatable-tool',
        description: 'Original description',
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      // Update the tool
      registeredTool.update(description: 'Updated description');

      await server.connect(transport);

      // Request tool list
      final request = const JsonRpcListToolsRequest(id: 1);
      transport.receiveMessage(request);

      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      expect(tools.first['description'], equals('Updated description'));
    });

    test('stateless tool handle preserves and updates its full API', () async {
      final initialOutputSchema = JsonSchema.array(
        items: JsonSchema.string(),
      );
      CallToolResult initialCallback(
        Map<String, dynamic> args,
        RequestHandlerExtra extra,
      ) {
        return CallToolResult.fromStructuredArray(['initial']);
      }

      final registeredTool = server.registerStatelessTool(
        'stateless-tool',
        outputJsonSchema: initialOutputSchema,
        callback: initialCallback,
      );

      expect(registeredTool.outputJsonSchema, same(initialOutputSchema));
      expect(registeredTool.outputSchema, isNull);
      expect(registeredTool.statelessCallback, same(initialCallback));
      expect(registeredTool.callback, isNull);

      final updatedOutputSchema = JsonSchema.string();
      CallToolResult updatedCallback(
        Map<String, dynamic> args,
        RequestHandlerExtra extra,
      ) {
        return CallToolResult.fromStructuredString('updated');
      }

      registeredTool.updateStateless(
        description: 'Updated stateless tool',
        outputJsonSchema: updatedOutputSchema,
        callback: updatedCallback,
      );

      expect(registeredTool.description, 'Updated stateless tool');
      expect(registeredTool.outputJsonSchema, same(updatedOutputSchema));
      expect(registeredTool.statelessCallback, same(updatedCallback));
      expect(
        () => registeredTool.updateStateless(
          outputJsonSchema: initialOutputSchema,
          clearOutputSchema: true,
        ),
        throwsArgumentError,
      );
      expect(registeredTool.outputJsonSchema, same(updatedOutputSchema));

      transport = McpServerTestTransport(initializeOnStart: false);
      await server.connect(transport);
      final listMessage = await _receiveResponse(
        transport,
        JsonRpcListToolsRequest(id: 10, meta: _statelessMeta()),
      );
      final listedTools =
          (listMessage as JsonRpcResponse).result['tools'] as List;
      expect(listedTools.single['description'], 'Updated stateless tool');
      expect(listedTools.single['outputSchema']['type'], 'string');

      final callMessage = await _receiveResponse(
        transport,
        JsonRpcCallToolRequest(
          id: 11,
          params: const CallToolRequest(name: 'stateless-tool').toJson(),
          meta: _statelessMeta(),
        ),
      );
      final result = CallToolResult.fromJson(
        (callMessage as JsonRpcResponse).result,
      );
      expect(result.structuredContentJson?.asString, 'updated');

      registeredTool.updateStateless(clearOutputSchema: true);
      expect(registeredTool.outputJsonSchema, isNull);
    });

    test('registerTool rename rejects an occupied name', () {
      final first = server.registerTool(
        'first-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      server.registerTool(
        'second-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      expect(
        () => first.update(name: 'second-tool'),
        throwsArgumentError,
      );
      expect(first.name, 'first-tool');
    });

    test('registerTool can be disabled and enabled', () async {
      final registeredTool = server.registerTool(
        'toggleable-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      await server.connect(transport);

      // Disable the tool
      registeredTool.disable();
      expect(registeredTool.enabled, isFalse);

      // Request tool list - should be empty
      final request1 = const JsonRpcListToolsRequest(id: 1);
      transport.receiveMessage(request1);
      await Future.delayed(const Duration(milliseconds: 100));

      var response = transport.sentMessages.last as JsonRpcResponse;
      var tools = response.result['tools'] as List;
      expect(tools, isEmpty);

      // Enable the tool
      registeredTool.enable();
      expect(registeredTool.enabled, isTrue);

      // Request tool list again - should have one tool
      final request2 = const JsonRpcListToolsRequest(id: 2);
      transport.receiveMessage(request2);
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      tools = response.result['tools'] as List;
      expect(tools.length, equals(1));
    });

    test('registerTool when removed is not listed', () async {
      final registeredTool = server.registerTool(
        'removable-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      await server.connect(transport);

      // First verify it's listed
      final request1 = const JsonRpcListToolsRequest(id: 1);
      transport.receiveMessage(request1);
      await Future.delayed(const Duration(milliseconds: 100));

      var response = transport.sentMessages.last as JsonRpcResponse;
      var tools = response.result['tools'] as List;
      expect(tools.length, equals(1));

      registeredTool.remove();

      // Request tool list - should be empty after removal.
      final request2 = const JsonRpcListToolsRequest(id: 2);
      transport.receiveMessage(request2);
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      tools = response.result['tools'] as List;
      expect(tools, isEmpty);
    });

    test('a stale tool handle cannot remove a replacement registration',
        () async {
      final stale = server.registerTool(
        'replaceable-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      stale.remove();
      server.registerTool(
        'replaceable-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      stale.remove();

      await server.connect(transport);
      transport.receiveMessage(const JsonRpcListToolsRequest(id: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      expect(tools.single['name'], 'replaceable-tool');
    });

    test('a removed tool handle cannot resurrect itself by renaming', () async {
      final stale = server.registerTool(
        'replaceable-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      stale.remove();
      server.registerTool(
        'replaceable-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      expect(
        () => stale.update(name: 'resurrected-tool'),
        throwsStateError,
      );

      await server.connect(transport);
      transport.receiveMessage(const JsonRpcListToolsRequest(id: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      expect(tools.single['name'], 'replaceable-tool');
    });

    test('tool call invokes callback with arguments', () async {
      final receivedArgs = Completer<Map<String, dynamic>?>();

      server.registerTool(
        'arg-test-tool',
        callback: (args, extra) async {
          receivedArgs.complete(args);
          return const CallToolResult(
            content: [TextContent(text: 'Done')],
          );
        },
      );

      await server.connect(transport);

      // Call the tool - using raw params map
      final callRequest = const JsonRpcCallToolRequest(
        id: 2,
        params: {
          'name': 'arg-test-tool',
          'arguments': {'key': 'value'},
        },
      );
      transport.receiveMessage(callRequest);

      final args = await receivedArgs.future.timeout(
        const Duration(seconds: 1),
      );
      expect(args, isNotNull);
      expect(args!['key'], equals('value'));
    });

    test('schema-invalid stable call returns an actionable tool error',
        () async {
      var callbackCalled = false;
      server.registerTool(
        'validated-tool',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        callback: (args, extra) async {
          callbackCalled = true;
          return const CallToolResult(content: []);
        },
      );
      await server.connect(transport);

      final message = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'stable-invalid',
          params: {
            'name': 'validated-tool',
            'arguments': {'count': 'many'},
          },
          meta: {McpMetaKey.protocolVersion: '2025-06-18'},
        ),
      );

      expect(message, isA<JsonRpcResponse>());
      final response = message as JsonRpcResponse;
      expect(response.id, 'stable-invalid');
      expect(response.result.keys, unorderedEquals(['content', 'isError']));
      final result = CallToolResult.fromJson(response.result);
      expect(result.isError, isTrue);
      expect(result.content.single, isA<TextContent>());
      expect(
        (result.content.single as TextContent).text,
        allOf(
          contains("Invalid arguments for tool 'validated-tool'"),
          contains('count'),
        ),
      );
      expect(callbackCalled, isFalse);
    });

    test('schema-invalid stateless call returns a complete tool error',
        () async {
      var callbackCalled = false;
      server.registerTool(
        'validated-tool',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        callback: (args, extra) async {
          callbackCalled = true;
          return const CallToolResult(content: []);
        },
      );
      transport = McpServerTestTransport(initializeOnStart: false);
      await server.connect(transport);

      final message = await _receiveResponse(
        transport,
        JsonRpcCallToolRequest(
          id: 'stateless-invalid',
          params: const {
            'name': 'validated-tool',
            'arguments': {'count': 'many'},
          },
          meta: _statelessMeta(),
        ),
      );

      expect(message, isA<JsonRpcResponse>());
      final response = message as JsonRpcResponse;
      expect(response.id, 'stateless-invalid');
      expect(response.result['resultType'], resultTypeComplete);
      expect(response.result, isNot(contains('ttlMs')));
      expect(response.result, isNot(contains('cacheScope')));
      expect(
        response.result['_meta']?[McpMetaKey.serverInfo],
        {'name': 'test-server', 'version': '1.0.0'},
      );
      expect(CallToolResult.fromJson(response.result).isError, isTrue);
      expect(callbackCalled, isFalse);
    });

    test('older negotiated versions retain invalidParams for schema failures',
        () async {
      for (final protocolVersion in const [
        '2025-06-18',
        '2025-03-26',
        '2024-11-05',
        '2024-10-07',
      ]) {
        final olderServer = McpServer(
          const Implementation(name: 'test-server', version: '1.0.0'),
        );
        final olderTransport = McpServerTestTransport(
          initializationProtocolVersion: protocolVersion,
        );
        var callbackCalled = false;
        olderServer.registerTool(
          'validated-tool',
          inputSchema: const ToolInputSchema(
            properties: {'count': JsonInteger()},
            required: ['count'],
          ),
          callback: (args, extra) async {
            callbackCalled = true;
            return const CallToolResult(content: []);
          },
        );

        try {
          await olderServer.connect(olderTransport);
          final message = await _receiveResponse(
            olderTransport,
            JsonRpcCallToolRequest(
              id: protocolVersion,
              params: const {
                'name': 'validated-tool',
                'arguments': {'count': 'many'},
              },
              meta: const {
                McpMetaKey.protocolVersion: latestInitializationProtocolVersion,
              },
            ),
          );

          expect(message, isA<JsonRpcError>(), reason: protocolVersion);
          final response = message as JsonRpcError;
          expect(response.id, protocolVersion);
          expect(response.error.code, ErrorCode.invalidParams.value);
          expect(
            response.error.message,
            contains("Invalid arguments for tool 'validated-tool'"),
          );
          expect(callbackCalled, isFalse);
        } finally {
          await olderServer.close();
        }
      }
    });

    test('malformed tool arguments remain protocol errors', () async {
      server.registerTool(
        'validated-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      await server.connect(transport);

      final statelessServer = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      addTearDown(statelessServer.close);
      statelessServer.registerTool(
        'validated-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      final statelessTransport = McpServerTestTransport(
        initializeOnStart: false,
      );
      await statelessServer.connect(statelessTransport);

      for (final scenario in [
        (
          transport: transport,
          request: const JsonRpcCallToolRequest(
            id: 'stable-malformed',
            params: {
              'name': 'validated-tool',
              'arguments': 'not-an-object',
            },
          ),
        ),
        (
          transport: statelessTransport,
          request: JsonRpcCallToolRequest(
            id: 'stateless-malformed',
            params: const {
              'name': 'validated-tool',
              'arguments': 'not-an-object',
            },
            meta: _statelessMeta(),
          ),
        ),
      ]) {
        final message = await _receiveResponse(
          scenario.transport,
          scenario.request,
        );
        expect(message, isA<JsonRpcError>());
        final response = message as JsonRpcError;
        expect(response.id, scenario.request.id);
        expect(response.error.code, ErrorCode.invalidParams.value);
        expect(
          response.error.message,
          'Failed to parse params for request ${Method.toolsCall}',
        );
      }
    });

    test('unsupported registered input schema is a server error', () async {
      var callbackCalled = false;
      server.registerTool(
        'invalid-schema-tool',
        inputSchema: ToolInputSchema.fromJson({
          r'$schema': 'https://example.com/unsupported-schema',
          'type': 'object',
        }),
        callback: (args, extra) async {
          callbackCalled = true;
          return const CallToolResult(content: []);
        },
      );
      await server.connect(transport);

      final message = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'invalid-schema',
          params: {'name': 'invalid-schema-tool', 'arguments': {}},
        ),
      );

      expect(message, isA<JsonRpcError>());
      final response = message as JsonRpcError;
      expect(response.id, 'invalid-schema');
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        "Tool 'invalid-schema-tool' has an invalid or unsupported input schema.",
      );
      expect(callbackCalled, isFalse);
    });

    test('older protocols retain invalidParams for invalid input schemas',
        () async {
      final olderServer = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      final olderTransport = McpServerTestTransport(
        initializationProtocolVersion: '2025-06-18',
      );
      olderServer.registerTool(
        'invalid-schema-tool',
        inputSchema: ToolInputSchema.fromJson({
          r'$schema': 'https://example.com/unsupported-schema',
          'type': 'object',
        }),
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      try {
        await olderServer.connect(olderTransport);
        final message = await _receiveResponse(
          olderTransport,
          const JsonRpcCallToolRequest(
            id: 'legacy-invalid-schema',
            params: {'name': 'invalid-schema-tool', 'arguments': {}},
          ),
        );

        expect(message, isA<JsonRpcError>());
        expect(
          (message as JsonRpcError).error.code,
          ErrorCode.invalidParams.value,
        );
      } finally {
        await olderServer.close();
      }
    });

    test('reconnect refreshes negotiated input-validation behavior', () async {
      final reconnectingServer = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      reconnectingServer.registerTool(
        'validated-tool',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        callback: (args, extra) async => const CallToolResult(content: []),
      );

      final olderTransport = McpServerTestTransport(
        initializationProtocolVersion: '2025-06-18',
      );
      await reconnectingServer.connect(olderTransport);
      final olderMessage = await _receiveResponse(
        olderTransport,
        const JsonRpcCallToolRequest(
          id: 'before-reconnect',
          params: {
            'name': 'validated-tool',
            'arguments': {'count': 'many'},
          },
        ),
      );
      expect(olderMessage, isA<JsonRpcError>());
      await reconnectingServer.close();

      final currentTransport = McpServerTestTransport();
      try {
        await reconnectingServer.connect(currentTransport);
        final currentMessage = await _receiveResponse(
          currentTransport,
          const JsonRpcCallToolRequest(
            id: 'after-reconnect',
            params: {
              'name': 'validated-tool',
              'arguments': {'count': 'many'},
            },
          ),
        );
        expect(currentMessage, isA<JsonRpcResponse>());
        expect(
          CallToolResult.fromJson(
            (currentMessage as JsonRpcResponse).result,
          ).isError,
          isTrue,
        );
      } finally {
        await reconnectingServer.close();
      }
    });

    test('tool call returns error for unknown tool', () async {
      server.registerTool(
        'known-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      await server.connect(transport);

      final statelessServer = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      addTearDown(statelessServer.close);
      statelessServer.registerTool(
        'known-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      final statelessTransport = McpServerTestTransport(
        initializeOnStart: false,
      );
      await statelessServer.connect(statelessTransport);

      for (final scenario in [
        (
          transport: transport,
          request: const JsonRpcCallToolRequest(
            id: 'stable-unknown',
            params: {'name': 'non-existent-tool'},
          ),
        ),
        (
          transport: statelessTransport,
          request: JsonRpcCallToolRequest(
            id: 'stateless-unknown',
            params: const {'name': 'non-existent-tool'},
            meta: _statelessMeta(),
          ),
        ),
      ]) {
        final message = await _receiveResponse(
          scenario.transport,
          scenario.request,
        );
        expect(message, isA<JsonRpcError>());
        final response = message as JsonRpcError;
        expect(response.id, scenario.request.id);
        expect(response.error.code, ErrorCode.invalidParams.value);
        expect(response.error.message, "Tool 'non-existent-tool' not found");
      }
    });

    test('disabled tool remains a protocol error', () async {
      final registeredTool = server.registerTool(
        'disabled-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      registeredTool.disable();
      await server.connect(transport);

      final message = await _receiveResponse(
        transport,
        const JsonRpcCallToolRequest(
          id: 'disabled',
          params: {'name': 'disabled-tool'},
        ),
      );

      expect(message, isA<JsonRpcError>());
      final response = message as JsonRpcError;
      expect(response.id, 'disabled');
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, "Tool 'disabled-tool' is disabled");
    });
  });

  group('McpServer Resource Registration', () {
    late McpServer server;
    late McpServerTestTransport transport;

    setUp(() {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      transport = McpServerTestTransport();
    });

    tearDown(() async {
      await server.close();
    });

    test('registerResource creates a resource that can be listed', () async {
      server.registerResource(
        'Test Resource',
        'test://resource',
        (description: 'A test resource', mimeType: null),
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                text: 'Resource content',
              ),
            ],
          );
        },
      );

      await server.connect(transport);

      // Request resource list
      final request = JsonRpcListResourcesRequest(id: 1);
      transport.receiveMessage(request);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last as JsonRpcResponse;
      final resources = response.result['resources'] as List;
      expect(resources.length, equals(1));
      expect(resources.first['uri'], equals('test://resource'));
    });

    test('registerResource includes list metadata when provided', () async {
      server.registerResource(
        'UI Resource',
        'ui://resource',
        (
          description: 'A UI resource',
          mimeType: mcpUiResourceMimeType,
        ),
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                text: '<!doctype html>',
                mimeType: mcpUiResourceMimeType,
              ),
            ],
          );
        },
        meta: const {
          'ui': {
            'prefersBorder': true,
          },
        },
      );

      await server.connect(transport);

      final request = JsonRpcListResourcesRequest(id: 1);
      transport.receiveMessage(request);

      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final resources = response.result['resources'] as List<dynamic>;
      final listed = resources.first as Map<String, dynamic>;

      expect(listed['uri'], equals('ui://resource'));
      expect(listed['_meta'], isNotNull);
      expect(listed['_meta']['ui']['prefersBorder'], isTrue);
    });

    test('registerResource can be enabled and disabled', () async {
      final registeredResource = server.registerResource(
        'Toggleable Resource',
        'test://toggleable',
        null,
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(uri: uri.toString(), text: 'content'),
            ],
          );
        },
      );

      await server.connect(transport);

      // Disable the resource
      registeredResource.disable();
      expect(registeredResource.enabled, isFalse);

      // Request resource list - should be empty
      final request1 = JsonRpcListResourcesRequest(id: 1);
      transport.receiveMessage(request1);
      await Future.delayed(const Duration(milliseconds: 100));

      var response = transport.sentMessages.last as JsonRpcResponse;
      var resources = response.result['resources'] as List;
      expect(resources, isEmpty);

      // Enable the resource
      registeredResource.enable();

      // Request again - should have one resource
      final request2 = JsonRpcListResourcesRequest(id: 2);
      transport.receiveMessage(request2);
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      resources = response.result['resources'] as List;
      expect(resources.length, equals(1));
    });

    test('registerResource can update its URI and be removed', () async {
      final registeredResource = server.registerResource(
        'Mutable Resource',
        'test://old',
        null,
        (uri, extra) async => ReadResourceResult(
          contents: [
            TextResourceContents(uri: uri.toString(), text: 'content'),
          ],
        ),
      );
      registeredResource.update(uri: 'test://new');

      await server.connect(transport);
      transport.receiveMessage(JsonRpcListResourcesRequest(id: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      var response = transport.sentMessages.last as JsonRpcResponse;
      var resources = response.result['resources'] as List;
      expect(resources.single['uri'], 'test://new');

      registeredResource.remove();
      transport.receiveMessage(JsonRpcListResourcesRequest(id: 2));
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      resources = response.result['resources'] as List;
      expect(resources, isEmpty);
    });

    test('resource and template renames reject occupied keys', () {
      final firstResource = server.registerResource(
        'First Resource',
        'test://first',
        null,
        (uri, extra) async => const ReadResourceResult(contents: []),
      );
      server.registerResource(
        'Second Resource',
        'test://second',
        null,
        (uri, extra) async => const ReadResourceResult(contents: []),
      );
      expect(
        () => firstResource.update(
          title: 'Mutated title',
          uri: 'test://second',
        ),
        throwsArgumentError,
      );
      expect(firstResource.title, isNull);

      final firstTemplate = server.registerResourceTemplate(
        'first-template',
        ResourceTemplateRegistration(
          'test://first/{id}',
          listCallback: (extra) => const ListResourcesResult(resources: []),
        ),
        null,
        (uri, variables, extra) async => const ReadResourceResult(contents: []),
      );
      server.registerResourceTemplate(
        'second-template',
        ResourceTemplateRegistration(
          'test://second/{id}',
          listCallback: (extra) => const ListResourcesResult(resources: []),
        ),
        null,
        (uri, variables, extra) async => const ReadResourceResult(contents: []),
      );
      expect(
        () => firstTemplate.update(
          name: 'second-template',
          title: 'Mutated title',
        ),
        throwsArgumentError,
      );
      expect(firstTemplate.title, isNull);
    });

    test('registerResourceTemplate can update its name and be removed',
        () async {
      final registeredTemplate = server.registerResourceTemplate(
        'old-template',
        ResourceTemplateRegistration(
          'test://{id}',
          listCallback: (extra) => const ListResourcesResult(resources: []),
        ),
        null,
        (uri, variables, extra) async => const ReadResourceResult(contents: []),
      );
      registeredTemplate.update(name: 'new-template');

      await server.connect(transport);
      transport.receiveMessage(JsonRpcListResourceTemplatesRequest(id: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      var response = transport.sentMessages.last as JsonRpcResponse;
      var templates = response.result['resourceTemplates'] as List;
      expect(templates.single['name'], 'new-template');

      registeredTemplate.remove();
      transport.receiveMessage(JsonRpcListResourceTemplatesRequest(id: 2));
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      templates = response.result['resourceTemplates'] as List;
      expect(templates, isEmpty);
    });

    test('read resource returns content', () async {
      server.registerResource(
        'Readable Resource',
        'test://readable',
        null,
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                text: 'Hello from resource',
              ),
            ],
          );
        },
      );

      await server.connect(transport);

      // Read the resource
      final readRequest = JsonRpcReadResourceRequest(
        id: 2,
        readParams: const ReadResourceRequestParams(uri: 'test://readable'),
      );
      transport.receiveMessage(readRequest);

      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final contents = response.result['contents'] as List;
      expect(contents.first['text'], equals('Hello from resource'));
    });

    test('legacy resource miss uses stable resource-not-found error', () async {
      server.registerResource(
        'Known Resource',
        'test://known',
        null,
        (uri, extra) async => ReadResourceResult(
          contents: [
            TextResourceContents(uri: uri.toString(), text: 'known'),
          ],
        ),
      );

      await server.connect(transport);

      transport.receiveMessage(
        JsonRpcReadResourceRequest(
          id: 'missing-resource',
          readParams: const ReadResourceRequestParams(uri: 'test://missing'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.resourceNotFound.value);
      expect(response.error.message, 'Resource not found');
      expect(response.error.data, {'uri': 'test://missing'});
    });

    test('stateless resource miss uses 2026 invalid params error', () async {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerResource(
        'Known Resource',
        'test://known',
        null,
        (uri, extra) async => ReadResourceResult(
          contents: [
            TextResourceContents(uri: uri.toString(), text: 'known'),
          ],
        ),
      );

      transport = McpServerTestTransport(initializeOnStart: false);
      await server.connect(transport);

      transport.receiveMessage(
        JsonRpcReadResourceRequest(
          id: 'missing-resource',
          readParams: const ReadResourceRequestParams(uri: 'test://missing'),
          meta: _statelessMeta(),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, 'Resource not found');
      expect(response.error.data, {'uri': 'test://missing'});
    });
  });

  group('McpServer Prompt Registration', () {
    late McpServer server;
    late McpServerTestTransport transport;

    setUp(() {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      transport = McpServerTestTransport();
    });

    tearDown(() async {
      await server.close();
    });

    test('registerPrompt creates a prompt that can be listed', () async {
      server.registerPrompt(
        'test-prompt',
        description: 'A test prompt',
        callback: (args, extra) async {
          return const GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'Hello'),
              ),
            ],
          );
        },
      );

      await server.connect(transport);

      // Request prompt list
      final request = JsonRpcListPromptsRequest(id: 1);
      transport.receiveMessage(request);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(transport.sentMessages.length, greaterThan(0));
      final response = transport.sentMessages.last as JsonRpcResponse;
      final prompts = response.result['prompts'] as List;
      expect(prompts.length, equals(1));
      expect(prompts.first['name'], equals('test-prompt'));
    });

    test('registerPrompt can be enabled and disabled', () async {
      final registeredPrompt = server.registerPrompt(
        'toggleable-prompt',
        callback: (args, extra) async {
          return const GetPromptResult(messages: []);
        },
      );

      await server.connect(transport);

      // Disable the prompt
      registeredPrompt.disable();
      expect(registeredPrompt.enabled, isFalse);

      // Request prompt list - should be empty
      final request1 = JsonRpcListPromptsRequest(id: 1);
      transport.receiveMessage(request1);
      await Future.delayed(const Duration(milliseconds: 100));

      var response = transport.sentMessages.last as JsonRpcResponse;
      var prompts = response.result['prompts'] as List;
      expect(prompts, isEmpty);

      // Enable the prompt
      registeredPrompt.enable();

      // Request again - should have one prompt
      final request2 = JsonRpcListPromptsRequest(id: 2);
      transport.receiveMessage(request2);
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      prompts = response.result['prompts'] as List;
      expect(prompts.length, equals(1));
    });

    test('registerPrompt rename rejects an occupied name', () {
      final first = server.registerPrompt(
        'first-prompt',
        callback: (args, extra) async => const GetPromptResult(messages: []),
      );
      server.registerPrompt(
        'second-prompt',
        callback: (args, extra) async => const GetPromptResult(messages: []),
      );

      expect(
        () => first.update(name: 'second-prompt'),
        throwsArgumentError,
      );
      expect(first.name, 'first-prompt');
    });

    test('registerPrompt can be removed', () async {
      final registeredPrompt = server.registerPrompt(
        'removable-prompt',
        callback: (args, extra) async => const GetPromptResult(messages: []),
      );

      await server.connect(transport);
      registeredPrompt.remove();
      transport.receiveMessage(JsonRpcListPromptsRequest(id: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.result['prompts'], isEmpty);
    });

    test('get prompt invokes callback with arguments', () async {
      server.registerPrompt(
        'callable-prompt',
        callback: (args, extra) async {
          final lang = args?['language'] ?? 'english';
          return GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'Hello in $lang'),
              ),
            ],
          );
        },
      );

      await server.connect(transport);

      // Get the prompt
      final getRequest = JsonRpcGetPromptRequest(
        id: 2,
        getParams: const GetPromptRequestParams(
          name: 'callable-prompt',
          arguments: {'language': 'french'},
        ),
      );
      transport.receiveMessage(getRequest);

      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final messages = response.result['messages'] as List;
      expect(messages.first['content']['text'], contains('french'));
    });

    test('get prompt passes a typed empty map when arguments are omitted',
        () async {
      server.registerPrompt(
        'no-arguments-prompt',
        callback: (args, extra) async {
          expect(args, isA<Map<String, dynamic>>());
          expect(args, isEmpty);
          return const GetPromptResult(messages: []);
        },
      );

      await server.connect(transport);
      transport.receiveMessage(
        JsonRpcGetPromptRequest(
          id: 3,
          getParams: const GetPromptRequestParams(name: 'no-arguments-prompt'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });
  });

  group('McpServer Connected State', () {
    late McpServer server;
    late McpServerTestTransport transport;

    setUp(() {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      transport = McpServerTestTransport();
    });

    tearDown(() async {
      try {
        await server.close();
      } catch (_) {}
    });

    test('isConnected returns false before connect', () {
      expect(server.isConnected, isFalse);
    });

    test('isConnected returns true after connect', () async {
      await server.connect(transport);
      expect(server.isConnected, isTrue);
    });

    test('isConnected returns false after close', () async {
      await server.connect(transport);
      await server.close();
      expect(server.isConnected, isFalse);
    });

    test('legacy connections accept initialization-era request metadata',
        () async {
      server.registerTool(
        'legacy-tool',
        callback: (args, extra) async => const CallToolResult(content: []),
      );
      await server.connect(transport);

      final message = await _receiveResponse(
        transport,
        const JsonRpcListToolsRequest(
          id: 'legacy-version-metadata',
          meta: {McpMetaKey.protocolVersion: '2025-06-18'},
        ),
      );

      expect(message, isA<JsonRpcResponse>());
    });

    test('legacy connections accept client progress notifications', () async {
      final errors = <Error>[];
      server.onError = errors.add;
      await server.connect(transport);

      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'request-1',
            progress: 1,
            total: 2,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(errors, isEmpty);
    });
  });
}
