import 'dart:async';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

Never _unsupported(String apiName) => throw UnsupportedError(
      '$apiName is only available on Dart IO platforms.',
    );

/// ID for SSE streams.
typedef StreamId = String;

/// ID for events in SSE streams.
typedef EventId = String;

/// Interface for resumability support via event storage.
abstract class EventStore {
  /// Stores an event for later retrieval.
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message);

  /// Replays events after a specified event ID.
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
        send,
  });
}

/// Simple in-memory event store for resumability.
class InMemoryEventStore implements EventStore {
  final Map<String, List<({EventId id, JsonRpcMessage message})>> _events = {};
  int _eventCounter = 0;

  @override
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message) async {
    final eventId = (++_eventCounter).toString();
    _events.putIfAbsent(streamId, () => []);
    _events[streamId]!.add((id: eventId, message: message));
    return eventId;
  }

  @override
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
        send,
  }) async {
    String? streamId;
    var fromIndex = -1;

    for (final entry in _events.entries) {
      final index = entry.value.indexWhere((event) => event.id == lastEventId);
      if (index >= 0) {
        streamId = entry.key;
        fromIndex = index;
        break;
      }
    }

    if (streamId == null) {
      throw StateError('Event ID not found: $lastEventId');
    }

    for (var i = fromIndex + 1; i < _events[streamId]!.length; i++) {
      final event = _events[streamId]![i];
      await send(event.id, event.message);
    }

    return streamId;
  }
}

/// Configuration options for StreamableHTTPServerTransport.
class StreamableHTTPServerTransportOptions {
  /// Function that generates a session ID for the transport.
  final String? Function()? sessionIdGenerator;

  /// A callback for session initialization events.
  final void Function(String sessionId)? onsessioninitialized;

  /// If true, the server will return JSON responses instead of SSE streams.
  final bool enableJsonResponse;

  /// Event store for resumability support.
  final EventStore? eventStore;

  /// Enables host/origin validation to mitigate DNS rebinding attacks.
  final bool enableDnsRebindingProtection;

  /// Explicit host allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedHosts;

  /// Explicit origin allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedOrigins;

  /// If true, reject unsupported `MCP-Protocol-Version` headers.
  final bool strictProtocolVersionHeaderValidation;

  /// If true, reject JSON-RPC batch payloads.
  final bool rejectBatchJsonRpcPayloads;

  /// The maximum number of events allowed during SSE resumption.
  final int maxReplayedEvents;

  /// Reconnection delay advertised in resumable SSE priming events.
  final Duration sseRetryDelay;

  /// Creates configuration options for StreamableHTTPServerTransport.
  StreamableHTTPServerTransportOptions({
    this.sessionIdGenerator,
    this.onsessioninitialized,
    this.enableJsonResponse = false,
    this.eventStore,
    this.enableDnsRebindingProtection = true,
    this.allowedHosts,
    this.allowedOrigins,
    this.strictProtocolVersionHeaderValidation = true,
    this.rejectBatchJsonRpcPayloads = true,
    this.maxReplayedEvents = 1000,
    this.sseRetryDelay = const Duration(seconds: 1),
  }) {
    if (sseRetryDelay.isNegative) {
      throw ArgumentError.value(
        sseRetryDelay,
        'sseRetryDelay',
        'Must not be negative',
      );
    }
  }
}

/// Stub for Streamable HTTP server transport on platforms without `dart:io`.
class StreamableHTTPServerTransport
    implements Transport, RequestIdAwareTransport {
  /// Creates a new StreamableHTTPServerTransport stub.
  StreamableHTTPServerTransport({required this.options});

  /// Transport options retained for API compatibility.
  final StreamableHTTPServerTransportOptions options;

  @override
  String? sessionId;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  Future<void> start() async =>
      _unsupported('StreamableHTTPServerTransport.start');

  /// Handles an incoming HTTP request on IO platforms.
  Future<void> handleRequest(Object request, [dynamic parsedBody]) async =>
      _unsupported('StreamableHTTPServerTransport.handleRequest');

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) =>
      sendWithRequestId(message, relatedRequestId: relatedRequestId);

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async =>
      _unsupported('StreamableHTTPServerTransport.send');
}

