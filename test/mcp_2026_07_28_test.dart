import 'dart:async';

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/server/tasks/handler.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
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
    this.unsupportedDiscoverProtocolVersions = const [],
    this.unsupportedDiscoverData,
    this.capabilities = const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
    this.toolsListResult = const {'tools': []},
  });

  final List<String> discoverVersions;
  final List<String> unsupportedDiscoverProtocolVersions;
  final Object? unsupportedDiscoverData;
  final ServerCapabilities capabilities;
  final Map<String, dynamic> toolsListResult;
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
      final requestedProtocolVersion =
          message.meta?[McpMetaKey.protocolVersion];
      if (unsupportedDiscoverProtocolVersions.contains(
        requestedProtocolVersion,
      )) {
        onmessage?.call(
          JsonRpcError(
            id: message.id,
            error: JsonRpcErrorData(
              code: ErrorCode.unsupportedProtocolVersion.value,
              message: 'Unsupported protocol version',
              data: unsupportedDiscoverData ??
                  {
                    'supported': discoverVersions,
                    'requested': requestedProtocolVersion,
                  },
            ),
          ),
        );
        return;
      }

      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: DiscoverResult(
            supportedVersions: discoverVersions,
            capabilities: capabilities,
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
          result: toolsListResult,
        ),
      );
    }
  }

  @override
  Future<void> start() async {}
}

class LegacyFallbackTransport extends Transport
    implements ProtocolVersionAwareTransport {
  LegacyFallbackTransport({
    this.toolsListResult = const {'tools': []},
  });

  final Map<String, dynamic> toolsListResult;
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
      return;
    }

    if (message is JsonRpcRequest && message.method == Method.toolsList) {
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: toolsListResult,
        ),
      );
    }
  }

  @override
  Future<void> start() async {}
}

class CompletedTaskHandler extends CancelTaskResultHandler {
  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async =>
      const CreateTaskResult(
        task: Task(
          taskId: 'task-1',
          status: TaskStatus.completed,
          ttl: null,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:01:00Z',
        ),
      );

  @override
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra) async => Task(
        taskId: taskId,
        status: TaskStatus.completed,
        ttl: null,
        createdAt: '2026-07-28T00:00:00Z',
        lastUpdatedAt: '2026-07-28T00:01:00Z',
      );

  @override
  Future<Task> cancelTaskWithResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) =>
      getTask(taskId, extra);

  @override
  Future<CallToolResult> getTaskResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) async =>
      const CallToolResult(
        content: [TextContent(text: 'task complete')],
      );
}

