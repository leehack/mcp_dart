import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:mcp_dart/src/client/oauth_client_platform.dart'
    as oauth_platform;
import 'package:mcp_dart/src/shared/protocol_direction.dart';
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

const int _maxSafeHeaderInteger = 9007199254740991;
const int _minSafeHeaderInteger = -9007199254740991;
final Expando<String> _preRegisteredOAuthProviderIssuers =
    Expando<String>('pre-registered OAuth provider issuer');

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

class _StartSseOptions extends StartSseOptions {
  final RequestId? requestMessageId;
  final void Function()? onTerminalResponse;
  final void Function(Error error)? onRequestStreamEnd;
  final bool Function()? isRequestCancelled;
  final Future<void>? requestCancellationTrigger;
  final bool rejectServerRequests;

  const _StartSseOptions({
    super.resumptionToken,
    super.onResumptionToken,
    super.replayMessageId,
    this.requestMessageId,
    this.onTerminalResponse,
    this.onRequestStreamEnd,
    this.isRequestCancelled,
    this.requestCancellationTrigger,
    super.shouldReconnect,
    this.rejectServerRequests = false,
  });
}

class _RequestCancellation {
  final Completer<void> _trigger = Completer<void>();

  bool get isCancelled => _trigger.isCompleted;

  Future<void> get trigger => _trigger.future;

  void cancel() {
    if (!_trigger.isCompleted) {
      _trigger.complete();
    }
  }
}

class _HttpAbortBinding {
  final Completer<void> _abortTrigger = Completer<void>();
  // Cancelled by [dispose] after the bound request settles.
  // ignore: cancel_subscriptions
  StreamSubscription<bool>? _subscription;
  // Cancelled by [dispose] after the bound operation settles.
  // ignore: cancel_subscriptions
  StreamSubscription<void>? _additionalSubscription;

  _HttpAbortBinding(
    StreamController<bool>? controller, {
    Future<void>? requestAbortTrigger,
    Stream<void>? additionalAbortStream,
  }) {
    if (controller != null && !controller.isClosed) {
      _subscription = controller.stream.listen((_) {
        if (!_abortTrigger.isCompleted) {
          _abortTrigger.complete();
        }
      });
    }
    requestAbortTrigger?.then((_) {
      if (!_abortTrigger.isCompleted) {
        _abortTrigger.complete();
      }
    });
    _additionalSubscription = additionalAbortStream?.listen((_) {
      if (!_abortTrigger.isCompleted) {
        _abortTrigger.complete();
      }
    });
  }

  Future<void> get abortTrigger => _abortTrigger.future;

  Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    final additionalSubscription = _additionalSubscription;
    _additionalSubscription = null;
    await subscription?.cancel();
    await additionalSubscription?.cancel();
  }
}

class _RequestOperationGuard {
  final Future<void> abortTrigger;
  final void Function() _ensureCurrent;

  const _RequestOperationGuard({
    required this.abortTrigger,
    required void Function() ensureCurrent,
  }) : _ensureCurrent = ensureCurrent;

  void check() => _ensureCurrent();

  Future<T> run<T>(FutureOr<T> Function() operation) {
    final completion = Completer<T>();

    void completeCurrentError() {
      if (completion.isCompleted) {
        return;
      }
      try {
        _ensureCurrent();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
        return;
      }
      completion.completeError(
        StateError('A guarded HTTP operation was interrupted.'),
      );
    }

    unawaited(
      abortTrigger.then<void>(
        (_) => completeCurrentError(),
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        },
      ),
    );

    Future<T>.sync(() {
      _ensureCurrent();
      return operation();
    }).then<void>(
      (value) {
        if (completion.isCompleted) {
          return;
        }
        try {
          _ensureCurrent();
          completion.complete(value);
        } catch (error, stackTrace) {
          completion.completeError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (completion.isCompleted) {
          return;
        }
        try {
          _ensureCurrent();
          completion.completeError(error, stackTrace);
        } catch (interruption, interruptionStackTrace) {
          completion.completeError(interruption, interruptionStackTrace);
        }
      },
    );

    return completion.future;
  }
}

Future<T> _runRequestOperation<T>(
  _RequestOperationGuard? guard,
  FutureOr<T> Function() operation,
) =>
    guard?.run(operation) ?? Future<T>.sync(operation);

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

/// The role of a URI discovered while preparing an MCP OAuth flow.
enum OAuthEndpointKind {
  /// OAuth Protected Resource Metadata document.
  protectedResourceMetadata,

  /// Authorization-server issuer advertised by protected-resource metadata.
  authorizationServer,

  /// OAuth Authorization Server Metadata or OpenID Connect Discovery document.
  authorizationServerMetadata,

  /// Browser-facing authorization endpoint.
  authorizationEndpoint,

  /// Authorization-code token endpoint.
  tokenEndpoint,

  /// Dynamic client registration endpoint.
  registrationEndpoint,
}

/// Approves a discovered cross-origin OAuth URI.
///
/// The transport always requires HTTP(S), rejects user information and
/// fragments, and permits plaintext HTTP only between loopback endpoints. This
/// validator is consulted only when a discovered URI is outside the MCP
/// endpoint's origin and is not another loopback endpoint in a loopback flow.
typedef OAuthUriValidator = bool Function(
  Uri uri,
  OAuthEndpointKind endpointKind,
);

/// Configuration options for the `StreamableHttpClientTransport`.
class StreamableHttpClientTransportOptions {
  /// An OAuth client provider to use for authentication.
  ///
  /// Before each request, the transport asks the provider for its current
  /// tokens. The provider is responsible for returning a refreshed usable token
  /// when needed. If no token exists, or the server rejects it, an
  /// `OAuthAuthorizationCodeProvider` can be used for discovery and an
  /// authorization redirect. The request then throws `UnauthorizedError`.
  ///
  /// After the user has finished authorizing via their user agent, and is redirected
  /// back to the MCP client application, call
  /// `StreamableHttpClientTransport.finishAuthRedirect` with the authorization
  /// code and returned state before retrying the request.
  ///
  /// If an `authProvider` is not provided, and auth is required, an `UnauthorizedError`
  /// will be thrown.
  ///
  /// `UnauthorizedError` might also be thrown when sending any message over the transport,
  /// indicating that the session has expired, and needs to be re-authed and reconnected.
  final OAuthClientProvider? authProvider;

  /// Approves trusted cross-origin HTTPS endpoints discovered during OAuth.
  ///
  /// Same-origin endpoints are accepted by default. When the MCP endpoint is
  /// loopback, other loopback endpoints are also accepted for local development.
  /// All other discovered origins are rejected unless this callback returns
  /// `true`. Keep the policy narrow, normally by matching exact expected hosts.
  final OAuthUriValidator? oauthUriValidator;

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
    this.oauthUriValidator,
    this.requestInit,
    this.reconnectionOptions,
    this.sessionId,
  });
}