/// Server transport for SSE on IO platforms.
class SseServerTransport implements Transport {
  /// Creates a new SSE server transport stub.
  SseServerTransport({
    required Object response,
    required String messageEndpointPath,
  })  : _response = response,
        _messageEndpointPath = messageEndpointPath;

  final Object _response;
  final String _messageEndpointPath;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String get sessionId => _unsupported('SseServerTransport.sessionId');

  @override
  Future<void> start() async {
    // Touch constructor fields so analyzer does not flag them as unused.
    Object.hash(_response, _messageEndpointPath);
    _unsupported('SseServerTransport.start');
  }

  /// Handles incoming HTTP POST requests on IO platforms.
  Future<void> handlePostMessage(Object request, {dynamic parsedBody}) async =>
      _unsupported('SseServerTransport.handlePostMessage');

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async =>
      _unsupported('SseServerTransport.send');
}

/// Manages Server-Sent Events (SSE) connections and routes HTTP requests.
class SseServerManager {
  /// Creates an SSE server manager stub.
  SseServerManager(
    this.mcpServer, {
    this.ssePath = '/sse',
    this.messagePath = '/messages',
    this.enableDnsRebindingProtection = false,
    this.allowedHosts,
    this.allowedOrigins,
  });

  /// Map to store active SSE transports, keyed by session ID.
  final Map<String, SseServerTransport> activeSseTransports = {};

  /// The main MCP Server instance.
  final McpServer mcpServer;

  /// Path for establishing SSE connections.
  final String ssePath;

  /// Path for sending messages to the server.
  final String messagePath;

  /// Enables host/origin validation to mitigate DNS rebinding attacks.
  final bool enableDnsRebindingProtection;

  /// Explicit host allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedHosts;

  /// Explicit origin allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedOrigins;

  /// Routes incoming HTTP requests on IO platforms.
  Future<void> handleRequest(Object request) async =>
      _unsupported('SseServerManager.handleRequest');

  /// Handles the initial GET request to establish an SSE connection.
  Future<void> handleSseConnection(Object request) async =>
      _unsupported('SseServerManager.handleSseConnection');
}

/// Stub for stdio server transport on platforms without `dart:io`.
class StdioServerTransport implements Transport {
  /// Creates a new stdio server transport stub.
  StdioServerTransport({Object? stdin, Object? stdout})
      : _stdin = stdin,
        _stdout = stdout;

  final Object? _stdin;
  final Object? _stdout;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    Object.hash(_stdin, _stdout);
    _unsupported('StdioServerTransport.start');
  }

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async =>
      _unsupported('StdioServerTransport.send');
}

/// OAuth 2.0 Protected Resource Metadata advertised by a Streamable HTTP server.
class OAuthProtectedResourceMetadata {
  /// Canonical MCP resource URI that access tokens are issued for.
  final Uri resource;

  /// Authorization server issuer URLs that can issue tokens for [resource].
  final List<Uri> authorizationServers;

  /// Supported bearer token presentation methods.
  final List<String> bearerMethodsSupported;

  /// Scopes the resource server can advertise to clients.
  final List<String>? scopesSupported;

  /// Additional metadata fields to include in the protected-resource document.
  final Map<String, Object?> additionalFields;

  /// Creates OAuth protected-resource metadata.
  const OAuthProtectedResourceMetadata({
    required this.resource,
    required this.authorizationServers,
    this.bearerMethodsSupported = const ['header'],
    this.scopesSupported,
    this.additionalFields = const {},
  });

  /// Converts this metadata to its wire JSON shape.
  Map<String, Object?> toJson() => {
        ...additionalFields,
        'resource': resource.toString(),
        'authorization_servers':
            authorizationServers.map((uri) => uri.toString()).toList(),
        'bearer_methods_supported': bearerMethodsSupported,
        if (scopesSupported != null) 'scopes_supported': scopesSupported,
      };
}

