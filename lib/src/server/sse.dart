import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.server.sse");

/// Maximum size for incoming POST message bodies.
const int _maximumMessageSize = 4 * 1024 * 1024; // 4MB in bytes

/// Server transport for SSE: sends messages over a persistent SSE connection
/// ([HttpResponse]) and receives messages from separate HTTP POST requests
/// handled by [handlePostMessage].
///
/// This requires integration with a Dart HTTP server (like `dart:io`'s
/// `HttpServer` or frameworks like Shelf/Alfred). The `start` method manages
/// the SSE response stream, while `handlePostMessage` should be called from
/// the server's routing logic for the designated message endpoint.
class SseServerTransport implements Transport {
  StringConversionSink? _sink;
  final HttpResponse _sseResponse;

  /// The unique session ID for this connection, used to route POST messages.
  late final String _sessionId;

  /// The relative or absolute path where the client should POST messages.
  final String _messageEndpointPath;

  /// Controller for managing the SSE connection stream closing.
  final StreamController<void> _closeController = StreamController.broadcast();

  /// Callback for when the connection is closed.
  @override
  void Function()? onclose;

  /// Callback for reporting errors.
  @override
  void Function(Error error)? onerror;

  /// Callback for received messages (from POST requests).
  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Returns the unique session ID for this transport instance.
  /// Used by the client in the POST request URL query parameters.
  @override
  String get sessionId => _sessionId;

  /// Creates a new SSE server transport.
  ///
  /// - [response]: The [HttpResponse] object obtained from the HTTP server
  ///   for the initial SSE connection request (e.g., GET /sse). This transport
  ///   takes control of this response object.
  /// - [messageEndpointPath]: The URL path (relative or absolute) that the client
  ///   will be instructed to POST messages to.
  SseServerTransport({
    required HttpResponse response,
    required String messageEndpointPath,
  })  : _sseResponse = response,
        _messageEndpointPath = messageEndpointPath {
    _sessionId = generateUUID();
  }

  /// Handles the initial SSE connection setup.
  ///
  /// Configures the [HttpResponse] for SSE, sends the initial 'endpoint' event
  /// instructing the client where to POST messages, and listens for the
  /// connection to close.
  @override
  Future<void> start() async {
    if (_closeController.isClosed) {
      throw StateError(
        "SseServerTransport cannot start: Transport is already closed.",
      );
    }

    try {
      _sseResponse.headers.chunkedTransferEncoding = false;
      _sseResponse.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      _sseResponse.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      _sseResponse.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final socket = await _sseResponse.detachSocket(writeHeaders: true);
      _sink = utf8.encoder.startChunkedConversion(socket);
      final endpointUrl =
          '$_messageEndpointPath?sessionId=${Uri.encodeComponent(sessionId)}';
      await _sendSseEvent(name: 'endpoint', data: endpointUrl);

      socket.listen(
        (_) {},
        onDone: () {
          _logger.debug('Client disconnected');
          close();
        },
        onError: (error) {
          _logger.warn('Socket error: $error');
          onerror?.call(
            error is Error ? error : StateError("Socket error: $error"),
          );
        },
      );
    } on UnimplementedError catch (e) {
      _logger.error('UnimplementedError during SSE transport setup: $e');
      onerror?.call(e);
      rethrow;
    } catch (error) {
      _logger.error('Error starting SSE transport: $error');
    }
  }

