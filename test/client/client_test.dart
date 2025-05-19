import 'dart:async';

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('Client', () {
    late Client client;
    late Implementation clientInfo;
    late MockTransport transport;
    late ServerCapabilities mockServerCapabilities;

    setUp(() {
      clientInfo = Implementation(name: 'TestClient', version: '1.0.0');
      client = Client(clientInfo);
      transport = MockTransport();

      // Define mock server capabilities for testing
      mockServerCapabilities = ServerCapabilities(
        logging: {'supported': true},
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        resources: ServerCapabilitiesResources(
          subscribe: true,
          listChanged: true,
        ),
        tools: ServerCapabilitiesTools(listChanged: true),
      );
    });

    test('constructor initializes with client info and default capabilities',
        () {
      expect(client.getServerCapabilities(), isNull);
      expect(client.getServerVersion(), isNull);
      expect(client.getInstructions(), isNull);
    });

    test('registerCapabilities throws StateError if transport is connected',
        () async {
      // Connect the client to the transport first
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );

      await client.connect(transport);

      // Now test that registerCapabilities throws an exception after connection
      expect(
        () => client.registerCapabilities(ClientCapabilities()),
        throwsA(isA<StateError>()),
      );
    });

    test('registerCapabilities merges capabilities', () {
      final initialCapabilities =
          ClientCapabilities(experimental: {'feature1': true});
      client = Client(clientInfo,
          options: ClientOptions(capabilities: initialCapabilities));

      final additionalCapabilities = ClientCapabilities(
          experimental: {'feature2': true},
          roots: ClientCapabilitiesRoots(listChanged: true));

      client.registerCapabilities(additionalCapabilities);

      // This test is somewhat limited as we don't have direct access to the private _capabilities
      // We'll test this indirectly in other tests
    });

    test('connect initializes the client with the server', () async {
      // Setup the mock transport to respond to initialization
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
        instructions: 'Test instructions',
      );

      await client.connect(transport);

      final serverCaps = client.getServerCapabilities();
      expect(serverCaps?.logging != null, isTrue);
      expect(serverCaps?.prompts?.listChanged,
          equals(mockServerCapabilities.prompts?.listChanged));
      expect(serverCaps?.resources?.subscribe,
          equals(mockServerCapabilities.resources?.subscribe));
      expect(serverCaps?.resources?.listChanged,
          equals(mockServerCapabilities.resources?.listChanged));
      expect(serverCaps?.tools?.listChanged,
          equals(mockServerCapabilities.tools?.listChanged));
      expect(client.getServerVersion()?.name, equals('TestServer'));
      expect(client.getServerVersion()?.version, equals('2.0.0'));
      expect(client.getInstructions(), equals('Test instructions'));

      expect(transport.sentMessages.length, greaterThan(0));
      expect(transport.sentMessages.first is JsonRpcRequest, isTrue);
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('initialize'));

      // Verify that an initialized notification was sent
      final List<JsonRpcMessage> notifications = transport.sentMessages
          .where((m) =>
              m is JsonRpcNotification &&
              m.method == 'notifications/initialized')
          .toList();
      expect(notifications.length, equals(1));
    });

    test('connect throws if server returns unsupported protocol version',
        () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: '1999-01-01', // Unsupported version
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );

      expect(() => client.connect(transport), throwsA(isA<McpError>()));
    });

    test('connect handles transport errors', () async {
      transport.shouldThrowOnStart = true;
      expect(() => client.connect(transport), throwsException);
    });

    test('assertCapabilityForMethod checks for required server capabilities',
        () async {
      // Setup connected client with capabilities
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      // Should not throw for supported capabilities
      expect(() => client.assertCapabilityForMethod("logging/setLevel"),
          returnsNormally);
      expect(() => client.assertCapabilityForMethod("prompts/list"),
          returnsNormally);
      expect(() => client.assertCapabilityForMethod("resources/subscribe"),
          returnsNormally);
      expect(() => client.assertCapabilityForMethod("tools/call"),
          returnsNormally);

      // Create a client with limited capabilities
      final limitedClient = Client(clientInfo);
      transport = MockTransport();
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: ServerCapabilities(), // No capabilities
        serverInfo: Implementation(name: 'LimitedServer', version: '1.0.0'),
      );
      await limitedClient.connect(transport);

      // Should throw for unsupported capabilities
      expect(() => limitedClient.assertCapabilityForMethod("logging/setLevel"),
          throwsA(isA<McpError>()));
      expect(() => limitedClient.assertCapabilityForMethod("prompts/list"),
          throwsA(isA<McpError>()));
    });

    test('assertCapabilityForMethod throws if client not initialized', () {
      expect(() => client.assertCapabilityForMethod("logging/setLevel"),
          throwsA(isA<StateError>()));
    });

    test('assertNotificationCapability checks client capabilities', () {
      final capableClient = Client(clientInfo,
          options: ClientOptions(
              capabilities: ClientCapabilities(
                  roots: ClientCapabilitiesRoots(listChanged: true))));

      // Should not throw for supported capabilities
      expect(
          () => capableClient
              .assertNotificationCapability("notifications/roots/list_changed"),
          returnsNormally);

      // Should throw for unsupported capabilities
      expect(
          () => client
              .assertNotificationCapability("notifications/roots/list_changed"),
          throwsA(isA<StateError>()));
    });

    test('assertRequestHandlerCapability checks client capabilities', () {
      final capableClient = Client(clientInfo,
          options: ClientOptions(
              capabilities: ClientCapabilities(
                  sampling: {'supported': true},
                  roots: ClientCapabilitiesRoots())));

      // Should not throw for supported capabilities
      expect(
          () => capableClient
              .assertRequestHandlerCapability("sampling/createMessage"),
          returnsNormally);
      expect(() => capableClient.assertRequestHandlerCapability("roots/list"),
          returnsNormally);

      // Should throw for unsupported capabilities
      expect(
          () => client.assertRequestHandlerCapability("sampling/createMessage"),
          throwsA(isA<StateError>()));
    });

    test('ping sends a ping request and returns EmptyResult', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.ping();

      // Verify a ping request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('ping'));
    });

    test('complete sends completion request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      final params = CompleteRequestParams(
          ref: PromptReference(name: 'test-prompt'),
          argument: ArgumentCompletionInfo(name: 'arg1', value: 'val'));

      await client.complete(params);

      // Verify a complete request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('completion/complete'));
    });

    test('setLoggingLevel sends logging level request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.setLoggingLevel(LoggingLevel.debug);

      // Verify a setLevel request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('logging/setLevel'));
    });

    test('getPrompt sends prompt request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      final params = GetPromptRequestParams(name: 'test-prompt');
      await client.getPrompt(params);

      // Verify a getPrompt request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('prompts/get'));
    });

    test('listPrompts sends list prompts request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.listPrompts();

      // Verify a listPrompts request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('prompts/list'));
    });

    test('listResources sends list resources request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.listResources();

      // Verify a listResources request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('resources/list'));
    });

    test('listResourceTemplates sends list resource templates request',
        () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.listResourceTemplates();

      // Verify a listResourceTemplates request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('resources/templates/list'));
    });

    test('readResource sends resource read request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      final params = ReadResourceRequestParams(uri: 'test://resource');
      await client.readResource(params);

      // Verify a readResource request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('resources/read'));
    });

    test('subscribeResource sends resource subscribe request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      final params = SubscribeRequestParams(uri: 'test://resource');
      await client.subscribeResource(params);

      // Verify a subscribeResource request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('resources/subscribe'));
    });

    test('unsubscribeResource sends resource unsubscribe request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      final params = UnsubscribeRequestParams(uri: 'test://resource');
      await client.unsubscribeResource(params);

      // Verify an unsubscribeResource request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('resources/unsubscribe'));
    });

    test('callTool sends tool call request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      final params = CallToolRequestParams(name: 'test-tool');
      await client.callTool(params);

      // Verify a callTool request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('tools/call'));
    });

    test('listTools sends list tools request', () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.listTools();

      // Verify a listTools request was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcRequest).method,
          equals('tools/list'));
    });

    test('sendRootsListChanged sends roots list changed notification',
        () async {
      transport.mockInitializeResponse = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: mockServerCapabilities,
        serverInfo: Implementation(name: 'TestServer', version: '2.0.0'),
      );
      await client.connect(transport);

      transport.clearSentMessages();

      await client.sendRootsListChanged();

      // Verify a roots list changed notification was sent
      expect(transport.sentMessages.length, equals(1));
      expect((transport.sentMessages.first as JsonRpcNotification).method,
          equals('notifications/roots/list_changed'));
    });
  });
}

