import 'dart:async';

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

class RecordingTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool started = false;
  bool closed = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
  }

  @override
  Future<void> start() async {
    started = true;
  }

  void receive(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

class DiscoveringClientTransport extends Transport
    implements ProtocolVersionAwareTransport {
  DiscoveringClientTransport({
    this.discoverVersions = const [draftProtocolVersion2026_07_28],
  });

  final List<String> discoverVersions;
  final List<JsonRpcMessage> sentMessages = [];

  @override
  String? protocolVersion;

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
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: DiscoverResult(
            supportedVersions: discoverVersions,
            capabilities: const ServerCapabilities(
              tools: ServerCapabilitiesTools(),
            ),
            serverInfo: const Implementation(name: 'server', version: '1.0.0'),
          ).toJson(),
        ),
      );
      return;
    }

    if (message is JsonRpcRequest && message.method == Method.toolsList) {
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: const ListToolsResult(tools: []).toJson(),
        ),
      );
    }
  }

  @override
  Future<void> start() async {}
}

class LegacyFallbackTransport extends Transport
    implements ProtocolVersionAwareTransport {
  final List<JsonRpcMessage> sentMessages = [];

  @override
  String? protocolVersion;

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
      onmessage?.call(
        JsonRpcError(
          id: message.id,
          error: JsonRpcErrorData(
            code: ErrorCode.methodNotFound.value,
            message: 'Method not found',
          ),
        ),
      );
      return;
    }

    if (message is JsonRpcRequest && message.method == Method.initialize) {
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: const InitializeResult(
            protocolVersion: stableProtocolVersion2025_11_25,
            capabilities: ServerCapabilities(
              tools: ServerCapabilitiesTools(),
            ),
            serverInfo: Implementation(name: 'server', version: '1.0.0'),
          ).toJson(),
        ),
      );
    }
  }

  @override
  Future<void> start() async {}
}

