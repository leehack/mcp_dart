import 'dart:async';

import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/mcp_header_validation.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/protocol_direction.dart';
import 'package:mcp_dart/src/shared/stateless_meta_validation.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/tool_parameter_headers.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.client");

const _defaultLegacyDiscoveryTimeout = Duration(seconds: 5);

/// Options for configuring the MCP [McpClient].
class McpClientOptions extends ProtocolOptions {
  /// Capabilities to advertise as being supported by this client.
  final ClientCapabilities? capabilities;

  /// High-level protocol compatibility profile.
  ///
  /// Defaults to [McpProtocol.stable], which prefers MCP `2026-07-28`
  /// negotiation with legacy fallback.
  final McpProtocol protocol;

  final String? _protocolVersion;

  /// Preferred protocol version for negotiation.
  ///
  /// When omitted, this is derived from [protocol]. Passing this explicitly is
  /// a low-level override; most callers should prefer [protocol]. A supported
  /// legacy version selects the legacy `initialize` flow unless
  /// [useServerDiscover] is explicitly enabled.
  String get protocolVersion {
    final protocolVersion = _protocolVersion;
    if (protocolVersion != null) {
      return protocolVersion;
    }
    if (protocol == McpProtocol.legacy && _useServerDiscover == true) {
      return defaultProtocolVersion;
    }
    return protocol.preferredProtocolVersion;
  }

  final bool? _useServerDiscover;

  /// Whether [McpClient.connect] should probe with `server/discover` first.
  ///
  /// [McpProtocol.require2026] always enables discovery, even when
  /// [useServerDiscover] is explicitly set to `false`.
  ///
  /// When omitted, an explicit stateless [protocolVersion] enables discovery,
  /// while an explicit supported legacy version selects `initialize` unless
  /// [protocol] is [McpProtocol.require2026]. Otherwise this is derived from
  /// [protocol]. Explicitly enabling discovery with a legacy version probes
  /// the latest stateless version and preserves the legacy version for
  /// initialization fallback.
  bool get useServerDiscover {
    if (protocol == McpProtocol.require2026) {
      return true;
    }

    final useServerDiscover = _useServerDiscover;
    if (useServerDiscover != null) {
      return useServerDiscover;
    }

    final protocolVersion = _protocolVersion;
    if (protocolVersion != null) {
      if (isStatelessProtocolVersion(protocolVersion)) {
        return true;
      }
      if (protocol != McpProtocol.require2026 &&
          legacyProtocolVersions.contains(protocolVersion)) {
        return false;
      }
    }

    return protocol.useServerDiscoverByDefault;
  }

  /// Whether a failed `server/discover` probe should fall back to the legacy
  /// `initialize` handshake when the peer looks like a pre-discovery server.
  final bool? _allowLegacyInitializationFallback;

  /// Whether a failed `server/discover` probe should fall back to `initialize`.
  ///
  /// When omitted, this is derived from [protocol]. [McpProtocol.require2026]
  /// always disables fallback, even when
  /// [allowLegacyInitializationFallback] is explicitly set to `true`.
  bool get allowLegacyInitializationFallback {
    if (protocol == McpProtocol.require2026) {
      return false;
    }
    return _allowLegacyInitializationFallback ??
        protocol.allowLegacyInitializationFallbackByDefault;
  }

  final Duration _legacyDiscoveryTimeout;

  /// Creates MCP client options.
  ///
  /// [legacyDiscoveryTimeout] bounds the initial `server/discover` probe on
  /// body-only transports such as stdio. HTTP transports retain the normal
  /// request timeout because an HTTP discovery timeout indicates an outage,
  /// not a legacy peer.
  const McpClientOptions({
    super.enforceStrictCapabilities,
    super.gracefulShutdownTimeout,
    this.capabilities,
    this.protocol = McpProtocol.stable,
    String? protocolVersion,
    bool? useServerDiscover,
    bool? allowLegacyInitializationFallback,
    Duration legacyDiscoveryTimeout = _defaultLegacyDiscoveryTimeout,
  })  : _protocolVersion = protocolVersion,
        _useServerDiscover = useServerDiscover,
        _allowLegacyInitializationFallback = allowLegacyInitializationFallback,
        _legacyDiscoveryTimeout = legacyDiscoveryTimeout;
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

  /// Changed acknowledgments from replacement streams after transport replay.
  ///
  /// The initial stream's acknowledgment is exposed through [acknowledged].
  /// Reconnecting transports suppress equivalent replay acknowledgments and
  /// emit only a changed filter here.
  final Stream<SubscriptionsAcknowledgedNotification> acknowledgmentChanges;

  /// Notifications delivered on this subscription stream after acknowledgment.
  final Stream<JsonRpcNotification> notifications;

  /// Completes when the `subscriptions/listen` request ends gracefully.
  final Future<SubscriptionsListenResult> done;

  McpSubscription._({
    required this.id,
    required this.acknowledged,
    required this.acknowledgmentChanges,
    required this.notifications,
    required this.done,
    required void Function([Object? reason]) cancel,
  }) : _cancel = cancel;

  /// Cancels this subscription stream.
  void cancel([Object? reason]) {
    _cancel(reason);
  }
}