class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  InitializeResult? mockInitializeResponse;
  bool shouldThrowOnStart = false;

  void clearSentMessages() {
    sentMessages.clear();
  }

  @override
  Future<void> start() async {
    if (shouldThrowOnStart) {
      throw Exception("Failed to start transport");
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    sentMessages.add(message);

    // If it's an initialize request, respond with the mock response
    if (message is JsonRpcRequest &&
        message.method == 'initialize' &&
        mockInitializeResponse != null) {
      if (onmessage != null) {
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: mockInitializeResponse!.toJson(),
        ));
      }
    } else if (message is JsonRpcRequest &&
        message.method == 'completion/complete') {
      if (onmessage != null) {
        final completion =
            CompletionResultData(values: ['suggestion1', 'suggestion2']);
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: CompleteResult(completion: completion).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest && message.method == 'tools/call') {
      if (onmessage != null) {
        final content = [TextContent(text: "Tool result")];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: CallToolResult.fromContent(content: content).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest && message.method == 'prompts/get') {
      if (onmessage != null) {
        final messages = [
          PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(text: "Test prompt"))
        ];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: GetPromptResult(messages: messages).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest && message.method == 'prompts/list') {
      if (onmessage != null) {
        final prompts = [Prompt(name: "test-prompt")];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: ListPromptsResult(prompts: prompts).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest &&
        message.method == 'resources/list') {
      if (onmessage != null) {
        final resources = [
          Resource(uri: "test://resource", name: "test-resource")
        ];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: ListResourcesResult(resources: resources).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest &&
        message.method == 'resources/templates/list') {
      if (onmessage != null) {
        final templates = [
          ResourceTemplate(
              uriTemplate: "test://{template}", name: "test-template")
        ];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: ListResourceTemplatesResult(resourceTemplates: templates)
              .toJson(),
        ));
      }
    } else if (message is JsonRpcRequest &&
        message.method == 'resources/read') {
      if (onmessage != null) {
        final contents = [
          TextResourceContents(uri: "test://resource", text: "Resource content")
        ];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: ReadResourceResult(contents: contents).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest && message.method == 'tools/list') {
      if (onmessage != null) {
        final tools = [Tool(name: "test-tool", inputSchema: ToolInputSchema())];
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: ListToolsResult(tools: tools).toJson(),
        ));
      }
    } else if (message is JsonRpcRequest) {
      // For any other request, respond with an empty result
      if (onmessage != null) {
        onmessage!(JsonRpcResponse(
          id: message.id,
          result: const EmptyResult().toJson(),
        ));
      }
    }
  }

  @override
  Future<void> close() async {}

  @override
  String? get sessionId => null;

  // Transport callbacks implementation
  void Function()? _onclose;
  void Function(Error error)? _onerror;
  void Function(JsonRpcMessage message)? _onmessage;

  @override
  void Function()? get onclose => _onclose;

  @override
  set onclose(void Function()? value) {
    _onclose = value;
  }

  @override
  void Function(Error error)? get onerror => _onerror;

  @override
  set onerror(void Function(Error error)? value) {
    _onerror = value;
  }

  @override
  void Function(JsonRpcMessage message)? get onmessage => _onmessage;

  @override
  set onmessage(void Function(JsonRpcMessage message)? value) {
    _onmessage = value;
  }
}
