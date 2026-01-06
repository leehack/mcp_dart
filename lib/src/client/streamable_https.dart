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

  /// Whether to attempt reconnection when the stream closes.
  /// Default is true.
  final bool shouldReconnect;

  const StartSseOptions({
    this.resumptionToken,
    this.onResumptionToken,
    this.replayMessageId,
    this.shouldReconnect = true,
  });
}

/// Configuration options for reconnection behavior of the StreamableHttpClientTransport.
class StreamableHttpReconnectionOptions {
  /// Maximum backoff time between reconnection attempts in milliseconds.
  /// Default is 30000 (30 seconds).
  final int maxReconnectionDelay;

  /// Initial backoff time between reconnection attempts in milliseconds.
  /// Default is 1000 (1 second).
  final int initialReconnectionDelay;

  /// The factor by which the reconnection delay increases after each attempt.
  /// Default is 1.5.
  final double reconnectionDelayGrowFactor;

  /// Maximum number of reconnection attempts before giving up.
  /// Default is 2.
  final int maxRetries;

  const StreamableHttpReconnectionOptions({
    required this.maxReconnectionDelay,
    required this.initialReconnectionDelay,
    required this.reconnectionDelayGrowFactor,
    required this.maxRetries,
  });
}

/// Configuration options for the `StreamableHttpClientTransport`.
class StreamableHttpClientTransportOptions {
  /// An OAuth client provider to use for authentication.
  ///
  /// When an `authProvider` is specified and the connection is started:
  /// 1. The connection is attempted with any existing access token from the `authProvider`.
  /// 2. If the access token has expired, the `authProvider` is used to refresh the token.
  /// 3. If token refresh fails or no access token exists, and auth is required,
  ///    `OAuthClientProvider.redirectToAuthorization` is called, and an `UnauthorizedError`
  ///    will be thrown from `connect`/`start`.
  ///
  /// After the user has finished authorizing via their user agent, and is redirected
  /// back to the MCP client application, call `StreamableHttpClientTransport.finishAuth`
  /// with the authorization code before retrying the connection.
  ///
  /// If an `authProvider` is not provided, and auth is required, an `UnauthorizedError`
  /// will be thrown.
  ///
  /// `UnauthorizedError` might also be thrown when sending any message over the transport,
  /// indicating that the session has expired, and needs to be re-authed and reconnected.
  final OAuthClientProvider? authProvider;

  /// Customizes HTTP requests to the server.
  final Map<String, dynamic>? requestInit;

  /// Options to configure the reconnection behavior.
  final StreamableHttpReconnectionOptions? reconnectionOptions;

  /// Session ID for the connection. This is used to identify the session on the server.
  /// When not provided and connecting to a server that supports session IDs,
  /// the server will generate a new session ID.
  final String? sessionId;

  const StreamableHttpClientTransportOptions({
    this.authProvider,
    this.requestInit,
    this.reconnectionOptions,
    this.sessionId,
  });
}

/// Client transport for Streamable HTTP: this implements the MCP Streamable HTTP transport specification.
/// It will connect to a server using HTTP POST for sending messages and HTTP GET with Server-Sent Events
/// for receiving messages.
class StreamableHttpClientTransport implements Transport {
  StreamController<bool>? _abortController;
  final Uri _url;
  final Map<String, dynamic>? _requestInit;
  final OAuthClientProvider? _authProvider;
  String? _sessionId;
  final StreamableHttpReconnectionOptions _reconnectionOptions;
  bool _isClosed = false;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  final http.Client _httpClient;

  StreamableHttpClientTransport(
    Uri url, {
    StreamableHttpClientTransportOptions? opts,
  })  : _url = url,
        _requestInit = opts?.requestInit,
        _authProvider = opts?.authProvider,
        _sessionId = opts?.sessionId,
        _reconnectionOptions = opts?.reconnectionOptions ??
            _defaultStreamableHttpReconnectionOptions,
        _httpClient = http.Client();

