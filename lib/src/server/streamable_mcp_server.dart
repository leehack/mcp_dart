import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/types.dart';

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

  /// Factory to create a new MCP server instance for a given session.
  final McpServer Function(String sessionId) _serverFactory;

  /// Host to bind the HTTP server to.
  final String host;

  /// Port to bind the HTTP server to.
  final int port;

  /// Path to listen for MCP requests on.
  final String path;

  /// Event store for resumability support.
  final EventStore? eventStore;

  /// Optional callback to authenticate requests.
  /// Returns true if the request is allowed, false otherwise.
  final FutureOr<bool> Function(HttpRequest request)? authenticator;

  HttpServer? _httpServer;
  final Map<String, StreamableHTTPServerTransport> _transports = {};
  // Keep track of servers to close them if needed, though closing transport usually suffices
  final Map<String, McpServer> _servers = {};

  StreamableMcpServer({
    required McpServer Function(String sessionId) serverFactory,
    this.host = 'localhost',
    this.port = 3000,
    this.path = '/mcp',
    this.eventStore,
    this.authenticator,
  }) : _serverFactory = serverFactory;

  /// Starts the HTTP server.
  Future<void> start() async {
    if (_httpServer != null) {
      throw StateError('Server already started');
    }

    _httpServer = await HttpServer.bind(host, port);
    _logger.info(
      'MCP Streamable HTTP Server listening on http://$host:$port$path',
    );

    _httpServer!.listen(_handleRequest);
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
    _setCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (request.uri.path != path) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
      return;
    }

    if (authenticator != null) {
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
        request.response
          ..statusCode = HttpStatus.forbidden
          ..write('Forbidden')
          ..close();
        return;
      }
    }

    try {
      if (request.method == 'POST') {
        await _handlePostRequest(request);
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

    final bodyBytes = await _collectBytes(request);
    final bodyString = utf8.decode(bodyBytes);
    dynamic body;
    try {
      body = jsonDecode(bodyString);
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.parseError.value,
                message: 'Parse error',
              ),
            ).toJson(),
          ),
        )
        ..close();
      return;
    }

    final sessionId = request.headers.value('mcp-session-id');
    StreamableHTTPServerTransport? transport;

    if (sessionId != null && _transports.containsKey(sessionId)) {
      transport = _transports[sessionId]!;
    } else if (sessionId == null && _isInitializeRequest(body)) {
      // New initialization request
      transport = _createTransport();

      // We need to pass the body we already read to the transport
      await transport.handleRequest(request, body);
      return;
    } else {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message:
                    'Bad Request: No valid session ID provided or not an initialization request',
              ),
            ).toJson(),
          ),
        )
        ..close();
      return;
    }

    // Handle the request with existing transport
    await transport.handleRequest(request, body);
  }

  Future<void> _handleGetRequest(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null || !_transports.containsKey(sessionId)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid or missing session ID')
        ..close();
      return;
    }

    final transport = _transports[sessionId]!;
    await transport.handleRequest(request);
  }

  Future<void> _handleDeleteRequest(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null || !_transports.containsKey(sessionId)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid or missing session ID')
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

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers
        .set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, mcp-session-id, Last-Event-ID, Authorization',
    );
    response.headers.set('Access-Control-Allow-Credentials', 'true');
    response.headers.set('Access-Control-Max-Age', '86400');
    response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
  }
}
