/// Stub implementation of server functionality for web platform.
///
/// MCP server functionality is not available in web browsers. This stub provides
/// the same API surface but throws appropriate errors when used.
library;

import 'dart:async';

import '../shared/transport.dart';
import '../shared/protocol.dart';
import '../types.dart';
import 'mcp.dart';

/// Options for configuring the MCP [Server].
class ServerOptions {
  /// Capabilities to advertise as being supported by this server.
  final ServerCapabilities? capabilities;

  /// Optional instructions describing how to use the server and its features.
  final String? instructions;

  /// Creates server options.
  const ServerOptions({
    this.capabilities,
    this.instructions,
  });
}

/// MCP server implementation for handling client connections.
///
/// This class is not available on web platforms as servers require
/// native I/O capabilities not available in browser environments.
class Server {
  /// Callback invoked when initialization has fully completed.
  void Function()? oninitialized;

  /// Stub constructor that throws on web platforms.
  Server(
    Implementation serverInfo, {
    ServerOptions? options,
  }) {
    throw UnsupportedError(
      'Server is not supported on web platforms. '
      'MCP servers require native I/O capabilities.',
    );
  }

  /// Registers request handler (stub)
  void setRequestHandler<ReqT extends JsonRpcRequest>(
    String method,
    Future<BaseResultData> Function(ReqT request, RequestHandlerExtra extra)
        handler,
    ReqT Function(RequestId id, Map<String, dynamic>? params,
            Map<String, dynamic>? meta)
        requestFactory,
  ) {
    throw UnsupportedError(
        'Server.setRequestHandler is not supported on web platforms.');
  }

  /// Connects to transport (stub)
  Future<void> connect(Transport transport) {
    throw UnsupportedError('Server.connect is not supported on web platforms.');
  }

  /// Registers new capabilities (stub)
  void registerCapabilities(ServerCapabilities capabilities) {
    throw UnsupportedError(
        'Server.registerCapabilities is not supported on web platforms.');
  }

  /// Gets client capabilities (stub)
  ClientCapabilities? getClientCapabilities() {
    throw UnsupportedError(
        'Server.getClientCapabilities is not supported on web platforms.');
  }

  /// Gets server capabilities (stub)
  ServerCapabilities getCapabilities() {
    throw UnsupportedError(
        'Server.getCapabilities is not supported on web platforms.');
  }

  /// Closes the server (stub)
  Future<void> close() {
    throw UnsupportedError('Server.close is not supported on web platforms.');
  }
}

/// Server-Sent Events (SSE) implementation for streaming data.
///
/// This class is not available on web platforms.
class ServerSentEvent {
  /// Stub constructor that throws on web platforms.
  ServerSentEvent({
    String? data,
    String? event,
    String? id,
  }) {
    throw UnsupportedError(
      'ServerSentEvent is not supported on web platforms.',
    );
  }
}

/// SSE transport for server communication.
///
/// This transport is not available on web platforms.
class SseTransport extends Transport {
  /// Stub constructor that throws on web platforms.
  SseTransport() {
    throw UnsupportedError(
      'SseTransport is not supported on web platforms.',
    );
  }

  @override
  String? get sessionId => throw UnsupportedError(
        'SseTransport is not supported on web platforms.',
      );

  @override
  Future<void> start() => throw UnsupportedError(
        'SseTransport is not supported on web platforms.',
      );

  @override
  Future<void> send(JsonRpcMessage message) => throw UnsupportedError(
        'SseTransport is not supported on web platforms.',
      );

  @override
  Future<void> close() => throw UnsupportedError(
        'SseTransport is not supported on web platforms.',
      );
}

/// Streamable HTTPS server transport options.
///
/// This class is not available on web platforms.
class StreamableHTTPServerTransportOptions {
  /// Stub constructor that throws on web platforms.
  StreamableHTTPServerTransportOptions({
    String? Function()? sessionIdGenerator,
    void Function(String sessionId)? onsessioninitialized,
    bool enableJsonResponse = false,
    dynamic eventStore,
  }) {
    throw UnsupportedError(
      'StreamableHTTPServerTransportOptions is not supported on web platforms.',
    );
  }
}

/// Streamable HTTPS server transport.
///
/// This transport is not available on web platforms.
class StreamableHTTPServerTransport extends Transport {
  /// Stub constructor that throws on web platforms.
  StreamableHTTPServerTransport({
    StreamableHTTPServerTransportOptions? options,
  }) {
    throw UnsupportedError(
      'StreamableHTTPServerTransport is not supported on web platforms.',
    );
  }

  @override
  String? get sessionId => throw UnsupportedError(
        'StreamableHTTPServerTransport is not supported on web platforms.',
      );

  @override
  Future<void> start() => throw UnsupportedError(
        'StreamableHTTPServerTransport is not supported on web platforms.',
      );

  @override
  Future<void> send(JsonRpcMessage message) => throw UnsupportedError(
        'StreamableHTTPServerTransport is not supported on web platforms.',
      );