/// Bearer `WWW-Authenticate` challenge parameters for OAuth resource servers.
class OAuthBearerChallenge {
  /// Protected-resource metadata URL advertised through `resource_metadata`.
  final Uri? resourceMetadata;

  /// Scope required for the failed request.
  final String? scope;

  /// OAuth bearer error code, such as `insufficient_scope`.
  final String? error;

  /// Optional human-readable bearer error description.
  final String? errorDescription;

  /// Additional bearer challenge parameters.
  final Map<String, String> additionalParameters;

  /// Creates a bearer challenge.
  const OAuthBearerChallenge({
    this.resourceMetadata,
    this.scope,
    this.error,
    this.errorDescription,
    this.additionalParameters = const {},
  });

  /// Creates the challenge recommended for insufficient-scope responses.
  const OAuthBearerChallenge.insufficientScope({
    required Uri resourceMetadata,
    required String scope,
    String? errorDescription,
    Map<String, String> additionalParameters = const {},
  }) : this(
          resourceMetadata: resourceMetadata,
          scope: scope,
          error: 'insufficient_scope',
          errorDescription: errorDescription,
          additionalParameters: additionalParameters,
        );

  /// Converts this challenge to a `WWW-Authenticate` header value.
  String toHeaderValue() {
    final parameters = <String, String>{
      ...additionalParameters,
      if (resourceMetadata != null)
        'resource_metadata': resourceMetadata.toString(),
      if (scope != null) 'scope': scope!,
      if (error != null) 'error': error!,
      if (errorDescription != null) 'error_description': errorDescription!,
    };
    final serializedParameters = parameters.entries
        .map((entry) => '${entry.key}="${_quoteHeaderValue(entry.value)}"')
        .join(', ');
    return serializedParameters.isEmpty
        ? 'Bearer'
        : 'Bearer $serializedParameters';
  }
}

String _quoteHeaderValue(String value) {
  const backslash = '\\';
  const escapedBackslash = '\\\\';
  const quote = '"';
  const escapedQuote = r'\"';
  return value
      .replaceAll(backslash, escapedBackslash)
      .replaceAll(quote, escapedQuote);
}

/// OAuth protected-resource behavior for [StreamableMcpServer].
class OAuthProtectedResourceOptions {
  /// Metadata returned from protected-resource well-known endpoints.
  final OAuthProtectedResourceMetadata metadata;

  /// Public protected-resource metadata URL advertised in bearer challenges.
  final Uri? metadataUri;

  /// Optional scope challenge returned on unauthorized requests.
  final String? scope;

  /// Optional endpoint-specific metadata path.
  final String? metadataPath;

  /// Also serve metadata at the root protected-resource well-known endpoint.
  final bool serveRootMetadata;

  /// Creates OAuth protected-resource server options.
  const OAuthProtectedResourceOptions({
    required this.metadata,
    this.metadataUri,
    this.scope,
    this.metadataPath,
    this.serveRootMetadata = true,
  });
}

/// Result returned by [StreamableMcpServer.authenticationHandler].
class StreamableMcpAuthenticationResult {
  // Mirrors the IO implementation's private state for const constructor shape.
  // ignore: unused_field
  final _StreamableMcpAuthenticationStatus _status;

  /// Scope required for an insufficient-scope response.
  final String? scope;

  /// Optional human-readable bearer error description.
  final String? errorDescription;

  /// Additional bearer challenge parameters.
  final Map<String, String> additionalChallengeParameters;

  const StreamableMcpAuthenticationResult._(
    this._status, {
    this.scope,
    this.errorDescription,
    this.additionalChallengeParameters = const {},
  });

  /// Allows the request to proceed.
  const StreamableMcpAuthenticationResult.allow()
      : this._(_StreamableMcpAuthenticationStatus.allow);

  /// Rejects the request as unauthenticated or invalidly authenticated.
  const StreamableMcpAuthenticationResult.unauthorized({
    String? errorDescription,
    Map<String, String> additionalChallengeParameters = const {},
  }) : this._(
          _StreamableMcpAuthenticationStatus.unauthorized,
          errorDescription: errorDescription,
          additionalChallengeParameters: additionalChallengeParameters,
        );