  Future<void> _authThenStart() async {
    if (_authProvider == null) {
      throw UnauthorizedError("No auth provider");
    }

    AuthResult result;
    try {
      result = await auth(_authProvider!, serverUrl: _url);
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(McpError(0, error.toString()));
      }
      rethrow;
    }

    if (result != "AUTHORIZED") {
      throw UnauthorizedError();
    }

    return await _startOrAuthSse(const StartSseOptions());
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

  Future<void> _startOrAuthSse(StartSseOptions options) async {
    final resumptionToken = options.resumptionToken;
    try {
      // Try to open an initial SSE stream with GET to listen for server messages
      // This is optional according to the spec - server may not support it
      final headers = await _commonHeaders();
      headers['Accept'] = "text/event-stream";

      // Include Last-Event-ID header for resumable streams if provided
      if (resumptionToken != null) {
        headers['last-event-id'] = resumptionToken;
      }

      final request = http.Request('GET', _url);
      request.headers.addAll(headers);
      final response = await _httpClient.send(request);

      if (response.statusCode != 200) {
        if (response.statusCode == 401 && _authProvider != null) {
          // Need to authenticate
          return await _authThenStart();
        }

        // 405 indicates that the server does not offer an SSE stream at GET endpoint
        // This is an expected case that should not trigger an error
        if (response.statusCode == 405) {
          return;
        }

        throw StreamableHttpError(
          response.statusCode,
          "Failed to open SSE stream: ${response.reasonPhrase}",
        );
      }

      _handleSseStream(response, options);
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        final err = McpError(0, error.toString());
        onerror?.call(err);
      }
      rethrow;
    }
  }

  /// Calculates the next reconnection delay using backoff algorithm
  ///
  /// @param attempt Current reconnection attempt count for the specific stream
  /// @returns Time to wait in milliseconds before next reconnection attempt
  int _getNextReconnectionDelay(int attempt) {
    // Access default values directly, ensuring they're never undefined
    final initialDelay = _reconnectionOptions.initialReconnectionDelay;
    final growFactor = _reconnectionOptions.reconnectionDelayGrowFactor;
    final maxDelay = _reconnectionOptions.maxReconnectionDelay;

    // Cap at maximum delay
    return (initialDelay * math.pow(growFactor, attempt))
        .round()
        .clamp(0, maxDelay);
  }

  /// Schedule a reconnection attempt with exponential backoff
  ///
  /// @param options The SSE connection options
  /// @param attemptCount Current reconnection attempt count for this specific stream
  void _scheduleReconnection(StartSseOptions options, [int attemptCount = 0]) {
    // Use provided options or default options
    final maxRetries = _reconnectionOptions.maxRetries;

    // Check if we've exceeded maximum retry attempts
    if (maxRetries > 0 && attemptCount >= maxRetries) {
      onerror?.call(
        McpError(0, "Maximum reconnection attempts ($maxRetries) exceeded."),
      );
      return;
    }

    // Calculate next delay based on current attempt count
    final delay = _getNextReconnectionDelay(attemptCount);

    // Schedule the reconnection
    Future.delayed(Duration(milliseconds: delay), () {
      // Use the last event ID to resume where we left off
      _startOrAuthSse(options).catchError((error) {
        final errorMessage =
            error is Error ? error.toString() : error.toString();
        onerror?.call(
          McpError(0, "Failed to reconnect SSE stream: $errorMessage"),
        );

        // Schedule another attempt if this one failed, incrementing the attempt counter
        _scheduleReconnection(options, attemptCount + 1);

        // Ensure the Future completes
        return null;
      });
    });
  }

  void _handleSseStream(http.StreamedResponse stream, StartSseOptions options) {
    final onResumptionToken = options.onResumptionToken;
    final replayMessageId = options.replayMessageId;

    String? lastEventId;
    String buffer = '';
    String? eventName;
    String? eventId;
    String? eventData;

    // Function to process a complete SSE event
    void processEvent() {
      if (eventData == null) return;

      // Update last event ID if provided
      if (eventId != null) {
        lastEventId = eventId;
        onResumptionToken?.call(eventId!);
      }

      if (eventName == null || eventName == 'message') {
        try {
          final message = JsonRpcMessage.fromJson(jsonDecode(eventData!));

          // Can't set id directly if it's final, need to create a new message
          if (replayMessageId != null && message is JsonRpcResponse) {
            // Create a new response with the same data but different ID
            final newMessage = JsonRpcResponse(
              id: replayMessageId,
              result: message.result,
              meta: message.meta,
            );
            onmessage?.call(newMessage);
          } else {
            onmessage?.call(message);
          }
        } catch (error) {
          if (error is Error) {
            onerror?.call(error);
          } else {
            onerror?.call(McpError(0, error.toString()));
          }
        }
      }

      // Reset for next event
      eventName = null;
      eventId = null;
      eventData = null;
    }

    // Helper function to handle reconnection logic
    void handleReconnection(String? eventId, String errorMessage) {
      if (_isClosed || !options.shouldReconnect) return;

      if (_abortController != null && !_abortController!.isClosed) {
        if (eventId != null) {
          try {
            _scheduleReconnection(
              StartSseOptions(
                resumptionToken: eventId,
                onResumptionToken: onResumptionToken,
                replayMessageId: replayMessageId,
                shouldReconnect: options.shouldReconnect,
              ),
            );
          } catch (error) {
            final errorMessage =
                error is Error ? error.toString() : error.toString();
            onerror?.call(McpError(0, "Failed to reconnect: $errorMessage"));
          }
        }
      }
    }

    // Convert the stream to a broadcast stream to allow multiple listeners if needed
    final broadcastStream = stream.stream;

    // Create a subscription to the stream
    final subscription =
        broadcastStream.transform(utf8.decoder).asBroadcastStream().listen(
      (data) {
        buffer += data;

        // Process the buffer line by line
        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          var line = buffer.substring(0, index);
          if (line.endsWith('\r')) {
            line = line.substring(0, line.length - 1);
          }
          buffer = buffer.substring(index + 1);

          if (line.isEmpty) {
            // Empty line means end of event
            processEvent();
            continue;
          }

          if (line.startsWith(':')) {
            // Comment line, ignore
            continue;
          }

          final colonIndex = line.indexOf(':');
          if (colonIndex > 0) {
            final field = line.substring(0, colonIndex);
            // The value starts after colon + optional space
            final valueStart = colonIndex +
                1 +
                (line.length > colonIndex + 1 && line[colonIndex + 1] == ' '
                    ? 1
                    : 0);
            final value = line.substring(valueStart);

            switch (field) {
              case 'event':
                eventName = value;
                break;
              case 'id':
                eventId = value;
                break;
              case 'data':
                eventData = (eventData ?? '') + value;
                break;
            }
          }
        }
      },
      onDone: () {
        // Process any final event
        processEvent();

        // Handle stream closure - likely a network disconnect
        handleReconnection(lastEventId, "Stream closed");
      },
      onError: (error) {
        final errorMessage =
            error is Error ? error.toString() : error.toString();
        onerror?.call(McpError(0, "SSE stream disconnected: $errorMessage"));

        // Attempt to reconnect if the stream disconnects unexpectedly
        handleReconnection(lastEventId, errorMessage);
      },
    );

    // Register the subscription cleanup when the abort controller is triggered
    _abortController?.stream.listen((_) {
      subscription.cancel();
    });
  }

  @override
  Future<void> start() async {
    if (_abortController != null) {
      throw McpError(
        0,
        "StreamableHttpClientTransport already started! If using Client class, note that connect() calls start() automatically.",
      );
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

    final result = await auth(
      _authProvider!,
      serverUrl: _url,
      authorizationCode: authorizationCode,
    );
    if (result != "AUTHORIZED") {
      throw UnauthorizedError("Failed to authorize");
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    // Abort any pending requests
    _abortController?.add(true);
    _abortController?.close();
    _httpClient.close();

    onclose?.call();
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
    String? resumptionToken,
    void Function(String)? onResumptionToken,
  }) async {
    try {
      if (resumptionToken != null) {
        // If we have a last event ID, we need to reconnect the SSE stream
        final replayId = message is JsonRpcRequest ? message.id : null;
        _startOrAuthSse(
          StartSseOptions(
            resumptionToken: resumptionToken,
            replayMessageId: replayId,
            onResumptionToken: onResumptionToken,
          ),
        ).catchError((err) {
          if (err is Error) {
            onerror?.call(err);
          } else {
            onerror?.call(McpError(0, err.toString()));
          }
        });
        return;
      }

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

      final request = http.Request('POST', _url);
      request.headers.addAll(headers);
      request.body = jsonEncode(message.toJson());

      final response = await _httpClient.send(request);

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

        final text = await response.stream.transform(utf8.decoder).join();
        throw McpError(
          0,
          "Error POSTing to endpoint (HTTP ${response.statusCode}): $text",
        );
      }

      // If the response is 202 Accepted, there's no body to process
      if (response.statusCode == 202) {
        // Ensure we drain the stream to release the connection
        await response.stream.drain();

        await Future.delayed(Duration.zero);

        // if the accepted notification is initialized, we start the SSE stream
        // if it's supported by the server
        if (_isInitializedNotification(message)) {
          // Start without a lastEventId since this is a fresh connection
          _startOrAuthSse(const StartSseOptions()).catchError((err) {
            if (err is Error) {
              onerror?.call(err);
            } else {
              onerror?.call(McpError(0, err.toString()));
            }
          });
        }
        return;
      }

      // Start SSE if this was the initialized notification, even if 200 OK
      if (_isInitializedNotification(message)) {
        _startOrAuthSse(const StartSseOptions()).catchError((err) {
          if (err is Error) {
            onerror?.call(err);
          } else {
            onerror?.call(McpError(0, err.toString()));
          }
        });
      }

      // Check if the message is a request that expects a response
      final hasRequests = message is JsonRpcRequest && message.id != null;

      // Check the response type
      final contentType = response.headers['content-type'];

      if (hasRequests) {
        if (contentType?.contains('text/event-stream') ?? false) {
          // Handle SSE stream responses for requests
          _handleSseStream(
            response,
            StartSseOptions(
              onResumptionToken: onResumptionToken,
              shouldReconnect: false, // Do not reconnect for POST responses
            ),
          );
        } else if (contentType?.contains('application/json') ?? false) {
          // For non-streaming servers, we might get direct JSON responses
          final jsonStr = await response.stream.transform(utf8.decoder).join();
          final data = jsonDecode(jsonStr);

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
  ///
  /// Clients that no longer need a particular session
  /// (e.g., because the user is leaving the client application) SHOULD send an
  /// HTTP DELETE to the MCP endpoint with the Mcp-Session-Id header to explicitly
  /// terminate the session.
  ///
  /// The server MAY respond with HTTP 405 Method Not Allowed, indicating that
  /// the server does not allow clients to terminate sessions.
  Future<void> terminateSession() async {
    if (_sessionId == null) {
      return; // No session to terminate
    }

    try {
      final headers = await _commonHeaders();

      final response = await _httpClient.delete(_url, headers: headers);

      // We specifically handle 405 as a valid response according to the spec,
      // meaning the server does not support explicit session termination
      if (response.statusCode < 200 ||
          response.statusCode >= 300 && response.statusCode != 405) {
        throw StreamableHttpError(
          response.statusCode,
          "Failed to terminate session: ${response.reasonPhrase}",
        );
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
    if (message is JsonRpcNotification) {
      return message.method == "notifications/initialized";
    }
    return false;
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
Future<AuthResult> auth(
  OAuthClientProvider provider, {
  required Uri serverUrl,
  String? authorizationCode,
}) async {
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
