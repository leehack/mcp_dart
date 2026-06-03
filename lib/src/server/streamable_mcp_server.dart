import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/server/dns_rebinding_protection.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/mcp_header_validation.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';

const List<String> _defaultCorsAllowedHeaders = [
  'Origin',
  'X-Requested-With',
  'Content-Type',
  'Accept',
  'mcp-session-id',
  'Last-Event-ID',
  'Authorization',
  'MCP-Protocol-Version',
  'Mcp-Method',
  'Mcp-Name',
];

String _quoteHeaderValue(String value) {
  const backslash = '\\';
  const escapedBackslash = '\\\\';
  const quote = '"';
  const escapedQuote = r'\"';
  return value
      .replaceAll(backslash, escapedBackslash)
      .replaceAll(quote, escapedQuote);
}

/// OAuth 2.0 Protected Resource Metadata advertised by a Streamable HTTP server.
///
/// This metadata follows the MCP authorization profile for HTTP transports and
/// is served from the OAuth protected-resource well-known endpoint when
/// [StreamableMcpServer.oauthProtectedResource] is configured.
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

/// OAuth protected-resource behavior for [StreamableMcpServer].
class OAuthProtectedResourceOptions {
  /// Metadata returned from protected-resource well-known endpoints.
  final OAuthProtectedResourceMetadata metadata;

  /// Public protected-resource metadata URL advertised in bearer challenges.
  ///
  /// Defaults to the request-derived URL for [metadataPath]. Set this when the
  /// server is behind a reverse proxy or TLS terminator that rewrites the
  /// scheme, host, or port seen by Dart.
  final Uri? metadataUri;

  /// Optional scope challenge returned on unauthorized requests.
  final String? scope;

  /// Optional endpoint-specific metadata path.
  ///
  /// Defaults to `/.well-known/oauth-protected-resource` plus the MCP endpoint
  /// path, for example `/.well-known/oauth-protected-resource/mcp`.
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

  bool get _allowed => _status == _StreamableMcpAuthenticationStatus.allow;
}

enum _StreamableMcpAuthenticationStatus {
  allow,
  unauthorized,
  insufficientScope,
}

/// A high-level server implementation that manages multiple MCP sessions over Streamable HTTP.
///
/// This server handles:
/// - HTTP server lifecycle (bind, listen, close)
/// - Session management (creation, retrieval, cleanup)
/// - Routing of MCP requests (POST) and SSE streams (GET)
/// - Authentication (optional)
///
/// Usage:
/// ```dart
/// final server = StreamableMcpServer(
///   serverFactory: (sessionId) {
///     return McpServer(
///       Implementation(name: 'my-server', version: '1.0.0'),
///     )..tool(...);
///   },
///   host: 'localhost',
///   port: 3000,
/// );
/// await server.start();
/// ```
class StreamableMcpServer {
  static final Logger _logger = Logger('StreamableMcpServer');
  static const int defaultPort = 3000;
  static const String defaultCorsMaxAgeSeconds = '86400';

  /// Factory to create a new MCP server instance for a given session.
  final McpServer Function(String sessionId) _serverFactory;

  /// Host to bind the HTTP server to.
  final String host;

  /// Port to bind the HTTP server to.
  final int port;

  /// Port currently bound by the HTTP server.
  ///
  /// This differs from [port] when the server was configured with `port: 0`
  /// and the operating system selected an available port during [start].
  int get boundPort => _httpServer?.port ?? port;

  /// Path to listen for MCP requests on.
  final String path;

  /// Event store for resumability support.
  final EventStore? eventStore;

  /// Optional callback to authenticate requests.
  /// Returns true if the request is allowed, false otherwise.
  final FutureOr<bool> Function(HttpRequest request)? authenticator;

  /// Optional callback that can return detailed authentication failures.
  ///
  /// Use this instead of [authenticator] when a server needs to distinguish
  /// invalid/missing credentials from OAuth insufficient-scope failures.
  final FutureOr<StreamableMcpAuthenticationResult> Function(
    HttpRequest request,
  )? authenticationHandler;

  /// Optional OAuth protected-resource metadata and challenge behavior.
  ///
  /// When configured, the server serves OAuth Protected Resource Metadata and
  /// failed [authenticator] checks return a `401 Unauthorized` bearer challenge
  /// with a `resource_metadata` URL. Without this option, failed authentication
  /// preserves the historical generic `403 Forbidden` response.
  final OAuthProtectedResourceOptions? oauthProtectedResource;