  /// Rejects the request because the presented token lacks required scope.
  const StreamableMcpAuthenticationResult.insufficientScope({
    required String scope,
    String? errorDescription,
    Map<String, String> additionalChallengeParameters = const {},
  }) : this._(
          _StreamableMcpAuthenticationStatus.insufficientScope,
          scope: scope,
          errorDescription: errorDescription,
          additionalChallengeParameters: additionalChallengeParameters,
        );
}

enum _StreamableMcpAuthenticationStatus {
  allow,
  unauthorized,
  insufficientScope,
}

/// A high-level server implementation that manages sessions over Streamable HTTP.
class StreamableMcpServer {
  /// Default port used by the IO implementation.
  static const int defaultPort = 3000;

  /// Creates a high-level Streamable HTTP server stub.
  StreamableMcpServer({
    required McpServer Function(String sessionId) serverFactory,
    this.host = 'localhost',
    this.port = defaultPort,
    this.path = '/mcp',
    this.eventStore,
    this.authenticator,
    this.authenticationHandler,
    this.oauthProtectedResource,
    this.enableDnsRebindingProtection = true,
    this.allowedHosts,
    this.allowedOrigins,
    this.strictProtocolVersionHeaderValidation = true,
    this.rejectBatchJsonRpcPayloads = true,
    this.enableJsonResponse = false,
    this.sseRetryDelay = const Duration(seconds: 1),
  }) : _serverFactory = serverFactory {
    if (sseRetryDelay.isNegative) {
      throw ArgumentError.value(
        sseRetryDelay,
        'sseRetryDelay',
        'Must not be negative',
      );
    }
  }

  final McpServer Function(String sessionId) _serverFactory;

  /// Host to bind the HTTP server to on IO platforms.
  final String host;

  /// Port to bind the HTTP server to on IO platforms.
  final int port;

  /// Path to listen for MCP requests on.
  final String path;

  /// Event store for resumability support.
  final EventStore? eventStore;

  /// Optional callback to authenticate requests.
  final FutureOr<bool> Function(dynamic request)? authenticator;

  /// Optional callback that can return detailed authentication failures.
  final FutureOr<StreamableMcpAuthenticationResult> Function(dynamic request)?
      authenticationHandler;

  /// Optional OAuth protected-resource metadata and challenge behavior.
  final OAuthProtectedResourceOptions? oauthProtectedResource;

  /// Enables host/origin validation to mitigate DNS rebinding attacks.
  final bool enableDnsRebindingProtection;

  /// Explicit host allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedHosts;

  /// Explicit origin allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedOrigins;

  /// If true, reject unsupported `MCP-Protocol-Version` headers.
  final bool strictProtocolVersionHeaderValidation;

  /// If true, reject JSON-RPC batch payloads.
  final bool rejectBatchJsonRpcPayloads;

  /// If true, return JSON responses instead of SSE streams for request/response
  /// interactions.
  final bool enableJsonResponse;

  /// Reconnection delay advertised in resumable SSE priming events.
  final Duration sseRetryDelay;

  /// Port currently bound by the HTTP server.
  ///
  /// Web/default stubs never bind a server, so this mirrors the configured port.
  int get boundPort => port;

  /// Starts the HTTP server on IO platforms.
  Future<void> start() async {
    // Touch constructor fields so analyzer does not flag them as unused without
    // invoking user-provided callbacks on unsupported platforms.
    Object.hash(
      _serverFactory,
      host,
      port,
      path,
      eventStore,
      authenticator,
      authenticationHandler,
      oauthProtectedResource,
      enableDnsRebindingProtection,
      allowedHosts,
      allowedOrigins,
      strictProtocolVersionHeaderValidation,
      rejectBatchJsonRpcPayloads,
      enableJsonResponse,
      sseRetryDelay,
    );
    _unsupported('StreamableMcpServer.start');
  }

  /// Stops the HTTP server and closes active sessions.
  Future<void> stop() async {}
}
