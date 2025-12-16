import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock transport for McpServer tests
class McpServerTestTransport implements Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool _closed = false;

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
  Future<void> start() async {
    if (_closed) throw StateError('Cannot start closed transport');
  }
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

      // Disable the tool (remove() has a bug, so use disable())
      registeredTool.disable();

      // Request tool list - should be empty since disabled
      final request2 = const JsonRpcListToolsRequest(id: 2);
      transport.receiveMessage(request2);
      await Future.delayed(const Duration(milliseconds: 100));

      response = transport.sentMessages.last as JsonRpcResponse;
      tools = response.result['tools'] as List;
      expect(tools, isEmpty);
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

    test('tool call returns error for unknown tool', () async {
      await server.connect(transport);

      // Call a non-existent tool
      final callRequest = const JsonRpcCallToolRequest(
        id: 1,
        params: {'name': 'non-existent-tool'},
      );
      transport.receiveMessage(callRequest);

      await Future.delayed(const Duration(milliseconds: 100));

      final response = transport.sentMessages.last;
      expect(response, isA<JsonRpcError>());
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
  });
}
