import 'dart:io';

import 'package:mcp_dart/src/shared/logging.dart';

import 'mcp_server.dart';
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

  /// Enables host/origin validation to mitigate DNS rebinding attacks.
  final bool enableDnsRebindingProtection;

  /// Explicit host allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedHosts;

  /// Explicit origin allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedOrigins;

  SseServerManager(
    this.mcpServer, {
    this.ssePath = '/sse',
    this.messagePath = '/messages',
    this.enableDnsRebindingProtection = false,
    this.allowedHosts,
    this.allowedOrigins,
  });

  /// Routes incoming HTTP requests to appropriate handlers.
  Future<void> handleRequest(HttpRequest request) async {
    _logger.debug("Received request: ${request.method} ${request.uri.path}");

    if (enableDnsRebindingProtection &&
        !_isRequestAllowedByDnsRebindingProtection(request)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden: blocked by DNS rebinding protection');
      await request.response.close();
      return;
    }

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
    _logger.debug("Client connecting for SSE at /sse...");
    SseServerTransport? transport;

    try {
      transport = SseServerTransport(
        response: request.response,
        messageEndpointPath: messagePath,
      );

      final sessionId = transport.sessionId;
      activeSseTransports[sessionId] = transport;
      _logger.debug("Stored new SSE transport for session: $sessionId");

      transport.onclose = () {
        _logger.debug(
          "SSE transport closed (Session: $sessionId). Removing from active list.",
        );
        activeSseTransports.remove(sessionId);
      };

      transport.onerror = (error) {
        _logger.warn("Error on SSE transport (Session: $sessionId): $error");
      };

      await mcpServer.connect(transport);
      _logger.debug("SSE transport connected, session ID: $sessionId");
    } catch (e) {
      _logger.warn("Error setting up SSE connection: $e");
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
    _logger.debug("Received POST to $messagePath (Session ID: $sessionId)");

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
      _logger.debug("No active SSE transport found for session ID: $sessionId");
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

  bool _isRequestAllowedByDnsRebindingProtection(HttpRequest request) {
    final hostHeader = request.headers.value(HttpHeaders.hostHeader);
    if (hostHeader == null || hostHeader.trim().isEmpty) {
      return false;
    }

    final allowedHostSet = _normalizedAllowedHosts();
    if (!_isHostAllowed(hostHeader, allowedHostSet)) {
      return false;
    }

    final originHeader = request.headers.value('origin');
    if (originHeader == null || originHeader.trim().isEmpty) {
      return true;
    }

    if (originHeader.trim().toLowerCase() == 'null') {
      return false;
    }

    final configuredOrigins = _normalizedAllowedOrigins();
    if (configuredOrigins != null) {
      final normalizedOrigin = _normalizeOrigin(originHeader);
      return normalizedOrigin != null &&
          configuredOrigins.contains(normalizedOrigin);
    }

    final originUri = Uri.tryParse(originHeader);
    if (originUri == null || originUri.host.isEmpty) {
      return false;
    }

    final originHost = _extractHost(originUri.host);
    return allowedHostSet.contains(originHost);
  }

  Set<String> _normalizedAllowedHosts() {
    final configuredHosts = allowedHosts;
    if (configuredHosts != null && configuredHosts.isNotEmpty) {
      return configuredHosts.map(_extractHost).toSet();
    }

    return {
      'localhost',
      '127.0.0.1',
      '::1',
    };
  }

  Set<String>? _normalizedAllowedOrigins() {
    final configuredOrigins = allowedOrigins;
    if (configuredOrigins == null || configuredOrigins.isEmpty) {
      return null;
    }

    return configuredOrigins.map(_normalizeOrigin).whereType<String>().toSet();
  }

  bool _isHostAllowed(String hostHeader, Set<String> allowedHosts) {
    final rawHost = hostHeader.trim().toLowerCase();
    final normalizedHost = _extractHost(rawHost);

    if (allowedHosts.contains(rawHost)) {
      return true;
    }

    return allowedHosts.contains(normalizedHost);
  }

  String _extractHost(String hostOrOrigin) {
    final lower = hostOrOrigin.trim().toLowerCase();

    if (lower.contains('://')) {
      final parsedUri = Uri.tryParse(lower);
      if (parsedUri != null && parsedUri.host.isNotEmpty) {
        return _extractHost(parsedUri.host);
      }
    }

    if (lower.startsWith('[')) {
      final end = lower.indexOf(']');
      if (end > 1) {
        return lower.substring(1, end);
      }
    }

    final firstColon = lower.indexOf(':');
    final lastColon = lower.lastIndexOf(':');
    if (firstColon != -1 && firstColon == lastColon) {
      return lower.substring(0, firstColon);
    }

    return lower;
  }

  String? _normalizeOrigin(String origin) {
    final parsedUri = Uri.tryParse(origin.trim());
    if (parsedUri == null ||
        parsedUri.scheme.isEmpty ||
        parsedUri.host.isEmpty) {
      return null;
    }

    final normalizedHost = _extractHost(parsedUri.host);
    final portPart = parsedUri.hasPort ? ':${parsedUri.port}' : '';
    return '${parsedUri.scheme.toLowerCase()}://$normalizedHost$portPart';
  }
}
