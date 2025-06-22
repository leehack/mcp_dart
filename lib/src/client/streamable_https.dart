import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:eventflux/eventflux.dart';
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

  /// A custom HTTP client adapter, mainly for testing purposes.
  final HttpClientAdapter? httpClientAdapter;

  const StreamableHttpClientTransportOptions({
    this.authProvider,
    this.requestInit,
    this.reconnectionOptions,
    this.sessionId,
    this.httpClientAdapter,
  });
}

/// Client transport for Streamable HTTP: this implements the MCP Streamable HTTP transport specification.
/// It will connect to a server using HTTP POST for sending messages and HTTP GET with Server-Sent Events
/// for receiving messages.
class StreamableHttpClientTransport implements Transport {
  final EventFlux _eventFlux;
  final http.Client _httpClient;
  final Uri _url;
  final Map<String, dynamic>? _requestInit;
  final OAuthClientProvider? _authProvider;
  String? _sessionId;
  final StreamableHttpReconnectionOptions _reconnectionOptions;
  final HttpClientAdapter? _httpClientAdapter;
  bool _isClosed = false;
  int _reconnectionAttempts = 0;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  StreamableHttpClientTransport(
    Uri url, {
    StreamableHttpClientTransportOptions? opts,
    http.Client? httpClient,
  })  : _url = url,
        _requestInit = opts?.requestInit,
        _authProvider = opts?.authProvider,
        _sessionId = opts?.sessionId,
        _reconnectionOptions = opts?.reconnectionOptions ??
            _defaultStreamableHttpReconnectionOptions,
        _eventFlux = EventFlux.spawn(),
        _httpClientAdapter = opts?.httpClientAdapter,
        _httpClient = httpClient ?? http.Client();

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

    return await _startSseConnection(const StartSseOptions());
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

  void _handleConnectionError(dynamic error) {
    if (_isClosed) return;

    onerror?.call(
        StreamableHttpError(0, 'SSE connection error: ${error.toString()}'));

    if (_reconnectionAttempts < _reconnectionOptions.maxRetries) {
      final delay = (_reconnectionOptions.initialReconnectionDelay *
              math.pow(_reconnectionOptions.reconnectionDelayGrowFactor,
                  _reconnectionAttempts))
          .toInt();

      final cappedDelay =
          math.min(delay, _reconnectionOptions.maxReconnectionDelay);

      _reconnectionAttempts++;
      Future.delayed(Duration(milliseconds: cappedDelay), () {
        if (!_isClosed) {
          _startSseConnection(const StartSseOptions());
        }
      });
    } else {
      close();
    }
  }

  Future<void> _startSseConnection(StartSseOptions options) async {
    if (_isClosed) return;

    try {
      final headers = await _commonHeaders();
      headers['Accept'] = 'text/event-stream';
      headers['Cache-Control'] = 'no-cache';

      if (options.resumptionToken != null) {
        headers['last-event-id'] = options.resumptionToken!;
      }

      _eventFlux.connect(
        EventFluxConnectionType.get,
        _url.toString(),
        header: headers,
        httpClient: _httpClientAdapter,
        onSuccessCallback: (response) {
          _reconnectionAttempts = 0; // Reset on successful connection
          response?.stream?.listen(
            (event) {
              _handleSseMessage(event, options);
            },
            onError: _handleConnectionError,
            onDone: () {
              if (!_isClosed) {
                _handleConnectionError('SSE stream closed unexpectedly');
              }
            },
          );
        },
        onError: (e) {
          if (e.statusCode == 401 && _authProvider != null) {
            _authThenStart();
          } else {
            _handleConnectionError(e);
          }
        },
      );
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  void _handleSseMessage(EventFluxData event, StartSseOptions sseOptions) {
    if (event.data.isEmpty) {
      return;
    }

    if (sseOptions.onResumptionToken != null) {
      sseOptions.onResumptionToken!(event.id);
    }

    try {
      final decodedData = jsonDecode(event.data);
      if (decodedData is Map<String, dynamic>) {
        final message = JsonRpcMessage.fromJson(decodedData);
        onmessage?.call(message);
      }
    } catch (e) {
      onerror?.call(McpError(-32700, 'Error parsing SSE message: $e'));
    }
  }

  @override
  Future<void> start() async {
    // With this new model, connection is lazily established when initialized is sent.
    // If auth is needed, it will be triggered by the first send.
    // We could pre-emptively auth here if desired.
    return Future.value();
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
    if (!_isClosed) {
      _isClosed = true;
      _eventFlux.disconnect();
      _httpClient.close();
      onclose?.call();
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_isClosed) {
      throw McpError(0, 'Transport is closed');
    }

    // Check for authentication first
    if (_authProvider != null) {
      final tokens = await _authProvider!.tokens();
      if (tokens == null) {
        await _authProvider!.redirectToAuthorization();
        throw UnauthorizedError('Authentication required');
      }
    }

    final headers = await _commonHeaders();
    headers['Content-Type'] = 'application/json';

    try {
      final response = await _httpClient.post(
        _url,
        headers: headers,
        body: jsonEncode(message.toJson()),
      );

      _sessionId ??= response.headers['mcp-session-id'];

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (message is JsonRpcRequest && response.body.isNotEmpty) {
          final responseBody = jsonDecode(response.body);
          final responseMessage = JsonRpcMessage.fromJson(responseBody);
          onmessage?.call(responseMessage);
        }
        if (message is JsonRpcInitializedNotification) {
          // After initialized, we start the SSE connection
          _startSseConnection(const StartSseOptions());
        }
      } else {
        throw StreamableHttpError(
          response.statusCode,
          'Failed to send message: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      final error =
          e is Error ? e : StreamableHttpError(0, 'Failed to send message: $e');
      onerror?.call(error);
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
    try {
      final headers = await _commonHeaders();

      final client = http.Client();
      final request = await client.delete(_url, headers: headers);

      if (request.statusCode < 200 || request.statusCode >= 300) {
        throw McpError(0, "Error from DELETE: ${request.reasonPhrase}");
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

  /// Re-authenticates if necessary and reconnects the SSE stream.
  Future<void> resume(StartSseOptions options) async {
    if (_isClosed) {
      throw McpError(0, 'Transport is closed');
    }
    return await _startSseConnection(options);
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
