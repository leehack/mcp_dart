import 'dart:async';

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/server/tasks.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

class RecordingTransport extends Transport {
  RecordingTransport({this.sessionIdValue});

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
    this.discoverVersions = const [draftProtocolVersion2026_07_28],
    this.unsupportedDiscoverProtocolVersions = const [],
    this.unsupportedDiscoverData,
    this.capabilities = const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
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
  });

  final McpError? discoveryError;
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

Map<String, dynamic> _clientMeta({
  String? protocolVersion,
  ClientCapabilities clientCapabilities = const ClientCapabilities(),
  Map<String, dynamic>? meta,
  Object? logLevel,
}) {
  return buildProtocolRequestMeta(
    protocolVersion: protocolVersion ?? draftProtocolVersion2026_07_28,
    clientInfo: const Implementation(name: 'client', version: '1.0.0'),
    clientCapabilities: clientCapabilities,
    meta: meta,
    logLevel: logLevel,
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
  group('MCP 2026-07-28 RC protocol foundation', () {
    test('defines draft protocol version separately from stable default', () {
      expect(latestProtocolVersion, stableProtocolVersion2025_11_25);
      expect(latestDraftProtocolVersion, draftProtocolVersion2026_07_28);
      expect(
        supportedProtocolVersionsWithDraft,
        contains(draftProtocolVersion2026_07_28),
      );
      expect(statelessProtocolVersions, [draftProtocolVersion2026_07_28]);
      expect(isStatelessProtocolVersion(draftProtocolVersion2026_07_28), true);
      expect(isStatelessProtocolVersion(latestProtocolVersion), false);
    });

    test('builds stateless request metadata without dropping caller metadata',
        () {
      final meta = buildProtocolRequestMeta(
        protocolVersion: draftProtocolVersion2026_07_28,
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
        draftProtocolVersion2026_07_28,
      );
      expect(meta[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
      expect(meta[McpMetaKey.clientCapabilities], <String, dynamic>{});
      expect(meta[McpMetaKey.logLevel], 'debug');
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
            protocolVersion: draftProtocolVersion2026_07_28,
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
          McpMetaKey.protocolVersion: latestProtocolVersion,
        },
        'params': {
          '_meta': _clientMeta(),
        },
      });

      expect(parsed, isA<JsonRpcListToolsRequest>());
      final request = parsed as JsonRpcListToolsRequest;
      expect(
        request.meta?[McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );
      expect(request.meta?[McpMetaKey.clientInfo], {
        'name': 'client',
        'version': '1.0.0',
      });
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
        () => ElicitRequestParams.fromJson({
          'mode': 'url',
          'message': 'Open browser',
          'url': 'authorize/callback',
          'elicitationId': 'auth-1',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitRequestParams.url(
          message: 'Open browser',
          url: 'authorize/callback',
          elicitationId: 'auth-1',
        ).toJson(),
        throwsA(isA<ArgumentError>()),
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
        protocolVersion: draftProtocolVersion2026_07_28,
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
            McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
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
              McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
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
          'supportedVersions': [draftProtocolVersion2026_07_28],
          'capabilities': <String, dynamic>{},
          'serverInfo': {'name': 'server', 'version': '1.0.0'},
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const DiscoverResult(
          supportedVersions: [draftProtocolVersion2026_07_28],
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
        protocolVersion: draftProtocolVersion2026_07_28,
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
        protocolVersion: stableProtocolVersion2025_11_25,
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
        supportedVersions: [draftProtocolVersion2026_07_28],
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
        'supportedVersions': [draftProtocolVersion2026_07_28],
        'capabilities': <String, dynamic>{},
        'serverInfo': {'name': 'server', 'version': '1.0.0'},
      };

      for (final parse in <Object Function()>[
        () => DiscoverResult.fromJson({
              ...result,
              'supportedVersions': [draftProtocolVersion2026_07_28, 1],
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'capabilities': 'bad',
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'serverInfo': 'bad',
            }),
        () => DiscoverResult.fromJson({
              ...result,
              'instructions': 1,
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
    });

    test('requires complete resultType on server/discover results', () {
      final validResult = const DiscoverResult(
        supportedVersions: [draftProtocolVersion2026_07_28],
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
          supportedVersions: [draftProtocolVersion2026_07_28],
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
        draftProtocolVersion2026_07_28,
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
        draftProtocolVersion2026_07_28,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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

    test('server handles task extension methods without per-request capability',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
      server.setRequestHandler<JsonRpcCancelTaskRequest>(
        Method.tasksCancel,
        (request, extra) async => const TaskExtensionAcknowledgementResult(),
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
        (request, extra) async => const EmptyResult(),
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
      final statelessMeta = _clientMeta();

      transport
        ..receive(
          JsonRpcGetTaskRequest(
            id: 'get-task',
            getParams: const GetTaskRequest(taskId: 'task-1'),
            meta: statelessMeta,
          ),
        )
        ..receive(
          JsonRpcCancelTaskRequest(
            id: 'cancel-task',
            cancelParams: const CancelTaskRequest(taskId: 'task-1'),
            meta: statelessMeta,
          ),
        )
        ..receive(
          JsonRpcUpdateTaskRequest(
            id: 'update-task',
            updateParams: const UpdateTaskRequest(
              taskId: 'task-1',
              inputResponses: {},
            ),
            meta: statelessMeta,
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

    test('server task store uses task extension results for stateless requests',
        () async {
      final store = InMemoryTaskStore();
      addTearDown(store.dispose);
      final completedTask = await store.createTask(
        const TaskCreation(ttl: 60000),
        'source-request',
        const {
          'method': Method.toolsCall,
          'params': {'name': 'long'},
        },
        null,
      );
      await store.storeTaskResult(
        completedTask.taskId,
        TaskStatus.completed,
        const CallToolResult(content: [TextContent(text: 'done')]),
      );
      final workingTask = await store.createTask(
        const TaskCreation(ttl: null),
        'cancel-request',
        const {
          'method': Method.toolsCall,
          'params': {'name': 'cancel-me'},
        },
        null,
      );
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: McpServerOptions(
          protocol: McpProtocol.preview2026,
          capabilities: const ServerCapabilities(
            extensions: {mcpTasksExtensionId: {}},
          ),
          taskStore: store,
        ),
      );
      final transport = RecordingTransport();
      await server.connect(transport);

      final meta = _clientMeta(
        clientCapabilities: const ClientCapabilities(
          extensions: {mcpTasksExtensionId: {}},
        ),
      );
      transport
        ..receive(
          JsonRpcGetTaskRequest(
            id: 'get-task',
            getParams: GetTaskRequest(taskId: completedTask.taskId),
            meta: meta,
          ),
        )
        ..receive(
          JsonRpcCancelTaskRequest(
            id: 'cancel-task',
            cancelParams: CancelTaskRequest(taskId: workingTask.taskId),
            meta: meta,
          ),
        );
      await _pump();

      final responses = transport.sentMessages.cast<JsonRpcResponse>().toList();
      expect(responses, hasLength(2));
      expect(responses[0].result['resultType'], resultTypeComplete);
      expect(responses[0].result['taskId'], completedTask.taskId);
      expect(responses[0].result['status'], TaskStatus.completed.name);
      expect(responses[0].result['ttlMs'], 60000);
      expect(responses[0].result, isNot(contains('ttl')));
      expect(responses[0].result['result']['content'], [
        {'type': 'text', 'text': 'done'},
      ]);
      expect(responses[1].result, {'resultType': resultTypeComplete});
      expect(
        (await store.getTask(workingTask.taskId))?.status,
        TaskStatus.cancelled,
      );
    });

    test('server does not expose legacy task handlers as task extension',
        () async {
      final server = McpServer(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
        JsonRpcInitializeRequest(
          id: 'init',
          initParams: const InitializeRequest(
            protocolVersion: stableProtocolVersion2025_11_25,
            capabilities: ClientCapabilities(
              extensions: {mcpTasksExtensionId: {}},
            ),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();
      transport.sentMessages.clear();

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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
      expect(response.error.data, contains('Task not found'));
    });

    test('stateless tools/call rejects CallToolResult resultType spoof',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
        ),
      );
      server.registerTool(
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
          protocol: McpProtocol.preview2026,
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
                  elicitationId: 'auth-1',
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
          protocol: McpProtocol.preview2026,
        ),
      );
      server.registerPrompt(
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
          protocol: McpProtocol.preview2026,
        ),
      );
      server.registerResource(
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
    });

    test('stateless unsupported methods reject input required results',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
      expect(receivedProtocolVersion, draftProtocolVersion2026_07_28);
      expect(receivedClientInfo?.name, 'client');
      expect(receivedClientInfo?.version, '1.0.0');
      expect(receivedClientCapabilities?.toJson(), isEmpty);
    });

    test('stateless handlers do not inherit transport session identity',
        () async {
      final taskStore = SessionRecordingTaskStore();
      addTearDown(taskStore.dispose);
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: McpServerOptions(
          protocol: McpProtocol.preview2026,
          capabilities: const ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            extensions: {mcpTasksExtensionId: {}},
          ),
          taskStore: taskStore,
        ),
      );
      RequestHandlerExtra? receivedExtra;
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (request, extra) async {
          receivedExtra = extra;
          await extra.taskStore!.createTask(const TaskCreation(ttl: 1000));
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
      expect(taskStore.createTaskSessionIds, [isNull]);
    });

    test('server handler client requests stay associated with origin request',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
            protocolVersion: stableProtocolVersion2025_11_25,
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
            protocolVersion: draftProtocolVersion2026_07_28,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ),
      );
      await _pump();

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(
        response.result['protocolVersion'],
        stableProtocolVersion2025_11_25,
      );
      expect(
        response.result['protocolVersion'],
        isNot(latestDraftProtocolVersion),
      );
    });

    test('server returns unsupported protocol version for stateless metadata',
        () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
        ),
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
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
        validateToolRequest({
          McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
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
    });

    test('server rejects core RPCs removed from stateless MCP', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
        ),
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
        options: const McpServerOptions(
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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

    test('preview client uses server/discover and sends stateless metadata',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
        ),
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

    test('stateless client rejects legacy task request options before send',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
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

    test('client uses legacy initialization by default', () async {
      final transport = LegacyFallbackTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );

      await client.connect(transport);

      expect(client.getProtocolVersion(), stableProtocolVersion2025_11_25);
      expect(transport.protocolVersion, stableProtocolVersion2025_11_25);
      expect(
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        isNot(contains(Method.serverDiscover)),
      );
      expect(
        transport.sentMessages
            .whereType<JsonRpcRequest>()
            .map((message) => message.method),
        contains(Method.initialize),
      );
      final initializeRequest = transport.sentMessages
          .whereType<JsonRpcRequest>()
          .singleWhere((message) => message.method == Method.initialize);
      expect(
        initializeRequest.params?['protocolVersion'],
        stableProtocolVersion2025_11_25,
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
          'Invalid request parameters',
        ),
      ];

      for (final error in errors) {
        final transport = LegacyFallbackTransport(discoveryError: error);
        final client = McpClient(
          const Implementation(name: 'client', version: '1.0.0'),
          options: const McpClientOptions(
            protocol: McpProtocol.preview2026,
          ),
        );

        await client.connect(transport);

        expect(client.getProtocolVersion(), stableProtocolVersion2025_11_25);
        expect(transport.protocolVersion, stableProtocolVersion2025_11_25);
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
          protocol: McpProtocol.preview2026,
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

    test('stateless client rejects removed notifications before send',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
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
    });

    test('stateless client rejects server-initiated requests on transport',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
          capabilities: ClientCapabilities(roots: ClientCapabilitiesRoots()),
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      transport.onmessage?.call(const JsonRpcListRootsRequest(id: 'roots-1'));
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.id, 'roots-1');
      expect(response.error.code, ErrorCode.invalidRequest.value);
      expect(response.error.message, contains('input_required'));
      expect(response.error.message, contains('inputRequests'));
    });

    test(
        'stateless client reports method not found for unadvertised peer method',
        () async {
      final transport = DiscoveringClientTransport();
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
          useServerDiscover: true,
        ),
      );
      await client.connect(transport);
      transport.sentMessages.clear();

      transport.onmessage?.call(const JsonRpcListRootsRequest(id: 'roots-1'));
      await _pump();

      final response = transport.sentMessages.single as JsonRpcError;
      expect(response.id, 'roots-1');
      expect(response.error.code, ErrorCode.methodNotFound.value);
      expect(response.error.message, contains('roots'));
    });

    test('client retries tools/call after fulfilling input_required requests',
        () async {
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
          protocol: McpProtocol.preview2026,
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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

    test('client listenSubscriptions demultiplexes by subscription id',
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
          protocol: McpProtocol.preview2026,
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
        draftProtocolVersion2026_07_28,
      );
      expect(listenRequests[0].params?['notifications'], {
        'toolsListChanged': true,
      });

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
      final resourceNotification = resourcesSubscription.notifications.first;
      transport.onmessage?.call(
        JsonRpcToolListChangedNotification(
          meta: {McpMetaKey.subscriptionId: toolsSubscription.id},
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
        (await toolNotification).method,
        Method.notificationsToolsListChanged,
      );
      expect(
        (await resourceNotification).method,
        Method.notificationsResourcesUpdated,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          result: const {'resultType': resultTypeComplete},
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
            protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
          useServerDiscover: true,
        ),
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
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
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

    test(
        'client retries discovery with advertised compatible stateless version',
        () async {
      final transport = DiscoveringClientTransport(
        unsupportedDiscoverProtocolVersions: const ['1900-01-01'],
      );
      final client = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const McpClientOptions(
          protocol: McpProtocol.preview2026,
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
              protocol: McpProtocol.preview2026,
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
          protocol: McpProtocol.preview2026,
        ),
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
      final initializeRequest = transport.sentMessages
          .whereType<JsonRpcRequest>()
          .singleWhere((message) => message.method == Method.initialize);
      expect(
        initializeRequest.params?['protocolVersion'],
        stableProtocolVersion2025_11_25,
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
