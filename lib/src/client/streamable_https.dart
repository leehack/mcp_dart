import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
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

const int _maxSafeHeaderInteger = 9007199254740991;
const int _minSafeHeaderInteger = -9007199254740991;

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

  /// The originating request ID for a request-scoped SSE response.
  ///
  /// Unlike [replayMessageId], this does not rewrite wire messages. It only
  /// tracks completion and supplies the ID if the stream must later resume.
  final RequestId? requestMessageId;

  /// Completes the originating send after its terminal response is dispatched.
  final void Function()? onTerminalResponse;

  /// Fails the originating send when its response stream cannot resume.
  final void Function(Error error)? onRequestStreamEnd;

  /// Whether to attempt reconnection when the stream closes.
  /// Default is true.
  final bool shouldReconnect;

  /// Whether JSON-RPC requests received on this stream should be rejected.
  final bool rejectServerRequests;

  const StartSseOptions({
    this.resumptionToken,
    this.onResumptionToken,
    this.replayMessageId,
    this.requestMessageId,
    this.onTerminalResponse,
    this.onRequestStreamEnd,
    this.shouldReconnect = true,
    this.rejectServerRequests = false,
  });
}

class _HttpAbortBinding {
  final Completer<void> _abortTrigger = Completer<void>();
  // Cancelled by [dispose] after the bound request settles.
  // ignore: cancel_subscriptions
  StreamSubscription<bool>? _subscription;

  _HttpAbortBinding(StreamController<bool>? controller) {
    if (controller == null || controller.isClosed) {
      return;
    }
    _subscription = controller.stream.listen((_) {
      if (!_abortTrigger.isCompleted) {
        _abortTrigger.complete();
      }
    });
  }

