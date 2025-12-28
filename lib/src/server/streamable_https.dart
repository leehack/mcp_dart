import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/uuid.dart';

import '../shared/transport.dart';
import '../types.dart';

/// ID for SSE streams
typedef StreamId = String;

/// ID for events in SSE streams
typedef EventId = String;

/// Interface for resumability support via event storage
abstract class EventStore {
  /// Stores an event for later retrieval
  ///
  /// [streamId] ID of the stream the event belongs to
  /// [message] The JSON-RPC message to store
  ///
  /// Returns the generated event ID for the stored event
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message);

  /// Replays events after a specified event ID
  ///
  /// [lastEventId] The last event ID received by the client
  /// [send] Callback function that will be called for each event
  ///
  /// Returns the stream ID associated with the events
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
        send,
  });
}

/// Configuration options for StreamableHTTPServerTransport
class StreamableHTTPServerTransportOptions {
  /// Function that generates a session ID for the transport.
  /// The session ID SHOULD be globally unique and cryptographically secure (e.g., a securely generated UUID, a JWT, or a cryptographic hash)
  ///
  /// Return null to disable session management
  final String? Function()? sessionIdGenerator;

  /// A callback for session initialization events
  /// This is called when the server initializes a new session.
  /// Useful in cases when you need to register multiple MCP sessions
  /// and need to keep track of them.
  final void Function(String sessionId)? onsessioninitialized;

  /// If true, the server will return JSON responses instead of starting an SSE stream.
  /// This can be useful for simple request/response scenarios without streaming.
  /// Default is false (SSE streams are preferred).
  final bool enableJsonResponse;

  /// Event store for resumability support
  /// If provided, resumability will be enabled, allowing clients to reconnect and resume messages
  final EventStore? eventStore;

  /// Creates configuration options for StreamableHTTPServerTransport
  StreamableHTTPServerTransportOptions({
    this.sessionIdGenerator,
    this.onsessioninitialized,
    this.enableJsonResponse = false,
    this.eventStore,
  });
}

/// Server transport for Streamable HTTP: this implements the MCP Streamable HTTP transport specification.
/// It supports both SSE streaming and direct HTTP responses.
///
/// Usage example:
///
/// ```dart
/// // Stateful mode - server sets the session ID
/// final statefulTransport = StreamableHTTPServerTransport(
///   options: StreamableHTTPServerTransportOptions(
///     sessionIdGenerator: () => generateUUID(),
///   ),
/// );
///
/// // Stateless mode - explicitly set session ID to null
/// final statelessTransport = StreamableHTTPServerTransport(
///   options: StreamableHTTPServerTransportOptions(
///     sessionIdGenerator: () => null,
///   ),
/// );
///
/// // Using with HTTP server
/// final server = await HttpServer.bind('localhost', 8080);
/// server.listen((request) {
///   if (request.uri.path == '/mcp') {
///     statefulTransport.handleRequest(request);
///   }
/// });
/// ```
///
/// In stateful mode:
/// - Session ID is generated and included in response headers
/// - Session ID is always included in initialization responses
/// - Requests with invalid session IDs are rejected with 404 Not Found
/// - Non-initialization requests without a session ID are rejected with 400 Bad Request
/// - State is maintained in-memory (connections, message history)
///
/// In stateless mode:
/// - Session ID is only included in initialization responses
/// - No session validation is performed
class StreamableHTTPServerTransport implements Transport {
  // when sessionId is not set (null), it means the transport is in stateless mode
  final String? Function()? _sessionIdGenerator;
  bool _started = false;
  final Map<String, HttpResponse> _streamMapping = {};
  final Map<dynamic, String> _requestToStreamMapping = {};
  final Map<dynamic, JsonRpcMessage> _requestResponseMap = {};
  bool _initialized = false;
  final bool _enableJsonResponse;
  final String _standaloneSseStreamId = '_GET_stream';
  final EventStore? _eventStore;
  final void Function(String sessionId)? _onsessioninitialized;

  @override
  String? sessionId;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Creates a new StreamableHTTPServerTransport
  StreamableHTTPServerTransport({
    required StreamableHTTPServerTransportOptions options,
  })  : _sessionIdGenerator = options.sessionIdGenerator,
        _enableJsonResponse = options.enableJsonResponse,
        _eventStore = options.eventStore,
        _onsessioninitialized = options.onsessioninitialized;

  /// Starts the transport. This is required by the Transport interface but is a no-op
  /// for the Streamable HTTP transport as connections are managed per-request.
  @override
  Future<void> start() async {
    if (_started) {
      throw StateError("Transport already started");
    }
    _started = true;
  }