  @override
  Future<void> close() => throw UnsupportedError(
        'StreamableHTTPServerTransport is not supported on web platforms.',
      );

  /// Handle request (stub)
  Future<void> handleRequest(dynamic req, [dynamic parsedBody]) async {
    throw UnsupportedError(
        'StreamableHTTPServerTransport.handleRequest is not supported on web platforms.');
  }
}

/// Stdio server transport.
///
/// This transport is not available on web platforms.
class StdioServerTransport extends Transport {
  /// Stub constructor that throws on web platforms.
  StdioServerTransport() {
    throw UnsupportedError(
      'StdioServerTransport is not supported on web platforms.',
    );
  }

  @override
  String? get sessionId => throw UnsupportedError(
        'StdioServerTransport is not supported on web platforms.',
      );

  @override
  Future<void> start() => throw UnsupportedError(
        'StdioServerTransport is not supported on web platforms.',
      );

  @override
  Future<void> send(JsonRpcMessage message) => throw UnsupportedError(
        'StdioServerTransport is not supported on web platforms.',
      );

  @override
  Future<void> close() => throw UnsupportedError(
        'StdioServerTransport is not supported on web platforms.',
      );
}

/// MCP protocol utilities.
///
/// Basic protocol utilities remain available on web for client use.
class McpProtocol {
  /// Creates a JSON-RPC request with the given method and parameters.
  static JsonRpcRequest createRequest(String method,
      [Map<String, dynamic>? params]) {
    throw UnsupportedError(
      'McpProtocol server utilities are not supported on web platforms.',
    );
  }
}

/// SSE server manager for handling multiple connections.
///
/// This class is not available on web platforms.
class SseServerManager {
  /// Stub constructor that throws on web platforms.
  SseServerManager(
    dynamic mcpServer, {
    String ssePath = '/sse',
    String messagePath = '/messages',
  }) {
    throw UnsupportedError(
      'SseServerManager is not supported on web platforms.',
    );
  }

  /// Handle request (stub)
  Future<void> handleRequest(dynamic req, [dynamic parsedBody]) async {
    throw UnsupportedError(
        'StreamableHTTPServerTransport.handleRequest is not supported on web platforms.');
  }
}

/// MCP server with higher-level helper methods.
///
/// This class is not available on web platforms as servers require
/// native I/O capabilities not available in browser environments.
class McpServer {
  /// The underlying server instance
  Server get server => throw UnsupportedError(
      'McpServer.server is not supported on web platforms.');

  /// Stub constructor that throws on web platforms.
  McpServer(Implementation serverInfo, {ServerOptions? options}) {
    throw UnsupportedError(
      'McpServer is not supported on web platforms. '
      'MCP servers require native I/O capabilities.',
    );
  }

  /// Registers a tool (stub)
  void tool(
    String name, {
    String? description,
    Map<String, dynamic>? inputSchemaProperties,
    Map<String, dynamic>? outputSchemaProperties,
    ToolAnnotations? annotations,
    required ToolCallback callback,
  }) {
    throw UnsupportedError('McpServer.tool is not supported on web platforms.');
  }

  /// Registers a resource (stub)
  void resource(
    String name,
    String uri,
    ReadResourceCallback readCallback, {
    ResourceMetadata? metadata,
  }) {
    throw UnsupportedError(
        'McpServer.resource is not supported on web platforms.');
  }

  /// Registers a prompt (stub)
  void prompt(
    String name, {
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    PromptCallback? callback,
  }) {
    throw UnsupportedError(
        'McpServer.prompt is not supported on web platforms.');
  }

  /// Connects the server to a communication [transport] (stub)
  Future<void> connect(Transport transport) async {
    throw UnsupportedError(
        'McpServer.connect is not supported on web platforms.');
  }
}

/// Prompt argument definition (stub)
class PromptArgumentDefinition {
  PromptArgumentDefinition({
    String? description,
    bool required = false,
    Type type = String,
    dynamic completable,
  }) {
    throw UnsupportedError(
        'PromptArgumentDefinition is not supported on web platforms.');
  }
}

/// Event ID for server-sent events (type alias)
typedef EventId = String;

/// Stream ID for server transports (type alias)
typedef StreamId = String;

// Export all the same classes that the real server module exports
// This ensures API compatibility while providing web-safe stubs

/// Alias for ServerSentEvent to match sse.dart exports
typedef SSE = ServerSentEvent;

/// Alias for SseTransport to match sse.dart exports
typedef SseServerTransport = SseTransport;

/// Alias for StdioServerTransport to match stdio.dart exports
// Already defined above

/// Event store interface (stub)
abstract class EventStore {
  const EventStore();

  /// Stores an event for later retrieval (stub)
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message) {
    throw UnsupportedError(
        'EventStore.storeEvent is not supported on web platforms.');
  }

  /// Replays events after a specified event ID (stub)
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
        send,
  }) {
    throw UnsupportedError(
        'EventStore.replayEventsAfter is not supported on web platforms.');
  }
}