/// Client transport for Streamable HTTP: this implements the MCP Streamable HTTP transport specification.
/// It will connect to a server using HTTP POST for sending messages and HTTP GET with Server-Sent Events
/// for receiving messages.
class StreamableHttpClientTransport
    implements
        Transport,
        ProtocolVersionAwareTransport,
        RequestCancellationAwareTransport,
        ToolParameterHeaderAwareTransport {
  StreamController<bool>? _abortController;
  final Uri _url;
  final Map<String, dynamic>? _requestInit;
  final OAuthClientProvider? _authProvider;
  final OAuthUriValidator? _oauthUriValidator;
  String? _sessionId;
  String? _protocolVersion;
  ToolParameterHeaderMappings _toolParameterHeaderMappings = const {};
  int _sessionGeneration = 0;
  bool _staleSessionDetected = false;
  final StreamableHttpReconnectionOptions _reconnectionOptions;
  bool _isClosed = false;
  _PendingOAuthAuthorization? _pendingOAuthAuthorization;
  Object? _pendingOAuthAuthorizationOwner;
  String? _preRegisteredClientIssuer;
  String? _authorizationServerIssuer;
  final Map<String, _OAuthClientRegistration> _oauthRegistrations = {};
  final Set<String> _oauthRequestedScopes = {};
  final Map<RequestId, _RequestCancellation> _requestCancellations = {};
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();

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
        _oauthUriValidator = opts?.oauthUriValidator,
        _sessionId = opts?.sessionId,
        _reconnectionOptions = opts?.reconnectionOptions ??
            _defaultStreamableHttpReconnectionOptions,
        _httpClient = http.Client();

  bool _isAuthorizationRequiredResponse(
    int statusCode,
    Map<String, String> headers,
  ) {
    if (statusCode == 401) {
      return true;
    }
    if (statusCode != 403) {
      return false;
    }
    return _parseOAuthBearerChallenges(headers['www-authenticate'])
        .any((challenge) => challenge.error == 'insufficient_scope');
  }

  Future<void> _handleAuthorizationRequired(
    http.StreamedResponse response, {
    _RequestOperationGuard? requestGuard,
  }) async {
    final authProvider = _authProvider;
    if (authProvider == null) {
      await _drainAuthorizationResponse(response, requestGuard);
      throw UnauthorizedError('Authentication required');
    }

    final authenticateHeader = response.headers['www-authenticate'];
    final bearerChallenges = _parseOAuthBearerChallenges(authenticateHeader);
    OAuthBearerChallengeParameters? challenge;
    if (response.statusCode == 403) {
      for (final candidate in bearerChallenges) {
        if (candidate.error == 'insufficient_scope') {
          challenge = candidate;
          break;
        }
      }
    }
    challenge ??= OAuthBearerChallengeParameters.fromHeader(
      authenticateHeader,
    );
    await _drainAuthorizationResponse(response, requestGuard);

    if (authProvider is OAuthAuthorizationCodeProvider) {
      Object? authorizationOwner;
      try {
        final preparedAuthorization = await _prepareAuthorizationRequest(
          authProvider,
          challenge,
          requestGuard: requestGuard,
        );
        requestGuard?.check();
        authorizationOwner = Object();
        _pendingOAuthAuthorization = preparedAuthorization.pending;
        _pendingOAuthAuthorizationOwner = authorizationOwner;
        await _runRequestOperation(
          requestGuard,
          () => authProvider.redirectToAuthorizationUrl(
            preparedAuthorization.request.authorizationUri,
          ),
        );
        throw UnauthorizedError('Authentication required');
      } catch (error, stackTrace) {
        if (requestGuard != null) {
          try {
            requestGuard.check();
          } catch (interruption, interruptionStackTrace) {
            if (authorizationOwner != null &&
                identical(
                  _pendingOAuthAuthorizationOwner,
                  authorizationOwner,
                )) {
              _pendingOAuthAuthorization = null;
              _pendingOAuthAuthorizationOwner = null;
            }
            Error.throwWithStackTrace(interruption, interruptionStackTrace);
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    await _runRequestOperation(
      requestGuard,
      authProvider.redirectToAuthorization,
    );
    throw UnauthorizedError('Authentication required');
  }

  Future<void> _drainAuthorizationResponse(
    http.StreamedResponse response,
    _RequestOperationGuard? requestGuard,
  ) async {
    if (requestGuard == null) {
      await response.stream.drain<void>();
      return;
    }

    final drained = Completer<void>();
    final subscription = response.stream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!drained.isCompleted) {
          drained.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!drained.isCompleted) {
          drained.complete();
        }
      },
      cancelOnError: true,
    );
    try {
      await requestGuard.run(() => drained.future);
    } finally {
      unawaited(
        subscription.cancel().onError((_, __) {
          // Request cancellation has already determined the public outcome.
        }),
      );
    }
  }

  Future<_PreparedOAuthAuthorization> _prepareAuthorizationRequest(
    OAuthAuthorizationCodeProvider provider,
    OAuthBearerChallengeParameters? challenge, {
    _RequestOperationGuard? requestGuard,
  }) async {
    _validateOAuthRedirectUri(provider.redirectUri);
    final protectedResourceDiscovery = await _discoverProtectedResourceMetadata(
      challenge,
      requestGuard: requestGuard,
    );
    final protectedResourceMetadata = protectedResourceDiscovery.document;
    final authorizationServerIdentifier =
        protectedResourceDiscovery.authorizationServerIdentifiers.isEmpty
            ? null
            : protectedResourceDiscovery.authorizationServerIdentifiers.first;
    if (authorizationServerIdentifier == null) {
      throw UnauthorizedError(
        'Protected resource metadata did not include authorization_servers',
      );
    }
    final authorizationServerUri = Uri.parse(authorizationServerIdentifier);
    _validateOAuthUri(
      authorizationServerUri,
      OAuthEndpointKind.authorizationServer,
    );

    final authorizationServerMetadata =
        await _discoverAuthorizationServerMetadata(
      authorizationServerUri,
      issuerIdentifier: authorizationServerIdentifier,
      requestGuard: requestGuard,
    );
    _authorizationServerIssuer = authorizationServerIdentifier;
    final authorizationEndpoint =
        authorizationServerMetadata.authorizationEndpoint;
    final tokenEndpoint = authorizationServerMetadata.tokenEndpoint;
    if (authorizationEndpoint == null || tokenEndpoint == null) {
      throw UnauthorizedError(
        'Authorization server metadata is missing authorization_endpoint or token_endpoint',
      );
    }
    _validateOAuthUri(
      authorizationEndpoint,
      OAuthEndpointKind.authorizationEndpoint,
    );
    _validateOAuthUri(tokenEndpoint, OAuthEndpointKind.tokenEndpoint);

    final methods = authorizationServerMetadata.codeChallengeMethodsSupported;
    if (methods == null || !methods.contains('S256')) {
      throw UnauthorizedError(
        'Authorization server does not advertise PKCE S256 support',
      );
    }

    final clientRegistration = await _resolveOAuthClientRegistration(
      provider,
      authorizationServerMetadata,
      issuerIdentifier: authorizationServerIdentifier,
      requestGuard: requestGuard,
    );
    _validateOAuthClientRegistration(clientRegistration);
    final scope = _authorizationScope(
      challenge,
      provider,
      protectedResourceMetadata,
    );
    final codeVerifier = _generatePkceCodeVerifier();
    final codeChallenge = _generatePkceS256Challenge(codeVerifier);
    final state = _generateOAuthState();

    final authorizationUri = authorizationEndpoint.replace(
      queryParameters: {
        ...authorizationEndpoint.queryParameters,
        'response_type': 'code',
        'client_id': clientRegistration.clientId,
        'redirect_uri': provider.redirectUri.toString(),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'resource': protectedResourceMetadata.resource.toString(),
        if (scope != null && scope.isNotEmpty) 'scope': scope,
      },
    );

    final authorizationRequest = OAuthAuthorizationRequest(
      authorizationUri: authorizationUri,
      codeVerifier: codeVerifier,
      codeChallenge: codeChallenge,
      state: state,
      resource: protectedResourceMetadata.resource,
      scope: scope,
    );

    final pendingAuthorization = _PendingOAuthAuthorization(
      tokenEndpoint: tokenEndpoint,
      codeVerifier: codeVerifier,
      clientId: clientRegistration.clientId,
      clientSecret: clientRegistration.clientSecret,
      tokenEndpointAuthMethod: clientRegistration.tokenEndpointAuthMethod,
      redirectUri: provider.redirectUri,
      resource: protectedResourceMetadata.resource,
      issuer: authorizationServerIdentifier,
      state: state,
      scope: scope,
      authorizationResponseIssParameterSupported: authorizationServerMetadata
          .authorizationResponseIssParameterSupported,
    );

    requestGuard?.check();
    return _PreparedOAuthAuthorization(
      request: authorizationRequest,
      pending: pendingAuthorization,
    );
  }

  String? _authorizationScope(
    OAuthBearerChallengeParameters? challenge,
    OAuthAuthorizationCodeProvider provider,
    OAuthProtectedResourceMetadataDocument protectedResourceMetadata,
  ) {
    final requestedScopes = <String>{..._oauthRequestedScopes};
    final challengedScopes = _splitOAuthScopes(challenge?.scope);
    if (challengedScopes.isNotEmpty) {
      requestedScopes.addAll(challengedScopes);
      return requestedScopes.join(' ');
    }

    if (provider.scopes.isNotEmpty) {
      requestedScopes.addAll(provider.scopes);
      return requestedScopes.join(' ');
    }

    final supportedScopes = protectedResourceMetadata.scopesSupported;
    if (supportedScopes != null && supportedScopes.isNotEmpty) {
      requestedScopes.addAll(supportedScopes);
      return requestedScopes.join(' ');
    }

    return null;
  }

  List<String> _splitOAuthScopes(String? scope) {
    if (scope == null || scope.trim().isEmpty) {
      return const [];
    }
    return scope
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<_OAuthClientRegistration> _resolveOAuthClientRegistration(
    OAuthAuthorizationCodeProvider provider,
    OAuthAuthorizationServerMetadataDocument authorizationServerMetadata, {
    required String issuerIdentifier,
    _RequestOperationGuard? requestGuard,
  }) async {
    final providerClientId = provider.clientId;
    if (providerClientId.isNotEmpty) {
      if (authorizationServerMetadata.clientIdMetadataDocumentSupported ==
              true &&
          provider.clientSecret == null &&
          _isClientIdMetadataDocumentUri(providerClientId)) {
        return _OAuthClientRegistration(
          clientId: providerClientId,
          clientSecret: null,
          tokenEndpointAuthMethod: _selectTokenEndpointAuthMethod(
            authorizationServerMetadata,
            null,
          ),
        );
      }

      final boundIssuer = _preRegisteredClientIssuer ??
          _preRegisteredOAuthProviderIssuers[provider];
      if (boundIssuer != null && boundIssuer != issuerIdentifier) {
        throw UnauthorizedError(
          'Pre-registered OAuth client credentials are bound to authorization '
          'server "$boundIssuer" and cannot be reused for "$issuerIdentifier"',
        );
      }
      _preRegisteredClientIssuer = issuerIdentifier;
      _preRegisteredOAuthProviderIssuers[provider] = issuerIdentifier;
      return _OAuthClientRegistration(
        clientId: providerClientId,
        clientSecret: provider.clientSecret,
        tokenEndpointAuthMethod: _selectTokenEndpointAuthMethod(
          authorizationServerMetadata,
          provider.clientSecret,
        ),
      );
    }

    final registrationEndpoint =
        authorizationServerMetadata.registrationEndpoint;
    if (registrationEndpoint != null) {
      final existingRegistration = _oauthRegistrations[issuerIdentifier];
      if (existingRegistration != null) {
        return existingRegistration;
      }

      final registration = await _runRequestOperation(
        requestGuard,
        () => _registerOAuthClient(
          provider,
          authorizationServerMetadata,
          registrationEndpoint,
          requestGuard: requestGuard,
        ),
      );
      requestGuard?.check();
      _oauthRegistrations[issuerIdentifier] = registration;
      return registration;
    }

    throw UnauthorizedError(
      'No OAuth client registration is available for authorization server '
      '"$issuerIdentifier"; configure a pre-registered client ID, use a valid '
      'Client ID Metadata Document URL, or enable Dynamic Client Registration '
      'on the server',
    );
  }

  bool _isClientIdMetadataDocumentUri(String value) {
    final uri = Uri.tryParse(value);
    // The pinned MCP client-registration rules require an HTTPS client ID
    // with a non-root path before it can identify a metadata document.
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.pathSegments.any((segment) => segment.isNotEmpty) &&
        !uri.pathSegments.any((segment) => segment == '.' || segment == '..');
  }

  Future<_OAuthClientRegistration> _registerOAuthClient(
    OAuthAuthorizationCodeProvider provider,
    OAuthAuthorizationServerMetadataDocument authorizationServerMetadata,
    Uri registrationEndpoint, {
    _RequestOperationGuard? requestGuard,
  }) async {
    _validateOAuthUri(
      registrationEndpoint,
      OAuthEndpointKind.registrationEndpoint,
    );
    final tokenEndpointAuthMethod = _selectTokenEndpointAuthMethod(
      authorizationServerMetadata,
      provider.clientSecret,
    );
    final response = await _runRequestOperation(
      requestGuard,
      () => _sendOAuthRequest(
        'POST',
        registrationEndpoint,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'client_name':
              provider.clientId.isEmpty ? 'mcp_dart' : provider.clientId,
          'redirect_uris': [provider.redirectUri.toString()],
          'grant_types': ['authorization_code', 'refresh_token'],
          'response_types': ['code'],
          'application_type': _oauthApplicationType(provider.redirectUri),
          'token_endpoint_auth_method': tokenEndpointAuthMethod,
        }),
        abortTrigger: requestGuard?.abortTrigger,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UnauthorizedError(
        'Dynamic client registration failed with HTTP ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw UnauthorizedError('Client registration response must be an object');
    }
    final clientId = json['client_id'];
    if (clientId is! String || clientId.isEmpty) {
      throw UnauthorizedError('Client registration did not include client_id');
    }
    final clientSecret = json['client_secret'];
    final registeredAuthMethod = json['token_endpoint_auth_method'];
    final resolvedAuthMethod = switch (registeredAuthMethod) {
      null => tokenEndpointAuthMethod,
      final String method => _requireSupportedTokenEndpointAuthMethod(
          method,
          source: 'Dynamic client registration',
        ),
      _ => throw UnauthorizedError(
          'Dynamic client registration returned a non-string '
          'token_endpoint_auth_method',
        ),
    };
    return _OAuthClientRegistration(
      clientId: clientId,
      clientSecret: clientSecret is String ? clientSecret : null,
      tokenEndpointAuthMethod: resolvedAuthMethod,
    );
  }

  String _selectTokenEndpointAuthMethod(
    OAuthAuthorizationServerMetadataDocument metadata,
    String? clientSecret,
  ) {
    // RFC 8414 Section 2 defines client_secret_basic as the default when the
    // authorization-server metadata omits this field.
    final supportedMethods = metadata.tokenEndpointAuthMethodsSupported ??
        const ['client_secret_basic'];
    if (clientSecret != null) {
      if (supportedMethods.contains('client_secret_basic')) {
        return 'client_secret_basic';
      }
      if (supportedMethods.contains('client_secret_post')) {
        return 'client_secret_post';
      }
    }
    if (supportedMethods.contains('none')) {
      return 'none';
    }
    if (supportedMethods.contains('client_secret_basic')) {
      return 'client_secret_basic';
    }
    if (supportedMethods.contains('client_secret_post')) {
      return 'client_secret_post';
    }
    throw UnauthorizedError(
      'Authorization server does not advertise a supported token endpoint '
      'authentication method',
    );
  }

  void _validateOAuthClientRegistration(
    _OAuthClientRegistration registration,
  ) {
    switch (registration.tokenEndpointAuthMethod) {
      case 'none':
        return;
      case 'client_secret_basic':
      case 'client_secret_post':
        final clientSecret = registration.clientSecret;
        if (clientSecret == null || clientSecret.isEmpty) {
          throw UnauthorizedError(
            'Token endpoint requires '
            '${registration.tokenEndpointAuthMethod} but no client secret is '
            'available',
          );
        }
        return;
      default:
        throw UnauthorizedError(
          'Unsupported token endpoint authentication method '
          '"${registration.tokenEndpointAuthMethod}"',
        );
    }
  }

  String _requireSupportedTokenEndpointAuthMethod(
    String method, {
    required String source,
  }) {
    switch (method) {
      case 'none':
      case 'client_secret_basic':
      case 'client_secret_post':
        return method;
      default:
        throw UnauthorizedError(
          '$source returned unsupported token_endpoint_auth_method "$method"',
        );
    }
  }

  Future<_DiscoveredProtectedResourceMetadata>
      _discoverProtectedResourceMetadata(
    OAuthBearerChallengeParameters? challenge, {
    _RequestOperationGuard? requestGuard,
  }) async {
    final resourceMetadata = challenge?.resourceMetadata;
    if (resourceMetadata != null) {
      return _fetchProtectedResourceMetadata(
        resourceMetadata,
        requestGuard: requestGuard,
      );
    }

    final errors = <Object>[];
    for (final uri in _protectedResourceMetadataCandidates()) {
      requestGuard?.check();
      try {
        return await _fetchProtectedResourceMetadata(
          uri,
          requestGuard: requestGuard,
        );
      } catch (error) {
        requestGuard?.check();
        errors.add(error);
      }
    }

    throw UnauthorizedError(
      'Failed to discover OAuth protected-resource metadata: $errors',
    );
  }

  List<Uri> _protectedResourceMetadataCandidates() {
    final candidates = <Uri>[];
    final endpointPath = _url.path.isEmpty ? '/' : _url.path;
    if (endpointPath != '/') {
      candidates.add(
        _oauthDiscoveryUri(
          _url,
          path: '/.well-known/oauth-protected-resource$endpointPath',
        ),
      );
    }
    candidates.add(
      _oauthDiscoveryUri(
        _url,
        path: '/.well-known/oauth-protected-resource',
      ),
    );

    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.toString())) candidate,
    ];
  }

  Future<_DiscoveredProtectedResourceMetadata> _fetchProtectedResourceMetadata(
    Uri uri, {
    _RequestOperationGuard? requestGuard,
  }) async {
    _validateOAuthUri(uri, OAuthEndpointKind.protectedResourceMetadata);
    final response = await _runRequestOperation(
      requestGuard,
      () => _sendOAuthRequest(
        'GET',
        uri,
        headers: const {'Accept': 'application/json'},
        abortTrigger: requestGuard?.abortTrigger,
      ),
    );
    if (response.statusCode != 200) {
      throw UnauthorizedError(
        'Protected-resource metadata request failed with HTTP ${response.statusCode}',
      );
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw UnauthorizedError(
        'Protected-resource metadata must be a JSON object',
      );
    }
    final metadata = OAuthProtectedResourceMetadataDocument.fromJson(json);
    if (!_isProtectedResourceForEndpoint(metadata.resource)) {
      throw UnauthorizedError(
        'Protected-resource metadata resource does not match server URL',
      );
    }
    return _DiscoveredProtectedResourceMetadata(
      document: metadata,
      authorizationServerIdentifiers: List<String>.unmodifiable(
        (json['authorization_servers'] as List).cast<String>(),
      ),
    );
  }

  bool _isProtectedResourceForEndpoint(Uri resource) {
    if (resource.fragment.isNotEmpty) {
      return false;
    }
    if (resource.scheme != _url.scheme ||
        resource.host != _url.host ||
        resource.port != _url.port) {
      return false;
    }

    final resourcePath = resource.path.isEmpty ? '/' : resource.path;
    final endpointPath = _url.path.isEmpty ? '/' : _url.path;
    return resourcePath == endpointPath || resourcePath == '/';
  }

  Future<OAuthAuthorizationServerMetadataDocument>
      _discoverAuthorizationServerMetadata(
    Uri issuer, {
    required String issuerIdentifier,
    _RequestOperationGuard? requestGuard,
  }) async {
    _validateOAuthUri(issuer, OAuthEndpointKind.authorizationServer);
    final errors = <Object>[];
    for (final uri in _authorizationServerMetadataCandidates(issuer)) {
      requestGuard?.check();
      try {
        final discoveredMetadata = await _fetchAuthorizationServerMetadata(
          uri,
          requestGuard: requestGuard,
        );
        if (discoveredMetadata.issuerIdentifier != issuerIdentifier) {
          throw UnauthorizedError(
            'Authorization-server metadata issuer does not exactly match '
            '"$issuerIdentifier"',
          );
        }
        return discoveredMetadata.document;
      } catch (error) {
        requestGuard?.check();
        errors.add(error);
      }
    }
    throw UnauthorizedError(
      'Failed to discover OAuth authorization-server metadata: $errors',
    );
  }

  List<Uri> _authorizationServerMetadataCandidates(Uri issuer) {
    final issuerPath = issuer.path.isEmpty ? '' : issuer.path;
    final pathPrefix = issuerPath == '/'
        ? ''
        : issuerPath.endsWith('/')
            ? issuerPath.substring(0, issuerPath.length - 1)
            : issuerPath;
    // The pinned MCP discovery rules put both insertion forms before OIDC
    // path appending. OAuth path appending remains a final compatibility probe.
    final candidates = [
      _oauthDiscoveryUri(
        issuer,
        path: '/.well-known/oauth-authorization-server$pathPrefix',
      ),
      _oauthDiscoveryUri(
        issuer,
        path: '/.well-known/openid-configuration$pathPrefix',
      ),
      _oauthDiscoveryUri(
        issuer,
        path:
            '${pathPrefix.isEmpty ? '' : pathPrefix}/.well-known/openid-configuration',
      ),
      _oauthDiscoveryUri(
        issuer,
        path:
            '${pathPrefix.isEmpty ? '' : pathPrefix}/.well-known/oauth-authorization-server',
      ),
    ];

    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.toString())) candidate,
    ];
  }

  Uri _oauthDiscoveryUri(Uri base, {required String path}) => Uri(
        scheme: base.scheme,
        userInfo: base.userInfo,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: path,
      );

  Future<_DiscoveredAuthorizationServerMetadata>
      _fetchAuthorizationServerMetadata(
    Uri uri, {
    _RequestOperationGuard? requestGuard,
  }) async {
    _validateOAuthUri(uri, OAuthEndpointKind.authorizationServerMetadata);
    final response = await _runRequestOperation(
      requestGuard,
      () => _sendOAuthRequest(
        'GET',
        uri,
        headers: const {'Accept': 'application/json'},
        abortTrigger: requestGuard?.abortTrigger,
      ),
    );
    if (response.statusCode != 200) {
      throw UnauthorizedError(
        'Authorization-server metadata request failed with HTTP ${response.statusCode}',
      );
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw UnauthorizedError(
        'Authorization-server metadata must be a JSON object',
      );
    }
    final metadata = OAuthAuthorizationServerMetadataDocument.fromJson(json);
    _validateOAuthUri(
      metadata.issuer,
      OAuthEndpointKind.authorizationServer,
    );
    final authorizationEndpoint = metadata.authorizationEndpoint;
    if (authorizationEndpoint != null) {
      _validateOAuthUri(
        authorizationEndpoint,
        OAuthEndpointKind.authorizationEndpoint,
      );
    }
    final tokenEndpoint = metadata.tokenEndpoint;
    if (tokenEndpoint != null) {
      _validateOAuthUri(tokenEndpoint, OAuthEndpointKind.tokenEndpoint);
    }
    final registrationEndpoint = metadata.registrationEndpoint;
    if (registrationEndpoint != null) {
      _validateOAuthUri(
        registrationEndpoint,
        OAuthEndpointKind.registrationEndpoint,
      );
    }
    return _DiscoveredAuthorizationServerMetadata(
      document: metadata,
      issuerIdentifier: json['issuer'] as String,
    );
  }

  Future<OAuthTokens> _exchangeAuthorizationCode(
    OAuthAuthorizationCodeProvider provider,
    String authorizationCode,
    _PendingOAuthAuthorization pendingAuthorization, {
    _RequestOperationGuard? requestGuard,
  }) async {
    _validateOAuthUri(
      pendingAuthorization.tokenEndpoint,
      OAuthEndpointKind.tokenEndpoint,
    );
    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': authorizationCode,
      'redirect_uri': pendingAuthorization.redirectUri.toString(),
      'client_id': pendingAuthorization.clientId,
      'code_verifier': pendingAuthorization.codeVerifier,
      'resource': pendingAuthorization.resource.toString(),
    };
    switch (pendingAuthorization.tokenEndpointAuthMethod) {
      case 'client_secret_basic':
        final clientSecret = pendingAuthorization.clientSecret;
        if (clientSecret == null) {
          throw UnauthorizedError(
            'Token endpoint requires client_secret_basic but no secret is available',
          );
        }
        headers['Authorization'] = _basicAuthorizationHeader(
          pendingAuthorization.clientId,
          clientSecret,
        );
        break;
      case 'client_secret_post':
        final clientSecret = pendingAuthorization.clientSecret;
        if (clientSecret == null) {
          throw UnauthorizedError(
            'Token endpoint requires client_secret_post but no secret is available',
          );
        }
        body['client_secret'] = clientSecret;
        break;
      case 'none':
        break;
      default:
        throw UnauthorizedError(
          'Unsupported token endpoint authentication method '
          '"${pendingAuthorization.tokenEndpointAuthMethod}"',
        );
    }

    final response = await _runRequestOperation(
      requestGuard,
      () => _sendOAuthRequest(
        'POST',
        pendingAuthorization.tokenEndpoint,
        headers: headers,
        body: body,
        abortTrigger: requestGuard?.abortTrigger,
      ),
    );
    if (response.statusCode != 200) {
      throw UnauthorizedError(
        'Token exchange failed with HTTP ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw UnauthorizedError('Token response must be a JSON object');
    }
    final accessToken = json['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw UnauthorizedError('Token response did not include access_token');
    }

    final tokens = OAuthIssuerBoundAuthorizationCodeTokens(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: _parseExpiresIn(json['expires_in']),
      scope: json['scope'] as String? ?? pendingAuthorization.scope,
      authorizationServerIssuer: pendingAuthorization.issuer,
      resource: pendingAuthorization.resource,
    );
    await _runRequestOperation(
      requestGuard,
      () => provider.saveTokens(tokens),
    );
    requestGuard?.check();
    _oauthRequestedScopes.addAll(_splitOAuthScopes(pendingAuthorization.scope));
    _oauthRequestedScopes.addAll(_splitOAuthScopes(tokens.scope));
    return tokens;
  }

  Future<http.Response> _sendOAuthRequest(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    Future<void>? abortTrigger,
  }) async {
    final request = (abortTrigger == null
        ? http.Request(method, uri)
        : http.AbortableRequest(
            method,
            uri,
            abortTrigger: abortTrigger,
          ))
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body is String) {
      request.body = body;
    } else if (body is Map<String, String>) {
      request.bodyFields = body;
    } else if (body != null) {
      throw ArgumentError.value(body, 'body', 'Unsupported OAuth body type');
    }

    final streamedResponse = await _httpClient.send(request);
    final response = await _readOAuthResponse(
      streamedResponse,
      uri,
      abortTrigger,
    );
    if (response.isRedirect) {
      throw UnauthorizedError(
        'OAuth endpoint redirects are not followed automatically',
      );
    }
    return response;
  }

  Future<http.Response> _readOAuthResponse(
    http.StreamedResponse response,
    Uri uri,
    Future<void>? abortTrigger,
  ) async {
    if (abortTrigger == null) {
      return http.Response.fromStream(response);
    }

    final body = BytesBuilder(copy: false);
    final completed = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      body.add,
      onError: (Object error, StackTrace stackTrace) {
        if (!completed.isCompleted) {
          completed.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completed.isCompleted) {
          completed.complete();
        }
      },
      cancelOnError: true,
    );
    unawaited(
      abortTrigger.then<void>((_) {
        if (completed.isCompleted) {
          return;
        }
        completed.completeError(http.RequestAbortedException(uri));
        unawaited(
          subscription.cancel().onError((_, __) {
            // The request abort already determines the public outcome.
          }),
        );
      }),
    );

    await completed.future;
    return http.Response.bytes(
      body.takeBytes(),
      response.statusCode,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  String _oauthApplicationType(Uri redirectUri) =>
      oauth_platform.oauthClientApplicationType == 'web' &&
              !_isLoopbackHost(redirectUri.host)
          ? 'web'
          : 'native';

  void _validateOAuthRedirectUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final isHttps = scheme == 'https' && uri.host.isNotEmpty;
    final isLoopbackHttp =
        scheme == 'http' && uri.host.isNotEmpty && _isLoopbackHost(uri.host);
    if ((!isHttps && !isLoopbackHttp) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw UnauthorizedError(
        'OAuth redirect URI must use HTTPS or loopback HTTP and must not '
        'contain user information or a fragment',
      );
    }
  }

  void _validateOAuthUri(Uri uri, OAuthEndpointKind endpointKind) {
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw UnauthorizedError(
        'Rejected invalid OAuth ${endpointKind.name} URI',
      );
    }

    final targetIsLoopback = _isLoopbackHost(uri.host);
    final serverIsLoopback = _isLoopbackHost(_url.host);
    if (scheme == 'http' && !(targetIsLoopback && serverIsLoopback)) {
      throw UnauthorizedError(
        'Rejected insecure OAuth ${endpointKind.name} URI',
      );
    }

    if (_hasSameOrigin(uri, _url) ||
        (targetIsLoopback && serverIsLoopback) ||
        (_oauthUriValidator?.call(uri, endpointKind) ?? false)) {
      return;
    }

    throw UnauthorizedError(
      'Rejected untrusted cross-origin OAuth ${endpointKind.name} URI',
    );
  }

  bool _hasSameOrigin(Uri first, Uri second) =>
      first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;

  bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
      return true;
    }
    if (normalized == '::1') {
      return true;
    }
    final octets = normalized.split('.');
    if (octets.length != 4) {
      return false;
    }
    final values = octets.map(int.tryParse).toList();
    return values
            .every((value) => value != null && value >= 0 && value <= 255) &&
        values.first == 127;
  }

  String _basicAuthorizationHeader(String clientId, String clientSecret) {
    final encodedClientId = Uri.encodeQueryComponent(clientId);
    final encodedClientSecret = Uri.encodeQueryComponent(clientSecret);
    final credentials = base64Encode(
      utf8.encode('$encodedClientId:$encodedClientSecret'),
    );
    return 'Basic $credentials';
  }

  int? _parseExpiresIn(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num && value.isFinite) {
      return value.toInt();
    }
    throw UnauthorizedError('Token response expires_in must be a number');
  }

  String _generatePkceCodeVerifier() =>
      _base64UrlNoPadding(_secureRandomBytes(32));

  String _generatePkceS256Challenge(String verifier) {
    final digest = crypto.sha256.convert(utf8.encode(verifier));
    return _base64UrlNoPadding(digest.bytes);
  }

  String _generateOAuthState() => _base64UrlNoPadding(_secureRandomBytes(16));

  List<int> _secureRandomBytes(int length) {
    final random = math.Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _base64UrlNoPadding(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  Future<Map<String, String>> _commonHeaders() async {
    final tokens = await _authProvider?.tokens();
    return _commonHeadersWithTokens(tokens);
  }

  Map<String, String> _commonHeadersWithTokens(OAuthTokens? tokens) {
    final headers = <String, String>{};

    if (tokens != null) {
      if (tokens is OAuthIssuerBoundAuthorizationCodeTokens) {
        if (!_isProtectedResourceForEndpoint(tokens.resource)) {
          throw UnauthorizedError(
            'OAuth access token is bound to a different protected resource',
          );
        }
        final selectedIssuer = _authorizationServerIssuer;
        if (selectedIssuer != null &&
            selectedIssuer != tokens.authorizationServerIssuer) {
          throw UnauthorizedError(
            'OAuth access token is bound to authorization server '
            '"${tokens.authorizationServerIssuer}", not "$selectedIssuer"',
          );
        }
      }
      headers["Authorization"] = "Bearer ${tokens.accessToken}";
    }

    if (_sessionId != null) {
      headers["mcp-session-id"] = _sessionId!;
    }

    if (_protocolVersion != null) {
      headers['MCP-Protocol-Version'] = _protocolVersion!;
    }

    if (_requestInit != null && _requestInit.containsKey('headers')) {
      final requestHeaders = _requestInit['headers'] as Map<String, dynamic>;
      for (final entry in requestHeaders.entries) {
        headers[entry.key] = entry.value.toString();
      }
    }

    return headers;
  }

  void _removeHeaderCaseInsensitive(
    Map<String, String> headers,
    String headerName,
  ) {
    final normalizedHeaderName = headerName.toLowerCase();
    final matchingKeys = headers.keys
        .where((key) => key.toLowerCase() == normalizedHeaderName)
        .toList();
    for (final key in matchingKeys) {
      headers.remove(key);
    }
  }

  Map<String, String> _headersForMessage(JsonRpcMessage message) {
    final headers = <String, String>{};
    final protocolVersion = _protocolVersion ?? _protocolVersionFrom(message);
    if (protocolVersion != null) {
      headers['MCP-Protocol-Version'] = protocolVersion;
    }

    if (protocolVersion == null ||
        !isStatelessProtocolVersion(protocolVersion)) {
      return headers;
    }

    final method = _methodFrom(message);
    if (method == null) {
      return headers;
    }

    headers['Mcp-Method'] = method;

    final params = _paramsFrom(message);
    final name = _standardNameHeaderValue(method, params);
    if (name != null) {
      headers['Mcp-Name'] = _encodeMcpHeaderValue(name);
    }

    if (method == Method.toolsCall && name != null) {
      headers.addAll(_toolParameterHeaders(name, params));
    }

    return headers;
  }

  Map<String, String> _toolParameterHeaders(
    String toolName,
    Map<String, dynamic>? params,
  ) {
    final mappings = _toolParameterHeaderMappings[toolName];
    final arguments = params?['arguments'];
    if (mappings == null || arguments is! Map) {
      return const {};
    }

    final argumentMap = arguments.cast<String, dynamic>();
    final headers = <String, String>{};
    for (final entry in mappings.entries) {
      final argument = _toolParameterHeaderArgument(argumentMap, entry.key);
      if (!argument.exists) {
        continue;
      }

      if (_isUnsafeHeaderInteger(argument.value)) {
        throw ArgumentError.value(
          argument.value,
          entry.key,
          'Tool "$toolName" parameter mirrored to '
          'Mcp-Param-${entry.value} must be within the JavaScript safe '
          'integer range ($_minSafeHeaderInteger to '
          '$_maxSafeHeaderInteger)',
        );
      }

      final value = _toolParameterHeaderString(argument.value);
      if (value == null) {
        continue;
      }

      headers['Mcp-Param-${entry.value}'] = _encodeMcpHeaderValue(value);
    }
    return headers;
  }

  ({bool exists, Object? value}) _toolParameterHeaderArgument(
    Map<String, dynamic> arguments,
    String selector,
  ) {
    if (!selector.startsWith('/')) {
      return (
        exists: arguments.containsKey(selector),
        value: arguments[selector],
      );
    }

    Object? current = arguments;
    for (final segment in _jsonPointerSegments(selector)) {
      if (current is! Map || !current.containsKey(segment)) {
        return (exists: false, value: null);
      }
      current = current[segment];
    }
    return (exists: true, value: current);
  }

  bool _isUnsafeHeaderInteger(Object? value) {
    if (value is int) {
      return value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger;
    }
    return value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        (value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger);
  }

  Iterable<String> _jsonPointerSegments(String selector) {
    if (selector == '/') {
      return const [''];
    }
    return selector
        .substring(1)
        .split('/')
        .map((segment) => segment.replaceAll('~1', '/').replaceAll('~0', '~'));
  }

  String? _toolParameterHeaderString(Object? value) {
    if (value is int) {
      if (value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger) {
        return null;
      }
      return value.toString();
    }
    if (value is double) {
      if (!value.isFinite || value != value.truncateToDouble()) {
        return null;
      }
      if (value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger) {
        return null;
      }
      return value.toInt().toString();
    }

    return switch (value) {
      String() => value,
      bool() => value.toString(),
      _ => null,
    };
  }

  String _encodeMcpHeaderValue(String value) {
    if (_isPlainMcpHeaderValue(value)) {
      return value;
    }

    return '=?base64?${base64Encode(utf8.encode(value))}?=';
  }

  bool _isPlainMcpHeaderValue(String value) {
    return value.isNotEmpty &&
        !_isBase64McpHeaderSentinel(value) &&
        value.trim() == value &&
        value.codeUnits.every(
          (unit) => unit == 0x09 || (unit >= 0x20 && unit <= 0x7E),
        );
  }

  bool _isBase64McpHeaderSentinel(String value) {
    return value.startsWith('=?base64?') && value.endsWith('?=');
  }

  String? _methodFrom(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.method;
    }
    if (message is JsonRpcNotification) {
      return message.method;
    }
    return null;
  }

  Map<String, dynamic>? _paramsFrom(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.params;
    }
    if (message is JsonRpcNotification) {
      return message.params;
    }
    return null;
  }

  Map<String, dynamic>? _metaFrom(JsonRpcMessage message) {
    final Map<String, dynamic>? directMeta;
    if (message is JsonRpcRequest) {
      directMeta = message.meta;
    } else if (message is JsonRpcNotification) {
      directMeta = message.meta;
    } else {
      return null;
    }
    if (directMeta != null) {
      return directMeta;
    }

    final paramsMeta = _paramsFrom(message)?['_meta'];
    if (paramsMeta is Map<String, dynamic>) {
      return paramsMeta;
    }
    if (paramsMeta is Map) {
      return paramsMeta.cast<String, dynamic>();
    }
    return null;
  }

  String? _protocolVersionFrom(JsonRpcMessage message) {
    final version = _metaFrom(message)?[McpMetaKey.protocolVersion];
    return version is String ? version : null;
  }

  _RequestCancellation? _registerRequestCancellation(
    JsonRpcMessage message,
  ) {
    if (message is! JsonRpcRequest) {
      return null;
    }
    final protocolVersion = _protocolVersion ?? _protocolVersionFrom(message);
    if (protocolVersion == null ||
        !isStatelessProtocolVersion(protocolVersion)) {
      return null;
    }

    final cancellation = _RequestCancellation();
    final previous = _requestCancellations[message.id];
    if (previous != null) {
      throw StateError(
        'A request with ID ${message.id} is already active on this transport.',
      );
    }
    _requestCancellations[message.id] = cancellation;
    return cancellation;
  }

  void _unregisterRequestCancellation(
    JsonRpcMessage message,
    _RequestCancellation? cancellation,
  ) {
    if (message is JsonRpcRequest &&
        identical(_requestCancellations[message.id], cancellation)) {
      _requestCancellations.remove(message.id);
    }
  }

  String? _standardNameHeaderValue(
    String method,
    Map<String, dynamic>? params,
  ) {
    if (params == null) {
      return null;
    }

    final nameField = switch (method) {
      Method.toolsCall => params['name'],
      Method.resourcesRead => params['uri'],
      Method.promptsGet => params['name'],
      Method.tasksGet ||
      Method.tasksUpdate ||
      Method.tasksCancel =>
        params['taskId'],
      _ => null,
    };
    return nameField is String ? nameField : null;
  }

  String? _clearStaleSession() {
    final staleSessionId = _sessionId;
    _sessionId = null;
    _protocolVersion = null;
    _staleSessionDetected = true;
    _signalSessionChange();
    return staleSessionId;
  }

  void _signalSessionChange() {
    _sessionGeneration += 1;
    if (_abortController != null && !_abortController!.isClosed) {
      _abortController!.add(true);
    }
  }

  Future<void> _startOrAuthSse(
    _StartSseOptions options, {
    int? sessionGeneration,
    int reconnectionAttempt = 0,
  }) async {
    if (_protocolVersion != null &&
        isStatelessProtocolVersion(_protocolVersion!)) {
      return;
    }

    final expectedSessionGeneration = sessionGeneration ?? _sessionGeneration;
    final trackedRequestId =
        options.requestMessageId ?? options.replayMessageId;
    Future<void> cancelResponseStream(http.StreamedResponse response) async {
      final responseSubscription = response.stream.listen(null);
      await responseSubscription.cancel();
    }

    void failRequestStream(Error error) {
      final onRequestStreamEnd = options.onRequestStreamEnd;
      if (onRequestStreamEnd != null) {
        onRequestStreamEnd(error);
        return;
      }
      if (trackedRequestId != null) {
        throw error;
      }
    }

    McpError interruptedConnectionError() {
      final detail = _isClosed
          ? 'The transport closed while reconnecting.'
          : 'The session reset while reconnecting.';
      return _requestSseStreamEndedError(trackedRequestId, detail);
    }

    bool connectionInterrupted() =>
        _isClosed || expectedSessionGeneration != _sessionGeneration;

    void handleInterruptedConnection() {
      failRequestStream(interruptedConnectionError());
    }

    if (connectionInterrupted()) {
      handleInterruptedConnection();
      return;
    }

    final resumptionToken = options.resumptionToken;
    final abortBinding = _HttpAbortBinding(
      _abortController,
      additionalAbortStream: _closeController.stream,
    );
    void ensureConnectionIsCurrent() {
      if (connectionInterrupted()) {
        throw interruptedConnectionError();
      }
    }

    final connectionGuard = _RequestOperationGuard(
      abortTrigger: abortBinding.abortTrigger,
      ensureCurrent: ensureConnectionIsCurrent,
    );
    try {
      // Try to open an initial SSE stream with GET to listen for server messages
      // This is optional according to the spec - server may not support it
      final headers = await connectionGuard.run(_commonHeaders);
      if (connectionInterrupted()) {
        handleInterruptedConnection();
        return;
      }
      final requestSessionId = headers['mcp-session-id'];
      headers['Accept'] = "text/event-stream";

      // Include Last-Event-ID header for resumable streams if provided
      if (resumptionToken?.isNotEmpty == true) {
        headers['last-event-id'] = resumptionToken!;
      }

      if (connectionInterrupted()) {
        handleInterruptedConnection();
        return;
      }
      final request = http.AbortableRequest(
        'GET',
        _url,
        abortTrigger: abortBinding.abortTrigger,
      );
      request.headers.addAll(headers);
      final response = await connectionGuard.run(
        () => _httpClient.send(request),
      );

      if (connectionInterrupted()) {
        await cancelResponseStream(response);
        handleInterruptedConnection();
        return;
      }

      if (response.statusCode != 200) {
        if (_authProvider != null &&
            _isAuthorizationRequiredResponse(
              response.statusCode,
              response.headers,
            )) {
          return await _handleAuthorizationRequired(
            response,
            requestGuard: connectionGuard,
          );
        }

        // 405 indicates that the server does not offer an SSE stream at GET endpoint
        // This is an expected case that should not trigger an error
        if (response.statusCode == 405) {
          await cancelResponseStream(response);
          if (connectionInterrupted()) {
            handleInterruptedConnection();
            return;
          }
          failRequestStream(
            _requestSseStreamEndedError(
              trackedRequestId,
              'The server does not support GET resumption.',
            ),
          );
          return;
        }

        if (response.statusCode == 404 && requestSessionId != null) {
          await cancelResponseStream(response);
          if (connectionInterrupted()) {
            handleInterruptedConnection();
            return;
          }
          String? staleSessionId = requestSessionId;
          if (_sessionId == requestSessionId) {
            staleSessionId = _clearStaleSession();
          }
          throw StaleSessionError(
            'Session not found',
            code: 404,
            sessionId: staleSessionId,
          );
        }

        await cancelResponseStream(response);
        throw StreamableHttpError(
          response.statusCode,
          "Failed to open SSE stream: ${response.reasonPhrase}",
        );
      }

      final responseMediaType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (responseMediaType != 'text/event-stream') {
        await cancelResponseStream(response);
        if (connectionInterrupted()) {
          handleInterruptedConnection();
          return;
        }
        throw StreamableHttpError(
          response.statusCode,
          'Expected text/event-stream from GET, received '
          '${responseMediaType ?? 'no Content-Type'}',
        );
      }

      _handleSseStream(
        response,
        options,
        isReconnectable: true,
        reconnectionAttempt: reconnectionAttempt,
      );
    } on http.RequestAbortedException catch (error) {
      if (connectionInterrupted()) {
        handleInterruptedConnection();
        return;
      }
      _reportError(error);
      rethrow;
    } catch (error) {
      if (connectionInterrupted() && error is! StaleSessionError) {
        handleInterruptedConnection();
        return;
      }
      _reportError(error);
      rethrow;
    } finally {
      await abortBinding.dispose();
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

  McpError _requestSseStreamEndedError(
    RequestId? requestId, [
    String? detail,
  ]) {
    final requestLabel = requestId == null ? '' : ' for request $requestId';
    final detailSuffix = detail == null ? '' : ' $detail';
    return McpError(
      ErrorCode.connectionClosed.value,
      'Request SSE stream$requestLabel ended before a response.$detailSuffix',
    );
  }

  /// Schedule a reconnection attempt with exponential backoff
  ///
  /// @param options The SSE connection options
  /// @param attemptCount Current reconnection attempt count for this specific stream
  void _scheduleReconnection(
    _StartSseOptions options, [
    int attemptCount = 0,
    int? retryDelayMs,
    int? sessionGeneration,
  ]) {
    final expectedSessionGeneration = sessionGeneration ?? _sessionGeneration;
    void reportInterruptedReconnection() {
      final onRequestStreamEnd = options.onRequestStreamEnd;
      if (onRequestStreamEnd == null) {
        return;
      }
      final detail = _isClosed
          ? 'The transport closed during reconnection.'
          : 'The session reset during reconnection.';
      onRequestStreamEnd(
        _requestSseStreamEndedError(
          options.requestMessageId ?? options.replayMessageId,
          detail,
        ),
      );
    }

    if (_isClosed || expectedSessionGeneration != _sessionGeneration) {
      reportInterruptedReconnection();
      return;
    }

    // Use provided options or default options
    final maxRetries = _reconnectionOptions.maxRetries;

    // Check if we've exceeded maximum retry attempts
    if (maxRetries > 0 && attemptCount >= maxRetries) {
      final error = _requestSseStreamEndedError(
        options.requestMessageId ?? options.replayMessageId,
        'Maximum reconnection attempts ($maxRetries) exceeded.',
      );
      _reportError(error);
      options.onRequestStreamEnd?.call(error);
      return;
    }

    // Calculate next delay based on current attempt count
    final delay = retryDelayMs ?? _getNextReconnectionDelay(attemptCount);

    Timer? reconnectTimer;
    // Cancelled when the timer fires or the transport/session is aborted.
    // ignore: cancel_subscriptions
    StreamSubscription<bool>? abortSubscription;
    var waitingToReconnect = true;

    void finishWaiting() {
      if (!waitingToReconnect) {
        return;
      }
      waitingToReconnect = false;
      reconnectTimer?.cancel();
      final currentAbortSubscription = abortSubscription;
      abortSubscription = null;
      if (currentAbortSubscription != null) {
        unawaited(currentAbortSubscription.cancel());
      }
    }

    void interruptWaiting() {
      if (!waitingToReconnect) {
        return;
      }
      finishWaiting();
      reportInterruptedReconnection();
    }

    abortSubscription = _abortController?.stream.listen((_) {
      interruptWaiting();
    });

    // Schedule the reconnection while keeping the request lifecycle attached
    // to transport/session cancellation during the backoff interval.
    reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (!waitingToReconnect) {
        return;
      }
      finishWaiting();
      if (_isClosed || expectedSessionGeneration != _sessionGeneration) {
        reportInterruptedReconnection();
        return;
      }

      // Use the last event ID to resume where we left off
      _startOrAuthSse(
        options,
        sessionGeneration: expectedSessionGeneration,
        reconnectionAttempt: attemptCount + 1,
      ).catchError((error) {
        if (error is StaleSessionError) {
          options.onRequestStreamEnd?.call(error);
          return null;
        }

        final errorMessage =
            error is Error ? error.toString() : error.toString();
        _reportError(
          McpError(0, "Failed to reconnect SSE stream: $errorMessage"),
        );

        // Schedule another attempt if this one failed, incrementing the attempt counter
        _scheduleReconnection(
          options,
          attemptCount + 1,
          null,
          expectedSessionGeneration,
        );

        // Ensure the Future completes
        return null;
      });
    });
  }

  void _handleSseStream(
    http.StreamedResponse stream,
    _StartSseOptions options, {
    required bool isReconnectable,
    int reconnectionAttempt = 0,
  }) {
    final onResumptionToken = options.onResumptionToken;
    final replayMessageId = options.replayMessageId;
    final requestMessageId = options.requestMessageId ?? replayMessageId;
    final streamSessionGeneration = _sessionGeneration;

    String? lastEventId = options.resumptionToken;
    int? retryDelayMs;
    String buffer = '';
    String? eventName;
    String? eventId;
    String? eventData;
    var terminalResponseReceived = false;
    var responseStreamFinished = false;
    var requestLifecycleSettled = false;
    // Cancelled by every stream terminal path and by the abort callback.
    // ignore: cancel_subscriptions
    StreamSubscription<bool>? abortSubscription;
    // Cancelled by stream completion/error or transport/session interruption.
    // ignore: cancel_subscriptions
    StreamSubscription<String>? streamSubscription;

    bool streamIsCurrent() =>
        !_isClosed && streamSessionGeneration == _sessionGeneration;

    bool requestWasCancelled() => options.isRequestCancelled?.call() == true;

    void cancelAbortSubscription() {
      final current = abortSubscription;
      abortSubscription = null;
      if (current != null) {
        unawaited(current.cancel());
      }
    }

    void cancelStreamSubscription() {
      final current = streamSubscription;
      streamSubscription = null;
      if (current != null) {
        unawaited(current.cancel());
      }
    }

    void settleTerminalResponse() {
      if (requestLifecycleSettled) {
        return;
      }
      requestLifecycleSettled = true;
      options.onTerminalResponse?.call();
    }

    void settleRequestError(Error error) {
      if (requestLifecycleSettled) {
        return;
      }
      requestLifecycleSettled = true;
      options.onRequestStreamEnd?.call(error);
    }

    void reportResumptionToken(String token) {
      try {
        onResumptionToken?.call(token);
      } catch (error) {
        _reportError(error);
      }
    }

    void interruptStream([String? detail]) {
      responseStreamFinished = true;
      cancelStreamSubscription();
      cancelAbortSubscription();
      if (requestMessageId != null && !terminalResponseReceived) {
        settleRequestError(
          _requestSseStreamEndedError(
            requestMessageId,
            detail ?? 'The transport closed or reset the session.',
          ),
        );
      }
    }

    void interruptCancelledStream() {
      responseStreamFinished = true;
      cancelStreamSubscription();
      cancelAbortSubscription();
      if (requestMessageId != null && !terminalResponseReceived) {
        settleRequestError(
          _requestSseStreamEndedError(
            requestMessageId,
            'The request response stream was cancelled.',
          ),
        );
      }
    }

    // Function to process a complete SSE event
    void processEvent() {
      if (requestWasCancelled()) {
        interruptCancelledStream();
        return;
      }
      if (!streamIsCurrent()) {
        interruptStream();
        return;
      }

      final data = eventData;

      // A non-empty ID-only event primes a request-scoped POST stream for
      // resumption. Capture it before checking data; an empty ID resets the
      // SSE cursor and is not a usable resumption token.
      if (eventId != null) {
        final nextEventId = eventId!;
        if (nextEventId.isEmpty) {
          lastEventId = null;
          reportResumptionToken('');
        } else {
          lastEventId = nextEventId;
          reportResumptionToken(nextEventId);
        }
      }

      if (data == null) {
        eventName = null;
        eventId = null;
        return;
      }

      final currentEventName = eventName;
      eventName = null;
      eventId = null;
      eventData = null;

      if (currentEventName != null && currentEventName != 'message') {
        return;
      }

      if (data.trim().isEmpty) {
        return;
      }

      try {
        final message = JsonRpcMessage.fromJson(jsonDecode(data));

        final isResponseMessage =
            message is JsonRpcResponse || message is JsonRpcError;
        final responseId = switch (message) {
          JsonRpcResponse(:final id) => id,
          JsonRpcError(:final id) => id,
          _ => null,
        };
        final isTerminalResponse = requestMessageId != null &&
            isResponseMessage &&
            responseId == requestMessageId;
        if (isTerminalResponse) {
          terminalResponseReceived = true;
        } else if (requestMessageId != null && isResponseMessage) {
          final error = McpError(
            ErrorCode.invalidRequest.value,
            'Request SSE stream for $requestMessageId received a response '
            'for ${responseId ?? 'a null ID'}.',
          );
          _reportError(error);
          if (options.rejectServerRequests) {
            return;
          }
        }

        try {
          _dispatchReceivedMessage(
            message,
            rejectServerRequests: options.rejectServerRequests,
          );
        } finally {
          if (isTerminalResponse) {
            responseStreamFinished = true;
            settleTerminalResponse();
            cancelStreamSubscription();
            cancelAbortSubscription();
          }
        }
      } catch (error) {
        _reportError(error);
      }
    }

    // Helper function to handle reconnection logic
    bool handleReconnection(String? eventId, [int? retryDelayOverrideMs]) {
      if (requestWasCancelled()) {
        interruptCancelledStream();
        return true;
      }
      if (_isClosed || streamSessionGeneration != _sessionGeneration) {
        if (requestMessageId != null && !terminalResponseReceived) {
          settleRequestError(
            _requestSseStreamEndedError(
              requestMessageId,
              'The transport closed or reset the session.',
            ),
          );
        }
        return true;
      }
      if (terminalResponseReceived) {
        return true;
      }
      if (!options.shouldReconnect ||
          eventId == null && (requestMessageId != null || !isReconnectable)) {
        return false;
      }

      if (_abortController != null && !_abortController!.isClosed) {
        try {
          _scheduleReconnection(
            _StartSseOptions(
              resumptionToken: eventId,
              onResumptionToken: onResumptionToken,
              replayMessageId: replayMessageId ?? requestMessageId,
              requestMessageId: requestMessageId,
              onTerminalResponse: options.onTerminalResponse,
              onRequestStreamEnd: options.onRequestStreamEnd,
              isRequestCancelled: options.isRequestCancelled,
              requestCancellationTrigger: options.requestCancellationTrigger,
              shouldReconnect: options.shouldReconnect,
              rejectServerRequests: options.rejectServerRequests,
            ),
            reconnectionAttempt,
            retryDelayOverrideMs,
            streamSessionGeneration,
          );
          return true;
        } catch (error) {
          final errorMessage =
              error is Error ? error.toString() : error.toString();
          _reportError(McpError(0, "Failed to reconnect: $errorMessage"));
        }
      }
      return false;
    }

    void reportUnresumableEnd([String? detail]) {
      if (terminalResponseReceived || requestMessageId == null) {
        return;
      }
      settleRequestError(
        _requestSseStreamEndedError(requestMessageId, detail),
      );
    }

    if (requestWasCancelled()) {
      final cancelledSubscription = stream.stream.listen(null);
      unawaited(cancelledSubscription.cancel());
      interruptCancelledStream();
      return;
    }

    if (!streamIsCurrent()) {
      final staleSubscription = stream.stream.listen(null);
      unawaited(staleSubscription.cancel());
      interruptStream();
      return;
    }

    // Create a subscription to the stream
    streamSubscription = stream.stream.transform(utf8.decoder).listen(
      (data) {
        if (responseStreamFinished) {
          return;
        }
        if (requestWasCancelled()) {
          interruptCancelledStream();
          return;
        }
        if (!streamIsCurrent()) {
          interruptStream();
          return;
        }
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
            if (responseStreamFinished) {
              return;
            }
            continue;
          }

          if (line.startsWith(':')) {
            // Comment line, ignore
            continue;
          }

          final colonIndex = line.indexOf(':');
          final field = colonIndex == -1 ? line : line.substring(0, colonIndex);
          final value = colonIndex == -1
              ? ''
              : line.substring(
                  colonIndex +
                      1 +
                      (line.length > colonIndex + 1 &&
                              line[colonIndex + 1] == ' '
                          ? 1
                          : 0),
                );

          switch (field) {
            case 'event':
              eventName = value;
              break;
            case 'id':
              if (!value.contains('\u0000')) {
                eventId = value;
              }
              break;
            case 'retry':
              final parsedRetry = int.tryParse(value.trim());
              if (parsedRetry != null && parsedRetry >= 0) {
                retryDelayMs = parsedRetry;
              }
              break;
            case 'data':
              eventData = eventData == null ? value : '$eventData\n$value';
              break;
          }
        }
      },
      onDone: () {
        if (responseStreamFinished) {
          return;
        }
        if (requestWasCancelled()) {
          interruptCancelledStream();
          return;
        }
        if (!streamIsCurrent()) {
          interruptStream();
          return;
        }
        responseStreamFinished = true;

        // Process any final event
        processEvent();
        cancelAbortSubscription();

        // Handle stream closure - likely a network disconnect
        final reconnecting = handleReconnection(lastEventId, retryDelayMs);
        if (!reconnecting) {
          reportUnresumableEnd();
        }
      },
      onError: (error) {
        if (responseStreamFinished) {
          return;
        }
        if (requestWasCancelled()) {
          interruptCancelledStream();
          return;
        }
        if (!streamIsCurrent()) {
          interruptStream();
          return;
        }
        responseStreamFinished = true;
        cancelAbortSubscription();

        final errorMessage =
            error is Error ? error.toString() : error.toString();
        _reportError(McpError(0, "SSE stream disconnected: $errorMessage"));

        // Attempt to reconnect if the stream disconnects unexpectedly
        final reconnecting = handleReconnection(lastEventId, retryDelayMs);
        if (!reconnecting) {
          reportUnresumableEnd('The stream disconnected: $errorMessage');
        }
      },
      cancelOnError: true,
    );

    if (responseStreamFinished) {
      cancelStreamSubscription();
      return;
    }

    // Register the subscription cleanup when the abort controller is triggered
    abortSubscription = _abortController?.stream.listen((_) {
      interruptStream();
    });
    options.requestCancellationTrigger?.then((_) {
      interruptCancelledStream();
    });

    if (!streamIsCurrent()) {
      interruptStream();
    }
  }

  void _reportError(Object error) {
    final reportedError =
        error is Error ? error : McpError(0, error.toString());
    try {
      onerror?.call(reportedError);
    } on Object {
      // User callbacks must not interrupt transport cleanup or settlement.
    }
  }

  void _dispatchReceivedMessage(
    JsonRpcMessage message, {
    required bool rejectServerRequests,
  }) {
    if (rejectServerRequests && message is JsonRpcRequest) {
      _reportError(
        McpError(
          ErrorCode.invalidRequest.value,
          'Server-initiated JSON-RPC requests are not supported on MCP '
          '2026-07-28 stateless response streams; return input_required with '
          'inputRequests instead.',
        ),
      );
      return;
    }

    onmessage?.call(message);
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

  /// Exchanges an authorization code using the legacy v2.2.2 callback shape.
  ///
  /// This method cannot validate the authorization response's `state` or
  /// issuer. It is retained for source and runtime compatibility with callers
  /// that validate the redirect independently. New integrations should use
  /// [finishAuthRedirect].
  @Deprecated(
    'Use finishAuthRedirect to validate the authorization state and issuer.',
  )
  Future<void> finishAuth(String authorizationCode) {
    return _finishAuth(authorizationCode);
  }

  /// Validates an OAuth authorization redirect and exchanges its code.
  ///
  /// Pass the exact [state] returned by the authorization server and its
  /// optional [issuer]. The transport rejects a missing or mismatched value
  /// before contacting the token endpoint.
  Future<void> finishAuthRedirect(
    String authorizationCode, {
    required String state,
    String? issuer,
  }) {
    return _finishAuth(
      authorizationCode,
      state: state,
      issuer: issuer,
      validateRedirect: true,
    );
  }

  /// Exchanges an authorization code for an access token.
  ///
  /// Closing the transport interrupts this future. Provider callbacks that
  /// have already started cannot be forcibly stopped, so provider
  /// implementations remain responsible for suppressing their own late side
  /// effects after cancellation.
  Future<void> _finishAuth(
    String authorizationCode, {
    String? state,
    String? issuer,
    bool validateRedirect = false,
  }) async {
    if (_authProvider == null) {
      throw UnauthorizedError("No auth provider");
    }

    final authProvider = _authProvider;
    final abortBinding = _HttpAbortBinding(
      null,
      additionalAbortStream: _closeController.stream,
    );
    try {
      void ensureTransportOpen() {
        if (_isClosed) {
          throw McpError(
            ErrorCode.connectionClosed.value,
            'Authorization was interrupted because the transport closed.',
          );
        }
      }

      final authGuard = _RequestOperationGuard(
        abortTrigger: abortBinding.abortTrigger,
        ensureCurrent: ensureTransportOpen,
      );
      authGuard.check();
      final pendingAuthorization = _pendingOAuthAuthorization;
      final pendingAuthorizationOwner = _pendingOAuthAuthorizationOwner;
      if (authProvider is OAuthAuthorizationCodeProvider &&
          pendingAuthorization != null) {
        if (validateRedirect) {
          _validateOAuthAuthorizationRedirect(
            pendingAuthorization,
            state: state,
            issuer: issuer,
          );
        }
        await _exchangeAuthorizationCode(
          authProvider,
          authorizationCode,
          pendingAuthorization,
          requestGuard: authGuard,
        );
        if (identical(_pendingOAuthAuthorization, pendingAuthorization) &&
            identical(
              _pendingOAuthAuthorizationOwner,
              pendingAuthorizationOwner,
            )) {
          _pendingOAuthAuthorization = null;
          _pendingOAuthAuthorizationOwner = null;
        }
        return;
      }

      final result = await authGuard.run(
        () => auth(
          authProvider,
          serverUrl: _url,
          authorizationCode: authorizationCode,
        ),
      );
      if (result != "AUTHORIZED") {
        throw UnauthorizedError("Failed to authorize");
      }
    } finally {
      await abortBinding.dispose();
    }
  }

  void _validateOAuthAuthorizationRedirect(
    _PendingOAuthAuthorization pendingAuthorization, {
    String? state,
    String? issuer,
  }) {
    if (state == null || state.isEmpty) {
      throw UnauthorizedError(
        'Authorization redirect did not include required state parameter',
      );
    }

    if (state != pendingAuthorization.state) {
      throw UnauthorizedError('Authorization redirect state mismatch');
    }

    if (pendingAuthorization.authorizationResponseIssParameterSupported ==
            true &&
        (issuer == null || issuer.isEmpty)) {
      throw UnauthorizedError(
        'Authorization response did not include required iss parameter',
      );
    }

    if (issuer != null && issuer != pendingAuthorization.issuer) {
      throw UnauthorizedError(
        'Authorization response issuer does not match authorization server',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    if (!_closeController.isClosed) {
      _closeController.add(null);
      await _closeController.close();
    }

    // Abort any pending requests
    final abortController = _abortController;
    if (abortController != null && !abortController.isClosed) {
      abortController.add(true);
      await abortController.close();
    }
    _httpClient.close();

    onclose?.call();
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
    String? resumptionToken,
    void Function(String)? onResumptionToken,
  }) {
    return _send(
      message,
      relatedRequestId: relatedRequestId,
      resumptionToken: resumptionToken,
      onResumptionToken: onResumptionToken,
    );
  }

  Future<void> _send(
    JsonRpcMessage message, {
    int? relatedRequestId,
    String? resumptionToken,
    void Function(String)? onResumptionToken,
    bool retryStaleSessionOn404 = true,
  }) async {
    final requestCancellation = _registerRequestCancellation(message);
    var retryFailureAlreadyReported = false;
    _HttpAbortBinding? abortBinding;
    try {
      if (_isClosed) {
        final requestId = message is JsonRpcRequest ? message.id : null;
        final requestLabel = requestId == null ? '' : ' $requestId';
        throw McpError(
          ErrorCode.connectionClosed.value,
          'HTTP request$requestLabel was interrupted because the transport '
          'closed.',
        );
      }
      final outgoingProtocolVersion =
          _protocolVersion ?? _protocolVersionFrom(message);
      if (outgoingProtocolVersion != null &&
          isStatelessProtocolVersion(outgoingProtocolVersion) &&
          (message is JsonRpcResponse || message is JsonRpcError)) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          'MCP $outgoingProtocolVersion clients must not send JSON-RPC '
          'responses to servers.',
        );
      }
      if (outgoingProtocolVersion != null &&
          isStatelessProtocolVersion(outgoingProtocolVersion) &&
          message is JsonRpcCancelledNotification) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          'MCP $outgoingProtocolVersion Streamable HTTP cancels a request by '
          'closing its response stream, not by sending '
          '${Method.notificationsCancelled}.',
        );
      }
      if (outgoingProtocolVersion != null &&
          isStatelessProtocolVersion(outgoingProtocolVersion) &&
          message is JsonRpcNotification &&
          isStatelessForbiddenClientNotification(message.method)) {
        throw McpError(
          ErrorCode.invalidRequest.value,
          'MCP $outgoingProtocolVersion clients must not send known '
          'server-to-client notification ${message.method}.',
        );
      }
      if (resumptionToken != null) {
        final protocolVersion =
            _protocolVersion ?? _protocolVersionFrom(message);
        if (protocolVersion != null &&
            isStatelessProtocolVersion(protocolVersion)) {
          throw McpError(
            ErrorCode.invalidRequest.value,
            'MCP $protocolVersion does not support SSE resumption tokens.',
          );
        }
        if (resumptionToken.isEmpty) {
          final requestId = message is JsonRpcRequest ? message.id : null;
          throw _requestSseStreamEndedError(
            requestId,
            'The resumption cursor was reset.',
          );
        }
        // If we have a last event ID, we need to reconnect the SSE stream
        final replayId = message is JsonRpcRequest ? message.id : null;
        await _startOrAuthSse(
          _StartSseOptions(
            resumptionToken: resumptionToken,
            replayMessageId: replayId,
            onResumptionToken: onResumptionToken,
          ),
        );
        return;
      }

      final requestSessionGeneration = _sessionGeneration;
      final requestSessionIdAtStart = _sessionId;
      void ensureRequestIsCurrent() {
        if (requestCancellation?.isCancelled == true) {
          throw http.RequestAbortedException(_url);
        }
        if (_isClosed) {
          final requestId = message is JsonRpcRequest ? message.id : null;
          final requestLabel = requestId == null ? '' : ' $requestId';
          throw McpError(
            ErrorCode.connectionClosed.value,
            'HTTP request$requestLabel was interrupted because the transport '
            'closed.',
          );
        }
        if (requestSessionGeneration != _sessionGeneration) {
          throw StaleSessionError(
            'Session changed while the HTTP request was in flight',
            code: 404,
            sessionId: requestSessionIdAtStart,
          );
        }
      }

      ensureRequestIsCurrent();
      abortBinding = _HttpAbortBinding(
        _abortController,
        requestAbortTrigger: requestCancellation?.trigger,
        additionalAbortStream: _closeController.stream,
      );
      final requestGuard = _RequestOperationGuard(
        abortTrigger: abortBinding.abortTrigger,
        ensureCurrent: ensureRequestIsCurrent,
      );

      // Check for authentication first - if we need auth, handle it before proceeding
      if (_staleSessionDetected && !_isInitializeRequest(message)) {
        throw StaleSessionError('Session not found', code: 404);
      }

      OAuthTokens? tokens;
      if (_authProvider != null) {
        tokens = await requestGuard.run(_authProvider.tokens);
        if (tokens == null) {
          if (_authProvider is OAuthAuthorizationCodeProvider) {
            // Let the server return a challenge so discovery can follow MCP
            // protected-resource metadata before redirecting.
          } else {
            // No tokens available - trigger authentication flow
            await requestGuard.run(_authProvider.redirectToAuthorization);
            throw UnauthorizedError('Authentication required');
          }
        }
      }

      final headers = _commonHeadersWithTokens(tokens);
      if (tokens is OAuthAuthorizationCodeTokens) {
        _oauthRequestedScopes.addAll(_splitOAuthScopes(tokens.scope));
      }
      requestGuard.check();
      headers.addAll(_headersForMessage(message));
      final protocolVersion = _protocolVersion ?? _protocolVersionFrom(message);
      final isStatelessRequest = protocolVersion != null &&
          isStatelessProtocolVersion(protocolVersion);
      if (isStatelessRequest) {
        _removeHeaderCaseInsensitive(headers, 'mcp-session-id');
      }
      final requestSessionId = headers['mcp-session-id'];
      headers['content-type'] = 'application/json';
      headers['accept'] = 'application/json, text/event-stream';

      try {
        ensureRequestIsCurrent();
        final request = http.AbortableRequest(
          'POST',
          _url,
          abortTrigger: abortBinding.abortTrigger,
        );
        request.headers.addAll(headers);
        request.body = jsonEncode(message.toJson());

        final response = await requestGuard.run(
          () => _httpClient.send(request),
        );
        if (_isClosed ||
            requestSessionGeneration != _sessionGeneration ||
            requestCancellation?.isCancelled == true) {
          final responseSubscription = response.stream.listen(null);
          unawaited(responseSubscription.cancel());
          ensureRequestIsCurrent();
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (_authProvider != null &&
              _isAuthorizationRequiredResponse(
                response.statusCode,
                response.headers,
              )) {
            return await _handleAuthorizationRequired(
              response,
              requestGuard: requestGuard,
            );
          }

          final text = await requestGuard.run(
            () => response.stream.transform(utf8.decoder).join(),
          );
          if (response.statusCode == 404 &&
              retryStaleSessionOn404 &&
              requestSessionId != null) {
            String? staleSessionId = requestSessionId;
            if (_sessionId == requestSessionId) {
              staleSessionId = _clearStaleSession();
            }
            if (!_isInitializeRequest(message)) {
              throw StaleSessionError(
                'Session not found',
                code: 404,
                sessionId: staleSessionId,
              );
            }

            try {
              await _send(
                message,
                relatedRequestId: relatedRequestId,
                resumptionToken: resumptionToken,
                onResumptionToken: onResumptionToken,
                retryStaleSessionOn404: false,
              );
            } catch (_) {
              retryFailureAlreadyReported = true;
              rethrow;
            }
            return;
          }
          // HTTP compatibility permits legacy fallback only after a 400
          // discovery response. Keep the HTTP status observable for all other
          // statuses instead of reducing them to the JSON-RPC body error.
          final canDispatchJsonRpcError = message is! JsonRpcRequest ||
              message.method != Method.serverDiscover ||
              response.statusCode == 400;
          if (canDispatchJsonRpcError &&
              _dispatchHttpJsonRpcErrorBody(
                text,
                message,
                rejectServerRequests: isStatelessRequest,
              )) {
            return;
          }
          throw McpError(
            0,
            "Error POSTing to endpoint (HTTP ${response.statusCode}): $text",
          );
        }

        // A server assigns a session ID only on a successful initialization
        // response. Later responses may repeat that ID but cannot replace it.
        final sessionId = response.headers['mcp-session-id'];
        if (sessionId != null && !isStatelessRequest) {
          if (_isInitializeRequest(message)) {
            _sessionId = sessionId;
            _staleSessionDetected = false;
          } else if (_sessionId != null && _sessionId != sessionId) {
            final responseSubscription = response.stream.listen(null);
            await responseSubscription.cancel();
            throw McpError(
              ErrorCode.invalidRequest.value,
              'A non-initialize response attempted to replace the MCP '
              'session ID.',
            );
          }
        }

        // If the response is 202 Accepted, there's no body to process
        if (response.statusCode == 202) {
          // Ensure we drain the stream to release the connection
          await requestGuard.run(response.stream.drain);

          await requestGuard.run(() => Future<void>.delayed(Duration.zero));

          if (isStatelessRequest && message is JsonRpcRequest) {
            throw McpError(
              ErrorCode.invalidRequest.value,
              'A stateless MCP request requires a terminal JSON-RPC response; '
              'the server returned HTTP 202.',
            );
          }

          // if the accepted notification is initialized, we start the SSE stream
          // if it's supported by the server
          if (_isInitializedNotification(message)) {
            // Start without a lastEventId since this is a fresh connection
            _startOrAuthSse(const _StartSseOptions()).catchError((err) {
              _reportError(err);
            });
          }
          return;
        }

        // Start SSE if this was the initialized notification, even if 200 OK
        if (_isInitializedNotification(message)) {
          _startOrAuthSse(const _StartSseOptions()).catchError((err) {
            _reportError(err);
          });
        }

        // Check if the message is a request that expects a response
        final hasRequests = message is JsonRpcRequest && message.id != null;

        // Check the response type
        final contentType = response.headers['content-type'];
        final responseMediaType =
            contentType?.split(';').first.trim().toLowerCase();

        if (hasRequests) {
          if (responseMediaType == 'text/event-stream') {
            // Handle SSE stream responses for requests
            final requestStreamCompletion = Completer<void>();
            _handleSseStream(
              response,
              _StartSseOptions(
                onResumptionToken: onResumptionToken,
                requestMessageId: message.id,
                onTerminalResponse: () {
                  if (!requestStreamCompletion.isCompleted) {
                    requestStreamCompletion.complete();
                  }
                },
                onRequestStreamEnd: (error) {
                  if (!requestStreamCompletion.isCompleted) {
                    requestStreamCompletion.completeError(error);
                  }
                },
                isRequestCancelled: () =>
                    requestCancellation?.isCancelled == true,
                requestCancellationTrigger: requestCancellation?.trigger,
                shouldReconnect: !isStatelessRequest,
                rejectServerRequests: isStatelessRequest,
              ),
              isReconnectable: false,
            );
            await requestStreamCompletion.future;
          } else if (responseMediaType == 'application/json') {
            // For non-streaming servers, we might get direct JSON responses
            final jsonStr = await requestGuard.run(
              () => response.stream.transform(utf8.decoder).join(),
            );
            final data = jsonDecode(jsonStr);

            if (data is List) {
              if (isStatelessRequest) {
                throw McpError(
                  ErrorCode.invalidRequest.value,
                  'MCP $protocolVersion does not support JSON-RPC batch '
                  'responses.',
                );
              }
              for (final item in data) {
                final msg = JsonRpcMessage.fromJson(item);
                _dispatchReceivedMessage(
                  msg,
                  rejectServerRequests: isStatelessRequest,
                );
              }
            } else {
              final msg = JsonRpcMessage.fromJson(data);
              if (isStatelessRequest) {
                final responseId = switch (msg) {
                  JsonRpcResponse(:final id) => id,
                  JsonRpcError(:final id) => id,
                  _ => null,
                };
                if (responseId != message.id) {
                  throw McpError(
                    ErrorCode.invalidRequest.value,
                    'Request ${message.id} received a direct response for '
                    '${responseId ?? 'a null ID'}.',
                  );
                }
              }
              _dispatchReceivedMessage(
                msg,
                rejectServerRequests: isStatelessRequest,
              );
            }
          } else {
            final responseSubscription = response.stream.listen(null);
            await responseSubscription.cancel();
            ensureRequestIsCurrent();
            throw StreamableHttpError(
              -1,
              "Unexpected content type: $contentType",
            );
          }
        } else {
          final responseSubscription = response.stream.listen(null);
          await responseSubscription.cancel();
          ensureRequestIsCurrent();
        }
      } on http.RequestAbortedException {
        ensureRequestIsCurrent();
        rethrow;
      }
    } catch (error) {
      if (!retryFailureAlreadyReported &&
          error is! StaleSessionError &&
          requestCancellation?.isCancelled != true) {
        _reportError(error);
      }
      rethrow;
    } finally {
      await abortBinding?.dispose();
      _unregisterRequestCancellation(message, requestCancellation);
    }
  }

  bool _dispatchHttpJsonRpcErrorBody(
    String body,
    JsonRpcMessage requestMessage, {
    required bool rejectServerRequests,
  }) {
    if (requestMessage is! JsonRpcRequest || body.trim().isEmpty) {
      return false;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return false;
    }
    if (decoded is List && rejectServerRequests) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        'Stateless MCP does not support JSON-RPC batch responses.',
      );
    }

    try {
      final responseCandidates = decoded is List ? decoded : [decoded];
      var dispatched = false;

      for (final candidate in responseCandidates) {
        if (candidate is! Map) {
          continue;
        }
        final parsed = JsonRpcMessage.fromJson(
          candidate.cast<String, dynamic>(),
        );
        if (parsed is! JsonRpcError || parsed.id != requestMessage.id) {
          continue;
        }
        _dispatchReceivedMessage(
          parsed,
          rejectServerRequests: rejectServerRequests,
        );
        dispatched = true;
      }

      return dispatched;
    } catch (_) {
      return false;
    }
  }

  @override
  String? get sessionId => _sessionId;

  @override
  String? get protocolVersion => _protocolVersion;

  @override
  bool canCancelRequest(RequestId requestId) =>
      _requestCancellations.containsKey(requestId);

  @override
  Future<void> cancelRequest(RequestId requestId) async {
    _requestCancellations[requestId]?.cancel();
  }

  @override
  set protocolVersion(String? value) {
    _protocolVersion = value;
  }

  @override
  void setToolParameterHeaderMappings(
    ToolParameterHeaderMappings mappings,
  ) {
    _toolParameterHeaderMappings = {
      for (final entry in mappings.entries)
        entry.key: Map.unmodifiable(Map<String, String>.from(entry.value)),
    };
  }

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
    if (_protocolVersion != null &&
        isStatelessProtocolVersion(_protocolVersion!)) {
      _sessionId = null;
      _staleSessionDetected = false;
      return;
    }

    final terminatingSessionId = _sessionId;
    if (terminatingSessionId == null) {
      return; // No session to terminate
    }

    final terminatingSessionGeneration = _sessionGeneration;
    void ensureTerminationIsCurrent() {
      if (_isClosed) {
        throw McpError(
          ErrorCode.connectionClosed.value,
          'Session termination was interrupted because the transport closed.',
        );
      }
      if (terminatingSessionGeneration != _sessionGeneration ||
          _sessionId != terminatingSessionId) {
        throw StaleSessionError(
          'Session changed while the termination request was in flight',
          code: 404,
          sessionId: terminatingSessionId,
        );
      }
    }

    _HttpAbortBinding? abortBinding = _HttpAbortBinding(
      _abortController,
      additionalAbortStream: _closeController.stream,
    );
    final terminationGuard = _RequestOperationGuard(
      abortTrigger: abortBinding.abortTrigger,
      ensureCurrent: ensureTerminationIsCurrent,
    );
    try {
      final headers = await terminationGuard.run(_commonHeaders);

      final request = http.AbortableRequest(
        'DELETE',
        _url,
        abortTrigger: abortBinding.abortTrigger,
      );
      request.headers.addAll(headers);

      final response = await terminationGuard.run(
        () => _httpClient.send(request),
      );
      if (_isClosed ||
          terminatingSessionGeneration != _sessionGeneration ||
          _sessionId != terminatingSessionId) {
        final responseSubscription = response.stream.listen(null);
        unawaited(responseSubscription.cancel());
        ensureTerminationIsCurrent();
      }
      await terminationGuard.run(response.stream.drain);

      // We specifically handle 405 as a valid response according to the spec,
      // meaning the server does not support explicit session termination
      if (response.statusCode < 200 ||
          response.statusCode >= 300 && response.statusCode != 405) {
        throw StreamableHttpError(
          response.statusCode,
          "Failed to terminate session: ${response.reasonPhrase}",
        );
      }

      await abortBinding.dispose();
      abortBinding = null;
      ensureTerminationIsCurrent();
      _sessionId = null;
      _staleSessionDetected = false;
      _signalSessionChange();
    } on http.RequestAbortedException {
      ensureTerminationIsCurrent();
      rethrow;
    } catch (error) {
      _reportError(error);
      rethrow;
    } finally {
      await abortBinding?.dispose();
    }
  }

  bool _isInitializeRequest(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.method == 'initialize';
    }
    return false;
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

