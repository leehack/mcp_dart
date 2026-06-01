import 'dart:async';

import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/mcp_header_validation.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.client");

/// Options for configuring the MCP [McpClient].
class McpClientOptions extends ProtocolOptions {
  /// Capabilities to advertise as being supported by this client.
  final ClientCapabilities? capabilities;

  /// Preferred protocol version for `server/discover` negotiation.
  final String protocolVersion;

  /// Whether [McpClient.connect] should probe with `server/discover` first.
  final bool useServerDiscover;

  /// Whether a failed `server/discover` probe should fall back to the legacy
  /// `initialize` handshake when the peer looks like a pre-discovery server.
  final bool allowLegacyInitializationFallback;

  const McpClientOptions({
    super.enforceStrictCapabilities,
    this.capabilities,
    this.protocolVersion = latestDraftProtocolVersion,
    this.useServerDiscover = true,
    this.allowLegacyInitializationFallback = true,
  });
}

/// Deprecated alias for [McpClientOptions].
@Deprecated('Use McpClientOptions instead')
typedef ClientOptions = McpClientOptions;

/// Handle for an active `subscriptions/listen` stream opened by [McpClient].
class McpSubscription {
  final void Function([Object? reason]) _cancel;

  /// JSON-RPC request ID that identifies this subscription stream.
  final int id;

  /// Acknowledgment sent as the first message on the subscription stream.
  final Future<SubscriptionsAcknowledgedNotification> acknowledged;

  /// Notifications delivered on this subscription stream after acknowledgment.
  final Stream<JsonRpcNotification> notifications;

  /// Completes when the `subscriptions/listen` request ends.
  final Future<EmptyResult> done;

  McpSubscription._({
    required this.id,
    required this.acknowledged,
    required this.notifications,
    required this.done,
    required void Function([Object? reason]) cancel,
  }) : _cancel = cancel;

  /// Cancels this subscription stream.
  void cancel([Object? reason]) {
    _cancel(reason);
  }
}

// Recursively applies default values from a JSON Schema to a data object.
void _applyElicitationDefaults(JsonSchema schema, Map<String, dynamic> data) {
  if (schema is! JsonObject) return;

  final properties = schema.properties;
  if (properties != null) {
    for (final entry in properties.entries) {
      final key = entry.key;
      final propSchema = entry.value;

      // Apply default if data doesn't have the key and schema has a default
      if (!data.containsKey(key) && propSchema.defaultValue != null) {
        data[key] = _deepCopy(propSchema.defaultValue);
      }

      // Recurse into existing nested objects (but not arrays)
      if (data[key] is Map) {
        _applyElicitationDefaults(
          propSchema,
          data[key] as Map<String, dynamic>,
        );
      }
    }
  }
}

dynamic _deepCopy(dynamic value) {
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, val) => MapEntry(key.toString(), _deepCopy(val)),
    );
  } else if (value is List) {
    return value.map((val) => _deepCopy(val)).toList();
  } else {
    return value;
  }
}

const Set<String> _statelessRemovedRequestMethods = {
  Method.initialize,
  Method.ping,
  Method.loggingSetLevel,
  Method.resourcesSubscribe,
  Method.resourcesUnsubscribe,
  Method.tasksList,
  Method.tasksResult,
};

const Set<String> _statelessRemovedNotificationMethods = {
  Method.notificationsInitialized,
  Method.notificationsRootsListChanged,
  Method.notificationsTasksStatus,
};

/// An MCP client implementation built on top of a pluggable [Transport].
///
/// Handles the initialization handshake with the server upon connection
/// and provides methods for making standard MCP requests.
class McpClient extends Protocol {
  ServerCapabilities? _serverCapabilities;
  Implementation? _serverVersion;
  ClientCapabilities _capabilities;
  final Implementation _clientInfo;
  final String _preferredProtocolVersion;
  final bool _useServerDiscover;
  final bool _allowLegacyInitializationFallback;
  String? _instructions;
  Future<void>? _sessionRefresh;
  String? _negotiatedProtocolVersion;
  bool _usesStatelessProtocol = false;
  bool _sentInitialized = false;

  final Map<String, JsonSchema> _cachedToolOutputSchemas = {};
  final Set<String> _cachedRequiredTaskTools = {};
  final ToolParameterHeaderMappings _cachedToolParameterHeaders = {};
  final Map<Object, _ClientSubscriptionState> _activeSubscriptions = {};

  /// Callback for handling elicitation requests from the server.
  ///
  /// This will be called when the server sends an `elicitation/create` request
  /// to collect structured user input. The client should prompt the user
  /// and return an [ElicitResult] with the action taken and content provided.
  Future<ElicitResult> Function(ElicitRequest)? onElicitRequest;

  /// Callback for handling task status notifications from the server.
  FutureOr<void> Function(TaskStatusNotification params)? onTaskStatus;

  /// Callback for handling sampling requests from the server.
  ///
  /// This will be called when the server sends a `sampling/createMessage` request
  /// to request an LLM completion from the client.
  Future<CreateMessageResult> Function(CreateMessageRequest params)?
      onSamplingRequest;

