import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

/// Default reconnection options for StreamableHTTP connections
const _defaultStreamableHttpReconnectionOptions =
    StreamableHttpReconnectionOptions(
  initialReconnectionDelay: 1000,
  maxReconnectionDelay: 30000,
  reconnectionDelayGrowFactor: 1.5,
  maxRetries: 2,
);

/// Error thrown for Streamable HTTP issues
class StreamableHttpError extends Error {
  /// HTTP status code if applicable
  final int? code;

  /// Error message
  final String message;

  StreamableHttpError(this.code, this.message);

  @override
  String toString() => 'Streamable HTTP error: $message';
}

/// Options for starting or authenticating an SSE connection
class StartSseOptions {
  /// The resumption token used to continue long-running requests that were interrupted.
  /// This allows clients to reconnect and continue from where they left off.
  final String? resumptionToken;

  /// A callback that is invoked when the resumption token changes.
  /// This allows clients to persist the latest token for potential reconnection.
  final void Function(String token)? onResumptionToken;

  /// Override Message ID to associate with the replay message
  /// so that response can be associated with the new resumed request.
  final dynamic replayMessageId;

  const StartSseOptions({
    this.resumptionToken,
    this.onResumptionToken,
    this.replayMessageId,
  });
}

/// Configuration options for reconnection behavior of the StreamableHttpClientTransport.
class StreamableHttpReconnectionOptions {
  /// Initial delay before the first reconnection attempt in milliseconds.
  final int initialReconnectionDelay;

  /// Maximum delay between reconnection attempts in milliseconds.
  final int maxReconnectionDelay;

  /// Factor by which the delay increases after each failed reconnection attempt.
  final double reconnectionDelayGrowFactor;

  /// Maximum number of reconnection attempts before giving up.
  final int maxRetries;

  const StreamableHttpReconnectionOptions({
    required this.initialReconnectionDelay,
    required this.maxReconnectionDelay,
    required this.reconnectionDelayGrowFactor,
    required this.maxRetries,
  });
}

/// Configuration options for the `StreamableHttpClientTransport`.
class StreamableHttpClientTransportOptions {
  /// Optional OAuth client provider for authentication.
  final OAuthClientProvider? authProvider;

  /// Customizes HTTP requests to the server.
  final Map<String, dynamic>? requestInit;

  /// Options to configure the reconnection behavior.
  final StreamableHttpReconnectionOptions? reconnectionOptions;

  /// Session ID for the connection.
  final String? sessionId;

  const StreamableHttpClientTransportOptions({
    this.authProvider,
    this.requestInit,
    this.reconnectionOptions,
    this.sessionId,
  });
}

/// Web implementation of StreamableHttpClientTransport using package:http
class StreamableHttpClientTransport implements Transport {
  StreamController<bool>? _abortController;
  final Uri _url;
  final Map<String, dynamic>? _requestInit;
  final OAuthClientProvider? _authProvider;
  String? _sessionId;
  final StreamableHttpReconnectionOptions _reconnectionOptions;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  StreamableHttpClientTransport(
    this._url, {
    StreamableHttpClientTransportOptions? opts,
  })  : _requestInit = opts?.requestInit,
        _authProvider = opts?.authProvider,
        _sessionId = opts?.sessionId,
        _reconnectionOptions = opts?.reconnectionOptions ??
            _defaultStreamableHttpReconnectionOptions;