/// Optional OAuth provider interface for first-class MCP authorization-code flow.
abstract class OAuthAuthorizationCodeProvider implements OAuthClientProvider {
  /// OAuth client ID.
  ///
  /// A non-empty value is treated as pre-registered client information and
  /// takes priority over Dynamic Client Registration. When the authorization
  /// server advertises Client ID Metadata Documents, a conforming HTTPS
  /// metadata-document URL is used as such. Return an empty string only to
  /// request deprecated Dynamic Client Registration.
  String get clientId;

  /// Redirect URI registered for the client.
  Uri get redirectUri;

  /// Optional client secret for confidential clients.
  String? get clientSecret;

  /// Requested scopes when a bearer challenge does not provide one.
  List<String> get scopes;

  /// Redirect the user agent to [authorizationUri].
  Future<void> redirectToAuthorizationUrl(Uri authorizationUri);

  /// Persist exchanged OAuth tokens.
  Future<void> saveTokens(OAuthTokens tokens);
}

/// Parsed Bearer `WWW-Authenticate` challenge parameters.
class OAuthBearerChallengeParameters {
  final Uri? resourceMetadata;
  final String? scope;
  final String? error;
  final String? errorDescription;
  final Map<String, String> additionalParameters;

  const OAuthBearerChallengeParameters({
    this.resourceMetadata,
    this.scope,
    this.error,
    this.errorDescription,
    this.additionalParameters = const {},
  });

