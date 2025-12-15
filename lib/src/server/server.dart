import 'dart:async';

import 'package:mcp_dart/src/shared/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.server");

/// Options for configuring the MCP [Server].
class ServerOptions extends ProtocolOptions {
  /// Capabilities to advertise as being supported by this server.
  final ServerCapabilities? capabilities;

  /// Optional instructions describing how to use the server and its features.
  final String? instructions;

  /// Optional JSON Schema validator for validating elicitation results.
  ///
  /// If not provided, a [BasicJsonSchemaValidator] will be used.
  final JsonSchemaValidator? jsonSchemaValidator;

  /// Creates server options.
  const ServerOptions({
    super.enforceStrictCapabilities,
    this.capabilities,
    this.instructions,
    this.jsonSchemaValidator,
  });
}

/// An MCP server implementation built on top of a pluggable [Transport].
///
/// This server automatically handles the initialization flow initiated by the client.
/// It extends the base [Protocol] class, providing server-specific logic and
/// capability handling.
class Server extends Protocol {
  ClientCapabilities? _clientCapabilities;
  Implementation? _clientVersion;
  ServerCapabilities _capabilities;
  final String? _instructions;
  final Implementation _serverInfo;
  final JsonSchemaValidator _jsonSchemaValidator;

  /// Map of session IDs to their configured logging level.
  final Map<String?, LoggingLevel> _loggingLevels = {};

  /// Mapping of LoggingLevel to severity index for comparison.
  static const Map<LoggingLevel, int> _logLevelSeverity = {
    LoggingLevel.debug: 0,
    LoggingLevel.info: 1,
    LoggingLevel.notice: 2,
    LoggingLevel.warning: 3,
    LoggingLevel.error: 4,
    LoggingLevel.critical: 5,
    LoggingLevel.alert: 6,
    LoggingLevel.emergency: 7,
  };

  /// Callback invoked when initialization has fully completed.
  void Function()? oninitialized;

  /// Initializes this server with its implementation details and options.
  Server(this._serverInfo, {ServerOptions? options})
      : _capabilities = options?.capabilities ?? const ServerCapabilities(),
        _instructions = options?.instructions,
        _jsonSchemaValidator =
            options?.jsonSchemaValidator ?? const BasicJsonSchemaValidator(),
        super(options) {
    setRequestHandler<JsonRpcInitializeRequest>(
      Method.initialize,
      (request, extra) async => _oninitialize(request.initParams),
      (id, params, meta) => JsonRpcInitializeRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setNotificationHandler<JsonRpcInitializedNotification>(
      Method.notificationsInitialized,
      (notification) async => oninitialized?.call(),
      (params, meta) => JsonRpcInitializedNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    if (_capabilities.logging != null) {
      setRequestHandler<JsonRpcSetLevelRequest>(
        Method.loggingSetLevel,
        (request, extra) async {
          _loggingLevels[extra.sessionId] = request.setParams.level;
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcSetLevelRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
    }
  }

  /// Checks if a log message should be ignored based on the session's log level.
  bool _isMessageIgnored(LoggingLevel level, String? sessionId) {
    final currentLevel = _loggingLevels[sessionId];
    if (currentLevel == null) return false;
    return _logLevelSeverity[level]! < _logLevelSeverity[currentLevel]!;
  }

  /// Registers new capabilities for this server.
  ///
  /// This can only be called *before* connecting to a transport.
  void registerCapabilities(ServerCapabilities capabilities) {
    if (transport != null) {
      throw StateError(
        "Cannot register capabilities after connecting to transport",
      );
    }

    final merged = mergeCapabilities<Map<String, dynamic>>(
      _capabilities.toJson(),
      capabilities.toJson(),
    );

    _capabilities = ServerCapabilities.fromJson(merged);
  }

  @override
  void setRequestHandler<ReqT extends JsonRpcRequest>(
    String method,
    Future<BaseResultData> Function(ReqT request, RequestHandlerExtra extra)
        handler,
    ReqT Function(
      RequestId id,
      Map<String, dynamic>? params,
      Map<String, dynamic>? meta,
    ) requestFactory,
  ) {
    if (method == Method.toolsCall) {
      Future<BaseResultData> wrappedHandler(
        ReqT request,
        RequestHandlerExtra extra,
      ) async {
        // Run the original handler
        final result = await handler(request, extra);

        // Validate the result based on whether it's a task-augmented request
        if (request is JsonRpcCallToolRequest && request.isTaskAugmented) {
          if (result is! CreateTaskResult) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Invalid task creation result: Expected CreateTaskResult",
            );
          }
        } else {
          if (result is! CallToolResult) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Invalid tools/call result: Expected CallToolResult",
            );
          }
        }
        return result;
      }

      super.setRequestHandler(method, wrappedHandler, requestFactory);
    } else {
      super.setRequestHandler(method, handler, requestFactory);
    }
  }