  /// Handles an incoming HTTP request, whether GET or POST
  Future<void> handleRequest(HttpRequest req, [dynamic parsedBody]) async {
    req.response.bufferOutput = false;
    if (req.method == "POST") {
      await _handlePostRequest(req, parsedBody);
    } else if (req.method == "GET") {
      await _handleGetRequest(req);
    } else if (req.method == "DELETE") {
      await _handleDeleteRequest(req);
    } else {
      await _handleUnsupportedRequest(req.response);
    }
  }

  /// Handles GET requests for SSE stream
  Future<void> _handleGetRequest(HttpRequest req) async {
    // The client MUST include an Accept header, listing text/event-stream as a supported content type.
    final acceptHeader = req.headers.value(HttpHeaders.acceptHeader) ?? '';
    if (!acceptHeader.contains("text/event-stream")) {
      req.response
        ..statusCode = HttpStatus.notAcceptable
        ..write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message: 'Not Acceptable: Client must accept text/event-stream',
              ),
            ).toJson(),
          ),
        );
      await _safeClose(req.response);
      return;
    }

    // If an Mcp-Session-Id is returned by the server during initialization,
    // clients using the Streamable HTTP transport MUST include it
    // in the Mcp-Session-Id header on all of their subsequent HTTP requests.
    if (!await _validateSession(req, req.response)) {
      return;
    }

    // Handle resumability: check for Last-Event-ID header
    if (_eventStore != null) {
      final lastEventId = req.headers.value('Last-Event-ID');
      if (lastEventId != null) {
        await _replayEvents(lastEventId, req.response);
        return;
      }
    }

    // The server MUST either return Content-Type: text/event-stream in response to this HTTP GET,
    // or else return HTTP 405 Method Not Allowed
    final headers = {
      HttpHeaders.contentTypeHeader: "text/event-stream; charset=utf-8",
      HttpHeaders.cacheControlHeader: "no-cache, no-transform",
      HttpHeaders.connectionHeader: "keep-alive",
    };

    // After initialization, always include the session ID if we have one
    if (sessionId != null) {
      headers["mcp-session-id"] = sessionId!;
    }

    // Check if there's already an active standalone SSE stream for this session
    if (_streamMapping[_standaloneSseStreamId] != null) {
      // Only one GET SSE stream is allowed per session
      req.response
        ..statusCode = HttpStatus.conflict
        ..write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message: 'Conflict: Only one SSE stream is allowed per session',
              ),
            ).toJson(),
          ),
        );
      await _safeClose(req.response);
      return;
    }

    // We need to send headers immediately as messages will arrive much later,
    // otherwise the client will just wait for the first message
    req.response.statusCode = HttpStatus.ok;
    headers.forEach((key, value) {
      req.response.headers.set(key, value);
    });

    // Assign the response to the standalone SSE stream before flushing
    // to ensure it's available if a task tries to send a message immediately
    _streamMapping[_standaloneSseStreamId] = req.response;

    await req.response.flush();

    // Set up close handler for client disconnects
    req.response.done.then((_) {
      _streamMapping.remove(_standaloneSseStreamId);
    });
  }

  /// Replays events that would have been sent after the specified event ID
  /// Only used when resumability is enabled
  Future<void> _replayEvents(String lastEventId, HttpResponse res) async {
    if (_eventStore == null) {
      return;
    }
    try {
      final headers = {
        HttpHeaders.contentTypeHeader: "text/event-stream; charset=utf-8",
        HttpHeaders.cacheControlHeader: "no-cache, no-transform",
        HttpHeaders.connectionHeader: "keep-alive",
      };

      if (sessionId != null) {
        headers["mcp-session-id"] = sessionId!;
      }

      res.statusCode = HttpStatus.ok;
      headers.forEach((key, value) {
        res.headers.set(key, value);
      });
      await res.flush();

      final streamId = await _eventStore!.replayEventsAfter(
        lastEventId,
        send: (eventId, message) async {
          if (!await _writeSSEEvent(res, message, eventId)) {
            onerror?.call(StateError("Failed to replay events"));
            await _safeClose(res);
          }
          return Future.value();
        },
      );

      _streamMapping[streamId] = res;
    } catch (error) {
      onerror?.call(error is Error ? error : StateError(error.toString()));
    }
  }

  /// Safely closes an HTTP response, ignoring errors if client disconnected
  Future<void> _safeClose(HttpResponse res) async {
    try {
      await res.close();
    } catch (e) {
      // Ignore close errors - client may have already disconnected
    }
  }

  /// Writes an event to the SSE stream with proper formatting
  Future<bool> _writeSSEEvent(
    HttpResponse res,
    JsonRpcMessage message, [
    String? eventId,
  ]) async {
    var eventData = "event: message\n";
    // Include event ID if provided - this is important for resumability
    if (eventId != null) {
      eventData += "id: $eventId\n";
    }
    eventData += "data: ${jsonEncode(message.toJson())}\n\n";

    try {
      res.add(utf8.encode(eventData));
      await res.flush();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Handles unsupported requests (PUT, PATCH, etc.)
  Future<void> _handleUnsupportedRequest(HttpResponse res) async {
    res.statusCode = HttpStatus.methodNotAllowed;
    res.headers.set(HttpHeaders.allowHeader, "GET, POST, DELETE");
    res.write(
      jsonEncode(
        JsonRpcError(
          id: null,
          error: JsonRpcErrorData(
            code: ErrorCode.connectionClosed.value,
            message: 'Method not allowed.',
          ),
        ).toJson(),
      ),
    );
    await _safeClose(res);
  }

  /// Handles POST requests containing JSON-RPC messages
  Future<void> _handlePostRequest(HttpRequest req, [dynamic parsedBody]) async {
    try {
      // Validate the Accept header
      final acceptHeader = req.headers.value(HttpHeaders.acceptHeader) ?? '';
      // The client MUST include an Accept header, listing both application/json and text/event-stream as supported content types.
      if (!acceptHeader.contains("application/json") || !acceptHeader.contains("text/event-stream")) {
        req.response.statusCode = HttpStatus.notAcceptable;
        req.response.write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message:
                    'Not Acceptable: Client must accept both application/json and text/event-stream',
              ),
            ).toJson(),
          ),
        );
        await _safeClose(req.response);
        return;
      }

      final contentType = req.headers.contentType?.value ?? '';
      if (!contentType.contains("application/json")) {
        req.response.statusCode = HttpStatus.unsupportedMediaType;
        req.response.write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message:
                    'Unsupported Media Type: Content-Type must be application/json',
              ),
            ).toJson(),
          ),
        );
        await _safeClose(req.response);
        return;
      }

      dynamic rawMessage;
      if (parsedBody != null) {
        rawMessage = parsedBody;
      } else {
        // Read and parse request body
        final bodyBytes = await _collectBytes(req);
        final bodyString = utf8.decode(bodyBytes);
        rawMessage = jsonDecode(bodyString);
      }

      List<JsonRpcMessage> messages = [];

      // Handle batch and single messages
      if (rawMessage is List) {
        for (final msg in rawMessage) {
          try {
            messages.add(JsonRpcMessage.fromJson(msg));
          } catch (e) {
            req.response.statusCode = HttpStatus.badRequest;
            req.response.write(
              jsonEncode(
                JsonRpcError(
                  id: null,
                  error: JsonRpcErrorData(
                    code: ErrorCode.parseError.value,
                    message: 'Parse error',
                    data: e.toString(),
                  ),
                ).toJson(),
              ),
            );
            await _safeClose(req.response);
            onerror?.call(e is Error ? e : StateError(e.toString()));
            return;
          }
        }
      } else {
        try {
          messages = [JsonRpcMessage.fromJson(rawMessage)];
        } catch (e) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(
            jsonEncode(
              JsonRpcError(
                id: null,
                error: JsonRpcErrorData(
                  code: ErrorCode.parseError.value,
                  message: 'Parse error',
                  data: e.toString(),
                ),
              ).toJson(),
            ),
          );
          await _safeClose(req.response);
          onerror?.call(e is Error ? e : StateError(e.toString()));
          return;
        }
      }

      // Check if this is an initialization request
      // https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle/
      final isInitializationRequest = messages.any(_isInitializeRequest);
      if (isInitializationRequest) {
        // If it's a server with session management and the session ID is already set we should reject the request
        // to avoid re-initialization.
        if (_initialized && sessionId != null) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(
            jsonEncode(
              JsonRpcError(
                id: null,
                error: JsonRpcErrorData(
                  code: ErrorCode.invalidRequest.value,
                  message: 'Invalid Request: Server already initialized',
                ),
              ).toJson(),
            ),
          );
          await _safeClose(req.response);
          return;
        }
        if (messages.length > 1) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(
            jsonEncode(
              JsonRpcError(
                id: null,
                error: JsonRpcErrorData(
                  code: ErrorCode.invalidRequest.value,
                  message:
                      'Invalid Request: Only one initialization request is allowed',
                ),
              ).toJson(),
            ),
          );
          await _safeClose(req.response);
          return;
        }
        sessionId = _sessionIdGenerator?.call();
        _initialized = true;

        // If we have a session ID and an onsessioninitialized handler, call it immediately
        // This is needed in cases where the server needs to keep track of multiple sessions
        if (sessionId != null && _onsessioninitialized != null) {
          _onsessioninitialized!(sessionId!);
        }
      }

      // If an Mcp-Session-Id is returned by the server during initialization,
      // clients using the Streamable HTTP transport MUST include it
      // in the Mcp-Session-Id header on all of their subsequent HTTP requests.
      if (!isInitializationRequest &&
          !await _validateSession(req, req.response)) {
        return;
      }

      // Check if it contains requests
      final hasRequests = messages.any(_isJsonRpcRequest);

      if (!hasRequests) {
        // If it only contains notifications or responses, return 202
        // Handle each message first to ensure processing
        for (final message in messages) {
          try {
            onmessage?.call(message);
          } catch (e) {
            // Don't let handler errors affect the response - message was received successfully
            onerror?.call(e is Error ? e : StateError(e.toString()));
          }
        }

        req.response.statusCode = HttpStatus.accepted;
        await _safeClose(req.response);
      } else if (hasRequests) {
        // The default behavior is to use SSE streaming
        // but in some cases server will return JSON responses
        final streamId = generateUUID();
        if (!_enableJsonResponse) {
          final headers = {
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
            HttpHeaders.cacheControlHeader: "no-cache",
            HttpHeaders.connectionHeader: "keep-alive",
          };

          // After initialization, always include the session ID if we have one
          if (sessionId != null) {
            headers["mcp-session-id"] = sessionId!;
          }

          req.response.statusCode = HttpStatus.ok;
          headers.forEach((key, value) {
            req.response.headers.set(key, value);
          });
        }

        // Store the response for this request to send messages back through this connection
        // We need to track by request ID to maintain the connection
        for (final message in messages) {
          if (_isJsonRpcRequest(message)) {
            final reqId = (message as JsonRpcRequest).id;
            _streamMapping[streamId] = req.response;
            _requestToStreamMapping[reqId] = streamId;
          }
        }

        // Set up close handler for client disconnects
        req.response.done.then((_) {
          _streamMapping.remove(streamId);
        });

        // Handle each message
        for (final message in messages) {
          try {
            onmessage?.call(message);
          } catch (e) {
            // Don't let handler errors affect the response - message was received successfully
            onerror?.call(e is Error ? e : StateError(e.toString()));
          }
        }
        // The server SHOULD NOT close the SSE stream before sending all JSON-RPC responses
        // This will be handled by the send() method when responses are ready
      }
    } catch (error) {
      // Return JSON-RPC formatted error
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.parseError.value,
              message: 'Parse error',
              data: error.toString(),
            ),
          ).toJson(),
        ),
      );
      await _safeClose(req.response);

      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(StateError(error.toString()));
      }
    }
  }

  /// Collects all bytes from an HTTP request
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

  /// Handles DELETE requests to terminate sessions
  Future<void> _handleDeleteRequest(HttpRequest req) async {
    if (!await _validateSession(req, req.response)) {
      return;
    }
    await close();
    req.response.statusCode = HttpStatus.ok;
    await _safeClose(req.response);
  }

  /// Validates session ID for non-initialization requests
  /// Returns true if the session is valid, false otherwise
  Future<bool> _validateSession(HttpRequest req, HttpResponse res) async {
    if (!_initialized) {
      // If the server has not been initialized yet, reject all requests
      res.statusCode = HttpStatus.badRequest;
      res.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message: 'Bad Request: Server not initialized',
            ),
          ).toJson(),
        ),
      );
      await _safeClose(res);
      return false;
    }

    if (sessionId == null) {
      // If the session ID is not set, the session management is disabled
      // and we don't need to validate the session ID
      return true;
    }

    final requestSessionId = req.headers.value("mcp-session-id");

    if (requestSessionId == null) {
      // Non-initialization requests without a session ID should return 400 Bad Request
      res.statusCode = HttpStatus.badRequest;
      res.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message: 'Bad Request: Mcp-Session-Id header is required',
            ),
          ).toJson(),
        ),
      );
      await _safeClose(res);
      return false;
    } else if (requestSessionId != sessionId) {
      // Reject requests with invalid session ID with 404 Not Found
      res.statusCode = HttpStatus.notFound;
      res.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message: 'Session not found',
            ),
          ).toJson(),
        ),
      );
      await _safeClose(res);
      return false;
    }

    return true;
  }

  @override
  Future<void> close() async {
    // Close all SSE connections - fix concurrent modification by creating a copy of the values first
    final responses = List<HttpResponse>.from(_streamMapping.values);
    for (final response in responses) {
      await _safeClose(response);
    }
    _streamMapping.clear();

    // Clear any pending responses
    _requestResponseMap.clear();
    _requestToStreamMapping.clear(); // Also clear this map
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {dynamic relatedRequestId}) async {
    dynamic requestId = relatedRequestId;
    if (_isJsonRpcResponse(message) || _isJsonRpcError(message)) {
      // If the message is a response, use the request ID from the message
      requestId = _getMessageId(message);
    }

    // Check if this message should be sent on the standalone SSE stream (no request ID)
    // Ignore notifications from tools (which have relatedRequestId set)
    // Those will be sent via dedicated response SSE streams
    if (requestId == null) {
      // For standalone SSE streams, we can only send requests and notifications
      if (_isJsonRpcResponse(message) || _isJsonRpcError(message)) {
        throw StateError(
          "Cannot send a response on a standalone SSE stream unless resuming a previous client request",
        );
      }

      final standaloneSse = _streamMapping[_standaloneSseStreamId];
      if (standaloneSse == null) {
        // The spec says the server MAY send messages on the stream, so it's ok to discard if no stream
        return;
      }

      // Generate and store event ID if event store is provided
      String? eventId;
      if (_eventStore != null) {
        // Stores the event and gets the generated event ID
        eventId =
            await _eventStore!.storeEvent(_standaloneSseStreamId, message);
      }

      // Send the message to the standalone SSE stream
      await _writeSSEEvent(standaloneSse, message, eventId);
      return;
    }

    // Get the response for this request
    final streamId = _requestToStreamMapping[requestId];
    if (streamId == null) {
      throw StateError("No connection established for request ID: $requestId");
    }

    final response = _streamMapping[streamId];

    if (!_enableJsonResponse) {
      // For SSE responses, generate event ID if event store is provided
      String? eventId;

      if (_eventStore != null) {
        eventId = await _eventStore!.storeEvent(streamId, message);
      }

      if (response != null) {
        // Write the event to the response stream
        await _writeSSEEvent(response, message, eventId);
      }
    }

    if (_isJsonRpcResponse(message)) {
      _requestResponseMap[requestId] = message;
      final relatedIds = _requestToStreamMapping.entries
          .where((entry) => _streamMapping[entry.value] == response)
          .map((entry) => entry.key)
          .toList();

      // Check if we have responses for all requests using this connection
      final allResponsesReady =
          relatedIds.every((id) => _requestResponseMap.containsKey(id));

      if (allResponsesReady) {
        if (response == null) {
          throw StateError(
            "No connection established for request ID: $requestId",
          );
        }

        if (_enableJsonResponse) {
          // All responses ready, send as JSON
          final headers = {
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          };

          if (sessionId != null) {
            headers['mcp-session-id'] = sessionId!;
          }

          final responses =
              relatedIds.map((id) => _requestResponseMap[id]!).toList();

          headers.forEach((key, value) {
            response.headers.set(key, value);
          });

          if (responses.length == 1) {
            response.write(jsonEncode(responses[0].toJson()));
          } else {
            response
                .write(jsonEncode(responses.map((r) => r.toJson()).toList()));
          }
          await _safeClose(response);
        } else {
          // End the SSE stream
          await _safeClose(response);
        }

        // Clean up
        for (final id in relatedIds) {
          _requestResponseMap.remove(id);
          _requestToStreamMapping.remove(id);
        }
      }
    }
  }

  /// Checks if a message is an initialize request
  bool _isInitializeRequest(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.method == "initialize";
    }
    return false;
  }

  /// Checks if a message is a JSON-RPC request
  bool _isJsonRpcRequest(JsonRpcMessage message) {
    return message is JsonRpcRequest;
  }

  /// Checks if a message is a JSON-RPC response
  bool _isJsonRpcResponse(JsonRpcMessage message) {
    return message is JsonRpcResponse;
  }

  /// Checks if a message is a JSON-RPC error
  bool _isJsonRpcError(JsonRpcMessage message) {
    return message is JsonRpcError;
  }

  /// Gets the ID from a JSON-RPC message
  dynamic _getMessageId(JsonRpcMessage message) {
    if (message is JsonRpcResponse) {
      return message.id;
    } else if (message is JsonRpcError) {
      return message.id;
    }
    return null;
  }
}