  factory OAuthBearerChallengeParameters.fromParameters(
    Map<String, String> parameters,
  ) {
    final normalizedParameters = <String, String>{
      for (final entry in parameters.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final knownKeys = {
      'resource_metadata',
      'scope',
      'error',
      'error_description',
    };
    final resourceMetadata = normalizedParameters['resource_metadata'];
    Uri? parsedResourceMetadata;
    if (resourceMetadata != null) {
      final uri = Uri.tryParse(resourceMetadata);
      if (uri != null && uri.hasScheme) {
        parsedResourceMetadata = uri;
      }
    }
    return OAuthBearerChallengeParameters(
      resourceMetadata: parsedResourceMetadata,
      scope: normalizedParameters['scope'],
      error: normalizedParameters['error'],
      errorDescription: normalizedParameters['error_description'],
      additionalParameters: Map<String, String>.fromEntries(
        parameters.entries.where(
          (entry) => !knownKeys.contains(entry.key.toLowerCase()),
        ),
      ),
    );
  }

  static OAuthBearerChallengeParameters? fromHeader(String? header) {
    if (header == null) {
      return null;
    }

    final challenges = _parseOAuthBearerChallenges(header);
    if (challenges.isEmpty) {
      return null;
    }
    return challenges.firstWhere(
      (challenge) => challenge.resourceMetadata != null,
      orElse: () => challenges.first,
    );
  }
}

/// OAuth Protected Resource Metadata discovered by the client transport.
class OAuthProtectedResourceMetadataDocument {
  final Uri resource;
  final List<Uri> authorizationServers;
  final List<String>? bearerMethodsSupported;
  final List<String>? scopesSupported;
  final Map<String, dynamic> additionalFields;

  const OAuthProtectedResourceMetadataDocument({
    required this.resource,
    required this.authorizationServers,
    this.bearerMethodsSupported,
    this.scopesSupported,
    this.additionalFields = const {},
  });

  factory OAuthProtectedResourceMetadataDocument.fromJson(
    Map<String, dynamic> json,
  ) {
    final resource = json['resource'];
    final authorizationServers = json['authorization_servers'];
    if (resource is! String ||
        resource.isEmpty ||
        authorizationServers is! List ||
        authorizationServers.isEmpty) {
      throw const FormatException(
        'Protected-resource metadata requires resource and at least one '
        'authorization_servers entry.',
      );
    }
    final resourceUri = Uri.tryParse(resource);
    if (!_isAbsoluteHttpUriWithoutUserInfoOrFragment(resourceUri)) {
      throw const FormatException(
        'Protected-resource metadata resource must be an absolute HTTP(S) URI '
        'without user information or a fragment.',
      );
    }
    final parsedAuthorizationServers = <Uri>[];
    for (final value in authorizationServers) {
      if (value is! String || value.isEmpty) {
        throw const FormatException(
          'Protected-resource metadata authorization_servers entries must be '
          'non-empty URI strings.',
        );
      }
      final uri = Uri.tryParse(value);
      if (!_isAbsoluteHttpUriWithoutUserInfoOrFragment(uri)) {
        throw const FormatException(
          'Protected-resource metadata authorization_servers entries must be '
          'absolute HTTP(S) URIs without user information or fragments.',
        );
      }
      parsedAuthorizationServers.add(uri!);
    }

    return OAuthProtectedResourceMetadataDocument(
      resource: resourceUri!,
      authorizationServers: parsedAuthorizationServers,
      bearerMethodsSupported:
          (json['bearer_methods_supported'] as List?)?.cast<String>(),
      scopesSupported: (json['scopes_supported'] as List?)?.cast<String>(),
      additionalFields: Map<String, dynamic>.from(json)
        ..removeWhere(
          (key, value) => {
            'resource',
            'authorization_servers',
            'bearer_methods_supported',
            'scopes_supported',
          }.contains(key),
        ),
    );
  }
}

/// OAuth Authorization Server Metadata discovered by the client transport.
class OAuthAuthorizationServerMetadataDocument {
  final Uri issuer;
  final Uri? authorizationEndpoint;
  final Uri? tokenEndpoint;
  final Uri? registrationEndpoint;
  final List<String>? codeChallengeMethodsSupported;
  final List<String>? tokenEndpointAuthMethodsSupported;
  final bool? clientIdMetadataDocumentSupported;
  final bool? authorizationResponseIssParameterSupported;
  final Map<String, dynamic> additionalFields;

  const OAuthAuthorizationServerMetadataDocument({
    required this.issuer,
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.registrationEndpoint,
    this.codeChallengeMethodsSupported,
    this.tokenEndpointAuthMethodsSupported,
    this.clientIdMetadataDocumentSupported,
    this.authorizationResponseIssParameterSupported,
    this.additionalFields = const {},
  });

  factory OAuthAuthorizationServerMetadataDocument.fromJson(
    Map<String, dynamic> json,
  ) {
    final issuer = json['issuer'];
    final issuerUri = issuer is String ? Uri.tryParse(issuer) : null;
    if (issuer is! String ||
        issuer.isEmpty ||
        !_isAbsoluteHttpUriWithoutUserInfoOrFragment(issuerUri)) {
      throw const FormatException(
        'Authorization-server metadata requires an absolute HTTP(S) issuer '
        'without user information or a fragment.',
      );
    }

    final authorizationEndpoint = json['authorization_endpoint'];
    final tokenEndpoint = json['token_endpoint'];
    final clientIdMetadataDocumentSupported =
        json['client_id_metadata_document_supported'];
    if (clientIdMetadataDocumentSupported != null &&
        clientIdMetadataDocumentSupported is! bool) {
      throw const FormatException(
        'client_id_metadata_document_supported must be a boolean.',
      );
    }
    return OAuthAuthorizationServerMetadataDocument(
      issuer: issuerUri!,
      authorizationEndpoint: authorizationEndpoint is String
          ? Uri.parse(authorizationEndpoint)
          : null,
      tokenEndpoint: tokenEndpoint is String ? Uri.parse(tokenEndpoint) : null,
      registrationEndpoint: json['registration_endpoint'] is String
          ? Uri.parse(json['registration_endpoint'] as String)
          : null,
      codeChallengeMethodsSupported:
          (json['code_challenge_methods_supported'] as List?)?.cast<String>(),
      tokenEndpointAuthMethodsSupported:
          (json['token_endpoint_auth_methods_supported'] as List?)
              ?.cast<String>(),
      clientIdMetadataDocumentSupported:
          clientIdMetadataDocumentSupported as bool?,
      authorizationResponseIssParameterSupported:
          json['authorization_response_iss_parameter_supported'] as bool?,
      additionalFields: Map<String, dynamic>.from(json)
        ..removeWhere(
          (key, value) => {
            'issuer',
            'authorization_endpoint',
            'token_endpoint',
            'registration_endpoint',
            'code_challenge_methods_supported',
            'token_endpoint_auth_methods_supported',
            'client_id_metadata_document_supported',
            'authorization_response_iss_parameter_supported',
          }.contains(key),
        ),
    );
  }
}

/// Authorization request built from MCP OAuth discovery metadata.
class OAuthAuthorizationRequest {
  final Uri authorizationUri;
  final String codeVerifier;
  final String codeChallenge;
  final String state;
  final Uri resource;
  final String? scope;

  const OAuthAuthorizationRequest({
    required this.authorizationUri,
    required this.codeVerifier,
    required this.codeChallenge,
    required this.state,
    required this.resource,
    this.scope,
  });
}

/// Represents OAuth tokens
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;

  OAuthTokens({
    required this.accessToken,
    this.refreshToken,
  });
}

/// OAuth authorization-code token response metadata.
///
/// The transport passes this subtype to [OAuthAuthorizationCodeProvider.saveTokens]
/// after exchanging an authorization code. It keeps [OAuthTokens] source-compatible
/// for existing subclasses while exposing standard token response fields.
class OAuthAuthorizationCodeTokens extends OAuthTokens {
  final String tokenType;
  final int? expiresIn;
  final String? scope;

