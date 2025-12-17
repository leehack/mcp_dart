import 'dart:async';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.client");

/// Options for configuring the MCP [Client].
class ClientOptions extends ProtocolOptions {
  /// Capabilities to advertise as being supported by this client.
  final ClientCapabilities? capabilities;

  const ClientOptions({
    super.enforceStrictCapabilities,
    this.capabilities,
  });
}

/// Recursively applies default values from a JSON Schema to a data object.
/// Recursively applies default values from a JSON Schema to a data object.
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

// Unused _applyDefaultsFromMap removed

/// An MCP client implementation built on top of a pluggable [Transport].
///
/// Handles the initialization handshake with the server upon connection
/// and provides methods for making standard MCP requests.
class Client extends Protocol {
  ServerCapabilities? _serverCapabilities;
  Implementation? _serverVersion;
  ClientCapabilities _capabilities;
  final Implementation _clientInfo;
  String? _instructions;

  final Map<String, JsonSchema> _cachedToolOutputSchemas = {};
  final Set<String> _cachedRequiredTaskTools = {};

  /// Callback for handling elicitation requests from the server.
  ///
  /// This will be called when the server sends an `elicitation/create` request
  /// to collect structured user input. The client should prompt the user
  /// and return an [ElicitResult] with the action taken and content provided.
  Future<ElicitResult> Function(ElicitRequestParams)? onElicitRequest;

  /// Callback for handling task status notifications from the server.
  FutureOr<void> Function(TaskStatusNotificationParams params)? onTaskStatus;

  /// Callback for handling sampling requests from the server.
  ///
  /// This will be called when the server sends a `sampling/createMessage` request
  /// to request an LLM completion from the client.
  Future<CreateMessageResult> Function(CreateMessageRequestParams params)?
      onSamplingRequest;

  /// Initializes this client with its implementation details and options.
  ///
  /// - [_clientInfo]: Information about this client's name and version.
  /// - [options]: Optional configuration settings including client capabilities.
  Client(this._clientInfo, {ClientOptions? options})
      : _capabilities = options?.capabilities ?? const ClientCapabilities(),
        super(options) {
    // Register elicit handler if capability is present
    if (_capabilities.elicitation?.form != null) {
      setRequestHandler<JsonRpcElicitRequest>(
        Method.elicitationCreate,
        (request, extra) async {
          if (onElicitRequest == null) {
            throw McpError(
              ErrorCode.methodNotFound.value,
              "No elicit handler registered",
            );
          }
          final result = await onElicitRequest!(request.elicitParams);

          // Apply defaults if client supports it and it's a form elicitation
          if (request.elicitParams.mode == ElicitationMode.form &&
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
        (id, params, meta) => JsonRpcElicitRequest(
          id: id,
          elicitParams: ElicitRequestParams.fromJson(params ?? {}),
          meta: meta,
        ),
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
          statusParams: TaskStatusNotificationParams.fromJson(params ?? {}),
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
          return await onSamplingRequest!(request.createParams);
        },
        (id, params, meta) => JsonRpcCreateMessageRequest(
          id: id,
          createParams: CreateMessageRequestParams.fromJson(params ?? {}),
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

  /// Connects to the server using the given [transport].
  ///
  /// Initiates the MCP initialization handshake and processes the result.
  @override
  Future<void> connect(Transport transport) async {
    await super.connect(transport);

    if (transport.sessionId != null) {
      return;
    }

    try {
      final initParams = InitializeRequestParams(
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

      const initializedNotification = JsonRpcInitializedNotification();
      await notification(initializedNotification);

      _logger.debug(
        "MCP Client Initialized. Server: ${result.serverInfo.name} ${result.serverInfo.version}, Protocol: ${result.protocolVersion}",
      );
    } catch (error) {
      _logger.error("MCP Client Initialization Failed: $error");
      await close();
      rethrow;
    }
  }

  /// Gets the server's reported capabilities after successful initialization.
  ServerCapabilities? getServerCapabilities() => _serverCapabilities;

  /// Gets the server's reported implementation info after successful initialization.
  Implementation? getServerVersion() => _serverVersion;

  /// Gets the server's instructions provided during initialization, if any.
  String? getInstructions() => _instructions;

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
      case Method.toolsCall:
      case Method.toolsList:
        supported = serverCaps.tools != null;
        requiredCapability = 'tools';
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
    if (_serverCapabilities?.tasks == null) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        "Server does not support tasks capability (required for task-based '$method')",
      );
    }
  }

  @override
  void assertTaskHandlerCapability(String method) {
    if (_capabilities.tasks == null) {
      throw StateError(
        "Client setup error: Cannot handle task-based '$method' without 'tasks' capability registered.",
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
    CompleteRequestParams params, [
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
    final params = SetLevelRequestParams(level: level);
    final req = JsonRpcSetLevelRequest(id: -1, setParams: params);
    return request<EmptyResult>(req, (json) => const EmptyResult(), options);
  }

  /// Sends a `prompts/get` request to retrieve a specific prompt/template.
  Future<GetPromptResult> getPrompt(
    GetPromptRequestParams params, [
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
    ListPromptsRequestParams? params,
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
    ListResourcesRequestParams? params,
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
    ListResourceTemplatesRequestParams? params,
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
    ReadResourceRequestParams params, [
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
    SubscribeRequestParams params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcSubscribeRequest(id: -1, subParams: params);
    return request<EmptyResult>(req, (json) => const EmptyResult(), options);
  }

  /// Sends a `resources/unsubscribe` request to cancel a resource subscription.
  Future<EmptyResult> unsubscribeResource(
    UnsubscribeRequestParams params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcUnsubscribeRequest(id: -1, unsubParams: params);
    return request<EmptyResult>(req, (json) => const EmptyResult(), options);
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

    _cacheToolMetadata(result.tools);

    return result;
  }

  void _cacheToolMetadata(List<Tool> tools) {
    _cachedToolOutputSchemas.clear();
    _cachedRequiredTaskTools.clear();

    for (final tool in tools) {
      if (tool.outputSchema != null) {
        _cachedToolOutputSchemas[tool.name] = tool.outputSchema!;
      }

      if (tool.execution?.taskSupport == 'required') {
        _cachedRequiredTaskTools.add(tool.name);
      }
    }
  }

  /// Sends a `notifications/roots/list_changed` notification to the server.
  Future<void> sendRootsListChanged() {
    const notif = JsonRpcRootsListChangedNotification();
    return notification(notif);
  }
}
