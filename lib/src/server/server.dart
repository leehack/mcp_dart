import 'dart:async';

import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/types/json_rpc.dart' as json_rpc;

final _logger = Logger("mcp_dart.server");

enum _ServerLifecycleState {
  uninitialized,
  initializing,
  initialized,
  ready,
}

/// Options for configuring the MCP [McpServer].
class McpServerOptions extends ProtocolOptions {
  /// Capabilities to advertise as being supported by this server.
  final ServerCapabilities? capabilities;

  /// Optional instructions describing how to use the server and its features.
  final String? instructions;

  const McpServerOptions({
    super.enforceStrictCapabilities,
    super.taskStore,
    super.taskMessageQueue,
    super.defaultTaskPollInterval,
    super.maxTaskQueueSize,
    this.capabilities,
    this.instructions,
  });
}

/// Deprecated alias for [McpServerOptions].
@Deprecated('Use McpServerOptions instead')
typedef ServerOptions = McpServerOptions;

/// An MCP server implementation built on top of a pluggable [Transport].
///
/// This server automatically handles the initialization flow initiated by the client.
/// It extends the base [Protocol] class, providing server-specific logic and
/// capability handling.
@Deprecated(
  'Use McpServer instead unless you need to create a custom protocol implementation',
)
class Server extends Protocol {
  ClientCapabilities? _clientCapabilities;
  Implementation? _clientVersion;
  _ServerLifecycleState _lifecycleState = _ServerLifecycleState.uninitialized;
  ServerCapabilities _capabilities;
  final String? _instructions;
  final Implementation _serverInfo;

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

  static const Set<String> _statelessRemovedRequestMethods = {
    Method.initialize,
    Method.ping,
    Method.loggingSetLevel,
    Method.resourcesSubscribe,
    Method.resourcesUnsubscribe,
  };

  static const Set<String> _statelessRemovedNotificationMethods = {
    Method.notificationsInitialized,
    Method.notificationsRootsListChanged,
    Method.notificationsTasksStatus,
  };

  static const Set<String> _inputRequiredResultMethods = {
    Method.toolsCall,
    Method.promptsGet,
    Method.resourcesRead,
  };

  /// Callback to be notified when the server is fully initialized.
  void Function()? oninitialized;