  /// Handles the client's `initialize` request.
  Future<InitializeResult> _oninitialize(InitializeRequestParams params) async {
    final requestedVersion = params.protocolVersion;

    _clientCapabilities = params.capabilities;
    _clientVersion = params.clientInfo;

    final protocolVersion = supportedProtocolVersions.contains(requestedVersion)
        ? requestedVersion
        : latestProtocolVersion;

    return InitializeResult(
      protocolVersion: protocolVersion,
      capabilities: getCapabilities(),
      serverInfo: _serverInfo,
      instructions: _instructions,
    );
  }

  /// Gets the client's reported capabilities, available after initialization.
  ClientCapabilities? getClientCapabilities() => _clientCapabilities;

  /// Gets the client's reported implementation info, available after initialization.
  Implementation? getClientVersion() => _clientVersion;

  /// Gets the server's currently configured capabilities.
  ServerCapabilities getCapabilities() => _capabilities;

  @override
  void assertCapabilityForMethod(String method) {
    switch (method) {
      case Method.samplingCreateMessage:
        if (!(_clientCapabilities?.sampling != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support sampling (required for server to send $method)",
          );
        }
        break;

      case Method.rootsList:
        if (!(_clientCapabilities?.roots != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support listing roots (required for server to send $method)",
          );
        }
        break;

      case Method.elicitationCreate:
        if (!(_clientCapabilities?.elicitation != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support elicitation (required for server to send $method)",
          );
        }
        break;

      case Method.ping:
        break;

      default:
        _logger.warn(
          "assertCapabilityForMethod called for unknown server-sent request method: $method",
        );
    }
  }

