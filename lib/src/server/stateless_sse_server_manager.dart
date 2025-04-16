import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Manages Server-Sent Events (SSE) connections and routes HTTP requests.
class StatelessSseServerManager {
  /// Map to store active SSE transports, keyed by session ID.
  final Map<String, SseServerTransport> activeSseTransports = {};

  /// Function that creates and returns an MCP Server instance.
  final McpServer Function() makeMcpServer;

  /// Path for establishing SSE connections.
  final String ssePath;

  /// Path for sending messages to the server.
  final String messagePath;

  StatelessSseServerManager(
    this.makeMcpServer, {
    this.ssePath = '/sse',
    this.messagePath = '/messages',
  });

  /// Routes incoming HTTP requests to appropriate handlers.
  Future<void> handleRequest(HttpRequest request) async {
    print("Received request: ${request.method} ${request.uri.path}");

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
    print("Client connecting for SSE at /sse...");
    SseServerTransport? transport;

    try {
      transport = SseServerTransport(
        response: request.response,
        messageEndpointPath: messagePath,
      );

      final sessionId = transport.sessionId;
      activeSseTransports[sessionId] = transport;
      print("Stored new SSE transport for session: $sessionId");

      transport.onclose = () {
        print(
          "SSE transport closed (Session: $sessionId). Removing from active list.",
        );
        activeSseTransports.remove(sessionId);
      };

      transport.onerror = (error) {
        print("Error on SSE transport (Session: $sessionId): $error");
      };

      final mcpServer = makeMcpServer();
      await mcpServer.connect(transport);
      print("SSE transport connected, session ID: $sessionId");
    } catch (e) {
      print("Error setting up SSE connection: $e");
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
    print("Received POST to $messagePath (Session ID: $sessionId)");

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
      print("No active SSE transport found for session ID: $sessionId");
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