  /// Initializes this server with its implementation details and options.
  /// - [options]: Optional configuration settings including server capabilities.
  Server(this._serverInfo, {McpServerOptions? options})
      : _capabilities = options?.capabilities ?? const ServerCapabilities(),
        _instructions = options?.instructions,
        super(options) {
    setRequestHandler<JsonRpcServerDiscoverRequest>(
      Method.serverDiscover,
      (request, extra) async => _onDiscover(),
      (id, params, meta) => JsonRpcServerDiscoverRequest(id: id, meta: meta),
    );

    setRequestHandler<JsonRpcInitializeRequest>(
      Method.initialize,
      (request, extra) async => _oninitialize(request.initParams),
      (id, params, meta) => JsonRpcInitializeRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.initialize,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setNotificationHandler<JsonRpcInitializedNotification>(
      Method.notificationsInitialized,
      (notification) async {
        oninitialized?.call();
        _lifecycleState = _ServerLifecycleState.ready;
      },
      (params, meta) => JsonRpcInitializedNotification.fromJson({
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsInitialized,
        if (params != null) 'params': params,
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
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.loggingSetLevel,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
    }
  }

  void _resetSessionState() {
    _clientCapabilities = null;
    _clientVersion = null;
    _lifecycleState = _ServerLifecycleState.uninitialized;
    _loggingLevels.clear();
  }

  McpError _unsupportedProtocolVersionError(String requestedVersion) {
    return McpError(
      ErrorCode.unsupportedProtocolVersion.value,
      'Unsupported protocol version',
      {
        'supported': supportedProtocolVersionsWithDraft,
        'requested': requestedVersion,
      },
    );
  }

  McpError? _validateStatelessRequestMetadata(JsonRpcRequest request) {
    final meta = request.meta;
    try {
      json_rpc.validateRequestMeta(meta, validateKeys: true);
    } on FormatException catch (error) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Invalid stateless request metadata.',
        error.message,
      );
    }

    final requestedVersion = meta?[McpMetaKey.protocolVersion];
    if (requestedVersion is! String || requestedVersion.isEmpty) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Missing required request metadata: ${McpMetaKey.protocolVersion}',
      );
    }
    if (!supportedProtocolVersionsWithDraft.contains(requestedVersion)) {
      return _unsupportedProtocolVersionError(requestedVersion);
    }
    if (!isStatelessProtocolVersion(requestedVersion)) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'server/discover and stateless requests require a stateless protocol version.',
      );
    }

    final clientInfo = meta?[McpMetaKey.clientInfo];
    if (clientInfo is! Map) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Missing required request metadata: ${McpMetaKey.clientInfo}',
      );
    }

    final clientCapabilities = meta?[McpMetaKey.clientCapabilities];
    if (clientCapabilities is! Map) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Missing required request metadata: ${McpMetaKey.clientCapabilities}',
      );
    }

    try {
      Implementation.fromJson(clientInfo.cast<String, dynamic>());
      ClientCapabilities.fromJson(clientCapabilities.cast<String, dynamic>());
    } catch (error) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Invalid stateless request metadata.',
        error.toString(),
      );
    }

    final logLevel = meta?[McpMetaKey.logLevel];
    if (logLevel != null && _parseLoggingLevel(logLevel) == null) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Invalid stateless request metadata: ${McpMetaKey.logLevel}',
      );
    }

    return null;
  }

  ({ClientCapabilities? capabilities, McpError? error})
      _clientCapabilitiesForRequest(JsonRpcRequest request) {
    final clientCapabilitiesValue =
        request.meta?[McpMetaKey.clientCapabilities];
    try {
      final clientCapabilities = clientCapabilitiesValue is Map
          ? ClientCapabilities.fromJson(
              clientCapabilitiesValue.cast<String, dynamic>(),
            )
          : _clientCapabilities;
      return (capabilities: clientCapabilities, error: null);
    } catch (error) {
      return (
        capabilities: null,
        error: McpError(
          ErrorCode.invalidRequest.value,
          'Invalid request client capabilities metadata.',
          error.toString(),
        ),
      );
    }
  }

  McpError _missingTasksExtensionCapabilityError() {
    return McpError(
      ErrorCode.missingRequiredClientCapability.value,
      'Missing required client capability',
      const {
        'requiredCapabilities': {
          'extensions': {
            mcpTasksExtensionId: <String, dynamic>{},
          },
        },
      },
    );
  }

  McpError _missingInputRequestClientCapabilityError(
    String inputRequestKey,
    String method,
    Map<String, dynamic> requiredCapabilities,
  ) {
    return McpError(
      ErrorCode.missingRequiredClientCapability.value,
      'Missing required client capability for input request',
      {
        'inputRequest': inputRequestKey,
        'method': method,
        'requiredCapabilities': requiredCapabilities,
      },
    );
  }

  bool _isStatelessRequest(JsonRpcRequest request) {
    final requestedProtocolVersion = request.meta?[McpMetaKey.protocolVersion];
    return requestedProtocolVersion is String &&
        isStatelessProtocolVersion(requestedProtocolVersion);
  }

  bool _isStatelessNotification(JsonRpcNotification notification) {
    final requestedProtocolVersion =
        notification.meta?[McpMetaKey.protocolVersion];
    return requestedProtocolVersion is String &&
        isStatelessProtocolVersion(requestedProtocolVersion);
  }

  LoggingLevel? _parseLoggingLevel(Object? value) {
    if (value is LoggingLevel) {
      return value;
    }
    if (value is String) {
      for (final level in LoggingLevel.values) {
        if (level.name == value) {
          return level;
        }
      }
    }
    return null;
  }

  bool _allowsStatelessLogging(
    LoggingLevel messageLevel,
    Map<String, dynamic>? requestMeta,
  ) {
    if (!_isStatelessMeta(requestMeta)) {
      return true;
    }

    final requestedLevel = _parseLoggingLevel(
      requestMeta?[McpMetaKey.logLevel],
    );
    if (requestedLevel == null) {
      return false;
    }

    return _logLevelSeverity[messageLevel]! >=
        _logLevelSeverity[requestedLevel]!;
  }

  bool _isStatelessMeta(Map<String, dynamic>? requestMeta) {
    final requestedProtocolVersion = requestMeta?[McpMetaKey.protocolVersion];
    return requestedProtocolVersion is String &&
        isStatelessProtocolVersion(requestedProtocolVersion);
  }

  McpError? _validateStatelessRemovedRequestMethod(JsonRpcRequest request) {
    if (!_isStatelessRequest(request)) {
      return null;
    }
    if (!_statelessRemovedRequestMethods.contains(request.method)) {
      return null;
    }

    return McpError(
      ErrorCode.methodNotFound.value,
      '${request.method} is not part of MCP stateless protocol versions.',
    );
  }

  McpError? _validateStatelessRemovedNotificationMethod(
    JsonRpcNotification notification,
  ) {
    if (!_isStatelessNotification(notification)) {
      return null;
    }
    if (!_statelessRemovedNotificationMethods.contains(notification.method)) {
      return null;
    }

    return McpError(
      ErrorCode.methodNotFound.value,
      '${notification.method} is not part of MCP stateless protocol versions.',
    );
  }

  McpError? _validateDraftTaskMethods(JsonRpcRequest request) {
    if (!_isStatelessRequest(request)) {
      return null;
    }

    switch (request.method) {
      case Method.tasksList:
      case Method.tasksResult:
        return McpError(
          ErrorCode.methodNotFound.value,
          '${request.method} is not part of the MCP Tasks extension.',
        );
    }

    return null;
  }

  McpError? _validateServerTasksExtensionSupport(JsonRpcRequest request) {
    if (!_isStatelessRequest(request)) {
      return null;
    }

    switch (request.method) {
      case Method.tasksGet:
      case Method.tasksCancel:
      case Method.tasksUpdate:
        if (_capabilities.supportsTasksExtension) {
          return null;
        }
        return McpError(
          ErrorCode.methodNotFound.value,
          '${request.method} requires server support for $mcpTasksExtensionId.',
        );
    }

    return null;
  }

  McpError? _validateTasksExtensionCapabilities(JsonRpcRequest request) {
    final requiresTasksExtension =
        request is JsonRpcSubscriptionsListenRequest &&
            request.listenParams.notifications.taskIds != null;

    if (!requiresTasksExtension) {
      return null;
    }

    final parsed = _clientCapabilitiesForRequest(request);
    if (parsed.error != null) {
      return parsed.error;
    }

    if (parsed.capabilities?.supportsTasksExtension ?? false) {
      return null;
    }

    return _missingTasksExtensionCapabilityError();
  }

  void _assertTasksExtensionClientCapability(JsonRpcRequest request) {
    final parsed = _clientCapabilitiesForRequest(request);
    if (parsed.error != null) {
      throw parsed.error!;
    }
    if (!(parsed.capabilities?.supportsTasksExtension ?? false)) {
      throw _missingTasksExtensionCapabilityError();
    }
  }

  McpError? _validateInputRequiredClientCapabilities(
    InputRequiredResult result,
    JsonRpcRequest request,
  ) {
    final inputRequests = result.inputRequests;
    if (inputRequests == null || inputRequests.isEmpty) {
      return null;
    }

    final parsed = _clientCapabilitiesForRequest(request);
    if (parsed.error != null) {
      return parsed.error;
    }

    for (final entry in inputRequests.entries) {
      final requiredCapabilities = _missingCapabilitiesForInputRequest(
        entry.value,
        parsed.capabilities,
      );
      if (requiredCapabilities != null) {
        return _missingInputRequestClientCapabilityError(
          entry.key,
          entry.value.method,
          requiredCapabilities,
        );
      }
    }

    return null;
  }

  Map<String, dynamic>? _missingCapabilitiesForInputRequest(
    InputRequest inputRequest,
    ClientCapabilities? capabilities,
  ) {
    switch (inputRequest.method) {
      case Method.elicitationCreate:
        final elicitParams = inputRequest.elicitParams;
        final requiredMode = elicitParams.isUrlMode ? 'url' : 'form';
        final elicitation = capabilities?.elicitation;
        final supportsMode = requiredMode == 'url'
            ? elicitation?.url != null
            : elicitation?.form != null;
        if (!supportsMode) {
          return {
            'elicitation': {
              requiredMode: <String, dynamic>{},
            },
          };
        }
        return null;
      case Method.samplingCreateMessage:
        final createParams = inputRequest.createMessageParams;
        final sampling = capabilities?.sampling;
        if (sampling == null) {
          return {'sampling': <String, dynamic>{}};
        }
        if ((createParams.tools != null || createParams.toolChoice != null) &&
            !sampling.tools) {
          return {
            'sampling': {'tools': <String, dynamic>{}},
          };
        }
        return null;
      case Method.rootsList:
        if (capabilities?.roots == null) {
          return {'roots': <String, dynamic>{}};
        }
        return null;
      default:
        return null;
    }
  }

  McpError? _validateRequestTaskSemantics(JsonRpcRequest request) {
    final removedMethodError = _validateDraftTaskMethods(request);
    if (removedMethodError != null) {
      return removedMethodError;
    }

    final serverExtensionError = _validateServerTasksExtensionSupport(request);
    if (serverExtensionError != null) {
      return serverExtensionError;
    }

    final extensionCapabilityError =
        _validateTasksExtensionCapabilities(request);
    if (extensionCapabilityError != null) {
      return extensionCapabilityError;
    }

    return null;
  }

  Future<bool> _allowsToolCallResult(
    BaseResultData result,
    JsonRpcRequest request,
    RequestHandlerExtra extra,
  ) async {
    if (result is CallToolResult) {
      _validateCallToolResult(result, request);
      return true;
    }
    if (_allowsInputRequiredResult(result, request)) {
      return true;
    }
    if (result is CreateTaskExtensionResult && _isStatelessRequest(request)) {
      await _validateTaskCreationResult(result, request, extra);
      return true;
    }

    return false;
  }

  void _validateCallToolResult(
    CallToolResult result,
    JsonRpcRequest request,
  ) {
    if (!_isStatelessRequest(request)) {
      return;
    }

    final resultType = result.extra?['resultType'];
    if (resultType == null || resultType == resultTypeComplete) {
      return;
    }

    throw McpError(
      ErrorCode.invalidParams.value,
      'Invalid ${request.method} result: CallToolResult cannot set MCP '
      'resultType "$resultType"; use InputRequiredResult or '
      'CreateTaskExtensionResult.',
    );
  }

  Future<void> _validateTaskCreationResult(
    CreateTaskExtensionResult result,
    JsonRpcRequest request,
    RequestHandlerExtra extra,
  ) async {
    if (!_capabilities.supportsTasksExtension) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: CreateTaskExtensionResult requires '
        'server support for $mcpTasksExtensionId.',
      );
    }

    _assertTasksExtensionClientCapability(request);

    if (!canHandleRequestMethod(Method.tasksGet)) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: CreateTaskExtensionResult requires '
        'a tasks/get handler so ${result.task.taskId} can be resolved.',
      );
    }

    final resolvedResult = await _resolveCreatedTask(result, request, extra);
    if (resolvedResult is! GetTaskExtensionResult) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: tasks/get for '
        '${result.task.taskId} must return GetTaskExtensionResult.',
      );
    }
    if (resolvedResult.task.taskId != result.task.taskId) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: tasks/get resolved '
        '${resolvedResult.task.taskId} instead of ${result.task.taskId}.',
      );
    }
  }

  Future<BaseResultData> _resolveCreatedTask(
    CreateTaskExtensionResult result,
    JsonRpcRequest request,
    RequestHandlerExtra extra,
  ) async {
    try {
      return await invokeRequestHandlerForValidation(
        JsonRpcGetTaskRequest(
          id: request.id,
          getParams: GetTaskRequest(taskId: result.task.taskId),
          meta: request.meta,
        ),
        extra,
      );
    } catch (error) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: CreateTaskExtensionResult taskId '
        '${result.task.taskId} must be resolvable by tasks/get before '
        'returning.',
        error.toString(),
      );
    }
  }

  bool _allowsPromptGetResult(BaseResultData result, JsonRpcRequest request) {
    return result is GetPromptResult ||
        _allowsInputRequiredResult(result, request);
  }

  bool _allowsResourceReadResult(
    BaseResultData result,
    JsonRpcRequest request,
  ) {
    return result is ReadResourceResult ||
        _allowsInputRequiredResult(result, request);
  }

  bool _allowsInputRequiredResult(
    BaseResultData result,
    JsonRpcRequest request,
  ) {
    if (result is! InputRequiredResult ||
        !_isStatelessRequest(request) ||
        !_inputRequiredResultMethods.contains(request.method)) {
      return false;
    }

    final capabilityError = _validateInputRequiredClientCapabilities(
      result,
      request,
    );
    if (capabilityError != null) {
      throw capabilityError;
    }

    return true;
  }

  void _validateUnsupportedInputRequiredResult(
    BaseResultData result,
    JsonRpcRequest request,
  ) {
    if (result is! InputRequiredResult) {
      return;
    }

    throw McpError(
      ErrorCode.invalidParams.value,
      'Invalid ${request.method} result: InputRequiredResult is only supported '
      'by ${_inputRequiredResultMethods.join(', ')} in MCP stateless requests.',
    );
  }

  bool _allowsTaskExtensionResult(
    BaseResultData result,
    JsonRpcRequest request,
  ) {
    if (!_isStatelessRequest(request)) {
      return true;
    }

    return switch (request.method) {
      Method.tasksGet => result is GetTaskExtensionResult,
      Method.tasksCancel ||
      Method.tasksUpdate =>
        result is TaskExtensionAcknowledgementResult || result is EmptyResult,
      _ => true,
    };
  }

  String _expectedTaskExtensionResult(String method) {
    return switch (method) {
      Method.tasksGet => 'GetTaskExtensionResult',
      Method.tasksCancel ||
      Method.tasksUpdate =>
        'TaskExtensionAcknowledgementResult or EmptyResult',
      _ => 'valid MCP Tasks extension result',
    };
  }

  bool _isLegacyTaskAugmentedRequest(JsonRpcCallToolRequest request) {
    if (_isStatelessRequest(request)) {
      return false;
    }
    return request.isTaskAugmented;
  }

  @override
  McpError? validateIncomingRequest(JsonRpcRequest request) {
    if (request.method == Method.serverDiscover) {
      final metadataError = _validateStatelessRequestMetadata(request);
      if (metadataError != null) {
        return metadataError;
      }
      return null;
    }

    final requestedProtocolVersion = request.meta?[McpMetaKey.protocolVersion];
    if (requestedProtocolVersion is String &&
        !supportedProtocolVersionsWithDraft
            .contains(requestedProtocolVersion)) {
      return _unsupportedProtocolVersionError(requestedProtocolVersion);
    }
    if (requestedProtocolVersion is String &&
        isStatelessProtocolVersion(requestedProtocolVersion)) {
      final metadataError = _validateStatelessRequestMetadata(request);
      if (metadataError != null) {
        return metadataError;
      }
      final removedMethodError = _validateStatelessRemovedRequestMethod(
        request,
      );
      if (removedMethodError != null) {
        return removedMethodError;
      }
      return _validateRequestTaskSemantics(request);
    }

    if (request.method == Method.initialize) {
      if (_lifecycleState != _ServerLifecycleState.uninitialized) {
        return McpError(
          ErrorCode.invalidRequest.value,
          "Received duplicate initialize request.",
        );
      }
      return null;
    }

    if (request.method == Method.ping) {
      return null;
    }

    if (_lifecycleState == _ServerLifecycleState.uninitialized) {
      return McpError(
        ErrorCode.invalidRequest.value,
        "Received ${request.method} before initialize; initialize must be the first interaction.",
      );
    }

    if (_lifecycleState != _ServerLifecycleState.ready) {
      return McpError(
        ErrorCode.invalidRequest.value,
        "Received ${request.method} before notifications/initialized.",
      );
    }

    return _validateRequestTaskSemantics(request);
  }

  @override
  McpError? validateIncomingNotification(JsonRpcNotification notification) {
    final removedMethodError =
        _validateStatelessRemovedNotificationMethod(notification);
    if (removedMethodError != null) {
      return removedMethodError;
    }

    switch (notification.method) {
      case Method.notificationsCancelled:
      case Method.notificationsProgress:
        return null;
      case Method.notificationsInitialized:
        if (_lifecycleState == _ServerLifecycleState.uninitialized ||
            _lifecycleState == _ServerLifecycleState.initializing) {
          return McpError(
            ErrorCode.invalidRequest.value,
            "Received notifications/initialized before initialize.",
          );
        }
        if (_lifecycleState == _ServerLifecycleState.ready) {
          return McpError(
            ErrorCode.invalidRequest.value,
            "Received duplicate notifications/initialized.",
          );
        }
        return null;
      default:
        if (_lifecycleState == _ServerLifecycleState.uninitialized) {
          return McpError(
            ErrorCode.invalidRequest.value,
            "Received ${notification.method} before initialize; initialize must be the first interaction.",
          );
        }
        if (_lifecycleState != _ServerLifecycleState.ready) {
          return McpError(
            ErrorCode.invalidRequest.value,
            "Received ${notification.method} before notifications/initialized.",
          );
        }
        return null;
    }
  }

  @override
  void onIncomingRequestAccepted(JsonRpcRequest request) {
    if (request.method == Method.initialize) {
      _lifecycleState = _ServerLifecycleState.initializing;
    }
  }

  @override
  void onIncomingRequestHandled(
    JsonRpcRequest request,
    BaseResultData result,
  ) {
    if (request.method == Method.initialize &&
        _lifecycleState == _ServerLifecycleState.initializing) {
      _lifecycleState = _ServerLifecycleState.initialized;
    }
  }

  @override
  void onIncomingRequestFailed(JsonRpcRequest request, Object error) {
    if (request.method == Method.initialize &&
        _lifecycleState == _ServerLifecycleState.initializing) {
      _clientCapabilities = null;
      _clientVersion = null;
      _lifecycleState = _ServerLifecycleState.uninitialized;
    }
  }

  bool _requiresCacheableResult(String method) {
    return switch (method) {
      Method.toolsList ||
      Method.promptsList ||
      Method.resourcesList ||
      Method.resourcesTemplatesList ||
      Method.resourcesRead =>
        true,
      _ => false,
    };
  }

  void _omitStatelessLegacyToolExecution(
    Map<String, dynamic> resultJson,
  ) {
    final tools = resultJson['tools'];
    if (tools is! List) {
      return;
    }
    for (final tool in tools) {
      if (tool is Map<String, dynamic>) {
        tool.remove('execution');
      }
    }
  }

  @override
  Map<String, dynamic> serializeIncomingResult(
    JsonRpcRequest request,
    BaseResultData result,
  ) {
    final json = super.serializeIncomingResult(request, result);
    if (!_isStatelessRequest(request)) {
      return json;
    }

    if (request.method == Method.toolsList) {
      _omitStatelessLegacyToolExecution(json);
    }

    json.putIfAbsent('resultType', () => resultTypeComplete);
    if (_requiresCacheableResult(request.method)) {
      json.putIfAbsent(
        'ttlMs',
        () => result is CacheableResultData ? result.ttlMs ?? 0 : 0,
      );
      json.putIfAbsent(
        'cacheScope',
        () => result is CacheableResultData
            ? result.cacheScope ?? CacheScope.private
            : CacheScope.private,
      );
    }

    return json;
  }

  @override
  void onConnectionClosed() {
    _resetSessionState();
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

        // Validate the result based on whether it's a legacy task-augmented
        // request. The stateless task extension ignores the old `task` hint.
        if (request is JsonRpcCallToolRequest &&
            _isLegacyTaskAugmentedRequest(request)) {
          if (result is! CreateTaskResult) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Invalid task creation result: Expected CreateTaskResult",
            );
          }
        } else {
          if (!await _allowsToolCallResult(result, request, extra)) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Invalid tools/call result: Expected CallToolResult",
            );
          }
        }
        return result;
      }

      super.setRequestHandler(method, wrappedHandler, requestFactory);
    } else if (method == Method.promptsGet) {
      Future<BaseResultData> wrappedHandler(
        ReqT request,
        RequestHandlerExtra extra,
      ) async {
        final result = await handler(request, extra);
        if (!_allowsPromptGetResult(result, request)) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'Invalid prompts/get result: Expected GetPromptResult',
          );
        }
        return result;
      }

      super.setRequestHandler(method, wrappedHandler, requestFactory);
    } else if (method == Method.resourcesRead) {
      Future<BaseResultData> wrappedHandler(
        ReqT request,
        RequestHandlerExtra extra,
      ) async {
        final result = await handler(request, extra);
        if (!_allowsResourceReadResult(result, request)) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'Invalid resources/read result: Expected ReadResourceResult',
          );
        }
        return result;
      }

      super.setRequestHandler(method, wrappedHandler, requestFactory);
    } else if (method == Method.tasksGet ||
        method == Method.tasksCancel ||
        method == Method.tasksUpdate) {
      Future<BaseResultData> wrappedHandler(
        ReqT request,
        RequestHandlerExtra extra,
      ) async {
        final result = await handler(request, extra);
        if (!_allowsTaskExtensionResult(result, request)) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Invalid ${request.method} result for MCP Tasks extension: Expected ${_expectedTaskExtensionResult(request.method)}",
          );
        }
        return result;
      }

      super.setRequestHandler(method, wrappedHandler, requestFactory);
    } else {
      Future<BaseResultData> wrappedHandler(
        ReqT request,
        RequestHandlerExtra extra,
      ) async {
        final result = await handler(request, extra);
        _validateUnsupportedInputRequiredResult(result, request);
        return result;
      }

      super.setRequestHandler(method, wrappedHandler, requestFactory);
    }
  }

  /// Handles the client's `initialize` request.
  Future<InitializeResult> _oninitialize(InitializeRequest params) async {
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

  ServerCapabilities _discoveryCapabilities() {
    final json = getCapabilities().toJson();
    json.remove('tasks');
    return ServerCapabilities.fromJson(json);
  }

  /// Handles the client's `server/discover` request.
  Future<DiscoverResult> _onDiscover() async {
    return DiscoverResult(
      supportedVersions: supportedProtocolVersionsWithDraft,
      capabilities: _discoveryCapabilities(),
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
            ErrorCode.methodNotFound.value,
            "Client does not support sampling (required for server to send $method)",
          );
        }
        break;

      case Method.rootsList:
        if (!(_clientCapabilities?.roots != null)) {
          throw McpError(
            ErrorCode.methodNotFound.value,
            "Client does not support listing roots (required for server to send $method)",
          );
        }
        break;

      case Method.elicitationCreate:
        if (!(_clientCapabilities?.elicitation != null)) {
          throw McpError(
            ErrorCode.methodNotFound.value,
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
        throw StateError(
          "$method is not part of stable MCP 2025-11-25. Use ${Method.notificationsExperimentalCompletionsListChanged} for extension behavior.",
        );

      case Method.notificationsExperimentalCompletionsListChanged:
        if (_capabilities.completions == null) {
          throw StateError(
            "Server does not support completions capability (required for sending $method)",
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

      case Method.notificationsTasks:
        if (!_capabilities.supportsTasksExtension) {
          throw StateError(
            "Server does not support the $mcpTasksExtensionId extension (required for sending $method)",
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
      case Method.notificationsSubscriptionsAcknowledged:
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
      case Method.serverDiscover:
      case Method.initialize:
      case Method.ping:
      case Method.completionComplete:
      case Method.subscriptionsListen:
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
      case Method.tasksResult:
        if (!(_capabilities.tasks != null ||
            _capabilities.supportsTasksExtension)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'tasks' capability or '$mcpTasksExtensionId' extension",
          );
        }
        break;

      case Method.tasksCancel:
      case Method.tasksGet:
        if (!(_capabilities.tasks != null ||
            _capabilities.supportsTasksExtension)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'tasks' capability or '$mcpTasksExtensionId' extension",
          );
        }
        break;

      case Method.tasksUpdate:
        if (!_capabilities.supportsTasksExtension) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without '$mcpTasksExtensionId' extension",
          );
        }
        break;

      default:
        _logger.info(
          "Setting request handler for potentially custom method '$method'. Ensure server capabilities match.",
        );
    }
  }

  @override
  void assertTaskCapability(String method) {
    final missingCapability = switch (method) {
      Method.samplingCreateMessage =>
        _clientCapabilities?.tasks?.requests?.sampling?.createMessage == null
            ? 'tasks.requests.sampling.createMessage'
            : null,
      Method.elicitationCreate =>
        _clientCapabilities?.tasks?.requests?.elicitation?.create == null
            ? 'tasks.requests.elicitation.create'
            : null,
      _ =>
        _clientCapabilities?.tasks == null ? 'tasks' : 'tasks.requests.$method',
    };

    if (missingCapability != null) {
      throw McpError(
        ErrorCode.methodNotFound.value,
        "Client does not support capability '$missingCapability' required for task-based '$method'",
      );
    }
  }

  @override
  void assertTaskHandlerCapability(String method) {
    final missingCapability = switch (method) {
      Method.toolsCall => _capabilities.tasks?.requests?.tools?.call == null
          ? 'tasks.requests.tools.call'
          : null,
      _ => _capabilities.tasks == null ? 'tasks' : 'tasks.requests.$method',
    };

    if (missingCapability != null) {
      throw StateError(
        "Server setup error: Cannot handle task-based '$method' without '$missingCapability' capability registered.",
      );
    }
  }

  /// Sends a `ping` request to the client and awaits an empty response.
  Future<EmptyResult> ping([RequestOptions? options]) {
    return request<EmptyResult>(
      const JsonRpcPingRequest(id: -1),
      EmptyResult.fromJson,
      options,
    );
  }

  /// Sends a `sampling/createMessage` request to the client to ask it to sample an LLM.
  Future<CreateMessageResult> createMessage(
    CreateMessageRequest params, [
    RequestOptions? options,
  ]) {
    // Capability check - only required when tools/toolChoice are provided
    if (params.tools != null || params.toolChoice != null) {
      if (!(_clientCapabilities?.sampling?.tools ?? false)) {
        throw McpError(
          ErrorCode.methodNotFound.value,
          "Client does not support sampling tools capability.",
        );
      }
    }
    if (params.includeContext != null &&
        params.includeContext != IncludeContext.none &&
        !(_clientCapabilities?.sampling?.context ?? false)) {
      throw McpError(
        ErrorCode.methodNotFound.value,
        "Client does not support sampling context capability.",
      );
    }

    // Message structure validation - always validate tool_use/tool_result pairs.
    if (params.messages.isNotEmpty) {
      final lastMessage = params.messages.last;
      final lastContent = lastMessage.contentBlocks;
      final hasToolResults =
          lastContent.any((c) => c is SamplingToolResultContent);

      final previousMessage = params.messages.length > 1
          ? params.messages[params.messages.length - 2]
          : null;
      final previousContent =
          previousMessage?.contentBlocks ?? const <SamplingContent>[];
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
    ElicitRequest params, [
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
        params.requestedSchema!.validate(result.content);
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
            completeParams: ElicitationCompleteNotification(
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
  ///
  /// For stateless MCP requests, pass [requestMeta] from
  /// [RequestHandlerExtra.meta] so log notifications honor the request-scoped
  /// `io.modelcontextprotocol/logLevel` opt-in.
  Future<void> sendLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
    Map<String, dynamic>? requestMeta,
  }) async {
    if (_capabilities.logging != null) {
      final statelessLogContext = _isStatelessMeta(requestMeta);
      if (_allowsStatelessLogging(params.level, requestMeta) &&
          (statelessLogContext ||
              !_isMessageIgnored(params.level, sessionId))) {
        final notif = JsonRpcLoggingMessageNotification(logParams: params);
        return notification(notif);
      }
    }
  }

  /// Sends a `notifications/resources/updated` notification to the client.
  Future<void> sendResourceUpdated(ResourceUpdatedNotification params) {
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

  /// Sends an experimental completion list-changed notification to the client.
  ///
  /// Stable MCP 2025-11-25 does not define a completion list-changed
  /// notification or capability flag.
  @Deprecated(
    'Stable MCP 2025-11-25 does not define completion list-changed notifications.',
  )
  Future<void> sendCompletionListChanged() {
    const notif = JsonRpcCompletionListChangedNotification();
    return notification(notif);
  }
}
