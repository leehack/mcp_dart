import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/server/tasks.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

const _removedDraftProtocolVersion2026V1 = 'DRAFT-2026-v1';

class PlainRecordingTransport extends Transport {
  PlainRecordingTransport({this.sessionIdValue});

  final List<JsonRpcMessage> sentMessages = [];
  final List<int?> sentRelatedRequestIds = [];
  final String? sessionIdValue;
  bool started = false;
  bool closed = false;

  @override
  String? get sessionId => sessionIdValue;

  @override
  Future<void> close() async {
    closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    sentRelatedRequestIds.add(relatedRequestId);
  }

  @override
  Future<void> start() async {
    started = true;
  }

  void receive(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

class RecordingTransport extends PlainRecordingTransport
    implements ServerSubscriptionCancellationTransport {
  RecordingTransport({super.sessionIdValue});
}

class AcknowledgmentGateTransport extends RecordingTransport {
  final Completer<void> acknowledgmentStarted = Completer<void>();
  final Completer<void> releaseAcknowledgment = Completer<void>();

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (message is JsonRpcNotification &&
        message.method == Method.notificationsSubscriptionsAcknowledged) {
      sentMessages.add(message);
      sentRelatedRequestIds.add(relatedRequestId);
      if (!acknowledgmentStarted.isCompleted) {
        acknowledgmentStarted.complete();
      }
      await releaseAcknowledgment.future;
      return;
    }
    await super.send(message, relatedRequestId: relatedRequestId);
  }
}

class CloseGateTransport extends RecordingTransport {
  final Completer<void> closeStarted = Completer<void>();
  final Completer<void> releaseClose = Completer<void>();
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    if (!closeStarted.isCompleted) {
      closeStarted.complete();
    }
    await releaseClose.future;
    await super.close();
  }
}

class EarlyCloseGateTransport extends RecordingTransport {
  final Completer<void> closeStarted = Completer<void>();
  final Completer<void> releaseClose = Completer<void>();
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    await super.close();
    if (!closeStarted.isCompleted) {
      closeStarted.complete();
    }
    await releaseClose.future;
  }
}

class CancellationGateTransport extends RecordingTransport {
  final Completer<void> cancellationStarted = Completer<void>();
  final Completer<void> releaseCancellation = Completer<void>();
  final List<String> lifecycleEvents = [];

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (message is JsonRpcNotification &&
        message.method == Method.notificationsSubscriptionsAcknowledged) {
      lifecycleEvents.add('acknowledgment');
    } else if (message is JsonRpcNotification &&
        message.method == Method.notificationsCancelled) {
      lifecycleEvents.add('cancellation');
      sentMessages.add(message);
      sentRelatedRequestIds.add(relatedRequestId);
      if (!cancellationStarted.isCompleted) {
        cancellationStarted.complete();
      }
      await releaseCancellation.future;
      return;
    } else if (message is JsonRpcResponse) {
      lifecycleEvents.add('response');
    }
    await super.send(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> close() async {
    lifecycleEvents.add('close');
    await super.close();
  }
}

class ValidationRecordingTransport extends RecordingTransport
    implements IncomingRequestValidationAwareTransport {
  McpError? Function(JsonRpcRequest request)? incomingRequestValidator;
  bool Function(String method)? requestMethodSupported;

  @override
  void setIncomingRequestValidator(
    McpError? Function(JsonRpcRequest request) validator,
  ) {
    incomingRequestValidator = validator;
  }

  @override
  void setRequestMethodSupported(bool Function(String method) isSupported) {
    requestMethodSupported = isSupported;
  }
}

class SessionRecordingTaskStore extends InMemoryTaskStore {
  final List<String?> createTaskSessionIds = [];
  final List<String?> updateTaskStatusSessionIds = [];

  @override
  Future<Task> createTask(
    TaskCreation taskParams,
    RequestId requestId,
    Map<String, dynamic> requestData,
    String? sessionId,
  ) {
    createTaskSessionIds.add(sessionId);
    return super.createTask(taskParams, requestId, requestData, sessionId);
  }

  @override
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
    String? sessionId,
  ]) {
    updateTaskStatusSessionIds.add(sessionId);
    return super.updateTaskStatus(taskId, status, statusMessage, sessionId);
  }
}

class DiscoveringClientTransport extends Transport
    implements ProtocolVersionAwareTransport {
  DiscoveringClientTransport({
    this.discoverVersions = const [previewProtocolVersion],
    this.unsupportedDiscoverProtocolVersions = const [],
    this.unsupportedDiscoverData,
    this.capabilities = const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
    this.discoverCapabilitiesJson,
    this.discoverServerInfo =
        const Implementation(name: 'server', version: '1.0.0'),
    this.toolsListResult = const {
      'resultType': resultTypeComplete,
      'tools': [],
      'ttlMs': 0,
      'cacheScope': CacheScope.private,
    },
    this.onRequest,
  });

  final List<String> discoverVersions;
  final List<String> unsupportedDiscoverProtocolVersions;
  final Object? unsupportedDiscoverData;
  final ServerCapabilities capabilities;
  final Map<String, dynamic>? discoverCapabilitiesJson;
  final Implementation? discoverServerInfo;
  final Map<String, dynamic> toolsListResult;
  final void Function(JsonRpcRequest request)? onRequest;
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

      final result = DiscoverResult(
        supportedVersions: discoverVersions,
        capabilities: capabilities,
        serverInfo: discoverServerInfo,
        ttlMs: 0,
        cacheScope: CacheScope.private,
      ).toJson();
      if (discoverCapabilitiesJson != null) {
        result['capabilities'] = discoverCapabilitiesJson;
      }
      onmessage?.call(JsonRpcResponse(id: message.id, result: result));
      return;
    }

    if (message is JsonRpcRequest && message.method == Method.toolsList) {
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: toolsListResult,
        ),
      );
      return;
    }

    if (message is JsonRpcRequest) {
      onRequest?.call(message);
    }
  }

  @override
  Future<void> start() async {}
}

class LegacyFallbackTransport extends Transport
    implements ProtocolVersionAwareTransport {
  LegacyFallbackTransport({
    this.discoveryError,
    this.toolsListResult = const {'tools': []},
    this.capabilities = const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
    this.onRequest,
  });

  final McpError? discoveryError;
  final Map<String, dynamic> toolsListResult;
  final ServerCapabilities capabilities;
  final void Function(JsonRpcRequest request)? onRequest;
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
      final error = discoveryError;
      if (error != null) {
        throw error;
      }
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
          result: InitializeResult(
            protocolVersion: latestInitializationProtocolVersion,
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
      return;
    }

    if (message is JsonRpcRequest) {
      onRequest?.call(message);
    }
  }

  @override
  Future<void> start() async {}
}

class CompletedTaskHandler extends CancelTaskResultHandler {
  RequestHandlerExtra? lastCreateTaskExtra;

  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    lastCreateTaskExtra = extra;
    return const CreateTaskResult(
      task: Task(
        taskId: 'task-1',
        status: TaskStatus.completed,
        ttl: null,
        createdAt: '2026-07-28T00:00:00Z',
        lastUpdatedAt: '2026-07-28T00:01:00Z',
      ),
    );
  }

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

class LegacyMetadataResult implements BaseResultData {
  @override
  final Map<String, dynamic>? meta;
  final Map<String, dynamic>? serializedMeta;

  const LegacyMetadataResult({this.meta, this.serializedMeta});

  @override
  Map<String, dynamic> toJson() => {
        'tools': <dynamic>[],
        if (serializedMeta != null) '_meta': serializedMeta,
      };
}

class UnserializableSubscriptionResult implements BaseResultData {
  const UnserializableSubscriptionResult();

  @override
  Map<String, dynamic>? get meta => null;

  @override
  Map<String, dynamic> toJson() {
    throw StateError('sentinel subscription serialization failure');
  }
}

Map<String, dynamic> _clientMeta({
  String? protocolVersion,
  Implementation clientInfo = const Implementation(
    name: 'client',
    version: '1.0.0',
  ),
  ClientCapabilities clientCapabilities = const ClientCapabilities(),
  Map<String, dynamic>? meta,
  Object? logLevel,
}) {
  return buildProtocolRequestMeta(
    protocolVersion: protocolVersion ?? previewProtocolVersion,
    clientInfo: clientInfo,
    clientCapabilities: clientCapabilities,
    meta: meta,
    logLevel: logLevel,
  );
}

const _allSubscriptionFilter = SubscriptionFilter(
  toolsListChanged: true,
  promptsListChanged: true,
  resourcesListChanged: true,
  resourceSubscriptions: ['file:///resource'],
  taskIds: ['task-1'],
);

List<JsonRpcNotification> _subscriptionDataNotifications() => [
      const JsonRpcToolListChangedNotification(),
      const JsonRpcPromptListChangedNotification(),
      const JsonRpcResourceListChangedNotification(),
      JsonRpcResourceUpdatedNotification(
        updatedParams: const ResourceUpdatedNotification(
          uri: 'file:///resource',
        ),
      ),
      JsonRpcTaskNotification(
        task: const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.working,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:00:00Z',
          ttlMs: null,
        ),
      ),
    ];

