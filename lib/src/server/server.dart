import 'dart:async';

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

  /// Creates server options.
  const ServerOptions({
    super.enforceStrictCapabilities,
    this.capabilities,
    this.instructions,
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

  /// Callback invoked when initialization has fully completed.
  void Function()? oninitialized;

  /// Initializes this server with its implementation details and options.
  Server(this._serverInfo, {ServerOptions? options})
      : _capabilities = options?.capabilities ?? const ServerCapabilities(),
        _instructions = options?.instructions,
        super(options) {
    setRequestHandler<JsonRpcInitializeRequest>(
      "initialize",
      (request, extra) async => _oninitialize(request.initParams),
      (id, params, meta) => JsonRpcInitializeRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setNotificationHandler<JsonRpcInitializedNotification>(
      "notifications/initialized",
      (notification) async => oninitialized?.call(),
      (params, meta) => JsonRpcInitializedNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );
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
    _capabilities = ServerCapabilities.fromJson(
      mergeCapabilities<Map<String, dynamic>>(
        _capabilities.toJson(),
        capabilities.toJson(),
      ),
    );
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
      case "sampling/createMessage":
        if (!(_clientCapabilities?.sampling != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support sampling (required for server to send $method)",
          );
        }
        break;

      case "roots/list":
        if (!(_clientCapabilities?.roots != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support listing roots (required for server to send $method)",
          );
        }
        break;

      case "elicitation/create":
        if (!(_clientCapabilities?.elicitation != null)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            "Client does not support elicitation (required for server to send $method)",
          );
        }
        break;

      case "ping":
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
      case "notifications/message":
        if (!(_capabilities.logging != null)) {
          throw StateError(
            "Server does not support logging capability (required for sending $method)",
          );
        }
        break;

      case "notifications/resources/updated":
        if (!(_capabilities.resources?.subscribe ?? false)) {
          throw StateError(
            "Server does not support resource subscription capability (required for sending $method)",
          );
        }
        break;

      case "notifications/resources/list_changed":
        if (!(_capabilities.resources?.listChanged ?? false)) {
          throw StateError(
            "Server does not support resource list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case "notifications/tools/list_changed":
        if (!(_capabilities.tools?.listChanged ?? false)) {
          throw StateError(
            "Server does not support tool list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case "notifications/prompts/list_changed":
        if (!(_capabilities.prompts?.listChanged ?? false)) {
          throw StateError(
            "Server does not support prompt list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case "notifications/completions/list_changed":
        if (!(_capabilities.completions?.listChanged ?? false)) {
          throw StateError(
            "Server does not support completion list changed notifications capability (required for sending $method)",
          );
        }
        break;

      case "notifications/cancelled":
      case "notifications/progress":
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
      case "initialize":
      case "ping":
      case "completion/complete":
        break;

      case "logging/setLevel":
        if (!(_capabilities.logging != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'logging' capability",
          );
        }
        break;

      case "prompts/get":
      case "prompts/list":
        if (!(_capabilities.prompts != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'prompts' capability",
          );
        }
        break;

      case "resources/list":
      case "resources/templates/list":
      case "resources/read":
        if (!(_capabilities.resources != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'resources' capability",
          );
        }
        break;

      case "resources/subscribe":
      case "resources/unsubscribe":
        if (!(_capabilities.resources?.subscribe ?? false)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'resources.subscribe' capability",
          );
        }
        break;

      case "tools/call":
      case "tools/list":
        if (!(_capabilities.tools != null)) {
          throw StateError(
            "Server setup error: Cannot handle '$method' without 'tools' capability",
          );
        }
        break;

      case "tasks/list":
      case "tasks/cancel":
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
      JsonRpcPingRequest(id: -1),
      (json) => const EmptyResult(),
      options,
    );
  }

  /// Sends a `sampling/createMessage` request to the client to ask it to sample an LLM.
  Future<CreateMessageResult> createMessage(
    CreateMessageRequestParams params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcCreateMessageRequest(id: -1, createParams: params);
    return request<CreateMessageResult>(
      req,
      (json) => CreateMessageResult.fromJson(json),
      options,
    );
  }

  /// Sends a `roots/list` request to the client to ask for its root URIs.
  Future<ListRootsResult> listRoots({RequestOptions? options}) {
    final req = JsonRpcListRootsRequest(id: -1);
    return request<ListRootsResult>(
      req,
      (json) => ListRootsResult.fromJson(json),
      options,
    );
  }

  /// Sends a `notifications/message` (logging) notification to the client.
  Future<void> sendLoggingMessage(LoggingMessageNotificationParams params) {
    final notif = JsonRpcLoggingMessageNotification(logParams: params);
    return notification(notif);
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