Map<String, dynamic> _clientMeta({String? protocolVersion}) {
  return buildProtocolRequestMeta(
    protocolVersion: protocolVersion ?? draftProtocolVersion2026_07_28,
    clientInfo: const Implementation(name: 'client', version: '1.0.0'),
    clientCapabilities: const ClientCapabilities(),
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('MCP 2026-07-28 RC protocol foundation', () {
    test('defines draft protocol version separately from stable default', () {
      expect(latestProtocolVersion, stableProtocolVersion2025_11_25);
      expect(latestDraftProtocolVersion, draftProtocolVersion2026_07_28);
      expect(
        supportedProtocolVersionsWithDraft,
        contains(draftProtocolVersion2026_07_28),
      );
      expect(isStatelessProtocolVersion(draftProtocolVersion2026_07_28), true);
      expect(isStatelessProtocolVersion(latestProtocolVersion), false);
    });

    test('builds stateless request metadata without dropping caller metadata',
        () {
      final meta = buildProtocolRequestMeta(
        protocolVersion: draftProtocolVersion2026_07_28,
        clientInfo: const Implementation(name: 'client', version: '1.0.0'),
        clientCapabilities: const ClientCapabilities(),
        meta: const {'caller': 'value'},
        logLevel: 'debug',
      );

      expect(meta['caller'], 'value');
      expect(
        meta[McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );
      expect(meta[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
      expect(meta[McpMetaKey.clientCapabilities], <String, dynamic>{});
      expect(meta[McpMetaKey.logLevel], 'debug');
    });

    test('serializes server/discover request and result', () {
      final request = JsonRpcServerDiscoverRequest(
        id: 'discover-1',
        meta: _clientMeta(),
      );

      final requestJson = request.toJson();
      expect(requestJson['method'], Method.serverDiscover);
      expect(
        requestJson['params']['_meta'][McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );
      expect(
        requestJson['params']['_meta'][McpMetaKey.clientCapabilities],
        <String, dynamic>{},
      );

      final result = const DiscoverResult(
        supportedVersions: [draftProtocolVersion2026_07_28],
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        serverInfo: Implementation(name: 'server', version: '1.0.0'),
        instructions: 'Use the tools.',
      );
      final resultJson = result.toJson();
      expect(resultJson['resultType'], 'complete');
      expect(resultJson['supportedVersions'], [draftProtocolVersion2026_07_28]);
      expect(resultJson['capabilities'], {'tools': <String, dynamic>{}});
      expect(
        DiscoverResult.fromJson(resultJson).instructions,
        'Use the tools.',
      );
    });

    test('serializes MRTR input required results', () {
      final result = InputRequiredResult(
        inputRequests: {
          'github_login': InputRequest.elicit(
            ElicitRequest.form(
              message: 'Please provide your GitHub username',
              requestedSchema: JsonSchema.object(
                properties: {'name': JsonSchema.string()},
                required: ['name'],
              ),
            ),
          ),
          'capital_of_france': InputRequest.createMessage(
            const CreateMessageRequest(
              messages: [
                SamplingMessage(
                  role: SamplingMessageRole.user,
                  content: SamplingTextContent(
                    text: 'What is the capital of France?',
                  ),
                ),
              ],
              maxTokens: 100,
            ),
          ),
          'roots': InputRequest.listRoots(),
        },
        requestState: 'AEAD-protected blob',
        meta: const {'trace': 'abc'},
      );

      final json = result.toJson();
      expect(json['resultType'], resultTypeInputRequired);
      expect(json['requestState'], 'AEAD-protected blob');
      expect(json['_meta'], {'trace': 'abc'});
      expect(
        json['inputRequests']['github_login']['method'],
        Method.elicitationCreate,
      );
      expect(
        json['inputRequests']['capital_of_france']['method'],
        Method.samplingCreateMessage,
      );
      expect(json['inputRequests']['roots'], {'method': Method.rootsList});

      final parsed = InputRequiredResult.fromJson(json);
      expect(parsed.requestState, 'AEAD-protected blob');
      expect(
        parsed.inputRequests!['github_login']!.elicitParams.message,
        'Please provide your GitHub username',
      );
      expect(
        parsed
            .inputRequests!['capital_of_france']!.createMessageParams.maxTokens,
        100,
      );
    });

    test('serializes MRTR retry fields on supported client requests', () {
      final inputResponses = {
        'github_login': InputResponse.fromResult(
          const ElicitResult(
            action: 'accept',
            content: {'name': 'octocat'},
          ),
        ),
        'roots': InputResponse.fromResult(
          ListRootsResult(roots: [Root(uri: 'file:///repo')]),
        ),
      };

      final toolRequest = CallToolRequest(
        name: 'deploy',
        arguments: const {'service': 'api'},
        inputResponses: inputResponses,
        requestState: 'opaque-state',
      );
      final toolJson = toolRequest.toJson();
      expect(toolJson['inputResponses']['github_login']['action'], 'accept');
      expect(toolJson['requestState'], 'opaque-state');

      final parsedToolRequest = CallToolRequest.fromJson(toolJson);
      expect(parsedToolRequest.requestState, 'opaque-state');
      expect(
        parsedToolRequest.inputResponses!['roots']!.toJson()['roots'][0]['uri'],
        'file:///repo',
      );

      final promptJson = GetPromptRequest(
        name: 'summary',
        inputResponses: inputResponses,
        requestState: 'prompt-state',
      ).toJson();
      expect(promptJson['inputResponses']['github_login']['content'], {
        'name': 'octocat',
      });
      expect(
        GetPromptRequest.fromJson(promptJson).requestState,
        'prompt-state',
      );

      final resourceJson = ReadResourceRequest(
        uri: 'file:///repo/README.md',
        inputResponses: inputResponses,
        requestState: 'resource-state',
      ).toJson();
      expect(
        resourceJson['inputResponses']['roots']['roots'][0]['uri'],
        'file:///repo',
      );
      expect(
        ReadResourceRequest.fromJson(resourceJson).requestState,
        'resource-state',
      );
    });

    test('rejects malformed MRTR wire shapes', () {
      expect(
        () => InputRequiredResult.fromJson(
          const {'resultType': resultTypeInputRequired},
        ),
        throwsFormatException,
      );
      expect(
        () => InputRequiredResult.fromJson(
          const {
            'resultType': resultTypeInputRequired,
            'requestState': 1,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => InputRequiredResult.fromJson(
          const {
            'resultType': resultTypeInputRequired,
            'requestState': 'state',
            '_meta': false,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => InputRequiredResult.fromJson(
          const {
            'resultType': resultTypeInputRequired,
            'inputRequests': {
              'unsupported': {'method': Method.toolsCall},
            },
          },
        ),
        throwsFormatException,
      );
      expect(
        () => CallToolRequest.fromJson(
          const {'name': 'deploy', 'requestState': 1},
        ),
        throwsFormatException,
      );
      expect(
        () => ReadResourceRequest.fromJson(
          const {
            'uri': 'file:///repo/README.md',
            'inputResponses': {'roots': []},
          },
        ),
        throwsFormatException,
      );
    });

    test('server handles server/discover before legacy initialization',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
          instructions: 'Discovery instructions.',
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover-1', meta: _clientMeta()),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.id, 'discover-1');
      expect(
        response.result['supportedVersions'],
        contains(draftProtocolVersion2026_07_28),
      );
      expect(response.result['serverInfo']['name'], 'server');
      expect(response.result['instructions'], 'Discovery instructions.');
    });

    test('server accepts stateless requests without initialize', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          expect(
            extra.meta?[McpMetaKey.protocolVersion],
            draftProtocolVersion2026_07_28,
          );
          return const ListToolsResult(
            tools: [
              Tool(name: 'echo', inputSchema: JsonObject()),
            ],
          );
        },
        (id, params, meta) => JsonRpcListToolsRequest(
          id: id,
          params: params,
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(JsonRpcListToolsRequest(id: 1, meta: _clientMeta()));
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      final tools = response.result['tools'] as List<dynamic>;
      expect(tools.single['name'], 'echo');
    });

    test('server returns unsupported protocol version for stateless metadata',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcListToolsRequest(
          id: 1,
          meta: _clientMeta(protocolVersion: '1900-01-01'),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.unsupportedProtocolVersion.value);
      expect(response.error.data['requested'], '1900-01-01');
      expect(
        response.error.data['supported'],
        contains(draftProtocolVersion2026_07_28),
      );
    });

    test('server rejects malformed stateless request metadata', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
      );

      McpError? validateToolRequest(Map<String, dynamic>? meta) {
        return server.validateIncomingRequest(
          JsonRpcListToolsRequest(id: 1, meta: meta),
        );
      }

      McpError? validateDiscoverRequest(Map<String, dynamic>? meta) {
        return server.validateIncomingRequest(
          JsonRpcServerDiscoverRequest(id: 1, meta: meta),
        );
      }

      expect(
        validateDiscoverRequest(const {}),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains(McpMetaKey.protocolVersion),
        ),
      );
      expect(
        validateDiscoverRequest(
          _clientMeta(protocolVersion: stableProtocolVersion2025_11_25),
        ),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains('stateless protocol version'),
        ),
      );
      expect(
        validateToolRequest({
          McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
          McpMetaKey.clientCapabilities: <String, dynamic>{},
        }),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains(McpMetaKey.clientInfo),
        ),
      );
      expect(
        validateToolRequest({
          McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
          McpMetaKey.clientInfo: {
            'name': 'client',
            'version': '1.0.0',
          },
        }),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains(McpMetaKey.clientCapabilities),
        ),
      );
      expect(
        validateToolRequest({
          McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
          McpMetaKey.clientInfo: {'name': 1},
          McpMetaKey.clientCapabilities: <String, dynamic>{},
        }),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains('Invalid stateless request metadata.'),
        ),
      );
    });

    test('client can opt in to server/discover and sends stateless metadata',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), draftProtocolVersion2026_07_28);
      expect(transport.protocolVersion, draftProtocolVersion2026_07_28);
      expect(
        (transport.sentMessages.single as JsonRpcRequest).method,
        Method.serverDiscover,
      );

      await client.listTools();

      final listRequest = transport.sentMessages.last as JsonRpcRequest;
      expect(listRequest.method, Method.toolsList);
      expect(
        listRequest.meta?[McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );
      expect(listRequest.meta?[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
      expect(listRequest.meta?[McpMetaKey.clientCapabilities], {});
    });

    test('client rejects discovery when no compatible version is offered',
        () async {
      final transport = DiscoveringClientTransport(
        discoverVersions: const ['1900-01-01'],
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await expectLater(
        client.connect(transport),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.unsupportedProtocolVersion.value,
          ),
        ),
      );
    });

    test('client falls back to initialize when discovery is unavailable',
        () async {
      final transport = LegacyFallbackTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), stableProtocolVersion2025_11_25);
      expect(transport.protocolVersion, stableProtocolVersion2025_11_25);
      expect(
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        containsAllInOrder([Method.serverDiscover, Method.initialize]),
      );
      expect(
        transport.sentMessages.whereType<JsonRpcInitializedNotification>(),
        isEmpty,
      );
      expect(
        transport.sentMessages.whereType<JsonRpcNotification>().last.method,
        Method.notificationsInitialized,
      );
    });
  });
}