  @override
  void assertNotificationCapability(String method) {
    switch (method) {
      case Method.notificationsMessage:
        if (!(_capabilities.logging != null)) {
          throw StateError(
            "Server does not support logging capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsResourcesUpdated:
        if (!(_capabilities.resources?.subscribe ?? false)) {
          throw StateError(
            "Server does not support resource subscription capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsResourcesListChanged:
        if (!(_capabilities.resources?.listChanged ?? false)) {
          throw StateError(
            "Server does not support resource list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsToolsListChanged:
        if (!(_capabilities.tools?.listChanged ?? false)) {
          throw StateError(
            "Server does not support tool list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsPromptsListChanged:
        if (!(_capabilities.prompts?.listChanged ?? false)) {
          throw StateError(
            "Server does not support prompt list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsCompletionsListChanged:
        if (!(_capabilities.completions?.listChanged ?? false)) {
          throw StateError(
            "Server does not support completion list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsTasksStatus:
        if (!(_capabilities.tasks != null)) {
          throw StateError(
            "Server does not support task capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsElicitationComplete:
        if (!(_clientCapabilities?.elicitation?.url != null)) {
          throw StateError(
            "Client does not support URL elicitation (required for sending $method)",
          );
        }
        break;

      case Method.notificationsCancelled:
      case Method.notificationsProgress:
        break;

      default:
        _logger.warn(
          "assertNotificationCapability called for unknown server-sent notification method: $method",
        );
    }
  }

  @override
  void assertRequestHandlerCapability(String method) {
    switch (method) {
      case Method.initialize:
      case Method.ping:
      case Method.completionComplete:
        break;

      case Method.loggingSetLevel:
        if (!(_capabilities.logging != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'logging' capability",
          );
        }
        break;

      case Method.promptsGet:
      case Method.promptsList:
        if (!(_capabilities.prompts != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'prompts' capability",
          );
        }
        break;

      case Method.resourcesList:
      case Method.resourcesTemplatesList:
      case Method.resourcesRead:
        if (!(_capabilities.resources != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'resources' capability",
          );
        }
        break;

      case Method.resourcesSubscribe:
      case Method.resourcesUnsubscribe:
        if (!(_capabilities.resources?.subscribe ?? false)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'resources.subscribe' capability",
          );
        }
        break;

      case Method.toolsCall:
      case Method.toolsList:
        if (!(_capabilities.tools != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'tools' capability",
          );
        }
        break;

      case Method.tasksList:
      case Method.tasksCancel:
      case Method.tasksGet:
      case Method.tasksResult:
        if (!(_capabilities.tasks != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'tasks' capability",
          );
        }
        break;

      default:
        _logger.info(
          "Setting request handler for potentially custom method '$method'. Ensure server capabilities match.",
        );
    }
  }

  /// Sends a `ping` request to the client and awaits an empty response.
  Future<EmptyResult> ping([RequestOptions? options]) {
    return request<EmptyResult>(
      const JsonRpcPingRequest(id: -1),
      (json) => const EmptyResult(),
      options,
    );
  }

  /// Sends a `sampling/createMessage` request to the client to ask it to sample an LLM.
  Future<CreateMessageResult> createMessage(
    CreateMessageRequestParams params, [
    RequestOptions? options,
  ]) {
    // Capability check - only required when tools/toolChoice are provided
    if (params.tools != null || params.toolChoice != null) {
      if (!(_clientCapabilities?.sampling?.tools ?? false)) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          "Client does not support sampling tools capability.",
        );
      }
    }

    // Message structure validation - always validate tool_use/tool_result pairs.
    if (params.messages.isNotEmpty) {
      final lastMessage = params.messages.last;
      final lastContent = lastMessage.content is List
          ? lastMessage.content as List
          : [lastMessage.content];
      final hasToolResults =
          lastContent.any((c) => c is SamplingToolResultContent);

      final previousMessage = params.messages.length > 1
          ? params.messages[params.messages.length - 2]
          : null;
      final previousContent = previousMessage != null
          ? (previousMessage.content is List
              ? previousMessage.content as List
              : [previousMessage.content])
          : [];
      final hasPreviousToolUse =
          previousContent.any((c) => c is SamplingToolUseContent);

      if (hasToolResults) {
        if (lastContent.any((c) => c is! SamplingToolResultContent)) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "The last message must contain only tool_result content if any is present",
          );
        }
        if (!hasPreviousToolUse) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "tool_result blocks are not matching any tool_use from the previous message",
          );
        }
      }

      if (hasPreviousToolUse) {
        final toolUseIds = previousContent
            .whereType<SamplingToolUseContent>()
            .map((c) => c.id)
            .toSet();
        final toolResultIds = lastContent
            .whereType<SamplingToolResultContent>()
            .map((c) => c.toolUseId)
            .toSet();

        if (toolUseIds.length != toolResultIds.length ||
            !toolUseIds.every((id) => toolResultIds.contains(id))) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "ids of tool_result blocks and tool_use blocks from previous message do not match",
          );
        }
      }
    }

    final req = JsonRpcCreateMessageRequest(id: -1, createParams: params);
    return request<CreateMessageResult>(
      req,
      (json) => CreateMessageResult.fromJson(json),
      options,
    );
  }

  /// Creates an elicitation request for the given parameters.
  Future<ElicitResult> elicitInput(
    ElicitRequestParams params, [
    RequestOptions? options,
  ]) async {
    // Mode defaults to 'form' if omitted (handled in types, but logic here too)
    final mode = params.mode ?? ElicitationMode.form;

    switch (mode) {
      case ElicitationMode.url:
        if (!(_clientCapabilities?.elicitation?.url != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support url elicitation.",
          );
        }
        break;
      case ElicitationMode.form:
        if (!(_clientCapabilities?.elicitation?.form != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support form elicitation.",
          );
        }
        break;
    }

    // Note: Schema validation of the result is omitted as no JSON Schema validator is available.

    final req = JsonRpcElicitRequest(id: -1, elicitParams: params);
    final result = await request<ElicitResult>(
      req,
      (json) => ElicitResult.fromJson(json),
      options,
    );

    if (params.isFormMode &&
        result.accepted &&
        result.content != null &&
        params.requestedSchema != null) {
      try {
        _jsonSchemaValidator.validate(
          params.requestedSchema!,
          result.content,
        );
      } catch (e) {
        if (e is JsonSchemaValidationException) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Elicitation response content does not match requested schema: ${e.message}",
          );
        }
        throw McpError(
          ErrorCode.internalError.value,
          "Error validating elicitation response: $e",
        );
      }
    }

    return result;
  }

  /// Creates a reusable callback that, when invoked, will send a `notifications/elicitation/complete`
  /// notification for the specified elicitation ID.
  Future<void> Function() createElicitationCompletionNotifier(
    String elicitationId,
  ) {
    if (!(_clientCapabilities?.elicitation?.url != null)) {
      throw StateError(
        "Client does not support URL elicitation (required for notifications/elicitation/complete)",
      );
    }

    return () => notification(
          JsonRpcElicitationCompleteNotification(
            completeParams: ElicitationCompleteParams(
              elicitationId: elicitationId,
            ),
          ),
        );
  }

  /// Sends a `roots/list` request to the client to ask for its root URIs.
  Future<ListRootsResult> listRoots({RequestOptions? options}) {
    final req = const JsonRpcListRootsRequest(id: -1);
    return request<ListRootsResult>(
      req,
      (json) => ListRootsResult.fromJson(json),
      options,
    );
  }

  /// Sends a `notifications/message` (logging) notification to the client.
  Future<void> sendLoggingMessage(
    LoggingMessageNotificationParams params, {
    String? sessionId,
  }) async {
    if (_capabilities.logging != null) {
      if (!_isMessageIgnored(params.level, sessionId)) {
        final notif = JsonRpcLoggingMessageNotification(logParams: params);
        return notification(notif);
      }
    }
  }

  /// Sends a `notifications/resources/updated` notification to the client.
  Future<void> sendResourceUpdated(ResourceUpdatedNotificationParams params) {
    final notif = JsonRpcResourceUpdatedNotification(updatedParams: params);
    return notification(notif);
  }

  /// Sends a `notifications/resources/list_changed` notification to the client.
  Future<void> sendResourceListChanged() {
    const notif = JsonRpcResourceListChangedNotification();
    return notification(notif);
  }

  /// Sends a `notifications/tools/list_changed` notification to the client.
  Future<void> sendToolListChanged() {
    const notif = JsonRpcToolListChangedNotification();
    return notification(notif);
  }

  /// Sends a `notifications/prompts/list_changed` notification to the client.
  Future<void> sendPromptListChanged() {
    const notif = JsonRpcPromptListChangedNotification();
    return notification(notif);
  }

  /// Sends a `notifications/completions/list_changed` notification to the client.
  Future<void> sendCompletionListChanged() {
    const notif = JsonRpcCompletionListChangedNotification();
    return notification(notif);
  }
}