  /// Handles incoming HTTP POST requests containing client messages.
  ///
  /// Parses the request body as JSON, validates it, and invokes the [onmessage]
  /// callback with the parsed message.
  Future<void> handlePostMessage(
    HttpRequest request, {
    dynamic parsedBody,
  }) async {
    final response = request.response;

    if (_closeController.isClosed) {
      response.statusCode = HttpStatus.serviceUnavailable;
      response.write("SSE connection not established or closed.");
      await response.close();
      onerror?.call(
        StateError("Received POST message but SSE connection is not active."),
      );
      return;
    }

    if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'POST');
      response.write("Method Not Allowed. Use POST.");
      await response.close();
      return;
    }

    ContentType? contentType;
    try {
      contentType = request.headers.contentType ?? ContentType.json;
    } catch (e) {
      response.statusCode = HttpStatus.badRequest;
      response.write("Invalid Content-Type header: $e");
      await response.close();
      onerror?.call(
        ArgumentError("Invalid Content-Type header in POST request."),
      );
      return;
    }

    if (contentType.mimeType != 'application/json') {
      response.statusCode = HttpStatus.unsupportedMediaType;
      response.write(
        "Unsupported Content-Type: ${request.headers.contentType?.mimeType}. Expected 'application/json'.",
      );
      await response.close();
      onerror?.call(
        ArgumentError(
          "Unsupported Content-Type in POST request: ${request.headers.contentType?.mimeType}",
        ),
      );
      return;
    }

    dynamic messageJson;
    try {
      if (parsedBody != null) {
        messageJson = parsedBody;
      } else {
        final bodyBytes =
            await request.fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
          builder.add(chunk);
          if (builder.length > _maximumMessageSize) {
            throw const HttpException(
              "Message size exceeds limit of $_maximumMessageSize bytes.",
            );
          }
          return builder;
        }).then((builder) => builder.toBytes());

        final encoding =
            Encoding.getByName(contentType.parameters['charset']) ?? utf8;
        final bodyString = encoding.decode(bodyBytes);
        messageJson = jsonDecode(bodyString);
      }

      if (messageJson is! Map<String, dynamic>) {
        throw const FormatException(
          "Invalid JSON message format: Expected a JSON object.",
        );
      }

      await handleMessage(messageJson);

      response.statusCode = HttpStatus.accepted;
      response.write("Accepted");
      await response.close();
    } catch (error) {
      onerror?.call(
        error is Error
            ? error
            : StateError("Error handling POST message: $error"),
      );
      response.statusCode = HttpStatus.internalServerError;
      response.write("Error processing message: $error");
      await response.close();
    }
  }

  /// Handles a message received via any means (typically from [handlePostMessage]).
  /// Parses the raw JSON object and invokes the [onmessage] callback.
  Future<void> handleMessage(Map<String, dynamic> messageJson) async {
    JsonRpcMessage parsedMessage;
    try {
      parsedMessage = JsonRpcMessage.fromJson(messageJson);
    } catch (error) {
      _logger.warn("Failed to parse JsonRpcMessage from JSON: $messageJson");
      rethrow;
    }

    try {
      onmessage?.call(parsedMessage);
    } catch (e) {
      _logger.warn("Error within onmessage handler: $e");
      onerror?.call(StateError("Error in onmessage handler: $e"));
    }
  }

  /// Sends a [JsonRpcMessage] to the client over the established SSE connection.
  ///
  /// Serializes the message to JSON and formats it as an SSE 'message' event.
  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closeController.isClosed) {
      throw StateError("Cannot send message: SSE connection is not active.");
    }

    try {
      final jsonString = jsonEncode(message.toJson());
      await _sendSseEvent(name: 'message', data: jsonString);
    } catch (error) {
      onerror?.call(StateError("Failed to send message over SSE: $error"));
      throw StateError("Failed to send message over SSE: $error");
    }
  }

  /// Formats and sends a Server-Sent Event.
  Future<void> _sendSseEvent({
    required String name,
    required String data,
  }) async {
    if (_closeController.isClosed) return;

    final buffer = 'event: $name\ndata: $data\n\n';
    _sink?.add(buffer);
  }

  /// Closes the SSE connection and cleans up resources.
  /// Invokes the [onclose] callback.
  @override
  Future<void> close() async {
    _handleClosure();
  }

  /// Internal cleanup logic for closing the connection.
  void _handleClosure({bool propagateToCallback = true}) {
    if (_closeController.isClosed) return;

    _closeController.add(null);
    _closeController.close();

    try {
      _sink?.close();
    } catch (e) {
      _logger.warn("Error closing SSE response: $e");
    }
    _sink = null;

    if (propagateToCallback) {
      try {
        onclose?.call();
      } catch (e) {
        _logger.warn("Error within onclose handler: $e");
        onerror?.call(StateError("Error in onclose handler: $e"));
      }
    }
  }
}