  /// Initializes this client with its implementation details and options.
  ///
  /// - [_clientInfo]: Information about this client's name and version.
  /// - [options]: Optional configuration settings including client capabilities.
  McpClient(this._clientInfo, {McpClientOptions? options})
      : _capabilities = options?.capabilities ?? const ClientCapabilities(),
        _preferredProtocolVersion =
            options?.protocolVersion ?? latestDraftProtocolVersion,
        _useServerDiscover = options?.useServerDiscover ?? true,
        _allowLegacyInitializationFallback =
            options?.allowLegacyInitializationFallback ?? true,
        super(options) {
    // Register elicit handler if any elicitation mode is advertised.
    if (_capabilities.elicitation != null) {
      setRequestHandler<JsonRpcElicitRequest>(
        Method.elicitationCreate,
        (request, extra) async {
          if (request.elicitParams.isUrlMode &&
              _capabilities.elicitation?.url == null) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Client does not support URL elicitation.",
            );
          }
          if (request.elicitParams.isFormMode &&
              _capabilities.elicitation?.form == null) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Client does not support form elicitation.",
            );
          }
          if (onElicitRequest == null) {
            throw McpError(
              ErrorCode.methodNotFound.value,
              "No elicit handler registered",
            );
          }
          final result = await onElicitRequest!(request.elicitParams);