  /// Parses Server-Sent Events response and extracts JSON messages
  void _parseSseResponse(String sseData) {
    final lines = sseData.split('\n');
    String? eventData;

    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.isEmpty) {
        // Empty line indicates end of event - process it
        if (eventData != null) {
          try {
            final jsonData = jsonDecode(eventData);
            final message = JsonRpcMessage.fromJson(jsonData);
            onmessage?.call(message);
          } catch (e) {
            // Ignore malformed JSON in SSE events
          }
        }
        
        // Reset for next event
        eventData = null;
      } else if (trimmed.startsWith('data:')) {
        final dataValue = trimmed.substring(5).trim();
        eventData = eventData == null ? dataValue : '$eventData\n$dataValue';
      }
      // Ignore other SSE fields like event:, id:, retry:
    }
    
    // Process final event if no trailing empty line
    if (eventData != null) {
      try {
        final jsonData = jsonDecode(eventData);
        final message = JsonRpcMessage.fromJson(jsonData);
        onmessage?.call(message);
      } catch (e) {
        // Ignore malformed JSON in SSE events
      }
    }
  }

  Future<Map<String, String>> _commonHeaders() async {
    final headers = <String, String>{};

    if (_authProvider != null) {
      final tokens = await _authProvider!.tokens();
      if (tokens != null) {
        headers["Authorization"] = "Bearer ${tokens.accessToken}";
      }
    }

    if (_sessionId != null) {
      headers["mcp-session-id"] = _sessionId!;
    }

    if (_requestInit != null && _requestInit!.containsKey('headers')) {
      final requestHeaders = _requestInit!['headers'] as Map<String, dynamic>;
      for (final entry in requestHeaders.entries) {
        headers[entry.key] = entry.value.toString();
      }
    }

    return headers;
  }

  @override
  Future<void> start() async {
    if (_abortController != null) {
      throw McpError(0,
          "StreamableHttpClientTransport already started! If using Client class, note that connect() calls start() automatically.");
    }

    _abortController = StreamController<bool>.broadcast();
  }

  /// Call this method after the user has finished authorizing via their user agent and is redirected
  /// back to the MCP client application. This will exchange the authorization code for an access token,
  /// enabling the next connection attempt to successfully auth.
  Future<void> finishAuth(String authorizationCode) async {
    if (_authProvider == null) {
      throw UnauthorizedError("No auth provider");
    }

    final result = await auth(_authProvider!,
        serverUrl: _url, authorizationCode: authorizationCode);
    if (result != "AUTHORIZED") {
      throw UnauthorizedError("Failed to authorize");
    }
  }

  @override
  Future<void> close() async {
    // Abort any pending requests
    _abortController?.add(true);
    _abortController?.close();

    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message,
      {String? resumptionToken,
      void Function(String)? onResumptionToken}) async {
    try {
      // Check for authentication first - if we need auth, handle it before proceeding
      if (_authProvider != null) {
        final tokens = await _authProvider!.tokens();
        if (tokens == null) {
          // No tokens available - trigger authentication flow
          await _authProvider!.redirectToAuthorization();
          throw UnauthorizedError('Authentication required');
        }
      }

      final headers = await _commonHeaders();
      headers['content-type'] = 'application/json';
      headers['accept'] = 'application/json, text/event-stream';

      // Add body
      final bodyJson = jsonEncode(message.toJson());

      final response = await http.post(
        _url,
        headers: headers,
        body: bodyJson,
      );

      // Handle session ID received during initialization
      final sessionId = response.headers['mcp-session-id'];
      if (sessionId != null) {
        _sessionId = sessionId;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && _authProvider != null) {
          // Authentication failed with the server - try to refresh or redirect
          await _authProvider!.redirectToAuthorization();
          throw UnauthorizedError('Authentication failed with the server');
        }

        throw McpError(0,
            "Error POSTing to endpoint (HTTP ${response.statusCode}): ${response.body}");
      }

      // If the response is 202 Accepted, there's no body to process
      if (response.statusCode == 202) {
        return;
      }

      // Check if the message is a request that expects a response
      final hasRequests = message is JsonRpcRequest && message.id != null;

      // Check the response type
      final contentType = response.headers['content-type'];

      if (hasRequests) {
        if (contentType?.contains('text/event-stream') ?? false) {
          // Handle SSE stream responses for requests
          _parseSseResponse(response.body);
        } else if (contentType?.contains('application/json') ?? false) {
          // For non-streaming servers, we might get direct JSON responses
          final data = jsonDecode(response.body);

          if (data is List) {
            for (final item in data) {
              final msg = JsonRpcMessage.fromJson(item);
              onmessage?.call(msg);
            }
          } else {
            final msg = JsonRpcMessage.fromJson(data);
            onmessage?.call(msg);
          }
        } else {
          throw StreamableHttpError(
            -1,
            "Unexpected content type: $contentType",
          );
        }
      }
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(McpError(0, error.toString()));
      }
      rethrow;
    }
  }

  @override
  String? get sessionId => _sessionId;

  /// Terminates the current session by sending a DELETE request to the server.
  Future<void> terminateSession() async {
    if (_sessionId == null) {
      return; // No session to terminate
    }

    try {
      final headers = await _commonHeaders();

      final response = await http.delete(
        _url,
        headers: headers,
      );

      // We specifically handle 405 as a valid response according to the spec,
      // meaning the server does not support explicit session termination
      if (response.statusCode < 200 ||
          response.statusCode >= 300 && response.statusCode != 405) {
        throw StreamableHttpError(response.statusCode,
            "Failed to terminate session: ${response.body}");
      }

      _sessionId = null;
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(McpError(0, error.toString()));
      }
      rethrow;
    }
  }

  // Helper method to check if a message is an initialized notification
  bool _isInitializedNotification(JsonRpcMessage message) {
    return message is JsonRpcInitializedNotification;
  }
}

/// Represents an unauthorized error
class UnauthorizedError extends Error {
  final String? message;

  UnauthorizedError([this.message]);

  @override
  String toString() => 'Unauthorized${message != null ? ': $message' : ''}';
}

/// Represents an OAuth client provider for authentication
abstract class OAuthClientProvider {
  /// Get current tokens if available
  Future<OAuthTokens?> tokens();

  /// Redirect to authorization endpoint
  Future<void> redirectToAuthorization();
}

/// Represents OAuth tokens
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;

  OAuthTokens({required this.accessToken, this.refreshToken});
}

/// Result of an authentication attempt
typedef AuthResult = String; // "AUTHORIZED" or other values

/// Performs authentication with the provided OAuth client
Future<AuthResult> auth(OAuthClientProvider provider,
    {required Uri serverUrl, String? authorizationCode}) async {
  // Simple implementation that would need to be expanded in a real implementation
  final tokens = await provider.tokens();
  if (tokens != null) {
    return "AUTHORIZED";
  }

  // If we have an authorization code, we'd process it here
  if (authorizationCode != null) {
    // Implementation would include exchanging the code for tokens
    return "AUTHORIZED";
  }

  // Need to redirect for authorization
  await provider.redirectToAuthorization();
  return "NEEDS_AUTH";
}