  OAuthAuthorizationCodeTokens({
    required super.accessToken,
    super.refreshToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
    this.scope,
  });
}

/// Authorization-code tokens bound to their issuing authorization server and
/// protected resource.
///
/// Providers should persist these fields together with the token values. The
/// transport uses them to prevent credentials from being reused after a
/// protected resource migrates to a different authorization server.
class OAuthIssuerBoundAuthorizationCodeTokens
    extends OAuthAuthorizationCodeTokens {
  /// Exact issuer identifier from validated authorization-server metadata.
  final String authorizationServerIssuer;

  /// Protected resource for which the access token was requested.
  final Uri resource;

  /// Creates authorization-code tokens bound to an issuer and resource.
  OAuthIssuerBoundAuthorizationCodeTokens({
    required super.accessToken,
    super.refreshToken,
    super.tokenType,
    super.expiresIn,
    super.scope,
    required this.authorizationServerIssuer,
    required this.resource,
  });
}

class _PendingOAuthAuthorization {
  final Uri tokenEndpoint;
  final String codeVerifier;
  final String clientId;
  final String? clientSecret;
  final String tokenEndpointAuthMethod;
  final Uri redirectUri;
  final Uri resource;
  final String issuer;
  final String state;
  final String? scope;
  final bool? authorizationResponseIssParameterSupported;