Map<String, dynamic> _clientMeta({
  String? protocolVersion,
  ClientCapabilities clientCapabilities = const ClientCapabilities(),
  Object? logLevel,
}) {
  return buildProtocolRequestMeta(
    protocolVersion: protocolVersion ?? draftProtocolVersion2026_07_28,
    clientInfo: const Implementation(name: 'client', version: '1.0.0'),
    clientCapabilities: clientCapabilities,
    logLevel: logLevel,
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

    test('serializes cacheable result hints without changing legacy defaults',
        () {
      final toolsJson = const ListToolsResult(
        tools: [],
        ttlMs: 300000,
        cacheScope: CacheScope.public,
      ).toJson();
      expect(toolsJson['ttlMs'], 300000);
      expect(toolsJson['cacheScope'], CacheScope.public);
      expect(toolsJson, isNot(contains('resultType')));
      final parsedTools = ListToolsResult.fromJson(toolsJson);
      expect(parsedTools.ttlMs, 300000);
      expect(parsedTools.cacheScope, CacheScope.public);

      final promptsJson = const ListPromptsResult(
        prompts: [],
        ttlMs: 600000,
        cacheScope: CacheScope.private,
      ).toJson();
      expect(ListPromptsResult.fromJson(promptsJson).ttlMs, 600000);
      expect(
        ListPromptsResult.fromJson(promptsJson).cacheScope,
        CacheScope.private,
      );

      final resourcesJson = const ListResourcesResult(
        resources: [],
        ttlMs: 120000,
        cacheScope: CacheScope.public,
      ).toJson();
      expect(ListResourcesResult.fromJson(resourcesJson).ttlMs, 120000);
      expect(
        ListResourcesResult.fromJson(resourcesJson).cacheScope,
        CacheScope.public,
      );

      final templatesJson = const ListResourceTemplatesResult(
        resourceTemplates: [],
        ttlMs: 30000,
        cacheScope: CacheScope.public,
      ).toJson();
      expect(
        ListResourceTemplatesResult.fromJson(templatesJson).ttlMs,
        30000,
      );
      expect(
        ListResourceTemplatesResult.fromJson(templatesJson).cacheScope,
        CacheScope.public,
      );

      final readJson = const ReadResourceResult(
        contents: [TextResourceContents(uri: 'file:///a.txt', text: 'a')],
        ttlMs: 60000,
        cacheScope: CacheScope.private,
      ).toJson();
      expect(ReadResourceResult.fromJson(readJson).ttlMs, 60000);
      expect(
        ReadResourceResult.fromJson(readJson).cacheScope,
        CacheScope.private,
      );

      expect(const ListToolsResult(tools: []).toJson(), {'tools': []});
      expect(
        ListToolsResult.fromJson(const {'tools': [], 'ttlMs': -1}).ttlMs,
        0,
      );
      expect(
        () => ListToolsResult.fromJson(
          const {'tools': [], 'cacheScope': 'shared'},
        ),
        throwsFormatException,
      );
      expect(
        () => const ListToolsResult(tools: [], ttlMs: -1).toJson(),
        throwsArgumentError,
      );
      expect(
        () => const ListToolsResult(
          tools: [],
          cacheScope: 'shared',
        ).toJson(),
        throwsArgumentError,
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

    test('server acknowledges subscriptions/listen with subscription id',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
            resources: ServerCapabilitiesResources(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            request.listenParams.notifications.acknowledgedBy(
              const ServerCapabilities(
                tools: ServerCapabilitiesTools(listChanged: true),
                resources: ServerCapabilitiesResources(),
              ),
            ),
          );
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-1',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(
              toolsListChanged: true,
              promptsListChanged: true,
              resourceSubscriptions: ['file:///project/config.json'],
            ),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final acknowledged = JsonRpcMessage.fromJson(
        transport.sentMessages.first.toJson(),
      ) as JsonRpcSubscriptionsAcknowledgedNotification;
      expect(
        acknowledged.method,
        Method.notificationsSubscriptionsAcknowledged,
      );
      expect(acknowledged.meta?[McpMetaKey.subscriptionId], 'sub-1');
      expect(
        acknowledged.acknowledgedParams.notifications.toJson(),
        {
          'toolsListChanged': true,
          'resourceSubscriptions': ['file:///project/config.json'],
        },
      );
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });

    test('server rejects subscription notifications before acknowledgment',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendNotification(
            const JsonRpcToolListChangedNotification(),
          );
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-1',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidRequest.value);
      expect(
        response.error.message,
        contains(Method.notificationsSubscriptionsAcknowledged),
      );
    });

    test('server tags direct subscription notifications with subscription id',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            request.listenParams.notifications.acknowledgedBy(
              const ServerCapabilities(
                tools: ServerCapabilitiesTools(listChanged: true),
              ),
            ),
          );
          await extra.sendNotification(
            const JsonRpcToolListChangedNotification(),
          );
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-1',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      expect(transport.sentMessages, hasLength(3));
      expect(
        transport.sentMessages.take(2).map((message) => message.toJson()),
        everyElement(
          containsPair(
            'params',
            containsPair(
              '_meta',
              containsPair(McpMetaKey.subscriptionId, 'sub-1'),
            ),
          ),
        ),
      );
      expect(
        (transport.sentMessages[1] as JsonRpcNotification).method,
        Method.notificationsToolsListChanged,
      );
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });

    test('stateless server responses add complete result and cache defaults',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            prompts: ServerCapabilitiesPrompts(),
            resources: ServerCapabilitiesResources(),
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(
          tools: [],
          ttlMs: 300000,
          cacheScope: CacheScope.public,
        ),
        (id, params, meta) => JsonRpcListToolsRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcListPromptsRequest>(
        Method.promptsList,
        (request, extra) async => const ListPromptsResult(prompts: []),
        (id, params, meta) => JsonRpcListPromptsRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcListResourcesRequest>(
        Method.resourcesList,
        (request, extra) async => const ListResourcesResult(resources: []),
        (id, params, meta) => JsonRpcListResourcesRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcListResourceTemplatesRequest>(
        Method.resourcesTemplatesList,
        (request, extra) async =>
            const ListResourceTemplatesResult(resourceTemplates: []),
        (id, params, meta) => JsonRpcListResourceTemplatesRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcReadResourceRequest>(
        Method.resourcesRead,
        (request, extra) async => const ReadResourceResult(
          contents: [TextResourceContents(uri: 'file:///a.txt', text: 'a')],
        ),
        (id, params, meta) => JsonRpcReadResourceRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final requests = [
        JsonRpcListToolsRequest(id: 'tools', meta: _clientMeta()),
        JsonRpcListPromptsRequest(id: 'prompts', meta: _clientMeta()),
        JsonRpcListResourcesRequest(id: 'resources', meta: _clientMeta()),
        JsonRpcListResourceTemplatesRequest(
          id: 'templates',
          meta: _clientMeta(),
        ),
        JsonRpcReadResourceRequest(
          id: 'read',
          readParams: const ReadResourceRequest(uri: 'file:///a.txt'),
          meta: _clientMeta(),
        ),
      ];
      for (final request in requests) {
        transport.receive(request);
        await _pump();
      }

      final responses = transport.sentMessages.cast<JsonRpcResponse>().toList();
      final tools = responses[0].result;
      expect(tools['resultType'], resultTypeComplete);
      expect(tools['ttlMs'], 300000);
      expect(tools['cacheScope'], CacheScope.public);

      for (final response in responses.skip(1)) {
        expect(response.result['resultType'], resultTypeComplete);
        expect(response.result['ttlMs'], 0);
        expect(response.result['cacheScope'], CacheScope.private);
      }
    });

    test('server rejects task subscriptions without task extension capability',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async => const EmptyResult(),
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-task',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(taskIds: ['task-1']),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(
        response.error.code,
        ErrorCode.missingRequiredClientCapability.value,
      );
      expect(
        response.error.data['requiredCapabilities']['extensions']
            [mcpTasksExtensionId],
        isEmpty,
      );
    });

    test('server rejects task extension methods without client capability',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport
        ..receive(
          JsonRpcGetTaskRequest(
            id: 'get-task',
            getParams: const GetTaskRequest(taskId: 'task-1'),
            meta: _clientMeta(),
          ),
        )
        ..receive(
          JsonRpcCancelTaskRequest(
            id: 'cancel-task',
            cancelParams: const CancelTaskRequest(taskId: 'task-1'),
            meta: _clientMeta(),
          ),
        )
        ..receive(
          JsonRpcUpdateTaskRequest(
            id: 'update-task',
            updateParams: const UpdateTaskRequest(
              taskId: 'task-1',
              inputResponses: {},
            ),
            meta: _clientMeta(),
          ),
        );
      await _pump();

      final errors = transport.sentMessages.cast<JsonRpcError>();
      expect(
        errors.map((response) => response.error.code),
        everyElement(ErrorCode.missingRequiredClientCapability.value),
      );
      expect(
        errors.first.error.data['requiredCapabilities']['extensions']
            [mcpTasksExtensionId],
        isEmpty,
      );
    });

    test('server handles task extension methods with 2026 result shapes',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async => const GetTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'task-1',
            status: TaskStatus.completed,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:01:00Z',
            ttlMs: 60000,
            result: {
              'content': [
                {'type': 'text', 'text': 'done'},
              ],
            },
          ),
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcCancelTaskRequest>(
        Method.tasksCancel,
        (request, extra) async => const TaskExtensionAcknowledgementResult(),
        (id, params, meta) => JsonRpcCancelTaskRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcUpdateTaskRequest>(
        Method.tasksUpdate,
        (request, extra) async => const EmptyResult(),
        (id, params, meta) => JsonRpcUpdateTaskRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);
      final taskExtensionMeta = _clientMeta(
        clientCapabilities: const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ),
      );

      transport
        ..receive(
          JsonRpcGetTaskRequest(
            id: 'get-task',
            getParams: const GetTaskRequest(taskId: 'task-1'),
            meta: taskExtensionMeta,
          ),
        )
        ..receive(
          JsonRpcCancelTaskRequest(
            id: 'cancel-task',
            cancelParams: const CancelTaskRequest(taskId: 'task-1'),
            meta: taskExtensionMeta,
          ),
        )
        ..receive(
          JsonRpcUpdateTaskRequest(
            id: 'update-task',
            updateParams: const UpdateTaskRequest(
              taskId: 'task-1',
              inputResponses: {},
            ),
            meta: taskExtensionMeta,
          ),
        );
      await _pump();

      final responses = transport.sentMessages.cast<JsonRpcResponse>().toList();
      expect(responses, hasLength(3));
      expect(responses[0].result['resultType'], resultTypeComplete);
      expect(responses[0].result['taskId'], 'task-1');
      expect(responses[0].result['ttlMs'], 60000);
      expect(responses[0].result, isNot(contains('ttl')));
      expect(responses[1].result, {'resultType': resultTypeComplete});
      expect(responses[2].result, {'resultType': resultTypeComplete});
    });

    test('server does not expose legacy task handlers as task extension',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      var handlerCalled = false;
      server.experimental.onGetTask((taskId, extra) async {
        handlerCalled = true;
        return Task(
          taskId: taskId,
          status: TaskStatus.completed,
          ttl: null,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:01:00Z',
        );
      });
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcGetTaskRequest(
          id: 'get-task',
          getParams: const GetTaskRequest(taskId: 'task-1'),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              extensions: {mcpTasksExtensionId: {}},
            ),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.methodNotFound.value);
      expect(response.error.message, contains(mcpTasksExtensionId));
      expect(handlerCalled, isFalse);
    });

    test('stateless task extension handlers reject legacy result shapes',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async => Task(
          taskId: request.getParams.taskId,
          status: TaskStatus.completed,
          ttl: null,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:01:00Z',
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcGetTaskRequest(
          id: 'get-task',
          getParams: const GetTaskRequest(taskId: 'task-1'),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              extensions: {mcpTasksExtensionId: {}},
            ),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains('GetTaskExtensionResult'));
    });

    test('server rejects removed legacy task methods in stateless protocol',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(list: true),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);
      final taskExtensionMeta = _clientMeta(
        clientCapabilities: const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ),
      );

      transport
        ..receive(
          JsonRpcListTasksRequest(id: 'list-tasks', meta: taskExtensionMeta),
        )
        ..receive(
          JsonRpcTaskResultRequest(
            id: 'task-result',
            resultParams: const TaskResultRequest(taskId: 'task-1'),
            meta: taskExtensionMeta,
          ),
        );
      await _pump();

      final errors = transport.sentMessages.cast<JsonRpcError>();
      expect(
        errors.map((response) => response.error.code),
        everyElement(ErrorCode.methodNotFound.value),
      );
      expect(errors.first.error.message, contains('MCP Tasks extension'));
    });

    test('server/discover omits legacy task capabilities', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(
              list: true,
              requests: ServerCapabilitiesTasksRequests(
                tools: ServerCapabilitiesTasksTools(
                  call: ServerCapabilitiesTasksToolsCall(),
                ),
              ),
            ),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover-1', meta: _clientMeta()),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      final capabilities = response.result['capabilities'] as Map;
      expect(capabilities, isNot(contains('tasks')));
      expect(
        (capabilities['extensions'] as Map)[mcpTasksExtensionId],
        isEmpty,
      );
    });

    test('stateless tools/call ignores legacy task parameter', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      server.registerTool(
        'echo',
        callback: (args, extra) => const CallToolResult(
          content: [TextContent(text: 'ok')],
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: {
            ...const CallToolRequest(name: 'echo').toJson(),
            'task': {'ttl': 1000},
          },
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['content'][0]['text'], 'ok');
    });

    test('stateless tools/call permits extension task creation results',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async => const CreateTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'task-1',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:00Z',
            ttlMs: null,
          ),
        ),
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'long').toJson(),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              extensions: {mcpTasksExtensionId: {}},
            ),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['resultType'], resultTypeTask);
      expect(response.result['taskId'], 'task-1');
    });

    test(
        'stateless tools/call rejects task extension result without capability',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async => const CreateTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'task-1',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:00Z',
            ttlMs: null,
          ),
        ),
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'long').toJson(),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(
        response.error.code,
        ErrorCode.missingRequiredClientCapability.value,
      );
    });

    test('stateless tools/call permits input required results', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async =>
            const InputRequiredResult(requestState: 'retry-state'),
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'needs-input').toJson(),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['resultType'], resultTypeInputRequired);
      expect(response.result['requestState'], 'retry-state');
    });

    test('stateless required legacy task tool resolves to final result',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      server.experimental.registerToolTask(
        'long',
        handler: CompletedTaskHandler(),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'long').toJson(),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['content'][0]['text'], 'task complete');
    });

    test('stateless tools/list omits legacy task execution metadata', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      server.registerTool(
        'echo',
        callback: (args, extra) => const CallToolResult(
          content: [TextContent(text: 'ok')],
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport
          .receive(JsonRpcListToolsRequest(id: 'tools', meta: _clientMeta()));
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      final tool = (response.result['tools'] as List).single as Map;
      expect(tool, isNot(contains('execution')));
    });

    test('stateless tools/list returns tools sorted by name', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      for (final name in ['zeta', 'alpha', 'middle']) {
        server.registerTool(
          name,
          callback: (args, extra) => const CallToolResult(
            content: [TextContent(text: 'ok')],
          ),
        );
      }
      final transport = RecordingTransport();
      await server.connect(transport);

      transport
          .receive(JsonRpcListToolsRequest(id: 'tools', meta: _clientMeta()));
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      final tools = response.result['tools'] as List;
      expect(tools.map((tool) => tool['name']), ['alpha', 'middle', 'zeta']);
    });

    test('tasks/update handler requires task extension capability', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(),
          ),
        ),
      );

      expect(
        () => server.setRequestHandler<JsonRpcUpdateTaskRequest>(
          Method.tasksUpdate,
          (request, extra) async => const TaskExtensionAcknowledgementResult(),
          (id, params, meta) => JsonRpcUpdateTaskRequest.fromJson({
            'id': id,
            'params': params,
            if (meta != null) '_meta': meta,
          }),
        ),
        throwsStateError,
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
      expect(
        validateToolRequest(_clientMeta(logLevel: 'verbose')),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains(McpMetaKey.logLevel),
        ),
      );
    });

    test('server rejects core RPCs removed from stateless MCP', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final removedRequests = <JsonRpcRequest>[
        JsonRpcRequest(
          id: 1,
          method: Method.initialize,
          params: const {
            'protocolVersion': draftProtocolVersion2026_07_28,
            'capabilities': <String, dynamic>{},
            'clientInfo': {'name': 'client', 'version': '1.0.0'},
          },
          meta: _clientMeta(),
        ),
        JsonRpcRequest(
          id: 2,
          method: Method.ping,
          meta: _clientMeta(),
        ),
        JsonRpcRequest(
          id: 3,
          method: Method.loggingSetLevel,
          params: const {'level': 'info'},
          meta: _clientMeta(),
        ),
        JsonRpcRequest(
          id: 4,
          method: Method.resourcesSubscribe,
          params: const {'uri': 'file:///tmp/example.txt'},
          meta: _clientMeta(),
        ),
        JsonRpcRequest(
          id: 5,
          method: Method.resourcesUnsubscribe,
          params: const {'uri': 'file:///tmp/example.txt'},
          meta: _clientMeta(),
        ),
      ];

      for (final request in removedRequests) {
        transport.sentMessages.clear();

        transport.receive(request);
        await _pump();

        final response = transport.sentMessages.single as JsonRpcError;
        expect(response.id, request.id);
        expect(response.error.code, ErrorCode.methodNotFound.value);
        expect(response.error.message, contains(request.method));
      }
    });

    test('server rejects notifications removed from stateless MCP', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      final errors = <Error>[];
      server.onerror = errors.add;
      final transport = RecordingTransport();
      await server.connect(transport);

      final initialized = JsonRpcMessage.fromJson({
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsInitialized,
        'params': {'_meta': _clientMeta()},
      }) as JsonRpcNotification;
      final rootsListChanged = JsonRpcMessage.fromJson({
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsRootsListChanged,
        'params': {'_meta': _clientMeta()},
      }) as JsonRpcNotification;

      expect(
        initialized.meta?[McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );
      expect(
        rootsListChanged.meta?[McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );

      for (final notification in [initialized, rootsListChanged]) {
        errors.clear();

        transport.receive(notification);
        await _pump();

        final error = errors.single as McpError;
        expect(error.code, ErrorCode.methodNotFound.value);
        expect(error.message, contains(notification.method));
      }
      expect(transport.sentMessages, isEmpty);
    });

    test('server gates stateless logging by request metadata', () async {
      late Server server;
      server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            logging: {},
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          await server.sendLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.debug,
              data: 'skip',
            ),
            requestMeta: extra.meta,
          );
          await server.sendLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.warning,
              data: 'emit',
            ),
            requestMeta: extra.meta,
          );
          return const ListToolsResult(tools: []);
        },
        (id, params, meta) => JsonRpcListToolsRequest(
          id: id,
          params: params,
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcListToolsRequest(
          id: 1,
          meta: _clientMeta(logLevel: 'warning'),
        ),
      );
      await _pump();

      expect(transport.sentMessages, hasLength(2));
      final loggingNotification =
          transport.sentMessages.first as JsonRpcNotification;
      expect(loggingNotification.method, Method.notificationsMessage);
      expect(loggingNotification.params?['level'], LoggingLevel.warning.name);
      expect(loggingNotification.params?['data'], 'emit');
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });

    test('server does not send stateless logging without request logLevel',
        () async {
      late Server server;
      server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(
            logging: {},
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          await server.sendLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.error,
              data: 'skip',
            ),
            requestMeta: extra.meta,
          );
          return const ListToolsResult(tools: []);
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

      expect(transport.sentMessages, hasLength(1));
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
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

    test('client rejects unrecognized stateless resultType values', () async {
      final transport = DiscoveringClientTransport(
        toolsListResult: const {
          'resultType': 'future_extension',
          'tools': [],
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await client.connect(transport);

      await expectLater(
        client.listTools(),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.internalError.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Failed to parse result for ${Method.toolsList}'),
              )
              .having(
                (error) => error.data.toString(),
                'data',
                contains('Unrecognized MCP resultType "future_extension"'),
              ),
        ),
      );
    });

    test('client rejects non-string stateless resultType values', () async {
      final transport = DiscoveringClientTransport(
        toolsListResult: const {
          'resultType': 42,
          'tools': [],
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await client.connect(transport);

      await expectLater(
        client.listTools(),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.internalError.value,
              )
              .having(
                (error) => error.data.toString(),
                'data',
                contains('MCP resultType must be a string'),
              ),
        ),
      );
    });

    test('client accepts advertised task extension resultType values',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
          extensions: withMcpTasksExtension(null),
        ),
        toolsListResult: const {
          'resultType': resultTypeTask,
          'tools': [],
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await client.connect(transport);

      final result = await client.listTools();
      expect(result.tools, isEmpty);
    });

    test('stable client sessions do not validate future resultType values',
        () async {
      final transport = LegacyFallbackTransport(
        toolsListResult: const {
          'resultType': 'future_extension',
          'tools': [],
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(useServerDiscover: true),
      );

      await client.connect(transport);

      final result = await client.listTools();
      expect(client.getProtocolVersion(), stableProtocolVersion2025_11_25);
      expect(result.tools, isEmpty);
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

    test(
        'client retries discovery with advertised compatible stateless version',
        () async {
      final transport = DiscoveringClientTransport(
        unsupportedDiscoverProtocolVersions: const ['1900-01-01'],
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocolVersion: '1900-01-01',
          useServerDiscover: true,
        ),
      );

      await client.connect(transport);

      final discoverRequests = transport.sentMessages
          .whereType<JsonRpcRequest>()
          .where((message) => message.method == Method.serverDiscover)
          .toList();
      expect(discoverRequests, hasLength(2));
      expect(
        discoverRequests.map(
          (request) => request.meta?[McpMetaKey.protocolVersion],
        ),
        ['1900-01-01', draftProtocolVersion2026_07_28],
      );
      expect(client.getProtocolVersion(), draftProtocolVersion2026_07_28);
      expect(transport.protocolVersion, draftProtocolVersion2026_07_28);
      expect(
        transport.sentMessages.whereType<JsonRpcRequest>().map(
              (message) => message.method,
            ),
        isNot(contains(Method.initialize)),
      );
    });

    for (final scenario in [
      (
        name: 'malformed error data',
        requested: '1900-01-01',
        discoverVersions: const [draftProtocolVersion2026_07_28],
        data: 'not-an-object',
      ),
      (
        name: 'missing supported versions',
        requested: '1900-01-01',
        discoverVersions: const [draftProtocolVersion2026_07_28],
        data: const {'requested': '1900-01-01'},
      ),
      (
        name: 'no compatible stateless version',
        requested: '1900-01-01',
        discoverVersions: const ['1900-01-01'],
        data: null,
      ),
      (
        name: 'advertised version matches rejected request',
        requested: draftProtocolVersion2026_07_28,
        discoverVersions: const [draftProtocolVersion2026_07_28],
        data: const {
          'supported': [draftProtocolVersion2026_07_28],
          'requested': draftProtocolVersion2026_07_28,
        },
      ),
    ]) {
      test(
        'client does not fall back to initialize after unsupported discovery '
        '${scenario.name}',
        () async {
          final transport = DiscoveringClientTransport(
            discoverVersions: scenario.discoverVersions,
            unsupportedDiscoverProtocolVersions: [scenario.requested],
            unsupportedDiscoverData: scenario.data,
          );
          final client = McpClient(
            const Implementation(name: 'client', version: '1.0.0'),
            options: McpClientOptions(
              protocolVersion: scenario.requested,
              useServerDiscover: true,
            ),
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
          expect(
            transport.sentMessages.whereType<JsonRpcRequest>().map(
                  (message) => message.method,
                ),
            isNot(contains(Method.initialize)),
          );
        },
      );
    }

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