          // Apply defaults if client supports it and it's a form elicitation
          if (request.elicitParams.isFormMode &&
              result.action == 'accept' &&
              result.content is Map &&
              request.elicitParams.requestedSchema != null &&
              _capabilities.elicitation?.form?.applyDefaults == true) {
            _applyElicitationDefaults(
              request.elicitParams.requestedSchema!,
              result.content!,
            );
          }
          return result;
        },
        (id, params, meta) {
          final protocolVersion = _protocolVersionForIncomingRequest(meta);
          return JsonRpcElicitRequest(
            id: id,
            elicitParams: ElicitRequest.fromJson(
              params ?? {},
              protocolVersion: protocolVersion,
            ),
            meta: meta,
            protocolVersion: protocolVersion,
          );
        },
      );
    }

    // Register task status notification handler
    if (_capabilities.tasks != null) {
      setNotificationHandler<JsonRpcTaskStatusNotification>(
        Method.notificationsTasksStatus,
        (notification) async {
          await onTaskStatus?.call(notification.statusParams);
        },
        (params, meta) => JsonRpcTaskStatusNotification(
          statusParams: TaskStatusNotification.fromJson(params ?? {}),
          meta: meta,
        ),
      );
    }

    // Register sampling request handler if capability is present
    if (_capabilities.sampling != null) {
      setRequestHandler<JsonRpcCreateMessageRequest>(
        Method.samplingCreateMessage,
        (request, extra) async {
          if (onSamplingRequest == null) {
            throw McpError(
              ErrorCode.methodNotFound.value,
              "No sampling handler registered",
            );
          }
          if ((request.createParams.tools != null ||
                  request.createParams.toolChoice != null) &&
              _capabilities.sampling?.tools != true) {
            throw McpError(
              ErrorCode.invalidRequest.value,
              "Client does not support 'sampling.tools' capability required by sampling/createMessage request.",
            );
          }
          return await onSamplingRequest!(request.createParams);
        },
        (id, params, meta) => JsonRpcCreateMessageRequest(
          id: id,
          createParams: CreateMessageRequest.fromJson(params ?? {}),
          meta: meta,
        ),
      );
    }
  }

  /// Registers new capabilities for this client.
  ///
  /// This can only be called before connecting to a transport.
  /// Throws [StateError] if called after connecting.
  void registerCapabilities(ClientCapabilities capabilities) {
    if (transport != null) {
      throw StateError(
        "Cannot register capabilities after connecting to transport",
      );
    }
    _capabilities = ClientCapabilities.fromJson(
      mergeCapabilities(_capabilities.toJson(), capabilities.toJson()),
    );
  }

  Future<void> _initializeSession(Transport transport) async {
    _sentInitialized = false;
    _usesStatelessProtocol = false;

    final initParams = InitializeRequest(
      protocolVersion: latestProtocolVersion,
      capabilities: _capabilities,
      clientInfo: _clientInfo,
    );

    final initRequest = JsonRpcInitializeRequest(
      id: -1,
      initParams: initParams,
    );

    final InitializeResult result = await request<InitializeResult>(
      initRequest,
      (json) => InitializeResult.fromJson(json),
    );

    if (!supportedProtocolVersions.contains(result.protocolVersion)) {
      throw McpError(
        ErrorCode.internalError.value,
        "Server's chosen protocol version is not supported by client: ${result.protocolVersion}. Supported: $supportedProtocolVersions",
      );
    }

    _serverCapabilities = result.capabilities;
    _serverVersion = result.serverInfo;
    _instructions = result.instructions;
    _negotiatedProtocolVersion = result.protocolVersion;

    if (transport is ProtocolVersionAwareTransport) {
      (transport as ProtocolVersionAwareTransport).protocolVersion =
          result.protocolVersion;
    }

    const initializedNotification = JsonRpcInitializedNotification();
    try {
      await notification(initializedNotification);
      _sentInitialized = true;
    } catch (_) {
      _sentInitialized = false;
      rethrow;
    }

    _logger.debug(
      "MCP Client Initialized. Server: ${result.serverInfo.name} ${result.serverInfo.version}, Protocol: ${result.protocolVersion}",
    );
  }

  Map<String, dynamic> _statelessRequestMeta(Map<String, dynamic>? meta) {
    return buildProtocolRequestMeta(
      protocolVersion: _negotiatedProtocolVersion ?? _preferredProtocolVersion,
      clientInfo: _clientInfo,
      clientCapabilities: _capabilities,
      meta: meta,
    );
  }

  String? _retryableDiscoveryProtocolVersion(
    McpError error,
    String attemptedVersion,
  ) {
    if (error.code != ErrorCode.unsupportedProtocolVersion.value) {
      return null;
    }

    final data = error.data;
    if (data is! Map) {
      return null;
    }

    final supported = data['supported'];
    if (supported is! Iterable) {
      return null;
    }

    final advertisedVersions = <String>[];
    for (final version in supported) {
      if (version is String) {
        advertisedVersions.add(version);
      }
    }

    final retryVersion = negotiateProtocolVersion(
      advertisedVersions,
      localSupportedVersions: statelessProtocolVersions,
    );
    if (retryVersion == null || retryVersion == attemptedVersion) {
      return null;
    }
    return retryVersion;
  }

  Future<DiscoverResult> _discoverServerWithVersion(
    String protocolVersion,
  ) async {
    final activeTransport = transport;
    final ProtocolVersionAwareTransport? versionedTransport =
        activeTransport is ProtocolVersionAwareTransport
            ? activeTransport as ProtocolVersionAwareTransport
            : null;
    versionedTransport?.protocolVersion = protocolVersion;

    final result = await super.request<DiscoverResult>(
      JsonRpcServerDiscoverRequest(
        id: -1,
        meta: buildProtocolRequestMeta(
          protocolVersion: protocolVersion,
          clientInfo: _clientInfo,
          clientCapabilities: _capabilities,
        ),
      ),
      (json) => DiscoverResult.fromJson(json),
    );

    final negotiatedProtocolVersion = negotiateProtocolVersion(
      result.supportedVersions,
      localSupportedVersions: supportedProtocolVersionsWithDraft,
    );
    if (negotiatedProtocolVersion == null) {
      throw McpError(
        ErrorCode.unsupportedProtocolVersion.value,
        "Server does not support a compatible MCP protocol version.",
        {
          'supported': result.supportedVersions,
          'requested': protocolVersion,
        },
      );
    }

    _serverCapabilities = result.capabilities;
    _serverVersion = result.serverInfo;
    _instructions = result.instructions;
    _negotiatedProtocolVersion = negotiatedProtocolVersion;
    _usesStatelessProtocol = isStatelessProtocolVersion(
      negotiatedProtocolVersion,
    );
    _sentInitialized = true;

    versionedTransport?.protocolVersion = negotiatedProtocolVersion;

    _logger.debug(
      "MCP Server Discovered. Server: ${result.serverInfo.name} ${result.serverInfo.version}, Protocol: $negotiatedProtocolVersion",
    );

    return result;
  }

  Future<DiscoverResult> discoverServer() async {
    try {
      return await _discoverServerWithVersion(_preferredProtocolVersion);
    } catch (error) {
      if (error is! McpError) {
        rethrow;
      }

      final retryVersion = _retryableDiscoveryProtocolVersion(
        error,
        _preferredProtocolVersion,
      );
      if (retryVersion == null) {
        rethrow;
      }

      _logger.debug(
        "server/discover rejected protocol $_preferredProtocolVersion; "
        "retrying with $retryVersion.",
      );
      return await _discoverServerWithVersion(retryVersion);
    }
  }

  /// Connects to the server using the given [transport].
  ///
  /// Initiates the MCP initialization handshake and processes the result.
  @override
  Future<void> connect(Transport transport) async {
    await super.connect(transport);

    try {
      if (_useServerDiscover) {
        try {
          await discoverServer();
          return;
        } catch (error) {
          if (!_isLegacyDiscoveryFallbackError(error)) {
            rethrow;
          }
          _logger.debug(
            "server/discover not available; falling back to initialize.",
          );
          if (transport is ProtocolVersionAwareTransport) {
            (transport as ProtocolVersionAwareTransport).protocolVersion = null;
          }
        }
      }

      await _initializeSession(transport);
    } catch (error) {
      _logger.error("MCP Client Initialization Failed: $error");
      await close();
      rethrow;
    }
  }

  bool _isLegacyDiscoveryFallbackError(Object error) {
    if (!_allowLegacyInitializationFallback || error is! McpError) {
      return false;
    }
    if (error.code == ErrorCode.methodNotFound.value) {
      return true;
    }

    final message = error.message;
    if (error.code == 0 &&
        message.contains('Error POSTing to endpoint (HTTP 400)')) {
      return true;
    }

    return (error.code == 0 ||
            error.code == ErrorCode.connectionClosed.value ||
            error.code == ErrorCode.invalidRequest.value) &&
        message.contains('Server not initialized');
  }

  @override
  Future<T> request<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    RequestId? relatedRequestId,
  ]) async {
    _assertStatelessRequestAllowed(requestData.method);

    final outboundRequest =
        _usesStatelessProtocol && requestData.method != Method.serverDiscover
            ? JsonRpcRequest(
                id: requestData.id,
                method: requestData.method,
                params: requestData.params,
                meta: _statelessRequestMeta(requestData.meta),
              )
            : requestData;

    try {
      return await super.request<T>(
        outboundRequest,
        resultFactory,
        options,
        relatedRequestId,
      );
    } catch (error) {
      if (error is! StaleSessionError ||
          outboundRequest.method == 'initialize') {
        rethrow;
      }

      final activeTransport = transport;
      if (activeTransport == null) {
        rethrow;
      }

      final rejectedSessionId = error.sessionId;
      final currentSessionId = activeTransport.sessionId;
      final refreshAlreadyInProgress = _sessionRefresh;
      if (refreshAlreadyInProgress != null) {
        await refreshAlreadyInProgress;
      } else if (rejectedSessionId == null ||
          currentSessionId == null ||
          currentSessionId == rejectedSessionId) {
        final refresh = _initializeSession(activeTransport);
        _sessionRefresh = refresh;
        try {
          await refresh;
        } finally {
          if (identical(_sessionRefresh, refresh)) {
            _sessionRefresh = null;
          }
        }
      }

      return await super.request<T>(
        outboundRequest,
        resultFactory,
        options,
        relatedRequestId,
      );
    }
  }

  @override
  Future<void> notification(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    RequestId? relatedRequestId,
  }) async {
    _assertStatelessNotificationAllowed(notificationData.method);
    await super.notification(
      notificationData,
      relatedTask: relatedTask,
      relatedRequestId: relatedRequestId,
    );
  }

  void _assertStatelessRequestAllowed(String method) {
    if (!_usesStatelessProtocol ||
        !_statelessRemovedRequestMethods.contains(method)) {
      return;
    }

    throw McpError(
      ErrorCode.methodNotFound.value,
      'MCP $_negotiatedProtocolVersion does not define $method.',
    );
  }

  void _assertStatelessNotificationAllowed(String method) {
    if (!_usesStatelessProtocol ||
        !_statelessRemovedNotificationMethods.contains(method)) {
      return;
    }

    throw McpError(
      ErrorCode.methodNotFound.value,
      'MCP $_negotiatedProtocolVersion does not define $method.',
    );
  }

  /// Gets the server's reported capabilities after successful initialization.
  ServerCapabilities? getServerCapabilities() => _serverCapabilities;

  /// Gets the server's reported implementation info after successful initialization.
  Implementation? getServerVersion() => _serverVersion;

  /// Gets the server's instructions provided during initialization, if any.
  String? getInstructions() => _instructions;

  /// Gets the negotiated protocol version after connection.
  String? getProtocolVersion() => _negotiatedProtocolVersion;

  String? _protocolVersionForIncomingRequest(Map<String, dynamic>? meta) {
    final protocolVersion = meta?[McpMetaKey.protocolVersion];
    if (protocolVersion is String) {
      return protocolVersion;
    }
    return _negotiatedProtocolVersion ?? _preferredProtocolVersion;
  }

  @override
  bool isRecognizedResultType(String resultType) {
    if (super.isRecognizedResultType(resultType)) {
      return true;
    }

    return resultType == resultTypeTask &&
        (_serverCapabilities?.supportsTasksExtension ?? false);
  }

  @override
  McpError? validateIncomingRequest(JsonRpcRequest request) {
    if (_usesStatelessProtocol) {
      return McpError(
        ErrorCode.invalidRequest.value,
        'Server-initiated JSON-RPC requests are not supported in stateless '
        'MCP; return input_required with inputRequests instead.',
      );
    }

    if (_sentInitialized || request.method == Method.ping) {
      return null;
    }

    return McpError(
      ErrorCode.invalidRequest.value,
      "Received ${request.method} before notifications/initialized was sent.",
    );
  }

  @override
  McpError? validateIncomingNotification(JsonRpcNotification notification) {
    if (_sentInitialized) {
      return null;
    }

    switch (notification.method) {
      case Method.notificationsMessage:
      case Method.notificationsCancelled:
      case Method.notificationsProgress:
        return null;
      default:
        return McpError(
          ErrorCode.invalidRequest.value,
          "Received ${notification.method} before notifications/initialized was sent.",
        );
    }
  }

  @override
  void onIncomingNotificationAccepted(JsonRpcNotification notification) {
    final subscriptionId = notification.meta?[McpMetaKey.subscriptionId];
    if (subscriptionId is! int && subscriptionId is! String) {
      return;
    }

    final activeSubscription = _activeSubscriptions[subscriptionId];
    activeSubscription?.handleNotification(notification);
  }

  @override
  void onConnectionClosed() {
    final subscriptions = List<_ClientSubscriptionState>.from(
      _activeSubscriptions.values,
    );
    _activeSubscriptions.clear();
    for (final subscription in subscriptions) {
      subscription.fail(
        McpError(ErrorCode.connectionClosed.value, 'Connection closed'),
        StackTrace.current,
      );
    }
  }

  @override
  void assertCapabilityForMethod(String method) {
    final serverCaps = _serverCapabilities;
    if (serverCaps == null) {
      throw StateError(
        "Cannot check server capabilities before initialization is complete.",
      );
    }

    bool supported = true;
    String? requiredCapability;

    switch (method) {
      case Method.loggingSetLevel:
        supported = serverCaps.logging != null;
        requiredCapability = 'logging';
        break;
      case Method.promptsGet:
      case Method.promptsList:
        supported = serverCaps.prompts != null;
        requiredCapability = 'prompts';
        break;
      case Method.resourcesList:
      case Method.resourcesTemplatesList:
      case Method.resourcesRead:
        supported = serverCaps.resources != null;
        requiredCapability = 'resources';
        break;
      case Method.resourcesSubscribe:
      case Method.resourcesUnsubscribe:
        supported = serverCaps.resources?.subscribe ?? false;
        requiredCapability = 'resources.subscribe';
        break;
      case Method.subscriptionsListen:
        supported = true;
        break;
      case Method.toolsCall:
      case Method.toolsList:
        supported = serverCaps.tools != null;
        requiredCapability = 'tools';
        break;
      case Method.tasksGet:
      case Method.tasksCancel:
        supported =
            serverCaps.tasks != null || serverCaps.supportsTasksExtension;
        requiredCapability = 'tasks or $mcpTasksExtensionId';
        break;
      case Method.tasksUpdate:
        supported = serverCaps.supportsTasksExtension;
        requiredCapability = mcpTasksExtensionId;
        break;
      case Method.tasksList:
      case Method.tasksResult:
        supported = serverCaps.tasks != null;
        requiredCapability = 'tasks';
        break;
      case Method.completionComplete:
        supported = serverCaps.completions != null;
        requiredCapability = 'completions';
        break;
      default:
        _logger.warn(
          "assertCapabilityForMethod called for potentially custom client request: $method",
        );
        supported = true;
    }

    if (!supported) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        "Server does not support capability '$requiredCapability' required for method '$method'",
      );
    }
  }

  @override
  void assertNotificationCapability(String method) {
    switch (method) {
      case Method.notificationsRootsListChanged:
        if (!(_capabilities.roots?.listChanged ?? false)) {
          throw StateError(
            "Client does not support 'roots.listChanged' capability (required for sending $method)",
          );
        }
        break;
      default:
        _logger.warn(
          "assertNotificationCapability called for potentially custom client notification: $method",
        );
    }
  }

  @override
  void assertRequestHandlerCapability(String method) {
    switch (method) {
      case Method.samplingCreateMessage:
        if (!(_capabilities.sampling != null)) {
          throw StateError(
            "Client setup error: Cannot handle '$method' without 'sampling' capability registered.",
          );
        }
        break;
      case Method.rootsList:
        if (!(_capabilities.roots != null)) {
          throw StateError(
            "Client setup error: Cannot handle '$method' without 'roots' capability registered.",
          );
        }
        break;
      case Method.elicitationCreate:
        if (!(_capabilities.elicitation != null)) {
          throw StateError(
            "Client setup error: Cannot handle '$method' without 'elicitation' capability registered.",
          );
        }
        break;
      default:
        _logger.info(
          "Setting request handler for potentially custom method '$method'. Ensure client capabilities match.",
        );
    }
  }

  @override
  void assertTaskCapability(String method) {
    final missingCapability = switch (method) {
      Method.toolsCall =>
        _serverCapabilities?.tasks?.requests?.tools?.call == null
            ? 'tasks.requests.tools.call'
            : null,
      _ =>
        _serverCapabilities?.tasks == null ? 'tasks' : 'tasks.requests.$method',
    };

    if (missingCapability != null) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        "Server does not support capability '$missingCapability' required for task-based '$method'",
      );
    }
  }

  @override
  void assertTaskHandlerCapability(String method) {
    final missingCapability = switch (method) {
      Method.samplingCreateMessage =>
        _capabilities.tasks?.requests?.sampling?.createMessage == null
            ? 'tasks.requests.sampling.createMessage'
            : null,
      Method.elicitationCreate =>
        _capabilities.tasks?.requests?.elicitation?.create == null
            ? 'tasks.requests.elicitation.create'
            : null,
      _ => _capabilities.tasks == null ? 'tasks' : 'tasks.requests.$method',
    };

    if (missingCapability != null) {
      throw StateError(
        "Client setup error: Cannot handle task-based '$method' without '$missingCapability' capability registered.",
      );
    }
  }

  /// Sends a `ping` request to the server and awaits an empty response.
  Future<EmptyResult> ping([RequestOptions? options]) {
    return request<EmptyResult>(
      const JsonRpcPingRequest(id: -1),
      (json) => const EmptyResult(),
      options,
    );
  }

  /// Sends a `completion/complete` request to the server for argument completion.
  Future<CompleteResult> complete(
    CompleteRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcCompleteRequest(id: -1, completeParams: params);
    return request<CompleteResult>(
      req,
      (json) => CompleteResult.fromJson(json),
      options,
    );
  }

  /// Sends a `logging/setLevel` request to the server.
  Future<EmptyResult> setLoggingLevel(
    LoggingLevel level, [
    RequestOptions? options,
  ]) {
    final params = SetLevelRequest(level: level);
    final req = JsonRpcSetLevelRequest(id: -1, setParams: params);
    return request<EmptyResult>(req, (json) => const EmptyResult(), options);
  }

  /// Sends a `prompts/get` request to retrieve a specific prompt/template.
  Future<GetPromptResult> getPrompt(
    GetPromptRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcGetPromptRequest(id: -1, getParams: params);
    return request<GetPromptResult>(
      req,
      (json) => GetPromptResult.fromJson(json),
      options,
    );
  }

  /// Sends a `prompts/list` request to list available prompts/templates.
  Future<ListPromptsResult> listPrompts({
    ListPromptsRequest? params,
    RequestOptions? options,
  }) {
    final req = JsonRpcListPromptsRequest(id: -1, params: params);
    return request<ListPromptsResult>(
      req,
      (json) => ListPromptsResult.fromJson(json),
      options,
    );
  }

  /// Sends a `resources/list` request to list available resources.
  Future<ListResourcesResult> listResources({
    ListResourcesRequest? params,
    RequestOptions? options,
  }) {
    final req = JsonRpcListResourcesRequest(id: -1, params: params);
    return request<ListResourcesResult>(
      req,
      (json) => ListResourcesResult.fromJson(json),
      options,
    );
  }

  /// Sends a `resources/templates/list` request to list available resource templates.
  Future<ListResourceTemplatesResult> listResourceTemplates({
    ListResourceTemplatesRequest? params,
    RequestOptions? options,
  }) {
    final req = JsonRpcListResourceTemplatesRequest(id: -1, params: params);
    return request<ListResourceTemplatesResult>(
      req,
      (json) => ListResourceTemplatesResult.fromJson(json),
      options,
    );
  }

  /// Sends a `resources/read` request to read the content of a resource.
  Future<ReadResourceResult> readResource(
    ReadResourceRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcReadResourceRequest(id: -1, readParams: params);
    return request<ReadResourceResult>(
      req,
      (json) => ReadResourceResult.fromJson(json),
      options,
    );
  }

  /// Sends a `resources/subscribe` request to subscribe to updates for a resource.
  Future<EmptyResult> subscribeResource(
    SubscribeRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcSubscribeRequest(id: -1, subParams: params);
    return request<EmptyResult>(req, (json) => const EmptyResult(), options);
  }

  /// Sends a `resources/unsubscribe` request to cancel a resource subscription.
  Future<EmptyResult> unsubscribeResource(
    UnsubscribeRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcUnsubscribeRequest(id: -1, unsubParams: params);
    return request<EmptyResult>(req, (json) => const EmptyResult(), options);
  }

  /// Opens a `subscriptions/listen` stream and demultiplexes notifications.
  McpSubscription listenSubscriptions(SubscriptionsListenRequest params) {
    if (transport == null) {
      throw StateError('Not connected to a transport.');
    }

    final requestId = reserveRequestId();
    final abortController = BasicAbortController();
    final state = _ClientSubscriptionState(
      id: requestId,
      requestedNotifications: params.notifications,
      abortController: abortController,
      onClose: () => _activeSubscriptions.remove(requestId),
    );
    _activeSubscriptions[requestId] = state;

    final requestData = JsonRpcSubscriptionsListenRequest(
      id: requestId,
      listenParams: params,
      meta: _usesStatelessProtocol ? _statelessRequestMeta(null) : null,
    );
    final requestDone = super.requestWithReservedId<EmptyResult>(
      requestId,
      requestData,
      (json) => const EmptyResult(),
      RequestOptions(
        signal: abortController.signal,
        timeoutEnabled: false,
      ),
    );
    state.trackRequest(requestDone);

    return McpSubscription._(
      id: requestId,
      acknowledged: state.acknowledged,
      notifications: state.notifications,
      done: state.done,
      cancel: state.cancel,
    );
  }

  /// Sends a `tools/call` request to invoke a tool on the server.
  Future<CallToolResult> callTool(
    CallToolRequest params, {
    RequestOptions? options,
  }) async {
    if (_cachedRequiredTaskTools.contains(params.name)) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        'Tool "${params.name}" requires task-based execution.',
      );
    }

    final req = JsonRpcCallToolRequest(id: -1, params: params.toJson());
    final result = await request<CallToolResult>(
      req,
      (json) => CallToolResult.fromJson(json),
      options,
    );

    final outputSchema = _cachedToolOutputSchemas[params.name];
    if (outputSchema != null && !result.isError) {
      try {
        outputSchema.validate(result.structuredContent);
      } catch (e) {
        throw McpError(
          ErrorCode.invalidParams.value,
          "Structured content does not match the tool's output schema: $e",
        );
      }
    }

    return result;
  }

  /// Sends a `tools/list` request to list available tools on the server.
  Future<ListToolsResult> listTools({
    ListToolsRequest? params,
    RequestOptions? options,
  }) async {
    final req = JsonRpcListToolsRequest(id: -1, params: params?.toJson());
    final result = await request<ListToolsResult>(
      req,
      (json) => ListToolsResult.fromJson(json),
      options,
    );

    final tools = _cacheToolMetadata(result.tools);

    if (identical(tools, result.tools)) {
      return result;
    }

    return ListToolsResult(
      tools: tools,
      nextCursor: result.nextCursor,
      meta: result.meta,
    );
  }

  List<Tool> _cacheToolMetadata(List<Tool> tools) {
    _cachedToolOutputSchemas.clear();
    _cachedRequiredTaskTools.clear();
    _cachedToolParameterHeaders.clear();

    var filtered = false;
    final validTools = <Tool>[];

    for (final tool in tools) {
      final headerValidation = _validateToolParameterHeaders(tool);
      if (headerValidation.rejectionReason != null) {
        filtered = true;
        _logger.warn(
          'Rejecting tool "${tool.name}" from tools/list: '
          '${headerValidation.rejectionReason}',
        );
        continue;
      }

      validTools.add(tool);

      if (tool.outputSchema != null) {
        _cachedToolOutputSchemas[tool.name] = tool.outputSchema!;
      }

      if (tool.execution?.taskSupport == 'required') {
        _cachedRequiredTaskTools.add(tool.name);
      }

      if (headerValidation.mappings.isNotEmpty) {
        _cachedToolParameterHeaders[tool.name] = headerValidation.mappings;
      }
    }

    final activeTransport = transport;
    final headerAwareTransport =
        activeTransport is ToolParameterHeaderAwareTransport
            ? activeTransport as ToolParameterHeaderAwareTransport
            : null;
    if (headerAwareTransport != null) {
      headerAwareTransport.setToolParameterHeaderMappings(
        _cachedToolParameterHeaders,
      );
    }

    return filtered ? validTools : tools;
  }

  _ToolParameterHeaderValidation _validateToolParameterHeaders(Tool tool) {
    final inputSchema = tool.inputSchema;
    final properties =
        inputSchema is JsonObject ? inputSchema.properties : null;
    if (properties == null || properties.isEmpty) {
      return const _ToolParameterHeaderValidation.valid({});
    }

    final mappings = <String, String>{};
    final seenHeaders = <String>{};
    final rejectionReason = _collectToolParameterHeaderMappings(
      properties: properties,
      path: const [],
      mappings: mappings,
      seenHeaders: seenHeaders,
    );

    if (rejectionReason != null) {
      return _ToolParameterHeaderValidation.invalid(rejectionReason);
    }

    return _ToolParameterHeaderValidation.valid(mappings);
  }

  String? _collectToolParameterHeaderMappings({
    required Map<String, JsonSchema> properties,
    required List<String> path,
    required Map<String, String> mappings,
    required Set<String> seenHeaders,
  }) {
    for (final entry in properties.entries) {
      final parameterPath = [...path, entry.key];
      final parameterName = _toolParameterHeaderParameterName(parameterPath);
      final propertyJson = entry.value.toJson();
      if (!propertyJson.containsKey('x-mcp-header')) {
        if (entry.value is JsonObject) {
          final childProperties = (entry.value as JsonObject).properties;
          if (childProperties != null && childProperties.isNotEmpty) {
            final rejectionReason = _collectToolParameterHeaderMappings(
              properties: childProperties,
              path: parameterPath,
              mappings: mappings,
              seenHeaders: seenHeaders,
            );
            if (rejectionReason != null) {
              return rejectionReason;
            }
          }
        }
        continue;
      }

      final rawHeader = propertyJson['x-mcp-header'];
      if (rawHeader is! String) {
        return 'parameter "$parameterName" has a non-string x-mcp-header value';
      }

      if (rawHeader.isEmpty) {
        return 'parameter "$parameterName" has an empty x-mcp-header value';
      }

      if (!_isValidMcpHeaderNameSuffix(rawHeader)) {
        return 'parameter "$parameterName" has invalid x-mcp-header value '
            '"$rawHeader"';
      }

      final normalizedHeader = rawHeader.toLowerCase();
      if (!seenHeaders.add(normalizedHeader)) {
        return 'x-mcp-header value "$rawHeader" is not unique';
      }

      if (!_isToolParameterHeaderPrimitive(entry.value)) {
        return 'parameter "$parameterName" uses x-mcp-header on a schema that '
            'is not string, integer, or boolean';
      }

      mappings[_toolParameterHeaderSelector(parameterPath)] = rawHeader;
    }

    return null;
  }

  String _toolParameterHeaderSelector(List<String> path) {
    if (path.length == 1) {
      return path.single;
    }

    return '/${path.map(_escapeJsonPointerSegment).join('/')}';
  }

  String _toolParameterHeaderParameterName(List<String> path) {
    if (path.length == 1) {
      return path.single;
    }

    return _toolParameterHeaderSelector(path);
  }

  String _escapeJsonPointerSegment(String segment) {
    return segment.replaceAll('~', '~0').replaceAll('/', '~1');
  }

  bool _isValidMcpHeaderNameSuffix(String value) {
    return isValidMcpHeaderNameSuffix(value);
  }

  bool _isToolParameterHeaderPrimitive(JsonSchema schema) {
    return schema is JsonString ||
        schema is JsonInteger ||
        schema is JsonBoolean;
  }

  /// Sends a `notifications/roots/list_changed` notification to the server.
  Future<void> sendRootsListChanged() {
    const notif = JsonRpcRootsListChangedNotification();
    return notification(notif);
  }
}