  const _PendingOAuthAuthorization({
    required this.tokenEndpoint,
    required this.codeVerifier,
    required this.clientId,
    required this.clientSecret,
    required this.tokenEndpointAuthMethod,
    required this.redirectUri,
    required this.resource,
    required this.issuer,
    required this.state,
    required this.scope,
    required this.authorizationResponseIssParameterSupported,
  });
}

class _PreparedOAuthAuthorization {
  final OAuthAuthorizationRequest request;
  final _PendingOAuthAuthorization pending;

  const _PreparedOAuthAuthorization({
    required this.request,
    required this.pending,
  });
}

class _DiscoveredProtectedResourceMetadata {
  final OAuthProtectedResourceMetadataDocument document;
  final List<String> authorizationServerIdentifiers;

  const _DiscoveredProtectedResourceMetadata({
    required this.document,
    required this.authorizationServerIdentifiers,
  });
}

class _DiscoveredAuthorizationServerMetadata {
  final OAuthAuthorizationServerMetadataDocument document;
  final String issuerIdentifier;

  const _DiscoveredAuthorizationServerMetadata({
    required this.document,
    required this.issuerIdentifier,
  });
}

class _OAuthClientRegistration {
  final String clientId;
  final String? clientSecret;
  final String tokenEndpointAuthMethod;