ElicitResult _withElicitationDefaults(
  ElicitResult result,
  JsonSchema schema,
) {
  final content = _deepCopy(result.content ?? const <String, dynamic>{})
      as Map<String, dynamic>;
  _applyElicitationDefaults(schema, content);
  return ElicitResult(
    action: result.action,
    content: content,
    meta: result.meta,
  );
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

const Set<String> _statelessRemovedServerNotificationMethods = {
  Method.notificationsInitialized,
  Method.notificationsRootsListChanged,
  Method.notificationsTasksStatus,
  Method.notificationsElicitationComplete,
};

const Set<String> _statelessOnlyRequestMethods = {
  Method.subscriptionsListen,
  Method.tasksUpdate,
};

const Set<String> _statelessOnlyNotificationMethods = {
  Method.notificationsSubscriptionsAcknowledged,
  Method.notificationsTasks,
};

const Set<String> _statelessSubscriptionNotificationMethods = {
  Method.notificationsSubscriptionsAcknowledged,
  Method.notificationsToolsListChanged,
  Method.notificationsPromptsListChanged,
  Method.notificationsResourcesListChanged,
  Method.notificationsResourcesUpdated,
  Method.notificationsTasks,
};

const Set<String> _statelessInputRequiredResultMethods = {
  Method.toolsCall,
  Method.promptsGet,
  Method.resourcesRead,
};

const int _maxInputRequiredRetries = 16;
const int _maxToolMetadataRefreshPages = 100;

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
  final Duration _legacyDiscoveryTimeout;
  String? _instructions;
  Future<void>? _sessionRefresh;
  String? _negotiatedProtocolVersion;
  bool _usesStatelessProtocol = false;
  bool _sentInitialized = false;

  String get _preferredDiscoveryProtocolVersion =>
      legacyProtocolVersions.contains(_preferredProtocolVersion)
          ? defaultProtocolVersion
          : _preferredProtocolVersion;

  final Map<String, JsonSchema> _cachedToolOutputSchemas = {};
  final Set<String> _cachedRequiredTaskTools = {};
  final ToolParameterHeaderMappings _cachedToolParameterHeaders = {};
  String? _expectedToolListCursor;
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
        _preferredProtocolVersion = options?.protocolVersion ??
            McpProtocol.stable.preferredProtocolVersion,
        _useServerDiscover = options?.protocol == McpProtocol.require2026
            ? true
            : options?.useServerDiscover ??
                McpProtocol.stable.useServerDiscoverByDefault,
        _allowLegacyInitializationFallback = options?.protocol ==
                McpProtocol.require2026
            ? false
            : options?.allowLegacyInitializationFallback ??
                McpProtocol.stable.allowLegacyInitializationFallbackByDefault,
        _legacyDiscoveryTimeout =
            options?._legacyDiscoveryTimeout ?? _defaultLegacyDiscoveryTimeout,
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
              !(_capabilities.elicitation?.supportsForm ?? false)) {
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
          var result = await onElicitRequest!(request.elicitParams);

          // Apply defaults if client supports it and it's a form elicitation
          if (request.elicitParams.isFormMode &&
              result.action == 'accept' &&
              request.elicitParams.requestedSchema != null &&
              _capabilities.elicitation?.form?.applyDefaults == true) {
            result = _withElicitationDefaults(
              result,
              request.elicitParams.requestedSchema!,
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
              ErrorCode.methodNotFound.value,
              "Client does not support 'sampling.tools' capability required by sampling/createMessage request.",
            );
          }
          if (request.createParams.includeContext != null &&
              request.createParams.includeContext != IncludeContext.none &&
              _capabilities.sampling?.context != true) {
            throw McpError(
              ErrorCode.methodNotFound.value,
              "Client does not support 'sampling.context' capability required by sampling/createMessage request.",
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

    final initializationProtocolVersion =
        legacyProtocolVersions.contains(_preferredProtocolVersion)
            ? _preferredProtocolVersion
            : latestInitializationProtocolVersion;
    final initParams = InitializeRequest(
      protocolVersion: initializationProtocolVersion,
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

    if (!legacyProtocolVersions.contains(result.protocolVersion)) {
      throw McpError(
        ErrorCode.internalError.value,
        "Server's chosen initialization protocol version is not supported by client: ${result.protocolVersion}. Supported: $legacyProtocolVersions",
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

  Map<String, dynamic> _statelessRequestMeta(
    Map<String, dynamic>? meta, {
    LoggingLevel? logLevel,
  }) {
    return buildProtocolRequestMeta(
      protocolVersion: _negotiatedProtocolVersion ?? _preferredProtocolVersion,
      clientInfo: _clientInfo,
      clientCapabilities: _capabilities,
      meta: meta,
      logLevel: logLevel?.name,
    );
  }

  List<String>? _supportedVersionsFromUnsupportedProtocolError(McpError error) {
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
    return advertisedVersions;
  }

  String? _retryableDiscoveryProtocolVersion(
    McpError error,
    String attemptedVersion,
  ) {
    final advertisedVersions =
        _supportedVersionsFromUnsupportedProtocolError(error);
    if (advertisedVersions == null) return null;

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
    final discoveryOptions = versionedTransport == null
        ? RequestOptions(timeout: _legacyDiscoveryTimeout)
        : null;

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
      discoveryOptions,
    );

    final negotiatedProtocolVersion = negotiateProtocolVersion(
      result.supportedVersions,
      // A DiscoverResult identifies a modern peer. Legacy protocol versions
      // require the initialize handshake and cannot be selected here.
      localSupportedVersions: statelessProtocolVersions,
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

    final discoveredServer = result.serverInfo;
    final serverDescription = discoveredServer == null
        ? 'unknown'
        : '${discoveredServer.name} ${discoveredServer.version}';
    _logger.debug(
      "MCP Server Discovered. Server: $serverDescription, Protocol: $negotiatedProtocolVersion",
    );

    return result;
  }

  Future<DiscoverResult> discoverServer() async {
    final discoveryProtocolVersion = _preferredDiscoveryProtocolVersion;
    try {
      return await _discoverServerWithVersion(discoveryProtocolVersion);
    } catch (error) {
      if (error is! McpError) {
        rethrow;
      }

      final retryVersion = _retryableDiscoveryProtocolVersion(
        error,
        discoveryProtocolVersion,
      );
      if (retryVersion == null) {
        rethrow;
      }

      _logger.debug(
        "server/discover rejected protocol $discoveryProtocolVersion; "
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
          if (!_isLegacyDiscoveryFallbackError(error, transport)) {
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

  bool _isLegacyDiscoveryFallbackError(
    Object error,
    Transport transport,
  ) {
    if (!_allowLegacyInitializationFallback || error is! McpError) {
      return false;
    }
    if (error.code == ErrorCode.headerMismatch.value ||
        error.code == ErrorCode.missingRequiredClientCapability.value ||
        error.code == ErrorCode.unsupportedProtocolVersion.value) {
      // Recognized modern protocol errors identify a modern server. They may
      // trigger stateless retries, but never legacy initialization fallback.
      return false;
    }

    if (error.code == ErrorCode.requestTimeout.value) {
      // Body-only stream transports use discovery timeouts to identify silent
      // legacy peers. HTTP-capable transports surface timeouts as outages.
      return transport is! ProtocolVersionAwareTransport;
    }

    final message = error.message;
    if (error.code == 0) {
      return message.contains('Error POSTing to endpoint (HTTP 400)') ||
          message.contains('Server not initialized');
    }

    if (error.code == ErrorCode.connectionClosed.value) {
      return message.contains('Server not initialized');
    }

    // Legacy servers use implementation-defined JSON-RPC errors for unknown
    // requests before initialize. The compatibility rules intentionally do not
    // key fallback to one particular generic error code.
    return true;
  }

  @override
  Future<T> request<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    int? relatedRequestId,
  ]) async {
    _assertStatelessRequestAllowed(requestData.method);
    _assertLegacyRequestAllowed(requestData.method);

    final outboundRequest =
        _usesStatelessProtocol && requestData.method != Method.serverDiscover
            ? JsonRpcRequest(
                id: requestData.id,
                method: requestData.method,
                params: requestData.params,
                meta: _statelessRequestMeta(
                  requestData.meta,
                  logLevel: options?.logLevel,
                ),
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

  BaseResultData _parseExpectedOrInputRequired<T extends BaseResultData>(
    String method,
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) resultFactory,
  ) {
    if (json['resultType'] == resultTypeInputRequired) {
      if (!_usesStatelessProtocol) {
        throw FormatException(
          'MCP resultType "$resultTypeInputRequired" is not valid for '
          '$method in initialization-era MCP',
        );
      }
      return InputRequiredResult.fromJson(json);
    }
    return resultFactory(json);
  }

  BaseResultData _parseToolCallResult(Map<String, dynamic> json) {
    switch (json['resultType']) {
      case resultTypeInputRequired:
        if (!_usesStatelessProtocol) {
          throw const FormatException(
            'MCP resultType "$resultTypeInputRequired" is not valid for '
            '${Method.toolsCall} in initialization-era MCP',
          );
        }
        return InputRequiredResult.fromJson(json);
      case resultTypeTask:
        if (!_usesStatelessProtocol ||
            !_capabilities.supportsTasksExtension ||
            !(_serverCapabilities?.supportsTasksExtension ?? false)) {
          throw const FormatException(
            'MCP resultType "task" is not valid for tools/call',
          );
        }
        return CreateTaskExtensionResult.fromJson(json);
      default:
        return CallToolResult.fromJson(json);
    }
  }

  Future<InputResponses?> _resolveInputRequests(
    InputRequests? inputRequests,
    AbortSignal? signal,
  ) async {
    if (inputRequests == null) {
      return null;
    }

    final inputResponses = <String, InputResponse>{};
    for (final entry in inputRequests.entries) {
      signal?.throwIfAborted();
      _assertEmbeddedInputRequestCapability(entry.key, entry.value);
      final result = await handleEmbeddedInputRequest(
        entry.key,
        entry.value,
        signal: signal,
      );
      inputResponses[entry.key] = InputResponse.fromResult(result);
    }
    return inputResponses;
  }

  void _assertEmbeddedInputRequestCapability(
    String inputRequestKey,
    InputRequest inputRequest,
  ) {
    Map<String, dynamic>? requiredCapabilities;
    switch (inputRequest.method) {
      case Method.rootsList:
        if (_capabilities.roots == null) {
          requiredCapabilities = {'roots': <String, dynamic>{}};
        }
        break;
      case Method.elicitationCreate:
        final params = inputRequest.elicitParams;
        if (params.isUrlMode && _capabilities.elicitation?.url == null) {
          requiredCapabilities = {
            'elicitation': {'url': <String, dynamic>{}},
          };
        } else if (params.isFormMode &&
            !(_capabilities.elicitation?.supportsForm ?? false)) {
          requiredCapabilities = {
            'elicitation': {'form': <String, dynamic>{}},
          };
        }
        break;
      case Method.samplingCreateMessage:
        final params = inputRequest.createMessageParams;
        final sampling = _capabilities.sampling;
        if (sampling == null) {
          requiredCapabilities = {'sampling': <String, dynamic>{}};
        } else if ((params.tools != null || params.toolChoice != null) &&
            !sampling.tools) {
          requiredCapabilities = {
            'sampling': {'tools': <String, dynamic>{}},
          };
        } else if (params.includeContext != null &&
            params.includeContext != IncludeContext.none &&
            !sampling.context) {
          requiredCapabilities = {
            'sampling': {'context': <String, dynamic>{}},
          };
        }
        break;
    }

    if (requiredCapabilities != null) {
      throw McpError(
        ErrorCode.missingRequiredClientCapability.value,
        'Received an embedded input request requiring an unadvertised client '
        'capability.',
        {
          'inputRequest': inputRequestKey,
          'method': inputRequest.method,
          'requiredCapabilities': requiredCapabilities,
        },
      );
    }
  }

  Future<InputResponses?> _resolveNewInputRequests(
    InputRequests? inputRequests,
    Set<String> answeredKeys,
    AbortSignal? signal,
  ) async {
    if (inputRequests == null) {
      return null;
    }

    final pendingRequests = <String, InputRequest>{};
    for (final entry in inputRequests.entries) {
      if (!answeredKeys.contains(entry.key)) {
        pendingRequests[entry.key] = entry.value;
      }
    }
    if (pendingRequests.isEmpty) {
      return null;
    }

    final inputResponses = await _resolveInputRequests(
      pendingRequests,
      signal,
    );
    if (inputResponses != null) {
      answeredKeys.addAll(inputResponses.keys);
    }
    return inputResponses;
  }

  Future<T> _requestResolvingInputRequired<T extends BaseResultData>(
    String method,
    JsonRpcRequest Function(
      InputResponses? inputResponses,
      String? requestState,
      bool isRetry,
    ) buildRequest,
    T Function(Map<String, dynamic>) resultFactory, [
    RequestOptions? options,
  ]) async {
    InputResponses? inputResponses;
    String? requestState;

    for (var attempt = 0; attempt <= _maxInputRequiredRetries; attempt++) {
      final result = await request<BaseResultData>(
        buildRequest(inputResponses, requestState, attempt > 0),
        (json) => _parseExpectedOrInputRequired<T>(
          method,
          json,
          resultFactory,
        ),
        options,
      );

      if (result is T) {
        return result;
      }

      if (result is! InputRequiredResult) {
        throw McpError(
          ErrorCode.internalError.value,
          'Unexpected result type ${result.runtimeType} for $method.',
        );
      }

      if (attempt == _maxInputRequiredRetries) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          'Exceeded $_maxInputRequiredRetries input_required retries for $method.',
        );
      }

      inputResponses = await _resolveInputRequests(
        result.inputRequests,
        options?.signal,
      );
      requestState = result.requestState;
    }

    throw StateError('Unreachable input_required retry state for $method.');
  }

  Future<BaseResultData> _requestResolvingToolCall(
    CallToolRequest params,
    RequestOptions? options,
  ) async {
    InputResponses? inputResponses;
    String? requestState;
    var refreshedToolMetadata = false;

    for (var attempt = 0; attempt <= _maxInputRequiredRetries;) {
      final BaseResultData result;
      try {
        result = await request<BaseResultData>(
          JsonRpcCallToolRequest(
            id: -1,
            params: CallToolRequest(
              name: params.name,
              arguments: params.arguments,
              inputResponses:
                  attempt > 0 ? inputResponses : params.inputResponses,
              requestState: attempt > 0 ? requestState : params.requestState,
            ).toJson(),
          ),
          _parseToolCallResult,
          options,
        );
      } on McpError catch (error) {
        if (!refreshedToolMetadata &&
            error.code == ErrorCode.headerMismatch.value &&
            transport is ToolParameterHeaderAwareTransport) {
          refreshedToolMetadata = true;
          _logger.debug(
            'tools/call for "${params.name}" returned HeaderMismatch; '
            'refreshing tools/list and retrying.',
          );
          await _refreshToolMetadataFor(params.name, options);
          continue;
        }
        rethrow;
      }

      if (result is CallToolResult || result is CreateTaskExtensionResult) {
        return result;
      }

      if (result is! InputRequiredResult) {
        throw McpError(
          ErrorCode.internalError.value,
          'Unexpected result type ${result.runtimeType} for ${Method.toolsCall}.',
        );
      }

      if (attempt == _maxInputRequiredRetries) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          'Exceeded $_maxInputRequiredRetries input_required retries for ${Method.toolsCall}.',
        );
      }

      inputResponses = await _resolveInputRequests(
        result.inputRequests,
        options?.signal,
      );
      requestState = result.requestState;
      attempt += 1;
    }

    throw StateError(
      'Unreachable input_required retry state for ${Method.toolsCall}.',
    );
  }

  Future<void> _refreshToolMetadataFor(
    String toolName,
    RequestOptions? options,
  ) async {
    String? cursor;
    final seenCursors = <String>{};

    for (var page = 0; page < _maxToolMetadataRefreshPages; page++) {
      final result = await listTools(
        params: cursor == null ? null : ListToolsRequest(cursor: cursor),
        options: _toolMetadataRefreshOptions(options),
      );
      if (result.tools.any((tool) => tool.name == toolName)) {
        return;
      }

      final nextCursor = result.nextCursor;
      if (nextCursor == null) {
        return;
      }
      if (!seenCursors.add(nextCursor)) {
        _logger.warn(
          'Stopping tools/list refresh for "$toolName" because cursor '
          '"$nextCursor" was repeated.',
        );
        return;
      }
      cursor = nextCursor;
    }

    _logger.warn(
      'Stopping tools/list refresh for "$toolName" after '
      '$_maxToolMetadataRefreshPages pages.',
    );
  }

  RequestOptions? _toolMetadataRefreshOptions(RequestOptions? options) {
    if (options == null) {
      return null;
    }
    return RequestOptions(
      signal: options.signal,
      timeout: options.timeout,
      resetTimeoutOnProgress: options.resetTimeoutOnProgress,
      maxTotalTimeout: options.maxTotalTimeout,
      timeoutEnabled: options.timeoutEnabled,
      logLevel: options.logLevel,
    );
  }

  Future<CallToolResult> _resolveTaskExtensionToolResult(
    TaskExtensionTask initialTask,
    RequestOptions? options,
  ) async {
    var currentTask = initialTask;
    final answeredInputKeys = <String>{};

    while (true) {
      options?.signal?.throwIfAborted();

      // CreateTaskResult contains only the base Task shape. Always resolve the
      // detailed state through tasks/get before inspecting status-specific
      // fields, including when the seed already reports a terminal status.
      await _waitForTaskExtensionPoll(currentTask, options?.signal);
      currentTask = await _getTaskExtension(currentTask.taskId, options);

      switch (currentTask.status) {
        case TaskStatus.completed:
          final result = currentTask.result;
          if (result == null) {
            throw McpError(
              ErrorCode.internalError.value,
              'Completed task ${currentTask.taskId} is missing a result.',
            );
          }
          return CallToolResult.fromJson(result);

        case TaskStatus.failed:
          final error = currentTask.error;
          if (error != null) {
            throw McpError(error.code, error.message, error.data);
          }
          throw McpError(
            ErrorCode.internalError.value,
            'Task ${currentTask.taskId} failed without error details.',
          );

        case TaskStatus.cancelled:
          throw McpError(
            ErrorCode.invalidRequest.value,
            'Task ${currentTask.taskId} was cancelled.',
          );

        case TaskStatus.inputRequired:
          final inputResponses = await _resolveNewInputRequests(
            currentTask.inputRequests,
            answeredInputKeys,
            options?.signal,
          );
          if (inputResponses != null && inputResponses.isNotEmpty) {
            await request<TaskExtensionAcknowledgementResult>(
              JsonRpcUpdateTaskRequest(
                id: -1,
                updateParams: UpdateTaskRequest(
                  taskId: currentTask.taskId,
                  inputResponses: inputResponses,
                ),
              ),
              TaskExtensionAcknowledgementResult.fromJson,
              _taskFollowUpOptions(options),
            );
          }
          break;

        case TaskStatus.working:
          break;
      }
    }
  }

  Future<TaskExtensionTask> _getTaskExtension(
    String taskId,
    RequestOptions? options,
  ) async {
    final result = await request<GetTaskExtensionResult>(
      JsonRpcGetTaskRequest(
        id: -1,
        getParams: GetTaskRequest(taskId: taskId),
      ),
      GetTaskExtensionResult.fromJson,
      _taskFollowUpOptions(options),
    );
    if (result.task.taskId != taskId) {
      throw McpError(
        ErrorCode.internalError.value,
        'Invalid ${Method.tasksGet} response: returned task '
        '${result.task.taskId} instead of requested task $taskId.',
      );
    }
    return result.task;
  }

  RequestOptions? _taskFollowUpOptions(RequestOptions? options) {
    if (options == null) {
      return null;
    }
    return RequestOptions(
      signal: options.signal,
      timeout: options.timeout,
      resetTimeoutOnProgress: options.resetTimeoutOnProgress,
      maxTotalTimeout: options.maxTotalTimeout,
      timeoutEnabled: options.timeoutEnabled,
      logLevel: options.logLevel,
    );
  }

  Future<void> _waitForTaskExtensionPoll(
    TaskExtensionTask task,
    AbortSignal? signal,
  ) async {
    signal?.throwIfAborted();

    final interval = task.pollIntervalMs ?? 1000;
    final completer = Completer<void>();
    final timer = Timer(Duration(milliseconds: interval), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    StreamSubscription? abortSubscription;
    if (signal != null) {
      abortSubscription = signal.onAbort.listen((_) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(AbortError(signal.reason));
        }
      });
    }

    try {
      await completer.future;
    } finally {
      timer.cancel();
      await abortSubscription?.cancel();
    }
  }

  @override
  Future<void> notification(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    int? relatedRequestId,
  }) async {
    _assertStatelessNotificationAllowed(notificationData.method);
    if (_usesStatelessProtocol) {
      validateStatelessNotificationMetaObjects(notificationData);
    }
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

  void _assertLegacyRequestAllowed(String method) {
    if (_usesStatelessProtocol ||
        !_statelessOnlyRequestMethods.contains(method)) {
      return;
    }
    throw McpError(
      ErrorCode.methodNotFound.value,
      '$method is only available in MCP stateless protocol versions.',
    );
  }

  void _assertStatelessNotificationAllowed(String method) {
    if (!_usesStatelessProtocol ||
        !isStatelessForbiddenClientNotification(method)) {
      return;
    }

    throw McpError(
      ErrorCode.methodNotFound.value,
      'MCP $_negotiatedProtocolVersion does not define $method.',
    );
  }

  /// Gets the server's reported capabilities after successful initialization.
  ServerCapabilities? getServerCapabilities() => _serverCapabilities;

  /// Whether this client currently has an attached transport.
  bool get isConnected => transport != null;

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
  bool isResultTypeAllowedForRequest(
    JsonRpcRequest request,
    String resultType,
  ) {
    if (resultType == resultTypeInputRequired) {
      return _statelessInputRequiredResultMethods.contains(request.method);
    }
    if (resultType == resultTypeTask) {
      return request.method == Method.toolsCall &&
          _capabilities.supportsTasksExtension &&
          (_serverCapabilities?.supportsTasksExtension ?? false);
    }
    return super.isResultTypeAllowedForRequest(request, resultType);
  }

  @override
  McpError? validateIncomingRequest(JsonRpcRequest request) {
    if (_usesStatelessProtocol) {
      final missingPeerCapability =
          _missingPeerCapabilityForIncomingRequest(request.method);
      if (missingPeerCapability != null) {
        return McpError(
          ErrorCode.methodNotFound.value,
          "Client does not support capability '$missingPeerCapability' "
          "required for method '${request.method}'",
        );
      }
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
  bool shouldRespondToInvalidIncomingRequest(
    JsonRpcRequest request,
    McpError error,
  ) =>
      !_usesStatelessProtocol;

  String? _missingPeerCapabilityForIncomingRequest(String method) {
    return switch (method) {
      Method.rootsList => _capabilities.roots == null ? 'roots' : null,
      Method.samplingCreateMessage =>
        _capabilities.sampling == null ? 'sampling' : null,
      Method.elicitationCreate =>
        _capabilities.elicitation == null ? 'elicitation' : null,
      _ => null,
    };
  }

  McpError? _validateIncomingNotificationDirection(
    JsonRpcNotification notification,
  ) {
    if (_usesStatelessProtocol &&
        _statelessRemovedServerNotificationMethods
            .contains(notification.method)) {
      return McpError(
        ErrorCode.methodNotFound.value,
        'MCP $_negotiatedProtocolVersion does not define '
        '${notification.method}.',
      );
    }
    if (!_usesStatelessProtocol &&
        _statelessOnlyNotificationMethods.contains(notification.method)) {
      return McpError(
        ErrorCode.methodNotFound.value,
        '${notification.method} is only available in MCP stateless protocol '
        'versions.',
      );
    }
    return null;
  }

  @override
  McpError? validateIncomingNotificationBeforeParsing(
    JsonRpcNotification notification,
  ) =>
      _validateIncomingNotificationDirection(notification);

  @override
  McpError? validateIncomingNotification(JsonRpcNotification notification) {
    if (_usesStatelessProtocol) {
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

    final directionError = _validateIncomingNotificationDirection(notification);
    if (directionError != null) {
      return directionError;
    }
    if (_usesStatelessProtocol &&
        _statelessSubscriptionNotificationMethods
            .contains(notification.method)) {
      final subscriptionId = notification.meta?[McpMetaKey.subscriptionId];
      if (subscriptionId is! int && subscriptionId is! String) {
        return McpError(
          ErrorCode.invalidRequest.value,
          '${notification.method} must include a string or integer '
          '${McpMetaKey.subscriptionId}.',
        );
      }
      if (!_activeSubscriptions.containsKey(subscriptionId)) {
        return McpError(
          ErrorCode.invalidRequest.value,
          '${notification.method} references unknown subscription '
          '$subscriptionId.',
        );
      }
    }
    if (_usesStatelessProtocol &&
        notification.method == Method.notificationsCancelled) {
      JsonRpcCancelledNotification cancellation;
      try {
        cancellation = notification is JsonRpcCancelledNotification
            ? notification
            : JsonRpcCancelledNotification.fromJson(notification.toJson());
      } on FormatException catch (error) {
        return McpError(
          ErrorCode.invalidRequest.value,
          'Invalid stateless subscription cancellation.',
          error.message,
        );
      }
      final subscriptionId = cancellation.meta?[McpMetaKey.subscriptionId];
      if ((subscriptionId is! int && subscriptionId is! String) ||
          subscriptionId != cancellation.cancelParams.requestId) {
        return McpError(
          ErrorCode.invalidRequest.value,
          '${Method.notificationsCancelled} must correlate its requestId '
          'with ${McpMetaKey.subscriptionId}.',
        );
      }
    }
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
    if (notification is JsonRpcCancelledNotification) {
      final requestId = notification.cancelParams.requestId;
      final subscriptionId = notification.meta?[McpMetaKey.subscriptionId];
      final activeSubscription = _activeSubscriptions[requestId];
      if (activeSubscription != null &&
          (!_usesStatelessProtocol || subscriptionId == requestId)) {
        activeSubscription.handleServerCancellation();
        return;
      }
    }

    final subscriptionId = notification.meta?[McpMetaKey.subscriptionId];
    if (subscriptionId is! int && subscriptionId is! String) {
      return;
    }

    final activeSubscription = _activeSubscriptions[subscriptionId];
    final activeTransport = transport;
    var isReplayAcknowledgment = false;
    if (notification.method == Method.notificationsSubscriptionsAcknowledged &&
        activeTransport is SubscriptionReplayAcknowledgmentTransport) {
      isReplayAcknowledgment =
          (activeTransport as SubscriptionReplayAcknowledgmentTransport)
              .consumeSubscriptionReplayAcknowledgment(subscriptionId);
    }
    activeSubscription?.handleNotification(
      notification,
      isReplayAcknowledgment: isReplayAcknowledgment,
    );
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

    _serverCapabilities = null;
    _serverVersion = null;
    _instructions = null;
    _sessionRefresh = null;
    _negotiatedProtocolVersion = null;
    _usesStatelessProtocol = false;
    _sentInitialized = false;
    _cachedToolOutputSchemas.clear();
    _cachedRequiredTaskTools.clear();
    _cachedToolParameterHeaders.clear();
    _expectedToolListCursor = null;
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
        supported = _usesStatelessProtocol;
        requiredCapability = 'MCP stateless subscriptions';
        break;
      case Method.toolsCall:
      case Method.toolsList:
        supported = serverCaps.tools != null;
        requiredCapability = 'tools';
        break;
      case Method.tasksGet:
      case Method.tasksCancel:
        supported = _usesStatelessProtocol
            ? serverCaps.supportsTasksExtension
            : serverCaps.tasks != null;
        requiredCapability =
            _usesStatelessProtocol ? mcpTasksExtensionId : 'legacy tasks';
        break;
      case Method.tasksUpdate:
        supported = _usesStatelessProtocol && serverCaps.supportsTasksExtension;
        requiredCapability = mcpTasksExtensionId;
        break;
      case Method.tasksList:
      case Method.tasksResult:
        supported = !_usesStatelessProtocol && serverCaps.tasks != null;
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
        ErrorCode.methodNotFound.value,
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
        ErrorCode.methodNotFound.value,
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
      EmptyResult.fromJson,
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
    return request<EmptyResult>(req, EmptyResult.fromJson, options);
  }

  /// Sends a `prompts/get` request to retrieve a specific prompt/template.
  Future<GetPromptResult> getPrompt(
    GetPromptRequest params, [
    RequestOptions? options,
  ]) {
    return _requestResolvingInputRequired<GetPromptResult>(
      Method.promptsGet,
      (inputResponses, requestState, isRetry) => JsonRpcGetPromptRequest(
        id: -1,
        getParams: GetPromptRequest(
          name: params.name,
          arguments: params.arguments,
          inputResponses: isRetry ? inputResponses : params.inputResponses,
          requestState: isRetry ? requestState : params.requestState,
        ),
      ),
      GetPromptResult.fromJson,
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
    return _requestResolvingInputRequired<ReadResourceResult>(
      Method.resourcesRead,
      (inputResponses, requestState, isRetry) => JsonRpcReadResourceRequest(
        id: -1,
        readParams: ReadResourceRequest(
          uri: params.uri,
          inputResponses: isRetry ? inputResponses : params.inputResponses,
          requestState: isRetry ? requestState : params.requestState,
        ),
      ),
      ReadResourceResult.fromJson,
      options,
    );
  }

  /// Sends a `resources/subscribe` request to subscribe to updates for a resource.
  Future<EmptyResult> subscribeResource(
    SubscribeRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcSubscribeRequest(id: -1, subParams: params);
    return request<EmptyResult>(req, EmptyResult.fromJson, options);
  }

  /// Sends a `resources/unsubscribe` request to cancel a resource subscription.
  Future<EmptyResult> unsubscribeResource(
    UnsubscribeRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcUnsubscribeRequest(id: -1, unsubParams: params);
    return request<EmptyResult>(req, EmptyResult.fromJson, options);
  }

  /// Opens a `subscriptions/listen` stream and demultiplexes notifications.
  McpSubscription listenSubscriptions(SubscriptionsListenRequest params) {
    if (transport == null) {
      throw StateError('Not connected to a transport.');
    }
    _assertLegacyRequestAllowed(Method.subscriptionsListen);
    if (params.notifications.taskIds != null) {
      if (!_capabilities.supportsTasksExtension) {
        throw McpError(
          ErrorCode.missingRequiredClientCapability.value,
          'Task subscriptions require the client to advertise '
          '$mcpTasksExtensionId.',
          const {
            'requiredCapabilities': {
              'extensions': {
                mcpTasksExtensionId: <String, dynamic>{},
              },
            },
          },
        );
      }
      if (!(_serverCapabilities?.supportsTasksExtension ?? false)) {
        throw McpError(
          ErrorCode.methodNotFound.value,
          'Server does not support $mcpTasksExtensionId task subscriptions.',
        );
      }
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
    final requestDone = super.requestWithReservedId<SubscriptionsListenResult>(
      requestId,
      requestData,
      SubscriptionsListenResult.fromJson,
      RequestOptions(
        signal: abortController.signal,
        timeoutEnabled: false,
      ),
    );
    state.trackRequest(requestDone);

    return McpSubscription._(
      id: requestId,
      acknowledged: state.acknowledged,
      acknowledgmentChanges: state.acknowledgmentChanges,
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

    final taskOrToolResult = await _requestResolvingToolCall(params, options);
    final rawResult = taskOrToolResult is CreateTaskExtensionResult
        ? await _resolveTaskExtensionToolResult(
            taskOrToolResult.task,
            options,
          )
        : taskOrToolResult as CallToolResult;
    final result = _normalizeToolResultForProtocol(rawResult);

    final outputSchema = _cachedToolOutputSchemas[params.name];
    if (outputSchema != null && !result.isError) {
      try {
        if (!result.hasStructuredContent) {
          throw const FormatException(
            'structuredContent is required when outputSchema is declared',
          );
        }
        outputSchema.validate(result.structuredContentJson!.toJson());
      } catch (e) {
        throw McpError(
          ErrorCode.invalidParams.value,
          "Structured content does not match the tool's output schema: $e",
        );
      }
    }

    return result;
  }

  CallToolResult _normalizeToolResultForProtocol(CallToolResult result) {
    // Initialization-era MCP permits only object-root structured content.
    // Preserve the text/content fallback from newer peers without exposing a
    // 2026-only structured value through a legacy session.
    if (_usesStatelessProtocol || !result.hasStructuredContent) {
      return result;
    }

    final structuredContent = result.structuredContentJson?.toJson();
    if (structuredContent is Map &&
        structuredContent.keys.every((key) => key is String)) {
      return result;
    }

    return CallToolResult(
      content: result.content,
      isError: result.isError,
      meta: result.meta,
      extra: result.extra,
    );
  }

  bool _supportsToolOutputSchema(JsonSchema schema) {
    // MCP 2026-07-28 allows any JSON root; initialization-era schemas describe
    // object-root structured content only.
    return _usesStatelessProtocol || schema.toJson()['type'] == 'object';
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

    final cursor = params?.cursor;
    final continuesCurrentPagination =
        cursor != null && cursor == _expectedToolListCursor;
    final tools = _cacheToolMetadata(
      result.tools,
      reset: !continuesCurrentPagination,
    );
    _expectedToolListCursor = result.nextCursor;

    if (identical(tools, result.tools)) {
      return result;
    }

    return ListToolsResult(
      tools: tools,
      nextCursor: result.nextCursor,
      ttlMs: result.ttlMs,
      cacheScope: result.cacheScope,
      meta: result.meta,
    );
  }

  List<Tool> _cacheToolMetadata(
    List<Tool> tools, {
    required bool reset,
  }) {
    if (reset) {
      _cachedToolOutputSchemas.clear();
      _cachedRequiredTaskTools.clear();
      _cachedToolParameterHeaders.clear();
    }

    var filtered = false;
    final validTools = <Tool>[];

    for (final tool in tools) {
      _cachedToolOutputSchemas.remove(tool.name);
      _cachedRequiredTaskTools.remove(tool.name);
      _cachedToolParameterHeaders.remove(tool.name);

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

      final outputSchema = tool.outputSchema;
      if (outputSchema != null && _supportsToolOutputSchema(outputSchema)) {
        _cachedToolOutputSchemas[tool.name] = outputSchema;
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
    final reachabilityReason =
        toolParameterHeaderReachabilityRejectionReason(inputSchema.toJson());
    if (reachabilityReason != null) {
      return _ToolParameterHeaderValidation.invalid(reachabilityReason);
    }

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
  static const int _maxPendingNotifications = 256;

  final int id;
  final SubscriptionFilter requestedNotifications;
  final BasicAbortController abortController;
  final void Function() onClose;
  late final StreamController<JsonRpcNotification> _notifications;
  final Completer<SubscriptionsAcknowledgedNotification> _acknowledged =
      Completer<SubscriptionsAcknowledgedNotification>();
  final Completer<SubscriptionsListenResult> _done =
      Completer<SubscriptionsListenResult>();
  final StreamController<SubscriptionsAcknowledgedNotification>
      _acknowledgmentChanges =
      StreamController<SubscriptionsAcknowledgedNotification>.broadcast();
  final List<JsonRpcNotification> _pendingNotifications = [];

  SubscriptionFilter? _acknowledgedNotifications;
  bool _notificationStreamObserved = false;
  bool _notificationStreamShouldClose = false;
  ({Object error, StackTrace stackTrace})? _pendingNotificationError;
  bool _closed = false;
  bool _localCancellation = false;
  bool _serverCancellationReceived = false;

  _ClientSubscriptionState({
    required this.id,
    required this.requestedNotifications,
    required this.abortController,
    required this.onClose,
  }) {
    _notifications = StreamController<JsonRpcNotification>.broadcast(
      onListen: _onNotificationStreamListen,
    );
  }

  Future<SubscriptionsAcknowledgedNotification> get acknowledged =>
      _acknowledged.future;

  Stream<SubscriptionsAcknowledgedNotification> get acknowledgmentChanges =>
      _acknowledgmentChanges.stream;

  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  Future<SubscriptionsListenResult> get done => _done.future;

  void handleNotification(
    JsonRpcNotification notification, {
    bool isReplayAcknowledgment = false,
  }) {
    if (_closed) {
      return;
    }

    if (notification.method == Method.notificationsSubscriptionsAcknowledged) {
      final hadAcknowledgment = _acknowledgedNotifications != null;
      if (hadAcknowledgment && !isReplayAcknowledgment) {
        fail(
          McpError(
            ErrorCode.invalidRequest.value,
            'Subscription $id received '
            '${Method.notificationsSubscriptionsAcknowledged} more than once.',
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
      if (hadAcknowledgment && isReplayAcknowledgment) {
        _acknowledgmentChanges.add(acknowledgedParams);
      }
      return;
    }

    if (_serverCancellationReceived) {
      fail(
        McpError(
          ErrorCode.invalidRequest.value,
          'Subscription $id received ${notification.method} after '
          '${Method.notificationsCancelled}.',
        ),
        StackTrace.current,
      );
      return;
    }

    if (_acknowledgedNotifications == null) {
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

    if (_notificationStreamObserved) {
      _notifications.add(notification);
    } else {
      if (_pendingNotifications.length >= _maxPendingNotifications) {
        _pendingNotifications.clear();
        fail(
          McpError(
            ErrorCode.invalidRequest.value,
            'Subscription $id exceeded the '
            '$_maxPendingNotifications-notification buffer before its '
            'notification stream was listened to.',
          ),
          StackTrace.current,
        );
        return;
      }
      _pendingNotifications.add(notification);
    }
  }

  void handleServerCancellation() {
    if (_closed) {
      return;
    }
    if (_serverCancellationReceived) {
      fail(
        McpError(
          ErrorCode.invalidRequest.value,
          'Subscription $id received ${Method.notificationsCancelled} more '
          'than once.',
        ),
        StackTrace.current,
      );
      return;
    }
    if (_acknowledgedNotifications == null) {
      fail(
        McpError(
          ErrorCode.invalidRequest.value,
          'Subscription $id received ${Method.notificationsCancelled} before '
          '${Method.notificationsSubscriptionsAcknowledged}.',
        ),
        StackTrace.current,
      );
      return;
    }

    _serverCancellationReceived = true;
  }

  void _onNotificationStreamListen() {
    if (_notificationStreamObserved) {
      return;
    }
    _notificationStreamObserved = true;

    for (final notification in _pendingNotifications) {
      _notifications.add(notification);
    }
    _pendingNotifications.clear();

    final pendingError = _pendingNotificationError;
    if (pendingError != null) {
      _notifications.addError(pendingError.error, pendingError.stackTrace);
    }
    if (_notificationStreamShouldClose) {
      unawaited(_notifications.close());
    }
  }

  void _closeNotificationStream() {
    if (_notificationStreamObserved) {
      unawaited(_notifications.close());
    } else {
      _notificationStreamShouldClose = true;
    }
  }

  void _failNotificationStream(Object error, StackTrace stackTrace) {
    if (_notificationStreamObserved) {
      _notifications.addError(error, stackTrace);
      unawaited(_notifications.close());
    } else {
      _pendingNotificationError = (error: error, stackTrace: stackTrace);
      _notificationStreamShouldClose = true;
    }
  }

  void trackRequest(Future<SubscriptionsListenResult> requestDone) {
    requestDone.then(
      complete,
      onError: (Object error, StackTrace stackTrace) {
        if (_localCancellation) {
          complete(SubscriptionsListenResult(subscriptionId: id));
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
    complete(SubscriptionsListenResult(subscriptionId: id));
  }

  void complete(SubscriptionsListenResult result) {
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

    if (!_localCancellation && result.subscriptionId != id) {
      fail(
        McpError(
          ErrorCode.invalidRequest.value,
          'Subscription $id completed with mismatched '
          '${McpMetaKey.subscriptionId} ${result.subscriptionId}.',
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
    unawaited(_acknowledgmentChanges.close());
    _closeNotificationStream();
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
    unawaited(_acknowledgmentChanges.close());
    _failNotificationStream(error, stackTrace);
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
