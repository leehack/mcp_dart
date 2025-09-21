import 'dart:io';

import 'package:logging/logging.dart';

import 'mcp.dart';
import 'sse.dart';

final _logger = Logger("mcp_dart.server.sse.manager");

/// Manages Server-Sent Events (SSE) connections and routes HTTP requests.
class SseServerManager {
  /// Map to store active SSE transports, keyed by session ID.
  final Map<String, SseServerTransport> activeSseTransports = {};

  /// The main MCP Server instance.
  final McpServer mcpServer;

  /// Path for establishing SSE connections.
  final String ssePath;

  /// Path for sending messages to the server.
  final String messagePath;

  SseServerManager(
    this.mcpServer, {
    this.ssePath = '/sse',
    this.messagePath = '/messages',
  });

  /// Routes incoming HTTP requests to appropriate handlers.
  Future<void> handleRequest(HttpRequest request) async {
    _logger.fine("Received request: ${request.method} ${request.uri.path}");

    if (request.uri.path == ssePath) {
      if (request.method == 'GET') {
        await handleSseConnection(request);
      } else {
        await _sendMethodNotAllowed(request, ['GET']);
      }
    } else if (request.uri.path == messagePath) {
      if (request.method == 'POST') {
        await _handlePostMessage(request);
      } else {
        await _sendMethodNotAllowed(request, ['POST']);
      }
    } else {
      await _sendNotFound(request);
    }
  }

  /// Handles the initial GET request to establish an SSE connection.
  Future<void> handleSseConnection(HttpRequest request) async {
    _logger.fine("Client connecting for SSE at /sse...");
    SseServerTransport? transport;

    try {
      transport = SseServerTransport(
        response: request.response,
        messageEndpointPath: messagePath,
      );

      final sessionId = transport.sessionId;
      activeSseTransports[sessionId] = transport;
      _logger.fine("Stored new SSE transport for session: $sessionId");

      transport.onclose = () {
        _logger.fine(
          "SSE transport closed (Session: $sessionId). Removing from active list.",
        );
        activeSseTransports.remove(sessionId);
      };

      transport.onerror = (error) {
        _logger.warning("Error on SSE transport (Session: $sessionId): $error");
      };

      await mcpServer.connect(transport);
      _logger.fine("SSE transport connected, session ID: $sessionId");
    } catch (e) {
      _logger.warning("Error setting up SSE connection: $e");
      if (transport != null) {
        activeSseTransports.remove(transport.sessionId);
      }
      if (!request.response.headers.persistentConnection) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write("Failed to initialize SSE connection.");
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  /// Handles POST requests containing client messages.
  Future<void> _handlePostMessage(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    _logger.fine("Received POST to $messagePath (Session ID: $sessionId)");

    if (sessionId == null || sessionId.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write("Missing or empty 'sessionId' query parameter.");
      await request.response.close();
      return;
    }

    final transportToUse = activeSseTransports[sessionId];
    if (transportToUse != null) {
      await transportToUse.handlePostMessage(request);
    } else {
      _logger.fine("No active SSE transport found for session ID: $sessionId");
      request.response
        ..statusCode = HttpStatus.notFound
        ..write("No active SSE session found for ID: $sessionId");
      await request.response.close();
    }
  }

  /// Sends a 404 Not Found response.
  Future<void> _sendNotFound(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not Found');
    await request.response.close();
  }

  /// Sends a 405 Method Not Allowed response.
  Future<void> _sendMethodNotAllowed(
    HttpRequest request,
    List<String> allowedMethods,
  ) async {
    request.response
      ..statusCode = HttpStatus.methodNotAllowed
      ..headers.set(HttpHeaders.allowHeader, allowedMethods.join(', '))
      ..write('Method Not Allowed');
    await request.response.close();
  }
}