  const _OAuthClientRegistration({
    required this.clientId,
    required this.clientSecret,
    required this.tokenEndpointAuthMethod,
  });
}

bool _isAbsoluteHttpUriWithoutUserInfoOrFragment(Uri? uri) =>
    uri != null &&
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.fragment.isEmpty;

List<OAuthBearerChallengeParameters> _parseOAuthBearerChallenges(
  String? header,
) {
  if (header == null || header.trim().isEmpty) {
    return const [];
  }

  final challenges = <OAuthBearerChallengeParameters>[];
  String? currentScheme;
  final currentParts = <String>[];
  final parameterPrefix = RegExp(
    r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+\s*=",
  );
  final challengePrefix = RegExp(
    r"^([!#$%&'*+\-.^_`|~0-9A-Za-z]+)(?:\s+(.*))?$",
    dotAll: true,
  );

  void finishChallenge() {
    if (currentScheme?.toLowerCase() == 'bearer') {
      challenges.add(
        OAuthBearerChallengeParameters.fromParameters(
          _parseAuthenticateParameters(currentParts.join(', ')),
        ),
      );
    }
    currentScheme = null;
    currentParts.clear();
  }

  for (final rawSegment in _splitAuthenticateHeaderSegments(header)) {
    final segment = rawSegment.trim();
    if (segment.isEmpty) {
      continue;
    }
    if (parameterPrefix.hasMatch(segment)) {
      if (currentScheme != null) {
        currentParts.add(segment);
      }
      continue;
    }

    final match = challengePrefix.firstMatch(segment);
    if (match == null) {
      continue;
    }
    finishChallenge();
    currentScheme = match.group(1);
    final challengeValue = match.group(2)?.trim();
    if (challengeValue?.isNotEmpty == true) {
      currentParts.add(challengeValue!);
    }
  }
  finishChallenge();
  return challenges;
}

List<String> _splitAuthenticateHeaderSegments(String header) {
  final segments = <String>[];
  final current = StringBuffer();
  var quoted = false;
  var escaped = false;
  for (final codeUnit in header.codeUnits) {
    final char = String.fromCharCode(codeUnit);
    if (escaped) {
      current.write(char);
      escaped = false;
      continue;
    }
    if (quoted && char == '\\') {
      current.write(char);
      escaped = true;
      continue;
    }
    if (char == '"') {
      quoted = !quoted;
      current.write(char);
      continue;
    }
    if (char == ',' && !quoted) {
      segments.add(current.toString());
      current.clear();
      continue;
    }
    current.write(char);
  }
  segments.add(current.toString());
  return segments;
}

Map<String, String> _parseAuthenticateParameters(String input) {
  final parameters = <String, String>{};
  var index = 0;

  void skipSeparators() {
    while (index < input.length &&
        (input.codeUnitAt(index) == 0x20 || input[index] == ',')) {
      index += 1;
    }
  }

  while (index < input.length) {
    skipSeparators();
    if (index >= input.length) {
      break;
    }

    final keyStart = index;
    while (index < input.length && input[index] != '=' && input[index] != ',') {
      index += 1;
    }
    if (index >= input.length || input[index] != '=') {
      break;
    }

    final key = input.substring(keyStart, index).trim();
    index += 1;

    String value;
    if (index < input.length && input[index] == '"') {
      index += 1;
      final buffer = StringBuffer();
      while (index < input.length) {
        final char = input[index];
        if (char == '\\') {
          index += 1;
          if (index < input.length) {
            buffer.write(input[index]);
            index += 1;
          }
          continue;
        }
        if (char == '"') {
          index += 1;
          break;
        }
        buffer.write(char);
        index += 1;
      }
      value = buffer.toString();
    } else {
      final valueStart = index;
      while (index < input.length && input[index] != ',') {
        index += 1;
      }
      value = input.substring(valueStart, index).trim();
    }

    if (key.isNotEmpty) {
      parameters[key] = value;
    }
  }

  return parameters;
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
