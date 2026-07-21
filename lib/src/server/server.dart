import 'dart:async';

import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/protocol_direction.dart';
import 'package:mcp_dart/src/shared/protocol_notification_validation.dart';
import 'package:mcp_dart/src/shared/stateless_meta_validation.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/types/json_rpc.dart' as json_rpc;
import 'package:mcp_dart/src/types/validation.dart'
    show readJsonObject, readOptionalJsonObject;

import 'server_protocol_state.dart';

final _logger = Logger("mcp_dart.server");

void _validateServerNotification(
  Object protocol,
  JsonRpcNotification notification,
) {
  (protocol as Server)._validateOutgoingNotification(notification);
}

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

  /// High-level protocol compatibility profile.
  ///
  /// Defaults to [McpProtocol.stable], which advertises MCP `2026-07-28`
  /// stateless behavior alongside legacy protocol versions. Set this to
  /// [McpProtocol.legacy] to advertise only legacy MCP versions.
  final McpProtocol protocol;

  /// Protocol versions this server advertises and accepts for this profile.
  List<String> get supportedVersions => protocol.supportedVersions;

  const McpServerOptions({
    super.enforceStrictCapabilities,
    super.taskStore,
    super.taskMessageQueue,
    super.defaultTaskPollInterval,
    super.maxTaskQueueSize,
    super.gracefulShutdownTimeout,
    this.capabilities,
    this.instructions,
    this.protocol = McpProtocol.stable,
  });
}

/// Deprecated alias for [McpServerOptions].
@Deprecated('Use McpServerOptions instead')
typedef ServerOptions = McpServerOptions;