  /// Enables host/origin validation to mitigate DNS rebinding attacks.
  final bool enableDnsRebindingProtection;

  /// Explicit host allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedHosts;

  /// Explicit origin allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedOrigins;

  /// If true, reject unsupported `MCP-Protocol-Version` headers with HTTP 400.
  final bool strictProtocolVersionHeaderValidation;

  /// If true, reject JSON-RPC batch payloads for Streamable HTTP POST requests.
  final bool rejectBatchJsonRpcPayloads;

  /// If true, return JSON responses instead of SSE streams for request/response
  /// interactions.
  final bool enableJsonResponse;

  final Set<String> _defaultDnsRebindingAllowedHosts;

  HttpServer? _httpServer;
  final Map<String, StreamableHTTPServerTransport> _transports = {};
  // Keep track of servers to close them if needed, though closing transport usually suffices
  final Map<String, McpServer> _servers = {};

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
  })  : _serverFactory = serverFactory,
        _defaultDnsRebindingAllowedHosts = {
          normalizeDnsHost(host),
          ...defaultDnsRebindingAllowedHosts,
        };

  /// Starts the HTTP server.
  Future<void> start() async {
    if (_httpServer != null) {
      throw StateError('Server already started');
    }

    _httpServer = await HttpServer.bind(host, port);
    _logger.info(
      'MCP Streamable HTTP Server listening on http://$host:$boundPort$path',
    );

    final httpServer = _httpServer;
    if (httpServer == null) {
      throw StateError('HTTP server not initialized');
    }
    httpServer.listen(_handleRequest);
  }

  /// Stops the HTTP server and closes all active sessions.
  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;

    // Close all transports
    for (final transport in _transports.values) {
      await transport.close();
    }
    _transports.clear();
    _servers.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _setCorsHeaders(request, request.response);

    if (enableDnsRebindingProtection &&
        !isRequestAllowedByDnsRebindingProtection(
          request,
          allowedHosts: allowedHosts,
          allowedOrigins: allowedOrigins,
          defaultAllowedHosts: _defaultDnsRebindingAllowedHosts,
        )) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden: blocked by DNS rebinding protection');
      await request.response.close();
      return;
    }

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (_isProtectedResourceMetadataRequest(request)) {
      await _handleProtectedResourceMetadataRequest(request);
      return;
    }

    if (request.uri.path != path) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
      return;
    }

    final authenticationHandler = this.authenticationHandler;
    if (authenticationHandler != null) {
      StreamableMcpAuthenticationResult authResult;
      try {
        authResult = await authenticationHandler(request);
      } catch (e) {
        _logger.error('Authentication error: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Authentication Error')
          ..close();
        return;
      }

      if (!authResult._allowed) {
        await _respondAuthenticationFailure(request, authResult);
        return;
      }
    } else if (authenticator != null) {
      bool allowed = false;
      try {
        allowed = await authenticator!(request);
      } catch (e) {
        _logger.error('Authentication error: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Authentication Error')
          ..close();
        return;
      }

      if (!allowed) {
        await _respondUnauthorized(request);
        return;
      }
    }

    try {
      if (request.method == 'POST') {
        await _handlePostRequest(request);
      } else if (_requiresStatelessTransport(request)) {
        await _createStatelessTransport().handleRequest(request);
      } else if (request.method == 'GET') {
        await _handleGetRequest(request);
      } else if (request.method == 'DELETE') {
        await _handleDeleteRequest(request);
      } else {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set(HttpHeaders.allowHeader, 'GET, POST, DELETE, OPTIONS')
          ..write('Method Not Allowed')
          ..close();
      }
    } catch (e, stack) {
      _logger.error('Error handling request: $e\n$stack');
      if (!request.response.headers.contentType
          .toString()
          .startsWith('text/event-stream')) {
        try {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Internal Server Error')
            ..close();
        } catch (_) {
          // Response might be already closed
        }
      }
    }
  }

  Future<void> _handlePostRequest(HttpRequest request) async {
    // We need to read the body to determine if it's an initialization request
    // or a request for an existing session.
    // However, StreamableHTTPServerTransport.handleRequest expects to read the body itself
    // OR be passed the parsed body.
    // To support the routing logic (new vs existing session), we must read it here.

    final sessionId = request.headers.value('mcp-session-id');

    final bodyBytes = await _collectBytes(request);
    final bodyString = utf8.decode(bodyBytes);
    dynamic body;
    try {
      body = jsonDecode(bodyString);
    } catch (e) {
      if (sessionId != null &&
          !_transports.containsKey(sessionId) &&
          !_requiresStatelessTransport(request)) {
        await _respondWithJsonRpcError(
          request.response,
          httpStatus: HttpStatus.notFound,
          errorCode: ErrorCode.connectionClosed,
          message: 'Session not found',
        );
        return;
      }
      await _respondWithJsonRpcError(
        request.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.parseError,
        message: 'Parse error',
      );
      return;
    }

    if (rejectBatchJsonRpcPayloads && body is List) {
      await _respondWithJsonRpcError(
        request.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidRequest,
        message: 'Invalid Request: Batch JSON-RPC payloads are not supported',
      );
      return;
    }

    if (body is! Map && body is! List) {
      await _respondWithJsonRpcError(
        request.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidRequest,
        message:
            'Invalid Request: POST body must contain a JSON-RPC message object',
      );
      return;
    }

    final isStatelessRequest = _isStatelessRequest(request, body);
    if (sessionId != null &&
        !_transports.containsKey(sessionId) &&
        !isStatelessRequest) {
      await _respondWithJsonRpcError(
        request.response,
        httpStatus: HttpStatus.notFound,
        errorCode: ErrorCode.connectionClosed,
        message: 'Session not found',
      );
      return;
    }

    StreamableHTTPServerTransport? transport;

    if (isStatelessRequest) {
      transport = _createStatelessTransport();
      final server = _serverFactory('');
      await server.connect(transport);
      await transport.handleRequest(request, body);
      return;
    } else if (sessionId != null) {
      transport = _transports[sessionId]!;
    } else if (_isInitializeRequest(body)) {
      // New initialization request
      transport = _createTransport();

      // We need to pass the body we already read to the transport
      await transport.handleRequest(request, body);
      return;
    } else {
      await _respondWithJsonRpcError(
        request.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.connectionClosed,
        message:
            'Bad Request: No valid session ID provided or not an initialization request',
      );
      return;
    }

    // Handle the request with existing transport
    await transport.handleRequest(request, body);
  }

  Future<void> _handleGetRequest(HttpRequest request) async {
    if (_requiresStatelessTransport(request)) {
      await _createStatelessTransport().handleRequest(request);
      return;
    }

    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing session ID')
        ..close();
      return;
    }
    if (!_transports.containsKey(sessionId)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Session not found')
        ..close();
      return;
    }

    final transport = _transports[sessionId]!;
    await transport.handleRequest(request);
  }

  Future<void> _handleDeleteRequest(HttpRequest request) async {
    if (_requiresStatelessTransport(request)) {
      await _createStatelessTransport().handleRequest(request);
      return;
    }

    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing session ID')
        ..close();
      return;
    }
    if (!_transports.containsKey(sessionId)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Session not found')
        ..close();
      return;
    }

    final transport = _transports[sessionId]!;
    await transport.handleRequest(request);
  }

  StreamableHTTPServerTransport _createTransport() {
    late StreamableHTTPServerTransport transport;

    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: () => generateUUID(),
        eventStore: eventStore,
        enableDnsRebindingProtection: enableDnsRebindingProtection,
        allowedHosts: allowedHosts ?? {host},
        allowedOrigins: allowedOrigins,
        enableJsonResponse: enableJsonResponse,
        strictProtocolVersionHeaderValidation:
            strictProtocolVersionHeaderValidation,
        rejectBatchJsonRpcPayloads: rejectBatchJsonRpcPayloads,
        onsessioninitialized: (sid) {
          _logger.info('Session initialized: $sid');
          _transports[sid] = transport;

          // Create and connect the MCP server
          final server = _serverFactory(sid);
          _servers[sid] = server;

          // Connect server to transport
          // Note: connect() is async, but onsessioninitialized is sync.
          // This usually works because the transport handles the immediate request
          // and the server will be hooked up for subsequent messages or the current one
          // if handleRequest logic flows correctly.
          // However, for initialization, the Server needs to be connected to handle the
          // 'initialize' message that is currently being processed.
          //
          // StreamableHTTPServerTransport calls onsessioninitialized BEFORE processing messages.
          // So we should connect here.
          server.connect(transport).catchError((e) {
            _logger.error('Error connecting server to transport: $e');
            _transports.remove(sid);
            _servers.remove(sid);
          });
        },
      ),
    );

    transport.onclose = () {
      final sid = transport.sessionId;
      if (sid != null) {
        _transports.remove(sid);
        _servers.remove(sid); // This will be GC'd
        _logger.info('Session closed: $sid');
      }
    };

    return transport;
  }

  StreamableHTTPServerTransport _createStatelessTransport() {
    return StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: () => null,
        eventStore: eventStore,
        enableDnsRebindingProtection: enableDnsRebindingProtection,
        allowedHosts: allowedHosts ?? {host},
        allowedOrigins: allowedOrigins,
        enableJsonResponse: enableJsonResponse,
        strictProtocolVersionHeaderValidation:
            strictProtocolVersionHeaderValidation,
        rejectBatchJsonRpcPayloads: rejectBatchJsonRpcPayloads,
      ),
    );
  }

  bool _requiresStatelessTransport(HttpRequest request) {
    final versionHeader = request.headers.value('mcp-protocol-version');
    if (versionHeader == null || versionHeader.trim().isEmpty) {
      return false;
    }

    final version = versionHeader.trim();
    return isStatelessProtocolVersion(version) ||
        strictProtocolVersionHeaderValidation &&
            !supportedProtocolVersionsWithDraft.contains(version);
  }

  bool _isStatelessRequest(HttpRequest request, dynamic body) {
    if (_requiresStatelessTransport(request)) {
      return true;
    }
    if (body is Map<String, dynamic>) {
      final version = _bodyProtocolVersion(body);
      return version != null &&
          (isStatelessProtocolVersion(version) ||
              strictProtocolVersionHeaderValidation &&
                  !supportedProtocolVersionsWithDraft.contains(version));
    }
    if (body is List) {
      return body.whereType<Map<String, dynamic>>().any((item) {
        final version = _bodyProtocolVersion(item);
        return version != null &&
            (isStatelessProtocolVersion(version) ||
                strictProtocolVersionHeaderValidation &&
                    !supportedProtocolVersionsWithDraft.contains(version));
      });
    }
    return false;
  }

  String? _bodyProtocolVersion(Map<String, dynamic> body) {
    final params = body['params'];
    if (params is Map) {
      final meta = params['_meta'];
      if (meta is Map) {
        final version = meta[McpMetaKey.protocolVersion];
        if (version is String) {
          return version;
        }
      }
    }

    final topLevelMeta = body['_meta'];
    if (topLevelMeta is Map) {
      final version = topLevelMeta[McpMetaKey.protocolVersion];
      if (version is String) {
        return version;
      }
    }

    return null;
  }

  bool _isInitializeRequest(dynamic body) {
    if (body is Map<String, dynamic> &&
        body.containsKey('method') &&
        body['method'] == 'initialize') {
      return true;
    }
    // Batch request check
    if (body is List && body.isNotEmpty) {
      for (final item in body) {
        if (item is Map<String, dynamic> &&
            item.containsKey('method') &&
            item['method'] == 'initialize') {
          return true;
        }
      }
    }
    return false;
  }

  bool _isProtectedResourceMetadataRequest(HttpRequest request) {
    final options = oauthProtectedResource;
    if (options == null) {
      return false;
    }

    final metadataPath = _protectedResourceMetadataPath(options);
    return request.uri.path == metadataPath ||
        (options.serveRootMetadata &&
            request.uri.path == '/.well-known/oauth-protected-resource');
  }

  Future<void> _handleProtectedResourceMetadataRequest(
    HttpRequest request,
  ) async {
    if (request.method != 'GET') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, OPTIONS')
        ..write('Method Not Allowed');
      await request.response.close();
      return;
    }

    final options = oauthProtectedResource;
    if (options == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(options.metadata.toJson()));
    await request.response.close();
  }

  Future<void> _respondUnauthorized(HttpRequest request) async {
    await _respondAuthenticationFailure(
      request,
      const StreamableMcpAuthenticationResult.unauthorized(),
    );
  }

  Future<void> _respondAuthenticationFailure(
    HttpRequest request,
    StreamableMcpAuthenticationResult result,
  ) async {
    final options = oauthProtectedResource;
    if (options == null) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden');
      await request.response.close();
      return;
    }

    final insufficientScope =
        result._status == _StreamableMcpAuthenticationStatus.insufficientScope;
    request.response
      ..statusCode =
          insufficientScope ? HttpStatus.forbidden : HttpStatus.unauthorized
      ..headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        _wwwAuthenticateHeaderValue(request, options, result),
      )
      ..write(insufficientScope ? 'Forbidden' : 'Unauthorized');
    await request.response.close();
  }

  String _wwwAuthenticateHeaderValue(
    HttpRequest request,
    OAuthProtectedResourceOptions options,
    StreamableMcpAuthenticationResult result,
  ) {
    final metadataUri = options.metadataUri ??
        _absoluteUriForRequest(
          request,
          _protectedResourceMetadataPath(options),
        );
    if (result._status ==
        _StreamableMcpAuthenticationStatus.insufficientScope) {
      return OAuthBearerChallenge.insufficientScope(
        resourceMetadata: metadataUri,
        scope: result.scope!,
        errorDescription: result.errorDescription,
        additionalParameters: result.additionalChallengeParameters,
      ).toHeaderValue();
    }

    return OAuthBearerChallenge(
      resourceMetadata: metadataUri,
      scope: options.scope,
      errorDescription: result.errorDescription,
      additionalParameters: result.additionalChallengeParameters,
    ).toHeaderValue();
  }

  String _protectedResourceMetadataPath(
    OAuthProtectedResourceOptions options,
  ) {
    final configuredPath = options.metadataPath;
    if (configuredPath != null) {
      return configuredPath.startsWith('/')
          ? configuredPath
          : '/$configuredPath';
    }

    if (path == '/' || path.isEmpty) {
      return '/.well-known/oauth-protected-resource';
    }
    return '/.well-known/oauth-protected-resource${path.startsWith('/') ? path : '/$path'}';
  }

  Uri _absoluteUriForRequest(HttpRequest request, String path) {
    final requestedUri = request.requestedUri;
    return Uri(
      scheme: requestedUri.scheme,
      host: requestedUri.host,
      port: requestedUri.hasPort ? requestedUri.port : null,
      path: path,
    );
  }

  Future<Uint8List> _collectBytes(HttpRequest request) async {
    final completer = Completer<Uint8List>();
    final sink = BytesBuilder();

    request.listen(
      sink.add,
      onDone: () => completer.complete(sink.takeBytes()),
      onError: completer.completeError,
      cancelOnError: true,
    );

    return completer.future;
  }

  Future<void> _respondWithJsonRpcError(
    HttpResponse response, {
    required int httpStatus,
    required ErrorCode errorCode,
    required String message,
    Object? data,
  }) async {
    response
      ..statusCode = httpStatus
      ..write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: errorCode.value,
              message: message,
              data: data,
            ),
          ).toJson(),
        ),
      );
    await response.close();
  }

  String _corsAllowedHeaders(HttpRequest request) {
    final allowedHeaders = <String>[];
    final seenHeaders = <String>{};

    void addAllowedHeader(String headerName) {
      final normalized = headerName.toLowerCase();
      if (seenHeaders.add(normalized)) {
        allowedHeaders.add(headerName);
      }
    }

    for (final headerName in _defaultCorsAllowedHeaders) {
      addAllowedHeader(headerName);
    }

    final requestedHeaders =
        request.headers.value('access-control-request-headers');
    if (requestedHeaders == null) {
      return allowedHeaders.join(', ');
    }

    for (final rawHeaderName in requestedHeaders.split(',')) {
      final headerName = rawHeaderName.trim();
      if (headerName.isEmpty ||
          !headerName.codeUnits.every(isHttpFieldNameTokenChar)) {
        continue;
      }
      addAllowedHeader(headerName);
    }

    return allowedHeaders.join(', ');
  }

  void _setCorsHeaders(HttpRequest request, HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers
        .set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      _corsAllowedHeaders(request),
    );
    response.headers.set('Access-Control-Allow-Credentials', 'true');
    response.headers.set('Access-Control-Max-Age', defaultCorsMaxAgeSeconds);
    response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
  }
}