Map<String, dynamic> _serializeStatelessResult(
  BaseResultData result, {
  JsonRpcRequest? request,
}) {
  final server = Server(
    const Implementation(name: 'configured', version: '1.0.0'),
    options: const McpServerOptions(protocol: McpProtocol.require2026),
  );
  return server.serializeIncomingResult(
    request ?? JsonRpcListToolsRequest(id: 1, meta: _clientMeta()),
    result,
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void _registerTaskGetExtensionHandler(Server server) {
  server.setRequestHandler<JsonRpcGetTaskRequest>(
    Method.tasksGet,
    (request, extra) async => GetTaskExtensionResult(
      task: TaskExtensionTask(
        taskId: request.getParams.taskId,
        status: TaskStatus.working,
        createdAt: '2026-07-28T00:00:00Z',
        lastUpdatedAt: '2026-07-28T00:00:00Z',
        ttlMs: null,
      ),
    ),
    (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
      'jsonrpc': jsonRpcVersion,
      'id': id,
      'method': Method.tasksGet,
      'params': params,
      if (meta != null) '_meta': meta,
    }),
  );
}

void main() {
  group('MCP 2026-07-28 protocol foundation', () {
    test('rejects a negative graceful shutdown timeout', () {
      expect(
        () => Server(
          const Implementation(name: 'server', version: '1.0.0'),
          options: const McpServerOptions(
            gracefulShutdownTimeout: Duration(milliseconds: -1),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('distinguishes preview, stable, and default versions', () {
      expect(defaultProtocolVersion, previewProtocolVersion);
      expect(McpProtocol.values, [
        McpProtocol.stable,
        McpProtocol.legacy,
        McpProtocol.require2026,
      ]);
      expect(const McpClientOptions().protocol, McpProtocol.stable);
      expect(const McpClientOptions().useServerDiscover, isTrue);
      expect(
        const McpClientOptions(
          protocolVersion: latestInitializationProtocolVersion,
        ).useServerDiscover,
        isFalse,
      );
      expect(
        const McpClientOptions(
          protocolVersion: latestInitializationProtocolVersion,
          useServerDiscover: true,
        ).useServerDiscover,
        isTrue,
      );
      expect(
        const McpClientOptions(
          protocol: McpProtocol.require2026,
          protocolVersion: latestInitializationProtocolVersion,
        ).useServerDiscover,
        isTrue,
      );
      const strictOptionsWithLegacyOverrides = McpClientOptions(
        protocol: McpProtocol.require2026,
        useServerDiscover: false,
        allowLegacyInitializationFallback: true,
      );
      expect(strictOptionsWithLegacyOverrides.useServerDiscover, isTrue);
      expect(
        strictOptionsWithLegacyOverrides.allowLegacyInitializationFallback,
        isFalse,
      );
      expect(const McpServerOptions().protocol, McpProtocol.stable);
      expect(
        const McpServerOptions().supportedVersions,
        contains(previewProtocolVersion),
      );
      expect(
        allSupportedProtocolVersions,
        contains(previewProtocolVersion),
      );
      expect(statelessProtocolVersions, [previewProtocolVersion]);
      expect(isStatelessProtocolVersion(previewProtocolVersion), true);
      expect(
        isStatelessProtocolVersion(_removedDraftProtocolVersion2026V1),
        false,
      );
      expect(isStatelessProtocolVersion(defaultProtocolVersion), true);
      expect(McpProtocol.stable.supportsStatelessProtocol, true);
      expect(McpProtocol.legacy.supportsStatelessProtocol, false);
      expect(McpProtocol.require2026.supportsStatelessProtocol, true);
    });

    test('legacy profile remains an explicit development opt-out', () async {
      final transport = LegacyFallbackTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.legacy),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), latestInitializationProtocolVersion);
      expect(transport.protocolVersion, latestInitializationProtocolVersion);
      expect(
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        [Method.initialize],
      );
      expect(
        const McpServerOptions(protocol: McpProtocol.legacy).supportedVersions,
        isNot(contains(previewProtocolVersion)),
      );
    });

    test('builds stateless request metadata without dropping caller metadata',
        () {
      final meta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientInfo: const Implementation(name: 'client', version: '1.0.0'),
        clientCapabilities: const ClientCapabilities(),
        meta: const {
          'caller': 'value',
          'com.example.trace/id': 'trace-1',
        },
        logLevel: 'debug',
      );

      expect(meta['caller'], 'value');
      expect(meta['com.example.trace/id'], 'trace-1');
      expect(
        meta[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
      expect(meta[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
      expect(meta[McpMetaKey.clientCapabilities], <String, dynamic>{});
      expect(meta[McpMetaKey.logLevel], 'debug');
    });

    test('builds stateless request metadata without client identity', () {
      final meta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientCapabilities: const ClientCapabilities(),
      );

      expect(meta[McpMetaKey.protocolVersion], previewProtocolVersion);
      expect(meta[McpMetaKey.clientCapabilities], <String, dynamic>{});
      expect(meta, isNot(contains(McpMetaKey.clientInfo)));
    });

    test('typed client identity owns the reserved request metadata key', () {
      for (final rawClientInfo in <Object?>[
        null,
        'malformed',
        const {'name': 'raw-client', 'version': '1.0.0'},
      ]) {
        final callerMeta = <String, dynamic>{
          McpMetaKey.clientInfo: rawClientInfo,
          'com.example.trace/id': 'trace-1',
        };
        final meta = buildProtocolRequestMeta(
          protocolVersion: previewProtocolVersion,
          clientCapabilities: const ClientCapabilities(),
          meta: callerMeta,
        );

        expect(meta, isNot(contains(McpMetaKey.clientInfo)));
        expect(meta['com.example.trace/id'], 'trace-1');
        expect(callerMeta[McpMetaKey.clientInfo], equals(rawClientInfo));
      }

      final meta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientInfo: const Implementation(
          name: 'typed-client',
          version: '2.0.0',
        ),
        clientCapabilities: const ClientCapabilities(),
        meta: const {McpMetaKey.clientInfo: 'malformed'},
      );
      expect(meta[McpMetaKey.clientInfo], {
        'name': 'typed-client',
        'version': '2.0.0',
      });
    });

    test('response serialization preserves and merges result metadata', () {
      const response = JsonRpcResponse(
        id: 1,
        result: {
          '_meta': {
            'com.example/result': true,
            'com.example/shared': 'result',
          },
        },
        meta: {
          'com.example/response': true,
          'com.example/shared': 'response',
        },
      );

      final result = response.toJson()['result'] as Map<String, dynamic>;
      expect(result['_meta'], {
        'com.example/result': true,
        'com.example/response': true,
        'com.example/shared': 'response',
      });

      const emptyResponseMeta = JsonRpcResponse(id: 2, result: {}, meta: {});
      expect(
        emptyResponseMeta.toJson()['result'],
        containsPair('_meta', <String, dynamic>{}),
      );
      const emptyResultMeta = JsonRpcResponse(
        id: 3,
        result: {'_meta': <String, dynamic>{}},
      );
      expect(
        emptyResultMeta.toJson()['result'],
        containsPair('_meta', <String, dynamic>{}),
      );
    });

    test('response metadata wins after result metadata merge', () {
      const response = JsonRpcResponse(
        id: 1,
        result: {
          '_meta': {McpMetaKey.serverInfo: 'overridden-malformed-value'},
        },
        meta: {
          McpMetaKey.serverInfo: {
            'name': 'response-server',
            'version': '2.0.0',
          },
        },
      );

      final result = response.toJson()['result'] as Map<String, dynamic>;
      expect((result['_meta'] as Map)[McpMetaKey.serverInfo], {
        'name': 'response-server',
        'version': '2.0.0',
      });
    });

    test('rejects invalid 2026 request metadata keys during construction', () {
      for (final key in [
        '/name',
        '1bad/name',
        'bad prefix/value',
        'com.example./name',
        'com.example/name_',
      ]) {
        expect(
          () => buildProtocolRequestMeta(
            protocolVersion: previewProtocolVersion,
            clientInfo: const Implementation(
              name: 'client',
              version: '1.0.0',
            ),
            clientCapabilities: const ClientCapabilities(),
            meta: {key: 'value'},
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(key),
            ),
          ),
        );
      }
    });

    test('request parsing does not let top-level metadata override params', () {
      final parsed = JsonRpcMessage.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': 'tools',
        'method': Method.toolsList,
        '_meta': {
          McpMetaKey.protocolVersion: defaultProtocolVersion,
        },
        'params': {
          '_meta': _clientMeta(),
        },
      });

      expect(parsed, isA<JsonRpcListToolsRequest>());
      final request = parsed as JsonRpcListToolsRequest;
      expect(
        request.meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
      expect(request.meta?[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
    });

    test('valid params metadata ignores a malformed top-level fallback', () {
      final parsed = JsonRpcMessage.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': 'tools',
        'method': Method.toolsList,
        '_meta': 'unrelated-extension-value',
        'params': {'_meta': _clientMeta()},
      });

      expect(parsed, isA<JsonRpcListToolsRequest>());
      expect(
        (parsed as JsonRpcListToolsRequest).meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
    });

    test('preserves integer request ids and progress tokens', () {
      final message = JsonRpcMessage.fromJson(
        const {
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.toolsList,
          'params': {
            '_meta': {'progressToken': 2},
          },
        },
      );

      expect(message, isA<JsonRpcListToolsRequest>());
      final request = message as JsonRpcListToolsRequest;
      expect(request.id, 1);
      expect(request.progressToken, 2);
      expect(request.toJson()['id'], 1);
      expect(request.toJson()['params']['_meta']['progressToken'], 2);
    });

    test('rejects URL elicitation relative URI values', () {
      expect(
        () => ElicitRequestParams.fromJson(
          {
            'mode': 'url',
            'message': 'Open browser',
            'url': 'authorize/callback',
          },
          protocolVersion: previewProtocolVersion,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitRequestParams.url(
          message: 'Open browser',
          url: 'authorize/callback',
        ).toJson(protocolVersion: previewProtocolVersion),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('uses draft URL elicitation shape without elicitationId', () {
      final parsed = JsonRpcElicitRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': 1,
        'method': Method.elicitationCreate,
        'params': {
          'mode': 'url',
          'message': 'Open browser',
          'url': 'https://example.com/authorize',
          '_meta': {
            McpMetaKey.protocolVersion: previewProtocolVersion,
          },
        },
      });
      expect(parsed.elicitParams.isUrlMode, isTrue);
      expect(parsed.elicitParams.elicitationId, isNull);

      final serialized = const ElicitRequestParams.url(
        message: 'Open browser',
        url: 'https://example.com/authorize',
      ).toJson(protocolVersion: previewProtocolVersion);
      expect(serialized, isNot(contains('elicitationId')));
      expect(serialized['mode'], 'url');
      expect(serialized['url'], 'https://example.com/authorize');

      expect(
        () => JsonRpcElicitRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.elicitationCreate,
          'params': {
            'mode': 'url',
            'message': 'Open browser',
            'url': 'https://example.com/authorize',
            'elicitationId': 'legacy-id',
            '_meta': {
              McpMetaKey.protocolVersion: previewProtocolVersion,
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRpcElicitRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.elicitationCreate,
          'params': {
            'mode': 'url',
            'message': 'Open browser',
            'url': 'https://example.com/authorize',
            'elicitationId': null,
            '_meta': {
              McpMetaKey.protocolVersion: previewProtocolVersion,
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitRequestParams.url(
          message: 'Open browser',
          url: 'https://example.com/authorize',
          elicitationId: 'legacy-id',
        ).toJson(protocolVersion: previewProtocolVersion),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not classify removed elicitation completion notification', () {
      final parsed = JsonRpcMessage.fromJson({
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsElicitationComplete,
        'params': {'elicitationId': 'legacy-id'},
      });

      expect(parsed, isA<JsonRpcNotification>());
      expect(parsed, isNot(isA<JsonRpcElicitationCompleteNotification>()));
      expect(
        (parsed as JsonRpcNotification).method,
        Method.notificationsElicitationComplete,
      );
    });

    test('accepts fractional elicitation number schema keywords', () {
      final request = ElicitRequestParams.form(
        message: 'Configure ratio',
        requestedSchema: JsonSchema.object(
          properties: {
            'ratio': JsonSchema.number(
              minimum: 0.1,
              maximum: 0.9,
              defaultValue: 0.5,
            ),
          },
        ),
      );

      final requestJson = request.toJson(
        protocolVersion: previewProtocolVersion,
      );
      final ratioSchema = requestJson['requestedSchema']['properties']['ratio'];
      expect(ratioSchema['minimum'], 0.1);
      expect(ratioSchema['maximum'], 0.9);
      expect(ratioSchema['default'], 0.5);

      final inputRequestJson = InputRequest.elicit(request).toJson();
      final inputRatioSchema =
          inputRequestJson['params']['requestedSchema']['properties']['ratio'];
      expect(inputRatioSchema['minimum'], 0.1);

      final parsed = JsonRpcElicitRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': 1,
        'method': Method.elicitationCreate,
        'params': {
          'message': 'Configure ratio',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'count': {
                'type': 'integer',
                'maximum': 10.5,
              },
            },
          },
          '_meta': {
            McpMetaKey.protocolVersion: previewProtocolVersion,
          },
        },
      });
      final countSchema =
          parsed.elicitParams.requestedSchema!.toJson()['properties']['count'];
      expect(countSchema['maximum'], 10.5);

      expect(
        () => JsonRpcElicitRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.elicitationCreate,
          'params': {
            'message': 'Configure ratio',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'count': {
                  'type': 'integer',
                  'maximum': double.infinity,
                },
              },
            },
            '_meta': {
              McpMetaKey.protocolVersion: previewProtocolVersion,
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed elicitation wire shapes', () {
      final elicitParams = {
        'message': 'Choose option',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'option': {'type': 'string'},
          },
        },
      };
      final completeParams = {'elicitationId': 'elicitation-1'};

      for (final parse in <Object Function()>[
        () => JsonRpcElicitRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.elicitationCreate,
              'params': 'bad',
            }),
        () => JsonRpcElicitRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.elicitationCreate,
              'params': null,
            }),
        () => JsonRpcElicitRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.elicitationCreate,
              'params': elicitParams,
            }),
        () => JsonRpcElicitRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.samplingCreateMessage,
              'params': elicitParams,
            }),
        () => ElicitRequest.fromJson({
              'message': 'Bad properties',
              'requestedSchema': {
                'type': 'object',
                'properties': <Object?, Object?>{
                  1: {'type': 'string'},
                },
              },
            }),
        () => ElicitResult.fromJson({
              'action': 'accept',
              'url': 1,
            }),
        () => ElicitResult.fromJson({
              'action': 'accept',
              'content': <Object?, Object?>{1: 'bad'},
            }),
        () => ElicitationCompleteNotification.fromJson({
              'elicitationId': 1,
            }),
        () => JsonRpcElicitationCompleteNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsElicitationComplete,
              'params': 'bad',
            }),
        () => JsonRpcElicitationCompleteNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsElicitationComplete,
              'params': completeParams,
            }),
        () => JsonRpcElicitationCompleteNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsInitialized,
              'params': completeParams,
            }),
        () => URLElicitationRequiredErrorData.fromJson({
              'elicitations': [1],
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });

    test('embedded MRTR input requests keep method and params shape', () {
      final elicitInput = InputRequest.fromJson({
        'method': Method.elicitationCreate,
        'params': {
          'message': 'Choose option',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'option': {'type': 'string'},
            },
          },
        },
      });
      final samplingInput = InputRequest.fromJson({
        'method': Method.samplingCreateMessage,
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Hello'},
            },
          ],
          'maxTokens': 16,
        },
      });

      expect(elicitInput.elicitParams.message, 'Choose option');
      expect(samplingInput.createMessageParams.maxTokens, 16);
    });

    test('rejects non-finite JSON numbers', () {
      expect(
        () => ProgressNotification.fromJson({
          'progressToken': 'progress-1',
          'progress': double.nan,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ProgressNotification(
          progressToken: 'progress-1',
          progress: double.infinity,
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CreateMessageRequest.fromJson({
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Hello'},
            },
          ],
          'maxTokens': 16,
          'temperature': double.nan,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitResult.fromJson({
          'action': 'accept',
          'content': {'score': double.infinity},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        ElicitResult.fromJson({
          'action': 'accept',
          'content': {'score': 1.5},
        }).content,
        containsPair('score', 1.5),
      );
      expect(
        () => const ElicitResult(
          action: 'accept',
          content: {'score': double.nan},
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        const ElicitResult(
          action: 'accept',
          content: {'score': 1.5},
        ).toJson()['content'],
        containsPair('score', 1.5),
      );
    });

    test('rejects non-JSON sampling object values', () {
      expect(
        () => SamplingToolUseContent.fromJson({
          'type': 'tool_use',
          'id': 'call-1',
          'name': 'lookup',
          'input': {'query': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingMessage.fromJson({
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
          '_meta': {'provider': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      final createMessageParams = {
        'messages': [
          {
            'role': 'user',
            'content': {'type': 'text', 'text': 'Hello'},
          },
        ],
        'maxTokens': 16,
      };
      expect(
        () => JsonRpcCreateMessageRequest.fromJson({
          'jsonrpc': '1.0',
          'id': 1,
          'method': Method.samplingCreateMessage,
          'params': createMessageParams,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRpcCreateMessageRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.elicitationCreate,
          'params': createMessageParams,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageResult.fromJson({
          'role': 'assistant',
          'content': {'type': 'text', 'text': 'Hello'},
          'model': 'model-x',
          '_meta': {'provider': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequest.fromJson({
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Hello'},
            },
          ],
          'maxTokens': 16,
          'metadata': {'provider': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ModelHint.fromJson({'name': 1}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingContent.fromJson({
          'type': 'text',
          'text': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingTextContent.fromJson({
          'text': 'Hello',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingTextContent.fromJson({
          'type': 'image',
          'text': 'Hello',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingImageContent.fromJson({
          'type': 'text',
          'data': 'aW1nZGF0YQ==',
          'mimeType': 'image/png',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingAudioContent.fromJson({
          'type': 'image',
          'data': 'YXVkaW8tZGF0YQ==',
          'mimeType': 'audio/wav',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingToolUseContent.fromJson({
          'type': 'tool_result',
          'id': 'call-1',
          'name': 'search',
          'input': <String, dynamic>{},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingToolResultContent.fromJson({
          'type': 'tool_use',
          'toolUseId': 'call-1',
          'content': [
            {'type': 'text', 'text': 'Hello'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingToolResultContent.fromJson({
          'type': 'tool_result',
          'toolUseId': 'call-1',
          'content': [
            {'type': 'text', 'text': 'Hello'},
          ],
          'isError': 'false',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequest.fromJson({
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Hello'},
            },
          ],
          'maxTokens': 16,
          'stopSequences': ['STOP', 1],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageResult.fromJson({
          'role': 'assistant',
          'content': {'type': 'text', 'text': 'Hello'},
          'model': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Content.fromJson({
          'type': 1,
          'text': 'Hello',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Content.fromJson({
          'text': 'Hello',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Content.fromJson({
          'type': 'unknown',
          'text': 'Hello',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TextContent.fromJson({
          'type': 'image',
          'text': 'Hello',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TextContent.fromJson({
          'type': 'text',
          'text': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceContents.fromJson({
          'uri': 'file:///docs/readme.md',
          'text': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceContents.fromJson({
          'uri': 'file:///docs/readme.md',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceLink.fromJson({
          'type': 'resource_link',
          'uri': 'file:///docs/readme.md',
          'name': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceLink.fromJson({
          'type': 'resource',
          'uri': 'file:///docs/readme.md',
          'name': 'readme',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Resource.fromJson({
          'uri': 'file:///docs/readme.md',
          'name': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceTemplate.fromJson({
          'uriTemplate': 'file:///{path}',
          'name': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-JSON content object values', () {
      expect(
        () => TextContent.fromJson({
          'type': 'text',
          'text': 'Hello',
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceContents.fromJson({
          'uri': 'file:///docs/readme.md',
          'text': 'README body',
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceLink.fromJson({
          'type': 'resource_link',
          'uri': 'file:///docs/readme.md',
          'name': 'readme',
          'annotations': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-JSON result metadata values', () {
      expect(
        () => DiscoverResult.fromJson({
          'resultType': 'complete',
          'supportedVersions': [previewProtocolVersion],
          'capabilities': <String, dynamic>{},
          'serverInfo': {'name': 'server', 'version': '1.0.0'},
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const DiscoverResult(
          supportedVersions: [previewProtocolVersion],
          capabilities: ServerCapabilities(),
          serverInfo: Implementation(name: 'server', version: '1.0.0'),
          meta: {'bad': Object()},
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRpcMessage.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'result': {
            'resultType': 'complete',
            '_meta': {'bad': Object()},
          },
        }),
        throwsA(isA<FormatException>()),
      );
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
        previewProtocolVersion,
      );
      expect(
        requestJson['params']['_meta'][McpMetaKey.clientCapabilities],
        <String, dynamic>{},
      );

      final result = const DiscoverResult(
        supportedVersions: [previewProtocolVersion],
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        serverInfo: Implementation(name: 'server', version: '1.0.0'),
        instructions: 'Use the tools.',
        ttlMs: 1000,
        cacheScope: CacheScope.public,
      );
      final resultJson = result.toJson();
      expect(resultJson['resultType'], 'complete');
      expect(
        resultJson['supportedVersions'],
        [previewProtocolVersion],
      );
      expect(resultJson['capabilities'], {'tools': <String, dynamic>{}});
      expect(resultJson, isNot(contains('serverInfo')));
      expect(resultJson['_meta'], {
        McpMetaKey.serverInfo: {
          'name': 'server',
          'version': '1.0.0',
        },
      });
      expect(resultJson['ttlMs'], 1000);
      expect(resultJson['cacheScope'], CacheScope.public);
      final parsedResult = DiscoverResult.fromJson(resultJson);
      expect(parsedResult.serverInfo?.name, 'server');
      expect(
        parsedResult.instructions,
        'Use the tools.',
      );
      expect(parsedResult.ttlMs, 1000);
      expect(parsedResult.cacheScope, CacheScope.public);

      final identityFreeResult = DiscoverResult.fromJson({
        'resultType': resultTypeComplete,
        'supportedVersions': [previewProtocolVersion],
        'capabilities': <String, dynamic>{},
      });
      expect(identityFreeResult.serverInfo, isNull);

      for (final malformedServerInfo in <Object?>[
        null,
        'malformed',
        const {'name': 'missing-version'},
      ]) {
        expect(
          () => DiscoverResult.fromJson({
            'resultType': resultTypeComplete,
            'supportedVersions': [previewProtocolVersion],
            'capabilities': <String, dynamic>{},
            '_meta': {
              McpMetaKey.serverInfo: malformedServerInfo,
              'com.example/trace': 'trace-1',
            },
          }),
          throwsFormatException,
        );
      }

      expect(
        () => DiscoverResult.fromJson({
          'resultType': resultTypeComplete,
          'supportedVersions': [previewProtocolVersion],
          'capabilities': <String, dynamic>{},
          '_meta': {McpMetaKey.serverInfo: 'malformed'},
          'serverInfo': {'name': 'legacy-server', 'version': '1.0.0'},
        }),
        throwsFormatException,
      );

      final explicitEmptyMeta = const DiscoverResult(
        supportedVersions: [previewProtocolVersion],
        capabilities: ServerCapabilities(),
        meta: <String, dynamic>{},
      ).toJson();
      expect(explicitEmptyMeta, containsPair('_meta', <String, dynamic>{}));

      // Temporary compatibility for the pinned TypeScript and Python beta
      // fixtures. Remove once corrected SDK releases are pinned.
      final legacyIdentity = DiscoverResult.fromJson({
        'resultType': resultTypeComplete,
        'supportedVersions': [previewProtocolVersion],
        'capabilities': <String, dynamic>{},
        'serverInfo': {'name': 'legacy-server', 'version': '1.0.0'},
      });
      expect(legacyIdentity.serverInfo?.name, 'legacy-server');

      final handlerIdentity = const DiscoverResult(
        supportedVersions: [previewProtocolVersion],
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'configured', version: '1.0.0'),
        meta: {
          McpMetaKey.serverInfo: {
            'name': 'handler',
            'version': '2.0.0',
          },
        },
      ).toJson();
      expect(handlerIdentity['_meta'][McpMetaKey.serverInfo], {
        'name': 'handler',
        'version': '2.0.0',
      });

      final anonymousOverride = const DiscoverResult(
        supportedVersions: [previewProtocolVersion],
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'configured', version: '1.0.0'),
        meta: {
          McpMetaKey.serverInfo: null,
          'com.example/trace': 'trace-1',
        },
      ).toJson();
      expect(anonymousOverride['_meta'], {
        'com.example/trace': 'trace-1',
      });

      for (final malformedServerInfo in <Object>[
        'malformed',
        const <String, dynamic>{'name': 'missing-version'},
      ]) {
        expect(
          () => DiscoverResult(
            supportedVersions: const [previewProtocolVersion],
            capabilities: const ServerCapabilities(),
            meta: {McpMetaKey.serverInfo: malformedServerInfo},
          ).toJson(),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('stateless metadata omits legacy task capabilities', () {
      const clientCapabilities = ClientCapabilities(
        sampling: ClientCapabilitiesSampling(tools: true),
        roots: ClientCapabilitiesRoots(listChanged: true),
        tasks: ClientCapabilitiesTasks(
          cancel: true,
          list: true,
          requests: ClientCapabilitiesTasksRequests(
            sampling: ClientCapabilitiesTasksSampling(
              createMessage: ClientCapabilitiesTasksSamplingCreateMessage(),
            ),
          ),
        ),
        extensions: {mcpTasksExtensionId: {}},
      );
      expect(clientCapabilities.toJson(), contains('tasks'));

      final draftMeta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientInfo: const Implementation(name: 'client', version: '1.0.0'),
        clientCapabilities: clientCapabilities,
      );
      final draftCapabilities =
          draftMeta[McpMetaKey.clientCapabilities] as Map<String, dynamic>;
      expect(draftCapabilities, isNot(contains('tasks')));
      expect(draftCapabilities['roots'], isNot(contains('listChanged')));
      expect(
        (draftCapabilities['extensions'] as Map)[mcpTasksExtensionId],
        isEmpty,
      );

      final stableMeta = buildProtocolRequestMeta(
        protocolVersion: latestInitializationProtocolVersion,
        clientInfo: const Implementation(name: 'client', version: '1.0.0'),
        clientCapabilities: clientCapabilities,
      );
      final stableCapabilities =
          stableMeta[McpMetaKey.clientCapabilities] as Map<String, dynamic>;
      expect(stableCapabilities, contains('tasks'));
      expect(stableCapabilities['roots'], contains('listChanged'));
    });

    test('server/discover result omits legacy task capabilities', () {
      const serverCapabilities = ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        tasks: ServerCapabilitiesTasks(
          list: true,
          cancel: true,
          requests: ServerCapabilitiesTasksRequests(
            tools: ServerCapabilitiesTasksTools(
              call: ServerCapabilitiesTasksToolsCall(),
            ),
          ),
        ),
        extensions: {mcpTasksExtensionId: {}},
      );
      expect(serverCapabilities.toJson(), contains('tasks'));

      final json = const DiscoverResult(
        supportedVersions: [previewProtocolVersion],
        capabilities: serverCapabilities,
        serverInfo: Implementation(name: 'server', version: '1.0.0'),
      ).toJson();
      final capabilities = json['capabilities'] as Map<String, dynamic>;
      expect(capabilities, isNot(contains('tasks')));
      expect(capabilities, contains('tools'));
      expect((capabilities['extensions'] as Map)[mcpTasksExtensionId], isEmpty);
    });

    test('server/discover and capability fields reject malformed wire shapes',
        () {
      final result = {
        'resultType': resultTypeComplete,
        'supportedVersions': [previewProtocolVersion],
        'capabilities': <String, dynamic>{},
        'serverInfo': {'name': 'server', 'version': '1.0.0'},
      };

      for (final parse in <Object Function()>[
        () => DiscoverResult.fromJson({
              ...result,
              'supportedVersions': [previewProtocolVersion, 1],
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'capabilities': 'bad',
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'instructions': 1,
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'ttlMs': -1,
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'cacheScope': 'global',
            }),
        () => ClientCapabilitiesSampling.fromJson({
              'tools': {'bad': Object()},
            }),
        () => ServerCapabilities.fromJson({
              'logging': {'bad': Object()},
            }),
      ]) {
        expect(parse, throwsFormatException);
      }

      expect(
        DiscoverResult.fromJson({...result, 'serverInfo': 'bad'}).serverInfo,
        isNull,
      );
    });

    test('server/discover requires object-valued core capabilities', () {
      final result = {
        'resultType': resultTypeComplete,
        'supportedVersions': [previewProtocolVersion],
        'capabilities': <String, dynamic>{},
      };

      for (final capability in <String>{
        'experimental',
        'logging',
        'completions',
        'prompts',
        'resources',
        'tools',
        'extensions',
      }) {
        for (final malformedValue in <Object?>[true, false, null, const []]) {
          expect(
            () => DiscoverResult.fromJson({
              ...result,
              'capabilities': {capability: malformedValue},
            }),
            throwsFormatException,
            reason: '$capability must be an object when present',
          );
        }
      }
    });

    test('server/discover preserves additional capability JSON values', () {
      final parsed = DiscoverResult.fromJson({
        'resultType': resultTypeComplete,
        'supportedVersions': [previewProtocolVersion],
        'capabilities': {
          'tools': <String, dynamic>{},
          'completions': {'listChanged': 'future-value'},
          'tasks': ['future-task-shape'],
          'elicitation': 'future-elicitation-shape',
          'com.example/booleanCapability': true,
          'com.example/listCapability': ['fast', 1],
        },
      });

      expect(parsed.capabilities.tools, isNotNull);
      expect(parsed.capabilities.completions, isNotNull);
      expect(parsed.capabilities.additionalCapabilities, {
        'tasks': ['future-task-shape'],
        'elicitation': 'future-elicitation-shape',
        'com.example/booleanCapability': true,
        'com.example/listCapability': ['fast', 1],
      });
      expect(parsed.toJson()['capabilities'], {
        'tools': <String, dynamic>{},
        'completions': <String, dynamic>{},
        'tasks': ['future-task-shape'],
        'elicitation': 'future-elicitation-shape',
        'com.example/booleanCapability': true,
        'com.example/listCapability': ['fast', 1],
      });
    });

    test('legacy initialize retains boolean capability compatibility', () {
      final parsed = InitializeResult.fromJson({
        'protocolVersion': latestInitializationProtocolVersion,
        'capabilities': {
          'completions': true,
          'prompts': false,
          'resources': true,
          'tools': true,
        },
        'serverInfo': {'name': 'legacy-server', 'version': '1.0.0'},
      });

      expect(parsed.capabilities.completions, isNotNull);
      expect(parsed.capabilities.prompts, isNull);
      expect(parsed.capabilities.resources, isNotNull);
      expect(parsed.capabilities.tools, isNotNull);
    });

    test('requires complete resultType on server/discover results', () {
      final validResult = const DiscoverResult(
        supportedVersions: [previewProtocolVersion],
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'server', version: '1.0.0'),
      ).toJson();

      for (final json in [
        {
          ...validResult,
        }..remove('resultType'),
        {
          ...validResult,
          'resultType': resultTypeInputRequired,
        },
        {
          ...validResult,
          'resultType': 1,
        },
      ]) {
        expect(
          () => DiscoverResult.fromJson(json),
          throwsFormatException,
        );
      }

      expect(
        () => const DiscoverResult(
          resultType: resultTypeInputRequired,
          supportedVersions: [previewProtocolVersion],
          capabilities: ServerCapabilities(),
          serverInfo: Implementation(name: 'server', version: '1.0.0'),
        ).toJson(),
        throwsArgumentError,
      );
    });

    test('requires server/discover request metadata in params', () {
      expect(
        () => JsonRpcServerDiscoverRequest(id: 'discover-1').toJson(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('params._meta'),
          ),
        ),
      );

      for (final message in [
        {
          'jsonrpc': jsonRpcVersion,
          'id': 'discover-1',
          'method': Method.serverDiscover,
        },
        {
          'jsonrpc': jsonRpcVersion,
          'id': 'discover-1',
          'method': Method.serverDiscover,
          '_meta': _clientMeta(),
        },
        {
          'jsonrpc': jsonRpcVersion,
          'id': 'discover-1',
          'method': Method.serverDiscover,
          'params': <String, dynamic>{},
        },
      ]) {
        expect(
          () => JsonRpcMessage.fromJson(message),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              anyOf(contains('params'), contains('params._meta')),
            ),
          ),
        );
      }

      for (final parse in <Object Function()>[
        () => JsonRpcServerDiscoverRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 'discover-1',
              'method': Method.serverDiscover,
              'params': {'_meta': _clientMeta()},
            }),
        () => JsonRpcServerDiscoverRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 'discover-1',
              'method': Method.initialize,
              'params': {'_meta': _clientMeta()},
            }),
      ]) {
        expect(parse, throwsFormatException);
      }

      final parsed = JsonRpcMessage.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': 'discover-1',
        'method': Method.serverDiscover,
        'params': {'_meta': _clientMeta()},
      });
      expect(parsed, isA<JsonRpcServerDiscoverRequest>());
      expect(
        (parsed as JsonRpcServerDiscoverRequest)
            .meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
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
        () => ListToolsResult.fromJson(const {'tools': [], 'ttlMs': -1}),
        throwsFormatException,
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

    test(
        'prompt completion and notification fields reject malformed wire shapes',
        () {
      for (final parse in <Object Function()>[
        () => Prompt.fromJson({
              'name': 'prompt',
              'arguments': [1],
            }),
        () => GetPromptRequest.fromJson({
              'name': 'prompt',
              'arguments': {'arg': 1},
            }),
        () => JsonRpcListPromptsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 'prompts',
              'method': Method.resourcesList,
            }),
        () => JsonRpcGetPromptRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 'prompt',
              'method': Method.promptsGet,
              'params': {'name': 'prompt'},
            }),
        () => JsonRpcPromptListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsResourcesListChanged,
            }),
        () => JsonRpcListResourcesRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 'resources',
              'method': Method.resourcesList,
            }),
        () => JsonRpcListResourceTemplatesRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 'templates',
              'method': Method.resourcesList,
            }),
        () => JsonRpcReadResourceRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 'read',
              'method': Method.resourcesList,
              'params': {'uri': 'file:///a.txt'},
            }),
        () => JsonRpcResourceListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsResourcesUpdated,
            }),
        () => JsonRpcResourceUpdatedNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsResourcesUpdated,
              'params': {'uri': 'file:///a.txt'},
            }),
        () => CompleteRequest.fromJson({
              'ref': {'type': 'ref/prompt', 'name': 'prompt'},
              'argument': {'name': 'arg', 'value': 1},
            }),
        () => JsonRpcCompleteRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 'complete',
              'method': Method.completionComplete,
              'params': {
                'ref': {'type': 'ref/prompt', 'name': 'prompt'},
                'argument': {'name': 'arg', 'value': 'prefix'},
              },
            }),
        () => JsonRpcCompleteRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 'complete',
              'method': Method.promptsGet,
              'params': {
                'ref': {'type': 'ref/prompt', 'name': 'prompt'},
                'argument': {'name': 'arg', 'value': 'prefix'},
              },
            }),
        () => ResourceReference.fromJson({
              'uri': 'file:///{path}',
            }),
        () => ResourceReference.fromJson({
              'type': 'ref/prompt',
              'uri': 'file:///{path}',
            }),
        () => PromptReference.fromJson({
              'name': 'prompt',
            }),
        () => PromptReference.fromJson({
              'type': 'ref/resource',
              'name': 'prompt',
            }),
        () => CompletionResultData.fromJson({
              'values': ['a'],
              'hasMore': 'true',
            }),
        () => CreateMessageRequestParams.fromJson({
              'messages': [
                {
                  'role': 'user',
                  'content': {'type': 'text', 'text': 'Hello'},
                },
              ],
              'maxTokens': 100,
              'tools': 'bad',
            }),
        () => CreateMessageRequestParams.fromJson({
              'messages': [
                {
                  'role': 'user',
                  'content': {'type': 'text', 'text': 'Hello'},
                },
              ],
              'maxTokens': 100,
              'tools': [1],
            }),
        () => LoggingMessageNotification.fromJson({
              'level': 'info',
              'data': Object(),
            }),
        () => LoggingMessageNotification.fromJson({'level': 'info'}),
        () => JsonRpcLoggingMessageNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsMessage,
              'params': {'level': 'info', 'data': 'message'},
            }),
        () => JsonRpcLoggingMessageNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsProgress,
              'params': {'level': 'info', 'data': 'message'},
            }),
        () => JsonRpcCancelledNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsProgress,
              'params': {'requestId': 'request-1'},
            }),
        () => JsonRpcProgressNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsProgress,
              'params': {'progressToken': 'progress-1', 'progress': 1},
            }),
        () => ProgressNotification.fromJson({
              'progressToken': 'progress-1',
              'progress': 1,
              'message': 1,
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
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
              task: const TaskCreation(ttl: 1000),
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
              task: TaskCreation(ttl: 1000),
              maxTokens: 100,
              tools: [
                Tool(
                  name: 'lookup',
                  inputSchema: JsonObject(),
                  execution: ToolExecution(taskSupport: 'optional'),
                ),
              ],
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
        json['inputRequests']['github_login']['params'],
        isNot(contains('task')),
      );
      expect(
        json['inputRequests']['capital_of_france']['method'],
        Method.samplingCreateMessage,
      );
      expect(
        json['inputRequests']['capital_of_france']['params'],
        isNot(contains('task')),
      );
      expect(
        json['inputRequests']['capital_of_france']['params']['tools'][0],
        isNot(contains('execution')),
      );
      expect(json['inputRequests']['roots'], {'method': Method.rootsList});

      final parsed = InputRequiredResult.fromJson(json);
      expect(parsed.requestState, 'AEAD-protected blob');
      expect(
        parsed.inputRequests!['github_login']!.elicitParams.message,
        'Please provide your GitHub username',
      );
      expect(
        parsed.inputRequests!['github_login']!.elicitParams.task,
        isNull,
      );
      expect(
        parsed
            .inputRequests!['capital_of_france']!.createMessageParams.maxTokens,
        100,
      );
      expect(
        parsed.inputRequests!['capital_of_france']!.createMessageParams.task,
        isNull,
      );
    });

    test('serializes MRTR retry fields on supported client requests', () {
      final inputResponses = {
        'github_login': InputResponse.fromResult(
          const ElicitResult(
            action: 'accept',
            content: {'name': 'octocat'},
            meta: {'stable': true},
          ),
        ),
        'roots': InputResponse.fromResult(
          ListRootsResult(
            roots: [Root(uri: 'file:///repo')],
            meta: const {'stable': true},
          ),
        ),
        'capital_of_france': InputResponse.fromResult(
          const CreateMessageResult(
            model: 'model',
            role: SamplingMessageRole.assistant,
            content: SamplingTextContent(text: 'Paris'),
            meta: {'preserved': true},
          ),
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
      expect(
        toolJson['inputResponses']['github_login'],
        isNot(contains('_meta')),
      );
      expect(toolJson['inputResponses']['roots'], isNot(contains('_meta')));
      expect(toolJson['inputResponses']['capital_of_france']['_meta'], {
        'preserved': true,
      });
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
        () => InputRequiredResult.fromJson({
          'resultType': resultTypeInputRequired,
          'requestState': 'state',
          '_meta': {'bad': Object()},
        }),
        throwsFormatException,
      );
      expect(
        () => const InputRequiredResult(
          requestState: 'state',
          meta: {'bad': Object()},
        ).toJson(),
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
        () => InputRequiredResult.fromJson(
          const {
            'resultType': resultTypeInputRequired,
            'inputRequests': {
              'legacy_task_elicit': {
                'method': Method.elicitationCreate,
                'params': {
                  'mode': 'form',
                  'message': 'Need username',
                  'requestedSchema': {
                    'type': 'object',
                    'properties': {
                      'name': {'type': 'string'},
                    },
                  },
                  'task': {'ttl': 1000},
                },
              },
            },
          },
        ),
        throwsFormatException,
      );
      expect(
        () => InputRequiredResult.fromJson(
          const {
            'resultType': resultTypeInputRequired,
            'inputRequests': {
              'legacy_task_sampling': {
                'method': Method.samplingCreateMessage,
                'params': {
                  'messages': [
                    {
                      'role': 'user',
                      'content': {
                        'type': 'text',
                        'text': 'Continue?',
                      },
                    },
                  ],
                  'maxTokens': 1,
                  'task': {'ttl': 1000},
                },
              },
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
        () => CallToolRequest.fromJson({
          'name': 'deploy',
          'arguments': {'bad': Object()},
        }),
        throwsFormatException,
      );
      expect(
        () => const CallToolRequest(
          name: 'deploy',
          arguments: {'bad': Object()},
        ).toJson(),
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
      expect(
        () => ReadResourceRequest.fromJson(
          const {
            'uri': 'file:///repo/README.md',
            'inputResponses': {
              'unknown': {'unexpected': true},
            },
          },
        ),
        throwsFormatException,
      );
      expect(
        () => ReadResourceRequest.fromJson(
          const {
            'uri': 'file:///repo/README.md',
            'inputResponses': {
              'roots': {
                'roots': [],
                '_meta': {'trace': 'not-in-draft-client-result'},
              },
            },
          },
        ),
        throwsFormatException,
      );
      expect(
        () => const InputResponse.raw({
          'action': 'accept',
          '_meta': {'trace': 'not-in-draft-client-result'},
        }).toJson(),
        throwsFormatException,
      );
    });

    test('rejects malformed tool wire shapes', () {
      for (final parse in <Object Function()>[
        () => ToolAnnotations.fromJson({'openWorldHint': 'false'}),
        () => ToolExecution.fromJson({'taskSupport': 1}),
        () => Tool.fromJson({
              'name': 'search',
              'inputSchema': {'type': 'object'},
              'execution': 'bad',
            }),
        () => Tool.fromJson({
              'name': 'search',
              'inputSchema': {'type': 'object'},
              'icons': [1],
            }),
        () => ListToolsRequest.fromJson({'cursor': 1}),
        () => ListToolsResult.fromJson({
              'tools': [1],
            }),
        () => CallToolRequest.fromJson({'name': 1}),
        () => CallToolResult.fromJson({
              'content': <Map<String, dynamic>>[],
              'isError': 'true',
            }),
        () => JsonRpcListToolsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.toolsList,
              'params': 'bad',
            }),
        () => JsonRpcListToolsRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.toolsList,
            }),
        () => JsonRpcListToolsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.promptsList,
            }),
        () => JsonRpcCallToolRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.toolsCall,
              'params': 'bad',
            }),
        () => JsonRpcCallToolRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.toolsCall,
              'params': {'name': 'tool'},
            }),
        () => JsonRpcCallToolRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.promptsGet,
              'params': {'name': 'tool'},
            }),
        () => JsonRpcToolListChangedNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsToolsListChanged,
            }),
        () => JsonRpcToolListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsPromptsListChanged,
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });

    test('preserves network schema refs without dereferencing them', () async {
      var canaryRequests = 0;
      final canary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => canary.close(force: true));
      canary.listen((request) async {
        canaryRequests++;
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"type":"string"}');
        await request.response.close();
      });
      final networkRef = 'http://127.0.0.1:${canary.port}/schema.json';

      final tool = Tool.fromJson({
        'name': 'opaque-schema-ref',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'value': {'\$ref': networkRef},
          },
        },
      });

      expect(
        tool.toJson()['inputSchema'],
        containsPair(
          'properties',
          {
            'value': {'\$ref': networkRef},
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(canaryRequests, 0);
    });

    test('rejects malformed root wire shapes', () {
      for (final parse in <Object Function()>[
        () => Root.fromJson({'uri': 'file:///repo', 'name': 1}),
        () => ListRootsResult.fromJson({
              'roots': [1],
            }),
        () => JsonRpcListRootsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.rootsList,
              'params': 'bad',
            }),
        () => JsonRpcListRootsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.rootsList,
              'params': null,
            }),
        () => JsonRpcListRootsRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.rootsList,
            }),
        () => JsonRpcListRootsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.toolsList,
            }),
        () => JsonRpcRootsListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsRootsListChanged,
              'params': 'bad',
            }),
        () => JsonRpcRootsListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsRootsListChanged,
              'params': null,
            }),
        () => JsonRpcRootsListChangedNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsRootsListChanged,
            }),
        () => JsonRpcRootsListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsToolsListChanged,
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });

    test('rejects malformed task wire shapes', () {
      final taskParams = {'taskId': 'task-1'};
      final updateTaskParams = {
        'taskId': 'task-1',
        'inputResponses': <String, dynamic>{},
      };
      final taskStatusParams = {
        'taskId': 'task-1',
        'status': 'working',
        'ttl': null,
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:00:01Z',
      };
      final taskExtensionParams = {
        'taskId': 'task-1',
        'status': 'working',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:00:01Z',
        'ttlMs': null,
      };

      for (final parse in <Object Function()>[
        () => ListTasksRequest.fromJson({'cursor': 1}),
        () => JsonRpcListTasksRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksList,
              'params': null,
            }),
        () => JsonRpcListTasksRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.tasksList,
            }),
        () => JsonRpcListTasksRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksGet,
            }),
        () => ListTasksResult.fromJson({
              'tasks': [1],
            }),
        () => CancelTaskRequest.fromJson({'taskId': 1}),
        () => JsonRpcCancelTaskRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksCancel,
              'params': 'bad',
            }),
        () => JsonRpcCancelTaskRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.tasksCancel,
              'params': taskParams,
            }),
        () => JsonRpcCancelTaskRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksGet,
              'params': taskParams,
            }),
        () => GetTaskRequest.fromJson({'taskId': 1}),
        () => JsonRpcGetTaskRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksGet,
              'params': 'bad',
            }),
        () => JsonRpcGetTaskRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.tasksGet,
              'params': taskParams,
            }),
        () => JsonRpcGetTaskRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksCancel,
              'params': taskParams,
            }),
        () => TaskResultRequest.fromJson({'taskId': 1}),
        () => JsonRpcTaskResultRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksResult,
              'params': null,
            }),
        () => JsonRpcTaskResultRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.tasksResult,
              'params': taskParams,
            }),
        () => JsonRpcTaskResultRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksGet,
              'params': taskParams,
            }),
        () => CreateTaskResult.fromJson({'task': 'bad'}),
        () => JsonRpcUpdateTaskRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksUpdate,
              'params': 'bad',
            }),
        () => JsonRpcUpdateTaskRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.tasksUpdate,
              'params': updateTaskParams,
            }),
        () => JsonRpcUpdateTaskRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.tasksGet,
              'params': updateTaskParams,
            }),
        () => JsonRpcTaskStatusNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsTasksStatus,
              'params': 'bad',
            }),
        () => JsonRpcTaskStatusNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsTasksStatus,
              'params': taskStatusParams,
            }),
        () => JsonRpcTaskStatusNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsTasks,
              'params': taskStatusParams,
            }),
        () => JsonRpcTaskNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsTasks,
              'params': null,
            }),
        () => JsonRpcTaskNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsTasks,
              'params': taskExtensionParams,
            }),
        () => JsonRpcTaskNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsTasksStatus,
              'params': taskExtensionParams,
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });

    test('rejects malformed subscription wire shapes', () {
      for (final parse in <Object Function()>[
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': '1.0',
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': {
                '_meta': _clientMeta(),
                'notifications': <String, dynamic>{},
              },
            }),
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.toolsList,
              'params': {
                '_meta': _clientMeta(),
                'notifications': <String, dynamic>{},
              },
            }),
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': {
                'notifications': <String, dynamic>{},
              },
            }),
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': {
                '_meta': 'bad',
                'notifications': <String, dynamic>{},
              },
            }),
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': 'bad',
            }),
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': null,
            }),
        () => SubscriptionsListenRequest.fromJson({
              'notifications': 'bad',
            }),
        () => SubscriptionsListenRequest.fromJson({
              'notifications': <Object?, Object?>{
                1: true,
              },
            }),
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson({
              'jsonrpc': '1.0',
              'method': Method.notificationsSubscriptionsAcknowledged,
              'params': {
                'notifications': <String, dynamic>{},
              },
            }),
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsProgress,
              'params': {
                'notifications': <String, dynamic>{},
              },
            }),
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsSubscriptionsAcknowledged,
              'params': 'bad',
            }),
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsSubscriptionsAcknowledged,
              'params': null,
            }),
        () => SubscriptionsAcknowledgedNotification.fromJson({
              'notifications': <Object?, Object?>{
                1: true,
              },
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });

    test('serializes subscriptions/listen with required request metadata', () {
      final request = JsonRpcSubscriptionsListenRequest(
        id: 'sub-1',
        listenParams: const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
        meta: _clientMeta(),
      );

      final json = request.toJson();
      expect(json['method'], Method.subscriptionsListen);
      expect(json['params']['notifications'], {'toolsListChanged': true});
      expect(
        json['params']['_meta'][McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
      expect(
        json['params']['_meta'][McpMetaKey.clientCapabilities],
        <String, dynamic>{},
      );

      final parsed = JsonRpcSubscriptionsListenRequest.fromJson(json);
      expect(parsed.id, 'sub-1');
      expect(parsed.meta, _clientMeta());
      expect(parsed.listenParams.notifications.toolsListChanged, isTrue);
      expect(
        () => JsonRpcSubscriptionsListenRequest(
          id: 'missing-meta',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
        ).toJson(),
        throwsFormatException,
      );
    });

    test('serializes subscriptions/listen graceful-close result metadata', () {
      final result = SubscriptionsListenResult(subscriptionId: 'sub-1');

      expect(result.subscriptionId, 'sub-1');
      expect(result.toJson(), {
        '_meta': {McpMetaKey.subscriptionId: 'sub-1'},
      });

      final parsed = SubscriptionsListenResult.fromJson({
        '_meta': {McpMetaKey.subscriptionId: 7},
      });
      expect(parsed.subscriptionId, 7);

      for (final parse in <Object Function()>[
        () => SubscriptionsListenResult.fromJson(<String, dynamic>{}),
        () => SubscriptionsListenResult.fromJson({
              '_meta': <String, dynamic>{},
            }),
        () => SubscriptionsListenResult.fromJson({
              '_meta': {McpMetaKey.subscriptionId: true},
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });

    test('resource subscriptions require resources.subscribe capability', () {
      const requested = SubscriptionFilter(
        resourceSubscriptions: ['file:///project/config.json'],
      );

      expect(
        requested
            .acknowledgedBy(
              const ServerCapabilities(
                resources: ServerCapabilitiesResources(),
              ),
            )
            .toJson(),
        isEmpty,
      );
      expect(
        requested
            .acknowledgedBy(
              const ServerCapabilities(
                resources: ServerCapabilitiesResources(subscribe: true),
              ),
            )
            .toJson(),
        {
          'resourceSubscriptions': ['file:///project/config.json'],
        },
      );
    });

    test('server acknowledges subscriptions/listen with subscription id',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
            resources: ServerCapabilitiesResources(subscribe: true),
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
                resources: ServerCapabilitiesResources(subscribe: true),
              ),
            ),
          );
          return const EmptyResult(
            meta: {
              'com.example/trace': 'subscription-trace',
              McpMetaKey.subscriptionId: 'handler-value',
            },
          );
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
      final cancellation = JsonRpcCancelledNotification.fromJson(
        transport.sentMessages[1].toJson(),
      );
      expect(cancellation.cancelParams.requestId, 'sub-1');
      expect(cancellation.meta?[McpMetaKey.subscriptionId], 'sub-1');
      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.result['_meta'], {
        'com.example/trace': 'subscription-trace',
        McpMetaKey.subscriptionId: 'sub-1',
        McpMetaKey.serverInfo: {'name': 'server', 'version': '1.0.0'},
      });
      final wireResult = response.toJson()['result'] as Map<String, dynamic>;
      expect(wireResult['_meta'], response.result['_meta']);
    });

    test('server rejects subscription notifications before acknowledgment',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
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
          protocol: McpProtocol.stable,
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

      expect(transport.sentMessages, hasLength(4));
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
      final cancellation = JsonRpcCancelledNotification.fromJson(
        transport.sentMessages[2].toJson(),
      );
      expect(cancellation.cancelParams.requestId, 'sub-1');
      expect(cancellation.meta?[McpMetaKey.subscriptionId], 'sub-1');
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });

    test('server shares subscription state across raw and typed helpers',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendNotification(
            JsonRpcSubscriptionsAcknowledgedNotification(
              acknowledgedParams: const SubscriptionsAcknowledgedNotification(
                notifications: SubscriptionFilter(toolsListChanged: true),
              ),
            ),
          );
          await extra.sendSubscriptionNotification(
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
          id: 'sub-mixed-helpers',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      expect(transport.sentMessages, hasLength(4));
      expect(
        transport.sentMessages.take(2).map((message) => message.toJson()),
        everyElement(
          containsPair(
            'params',
            containsPair(
              '_meta',
              containsPair(
                McpMetaKey.subscriptionId,
                'sub-mixed-helpers',
              ),
            ),
          ),
        ),
      );
      expect(
        (transport.sentMessages[0] as JsonRpcNotification).method,
        Method.notificationsSubscriptionsAcknowledged,
      );
      expect(
        (transport.sentMessages[1] as JsonRpcNotification).method,
        Method.notificationsToolsListChanged,
      );
      expect(
        transport.sentMessages[2],
        isA<JsonRpcNotification>().having(
          (message) => message.method,
          'method',
          Method.notificationsCancelled,
        ),
      );
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });

    test('server cancels acknowledged subscriptions before shutdown', () async {
      final holdOpen = Completer<void>();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          await holdOpen.future;
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
          id: 'sub-shutdown',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      await server.close();

      expect(transport.closed, isTrue);
      expect(transport.sentMessages, hasLength(3));
      final cancellation = JsonRpcCancelledNotification.fromJson(
        transport.sentMessages[1].toJson(),
      );
      expect(cancellation.cancelParams.requestId, 'sub-shutdown');
      expect(cancellation.cancelParams.reason, 'Server is shutting down.');
      expect(
        cancellation.meta?[McpMetaKey.subscriptionId],
        'sub-shutdown',
      );
      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.id, 'sub-shutdown');
      expect(response.result['resultType'], resultTypeComplete);
      expect(
        response.result['_meta'][McpMetaKey.subscriptionId],
        'sub-shutdown',
      );
      expect(response.result['_meta'][McpMetaKey.serverInfo], {
        'name': 'server',
        'version': '1.0.0',
      });
    });

    test('server includes an in-flight acknowledgment in shutdown teardown',
        () async {
      final holdOpen = Completer<void>();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          await holdOpen.future;
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = AcknowledgmentGateTransport();
      await server.connect(transport);
      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-pending-ack',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await transport.acknowledgmentStarted.future.timeout(
        const Duration(seconds: 5),
      );

      final close = server.close();
      await _pump();
      expect(transport.closed, isFalse);

      transport.releaseAcknowledgment.complete();
      await close.timeout(const Duration(seconds: 5));
      holdOpen.complete();
      await _pump();

      expect(transport.closed, isTrue);
      expect(transport.sentMessages, hasLength(3));
      expect(
        transport.sentMessages[0],
        isA<JsonRpcNotification>().having(
          (message) => message.method,
          'method',
          Method.notificationsSubscriptionsAcknowledged,
        ),
      );
      final cancellation = JsonRpcCancelledNotification.fromJson(
        transport.sentMessages[1].toJson(),
      );
      expect(cancellation.cancelParams.requestId, 'sub-pending-ack');
      expect(
        transport.sentMessages[2],
        isA<JsonRpcResponse>().having(
          (message) => message.id,
          'id',
          'sub-pending-ack',
        ),
      );
    });

    test('server forces close when subscription shutdown stalls', () async {
      final holdOpen = Completer<void>();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          gracefulShutdownTimeout: Duration(milliseconds: 20),
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          await holdOpen.future;
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final errors = <Error>[];
      final transport = AcknowledgmentGateTransport();
      server.onerror = errors.add;
      await server.connect(transport);
      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-stalled-shutdown',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await transport.acknowledgmentStarted.future.timeout(
        const Duration(seconds: 5),
      );

      await server.close().timeout(const Duration(seconds: 1));

      expect(transport.closed, isTrue);
      expect(
        errors,
        contains(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('forcing transport shutdown'),
          ),
        ),
      );
      expect(transport.sentMessages, hasLength(1));

      transport.releaseAcknowledgment.complete();
      holdOpen.complete();
      await _pump();
      expect(transport.sentMessages, hasLength(1));
    });

    test(
        'server rejects subscriptions and ignores notifications after shutdown starts',
        () async {
      var handlerCalls = 0;
      var notificationHandlerCalls = 0;
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          handlerCalls++;
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      server.setNotificationHandler<JsonRpcCancelledNotification>(
        Method.notificationsCancelled,
        (notification) async {
          notificationHandlerCalls++;
        },
        (params, meta) => JsonRpcCancelledNotification(
          cancelParams: CancelledNotification.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = CloseGateTransport();
      await server.connect(transport);

      final close = server.close();
      await transport.closeStarted.future;
      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-too-late',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      transport.receive(
        JsonRpcCancelledNotification(
          cancelParams: const CancelledNotification(
            requestId: 'notification-too-late',
          ),
        ),
      );
      await _pump();

      expect(handlerCalls, 0);
      expect(notificationHandlerCalls, 0);
      expect(
        transport.sentMessages.where(
          (message) =>
              message is JsonRpcNotification &&
              message.method == Method.notificationsSubscriptionsAcknowledged,
        ),
        isEmpty,
      );
      expect(
        transport.sentMessages.single,
        isA<JsonRpcError>()
            .having((message) => message.id, 'id', 'sub-too-late')
            .having(
              (message) => message.error.code,
              'code',
              ErrorCode.connectionClosed.value,
            ),
      );

      transport.releaseClose.complete();
      await close;
      expect(transport.closed, isTrue);
    });

    test('protocol close is single-flight and rejects new outbound work',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      final transport = EarlyCloseGateTransport();
      await server.connect(transport);

      final firstClose = server.close();
      await transport.closeStarted.future;
      final secondClose = server.close();

      expect(identical(firstClose, secondClose), isTrue);
      final replacement = RecordingTransport();
      await expectLater(
        server.connect(replacement),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('closing'),
          ),
        ),
      );
      await expectLater(
        server.request<EmptyResult>(
          const JsonRpcPingRequest(id: 'too-late-request'),
          (_) => const EmptyResult(),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('closing'),
          ),
        ),
      );
      await expectLater(
        server.notification(
          const JsonRpcNotification(method: 'notifications/test/too-late'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('closing'),
          ),
        ),
      );
      expect(transport.sentMessages, isEmpty);

      transport.releaseClose.complete();
      await Future.wait([firstClose, secondClose]);
      expect(transport.closeCalls, 1);

      await server.connect(replacement);
      expect(replacement.started, isTrue);
      await server.close();
    });

    test('server close waits for an in-flight subscription settlement',
        () async {
      final handlerReady = Completer<void>();
      final completeHandler = Completer<void>();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          handlerReady.complete();
          await completeHandler.future;
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = CancellationGateTransport();
      await server.connect(transport);
      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-settling',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await handlerReady.future.timeout(const Duration(seconds: 5));

      completeHandler.complete();
      await transport.cancellationStarted.future.timeout(
        const Duration(seconds: 5),
      );
      final close = server.close();
      await _pump();

      expect(transport.closed, isFalse);
      expect(
        transport.sentMessages.whereType<JsonRpcResponse>(),
        isEmpty,
      );

      transport.releaseCancellation.complete();
      await close.timeout(const Duration(seconds: 5));

      expect(transport.closed, isTrue);
      expect(transport.lifecycleEvents, [
        'acknowledgment',
        'cancellation',
        'response',
        'close',
      ]);
      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.id, 'sub-settling');
    });

    test('server gracefully closes subscription response streams', () async {
      final holdOpen = Completer<void>();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          await holdOpen.future;
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSubscriptionsListenRequest(
          id: id,
          listenParams: SubscriptionsListenRequest.fromJson(params!),
          meta: meta,
        ),
      );
      final transport = PlainRecordingTransport();
      await server.connect(transport);
      transport.receive(
        JsonRpcSubscriptionsListenRequest(
          id: 'sub-response-stream',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      await server.close();

      expect(transport.closed, isTrue);
      expect(transport.sentMessages, hasLength(2));
      expect(
        transport.sentMessages.whereType<JsonRpcCancelledNotification>(),
        isEmpty,
      );
      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.id, 'sub-response-stream');
      expect(response.result['resultType'], resultTypeComplete);
      expect(
        response.result['_meta'][McpMetaKey.subscriptionId],
        'sub-response-stream',
      );
    });

    test('server sends subscription cancellation before handler errors',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          throw McpError(
            ErrorCode.invalidRequest.value,
            'subscription failed',
          );
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
          id: 'sub-error',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      expect(transport.sentMessages, hasLength(3));
      final cancellation = JsonRpcCancelledNotification.fromJson(
        transport.sentMessages[1].toJson(),
      );
      expect(cancellation.cancelParams.requestId, 'sub-error');
      expect(
        cancellation.cancelParams.reason,
        'Server terminated subscription stream after an error.',
      );
      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.id, 'sub-error');
      expect(response.error.code, ErrorCode.invalidRequest.value);
      expect(response.error.message, 'subscription failed');
    });

    test('server sends subscription cancellation before serialization errors',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(
            const SubscriptionFilter(toolsListChanged: true),
          );
          return const UnserializableSubscriptionResult();
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
          id: 'sub-serialization-error',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      expect(transport.sentMessages, hasLength(3));
      expect(
        transport.sentMessages.first,
        isA<JsonRpcNotification>().having(
          (message) => message.method,
          'method',
          Method.notificationsSubscriptionsAcknowledged,
        ),
      );
      final cancellation = JsonRpcCancelledNotification.fromJson(
        transport.sentMessages[1].toJson(),
      );
      expect(cancellation.cancelParams.requestId, 'sub-serialization-error');
      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.id, 'sub-serialization-error');
      expect(response.error.code, ErrorCode.internalError.value);
      expect(
        response.error.message,
        'Internal server error processing ${Method.subscriptionsListen}',
      );
      expect(response.error.message, isNot(contains('sentinel')));
    });

    test('stateless servers suppress legacy global subscription notifications',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
            prompts: ServerCapabilitiesPrompts(listChanged: true),
            resources: ServerCapabilitiesResources(
              listChanged: true,
              subscribe: true,
            ),
          ),
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      await server.sendToolListChanged();
      await server.sendPromptListChanged();
      await server.sendResourceListChanged();
      await server.sendResourceUpdated(
        const ResourceUpdatedNotification(uri: 'file:///resource'),
      );
      // ignore: deprecated_member_use_from_same_package
      await server.sendCompletionListChanged();

      expect(transport.sentMessages, isEmpty);
    });

    test('stateless normal handlers reject subscription-only notifications',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            logging: <String, dynamic>{},
            tools: ServerCapabilitiesTools(listChanged: true),
            prompts: ServerCapabilitiesPrompts(listChanged: true),
            resources: ServerCapabilitiesResources(
              listChanged: true,
              subscribe: true,
            ),
            extensions: {mcpTasksExtensionId: <String, dynamic>{}},
          ),
        ),
      );
      addTearDown(server.close);
      late RequestHandlerExtra handlerExtra;
      server.setRequestHandler<JsonRpcRequest>(
        'test/handler-notifications',
        (request, extra) async {
          handlerExtra = extra;
          await extra.sendProgress(1, total: 2);
          await extra.sendNotification(
            JsonRpcLoggingMessageNotification(
              logParams: const LoggingMessageNotification(
                level: LoggingLevel.warning,
                data: 'request log',
              ),
            ),
          );
          await extra.sendNotification(
            const JsonRpcNotification(method: 'test/custom-notification'),
          );
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcRequest(
          id: id,
          method: 'test/handler-notifications',
          params: params,
          meta: meta,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcRequest(
          id: 71,
          method: 'test/handler-notifications',
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              extensions: {mcpTasksExtensionId: <String, dynamic>{}},
            ),
            meta: const {'progressToken': 'progress-1'},
            logLevel: LoggingLevel.warning.name,
          ),
        ),
      );
      await _pump();

      expect(
        transport.sentMessages
            .whereType<JsonRpcNotification>()
            .map((message) => message.method),
        [
          Method.notificationsProgress,
          Method.notificationsMessage,
          'test/custom-notification',
        ],
      );
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());

      final invalidNotifications = <JsonRpcNotification>[
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: _allSubscriptionFilter,
          ),
        ),
        ..._subscriptionDataNotifications(),
        JsonRpcCancelledNotification(
          cancelParams: const CancelledNotification(
            requestId: 71,
            reason: 'handler emitted',
          ),
        ),
        for (final method in const [
          Method.notificationsInitialized,
          Method.notificationsRootsListChanged,
          Method.notificationsTasksStatus,
          Method.notificationsCompletionsListChanged,
          Method.notificationsExperimentalCompletionsListChanged,
          Method.notificationsElicitationComplete,
        ])
          JsonRpcNotification(method: method),
      ];
      for (final notification in invalidNotifications) {
        await expectLater(
          handlerExtra.sendNotification(notification),
          throwsA(
            isA<McpError>().having(
              (error) => error.code,
              'code',
              ErrorCode.invalidRequest.value,
            ),
          ),
          reason: notification.method,
        );
      }
      expect(transport.sentMessages, hasLength(4));
    });

    test('stateless subscription handlers keep stream notifications isolated',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(listChanged: true),
            prompts: ServerCapabilitiesPrompts(listChanged: true),
            resources: ServerCapabilitiesResources(
              listChanged: true,
              subscribe: true,
            ),
            extensions: {mcpTasksExtensionId: <String, dynamic>{}},
          ),
        ),
      );
      addTearDown(server.close);
      server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
        Method.subscriptionsListen,
        (request, extra) async {
          await extra.sendSubscriptionAcknowledged(_allSubscriptionFilter);
          for (final notification in _subscriptionDataNotifications()) {
            await extra.sendNotification(notification);
          }
          await expectLater(
            extra.sendNotification(
              JsonRpcCancelledNotification(
                cancelParams: CancelledNotification(
                  requestId: request.id,
                  reason: 'handler emitted',
                ),
              ),
            ),
            throwsA(
              isA<McpError>().having(
                (error) => error.code,
                'code',
                ErrorCode.invalidRequest.value,
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
          id: 'all-notifications',
          listenParams: const SubscriptionsListenRequest(
            notifications: _allSubscriptionFilter,
          ),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              extensions: {mcpTasksExtensionId: <String, dynamic>{}},
            ),
          ),
        ),
      );
      await _pump();

      final notifications =
          transport.sentMessages.whereType<JsonRpcNotification>().toList();
      expect(
        notifications.map((message) => message.method),
        [
          Method.notificationsSubscriptionsAcknowledged,
          Method.notificationsToolsListChanged,
          Method.notificationsPromptsListChanged,
          Method.notificationsResourcesListChanged,
          Method.notificationsResourcesUpdated,
          Method.notificationsTasks,
          Method.notificationsCancelled,
        ],
      );
      expect(
        notifications,
        everyElement(
          isA<JsonRpcNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscription id',
            'all-notifications',
          ),
        ),
      );
      final cancellation =
          JsonRpcCancelledNotification.fromJson(notifications.last.toJson());
      expect(
        cancellation.cancelParams.reason,
        'Server closed subscription stream.',
      );
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());
    });

    test('stateless server responses add complete result and cache defaults',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsList,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcListPromptsRequest>(
        Method.promptsList,
        (request, extra) async => const ListPromptsResult(prompts: []),
        (id, params, meta) => JsonRpcListPromptsRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.promptsList,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcListResourcesRequest>(
        Method.resourcesList,
        (request, extra) async => const ListResourcesResult(resources: []),
        (id, params, meta) => JsonRpcListResourcesRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.resourcesList,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcListResourceTemplatesRequest>(
        Method.resourcesTemplatesList,
        (request, extra) async =>
            const ListResourceTemplatesResult(resourceTemplates: []),
        (id, params, meta) => JsonRpcListResourceTemplatesRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.resourcesTemplatesList,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.resourcesRead,
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

      for (final response in responses) {
        expect(response.result['_meta'], {
          'io.modelcontextprotocol/serverInfo': {
            'name': 'server',
            'version': '1.0.0',
          },
        });
      }
      for (final response in responses.skip(1)) {
        expect(response.result['resultType'], resultTypeComplete);
        expect(response.result['ttlMs'], 0);
        expect(response.result['cacheScope'], CacheScope.private);
      }
    });

    test('stateless server disables caching for MRTR retry results', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            resources: ServerCapabilitiesResources(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcReadResourceRequest>(
        Method.resourcesRead,
        (request, extra) async => const ReadResourceResult(
          contents: [
            TextResourceContents(uri: 'file:///private.txt', text: 'private'),
          ],
          ttlMs: 300000,
          cacheScope: CacheScope.public,
        ),
        (id, params, meta) => JsonRpcReadResourceRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.resourcesRead,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final requests = [
        JsonRpcReadResourceRequest(
          id: 'initial',
          readParams: const ReadResourceRequest(uri: 'file:///private.txt'),
          meta: _clientMeta(),
        ),
        JsonRpcReadResourceRequest(
          id: 'input-responses',
          readParams: const ReadResourceRequest(
            uri: 'file:///private.txt',
            inputResponses: {},
          ),
          meta: _clientMeta(),
        ),
        JsonRpcReadResourceRequest(
          id: 'request-state',
          readParams: const ReadResourceRequest(
            uri: 'file:///private.txt',
            requestState: 'opaque-state',
          ),
          meta: _clientMeta(),
        ),
      ];
      for (final request in requests) {
        transport.receive(request);
        await _pump();
      }

      final responses = transport.sentMessages.cast<JsonRpcResponse>().toList();
      expect(responses[0].result['ttlMs'], 300000);
      expect(responses[0].result['cacheScope'], CacheScope.public);
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
          protocol: McpProtocol.stable,
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
        response.error.message,
        contains('Missing required client capability'),
      );
      expect(response.error.data, {
        'requiredCapabilities': {
          'extensions': {
            mcpTasksExtensionId: <String, dynamic>{},
          },
        },
      });
    });

    test('server requires task extension capability for task methods',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      final handledMethods = <String>[];
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async {
          handledMethods.add(request.method);
          return const GetTaskExtensionResult(
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
          );
        },
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcCancelTaskRequest>(
        Method.tasksCancel,
        (request, extra) async {
          handledMethods.add(request.method);
          return const TaskExtensionAcknowledgementResult();
        },
        (id, params, meta) => JsonRpcCancelTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksCancel,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcUpdateTaskRequest>(
        Method.tasksUpdate,
        (request, extra) async {
          handledMethods.add(request.method);
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcUpdateTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksUpdate,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);
      addTearDown(server.close);

      final missingCapabilityRequests = <JsonRpcRequest>[
        JsonRpcGetTaskRequest(
          id: 'get-task-missing',
          getParams: const GetTaskRequest(taskId: 'task-1'),
          meta: _clientMeta(),
        ),
        JsonRpcCancelTaskRequest(
          id: 'cancel-task-missing',
          cancelParams: const CancelTaskRequest(taskId: 'task-1'),
          meta: _clientMeta(),
        ),
        JsonRpcUpdateTaskRequest(
          id: 'update-task-missing',
          updateParams: const UpdateTaskRequest(
            taskId: 'task-1',
            inputResponses: {},
          ),
          meta: _clientMeta(),
        ),
      ];
      for (final request in missingCapabilityRequests) {
        transport.receive(request);
        await _pump();
      }

      expect(handledMethods, isEmpty);
      final errors = transport.sentMessages.cast<JsonRpcError>().toList();
      expect(errors, hasLength(3));
      for (final response in errors) {
        expect(
          response.error.code,
          ErrorCode.missingRequiredClientCapability.value,
        );
        expect(response.error.message, 'Missing required client capability');
        expect(response.error.data, {
          'requiredCapabilities': {
            'extensions': {
              mcpTasksExtensionId: <String, dynamic>{},
            },
          },
        });
      }

      transport.sentMessages.clear();
      transport.receive(
        JsonRpcGetTaskRequest(
          id: 'get-task-malformed',
          getParams: const GetTaskRequest(taskId: 'task-1'),
          meta: {
            ..._clientMeta(),
            McpMetaKey.clientCapabilities: {
              'extensions': {mcpTasksExtensionId: true},
            },
          },
        ),
      );
      await _pump();

      expect(handledMethods, isEmpty);
      final malformedCapabilityResponse =
          transport.sentMessages.single as JsonRpcError;
      expect(
        malformedCapabilityResponse.error.code,
        ErrorCode.invalidParams.value,
      );
      expect(
        malformedCapabilityResponse.error.message,
        'Invalid stateless request metadata.',
      );

      transport.sentMessages.clear();
      final taskExtensionMeta = _clientMeta(
        clientCapabilities: const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ),
      );
      final declaredCapabilityRequests = <JsonRpcRequest>[
        JsonRpcGetTaskRequest(
          id: 'get-task',
          getParams: const GetTaskRequest(taskId: 'task-1'),
          meta: taskExtensionMeta,
        ),
        JsonRpcCancelTaskRequest(
          id: 'cancel-task',
          cancelParams: const CancelTaskRequest(taskId: 'task-1'),
          meta: taskExtensionMeta,
        ),
        JsonRpcUpdateTaskRequest(
          id: 'update-task',
          updateParams: const UpdateTaskRequest(
            taskId: 'task-1',
            inputResponses: {},
          ),
          meta: taskExtensionMeta,
        ),
      ];
      for (final request in declaredCapabilityRequests) {
        transport.receive(request);
        await _pump();
      }

      final responses = transport.sentMessages.cast<JsonRpcResponse>().toList();
      expect(responses, hasLength(3));
      expect(handledMethods, [
        Method.tasksGet,
        Method.tasksCancel,
        Method.tasksUpdate,
      ]);
      expect(responses[0].result['resultType'], resultTypeComplete);
      expect(responses[0].result['taskId'], 'task-1');
      expect(responses[0].result['ttlMs'], 60000);
      expect(responses[0].result, isNot(contains('ttl')));
      for (final response in responses.skip(1)) {
        expect(response.result['resultType'], resultTypeComplete);
        expect(response.result['_meta'][McpMetaKey.serverInfo], {
          'name': 'server',
          'version': '1.0.0',
        });
      }
    });

    test('server rejects a tasks/get result for a different task', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async => const GetTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'task-2',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:00:01Z',
            ttlMs: null,
          ),
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
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
      expect(response.error.code, ErrorCode.internalError.value);
      expect(response.error.message, contains('task-2'));
      expect(response.error.message, contains('task-1'));
    });

    test('server preserves legacy task methods without extension capability',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.legacy,
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(cancel: true),
          ),
        ),
      );
      final handledMethods = <String>[];
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async {
          handledMethods.add(request.method);
          return const Task(
            taskId: 'task-1',
            status: TaskStatus.completed,
            ttl: null,
            createdAt: '2025-11-25T00:00:00Z',
            lastUpdatedAt: '2025-11-25T00:01:00Z',
          );
        },
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcCancelTaskRequest>(
        Method.tasksCancel,
        (request, extra) async {
          handledMethods.add(request.method);
          return const Task(
            taskId: 'task-1',
            status: TaskStatus.cancelled,
            ttl: null,
            createdAt: '2025-11-25T00:00:00Z',
            lastUpdatedAt: '2025-11-25T00:01:00Z',
          );
        },
        (id, params, meta) => JsonRpcCancelTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksCancel,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);
      addTearDown(server.close);

      transport.receive(
        JsonRpcInitializeRequest(
          id: 'initialize',
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(
              tasks: ClientCapabilitiesTasks(cancel: true),
            ),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();
      transport
        ..sentMessages.clear()
        ..receive(const JsonRpcInitializedNotification());
      await _pump();

      final requests = <JsonRpcRequest>[
        JsonRpcGetTaskRequest(
          id: 'get-task',
          getParams: const GetTaskRequest(taskId: 'task-1'),
        ),
        JsonRpcCancelTaskRequest(
          id: 'cancel-task',
          cancelParams: const CancelTaskRequest(taskId: 'task-1'),
        ),
      ];
      for (final request in requests) {
        transport.receive(request);
        await _pump();
      }

      expect(transport.sentMessages.whereType<JsonRpcError>(), isEmpty);
      expect(transport.sentMessages.whereType<JsonRpcResponse>(), hasLength(2));
      expect(handledMethods, [
        Method.tasksGet,
        Method.tasksCancel,
      ]);
    });

    test('server does not expose legacy task handlers as task extension',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
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
          protocol: McpProtocol.stable,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
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
          protocol: McpProtocol.stable,
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
        )
        ..receive(
          JsonRpcTaskStatusNotification(
            statusParams: const TaskStatusNotification(
              taskId: 'task-1',
              status: TaskStatus.working,
              ttl: null,
              createdAt: '2026-07-28T00:00:00Z',
              lastUpdatedAt: '2026-07-28T00:00:00Z',
            ),
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
          protocol: McpProtocol.stable,
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

    test('stateless tools/call rejects missing tool-required client capability',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerTool(
        'needs_sampling',
        meta: const {
          'io.modelcontextprotocol/requiredClientCapabilities': ['sampling'],
        },
        callback: (args, extra) => const CallToolResult(
          content: [TextContent(text: 'ok')],
        ),
      );
      final transport = ValidationRecordingTransport();
      await server.connect(transport);
      final validator = transport.incomingRequestValidator;
      expect(validator, isNotNull);

      final missingError = validator!(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'needs_sampling').toJson(),
          meta: _clientMeta(),
        ),
      );

      expect(missingError, isNotNull);
      expect(
        missingError!.code,
        ErrorCode.missingRequiredClientCapability.value,
      );
      expect(missingError.data, {
        'requiredCapabilities': {
          'sampling': <String, dynamic>{},
        },
      });

      final allowedError = validator(
        JsonRpcCallToolRequest(
          id: 'call-2',
          params: const CallToolRequest(name: 'needs_sampling').toJson(),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              sampling: ClientCapabilitiesSampling(tools: true),
            ),
          ),
        ),
      );
      expect(allowedError, isNull);
    });

    test('stateless tools/call enforces required capabilities on stdio shapes',
        () async {
      var callbackInvoked = false;
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      addTearDown(server.close);
      server.registerTool(
        'needs_sampling',
        inputSchema: const ToolInputSchema(
          properties: {'count': JsonInteger()},
          required: ['count'],
        ),
        meta: const {
          'io.modelcontextprotocol/requiredClientCapabilities': ['sampling'],
        },
        callback: (args, extra) {
          callbackInvoked = true;
          return const CallToolResult(content: [TextContent(text: 'ok')]);
        },
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-stdio',
          params: const CallToolRequest(
            name: 'needs_sampling',
            arguments: {'count': 'many'},
          ).toJson(),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(
        response.error.code,
        ErrorCode.missingRequiredClientCapability.value,
      );
      expect(callbackInvoked, isFalse);
    });

    test('stateless tools/call ignores malformed legacy task parameter',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
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
            'task': 'not-an-object',
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
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      _registerTaskGetExtensionHandler(server);
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

    test('stateless task support is not inferred from initialize capabilities',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      _registerTaskGetExtensionHandler(server);
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final legacyTransport = RecordingTransport();
      await server.connect(legacyTransport);

      legacyTransport.receive(
        JsonRpcInitializeRequest(
          id: 'init',
          initParams: const InitializeRequest(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(
              extensions: {mcpTasksExtensionId: {}},
            ),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();
      expect(legacyTransport.sentMessages.single, isA<JsonRpcResponse>());
      await server.close();

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
      expect(
        response.error.message,
        contains('Missing required client capability'),
      );
      expect(response.error.data, {
        'requiredCapabilities': {
          'extensions': {
            mcpTasksExtensionId: <String, dynamic>{},
          },
        },
      });
    });

    test('stateless tools/call rejects task result without server extension',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains(mcpTasksExtensionId));
    });

    test('stateless tools/call rejects task result without tasks/get handler',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains('tasks/get handler'));
    });

    test('stateless tools/call rejects task result before task is readable',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      var getTaskCalled = false;
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async {
          getTaskCalled = true;
          throw McpError(
            ErrorCode.invalidParams.value,
            'Task not found',
          );
        },
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

      final response = transport.sentMessages.single as JsonRpcError;
      expect(getTaskCalled, isTrue);
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains('must be resolvable'));
      expect(response.error.data, {'taskId': 'task-1'});
    });

    test('task creation rejects an unserializable durable task state',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
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
            ttlMs: null,
          ),
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains('must be resolvable'));
      expect(response.error.data, {'taskId': 'task-1'});
    });

    test('task creation preserves embedded input capability errors', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async => GetTaskExtensionResult(
          task: TaskExtensionTask(
            taskId: 'task-1',
            status: TaskStatus.inputRequired,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:01:00Z',
            ttlMs: null,
            inputRequests: {
              'approval': InputRequest.elicit(
                ElicitRequest.form(
                  message: 'Approve?',
                  requestedSchema: JsonSchema.object(
                    properties: {'approved': JsonSchema.boolean()},
                  ),
                ),
              ),
            },
          ),
        ),
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

      final response = transport.sentMessages.single as JsonRpcError;
      expect(
        response.error.code,
        ErrorCode.missingRequiredClientCapability.value,
      );
      expect(response.error.data, {
        'inputRequest': 'approval',
        'method': Method.elicitationCreate,
        'requiredCapabilities': {
          'elicitation': {'form': <String, dynamic>{}},
        },
      });
    });

    test('task validation logs but does not expose tasks/get exceptions',
        () async {
      const privateFailure = 'database password=do-not-disclose';
      final logs = <String>[];
      setMcpLogHandler((loggerName, level, message) {
        if (loggerName == 'mcp_dart.server') {
          logs.add(message);
        }
      });

      try {
        final server = Server(
          const Implementation(name: 'server', version: '1.0.0'),
          options: const McpServerOptions(
            protocol: McpProtocol.stable,
            capabilities: ServerCapabilities(
              tools: ServerCapabilitiesTools(),
              extensions: {mcpTasksExtensionId: {}},
            ),
          ),
        );
        server.setRequestHandler<JsonRpcGetTaskRequest>(
          Method.tasksGet,
          (request, extra) async => throw StateError(privateFailure),
          (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
            'jsonrpc': jsonRpcVersion,
            'id': id,
            'method': Method.tasksGet,
            'params': params,
            if (meta != null) '_meta': meta,
          }),
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
            'jsonrpc': jsonRpcVersion,
            'id': id,
            'method': Method.toolsCall,
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

        final response = transport.sentMessages.single as JsonRpcError;
        expect(response.error.code, ErrorCode.invalidParams.value);
        expect(response.error.message, contains('must be resolvable'));
        expect(response.error.data, {'taskId': 'task-1'});
        expect(response.toJson().toString(), isNot(contains(privateFailure)));
        expect(logs.join('\n'), contains(privateFailure));
      } finally {
        resetMcpLogHandler();
      }
    });

    test('stateless tools/call rejects CallToolResult resultType spoof',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async => const CallToolResult(
          content: [TextContent(text: 'spoof')],
          extra: {
            'resultType': resultTypeTask,
            'taskId': 'spoofed-task',
          },
        ),
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'spoof').toJson(),
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
      expect(response.error.message, contains('CallToolResult'));
      expect(response.error.message, contains('resultType'));
    });

    test(
        'stateless tools/call rejects task extension result without capability',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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
      expect(
        response.error.message,
        contains('Missing required client capability'),
      );
      expect(response.error.data, {
        'requiredCapabilities': {
          'extensions': {
            mcpTasksExtensionId: <String, dynamic>{},
          },
        },
      });
    });

    test('stateless tools/call permits input required results', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async =>
            const InputRequiredResult(requestState: 'retry-state'),
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
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

    test('stateless registerTool receives input responses and request state',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerStatelessTool(
        'needs_input',
        callback: (args, extra) {
          final response = extra.inputResponses?['profile'];
          if (response == null) {
            expect(extra.requestState, isNull);
            return InputRequiredResult(
              inputRequests: {
                'profile': InputRequest.elicit(
                  ElicitRequest.form(
                    message: 'Enter profile details',
                    requestedSchema: JsonSchema.object(
                      properties: {'name': JsonSchema.string()},
                      required: ['name'],
                    ),
                  ),
                ),
              },
              requestState: 'state-1',
            );
          }

          expect(extra.requestState, 'state-1');
          final responseJson = response.toJson();
          final content = responseJson['content'] as Map<String, dynamic>;
          return CallToolResult(
            content: [TextContent(text: 'Hello ${content['name']}')],
          );
        },
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'needs_input').toJson(),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              elicitation: ClientElicitation.formOnly(),
            ),
          ),
        ),
      );
      await _pump();

      final inputRequired = transport.sentMessages.single as JsonRpcResponse;
      expect(inputRequired.result['resultType'], resultTypeInputRequired);
      expect(inputRequired.result['requestState'], 'state-1');
      expect(inputRequired.result['inputRequests'], contains('profile'));

      transport.sentMessages.clear();
      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-2',
          params: CallToolRequest(
            name: 'needs_input',
            inputResponses: {
              'profile': InputResponse.fromResult(
                const ElicitResult(
                  action: 'accept',
                  content: {'name': 'Alice'},
                ),
              ),
            },
            requestState: 'state-1',
          ).toJson(),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              elicitation: ClientElicitation.formOnly(),
            ),
          ),
        ),
      );
      await _pump();

      final completed = transport.sentMessages.single as JsonRpcResponse;
      expect(completed.result['resultType'], resultTypeComplete);
      expect(completed.result['content'][0]['text'], 'Hello Alice');
    });

    test('stateless input required requests require client capabilities',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async {
          final inputRequest = switch (request.callParams.name) {
            'needs-form' => InputRequest.elicit(
                ElicitRequest.form(
                  message: 'Enter name',
                  requestedSchema: JsonSchema.object(
                    properties: {'name': JsonSchema.string()},
                    required: ['name'],
                  ),
                ),
              ),
            'needs-url' => InputRequest.elicit(
                const ElicitRequest.url(
                  message: 'Open browser',
                  url: 'https://example.com/authorize',
                ),
              ),
            'needs-roots' => InputRequest.listRoots(),
            'needs-sampling-tools' => InputRequest.createMessage(
                const CreateMessageRequest(
                  messages: [
                    SamplingMessage(
                      role: SamplingMessageRole.user,
                      content: SamplingTextContent(text: 'Search'),
                    ),
                  ],
                  maxTokens: 16,
                  tools: [
                    Tool(name: 'lookup', inputSchema: JsonObject()),
                  ],
                ),
              ),
            _ => throw StateError('Unknown tool ${request.callParams.name}'),
          };

          return InputRequiredResult(
            inputRequests: {request.callParams.name: inputRequest},
          );
        },
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final missingCapabilityCases = [
        (
          name: 'needs-form',
          meta: _clientMeta(),
          method: Method.elicitationCreate,
          requiredCapabilities: {
            'elicitation': {'form': <String, dynamic>{}},
          },
        ),
        (
          name: 'needs-url',
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              elicitation: ClientElicitation.formOnly(),
            ),
          ),
          method: Method.elicitationCreate,
          requiredCapabilities: {
            'elicitation': {'url': <String, dynamic>{}},
          },
        ),
        (
          name: 'needs-roots',
          meta: _clientMeta(),
          method: Method.rootsList,
          requiredCapabilities: {'roots': <String, dynamic>{}},
        ),
        (
          name: 'needs-sampling-tools',
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              sampling: ClientCapabilitiesSampling(),
            ),
          ),
          method: Method.samplingCreateMessage,
          requiredCapabilities: {
            'sampling': {'tools': <String, dynamic>{}},
          },
        ),
      ];

      for (final scenario in missingCapabilityCases) {
        transport.sentMessages.clear();
        transport.receive(
          JsonRpcCallToolRequest(
            id: scenario.name,
            params: CallToolRequest(name: scenario.name).toJson(),
            meta: scenario.meta,
          ),
        );
        await _pump();

        final response = transport.sentMessages.single as JsonRpcError;
        expect(
          response.error.code,
          ErrorCode.missingRequiredClientCapability.value,
        );
        expect(response.error.data['inputRequest'], scenario.name);
        expect(response.error.data['method'], scenario.method);
        expect(
          response.error.data['requiredCapabilities'],
          scenario.requiredCapabilities,
        );
      }

      transport.sentMessages.clear();
      transport.receive(
        JsonRpcCallToolRequest(
          id: 'allowed-form',
          params: const CallToolRequest(name: 'needs-form').toJson(),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              elicitation: ClientElicitation.formOnly(),
            ),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['resultType'], resultTypeInputRequired);
      expect(
        response.result['inputRequests']['needs-form']['method'],
        Method.elicitationCreate,
      );
    });

    test('stateless prompts/get permits input required results', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerStatelessPrompt(
        'needs_input',
        callback: (args, extra) =>
            const InputRequiredResult(requestState: 'prompt-state'),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcGetPromptRequest(
          id: 'prompt-1',
          getParams: const GetPromptRequest(name: 'needs_input'),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['resultType'], resultTypeInputRequired);
      expect(response.result['requestState'], 'prompt-state');
    });

    test('stateless resources/read permits input required results', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      server.registerStatelessResource(
        'needs_input',
        'memory://needs-input',
        null,
        (uri, extra) =>
            const InputRequiredResult(requestState: 'resource-state'),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcReadResourceRequest(
          id: 'resource-1',
          readParams: const ReadResourceRequest(uri: 'memory://needs-input'),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['resultType'], resultTypeInputRequired);
      expect(response.result['requestState'], 'resource-state');
      expect(response.result, isNot(contains('ttlMs')));
      expect(response.result, isNot(contains('cacheScope')));
    });

    test('stateless unsupported methods reject input required results',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities:
              ServerCapabilities(prompts: ServerCapabilitiesPrompts()),
        ),
      );
      server.setRequestHandler<JsonRpcListPromptsRequest>(
        Method.promptsList,
        (request, extra) async =>
            const InputRequiredResult(requestState: 'list-state'),
        (id, params, meta) => JsonRpcListPromptsRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.promptsList,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcListPromptsRequest(id: 'prompts', meta: _clientMeta()),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains('InputRequiredResult'));
      expect(response.error.message, contains(Method.promptsGet));
      expect(response.error.message, contains(Method.resourcesRead));
      expect(response.error.message, contains(Method.toolsCall));
    });

    test('stateless required legacy task tool resolves to final result',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      final handler = CompletedTaskHandler();
      server.experimental.registerToolTask(
        'long',
        handler: handler,
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: {
            ...const CallToolRequest(name: 'long').toJson(),
            'task': {'ttl': 1000},
          },
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['content'][0]['text'], 'task complete');
      expect(handler.lastCreateTaskExtra?.taskRequestedTtl, isNull);
    });

    test('stateless tools/list omits legacy task execution metadata', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
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

    test('stateless custom tools/list handlers omit legacy execution metadata',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(
          tools: [
            Tool(
              name: 'task-tool',
              inputSchema: JsonObject(),
              execution: ToolExecution(taskSupport: 'required'),
            ),
          ],
        ),
        (id, params, meta) => JsonRpcListToolsRequest(
          id: id,
          params: params,
          meta: meta,
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
      expect(response.result['resultType'], resultTypeComplete);
      expect(response.result['ttlMs'], 0);
      expect(response.result['cacheScope'], CacheScope.private);
    });

    test('stateless tools/list returns tools sorted by name', () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
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
          protocol: McpProtocol.stable,
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
            'jsonrpc': jsonRpcVersion,
            'id': id,
            'method': Method.tasksUpdate,
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
          protocol: McpProtocol.stable,
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
        contains(previewProtocolVersion),
      );
      expect(response.result, isNot(contains('serverInfo')));
      expect(response.result['_meta'][McpMetaKey.serverInfo], {
        'name': 'server',
        'version': '1.0.0',
      });
      expect(response.result['instructions'], 'Discovery instructions.');
    });

    test('server discovery emits open capabilities with legacy names',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(list: true),
            additionalCapabilities: {
              'tasks': ['future-task-shape'],
              'elicitation': 'future-elicitation-shape',
            },
          ),
        ),
      );
      addTearDown(server.close);
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover', meta: _clientMeta()),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['capabilities'], {
        'tasks': ['future-task-shape'],
        'elicitation': 'future-elicitation-shape',
      });
    });

    test('server requires stateless metadata after server/discover', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.stable),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover', meta: _clientMeta()),
      );
      await _pump();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());

      transport.receive(
        JsonRpcInitializeRequest(
          id: 'initialize',
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.id, 'initialize');
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(
        response.error.message,
        contains(McpMetaKey.protocolVersion),
      );
    });

    test('server accepts metadata-free cancellation in stateless stdio',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.stable),
      );
      final errors = <Error>[];
      final transport = RecordingTransport();
      await server.connect(transport);
      server.onerror = errors.add;

      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover', meta: _clientMeta()),
      );
      await _pump();

      transport.receive(
        JsonRpcCancelledNotification(
          cancelParams: const CancelledNotification(requestId: 'request'),
        ),
      );
      await _pump();

      expect(errors, isEmpty);
    });

    test('server locks a connection to legacy after initialize', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.stable),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcInitializeRequest(
          id: 'initialize',
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());

      transport.receive(const JsonRpcInitializedNotification());
      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover', meta: _clientMeta()),
      );
      await _pump();

      final response = transport.sentMessages.last as JsonRpcError;
      expect(response.id, 'discover');
      expect(response.error.code, ErrorCode.invalidRequest.value);
      expect(response.error.message, contains('legacy initialize protocol'));
    });

    test('server accepts stateless requests without initialize', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      String? receivedProtocolVersion;
      Implementation? receivedClientInfo;
      ClientCapabilities? receivedClientCapabilities;
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          receivedProtocolVersion = extra.protocolVersion;
          receivedClientInfo = extra.clientInfo;
          receivedClientCapabilities = extra.clientCapabilities;
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
      expect(response.result['_meta'], {
        McpMetaKey.serverInfo: {
          'name': 'server',
          'version': '1.0.0',
        },
      });
      expect(receivedProtocolVersion, previewProtocolVersion);
      expect(receivedClientInfo?.name, 'client');
      expect(receivedClientInfo?.version, '1.0.0');
      expect(receivedClientCapabilities?.toJson(), isEmpty);
    });

    test('server preserves handler result metadata and identity', () async {
      final server = Server(
        const Implementation(name: 'configured', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(
          tools: [],
          meta: {
            'com.example/trace': 'trace-1',
            McpMetaKey.serverInfo: {
              'name': 'handler',
              'version': '2.0.0',
            },
          },
        ),
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
      expect(response.result['_meta'], {
        'com.example/trace': 'trace-1',
        McpMetaKey.serverInfo: {
          'name': 'handler',
          'version': '2.0.0',
        },
      });
      final wireResult = response.toJson()['result'] as Map<String, dynamic>;
      expect(wireResult['_meta'], response.result['_meta']);
      await server.close();
    });

    test('server preserves metadata from legacy custom results', () {
      final result = _serializeStatelessResult(
        const LegacyMetadataResult(
          meta: {'com.example/trace': 'trace-1'},
        ),
      );

      expect(result['_meta'], {
        'com.example/trace': 'trace-1',
        McpMetaKey.serverInfo: {
          'name': 'configured',
          'version': '1.0.0',
        },
      });
    });

    test('explicit serialized metadata is authoritative for custom results',
        () {
      final result = _serializeStatelessResult(
        const LegacyMetadataResult(
          meta: {
            'com.example/handler-only': true,
            'com.example/shared': 'handler',
          },
          serializedMeta: {
            'com.example/serialized-only': true,
            'com.example/shared': 'serialized',
          },
        ),
      );

      expect(result['_meta'], {
        'com.example/shared': 'serialized',
        'com.example/serialized-only': true,
        McpMetaKey.serverInfo: {
          'name': 'configured',
          'version': '1.0.0',
        },
      });
    });

    test('legacy custom subscription metadata survives owned metadata', () {
      final result = _serializeStatelessResult(
        const LegacyMetadataResult(
          meta: {
            'com.example/trace': 'trace-1',
            McpMetaKey.subscriptionId: 'handler-value',
          },
        ),
        request: JsonRpcSubscriptionsListenRequest(
          id: 'sub-1',
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: _clientMeta(),
        ),
      );

      expect(result['_meta'], {
        'com.example/trace': 'trace-1',
        McpMetaKey.subscriptionId: 'sub-1',
        McpMetaKey.serverInfo: {
          'name': 'configured',
          'version': '1.0.0',
        },
      });
    });

    test('legacy custom anonymous identity preserves sibling metadata', () {
      final result = _serializeStatelessResult(
        const LegacyMetadataResult(
          meta: {
            'com.example/trace': 'trace-1',
            McpMetaKey.serverInfo: null,
          },
        ),
      );

      expect(result['_meta'], {
        'com.example/trace': 'trace-1',
      });
    });

    test('server omits anonymous handler identity from the wire', () async {
      final server = Server(
        const Implementation(name: 'configured', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(
          tools: [],
          meta: {
            'com.example/trace': 'trace-1',
            McpMetaKey.serverInfo: null,
          },
        ),
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
      expect(response.result['_meta'], {
        'com.example/trace': 'trace-1',
      });
      expect(response.meta, {
        'com.example/trace': 'trace-1',
      });
      final wireResult = response.toJson()['result'] as Map<String, dynamic>;
      expect(wireResult['_meta'], {
        'com.example/trace': 'trace-1',
      });
      await server.close();
    });

    test('server rejects malformed handler identity before serialization', () {
      final server = Server(
        const Implementation(name: 'configured', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
        ),
      );

      expect(
        () => server.serializeIncomingResult(
          JsonRpcListToolsRequest(id: 1, meta: _clientMeta()),
          const ListToolsResult(
            tools: [],
            meta: {McpMetaKey.serverInfo: 'malformed'},
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy initialize keeps body identity without result metadata',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['serverInfo'], {
        'name': 'server',
        'version': '1.0.0',
      });
      expect(response.result, isNot(contains('_meta')));
      final wireResult = response.toJson()['result'] as Map<String, dynamic>;
      expect(wireResult, isNot(contains('_meta')));
      await server.close();
    });

    test('server accepts stateless requests without client identity', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      RequestHandlerExtra? receivedExtra;
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          receivedExtra = extra;
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
        const JsonRpcListToolsRequest(
          id: 'anonymous-client',
          meta: {
            McpMetaKey.protocolVersion: previewProtocolVersion,
            McpMetaKey.clientCapabilities: <String, dynamic>{},
          },
        ),
      );
      await _pump();

      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      expect(receivedExtra?.clientInfo, isNull);
      expect(receivedExtra?.clientCapabilities?.toJson(), isEmpty);
      await server.close();
    });

    test('server rejects explicitly invalid stateless client identity metadata',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      for (final clientInfo in <Object?>[
        null,
        'not-an-object',
        <String, dynamic>{'name': 'missing-version'},
      ]) {
        transport.receive(
          JsonRpcListToolsRequest(
            id: 'invalid-${clientInfo.runtimeType}',
            meta: {
              McpMetaKey.protocolVersion: previewProtocolVersion,
              McpMetaKey.clientCapabilities: <String, dynamic>{},
              McpMetaKey.clientInfo: clientInfo,
            },
          ),
        );
        await _pump();

        final response = transport.sentMessages.single as JsonRpcError;
        expect(response.error.code, ErrorCode.invalidParams.value);
        transport.sentMessages.clear();
      }

      transport.receive(
        const JsonRpcListToolsRequest(
          id: 'missing-capabilities',
          meta: {
            McpMetaKey.protocolVersion: previewProtocolVersion,
          },
        ),
      );
      await _pump();
      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains(McpMetaKey.clientCapabilities));
      await server.close();
    });

    test('stateless handlers receive request-local client metadata', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      final handlersStarted = Completer<void>();
      final releaseHandlers = Completer<void>();
      final extras = <RequestId, RequestHandlerExtra>{};
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async {
          extras[request.id] = extra;
          if (extras.length == 2 && !handlersStarted.isCompleted) {
            handlersStarted.complete();
          }
          await releaseHandlers.future;
          return const CallToolResult(
            content: [TextContent(text: 'ok')],
          );
        },
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport
        ..receive(
          JsonRpcCallToolRequest(
            id: 'request-a',
            params: const CallToolRequest(name: 'tool-a').toJson(),
            meta: _clientMeta(
              clientInfo: const Implementation(
                name: 'client-a',
                version: '1.0.0',
              ),
              clientCapabilities: const ClientCapabilities(
                sampling: ClientCapabilitiesSampling(tools: true),
              ),
            ),
          ),
        )
        ..receive(
          JsonRpcCallToolRequest(
            id: 'request-b',
            params: const CallToolRequest(name: 'tool-b').toJson(),
            meta: _clientMeta(
              clientInfo: const Implementation(
                name: 'client-b',
                version: '2.0.0',
              ),
              clientCapabilities: const ClientCapabilities(
                extensions: {
                  'com.example/client-b': <String, dynamic>{},
                },
              ),
            ),
          ),
        );
      await handlersStarted.future.timeout(const Duration(seconds: 5));

      final firstExtra = extras['request-a']!;
      final secondExtra = extras['request-b']!;
      expect(firstExtra.clientInfo?.name, 'client-a');
      expect(firstExtra.clientInfo?.version, '1.0.0');
      expect(firstExtra.clientCapabilities?.sampling?.tools, isTrue);
      expect(firstExtra.clientCapabilities?.extensions, isNull);
      expect(secondExtra.clientInfo?.name, 'client-b');
      expect(secondExtra.clientInfo?.version, '2.0.0');
      expect(secondExtra.clientCapabilities?.sampling, isNull);
      expect(
        secondExtra.clientCapabilities?.extensions?['com.example/client-b'],
        isEmpty,
      );

      releaseHandlers.complete();
      await _pump();
      await _pump();
      expect(transport.sentMessages, hasLength(2));
    });

    test('stateless handlers do not inherit transport session identity',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      RequestHandlerExtra? receivedExtra;
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async {
          receivedExtra = extra;
          return const CallToolResult(
            content: [TextContent(text: 'ok')],
          );
        },
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport =
          RecordingTransport(sessionIdValue: 'stateful-session-id');
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'tool').toJson(),
          meta: _clientMeta(),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.result['resultType'], resultTypeComplete);
      expect(receivedExtra?.sessionId, isNull);
    });

    test('server handler client requests stay associated with origin request',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async {
          final result = await extra.sendRequest<ElicitResult>(
            JsonRpcElicitRequest(
              id: -1,
              elicitParams: ElicitRequest.form(
                message: 'Approve tool execution?',
                requestedSchema: JsonSchema.object(
                  properties: {'approved': JsonSchema.boolean()},
                  required: ['approved'],
                ),
              ),
            ),
            ElicitResult.fromJson,
            const RequestOptions(timeout: Duration(seconds: 1)),
          );
          expect(result.accepted, isTrue);
          return const CallToolResult(
            content: [TextContent(text: 'approved')],
          );
        },
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(
              elicitation: ClientElicitation.formOnly(),
            ),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();
      transport
        ..sentMessages.clear()
        ..sentRelatedRequestIds.clear()
        ..receive(const JsonRpcInitializedNotification());
      await _pump();

      transport.receive(
        JsonRpcCallToolRequest(
          id: 42,
          params: const CallToolRequest(name: 'needs-approval').toJson(),
        ),
      );
      await _pump();

      final nestedRequest = transport.sentMessages.single as JsonRpcRequest;
      expect(nestedRequest.method, Method.elicitationCreate);
      expect(transport.sentRelatedRequestIds.single, 42);

      transport.receive(
        JsonRpcResponse(
          id: nestedRequest.id,
          result: const ElicitResult(
            action: 'accept',
            content: {'approved': true},
          ).toJson(),
        ),
      );
      await _pump();

      expect(transport.sentMessages, hasLength(2));
      final response = transport.sentMessages.last as JsonRpcResponse;
      expect(response.id, 42);
      expect(response.result['content'][0]['text'], 'approved');
    });

    test('stateless server handlers reject nested client requests', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async {
          await extra.sendRequest<ElicitResult>(
            JsonRpcElicitRequest(
              id: -1,
              elicitParams: ElicitRequest.form(
                message: 'Must be embedded',
                requestedSchema: JsonSchema.object(properties: const {}),
              ),
            ),
            ElicitResult.fromJson,
            const RequestOptions(),
          );
          return const CallToolResult(content: []);
        },
        (id, params, meta) => JsonRpcCallToolRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.toolsCall,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcCallToolRequest(
          id: 'call-1',
          params: const CallToolRequest(name: 'nested').toJson(),
          meta: _clientMeta(
            clientCapabilities: const ClientCapabilities(
              elicitation: ClientElicitation.formOnly(),
            ),
          ),
        ),
      );
      await _pump();

      final error = transport.sentMessages.single as JsonRpcError;
      expect(error.id, 'call-1');
      expect(error.error.code, ErrorCode.internalError.value);
      expect(
        error.error.message,
        contains('Internal server error processing ${Method.toolsCall}'),
      );
      expect(
        transport.sentMessages.whereType<JsonRpcRequest>(),
        isEmpty,
      );
    });

    test('stateless servers reject legacy server-initiated helpers', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.stable),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final statelessError = isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('not supported by stateless MCP'),
      );
      expect(() => server.ping(), throwsA(statelessError));
      expect(
        () => server.request<EmptyResult>(
          const JsonRpcRequest(id: -1, method: 'custom/server-request'),
          EmptyResult.fromJson,
        ),
        throwsA(statelessError),
      );
      expect(
        () => server.createMessage(
          const CreateMessageRequest(
            messages: [
              SamplingMessage(
                role: SamplingMessageRole.user,
                content: SamplingTextContent(text: 'sample'),
              ),
            ],
            maxTokens: 1,
          ),
        ),
        throwsA(statelessError),
      );
      await expectLater(
        server.elicitInput(
          ElicitRequest.form(
            message: 'input',
            requestedSchema: JsonSchema.object(properties: const {}),
          ),
        ),
        throwsA(statelessError),
      );
      expect(() => server.listRoots(), throwsA(statelessError));
      expect(
        () => server.createElicitationCompletionNotifier('elicit-1'),
        throwsA(statelessError),
      );
      expect(transport.sentMessages, isEmpty);

      await expectLater(
        server.notification(const JsonRpcToolListChangedNotification()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(Method.subscriptionsListen),
          ),
        ),
      );
      expect(transport.sentMessages, isEmpty);

      for (final method in const [
        Method.notificationsMessage,
        Method.notificationsProgress,
        Method.notificationsCancelled,
      ]) {
        await expectLater(
          server.notification(JsonRpcNotification(method: method)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('cannot be emitted globally'),
            ),
          ),
        );
      }
      expect(transport.sentMessages, isEmpty);

      await server.notification(
        const JsonRpcNotification(method: 'example/custom-notification'),
      );
      expect(
        transport.sentMessages.single,
        isA<JsonRpcNotification>().having(
          (notification) => notification.method,
          'method',
          'example/custom-notification',
        ),
      );
    });

    test('server initialize never negotiates stateless draft version',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: previewProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(
        response.result['protocolVersion'],
        latestInitializationProtocolVersion,
      );
      expect(
        response.result['protocolVersion'],
        isNot(defaultProtocolVersion),
      );
    });

    test('server rejects removed draft protocol alias', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      transport.receive(
        JsonRpcListToolsRequest(
          id: 1,
          meta:
              _clientMeta(protocolVersion: _removedDraftProtocolVersion2026V1),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.unsupportedProtocolVersion.value);
      expect(
        response.error.data['requested'],
        _removedDraftProtocolVersion2026V1,
      );
      expect(
        response.error.data['supported'],
        contains(previewProtocolVersion),
      );
    });

    test('server rejects malformed stateless request metadata', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
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
          _clientMeta(protocolVersion: latestInitializationProtocolVersion),
        ),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains('stateless protocol version'),
        ),
      );
      expect(
        validateToolRequest({
          McpMetaKey.protocolVersion: previewProtocolVersion,
          McpMetaKey.clientCapabilities: <String, dynamic>{},
        }),
        isNull,
      );
      expect(
        validateToolRequest({
          McpMetaKey.protocolVersion: previewProtocolVersion,
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
          McpMetaKey.protocolVersion: previewProtocolVersion,
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
        validateToolRequest({
          McpMetaKey.protocolVersion: previewProtocolVersion,
          McpMetaKey.clientInfo: {
            'name': 'client',
            'version': '1.0.0',
          },
          McpMetaKey.clientCapabilities: {
            'experimental': {'feature': true},
          },
        }),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains('Invalid stateless request metadata.'),
        ),
      );
      for (final malformedCapabilities in <Map<String, dynamic>>[
        {'roots': true},
        {
          'sampling': {'tools': true},
        },
        {
          'elicitation': {'form': true},
        },
      ]) {
        expect(
          validateToolRequest({
            McpMetaKey.protocolVersion: previewProtocolVersion,
            McpMetaKey.clientCapabilities: malformedCapabilities,
          }),
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.invalidParams.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Invalid stateless request metadata.'),
              ),
          reason: '$malformedCapabilities',
        );
      }
      expect(
        validateToolRequest(_clientMeta(logLevel: 'verbose')),
        isA<McpError>().having(
          (error) => error.message,
          'message',
          contains(McpMetaKey.logLevel),
        ),
      );
      expect(
        validateToolRequest({
          ..._clientMeta(),
          'bad prefix/value': 'value',
        }),
        isA<McpError>()
            .having(
              (error) => error.code,
              'code',
              ErrorCode.invalidParams.value,
            )
            .having(
              (error) => error.data,
              'data',
              contains('bad prefix/value'),
            ),
      );
      expect(
        validateToolRequest(
          _clientMeta(meta: const {'com.example.trace/id': 'trace-1'}),
        ),
        isNull,
      );
      expect(
        validateToolRequest(
          _clientMeta(
            clientCapabilities: const ClientCapabilities(
              additionalCapabilities: {
                'com.example/clientFeature': {'enabled': true},
              },
            ),
          ),
        ),
        isNull,
      );

      const statelessCapabilityJson = <String, dynamic>{
        'roots': {'listChanged': 'future-value'},
        'elicitation': {
          'form': {'applyDefaults': 'future-value'},
        },
        'tasks': ['future-task-shape'],
      };
      expect(
        validateToolRequest({
          McpMetaKey.protocolVersion: previewProtocolVersion,
          McpMetaKey.clientCapabilities: statelessCapabilityJson,
        }),
        isNull,
      );
      final statelessCapabilities =
          ClientCapabilities.fromStatelessJson(statelessCapabilityJson);
      expect(statelessCapabilities.roots?.listChanged, isNull);
      expect(
        statelessCapabilities.elicitation?.form?.applyDefaults,
        isNull,
      );
      expect(statelessCapabilities.additionalCapabilities, {
        'tasks': ['future-task-shape'],
      });
      expect(
        statelessCapabilities.toJson(
          omitLegacyTasks: true,
          omitLegacyRootsListChanged: true,
        ),
        {
          'roots': <String, dynamic>{},
          'elicitation': {
            'form': <String, dynamic>{},
          },
          'tasks': ['future-task-shape'],
        },
      );

      // Keep the long-standing public parser compatibility; strict object
      // markers are enforced only at the 2026 stateless wire boundary above.
      final legacyCapabilities = ClientCapabilities.fromJson({
        'sampling': true,
        'tasks': {'list': true},
      });
      expect(legacyCapabilities.sampling, isNotNull);
      expect(legacyCapabilities.tasks?.list, isTrue);
    });

    test(
        'stateless-only and selected-stateless servers reject missing metadata as invalid params',
        () async {
      final statelessOnlyServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
        ),
      );
      addTearDown(statelessOnlyServer.close);

      final initialError = statelessOnlyServer.validateIncomingRequest(
        const JsonRpcListToolsRequest(id: 'stateless-only-missing-meta'),
      );
      expect(initialError?.code, ErrorCode.invalidParams.value);
      expect(initialError?.message, contains(McpMetaKey.protocolVersion));

      final compatibleServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.stable),
      );
      addTearDown(compatibleServer.close);
      final transport = RecordingTransport();
      await compatibleServer.connect(transport);

      transport.receive(
        JsonRpcServerDiscoverRequest(
          id: 'discover',
          meta: _clientMeta(),
        ),
      );
      await _pump();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      transport.sentMessages.clear();
      transport.sentRelatedRequestIds.clear();

      transport.receive(
        const JsonRpcListToolsRequest(id: 'selected-missing-meta'),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.error.code, ErrorCode.invalidParams.value);
      expect(response.error.message, contains(McpMetaKey.protocolVersion));
    });

    test('server rejects core RPCs removed from stateless MCP', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final removedRequests = <JsonRpcRequest>[
        JsonRpcRequest(
          id: 1,
          method: Method.initialize,
          params: const {
            'protocolVersion': previewProtocolVersion,
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
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
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
        previewProtocolVersion,
      );
      expect(
        rootsListChanged.meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
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

      transport.receive(
        JsonRpcServerDiscoverRequest(id: 'discover', meta: _clientMeta()),
      );
      await _pump();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      errors.clear();

      for (final method in const {
        Method.notificationsInitialized,
        Method.notificationsProgress,
        Method.notificationsResourcesListChanged,
        Method.notificationsResourcesUpdated,
        Method.notificationsSubscriptionsAcknowledged,
        Method.notificationsPromptsListChanged,
        Method.notificationsToolsListChanged,
        Method.notificationsMessage,
        Method.notificationsRootsListChanged,
        Method.notificationsTasksStatus,
        Method.notificationsTasks,
        Method.notificationsElicitationComplete,
      }) {
        errors.clear();
        transport.receive(JsonRpcNotification(method: method));
        await _pump();

        final error = errors.single as McpError;
        expect(error.code, ErrorCode.methodNotFound.value, reason: method);
        expect(error.message, contains(method), reason: method);
      }

      errors.clear();
      transport.receive(
        const JsonRpcNotification(method: 'com.example/notifications/custom'),
      );
      await _pump();
      expect(errors, isEmpty);
    });

    test('server gates stateless logging by request metadata', () async {
      late Server server;
      server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            logging: {},
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          await server.sendStatelessLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.debug,
              data: 'skip',
            ),
            requestMeta: extra.meta,
            requestId: extra.requestId,
          );
          await server.sendStatelessLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.warning,
              data: 'emit',
            ),
            requestMeta: extra.meta,
            requestId: extra.requestId,
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
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            logging: {},
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          await server.sendStatelessLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.error,
              data: 'skip',
            ),
            requestMeta: extra.meta,
            requestId: extra.requestId,
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

    test('legacy logging helper never emits for stateless requests', () async {
      late Server server;
      server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
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
              data: 'must stay request-scoped',
            ),
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

      for (final meta in <Map<String, dynamic>>[
        _clientMeta(),
        _clientMeta(logLevel: LoggingLevel.debug.name),
      ]) {
        transport.sentMessages.clear();
        transport.receive(JsonRpcListToolsRequest(id: 1, meta: meta));
        await _pump();

        expect(transport.sentMessages, hasLength(1));
        expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      }
    });

    test('stable client uses server/discover and sends stateless metadata',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
        ),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), previewProtocolVersion);
      expect(transport.protocolVersion, previewProtocolVersion);
      expect(
        (transport.sentMessages.single as JsonRpcRequest).method,
        Method.serverDiscover,
      );

      await client.listTools();

      final listRequest = transport.sentMessages.last as JsonRpcRequest;
      expect(listRequest.method, Method.toolsList);
      expect(
        listRequest.meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
      expect(listRequest.meta?[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
      expect(listRequest.meta?[McpMetaKey.clientCapabilities], {});
    });

    test(
      'stable client rejects malformed discovery capabilities without fallback',
      () async {
        final transport = DiscoveringClientTransport(
          discoverCapabilitiesJson: const {'tools': true},
        );
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
        );

        await expectLater(
          client.connect(transport),
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
                  'Failed to parse result for ${Method.serverDiscover}',
                ),
          ),
        );
        expect(
          transport.sentMessages.whereType<JsonRpcRequest>().map(
                (message) => message.method,
              ),
          [Method.serverDiscover],
        );
      },
    );

    test('stable client accepts additional discovery capability values',
        () async {
      final transport = DiscoveringClientTransport(
        discoverCapabilitiesJson: const {
          'tools': <String, dynamic>{},
          'com.example/futureCapability': true,
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );
      addTearDown(client.close);

      await client.connect(transport);

      expect(client.getServerCapabilities()?.additionalCapabilities, {
        'com.example/futureCapability': true,
      });
    });

    test('client discovery succeeds without server identity', () async {
      final transport = DiscoveringClientTransport(discoverServerInfo: null);
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), previewProtocolVersion);
      expect(client.getServerVersion(), isNull);
    });

    test('stateless client rejects legacy task request options before send',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
        ),
      );

      await client.connect(transport);
      final sentBeforeCall = transport.sentMessages.length;

      await expectLater(
        client.callTool(
          const CallToolRequest(name: 'echo'),
          options: const RequestOptions(task: TaskCreation(ttl: 1000)),
        ),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.invalidRequest.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('RequestOptions.task'),
              )
              .having(
                (error) => error.message,
                'message',
                contains(mcpTasksExtensionId),
              ),
        ),
      );

      expect(transport.sentMessages, hasLength(sentBeforeCall));
    });

    test('client negotiates the stateless protocol by default', () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), previewProtocolVersion);
      expect(transport.protocolVersion, previewProtocolVersion);
      expect(
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        [Method.serverDiscover],
      );
      final discoverRequest = transport.sentMessages.single as JsonRpcRequest;
      expect(
        discoverRequest.meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
    });

    test('client falls back when legacy HTTP rejects discovery before init',
        () async {
      final errors = [
        McpError(
          0,
          'Error POSTing to endpoint (HTTP 400): '
          '{"jsonrpc":"2.0","error":{"code":-32000,'
          '"message":"Bad Request: Server not initialized"},"id":null}',
        ),
        McpError(0, 'Error POSTing to endpoint (HTTP 400): '),
        McpError(
          ErrorCode.invalidParams.value,
          'Legacy parser rejected discovery',
        ),
        McpError(
          ErrorCode.internalError.value,
          'Legacy server failed before initialize',
        ),
      ];

      for (final error in errors) {
        final transport = LegacyFallbackTransport(discoveryError: error);
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: const McpClientOptions(
            protocol: McpProtocol.stable,
          ),
        );

        await client.connect(transport);

        expect(
          client.getProtocolVersion(),
          latestInitializationProtocolVersion,
        );
        expect(transport.protocolVersion, latestInitializationProtocolVersion);
        expect(
          transport.sentMessages
              .whereType<JsonRpcRequest>()
              .map((message) => message.method),
          [Method.serverDiscover, Method.initialize],
        );
      }
    });

    test('stateless client rejects removed request methods before send',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      final removedRequests = <({String method, Future<void> Function() call})>[
        (
          method: Method.ping,
          call: () async {
            await client.ping();
          },
        ),
        (
          method: Method.loggingSetLevel,
          call: () async {
            await client.setLoggingLevel(LoggingLevel.debug);
          },
        ),
        (
          method: Method.resourcesSubscribe,
          call: () async {
            await client.subscribeResource(
              const SubscribeRequest(uri: 'file:///tmp/example.txt'),
            );
          },
        ),
        (
          method: Method.resourcesUnsubscribe,
          call: () async {
            await client.unsubscribeResource(
              const UnsubscribeRequest(uri: 'file:///tmp/example.txt'),
            );
          },
        ),
        (
          method: Method.tasksList,
          call: () async {
            await client.request<ListTasksResult>(
              JsonRpcListTasksRequest(id: -1),
              ListTasksResult.fromJson,
            );
          },
        ),
        (
          method: Method.tasksResult,
          call: () async {
            await client.request<CallToolResult>(
              JsonRpcTaskResultRequest(
                id: -1,
                resultParams: const TaskResultRequest(taskId: 'task-1'),
              ),
              CallToolResult.fromJson,
            );
          },
        ),
      ];

      for (final scenario in removedRequests) {
        await expectLater(
          scenario.call(),
          throwsA(
            isA<McpError>()
                .having(
                  (error) => error.code,
                  'code',
                  ErrorCode.methodNotFound.value,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains(scenario.method),
                ),
          ),
        );
      }

      expect(transport.sentMessages, isEmpty);
    });

    test('stateless client rejects known wrong-direction notifications',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      final removedNotifications =
          <({String method, Future<void> Function() call})>[
        (
          method: Method.notificationsInitialized,
          call: () => client.notification(
                const JsonRpcInitializedNotification(),
              ),
        ),
        (
          method: Method.notificationsRootsListChanged,
          call: client.sendRootsListChanged,
        ),
        (
          method: Method.notificationsTasksStatus,
          call: () => client.notification(
                JsonRpcTaskStatusNotification(
                  statusParams: const TaskStatusNotification(
                    taskId: 'task-1',
                    status: TaskStatus.working,
                    ttl: null,
                    createdAt: '2026-07-28T00:00:00Z',
                    lastUpdatedAt: '2026-07-28T00:00:00Z',
                  ),
                ),
              ),
        ),
        for (final method in const {
          Method.notificationsProgress,
          Method.notificationsResourcesListChanged,
          Method.notificationsResourcesUpdated,
          Method.notificationsSubscriptionsAcknowledged,
          Method.notificationsPromptsListChanged,
          Method.notificationsToolsListChanged,
          Method.notificationsMessage,
          Method.notificationsTasks,
          Method.notificationsElicitationComplete,
        })
          (
            method: method,
            call: () => client.notification(
                  JsonRpcNotification(method: method),
                ),
          ),
      ];

      for (final scenario in removedNotifications) {
        await expectLater(
          scenario.call(),
          throwsA(
            isA<McpError>()
                .having(
                  (error) => error.code,
                  'code',
                  ErrorCode.methodNotFound.value,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains(scenario.method),
                ),
          ),
        );
      }

      expect(transport.sentMessages, isEmpty);

      await client.notification(
        const JsonRpcNotification(
          method: 'com.example/notifications/custom',
        ),
      );
      final sentNotification =
          transport.sentMessages.single as JsonRpcNotification;
      expect(
        sentNotification.method,
        'com.example/notifications/custom',
      );
    });

    test('stateless client rejects server-initiated requests on transport',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(roots: ClientCapabilitiesRoots()),
          useServerDiscover: true,
        ),
      );
      final errors = <Error>[];
      client.onerror = errors.add;
      await client.connect(transport);
      transport.sentMessages.clear();

      transport.onmessage?.call(const JsonRpcListRootsRequest(id: 'roots-1'));
      await _pump();

      expect(transport.sentMessages, isEmpty);
      expect(
        errors.single,
        isA<McpError>()
            .having(
              (error) => error.code,
              'code',
              ErrorCode.invalidRequest.value,
            )
            .having(
              (error) => error.message,
              'message',
              allOf(contains('input_required'), contains('inputRequests')),
            ),
      );
    });

    test(
        'stateless client reports method not found for unadvertised peer method',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      final errors = <Error>[];
      client.onerror = errors.add;
      await client.connect(transport);
      transport.sentMessages.clear();

      transport.onmessage?.call(const JsonRpcListRootsRequest(id: 'roots-1'));
      await _pump();

      expect(transport.sentMessages, isEmpty);
      expect(
        errors.single,
        isA<McpError>()
            .having(
              (error) => error.code,
              'code',
              ErrorCode.methodNotFound.value,
            )
            .having(
              (error) => error.message,
              'message',
              contains('roots'),
            ),
      );
    });

    for (final protocol in [McpProtocol.legacy, McpProtocol.stable]) {
      test(
          '$protocol client rejects 2026-only input_required results after '
          'initialization', () async {
        late LegacyFallbackTransport transport;
        final receivedMethods = <String>[];
        transport = LegacyFallbackTransport(
          capabilities: const ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            prompts: ServerCapabilitiesPrompts(),
            resources: ServerCapabilitiesResources(),
          ),
          onRequest: (request) {
            receivedMethods.add(request.method);
            transport.onmessage?.call(
              JsonRpcResponse(
                id: request.id,
                result: const InputRequiredResult(
                  requestState: '2026-only-state',
                ).toJson(),
              ),
            );
          },
        );
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: McpClientOptions(protocol: protocol),
        );
        await client.connect(transport);
        transport.sentMessages.clear();

        final scenarios = <({
          String method,
          Future<BaseResultData> Function() invoke,
        })>[
          (
            method: Method.toolsCall,
            invoke: () => client.callTool(
                  const CallToolRequest(name: 'needs-input'),
                ),
          ),
          (
            method: Method.promptsGet,
            invoke: () => client.getPrompt(
                  const GetPromptRequest(name: 'needs-input'),
                ),
          ),
          (
            method: Method.resourcesRead,
            invoke: () => client.readResource(
                  const ReadResourceRequest(uri: 'memory://needs-input'),
                ),
          ),
        ];

        for (final scenario in scenarios) {
          final sentBefore = transport.sentMessages.length;
          await expectLater(
            scenario.invoke(),
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
                    contains('Failed to parse result for ${scenario.method}'),
                  )
                  .having(
                    (error) => error.data.toString(),
                    'data',
                    allOf(
                      contains(resultTypeInputRequired),
                      contains('initialization-era MCP'),
                    ),
                  ),
            ),
          );
          expect(transport.sentMessages.length, sentBefore + 1);
        }

        expect(receivedMethods, [
          Method.toolsCall,
          Method.promptsGet,
          Method.resourcesRead,
        ]);
        await client.close();
      });
    }

    test(
        'client retries tools/call with the legacy default form capability '
        'after fulfilling input_required requests', () async {
      late DiscoveringClientTransport transport;
      final callRequests = <JsonRpcRequest>[];
      transport = DiscoveringClientTransport(
        onRequest: (request) {
          if (request.method != Method.toolsCall) {
            return;
          }

          callRequests.add(request);
          if (callRequests.length == 1) {
            transport.onmessage?.call(
              JsonRpcResponse(
                id: request.id,
                result: InputRequiredResult(
                  requestState: 'state-1',
                  inputRequests: {
                    'profile': InputRequest.elicit(
                      ElicitRequest.form(
                        message: 'Enter profile',
                        requestedSchema: JsonSchema.object(
                          properties: {'name': JsonSchema.string()},
                          required: ['name'],
                        ),
                      ),
                    ),
                    'roots': InputRequest.listRoots(),
                  },
                ).toJson(),
              ),
            );
            return;
          }

          expect(request.params?['requestState'], 'state-1');
          final inputResponses =
              request.params?['inputResponses'] as Map<String, dynamic>;
          expect(inputResponses['profile'], {
            'action': 'accept',
            'content': {'name': 'Ada'},
          });
          expect(inputResponses['roots'], {
            'roots': [
              {'uri': 'file:///repo'},
            ],
          });
          transport.onmessage?.call(
            JsonRpcResponse(
              id: request.id,
              result: {
                'resultType': resultTypeComplete,
                ...const CallToolResult(
                  content: [TextContent(text: 'ok')],
                ).toJson(),
              },
            ),
          );
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation(),
            roots: ClientCapabilitiesRoots(),
          ),
        ),
      );
      client.onElicitRequest = (params) async {
        expect(params.message, 'Enter profile');
        return const ElicitResult(
          action: 'accept',
          content: {'name': 'Ada'},
        );
      };
      client.setRequestHandler<JsonRpcListRootsRequest>(
        Method.rootsList,
        (request, extra) async => ListRootsResult(
          roots: [Root(uri: 'file:///repo')],
        ),
        (id, params, meta) => JsonRpcListRootsRequest(id: id, meta: meta),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      final result = await client.callTool(
        const CallToolRequest(name: 'lookup'),
      );

      expect((result.content.single as TextContent).text, 'ok');
      expect(callRequests, hasLength(2));
      expect(callRequests[1].id, isNot(callRequests[0].id));
    });

    test('client rejects embedded input requests for unadvertised capabilities',
        () async {
      final cases = [
        (
          name: 'roots',
          capabilities: const ClientCapabilities(),
          request: InputRequest.listRoots(),
          required: {'roots': <String, dynamic>{}},
        ),
        (
          name: 'form elicitation',
          capabilities: const ClientCapabilities(
            elicitation: ClientElicitation.urlOnly(),
          ),
          request: InputRequest.elicit(
            ElicitRequest.form(
              message: 'Form input',
              requestedSchema: JsonSchema.object(properties: const {}),
            ),
          ),
          required: {
            'elicitation': {'form': <String, dynamic>{}},
          },
        ),
        (
          name: 'URL elicitation',
          capabilities: const ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
          request: InputRequest.elicit(
            const ElicitRequest.url(
              message: 'Open URL',
              url: 'https://example.com/approve',
            ),
          ),
          required: {
            'elicitation': {'url': <String, dynamic>{}},
          },
        ),
        (
          name: 'sampling tools',
          capabilities: const ClientCapabilities(
            sampling: ClientCapabilitiesSampling(),
          ),
          request: InputRequest.createMessage(
            const CreateMessageRequest(
              messages: [
                SamplingMessage(
                  role: SamplingMessageRole.user,
                  content: SamplingTextContent(text: 'Use a tool'),
                ),
              ],
              maxTokens: 32,
              tools: [Tool(name: 'lookup', inputSchema: JsonObject())],
            ),
          ),
          required: {
            'sampling': {'tools': <String, dynamic>{}},
          },
        ),
        (
          name: 'sampling context',
          capabilities: const ClientCapabilities(
            sampling: ClientCapabilitiesSampling(),
          ),
          request: InputRequest.createMessage(
            const CreateMessageRequest(
              messages: [
                SamplingMessage(
                  role: SamplingMessageRole.user,
                  content: SamplingTextContent(text: 'Use context'),
                ),
              ],
              includeContext: IncludeContext.thisServer,
              maxTokens: 32,
            ),
          ),
          required: {
            'sampling': {'context': <String, dynamic>{}},
          },
        ),
      ];

      for (final scenario in cases) {
        var handlerInvoked = false;
        late DiscoveringClientTransport transport;
        transport = DiscoveringClientTransport(
          onRequest: (request) {
            if (request.method == Method.toolsCall) {
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: InputRequiredResult(
                    inputRequests: {'blocked': scenario.request},
                  ).toJson(),
                ),
              );
            }
          },
        );
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: McpClientOptions(
            protocol: McpProtocol.stable,
            capabilities: scenario.capabilities,
          ),
        );
        client
          ..fallbackRequestHandler = (request) async {
            handlerInvoked = true;
            return const EmptyResult();
          }
          ..onElicitRequest = (request) async {
            handlerInvoked = true;
            return const ElicitResult(action: 'decline');
          }
          ..onSamplingRequest = (request) async {
            handlerInvoked = true;
            throw StateError('must not be invoked');
          };
        await client.connect(transport);
        transport.sentMessages.clear();

        await expectLater(
          client.callTool(CallToolRequest(name: scenario.name)),
          throwsA(
            isA<McpError>()
                .having(
                  (error) => error.code,
                  'code',
                  ErrorCode.missingRequiredClientCapability.value,
                )
                .having(
                  (error) => error.data['requiredCapabilities'],
                  'requiredCapabilities',
                  scenario.required,
                ),
          ),
          reason: scenario.name,
        );
        expect(handlerInvoked, isFalse, reason: scenario.name);
        await client.close();
      }
    });

    test('client resolves task resultType tools/call responses', () async {
      late DiscoveringClientTransport transport;
      final requests = <JsonRpcRequest>[];
      transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
          extensions: withMcpTasksExtension(null),
        ),
        onRequest: (request) {
          requests.add(request);
          switch (request.method) {
            case Method.toolsCall:
              expect(request.params?['name'], 'delayed');
              final clientCapabilities = request
                  .meta?[McpMetaKey.clientCapabilities] as Map<String, dynamic>;
              expect(
                clientCapabilities['extensions'][mcpTasksExtensionId],
                <String, dynamic>{},
              );
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const CreateTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-1',
                      status: TaskStatus.working,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:01Z',
                      ttlMs: null,
                      pollIntervalMs: 1,
                    ),
                  ).toJson(),
                ),
              );
              break;

            case Method.tasksGet:
              expect(request.params?['taskId'], 'task-1');
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const GetTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-1',
                      status: TaskStatus.completed,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:02Z',
                      ttlMs: null,
                      result: {
                        'content': [
                          {'type': 'text', 'text': 'task done'},
                        ],
                        'isError': false,
                      },
                    ),
                  ).toJson(),
                ),
              );
              break;
          }
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(
            extensions: withMcpTasksExtension(null),
          ),
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      final result = await client.callTool(
        const CallToolRequest(name: 'delayed'),
      );

      expect((result.content.single as TextContent).text, 'task done');
      expect(requests.map((request) => request.method), [
        Method.toolsCall,
        Method.tasksGet,
      ]);
    });

    test('client rejects tasks/get responses for a different task', () async {
      late DiscoveringClientTransport transport;
      var getTaskRequests = 0;
      transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
          extensions: withMcpTasksExtension(null),
        ),
        onRequest: (request) {
          switch (request.method) {
            case Method.toolsCall:
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const CreateTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-1',
                      status: TaskStatus.working,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:01Z',
                      ttlMs: null,
                      pollIntervalMs: 0,
                    ),
                  ).toJson(),
                ),
              );
              break;
            case Method.tasksGet:
              getTaskRequests += 1;
              expect(request.params?['taskId'], 'task-1');
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const GetTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-2',
                      status: TaskStatus.completed,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:02Z',
                      ttlMs: null,
                      result: {
                        'content': [
                          {'type': 'text', 'text': 'wrong task'},
                        ],
                        'isError': false,
                      },
                    ),
                  ).toJson(),
                ),
              );
              break;
          }
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(
            extensions: withMcpTasksExtension(null),
          ),
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      await expectLater(
        client.callTool(const CallToolRequest(name: 'delayed')),
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
                allOf(contains('task-1'), contains('task-2')),
              ),
        ),
      );
      expect(getTaskRequests, 1);
      await client.close();
    });

    test('client sends request-scoped stateless logging metadata', () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );
      await client.connect(transport);
      expect(client.isConnected, isTrue);
      transport.sentMessages.clear();

      await client.listTools(
        options: const RequestOptions(logLevel: LoggingLevel.debug),
      );

      final request = transport.sentMessages.single as JsonRpcRequest;
      expect(request.method, Method.toolsList);
      expect(request.meta?[McpMetaKey.logLevel], 'debug');
      await client.close();
      expect(client.isConnected, isFalse);
    });

    test('client handles input_required before task resultType tools/call',
        () async {
      late DiscoveringClientTransport transport;
      final requests = <JsonRpcRequest>[];
      transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
          extensions: withMcpTasksExtension(null),
        ),
        onRequest: (request) {
          requests.add(request);
          switch (request.method) {
            case Method.toolsCall:
              if (requests
                      .where((sent) => sent.method == Method.toolsCall)
                      .length ==
                  1) {
                transport.onmessage?.call(
                  JsonRpcResponse(
                    id: request.id,
                    result: InputRequiredResult(
                      requestState: 'approved-state',
                      inputRequests: {
                        'approval': InputRequest.elicit(
                          ElicitRequest.form(
                            message: 'Approve async work?',
                            requestedSchema: JsonSchema.object(
                              properties: {
                                'approved': JsonSchema.boolean(),
                              },
                              required: ['approved'],
                            ),
                          ),
                        ),
                      },
                    ).toJson(),
                  ),
                );
                return;
              }

              expect(request.params?['requestState'], 'approved-state');
              expect(
                request.params?['inputResponses']['approval'],
                {
                  'action': 'accept',
                  'content': {'approved': true},
                },
              );
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const CreateTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-after-mrtr',
                      status: TaskStatus.working,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:01Z',
                      ttlMs: null,
                      pollIntervalMs: 1,
                    ),
                  ).toJson(),
                ),
              );
              break;

            case Method.tasksGet:
              expect(request.params?['taskId'], 'task-after-mrtr');
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const GetTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-after-mrtr',
                      status: TaskStatus.completed,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:02Z',
                      ttlMs: null,
                      result: {
                        'content': [
                          {'type': 'text', 'text': 'approved task done'},
                        ],
                      },
                    ),
                  ).toJson(),
                ),
              );
              break;
          }
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(
            elicitation: const ClientElicitation.formOnly(),
            extensions: withMcpTasksExtension(null),
          ),
        ),
      );
      client.onElicitRequest = (params) async {
        expect(params.message, 'Approve async work?');
        return const ElicitResult(
          action: 'accept',
          content: {'approved': true},
        );
      };
      await client.connect(transport);
      transport.sentMessages.clear();

      final result = await client.callTool(
        const CallToolRequest(name: 'async-approval-tool'),
      );

      expect((result.content.single as TextContent).text, 'approved task done');
      expect(requests.map((request) => request.method), [
        Method.toolsCall,
        Method.toolsCall,
        Method.tasksGet,
      ]);
    });

    test('client updates task input requests once while polling', () async {
      late DiscoveringClientTransport transport;
      var getCount = 0;
      var updateCount = 0;
      transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
          extensions: withMcpTasksExtension(null),
        ),
        onRequest: (request) {
          switch (request.method) {
            case Method.toolsCall:
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const CreateTaskExtensionResult(
                    task: TaskExtensionTask(
                      taskId: 'task-2',
                      status: TaskStatus.working,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:01Z',
                      ttlMs: null,
                      pollIntervalMs: 1,
                    ),
                  ).toJson(),
                ),
              );
              break;

            case Method.tasksGet:
              getCount += 1;
              final task = getCount < 3
                  ? TaskExtensionTask(
                      taskId: 'task-2',
                      status: TaskStatus.inputRequired,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:02Z',
                      ttlMs: null,
                      pollIntervalMs: 1,
                      inputRequests: {
                        'approval': InputRequest.elicit(
                          ElicitRequest.form(
                            message: 'Approve?',
                            requestedSchema: JsonSchema.object(
                              properties: {
                                'approved': JsonSchema.boolean(),
                              },
                              required: ['approved'],
                            ),
                          ),
                        ),
                      },
                    )
                  : const TaskExtensionTask(
                      taskId: 'task-2',
                      status: TaskStatus.completed,
                      createdAt: '2026-07-28T00:00:00Z',
                      lastUpdatedAt: '2026-07-28T00:00:03Z',
                      ttlMs: null,
                      result: {
                        'content': [
                          {'type': 'text', 'text': 'approved'},
                        ],
                      },
                    );
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: GetTaskExtensionResult(task: task).toJson(),
                ),
              );
              break;

            case Method.tasksUpdate:
              updateCount += 1;
              expect(request.params?['taskId'], 'task-2');
              expect(
                request.params?['inputResponses']['approval'],
                {
                  'action': 'accept',
                  'content': {'approved': true},
                },
              );
              transport.onmessage?.call(
                JsonRpcResponse(
                  id: request.id,
                  result: const TaskExtensionAcknowledgementResult().toJson(),
                ),
              );
              break;
          }
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(
            elicitation: const ClientElicitation.formOnly(),
            extensions: withMcpTasksExtension(null),
          ),
        ),
      );
      client.onElicitRequest = (params) async {
        expect(params.message, 'Approve?');
        return const ElicitResult(
          action: 'accept',
          content: {'approved': true},
        );
      };
      await client.connect(transport);
      transport.sentMessages.clear();

      final result = await client.callTool(
        const CallToolRequest(name: 'approval-tool'),
      );

      expect((result.content.single as TextContent).text, 'approved');
      expect(getCount, 3);
      expect(updateCount, 1);
    });

    test('client rejects task resultType when request lacks task extension',
        () async {
      late DiscoveringClientTransport transport;
      transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
          extensions: withMcpTasksExtension(null),
        ),
        onRequest: (request) {
          if (request.method != Method.toolsCall) {
            return;
          }
          transport.onmessage?.call(
            JsonRpcResponse(
              id: request.id,
              result: const CreateTaskExtensionResult(
                task: TaskExtensionTask(
                  taskId: 'task-3',
                  status: TaskStatus.working,
                  createdAt: '2026-07-28T00:00:00Z',
                  lastUpdatedAt: '2026-07-28T00:00:01Z',
                  ttlMs: null,
                ),
              ).toJson(),
            ),
          );
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
        ),
      );
      await client.connect(transport);

      await expectLater(
        client.callTool(const CallToolRequest(name: 'delayed')),
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
                contains(
                  'MCP resultType "$resultTypeTask" is not valid for '
                  '${Method.toolsCall}',
                ),
              ),
        ),
      );
    });

    test('client retries requestState-only input_required without responses',
        () async {
      late DiscoveringClientTransport transport;
      final readRequests = <JsonRpcRequest>[];
      transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          resources: ServerCapabilitiesResources(),
        ),
        onRequest: (request) {
          if (request.method != Method.resourcesRead) {
            return;
          }

          readRequests.add(request);
          if (readRequests.length == 1) {
            transport.onmessage?.call(
              JsonRpcResponse(
                id: request.id,
                result: const InputRequiredResult(
                  requestState: 'read-state',
                ).toJson(),
              ),
            );
            return;
          }

          expect(request.params?['requestState'], 'read-state');
          expect(request.params, isNot(contains('inputResponses')));
          transport.onmessage?.call(
            JsonRpcResponse(
              id: request.id,
              result: {
                'resultType': resultTypeComplete,
                ...const ReadResourceResult(
                  contents: [
                    TextResourceContents(
                      uri: 'file:///doc.txt',
                      text: 'hello',
                    ),
                  ],
                  ttlMs: 0,
                  cacheScope: CacheScope.private,
                ).toJson(),
              },
            ),
          );
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      final result = await client.readResource(
        const ReadResourceRequest(uri: 'file:///doc.txt'),
      );

      expect((result.contents.single as TextResourceContents).text, 'hello');
      expect(readRequests, hasLength(2));
      expect(readRequests[1].id, isNot(readRequests[0].id));
    });

    test('client listenSubscriptions requires a connected transport', () {
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );

      expect(
        () => client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
        ),
        throwsStateError,
      );
    });

    test('client task subscriptions require its Tasks extension capability',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: ServerCapabilities(
          extensions: withMcpTasksExtension(null),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.stable),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      expect(
        () => client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(taskIds: ['task-1']),
          ),
        ),
        throwsA(
          isA<McpError>()
              .having(
            (error) => error.code,
            'code',
            ErrorCode.missingRequiredClientCapability.value,
          )
              .having(
            (error) => error.data,
            'data',
            const {
              'requiredCapabilities': {
                'extensions': {
                  mcpTasksExtensionId: <String, dynamic>{},
                },
              },
            },
          ),
        ),
      );
      expect(transport.sentMessages, isEmpty);
      await client.close();
    });

    test('client task subscriptions require the server Tasks extension',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: McpClientOptions(
          protocol: McpProtocol.stable,
          capabilities: ClientCapabilities(
            extensions: withMcpTasksExtension(null),
          ),
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      expect(
        () => client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(taskIds: ['task-1']),
          ),
        ),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.methodNotFound.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains(mcpTasksExtensionId),
              ),
        ),
      );
      expect(transport.sentMessages, isEmpty);
      await client.close();
    });

    test('client listenSubscriptions rejects initialization-era sessions',
        () async {
      final transport = LegacyFallbackTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.legacy),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      expect(
        () => client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
        ),
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.methodNotFound.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('stateless'),
              ),
        ),
      );
      expect(transport.sentMessages, isEmpty);
    });

    test('stateless client rejects uncorrelated subscription notifications',
        () async {
      final transport = DiscoveringClientTransport();
      final errors = <Error>[];
      var fallbackInvocations = 0;
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      )
        ..onerror = errors.add
        ..fallbackNotificationHandler = (notification) async {
          fallbackInvocations += 1;
        };
      await client.connect(transport);

      const methods = [
        Method.notificationsSubscriptionsAcknowledged,
        Method.notificationsToolsListChanged,
        Method.notificationsPromptsListChanged,
        Method.notificationsResourcesListChanged,
        Method.notificationsResourcesUpdated,
        Method.notificationsTasks,
      ];
      for (final method in methods) {
        final notification = switch (method) {
          Method.notificationsSubscriptionsAcknowledged =>
            JsonRpcSubscriptionsAcknowledgedNotification(
              acknowledgedParams: const SubscriptionsAcknowledgedNotification(
                notifications: SubscriptionFilter(),
              ),
            ),
          Method.notificationsResourcesUpdated =>
            JsonRpcResourceUpdatedNotification(
              updatedParams: const ResourceUpdatedNotification(
                uri: 'file:///resource',
              ),
            ),
          Method.notificationsTasks => JsonRpcTaskNotification(
              task: const TaskExtensionTask(
                taskId: 'task-1',
                status: TaskStatus.working,
                createdAt: '2026-07-28T00:00:00Z',
                lastUpdatedAt: '2026-07-28T00:00:00Z',
                ttlMs: null,
              ),
            ),
          _ => JsonRpcNotification(method: method, params: const {}),
        };
        transport.onmessage?.call(notification);
        transport.onmessage?.call(
          JsonRpcMessage.fromJson({
            ...notification.toJson(),
            'params': {
              ...?notification.params,
              '_meta': {McpMetaKey.subscriptionId: 'unknown'},
            },
          }) as JsonRpcNotification,
        );
      }
      transport.onmessage?.call(
        JsonRpcCancelledNotification(
          cancelParams: const CancelledNotification(requestId: 'missing-meta'),
        ),
      );
      transport.onmessage?.call(
        JsonRpcCancelledNotification(
          cancelParams: const CancelledNotification(requestId: 'mismatched'),
          meta: {McpMetaKey.subscriptionId: 'other'},
        ),
      );
      // A well-formed late cancellation can race local subscription cleanup;
      // it is ignored rather than treated as a protocol failure.
      transport.onmessage?.call(
        JsonRpcCancelledNotification(
          cancelParams:
              const CancelledNotification(requestId: 'already-closed'),
          meta: {McpMetaKey.subscriptionId: 'already-closed'},
        ),
      );
      await _pump();

      expect(fallbackInvocations, 0);
      expect(errors, hasLength(methods.length * 2 + 2));
      expect(
        errors,
        everyElement(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.invalidRequest.value,
              )
              .having(
                (error) => error.message,
                'message',
                anyOf(
                  contains('must include'),
                  contains('unknown'),
                  contains('must correlate'),
                ),
              ),
        ),
      );
    });

    test(
        'client listenSubscriptions demultiplexes and orders acknowledgments per id',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
          resources: ServerCapabilitiesResources(),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final toolsSubscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      final resourcesSubscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(
            resourceSubscriptions: ['file:///project/config.json'],
          ),
        ),
      );
      await _pump();

      final listenRequests = transport.sentMessages
          .whereType<JsonRpcRequest>()
          .where((message) => message.method == Method.subscriptionsListen)
          .toList();
      expect(listenRequests, hasLength(2));
      expect(listenRequests[0].id, toolsSubscription.id);
      expect(listenRequests[1].id, resourcesSubscription.id);
      expect(
        listenRequests[0].meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
      expect(listenRequests[0].params?['notifications'], {
        'toolsListChanged': true,
      });

      final resourceNotification = resourcesSubscription.notifications.first;
      transport.onmessage?.call(
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: SubscriptionFilter(
              resourceSubscriptions: ['file:///project/config.json'],
            ),
          ),
          meta: {McpMetaKey.subscriptionId: resourcesSubscription.id},
        ),
      );
      transport.onmessage?.call(
        JsonRpcResourceUpdatedNotification(
          updatedParams: const ResourceUpdatedNotification(
            uri: 'file:///project/config.json',
          ),
          meta: {McpMetaKey.subscriptionId: resourcesSubscription.id},
        ),
      );
      expect(
        (await resourceNotification).method,
        Method.notificationsResourcesUpdated,
      );

      // On stdio, another subscription may be acknowledged and emit its first
      // notification before this subscription's acknowledgment. Ordering is
      // defined per subscription ID, not for the shared channel as a whole.
      transport.onmessage?.call(
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: {McpMetaKey.subscriptionId: toolsSubscription.id},
        ),
      );

      final toolsAcknowledged = await toolsSubscription.acknowledged;
      final resourcesAcknowledged = await resourcesSubscription.acknowledged;
      expect(toolsAcknowledged.notifications.toolsListChanged, isTrue);
      expect(
        resourcesAcknowledged.notifications.resourceSubscriptions,
        ['file:///project/config.json'],
      );

      final toolNotification = toolsSubscription.notifications.first;
      transport.onmessage?.call(
        JsonRpcToolListChangedNotification(
          meta: {McpMetaKey.subscriptionId: toolsSubscription.id},
        ),
      );
      expect(
        (await toolNotification).method,
        Method.notificationsToolsListChanged,
      );

      toolsSubscription.cancel('done');
      resourcesSubscription.cancel('done');
      await expectLater(toolsSubscription.done, completes);
      await expectLater(resourcesSubscription.done, completes);
      await _pump();

      final cancellations =
          transport.sentMessages.whereType<JsonRpcCancelledNotification>();
      expect(
        cancellations
            .map((notification) => notification.cancelParams.requestId),
        containsAll([toolsSubscription.id, resourcesSubscription.id]),
      );
    });

    test('client buffers subscription events until the first listener',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      await _pump();

      transport.onmessage?.call(
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );
      transport.onmessage?.call(
        JsonRpcToolListChangedNotification(
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );
      transport.onmessage?.call(
        JsonRpcResponse(
          id: subscription.id,
          result: {
            'resultType': resultTypeComplete,
            '_meta': {McpMetaKey.subscriptionId: subscription.id},
          },
        ),
      );

      await subscription.acknowledged;
      await subscription.done;
      final notification = await subscription.notifications.first;
      expect(notification.method, Method.notificationsToolsListChanged);
    });

    test('client bounds subscription events buffered before a listener',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      await _pump();

      transport.onmessage?.call(
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );
      await subscription.acknowledged;

      final doneExpectation = expectLater(
        subscription.done,
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.invalidRequest.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('256-notification buffer'),
              ),
        ),
      );

      for (var index = 0; index <= 256; index++) {
        transport.onmessage?.call(
          JsonRpcToolListChangedNotification(
            meta: {McpMetaKey.subscriptionId: subscription.id},
          ),
        );
      }

      await doneExpectation;
      await expectLater(
        subscription.notifications,
        emitsError(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('256-notification buffer'),
          ),
        ),
      );
      await _pump();

      final cancellation = transport.sentMessages
          .whereType<JsonRpcCancelledNotification>()
          .single;
      expect(cancellation.cancelParams.requestId, subscription.id);
    });

    test('client rejects a second subscription acknowledgment', () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      final done = expectLater(
        subscription.done,
        throwsA(
          isA<McpError>()
              .having(
                (error) => error.code,
                'code',
                ErrorCode.invalidRequest.value,
              )
              .having(
                (error) => error.message,
                'message',
                contains('more than once'),
              ),
        ),
      );
      await _pump();

      final acknowledgment = JsonRpcSubscriptionsAcknowledgedNotification(
        acknowledgedParams: const SubscriptionsAcknowledgedNotification(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
        meta: {McpMetaKey.subscriptionId: subscription.id},
      );
      transport.onmessage?.call(acknowledgment);
      await subscription.acknowledged;
      transport.onmessage?.call(acknowledgment);

      await done;
    });

    test(
        'client waits for the terminal response after server subscription '
        'cancellation', () async {
      late JsonRpcRequest listenRequest;
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
        onRequest: (request) {
          if (request.method == Method.subscriptionsListen) {
            listenRequest = request;
          }
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      await _pump();
      expect(listenRequest.id, subscription.id);

      transport.onmessage?.call(
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );
      await subscription.acknowledged;

      transport.onmessage?.call(
        JsonRpcCancelledNotification(
          cancelParams: CancelledNotification(
            requestId: subscription.id,
            reason: 'Server closed subscription stream.',
          ),
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );

      var doneSettled = false;
      unawaited(subscription.done.whenComplete(() => doneSettled = true));
      await _pump();
      expect(doneSettled, isFalse);

      transport.onmessage?.call(
        JsonRpcResponse(
          id: subscription.id,
          result: {
            'resultType': resultTypeComplete,
            '_meta': {McpMetaKey.subscriptionId: subscription.id},
          },
        ),
      );

      final done = await subscription.done;
      expect(done, isA<SubscriptionsListenResult>());
      expect(done.subscriptionId, subscription.id);
    });

    test('client subscription rejects notifications before acknowledgment',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      subscription.notifications.listen(null, onError: (_) {});
      await _pump();

      final acknowledgedExpectation = expectLater(
        subscription.acknowledged,
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains(Method.notificationsSubscriptionsAcknowledged),
          ),
        ),
      );
      final doneExpectation = expectLater(
        subscription.done,
        throwsA(isA<McpError>()),
      );

      transport.onmessage?.call(
        JsonRpcToolListChangedNotification(
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );

      await acknowledgedExpectation;
      await doneExpectation;
      await _pump();

      final cancellation = transport.sentMessages
          .whereType<JsonRpcCancelledNotification>()
          .single;
      expect(cancellation.cancelParams.requestId, subscription.id);
    });

    test('client subscription fails when the connection closes', () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      subscription.notifications.listen(null, onError: (_) {});
      await _pump();

      final acknowledgedExpectation = expectLater(
        subscription.acknowledged,
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      final doneExpectation = expectLater(
        subscription.done,
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            'Connection closed',
          ),
        ),
      );

      await transport.close();

      await acknowledgedExpectation;
      await doneExpectation;
    });

    test('client subscription rejects acknowledgments outside requested filter',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
          prompts: ServerCapabilitiesPrompts(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      subscription.notifications.listen(null, onError: (_) {});
      await _pump();

      final acknowledgedExpectation = expectLater(
        subscription.acknowledged,
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('not requested'),
          ),
        ),
      );
      final doneExpectation = expectLater(
        subscription.done,
        throwsA(isA<McpError>()),
      );

      transport.onmessage?.call(
        JsonRpcNotification(
          method: Method.notificationsSubscriptionsAcknowledged,
          params: const {
            'notifications': {'promptsListChanged': true},
          },
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );

      await acknowledgedExpectation;
      await doneExpectation;
      await _pump();

      final cancellation = transport.sentMessages
          .whereType<JsonRpcCancelledNotification>()
          .single;
      expect(cancellation.cancelParams.requestId, subscription.id);
    });

    test('client subscription rejects unacknowledged notification types',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
          prompts: ServerCapabilitiesPrompts(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      subscription.notifications.listen(null, onError: (_) {});
      await _pump();

      transport.onmessage?.call(
        JsonRpcSubscriptionsAcknowledgedNotification(
          acknowledgedParams: const SubscriptionsAcknowledgedNotification(
            notifications: SubscriptionFilter(toolsListChanged: true),
          ),
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );
      await subscription.acknowledged;

      final doneExpectation = expectLater(
        subscription.done,
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains(Method.notificationsPromptsListChanged),
          ),
        ),
      );

      transport.onmessage?.call(
        JsonRpcPromptListChangedNotification(
          meta: {McpMetaKey.subscriptionId: subscription.id},
        ),
      );

      await doneExpectation;
      await _pump();

      final cancellation = transport.sentMessages
          .whereType<JsonRpcCancelledNotification>()
          .single;
      expect(cancellation.cancelParams.requestId, subscription.id);
    });

    test('client subscription cancel before ack completes done', () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      await _pump();

      final acknowledgedExpectation = expectLater(
        subscription.acknowledged,
        throwsA(
          isA<AbortError>().having(
            (error) => error.reason,
            'reason',
            'user cancelled',
          ),
        ),
      );

      subscription.cancel('user cancelled');

      await acknowledgedExpectation;
      await expectLater(subscription.done, completes);
      await _pump();

      final cancellation = transport.sentMessages
          .whereType<JsonRpcCancelledNotification>()
          .single;
      expect(cancellation.cancelParams.requestId, subscription.id);
    });

    test('client subscription rejects completion before acknowledgment',
        () async {
      final transport = DiscoveringClientTransport(
        capabilities: const ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      subscription.notifications.listen(null, onError: (_) {});
      await _pump();

      final acknowledgedExpectation = expectLater(
        subscription.acknowledged,
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('completed before'),
          ),
        ),
      );
      final doneExpectation = expectLater(
        subscription.done,
        throwsA(isA<McpError>()),
      );

      transport.onmessage?.call(
        JsonRpcResponse(
          id: subscription.id,
          result: {
            'resultType': resultTypeComplete,
            '_meta': {McpMetaKey.subscriptionId: subscription.id},
          },
        ),
      );

      await acknowledgedExpectation;
      await doneExpectation;
    });

    test('client rejects missing stateless resultType values', () async {
      final transport = DiscoveringClientTransport(
        toolsListResult: const {
          'tools': [],
          'ttlMs': 0,
          'cacheScope': CacheScope.private,
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
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
                contains('must include resultType'),
              ),
        ),
      );
    });

    test('client rejects malformed identity on stateless non-discovery results',
        () async {
      for (final malformedServerInfo in <Object?>[
        null,
        'malformed',
        const <String, dynamic>{'name': 'missing-version'},
      ]) {
        final transport = DiscoveringClientTransport(
          toolsListResult: <String, dynamic>{
            'resultType': resultTypeComplete,
            'tools': const <dynamic>[],
            'ttlMs': 0,
            'cacheScope': CacheScope.private,
            '_meta': <String, dynamic>{
              McpMetaKey.serverInfo: malformedServerInfo,
            },
          },
        );
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: const McpClientOptions(
            protocol: McpProtocol.stable,
            useServerDiscover: true,
          ),
        );

        try {
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
                  ),
            ),
            reason: '$malformedServerInfo',
          );
        } finally {
          await client.close();
        }
      }
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
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
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
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
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

    test('client rejects input_required on non-MRTR requests', () async {
      final transport = DiscoveringClientTransport(
        toolsListResult: const {
          'resultType': resultTypeInputRequired,
          'requestState': 'list-state',
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
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
                contains(
                  'MCP resultType "$resultTypeInputRequired" is not valid for '
                  '${Method.toolsList}',
                ),
              ),
        ),
      );
    });

    for (final scenario in [
      (
        name: 'missing ttlMs',
        result: const {
          'resultType': resultTypeComplete,
          'tools': [],
          'cacheScope': CacheScope.private,
        },
        message: 'ttlMs',
      ),
      (
        name: 'missing cacheScope',
        result: const {
          'resultType': resultTypeComplete,
          'tools': [],
          'ttlMs': 0,
        },
        message: 'cacheScope',
      ),
      (
        name: 'negative ttlMs',
        result: const {
          'resultType': resultTypeComplete,
          'tools': [],
          'ttlMs': -1,
          'cacheScope': CacheScope.private,
        },
        message: 'ttlMs',
      ),
      (
        name: 'invalid cacheScope',
        result: const {
          'resultType': resultTypeComplete,
          'tools': [],
          'ttlMs': 0,
          'cacheScope': 'shared',
        },
        message: 'cacheScope',
      ),
    ]) {
      test('client rejects stateless cacheable result ${scenario.name}',
          () async {
        final transport = DiscoveringClientTransport(
          toolsListResult: scenario.result,
        );
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: const McpClientOptions(
            protocol: McpProtocol.stable,
            useServerDiscover: true,
          ),
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
                  contains(scenario.message),
                ),
          ),
        );
      });
    }

    test('client rejects task resultType on non-task-eligible requests',
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
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
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
                contains(
                  'MCP resultType "$resultTypeTask" is not valid for '
                  '${Method.toolsList}',
                ),
              ),
        ),
      );
    });

    test('client preserves cache hints when filtering invalid tools', () async {
      final transport = DiscoveringClientTransport(
        toolsListResult: const {
          'resultType': resultTypeComplete,
          'tools': [
            {
              'name': 'valid',
              'inputSchema': {'type': 'object'},
            },
            {
              'name': 'invalid_header',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'payload': {
                    'type': 'object',
                    'x-mcp-header': 'Payload',
                  },
                },
              },
            },
          ],
          'ttlMs': 300000,
          'cacheScope': CacheScope.public,
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );

      await client.connect(transport);

      final result = await client.listTools();
      expect(result.tools.map((tool) => tool.name), ['valid']);
      expect(result.ttlMs, 300000);
      expect(result.cacheScope, CacheScope.public);
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
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );

      await client.connect(transport);

      final result = await client.listTools();
      expect(client.getProtocolVersion(), latestInitializationProtocolVersion);
      expect(result.tools, isEmpty);
    });

    test('legacy client preserves opaque future reserved result metadata',
        () async {
      final transport = LegacyFallbackTransport(
        toolsListResult: const {
          'tools': <dynamic>[],
          '_meta': <String, dynamic>{
            McpMetaKey.serverInfo: null,
          },
        },
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
          useServerDiscover: true,
        ),
      );

      try {
        await client.connect(transport);
        final result = await client.listTools();

        expect(
          client.getProtocolVersion(),
          latestInitializationProtocolVersion,
        );
        expect(result.meta, containsPair(McpMetaKey.serverInfo, null));
      } finally {
        await client.close();
      }
    });

    test('client rejects discovery when no compatible version is offered',
        () async {
      final transport = DiscoveringClientTransport(
        discoverVersions: const ['1900-01-01'],
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
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
    });

    test('client rejects discovery results that offer only legacy versions',
        () async {
      final transport = DiscoveringClientTransport(
        discoverVersions: legacyProtocolVersions,
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
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
          protocol: McpProtocol.stable,
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
        ['1900-01-01', previewProtocolVersion],
      );
      expect(client.getProtocolVersion(), previewProtocolVersion);
      expect(transport.protocolVersion, previewProtocolVersion);
      expect(
        transport.sentMessages.whereType<JsonRpcRequest>().map(
              (message) => message.method,
            ),
        isNot(contains(Method.initialize)),
      );
    });

    test('stable client does not downgrade after a modern discovery error',
        () async {
      final transport = LegacyFallbackTransport(
        discoveryError: McpError(
          ErrorCode.unsupportedProtocolVersion.value,
          'Unsupported protocol version',
          const {
            'supported': legacyProtocolVersions,
            'requested': previewProtocolVersion,
          },
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
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
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        isNot(contains(Method.initialize)),
      );
    });

    test('HTTP-capable client does not downgrade after a discovery timeout',
        () async {
      final transport = LegacyFallbackTransport(
        discoveryError: McpError(
          ErrorCode.requestTimeout.value,
          'Discovery probe timed out',
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );

      await expectLater(
        client.connect(transport),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.requestTimeout.value,
          ),
        ),
      );
      expect(
        transport.sentMessages.whereType<JsonRpcRequest>().map(
              (message) => message.method,
            ),
        isNot(contains(Method.initialize)),
      );
    });

    test('require2026 client does not fall back to legacy versions', () async {
      final transport = LegacyFallbackTransport(
        discoveryError: McpError(
          ErrorCode.unsupportedProtocolVersion.value,
          'Unsupported protocol version',
          const {
            'supported': allSupportedProtocolVersions,
            'requested': previewProtocolVersion,
          },
        ),
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.require2026,
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
    });

    for (final scenario in [
      (
        name: 'disabled discovery',
        options: const McpClientOptions(
          protocol: McpProtocol.require2026,
          useServerDiscover: false,
        ),
      ),
      (
        name: 'enabled legacy fallback',
        options: const McpClientOptions(
          protocol: McpProtocol.require2026,
          allowLegacyInitializationFallback: true,
        ),
      ),
    ]) {
      test('require2026 ignores ${scenario.name} override', () async {
        final transport = LegacyFallbackTransport();
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: scenario.options,
        );

        await expectLater(
          client.connect(transport),
          throwsA(
            isA<McpError>().having(
              (error) => error.code,
              'code',
              ErrorCode.methodNotFound.value,
            ),
          ),
        );
        expect(
          transport.sentMessages
              .whereType<JsonRpcRequest>()
              .map((message) => message.method),
          [Method.serverDiscover],
        );
      });
    }

    for (final scenario in [
      (
        name: 'malformed error data',
        requested: '1900-01-01',
        discoverVersions: const [previewProtocolVersion],
        data: 'not-an-object',
      ),
      (
        name: 'missing supported versions',
        requested: '1900-01-01',
        discoverVersions: const [previewProtocolVersion],
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
        requested: previewProtocolVersion,
        discoverVersions: const [previewProtocolVersion],
        data: const {
          'supported': [previewProtocolVersion],
          'requested': previewProtocolVersion,
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
              protocol: McpProtocol.stable,
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
        options: const McpClientOptions(
          protocol: McpProtocol.stable,
        ),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), latestInitializationProtocolVersion);
      expect(transport.protocolVersion, latestInitializationProtocolVersion);
      expect(
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        containsAllInOrder([Method.serverDiscover, Method.initialize]),
      );
      final initializeRequest = transport.sentMessages
          .whereType<JsonRpcRequest>()
          .singleWhere((message) => message.method == Method.initialize);
      expect(
        initializeRequest.params?['protocolVersion'],
        latestInitializationProtocolVersion,
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
