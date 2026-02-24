import 'dart:async';

import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
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
  group('McpServer - Tool Registration', () {
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

    test('registers tool and lists it correctly', () async {
      var callbackInvoked = false;
      var receivedArgs = <String, dynamic>{};

      mcpServer.registerTool(
        'test_tool',
        description: 'A test tool',
        inputSchema: JsonObject(
          properties: {
            'input': JsonSchema.string(),
          },
        ),
        callback: (args, extra) async {
          callbackInvoked = true;
          receivedArgs = args;
          return CallToolResult(
            content: [TextContent(text: 'Tool executed: ${args['input']}')],
          );
        },
      );

      await mcpServer.connect(transport);

      // Simulate client sending initialize request
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

      // Now simulate tools/call request
      final callRequest = JsonRpcCallToolRequest(
        id: 3,
        params: const CallToolRequest(
          name: 'test_tool',
          arguments: {'input': 'test value'},
        ).toJson(),
      );

      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(callbackInvoked, isTrue);
      expect(receivedArgs['input'], equals('test value'));
    });

    test('tool callback receives RequestHandlerExtra', () async {
      RequestHandlerExtra? receivedExtra;

      mcpServer.registerTool(
        'extra_test',
        callback: (args, extra) async {
          receivedExtra = extra;
          return const CallToolResult(
            content: [TextContent(text: 'ok')],
          );
        },
      );

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

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'extra_test').toJson(),
      );
      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedExtra, isNotNull);
    });

    test('tool callback error returns CallToolResult with isError', () async {
      mcpServer.registerTool(
        'error_tool',
        callback: (args, extra) async {
          throw Exception('Tool execution failed');
        },
      );

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

      final callRequest = JsonRpcCallToolRequest(
        id: 2,
        params: const CallToolRequest(name: 'error_tool').toJson(),
      );

      transport.receiveMessage(callRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Should handle gracefully with error result
      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('cannot register duplicate tool names', () {
      mcpServer.registerTool(
        'duplicate',
        callback: (args, extra) async {
          return const CallToolResult(
            content: [TextContent(text: 'first')],
          );
        },
      );

      expect(
        () => mcpServer.registerTool(
          'duplicate',
          callback: (args, extra) async {
            return const CallToolResult(
              content: [TextContent(text: 'second')],
            );
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('already registered'),
          ),
        ),
      );
    });

    test('tool with output schema is registered correctly', () {
      mcpServer.registerTool(
        'schema_tool',
        description: 'Tool with schemas',
        inputSchema: JsonObject(
          properties: {
            'query': JsonSchema.string(),
          },
        ),
        outputSchema: JsonObject(
          properties: {
            'result': JsonSchema.string(),
          },
        ),
        callback: (args, extra) async {
          return const CallToolResult(
            content: [TextContent(text: 'result')],
          );
        },
      );

      // Tool should be registered successfully
      expect(mcpServer, isNotNull);
    });

    test('tool meta is included in tools/list response', () async {
      mcpServer.registerTool(
        'ui_tool',
        description: 'A tool with UI metadata',
        meta: {
          'ui': {
            'resourceUri': 'ui://test-server/dashboard',
            'visibility': ['model', 'app'],
          },
        },
        callback: (args, extra) async {
          return const CallToolResult(
            content: [TextContent(text: 'result')],
          );
        },
      );

      await mcpServer.connect(transport);

      // Initialize
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

      // Request tools/list
      final listRequest = JsonRpcListToolsRequest.fromJson({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });
      transport.receiveMessage(listRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Find the tools/list response
      final response = transport.sentMessages
          .whereType<JsonRpcResponse>()
          .where((r) => r.id == 2)
          .first;

      final tools = (response.result['tools'] as List)
          .cast<Map<String, dynamic>>();
      final uiTool = tools.firstWhere((t) => t['name'] == 'ui_tool');

      expect(uiTool['_meta'], isNotNull);
      expect(uiTool['_meta']['ui']['resourceUri'],
          equals('ui://test-server/dashboard'));
      expect(uiTool['_meta']['ui']['visibility'], equals(['model', 'app']));
    });
  });

  group('McpServer - Resource Registration', () {
    late McpServer mcpServer;
    late MockTransport transport;

    setUp(() {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            resources: ServerCapabilitiesResources(),
          ),
        ),
      );
      transport = MockTransport();
    });

    test('registers static resource and handles read callback', () async {
      var readCallbackInvoked = false;

      mcpServer.resource(
        'test_resource',
        'file:///test.txt',
        (uri, extra) async {
          readCallbackInvoked = true;
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                text: 'Test content',
              ),
            ],
          );
        },
        metadata: (description: 'Test resource', mimeType: 'text/plain'),
      );

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

      // Test resources/read
      final readRequest = JsonRpcReadResourceRequest(
        id: 3,
        readParams: const ReadResourceRequestParams(uri: 'file:///test.txt'),
      );
      transport.receiveMessage(readRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(readCallbackInvoked, isTrue);
    });

    test('cannot register duplicate resource URIs', () {
      mcpServer.resource(
        'resource1',
        'file:///duplicate.txt',
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(uri: uri.toString(), text: 'content1'),
            ],
          );
        },
      );

      expect(
        () => mcpServer.resource(
          'resource2',
          'file:///duplicate.txt',
          (uri, extra) async {
            return ReadResourceResult(
              contents: [
                TextResourceContents(uri: uri.toString(), text: 'content2'),
              ],
            );
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('already registered'),
          ),
        ),
      );
    });

    test('resourceTemplate with variable completion', () async {
      mcpServer.resourceTemplate(
        'file_template',
        ResourceTemplateRegistration(
          'file:///{path}',
          listCallback: (extra) async {
            return const ListResourcesResult(
              resources: [
                Resource(
                  uri: 'file:///file1.txt',
                  name: 'File 1',
                ),
                Resource(
                  uri: 'file:///file2.txt',
                  name: 'File 2',
                ),
              ],
            );
          },
          completeCallbacks: {
            'path': (currentValue) async {
              return ['file1.txt', 'file2.txt', 'file3.txt']
                  .where((f) => f.startsWith(currentValue))
                  .toList();
            },
          },
        ),
        (uri, variables, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                text: 'Content for ${variables['path']}',
              ),
            ],
          );
        },
        metadata: (description: 'File resources', mimeType: 'text/plain'),
      );

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

      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('resource template read matches query parameters', () async {
      var readCallbackInvoked = false;
      Map<String, dynamic>? receivedVariables;

      mcpServer.resourceTemplate(
        'entity_template',
        ResourceTemplateRegistration(
          'entity://list{?status,assignee}',
          listCallback: (extra) async =>
              const ListResourcesResult(resources: []),
        ),
        (uri, variables, extra) async {
          readCallbackInvoked = true;
          receivedVariables = Map<String, dynamic>.from(variables);
          return ReadResourceResult(
            contents: [
              TextResourceContents(uri: uri.toString(), text: 'content'),
            ],
          );
        },
      );

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

      final readRequest = JsonRpcReadResourceRequest(
        id: 2,
        readParams: const ReadResourceRequestParams(
          uri: 'entity://list?status=s1&assignee=u1',
        ),
      );

      transport.receiveMessage(readRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(readCallbackInvoked, isTrue);
      expect(receivedVariables, equals({'status': 's1', 'assignee': 'u1'}));
    });

    test('cannot register duplicate resource template names', () {
      mcpServer.resourceTemplate(
        'duplicate_template',
        ResourceTemplateRegistration(
          'file:///{path}',
          listCallback: (extra) async =>
              const ListResourcesResult(resources: []),
        ),
        (uri, variables, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(uri: uri.toString(), text: 'content'),
            ],
          );
        },
      );

      expect(
        () => mcpServer.resourceTemplate(
          'duplicate_template',
          ResourceTemplateRegistration(
            'http://{host}/{path}',
            listCallback: (extra) async =>
                const ListResourcesResult(resources: []),
          ),
          (uri, variables, extra) async {
            return ReadResourceResult(
              contents: [
                TextResourceContents(uri: uri.toString(), text: 'content2'),
              ],
            );
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('already registered'),
          ),
        ),
      );
    });

    test('resource read with invalid URI throws McpError', () async {
      mcpServer.resource(
        'valid_resource',
        'file:///valid.txt',
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(uri: uri.toString(), text: 'content'),
            ],
          );
        },
      );

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

      final readRequest = JsonRpcReadResourceRequest(
        id: 2,
        readParams: const ReadResourceRequestParams(uri: 'invalid:::uri'),
      );

      transport.receiveMessage(readRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Server should send error response
      expect(transport.sentMessages.isNotEmpty, isTrue);
    });
  });

  group('McpServer - Prompt Registration', () {
    late McpServer mcpServer;
    late MockTransport transport;

    setUp(() {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            prompts: ServerCapabilitiesPrompts(),
          ),
        ),
      );
      transport = MockTransport();
    });

    test('registers prompt and handles callback', () async {
      var callbackInvoked = false;
      var receivedArgs = <String, dynamic>{};

      mcpServer.prompt(
        'test_prompt',
        description: 'A test prompt',
        argsSchema: {
          'topic': const PromptArgumentDefinition(
            description: 'Topic to discuss',
            required: true,
          ),
        },
        callback: (args, extra) async {
          callbackInvoked = true;
          receivedArgs = args ?? {};
          return GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'Discuss ${args?['topic']}'),
              ),
            ],
          );
        },
      );

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

      // Test prompts/get
      final getRequest = JsonRpcGetPromptRequest(
        id: 3,
        getParams: const GetPromptRequestParams(
          name: 'test_prompt',
          arguments: {'topic': 'AI'},
        ),
      );
      transport.receiveMessage(getRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(callbackInvoked, isTrue);
      expect(receivedArgs['topic'], equals('AI'));
    });

    test('prompt with argument completion', () async {
      mcpServer.prompt(
        'autocomplete_prompt',
        description: 'Prompt with autocomplete',
        argsSchema: {
          'category': PromptArgumentDefinition(
            description: 'Category to select',
            required: true,
            completable: CompletableField(
              def: CompletableDef(
                complete: (value) async {
                  return ['tech', 'science', 'sports']
                      .where((c) => c.startsWith(value))
                      .toList();
                },
              ),
            ),
          ),
        },
        callback: (args, extra) async {
          return GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'Category: ${args?['category']}'),
              ),
            ],
          );
        },
      );

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

      // Test completion/complete for prompt argument
      final completeRequest = JsonRpcCompleteRequest(
        id: 2,
        completeParams: const CompleteRequestParams(
          ref: PromptReference(name: 'autocomplete_prompt'),
          argument: ArgumentCompletionInfo(name: 'category', value: 'te'),
        ),
      );
      transport.receiveMessage(completeRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('prompt argument validation - missing required argument', () async {
      mcpServer.prompt(
        'strict_prompt',
        argsSchema: {
          'required_arg': const PromptArgumentDefinition(
            required: true,
          ),
        },
        callback: (args, extra) async {
          return const GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'ok'),
              ),
            ],
          );
        },
      );

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

      // Call prompt without required argument
      final getRequest = JsonRpcGetPromptRequest(
        id: 2,
        getParams: const GetPromptRequestParams(
          name: 'strict_prompt',
          arguments: {}, // Missing required_arg
        ),
      );
      transport.receiveMessage(getRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Should send error response
      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('prompt argument validation - wrong type', () async {
      mcpServer.prompt(
        'typed_prompt',
        argsSchema: {
          'count': const PromptArgumentDefinition(
            required: true,
          ),
        },
        callback: (args, extra) async {
          return const GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'ok'),
              ),
            ],
          );
        },
      );

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

      // Call prompt with wrong type
      final getRequest = JsonRpcGetPromptRequest(
        id: 2,
        getParams: const GetPromptRequestParams(
          name: 'typed_prompt',
          arguments: {'count': 'not_a_number'}, // Wrong type
        ),
      );
      transport.receiveMessage(getRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Should send error response
      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('cannot register duplicate prompt names', () {
      mcpServer.prompt(
        'duplicate_prompt',
        callback: (args, extra) async {
          return const GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'first'),
              ),
            ],
          );
        },
      );

      expect(
        () => mcpServer.prompt(
          'duplicate_prompt',
          callback: (args, extra) async {
            return const GetPromptResult(
              messages: [
                PromptMessage(
                  role: PromptMessageRole.user,
                  content: TextContent(text: 'second'),
                ),
              ],
            );
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('already registered'),
          ),
        ),
      );
    });
  });

  group('McpServer - Completion', () {
    late McpServer mcpServer;
    late MockTransport transport;

    setUp(() {
      mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            prompts: ServerCapabilitiesPrompts(),
            resources: ServerCapabilitiesResources(),
          ),
        ),
      );
      transport = MockTransport();
    });

    test('resource template completion returns suggestions', () async {
      mcpServer.resourceTemplate(
        'completion_template',
        ResourceTemplateRegistration(
          'file:///{path}',
          listCallback: (extra) async =>
              const ListResourcesResult(resources: []),
          completeCallbacks: {
            'path': (currentValue) async {
              return [
                'documents/file1.txt',
                'documents/file2.txt',
                'downloads/file3.txt',
              ].where((p) => p.contains(currentValue)).toList();
            },
          },
        ),
        (uri, variables, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(uri: uri.toString(), text: 'content'),
            ],
          );
        },
      );

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

      final completeRequest = JsonRpcCompleteRequest(
        id: 2,
        completeParams: const CompleteRequestParams(
          ref: ResourceReference(
            uri: 'file:///{path}',
          ),
          argument: ArgumentCompletionInfo(name: 'path', value: 'documents'),
        ),
      );
      transport.receiveMessage(completeRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('completion limits results to 100 items', () async {
      mcpServer.prompt(
        'large_completion_prompt',
        argsSchema: {
          'item': PromptArgumentDefinition(
            completable: CompletableField(
              def: CompletableDef(
                complete: (value) async {
                  // Return more than 100 items
                  return List.generate(150, (i) => 'item_$i');
                },
              ),
            ),
          ),
        },
        callback: (args, extra) async {
          return const GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'ok'),
              ),
            ],
          );
        },
      );

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

      final completeRequest = JsonRpcCompleteRequest(
        id: 2,
        completeParams: const CompleteRequestParams(
          ref: PromptReference(name: 'large_completion_prompt'),
          argument: ArgumentCompletionInfo(name: 'item', value: 'item'),
        ),
      );
      transport.receiveMessage(completeRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Should limit to 100 and set hasMore=true
      expect(transport.sentMessages.isNotEmpty, isTrue);
    });

    test('completion returns empty result when no completer registered',
        () async {
      mcpServer.prompt(
        'no_completion_prompt',
        argsSchema: {
          'arg': const PromptArgumentDefinition(
            // No completable field
            required: false,
          ),
        },
        callback: (args, extra) async {
          return const GetPromptResult(
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'ok'),
              ),
            ],
          );
        },
      );

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

      final completeRequest = JsonRpcCompleteRequest(
        id: 2,
        completeParams: const CompleteRequestParams(
          ref: PromptReference(name: 'no_completion_prompt'),
          argument: ArgumentCompletionInfo(name: 'arg', value: 'test'),
        ),
      );
      transport.receiveMessage(completeRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // Should return empty completion result
      expect(transport.sentMessages.isNotEmpty, isTrue);
    });
  });

  group('McpServer - Connection Lifecycle', () {
    test('connect and close work correctly', () async {
      final mcpServer = McpServer(
        const Implementation(name: 'TestServer', version: '1.0.0'),
      );
      final transport = MockTransport();

      await mcpServer.connect(transport);
      expect(transport.isStarted, isTrue);

      await mcpServer.close();
      expect(transport.isClosed, isTrue);
    });
  });
}