/// Deprecated alias for [McpClient].
@Deprecated('Use McpClient instead')
typedef Client = McpClient;

class _ClientSubscriptionState {
  final int id;
  final SubscriptionFilter requestedNotifications;
  final BasicAbortController abortController;
  final void Function() onClose;
  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final Completer<SubscriptionsAcknowledgedNotification> _acknowledged =
      Completer<SubscriptionsAcknowledgedNotification>();
  final Completer<EmptyResult> _done = Completer<EmptyResult>();

  SubscriptionFilter? _acknowledgedNotifications;
  bool _closed = false;
  bool _localCancellation = false;

  _ClientSubscriptionState({
    required this.id,
    required this.requestedNotifications,
    required this.abortController,
    required this.onClose,
  });

  Future<SubscriptionsAcknowledgedNotification> get acknowledged =>
      _acknowledged.future;

  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  Future<EmptyResult> get done => _done.future;

  void handleNotification(JsonRpcNotification notification) {
    if (_closed) {
      return;
    }

    if (_acknowledgedNotifications == null) {
      if (notification.method !=
          Method.notificationsSubscriptionsAcknowledged) {
        fail(
          McpError(
            ErrorCode.invalidRequest.value,
            'Subscription $id received ${notification.method} before '
            '${Method.notificationsSubscriptionsAcknowledged}.',
          ),
          StackTrace.current,
        );
        return;
      }

      final acknowledgedParams =
          (notification as JsonRpcSubscriptionsAcknowledgedNotification)
              .acknowledgedParams;
      final acknowledgedNotifications = acknowledgedParams.notifications;
      if (!acknowledgedNotifications.isSubsetOf(requestedNotifications)) {
        fail(
          McpError(
            ErrorCode.invalidRequest.value,
            'Subscription $id acknowledged notifications that were not '
            'requested.',
          ),
          StackTrace.current,
        );
        return;
      }

      _acknowledgedNotifications = acknowledgedNotifications;
      if (!_acknowledged.isCompleted) {
        _acknowledged.complete(acknowledgedParams);
      }
      return;
    }

    final acknowledgedNotifications = _acknowledgedNotifications!;
    if (!acknowledgedNotifications.allowsNotification(notification)) {
      fail(
        McpError(
          ErrorCode.invalidRequest.value,
          '${notification.method} was not requested or acknowledged for '
          'subscription $id.',
        ),
        StackTrace.current,
      );
      return;
    }

    _notifications.add(notification);
  }