enum _ServerConnectionMode { undecided, legacy, stateless }

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
  _ServerConnectionMode _connectionMode = _ServerConnectionMode.undecided;
  ServerCapabilities _capabilities;
  final String? _instructions;
  final Implementation _serverInfo;
  final List<String> _supportedVersions;

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

  static const Set<String> _statelessOnlyRequestMethods = {
    Method.subscriptionsListen,
    Method.tasksUpdate,
  };

  static const Set<String> _statelessSubscriptionOnlyNotificationMethods = {
    Method.notificationsSubscriptionsAcknowledged,
    Method.notificationsToolsListChanged,
    Method.notificationsPromptsListChanged,
    Method.notificationsResourcesListChanged,
    Method.notificationsResourcesUpdated,
    Method.notificationsTasks,
  };

  static const Set<String> _statelessHandlerForbiddenNotificationMethods = {
    Method.notificationsCancelled,
    Method.notificationsInitialized,
    Method.notificationsRootsListChanged,
    Method.notificationsTasksStatus,
    Method.notificationsCompletionsListChanged,
    Method.notificationsExperimentalCompletionsListChanged,
    Method.notificationsElicitationComplete,
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
        _supportedVersions =
            options?.supportedVersions ?? McpProtocol.stable.supportedVersions,
        super(options) {
    writeProtocolNotificationValidator(this, _validateServerNotification);
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

  @override
  Future<void> connect(Transport transport) {
    if (transport is ServerSupportedProtocolVersionsAwareTransport) {
      (transport as ServerSupportedProtocolVersionsAwareTransport)
          .setServerSupportedProtocolVersions(_supportedVersions);
    }
    return super.connect(transport);
  }

  void _resetSessionState() {
    _clientCapabilities = null;
    _clientVersion = null;
    writeServerProtocolVersion(this, null);
    _lifecycleState = _ServerLifecycleState.uninitialized;
    _connectionMode = _ServerConnectionMode.undecided;
    _loggingLevels.clear();
    clearServerTaskOutputValidators(this);
  }

  McpError _unsupportedProtocolVersionError(String requestedVersion) {
    return McpError(
      ErrorCode.unsupportedProtocolVersion.value,
      'Unsupported protocol version',
      {
        'supported': _supportedVersions,
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
        ErrorCode.invalidParams.value,
        'Invalid stateless request metadata.',
        error.message,
      );
    }

    final requestedVersion = meta?[McpMetaKey.protocolVersion];
    if (requestedVersion is! String || requestedVersion.isEmpty) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Missing required request metadata: ${McpMetaKey.protocolVersion}',
      );
    }
    if (!_supportedVersions.contains(requestedVersion)) {
      return _unsupportedProtocolVersionError(requestedVersion);
    }
    if (!isStatelessProtocolVersion(requestedVersion)) {
      return McpError(
        ErrorCode.invalidParams.value,
        'server/discover and stateless requests require a stateless protocol version.',
      );
    }

    final hasClientInfo = meta?.containsKey(McpMetaKey.clientInfo) == true;
    final clientInfo = meta?[McpMetaKey.clientInfo];
    if (hasClientInfo && clientInfo is! Map) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Invalid stateless request metadata: ${McpMetaKey.clientInfo}',
      );
    }

    final clientCapabilities = meta?[McpMetaKey.clientCapabilities];
    if (clientCapabilities is! Map) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Missing required request metadata: ${McpMetaKey.clientCapabilities}',
      );
    }

    try {
      final typedClientCapabilities =
          clientCapabilities.cast<String, dynamic>();
      if (hasClientInfo) {
        Implementation.fromJson(clientInfo!.cast<String, dynamic>());
      }
      ClientCapabilities.fromStatelessJson(typedClientCapabilities);
    } catch (error) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Invalid stateless request metadata.',
        error.toString(),
      );
    }

    final logLevel = meta?[McpMetaKey.logLevel];
    if (logLevel != null && _parseLoggingLevel(logLevel) == null) {
      return McpError(
        ErrorCode.invalidParams.value,
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
      final protocolVersion = request.meta?[McpMetaKey.protocolVersion];
      ClientCapabilities? clientCapabilities;
      if (clientCapabilitiesValue is Map) {
        final json = clientCapabilitiesValue.cast<String, dynamic>();
        clientCapabilities = protocolVersion is String &&
                isStatelessProtocolVersion(protocolVersion)
            ? ClientCapabilities.fromStatelessJson(json)
            : ClientCapabilities.fromJson(json);
      } else {
        clientCapabilities = _clientCapabilities;
      }
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

  bool _usesStatelessNotificationSemantics(
    JsonRpcNotification notification,
  ) =>
      _connectionMode == _ServerConnectionMode.stateless ||
      (_connectionMode == _ServerConnectionMode.undecided &&
          _supportsStatelessProtocol &&
          !_supportsLegacyInitialization) ||
      _isStatelessNotification(notification);

  McpError? _validateRequestConnectionMode(JsonRpcRequest request) {
    final requestedProtocolVersion = request.meta?[McpMetaKey.protocolVersion];
    final selectsSupportedLegacyVersion = requestedProtocolVersion is String &&
        _supportedVersions.contains(requestedProtocolVersion) &&
        !isStatelessProtocolVersion(requestedProtocolVersion);
    return switch (_connectionMode) {
      _ServerConnectionMode.undecided => null,
      _ServerConnectionMode.legacy
          when request.method == Method.serverDiscover ||
              _isStatelessRequest(request) =>
        McpError(
          ErrorCode.invalidRequest.value,
          'This connection already selected the legacy initialize protocol; '
          'stateless requests require a separate connection.',
        ),
      _ServerConnectionMode.stateless
          when request.method == Method.initialize ||
              requestedProtocolVersion is! String ||
              selectsSupportedLegacyVersion =>
        McpError(
          ErrorCode.invalidRequest.value,
          'This connection already selected the stateless protocol; every '
          'request must use stateless protocol metadata.',
        ),
      _ => null,
    };
  }

  bool get _requiresStatelessMetadataBeforeConnectionMode =>
      _connectionMode == _ServerConnectionMode.stateless ||
      (_connectionMode == _ServerConnectionMode.undecided &&
          _supportsStatelessProtocol &&
          !_supportsLegacyInitialization);

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

  McpError? _validateStatelessClientNotificationDirection(
    JsonRpcNotification notification,
  ) {
    if (!_usesStatelessNotificationSemantics(notification)) {
      return null;
    }
    if (!isStatelessForbiddenClientNotification(notification.method)) {
      return null;
    }

    return McpError(
      ErrorCode.methodNotFound.value,
      '${notification.method} is not a client-to-server notification in MCP '
      'stateless protocol versions.',
    );
  }

  McpError? _validateLegacyRemovedRequestMethod(JsonRpcRequest request) {
    if (_isStatelessRequest(request) ||
        !_statelessOnlyRequestMethods.contains(request.method)) {
      return null;
    }
    return McpError(
      ErrorCode.methodNotFound.value,
      '${request.method} is only available in MCP stateless protocol versions.',
    );
  }

  McpError? _validateLegacyTaskCapability(JsonRpcRequest request) {
    if (_isStatelessRequest(request)) {
      return null;
    }
    final isLegacyTaskMethod = switch (request.method) {
      Method.tasksGet ||
      Method.tasksCancel ||
      Method.tasksList ||
      Method.tasksResult =>
        true,
      _ => false,
    };
    if (!isLegacyTaskMethod || _capabilities.tasks != null) {
      return null;
    }
    return McpError(
      ErrorCode.methodNotFound.value,
      '${request.method} requires the legacy tasks capability under MCP '
      '$latestInitializationProtocolVersion; $mcpTasksExtensionId does not '
      'enable legacy tasks.',
    );
  }

  McpError? _validateStatelessTaskMethods(JsonRpcRequest request) {
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
    final isTaskExtensionMethod = switch (request.method) {
      Method.tasksGet || Method.tasksUpdate || Method.tasksCancel => true,
      _ => false,
    };
    final requiresTasksExtension =
        (_isStatelessRequest(request) && isTaskExtensionMethod) ||
            (request is JsonRpcSubscriptionsListenRequest &&
                request.listenParams.notifications.taskIds != null);

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
  ) =>
      _validateInputRequestsClientCapabilities(result.inputRequests, request);

  McpError? _validateInputRequestsClientCapabilities(
    InputRequests? inputRequests,
    JsonRpcRequest request,
  ) {
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
            : elicitation?.supportsForm ?? false;
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
        if (createParams.includeContext != null &&
            createParams.includeContext != IncludeContext.none &&
            !sampling.context) {
          return {
            'sampling': {'context': <String, dynamic>{}},
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
    final legacyMethodError = _validateLegacyRemovedRequestMethod(request);
    if (legacyMethodError != null) {
      return legacyMethodError;
    }
    final legacyTaskError = _validateLegacyTaskCapability(request);
    if (legacyTaskError != null) {
      return legacyTaskError;
    }

    if (request is JsonRpcCallToolRequest) {
      try {
        request.callParams;
      } on FormatException {
        return McpError(
          ErrorCode.invalidParams.value,
          'Failed to parse params for request ${Method.toolsCall}',
        );
      }

      final validatesTaskAugmentation = !_isStatelessRequest(request) &&
          readServerProtocolVersion(this) ==
              latestInitializationProtocolVersion &&
          _capabilities.tasks?.requests?.tools?.call != null &&
          request.isTaskAugmented;
      if (validatesTaskAugmentation) {
        try {
          if (request.taskParams == null) {
            throw const FormatException('Task params must be an object');
          }
        } on FormatException {
          return McpError(
            ErrorCode.invalidParams.value,
            'Failed to parse task params for request ${Method.toolsCall}',
          );
        }
      }
    }

    final removedMethodError = _validateStatelessTaskMethods(request);
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
      try {
        await _validateTaskCreationResult(result, request, extra);
      } catch (_) {
        removeServerTaskOutputValidator(
          this,
          extra.sessionId,
          result.task.taskId,
        );
        rethrow;
      }
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
      final resolvedResult = await invokeRequestHandlerForValidation(
        JsonRpcGetTaskRequest(
          id: request.id,
          getParams: GetTaskRequest(taskId: result.task.taskId),
          meta: request.meta,
        ),
        extra,
      );
      // The durability requirement is about a real tasks/get response, not
      // merely a handler returning the expected Dart type. Force detailed task
      // and JSON validation now so an unserializable task cannot be advertised.
      if (resolvedResult is GetTaskExtensionResult) {
        resolvedResult.toJson();
      }
      return resolvedResult;
    } on ServerTaskOutputValidationError {
      rethrow;
    } on McpError catch (error, stackTrace) {
      if (error.code == ErrorCode.missingRequiredClientCapability.value) {
        rethrow;
      }
      _logger.error(
        'Failed to resolve task ${result.task.taskId} with tasks/get while '
        'validating ${request.method}: $error\n$stackTrace',
      );
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: CreateTaskExtensionResult taskId '
        '${result.task.taskId} must be resolvable by tasks/get before '
        'returning.',
        {'taskId': result.task.taskId},
      );
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to resolve task ${result.task.taskId} with tasks/get while '
        'validating ${request.method}: $error\n$stackTrace',
      );
      throw McpError(
        ErrorCode.invalidParams.value,
        'Invalid ${request.method} result: CreateTaskExtensionResult taskId '
        '${result.task.taskId} must be resolvable by tasks/get before '
        'returning.',
        {'taskId': result.task.taskId},
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

  void _validateTaskExtensionToolResult(
    BaseResultData result,
    JsonRpcRequest request,
    RequestHandlerExtra extra,
  ) {
    if (!_isStatelessRequest(request) ||
        request is! JsonRpcGetTaskRequest ||
        result is! GetTaskExtensionResult) {
      return;
    }

    final task = result.task;
    final requestedTaskId = request.getParams.taskId;
    if (task.taskId != requestedTaskId) {
      throw McpError(
        ErrorCode.internalError.value,
        'Invalid ${request.method} result: returned task ${task.taskId} '
        'instead of requested task $requestedTaskId.',
      );
    }
    if (task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled) {
      removeServerTaskOutputValidator(
        this,
        extra.sessionId,
        requestedTaskId,
      );
      return;
    }
    if (task.status != TaskStatus.completed) {
      return;
    }

    final validator = readServerTaskOutputValidator(
      this,
      extra.sessionId,
      requestedTaskId,
    );
    if (validator != null) {
      validator(task.result!);
      // Completed task results are immutable, so the captured schema contract
      // is no longer needed after the final result validates successfully.
      removeServerTaskOutputValidator(
        this,
        extra.sessionId,
        requestedTaskId,
      );
    }
  }

  void _validateTaskExtensionInputRequests(
    BaseResultData result,
    JsonRpcRequest request,
  ) {
    if (!_isStatelessRequest(request) || result is! GetTaskExtensionResult) {
      return;
    }
    final capabilityError = _validateInputRequestsClientCapabilities(
      result.task.inputRequests,
      request,
    );
    if (capabilityError != null) {
      throw capabilityError;
    }
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
    if (readServerProtocolVersion(this) ==
            latestInitializationProtocolVersion &&
        _capabilities.tasks?.requests?.tools?.call == null) {
      return false;
    }
    return request.isTaskAugmented;
  }

  @override
  McpError? validateIncomingRequest(JsonRpcRequest request) {
    // A stateless-only server, and a connection that has already selected the
    // stateless protocol, can identify malformed 2026 requests without using
    // legacy lifecycle state. Validate the required per-request fields first
    // so missing metadata consistently maps to Invalid params (-32602).
    var statelessMetadataValidated = false;
    if (_requiresStatelessMetadataBeforeConnectionMode) {
      final metadataError = _validateStatelessRequestMetadata(request);
      if (metadataError != null) {
        return metadataError;
      }
      statelessMetadataValidated = true;
    }

    final connectionModeError = _validateRequestConnectionMode(request);
    if (connectionModeError != null) {
      return connectionModeError;
    }

    if (request.method == Method.serverDiscover) {
      if (!_supportsStatelessProtocol) {
        // A recognized modern protocol error would identify this as a modern
        // server. Legacy-only profiles must instead let dual-era clients use
        // the initialize fallback defined by the compatibility rules.
        return McpError(
          ErrorCode.methodNotFound.value,
          '${Method.serverDiscover} is not available for legacy MCP profiles.',
        );
      }
      if (!statelessMetadataValidated) {
        final metadataError = _validateStatelessRequestMetadata(request);
        if (metadataError != null) {
          return metadataError;
        }
      }
      return null;
    }

    final requestedProtocolVersion = request.meta?[McpMetaKey.protocolVersion];
    if (requestedProtocolVersion is String &&
        !_supportedVersions.contains(requestedProtocolVersion)) {
      return _unsupportedProtocolVersionError(requestedProtocolVersion);
    }
    if (requestedProtocolVersion is String &&
        isStatelessProtocolVersion(requestedProtocolVersion)) {
      if (!statelessMetadataValidated) {
        final metadataError = _validateStatelessRequestMetadata(request);
        if (metadataError != null) {
          return metadataError;
        }
      }
      try {
        validateStatelessRequestMetaObjects(request);
      } on FormatException catch (error) {
        return McpError(
          ErrorCode.invalidParams.value,
          'Invalid nested stateless request metadata.',
          error.message,
        );
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
      if (!_supportsLegacyInitialization) {
        return _unsupportedProtocolVersionError(defaultProtocolVersion);
      }
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
  McpError? validateIncomingNotificationBeforeParsing(
    JsonRpcNotification notification,
  ) =>
      _validateStatelessClientNotificationDirection(notification);

  @override
  McpError? validateIncomingNotification(JsonRpcNotification notification) {
    if (_usesStatelessNotificationSemantics(notification)) {
      try {
        validateStatelessNotificationMetaObjects(notification);
      } on FormatException catch (error) {
        return McpError(
          ErrorCode.invalidParams.value,
          'Invalid stateless notification metadata.',
          error.message,
        );
      }
    }

    final directionError =
        _validateStatelessClientNotificationDirection(notification);
    if (directionError != null) {
      return directionError;
    }
    if (_usesStatelessNotificationSemantics(notification)) {
      // Stateless MCP has no initialize lifecycle. Cancellation and custom
      // extension notifications that survive the direction check are valid
      // inputs for protocol or application handlers.
      return null;
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
  void validateOutgoingSubscriptionNotification(
    JsonRpcSubscriptionsListenRequest request,
    JsonRpcNotification notification,
  ) {
    if (notification.method != Method.notificationsTasks) {
      return;
    }
    final taskNotification = notification is JsonRpcTaskNotification
        ? notification
        : JsonRpcTaskNotification.fromJson(notification.toJson());
    final capabilityError = _validateInputRequestsClientCapabilities(
      taskNotification.task.inputRequests,
      request,
    );
    if (capabilityError != null) {
      throw capabilityError;
    }
  }

  @override
  bool shouldSendOutgoingRequestScopedNotification(
    JsonRpcRequest request,
    JsonRpcNotification notification,
  ) {
    if (!_isStatelessRequest(request)) {
      return true;
    }
    if (_statelessHandlerForbiddenNotificationMethods.contains(
      notification.method,
    )) {
      final message = notification.method == Method.notificationsCancelled
          ? '${Method.notificationsCancelled} cannot be sent by request '
              'handlers in stateless MCP; subscription cancellation is '
              'managed by the protocol.'
          : '${notification.method} is not an allowed server notification '
              'from request handlers in stateless MCP.';
      throw McpError(
        ErrorCode.invalidRequest.value,
        message,
      );
    }
    if (_statelessSubscriptionOnlyNotificationMethods.contains(
      notification.method,
    )) {
      if (request is! JsonRpcSubscriptionsListenRequest) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          '${notification.method} can only be sent from a '
          '${Method.subscriptionsListen} handler in stateless MCP.',
        );
      }
      return true;
    }
    if (notification.method != Method.notificationsMessage) {
      return true;
    }
    if (_capabilities.logging == null) {
      return false;
    }
    final loggingNotification =
        notification is JsonRpcLoggingMessageNotification
            ? notification
            : JsonRpcLoggingMessageNotification.fromJson(notification.toJson());
    return _allowsStatelessLogging(
      loggingNotification.logParams.level,
      request.meta,
    );
  }

  @override
  void onIncomingRequestAccepted(JsonRpcRequest request) {
    if (request.method == Method.initialize) {
      _connectionMode = _ServerConnectionMode.legacy;
      _lifecycleState = _ServerLifecycleState.initializing;
    } else if (_connectionMode == _ServerConnectionMode.undecided &&
        _isStatelessRequest(request)) {
      _connectionMode = _ServerConnectionMode.stateless;
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
      writeServerProtocolVersion(this, null);
      _lifecycleState = _ServerLifecycleState.uninitialized;
    }
  }

  bool _requiresCacheableResult(String method) {
    return switch (method) {
      Method.serverDiscover ||
      Method.toolsList ||
      Method.promptsList ||
      Method.resourcesList ||
      Method.resourcesTemplatesList ||
      Method.resourcesRead =>
        true,
      _ => false,
    };
  }

  bool _isMrtrRetry(JsonRpcRequest request) {
    final params = request.params;
    return params?.containsKey('inputResponses') == true ||
        params?.containsKey('requestState') == true;
  }

  void _omitStatelessLegacyToolExecution(
    Map<String, dynamic> resultJson,
  ) {
    final tools = resultJson['tools'];
    if (tools is! List) {
      return;
    }
    resultJson['tools'] = [
      for (final tool in tools)
        if (tool is Map<String, dynamic>)
          Map<String, dynamic>.from(tool)..remove('execution')
        else
          tool,
    ];
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
    if (json['resultType'] == resultTypeComplete &&
        _requiresCacheableResult(request.method)) {
      if (_isMrtrRetry(request)) {
        // MRTR retry inputs are intentionally excluded from cache keys by the
        // protocol. Never propagate handler-provided reusable cache hints for
        // a result that depends on those inputs.
        json['ttlMs'] = 0;
        json['cacheScope'] = CacheScope.private;
      } else {
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
    }

    final handlerMeta = readOptionalJsonObject(result.meta, 'Result._meta');
    final serializedMeta =
        readOptionalJsonObject(json['_meta'], 'Result._meta');
    final resultMeta = <String, dynamic>{
      // Older custom results may expose metadata only through `meta`. Fall
      // back to it only when the serializer omitted `_meta`; explicit wire
      // metadata remains authoritative.
      ...?(json.containsKey('_meta') ? serializedMeta : handlerMeta),
    };
    final hasHandlerServerInfo =
        handlerMeta?.containsKey(McpMetaKey.serverInfo) == true;
    if (hasHandlerServerInfo || resultMeta.containsKey(McpMetaKey.serverInfo)) {
      final serverInfo = hasHandlerServerInfo
          ? handlerMeta![McpMetaKey.serverInfo]
          : resultMeta[McpMetaKey.serverInfo];
      if (serverInfo == null) {
        // An anonymous result omits the optional identity property. JSON null
        // is not a valid Implementation value.
        resultMeta.remove(McpMetaKey.serverInfo);
      } else {
        final serverInfoJson = readJsonObject(
          serverInfo,
          'Result._meta.${McpMetaKey.serverInfo}',
        );
        Implementation.fromJson(serverInfoJson);
        resultMeta[McpMetaKey.serverInfo] = serverInfoJson;
      }
    } else {
      resultMeta[McpMetaKey.serverInfo] = _serverInfo.toJson();
    }
    json['_meta'] = resultMeta;
    validateStatelessResultMetaObjects(request, json);

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
        _validateTaskExtensionToolResult(result, request, extra);
        _validateTaskExtensionInputRequests(result, request);
        if (request is JsonRpcCancelTaskRequest) {
          removeServerTaskOutputValidator(
            this,
            extra.sessionId,
            request.cancelParams.taskId,
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
        if (result is CreateTaskExtensionResult) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'Invalid ${request.method} result: CreateTaskExtensionResult is '
            'only supported by ${Method.toolsCall}.',
          );
        }
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

    final legacySupportedVersions = _supportedVersions
        .where((version) => !isStatelessProtocolVersion(version))
        .toList();
    final protocolVersion = legacySupportedVersions.contains(requestedVersion)
        ? requestedVersion
        : legacySupportedVersions.isNotEmpty
            ? legacySupportedVersions.first
            : defaultProtocolVersion;
    writeServerProtocolVersion(this, protocolVersion);

    return InitializeResult(
      protocolVersion: protocolVersion,
      capabilities: getCapabilities(),
      serverInfo: _serverInfo,
      instructions: _instructions,
    );
  }

  bool get _supportsLegacyInitialization {
    return _supportedVersions.any(
      (version) => !isStatelessProtocolVersion(version),
    );
  }

  bool get _supportsStatelessProtocol =>
      _supportedVersions.any(isStatelessProtocolVersion);

  ServerCapabilities _discoveryCapabilities() {
    final json = getCapabilities().toJson(omitLegacyTasks: true);
    return ServerCapabilities.fromDiscoveryJson(json);
  }

  /// Handles the client's `server/discover` request.
  Future<DiscoverResult> _onDiscover() async {
    return DiscoverResult(
      supportedVersions: _supportedVersions,
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
          "$method is not part of MCP 2025-11-25. Use ${Method.notificationsExperimentalCompletionsListChanged} for extension behavior.",
        );

      case Method.notificationsExperimentalCompletionsListChanged:
        if (_capabilities.completions == null) {
          throw StateError(
            "Server does not support completions capability (required for sending $method)",
          );
        }
        break;

      case Method.notificationsTasksStatus:
        final protocolVersion = readServerProtocolVersion(this);
        if (_capabilities.tasks == null ||
            protocolVersion == null ||
            isStatelessProtocolVersion(protocolVersion)) {
          throw StateError(
            'Server can send $method only in a negotiated legacy MCP session '
            "with the legacy 'tasks' capability.",
          );
        }
        break;

      case Method.notificationsTasks:
        if (!_supportsStatelessProtocol ||
            !_capabilities.supportsTasksExtension) {
          throw StateError(
            'Server does not support the stateless $mcpTasksExtensionId '
            'extension (required for sending $method)',
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

      case Method.notificationsSubscriptionsAcknowledged:
        if (!_supportsStatelessProtocol) {
          throw StateError(
            '$method is only available in MCP stateless protocol versions.',
          );
        }
        break;

      default:
        _logger.warn(
          "assertNotificationCapability called for unknown server-sent notification method: $method",
        );
    }
  }

  void _validateOutgoingNotification(JsonRpcNotification notification) {
    if (_usesStatelessNotificationSemantics(notification)) {
      validateStatelessNotificationMetaObjects(notification);
    }

    if (notification.method != Method.notificationsTasks) {
      return;
    }

    final taskNotification = notification is JsonRpcTaskNotification
        ? notification
        : JsonRpcTaskNotification.fromJson(notification.toJson());
    final task = taskNotification.task;
    if (task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled) {
      removeServerTaskOutputValidator(this, null, task.taskId);
      return;
    }
    if (task.status != TaskStatus.completed) {
      return;
    }

    final validator = readServerTaskOutputValidator(this, null, task.taskId);
    if (validator != null) {
      validator(task.result!);
      removeServerTaskOutputValidator(this, null, task.taskId);
    }
  }

  @override
  Future<void> notification(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    int? relatedRequestId,
  }) async {
    if (relatedRequestId == null &&
        !_hasLegacyServerInitiatedInteractionContext) {
      if (_statelessSubscriptionOnlyNotificationMethods.contains(
        notificationData.method,
      )) {
        throw StateError(
          '${notificationData.method} can only be emitted on an acknowledged '
          '${Method.subscriptionsListen} stream in stateless MCP.',
        );
      }
      if (_statelessHandlerForbiddenNotificationMethods.contains(
            notificationData.method,
          ) ||
          notificationData.method == Method.notificationsMessage ||
          notificationData.method == Method.notificationsProgress) {
        throw StateError(
          '${notificationData.method} cannot be emitted globally in stateless '
          'MCP; send request-scoped notifications through the originating '
          'RequestHandlerExtra.',
        );
      }
    }
    await super.notification(
      notificationData,
      relatedTask: relatedTask,
      relatedRequestId: relatedRequestId,
    );
  }

  @override
  void assertRequestHandlerCapability(String method) {
    switch (method) {
      case Method.serverDiscover:
      case Method.initialize:
      case Method.ping:
      case Method.completionComplete:
        break;

      case Method.subscriptionsListen:
        if (!_supportsStatelessProtocol) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without a stateless MCP protocol version",
          );
        }
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
        if (_capabilities.tasks == null) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without the legacy 'tasks' capability",
          );
        }
        break;

      case Method.tasksCancel:
      case Method.tasksGet:
        if (!(_capabilities.tasks != null ||
            (_supportsStatelessProtocol &&
                _capabilities.supportsTasksExtension))) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without the legacy "
            "'tasks' capability or a stateless MCP protocol version with the "
            "'$mcpTasksExtensionId' extension",
          );
        }
        break;

      case Method.tasksUpdate:
        if (!_supportsStatelessProtocol ||
            !_capabilities.supportsTasksExtension) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without a stateless MCP protocol version and '$mcpTasksExtensionId' extension",
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

  bool get _hasLegacyServerInitiatedInteractionContext {
    if (!_supportsStatelessProtocol) {
      return true;
    }
    final protocolVersion = readServerProtocolVersion(this);
    return protocolVersion != null &&
        !isStatelessProtocolVersion(protocolVersion);
  }

  void _assertLegacyServerInitiatedInteraction(String method) {
    if (_hasLegacyServerInitiatedInteractionContext) {
      return;
    }
    throw StateError(
      '$method is a legacy server-initiated interaction and is not supported '
      'by stateless MCP. Use stateless results and request-scoped '
      'notifications from the originating handler instead.',
    );
  }

  @override
  Future<T> request<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    int? relatedRequestId,
  ]) {
    _assertLegacyServerInitiatedInteraction(requestData.method);
    return super.request<T>(
      requestData,
      resultFactory,
      options,
      relatedRequestId,
    );
  }

  /// Sends a legacy-session `ping` request to the client.
  ///
  /// Stateless MCP does not permit server-to-client JSON-RPC requests.
  Future<EmptyResult> ping([RequestOptions? options]) {
    _assertLegacyServerInitiatedInteraction(Method.ping);
    return request<EmptyResult>(
      const JsonRpcPingRequest(id: -1),
      EmptyResult.fromJson,
      options,
    );
  }

  /// Sends a legacy-session `sampling/createMessage` request to the client.
  ///
  /// For stateless MCP, return an [InputRequiredResult] containing an embedded
  /// sampling input request from the originating handler.
  Future<CreateMessageResult> createMessage(
    CreateMessageRequest params, [
    RequestOptions? options,
  ]) {
    _assertLegacyServerInitiatedInteraction(Method.samplingCreateMessage);
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

    _validateSamplingToolMessages(params.messages);

    final req = JsonRpcCreateMessageRequest(id: -1, createParams: params);
    return request<CreateMessageResult>(
      req,
      (json) => CreateMessageResult.fromJson(json),
      options,
    );
  }

  void _validateSamplingToolMessages(List<SamplingMessage> messages) {
    // MCP 2026-07-28 Sampling, "Message Content Constraints": tool uses belong to
    // assistant turns and every one must be immediately resolved by a user
    // turn containing only matching tool results. Validate the full history,
    // not just its final pair.
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final content = message.contentBlocks;
      final toolUses = content.whereType<SamplingToolUseContent>().toList();
      final toolResults =
          content.whereType<SamplingToolResultContent>().toList();

      if (toolUses.isNotEmpty &&
          message.role != SamplingMessageRole.assistant) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'sampling message $index contains tool_use content but does not use '
          'the assistant role',
        );
      }

      if (toolResults.isNotEmpty) {
        if (message.role != SamplingMessageRole.user) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'sampling message $index contains tool_result content but does '
            'not use the user role',
          );
        }
        if (toolResults.length != content.length) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'sampling message $index must contain only tool_result content '
            'when any tool result is present',
          );
        }
      }

      if (toolUses.isEmpty) {
        if (toolResults.isNotEmpty &&
            (index == 0 ||
                !messages[index - 1]
                    .contentBlocks
                    .any((item) => item is SamplingToolUseContent))) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'sampling message $index contains tool_result content without '
            'tool_use content in the previous message',
          );
        }
        continue;
      }

      if (index + 1 >= messages.length) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'sampling message $index contains unresolved tool_use content',
        );
      }

      final resultMessage = messages[index + 1];
      final resultContent = resultMessage.contentBlocks;
      final matchingResults =
          resultContent.whereType<SamplingToolResultContent>().toList();
      if (resultMessage.role != SamplingMessageRole.user ||
          matchingResults.length != resultContent.length) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'sampling message $index with tool_use content must be followed by '
          'a user message containing only tool_result content',
        );
      }

      final toolUseIds = toolUses.map((item) => item.id).toList()..sort();
      final toolResultIds =
          matchingResults.map((item) => item.toolUseId).toList()..sort();
      var idsMatch = toolUseIds.length == toolResultIds.length;
      for (var idIndex = 0;
          idsMatch && idIndex < toolUseIds.length;
          idIndex++) {
        idsMatch = toolUseIds[idIndex] == toolResultIds[idIndex];
      }
      if (!idsMatch) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'sampling message $index tool_use IDs do not match the following '
          'tool_result IDs',
        );
      }
    }
  }

  /// Creates a legacy-session elicitation request for the given parameters.
  ///
  /// For stateless MCP, return an [InputRequiredResult] containing an embedded
  /// elicitation input request from the originating handler.
  Future<ElicitResult> elicitInput(
    ElicitRequest params, [
    RequestOptions? options,
  ]) async {
    _assertLegacyServerInitiatedInteraction(Method.elicitationCreate);
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
        if (!(_clientCapabilities?.elicitation?.supportsForm ?? false)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support form elicitation.",
          );
        }
        break;
    }

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

  /// Creates a legacy-session `notifications/elicitation/complete` callback.
  ///
  /// Stateless URL elicitation does not use this completion notification.
  Future<void> Function() createElicitationCompletionNotifier(
    String elicitationId,
  ) {
    _assertLegacyServerInitiatedInteraction(
      Method.notificationsElicitationComplete,
    );
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

  /// Sends a legacy-session `roots/list` request to the client.
  ///
  /// For stateless MCP, return an [InputRequiredResult] containing an embedded
  /// roots input request from the originating handler.
  Future<ListRootsResult> listRoots({RequestOptions? options}) {
    _assertLegacyServerInitiatedInteraction(Method.rootsList);
    final req = const JsonRpcListRootsRequest(id: -1);
    return request<ListRootsResult>(
      req,
      (json) => ListRootsResult.fromJson(json),
      options,
    );
  }

  /// Sends a legacy-session `notifications/message` notification.
  ///
  /// Global logging is suppressed for stateless MCP. Use
  /// [sendStatelessLoggingMessage] from the originating request handler so the
  /// request log-level opt-in and response-stream routing remain observable.
  Future<void> sendLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
  }) {
    if (!_allowsGlobalLegacyNotification(Method.notificationsMessage)) {
      return Future.value();
    }
    return _sendLoggingMessage(params, sessionId: sessionId);
  }

  /// Sends a request-scoped logging notification for stateless MCP.
  ///
  /// Pass [requestId] from [RequestHandlerExtra.requestId] when the transport
  /// has per-request response streams (notably Streamable HTTP). It remains
  /// optional for compatibility with shared-channel transports such as stdio.
  Future<void> sendStatelessLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
    required Map<String, dynamic>? requestMeta,
    RequestId? requestId,
  }) {
    return _sendLoggingMessage(
      params,
      sessionId: sessionId,
      requestMeta: requestMeta,
      requestId: requestId,
    );
  }

  Future<void> _sendLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
    Map<String, dynamic>? requestMeta,
    RequestId? requestId,
  }) async {
    if (_capabilities.logging != null) {
      final statelessLogContext = _isStatelessMeta(requestMeta);
      if (_allowsStatelessLogging(params.level, requestMeta) &&
          (statelessLogContext ||
              !_isMessageIgnored(params.level, sessionId))) {
        final notif = JsonRpcLoggingMessageNotification(logParams: params);
        if (statelessLogContext && requestId != null) {
          return notificationForRequest(notif, requestId: requestId);
        }
        if (statelessLogContext && transport is RequestIdAwareTransport) {
          throw ArgumentError.notNull('requestId');
        }
        return notification(notif);
      }
    }
  }

  bool _allowsGlobalLegacyNotification(String method) {
    if (_hasLegacyServerInitiatedInteractionContext) {
      return true;
    }
    final guidance = switch (method) {
      Method.notificationsMessage =>
        'Use sendStatelessLoggingMessage with the originating request '
            'metadata and ID instead.',
      Method.notificationsCompletionsListChanged =>
        'No stateless replacement is defined.',
      _ => 'Send it from a subscriptions/listen handler with '
          'RequestHandlerExtra.sendSubscriptionNotification instead.',
    };
    _logger.warn(
      '$method is not emitted globally for stateless MCP. $guidance',
    );
    return false;
  }

  /// Sends a legacy global `notifications/resources/updated` notification.
  ///
  /// Stateless MCP delivers this notification only through an acknowledged
  /// `subscriptions/listen` stream; global delivery is suppressed there.
  Future<void> sendResourceUpdated(ResourceUpdatedNotification params) {
    if (!_allowsGlobalLegacyNotification(
      Method.notificationsResourcesUpdated,
    )) {
      return Future.value();
    }
    final notif = JsonRpcResourceUpdatedNotification(updatedParams: params);
    return notification(notif);
  }

  /// Sends a legacy global `notifications/resources/list_changed` notification.
  Future<void> sendResourceListChanged() {
    if (!_allowsGlobalLegacyNotification(
      Method.notificationsResourcesListChanged,
    )) {
      return Future.value();
    }
    const notif = JsonRpcResourceListChangedNotification();
    return notification(notif);
  }

  /// Sends a legacy global `notifications/tools/list_changed` notification.
  Future<void> sendToolListChanged() {
    if (!_allowsGlobalLegacyNotification(
      Method.notificationsToolsListChanged,
    )) {
      return Future.value();
    }
    const notif = JsonRpcToolListChangedNotification();
    return notification(notif);
  }

  /// Sends a legacy global `notifications/prompts/list_changed` notification.
  Future<void> sendPromptListChanged() {
    if (!_allowsGlobalLegacyNotification(
      Method.notificationsPromptsListChanged,
    )) {
      return Future.value();
    }
    const notif = JsonRpcPromptListChangedNotification();
    return notification(notif);
  }

  /// Sends a legacy experimental completion list-changed notification.
  ///
  /// Stable MCP 2025-11-25 does not define a completion list-changed
  /// notification or capability flag.
  @Deprecated(
    'Stable MCP 2025-11-25 does not define completion list-changed notifications.',
  )
  Future<void> sendCompletionListChanged() {
    if (!_allowsGlobalLegacyNotification(
      Method.notificationsCompletionsListChanged,
    )) {
      return Future.value();
    }
    const notif = JsonRpcCompletionListChangedNotification();
    return notification(notif);
  }
}