  Future<void> get abortTrigger => _abortTrigger.future;

  Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
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
  final Map<String, _OAuthClientRegistration> _oauthRegistrations = {};
  final Set<String> _oauthRequestedScopes = {};

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
    final challenge =
        OAuthBearerChallengeParameters.fromHeader(headers['www-authenticate']);
    return challenge?.error == 'insufficient_scope';
  }

  Future<void> _handleAuthorizationRequired(
    http.StreamedResponse response,
  ) async {
    final authProvider = _authProvider;
    if (authProvider == null) {
      await response.stream.drain<void>();
      throw UnauthorizedError('Authentication required');
    }

    final challenge = OAuthBearerChallengeParameters.fromHeader(
      response.headers['www-authenticate'],
    );
    await response.stream.drain<void>();

    if (authProvider is OAuthAuthorizationCodeProvider) {
      final authorizationRequest = await _prepareAuthorizationRequest(
        authProvider,
        challenge,
      );
      await authProvider.redirectToAuthorizationUrl(
        authorizationRequest.authorizationUri,
      );
      throw UnauthorizedError('Authentication required');
    }

    await authProvider.redirectToAuthorization();
    throw UnauthorizedError('Authentication required');
  }

  Future<OAuthAuthorizationRequest> _prepareAuthorizationRequest(
    OAuthAuthorizationCodeProvider provider,
    OAuthBearerChallengeParameters? challenge,
  ) async {
    final protectedResourceMetadata =
        await _discoverProtectedResourceMetadata(challenge);
    final authorizationServerUri =
        protectedResourceMetadata.authorizationServers.isEmpty
            ? null
            : protectedResourceMetadata.authorizationServers.first;
    if (authorizationServerUri == null) {
      throw UnauthorizedError(
        'Protected resource metadata did not include authorization_servers',
      );
    }
    _validateOAuthUri(
      authorizationServerUri,
      OAuthEndpointKind.authorizationServer,
    );

    final authorizationServerMetadata =
        await _discoverAuthorizationServerMetadata(authorizationServerUri);
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

    _pendingOAuthAuthorization = _PendingOAuthAuthorization(
      tokenEndpoint: tokenEndpoint,
      codeVerifier: codeVerifier,
      clientId: clientRegistration.clientId,
      clientSecret: clientRegistration.clientSecret,
      tokenEndpointAuthMethod: clientRegistration.tokenEndpointAuthMethod,
      redirectUri: provider.redirectUri,
      resource: protectedResourceMetadata.resource,
      issuer: authorizationServerMetadata.issuer.toString(),
      state: state,
      scope: scope,
      authorizationResponseIssParameterSupported: authorizationServerMetadata
          .authorizationResponseIssParameterSupported,
    );

    return authorizationRequest;
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
    OAuthAuthorizationServerMetadataDocument authorizationServerMetadata,
  ) async {
    final issuerKey = authorizationServerMetadata.issuer.toString();
    if (authorizationServerMetadata.clientIdMetadataDocumentSupported == true &&
        _isClientIdMetadataDocumentUri(provider.clientId)) {
      return _OAuthClientRegistration(
        clientId: provider.clientId,
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
      final existingRegistration = _oauthRegistrations[issuerKey];
      if (existingRegistration != null) {
        return existingRegistration;
      }

      final registration = await _registerOAuthClient(
        provider,
        authorizationServerMetadata,
        registrationEndpoint,
      );
      _oauthRegistrations[issuerKey] = registration;
      return registration;
    }

    return _OAuthClientRegistration(
      clientId: provider.clientId,
      clientSecret: provider.clientSecret,
      tokenEndpointAuthMethod: _selectTokenEndpointAuthMethod(
        authorizationServerMetadata,
        provider.clientSecret,
      ),
    );
  }

  bool _isClientIdMetadataDocumentUri(String value) {
    final uri = Uri.tryParse(value);
    // The pinned MCP client-registration rules require an HTTPS client ID
    // with a non-root path before it can identify a metadata document.
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.pathSegments.any((segment) => segment.isNotEmpty);
  }

  Future<_OAuthClientRegistration> _registerOAuthClient(
    OAuthAuthorizationCodeProvider provider,
    OAuthAuthorizationServerMetadataDocument authorizationServerMetadata,
    Uri registrationEndpoint,
  ) async {
    _validateOAuthUri(
      registrationEndpoint,
      OAuthEndpointKind.registrationEndpoint,
    );
    final tokenEndpointAuthMethod = _selectTokenEndpointAuthMethod(
      authorizationServerMetadata,
      provider.clientSecret,
    );
    final response = await _sendOAuthRequest(
      'POST',
      registrationEndpoint,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'client_name': provider.clientId,
        'redirect_uris': [provider.redirectUri.toString()],
        'grant_types': ['authorization_code', 'refresh_token'],
        'response_types': ['code'],
        'application_type': 'native',
        'token_endpoint_auth_method': tokenEndpointAuthMethod,
      }),
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

  Future<OAuthProtectedResourceMetadataDocument>
      _discoverProtectedResourceMetadata(
    OAuthBearerChallengeParameters? challenge,
  ) async {
    final resourceMetadata = challenge?.resourceMetadata;
    if (resourceMetadata != null) {
      return _fetchProtectedResourceMetadata(resourceMetadata);
    }

    final errors = <Object>[];
    for (final uri in _protectedResourceMetadataCandidates()) {
      try {
        return await _fetchProtectedResourceMetadata(uri);
      } catch (error) {
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

  Future<OAuthProtectedResourceMetadataDocument>
      _fetchProtectedResourceMetadata(Uri uri) async {
    _validateOAuthUri(uri, OAuthEndpointKind.protectedResourceMetadata);
    final response = await _sendOAuthRequest(
      'GET',
      uri,
      headers: const {'Accept': 'application/json'},
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
    return metadata;
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
      _discoverAuthorizationServerMetadata(Uri issuer) async {
    _validateOAuthUri(issuer, OAuthEndpointKind.authorizationServer);
    final errors = <Object>[];
    for (final uri in _authorizationServerMetadataCandidates(issuer)) {
      try {
        final metadata = await _fetchAuthorizationServerMetadata(uri);
        if (metadata.issuer.toString() != issuer.toString()) {
          throw UnauthorizedError(
            'Authorization-server metadata issuer does not match $issuer',
          );
        }
        return metadata;
      } catch (error) {
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

  Future<OAuthAuthorizationServerMetadataDocument>
      _fetchAuthorizationServerMetadata(Uri uri) async {
    _validateOAuthUri(uri, OAuthEndpointKind.authorizationServerMetadata);
    final response = await _sendOAuthRequest(
      'GET',
      uri,
      headers: const {'Accept': 'application/json'},
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
    return metadata;
  }

  Future<OAuthTokens> _exchangeAuthorizationCode(
    OAuthAuthorizationCodeProvider provider,
    String authorizationCode,
    _PendingOAuthAuthorization pendingAuthorization,
  ) async {
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

    final response = await _sendOAuthRequest(
      'POST',
      pendingAuthorization.tokenEndpoint,
      headers: headers,
      body: body,
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

    final tokens = OAuthAuthorizationCodeTokens(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: _parseExpiresIn(json['expires_in']),
      scope: json['scope'] as String?,
    );
    _oauthRequestedScopes.addAll(_splitOAuthScopes(pendingAuthorization.scope));
    _oauthRequestedScopes.addAll(_splitOAuthScopes(tokens.scope));
    await provider.saveTokens(tokens);
    return tokens;
  }

  Future<http.Response> _sendOAuthRequest(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final request = http.Request(method, uri)
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
    final response = await http.Response.fromStream(streamedResponse);
    if (response.isRedirect) {
      throw UnauthorizedError(
        'OAuth endpoint redirects are not followed automatically',
      );
    }
    return response;
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
    final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));
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
    final headers = <String, String>{};

    if (_authProvider != null) {
      final tokens = await _authProvider.tokens();
      if (tokens != null) {
        headers["Authorization"] = "Bearer ${tokens.accessToken}";
      }
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
      headers['Mcp-Name'] = name;
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

      final value = _toolParameterHeaderString(argument.value);
      if (value == null) {
        continue;
      }

      headers['Mcp-Param-${entry.value}'] =
          _encodeToolParameterHeaderValue(value);
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

  String _encodeToolParameterHeaderValue(String value) {
    if (_isPlainToolParameterHeaderValue(value)) {
      return value;
    }

    return '=?base64?${base64Encode(utf8.encode(value))}?=';
  }

  bool _isPlainToolParameterHeaderValue(String value) {
    return !_isBase64ToolParameterHeaderSentinel(value) &&
        value.trim() == value &&
        value.codeUnits.every(
          (unit) => unit == 0x09 || (unit >= 0x20 && unit <= 0x7E),
        );
  }

  bool _isBase64ToolParameterHeaderSentinel(String value) {
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
    StartSseOptions options, {
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
    _HttpAbortBinding? abortBinding;
    try {
      // Try to open an initial SSE stream with GET to listen for server messages
      // This is optional according to the spec - server may not support it
      final headers = await _commonHeaders();
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

      abortBinding = _HttpAbortBinding(_abortController);
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
      final response = await _httpClient.send(request);

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
          return await _handleAuthorizationRequired(response);
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
      _reportError(error);
      rethrow;
    } finally {
      await abortBinding?.dispose();
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
    StartSseOptions options, [
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
    StartSseOptions options, {
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

    // Function to process a complete SSE event
    void processEvent() {
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
        }

        try {
          _dispatchReceivedMessage(
            message,
            rejectServerRequests: options.rejectServerRequests,
          );
        } finally {
          if (isTerminalResponse) {
            settleTerminalResponse();
          }
        }
      } catch (error) {
        _reportError(error);
      }
    }

    // Helper function to handle reconnection logic
    bool handleReconnection(String? eventId, [int? retryDelayOverrideMs]) {
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
            StartSseOptions(
              resumptionToken: eventId,
              onResumptionToken: onResumptionToken,
              replayMessageId: replayMessageId ?? requestMessageId,
              requestMessageId: requestMessageId,
              onTerminalResponse: options.onTerminalResponse,
              onRequestStreamEnd: options.onRequestStreamEnd,
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
          'Server-initiated JSON-RPC requests are not supported on 2026 '
          'stateless MCP response streams; return input_required with '
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

  /// Call this method after the user has finished authorizing via their user agent and is redirected
  /// back to the MCP client application. This will exchange the authorization code for an access token,
  /// enabling the next connection attempt to successfully auth.
  Future<void> finishAuth(
    String authorizationCode, {
    String? state,
    String? issuer,
  }) async {
    if (_authProvider == null) {
      throw UnauthorizedError("No auth provider");
    }

    final authProvider = _authProvider;
    final pendingAuthorization = _pendingOAuthAuthorization;
    if (authProvider is OAuthAuthorizationCodeProvider &&
        pendingAuthorization != null) {
      _validateOAuthAuthorizationRedirect(
        pendingAuthorization,
        state: state,
        issuer: issuer,
      );
      await _exchangeAuthorizationCode(
        authProvider,
        authorizationCode,
        pendingAuthorization,
      );
      _pendingOAuthAuthorization = null;
      return;
    }

    final result = await auth(
      authProvider,
      serverUrl: _url,
      authorizationCode: authorizationCode,
    );
    if (result != "AUTHORIZED") {
      throw UnauthorizedError("Failed to authorize");
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
    var retryFailureAlreadyReported = false;
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
          StartSseOptions(
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

      // Check for authentication first - if we need auth, handle it before proceeding
      if (_staleSessionDetected && !_isInitializeRequest(message)) {
        throw StaleSessionError('Session not found', code: 404);
      }

      if (_authProvider != null) {
        final tokens = await _authProvider.tokens();
        ensureRequestIsCurrent();
        if (tokens == null) {
          if (_authProvider is OAuthAuthorizationCodeProvider) {
            // Let the server return a challenge so discovery can follow MCP
            // protected-resource metadata before redirecting.
          } else {
            // No tokens available - trigger authentication flow
            await _authProvider.redirectToAuthorization();
            throw UnauthorizedError('Authentication required');
          }
        }
      }

      final headers = await _commonHeaders();
      ensureRequestIsCurrent();
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

      final abortBinding = _HttpAbortBinding(_abortController);
      try {
        ensureRequestIsCurrent();
        final request = http.AbortableRequest(
          'POST',
          _url,
          abortTrigger: abortBinding.abortTrigger,
        );
        request.headers.addAll(headers);
        request.body = jsonEncode(message.toJson());

        final response = await _httpClient.send(request);
        if (_isClosed || requestSessionGeneration != _sessionGeneration) {
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
            return await _handleAuthorizationRequired(response);
          }

          final text = await response.stream.transform(utf8.decoder).join();
          ensureRequestIsCurrent();
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
          await response.stream.drain();

          await Future.delayed(Duration.zero);
          ensureRequestIsCurrent();

          // if the accepted notification is initialized, we start the SSE stream
          // if it's supported by the server
          if (_isInitializedNotification(message)) {
            // Start without a lastEventId since this is a fresh connection
            _startOrAuthSse(const StartSseOptions()).catchError((err) {
              _reportError(err);
            });
          }
          return;
        }

        // Start SSE if this was the initialized notification, even if 200 OK
        if (_isInitializedNotification(message)) {
          _startOrAuthSse(const StartSseOptions()).catchError((err) {
            _reportError(err);
          });
        }

        // Check if the message is a request that expects a response
        final hasRequests = message is JsonRpcRequest && message.id != null;

        // Check the response type
        final contentType = response.headers['content-type'];

        if (hasRequests) {
          if (contentType?.contains('text/event-stream') ?? false) {
            // Handle SSE stream responses for requests
            final requestStreamCompletion = Completer<void>();
            _handleSseStream(
              response,
              StartSseOptions(
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
                shouldReconnect: !isStatelessRequest,
                rejectServerRequests: isStatelessRequest,
              ),
              isReconnectable: false,
            );
            await requestStreamCompletion.future;
          } else if (contentType?.contains('application/json') ?? false) {
            // For non-streaming servers, we might get direct JSON responses
            final jsonStr =
                await response.stream.transform(utf8.decoder).join();
            ensureRequestIsCurrent();
            final data = jsonDecode(jsonStr);

            if (data is List) {
              for (final item in data) {
                final msg = JsonRpcMessage.fromJson(item);
                _dispatchReceivedMessage(
                  msg,
                  rejectServerRequests: isStatelessRequest,
                );
              }
            } else {
              final msg = JsonRpcMessage.fromJson(data);
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
      } finally {
        await abortBinding.dispose();
      }
    } catch (error) {
      if (!retryFailureAlreadyReported && error is! StaleSessionError) {
        _reportError(error);
      }
      rethrow;
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

    try {
      final decoded = jsonDecode(body);
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

    _HttpAbortBinding? abortBinding;
    try {
      final headers = await _commonHeaders();
      ensureTerminationIsCurrent();

      abortBinding = _HttpAbortBinding(_abortController);
      final request = http.AbortableRequest(
        'DELETE',
        _url,
        abortTrigger: abortBinding.abortTrigger,
      );
      request.headers.addAll(headers);

      final response = await _httpClient.send(request);
      if (_isClosed ||
          terminatingSessionGeneration != _sessionGeneration ||
          _sessionId != terminatingSessionId) {
        final responseSubscription = response.stream.listen(null);
        unawaited(responseSubscription.cancel());
        ensureTerminationIsCurrent();
      }
      await response.stream.drain<void>();
      ensureTerminationIsCurrent();

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
  /// OAuth client id.
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
    final knownKeys = {
      'resource_metadata',
      'scope',
      'error',
      'error_description',
    };
    final resourceMetadata = parameters['resource_metadata'];
    Uri? parsedResourceMetadata;
    if (resourceMetadata != null) {
      final uri = Uri.tryParse(resourceMetadata);
      if (uri != null && uri.hasScheme) {
        parsedResourceMetadata = uri;
      }
    }
    return OAuthBearerChallengeParameters(
      resourceMetadata: parsedResourceMetadata,
      scope: parameters['scope'],
      error: parameters['error'],
      errorDescription: parameters['error_description'],
      additionalParameters: Map<String, String>.from(parameters)
        ..removeWhere((key, value) => knownKeys.contains(key)),
    );
  }

  static OAuthBearerChallengeParameters? fromHeader(String? header) {
    if (header == null) {
      return null;
    }

    final trimmed = header.trim();
    if (!trimmed.toLowerCase().startsWith('bearer')) {
      return null;
    }

    final parameters = _parseAuthenticateParameters(
      trimmed.substring('bearer'.length).trim(),
    );
    return OAuthBearerChallengeParameters.fromParameters(parameters);
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
    if (resource is! String || authorizationServers is! List) {
      throw const FormatException(
        'Protected-resource metadata requires resource and authorization_servers.',
      );
    }

    return OAuthProtectedResourceMetadataDocument(
      resource: Uri.parse(resource),
      authorizationServers: authorizationServers
          .map((value) => Uri.parse(value as String))
          .toList(),
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
    if (issuer is! String) {
      throw const FormatException(
        'Authorization-server metadata requires issuer.',
      );
    }

    final authorizationEndpoint = json['authorization_endpoint'];
    final tokenEndpoint = json['token_endpoint'];
    return OAuthAuthorizationServerMetadataDocument(
      issuer: Uri.parse(issuer),
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
          json['client_id_metadata_document_supported'] as bool?,
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