  void trackRequest(Future<EmptyResult> requestDone) {
    requestDone.then(
      complete,
      onError: (Object error, StackTrace stackTrace) {
        if (_localCancellation) {
          complete(const EmptyResult());
        } else {
          fail(error, stackTrace, abort: false);
        }
      },
    );
  }

  void cancel([Object? reason]) {
    if (_closed) {
      return;
    }

    _localCancellation = true;
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(AbortError(reason), StackTrace.current);
    }
    abortController.abort(reason);
    complete(const EmptyResult());
  }

  void complete(EmptyResult result) {
    if (_closed) {
      return;
    }

    final missingAcknowledgment = _acknowledgedNotifications == null &&
        !_localCancellation &&
        !abortController.signal.aborted;
    if (missingAcknowledgment) {
      fail(
        McpError(
          ErrorCode.invalidRequest.value,
          'Subscription $id completed before '
          '${Method.notificationsSubscriptionsAcknowledged}.',
        ),
        StackTrace.current,
        abort: false,
      );
      return;
    }

    _closed = true;
    onClose();
    if (!_done.isCompleted) {
      _done.complete(result);
    }
    _notifications.close();
  }

  void fail(
    Object error,
    StackTrace stackTrace, {
    bool abort = true,
  }) {
    if (_closed) {
      return;
    }

    _closed = true;
    onClose();
    if (abort && !abortController.signal.aborted) {
      abortController.abort(error);
    }
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(error, stackTrace);
    }
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
    _notifications
      ..addError(error, stackTrace)
      ..close();
  }
}

class _ToolParameterHeaderValidation {
  final Map<String, String> mappings;
  final String? rejectionReason;

  const _ToolParameterHeaderValidation.valid(this.mappings)
      : rejectionReason = null;

  const _ToolParameterHeaderValidation.invalid(this.rejectionReason)
      : mappings = const {};
}
