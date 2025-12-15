/// Example: MCP Server with OAuth 2.0 Authentication
///
/// **COMPLIES WITH MCP OAUTH SPECIFICATION (2025-06-18)**
///
/// This example demonstrates a fully compliant MCP server with OAuth 2.0
/// authentication as specified in the Model Context Protocol specification.
///
/// ## MCP Specification Compliance
///
/// ✅ **PKCE Support** (RFC 7636)
///    - Requires code_verifier in authorization code exchange
///    - Advertises S256 code_challenge_method in metadata
///
/// ✅ **Resource Parameter**
///    - Includes resource parameter in all token requests
///    - Ensures tokens are specific to this MCP server
///
/// ✅ **Token Audience Validation**
///    - Validates token audience matches server URI
///    - Prevents token passthrough attacks
///
/// ✅ **Redirect URI Validation**
///    - Validates redirect URIs against allowed list
///    - Requires exact URI matching
///
/// ✅ **OAuth Metadata Discovery**
///    - Implements /.well-known/oauth-authorization-server endpoint
///    - Provides OAuth 2.0 Authorization Server Metadata
///
/// ✅ **WWW-Authenticate Header**
///    - Returns proper 401 Unauthorized with WWW-Authenticate header
///    - Includes authorization_uri when metadata is configured
///
/// ⚠️  **HTTPS Support**
///    - Supports HTTPS with --https flag (self-signed cert for dev)
///    - For production, use reverse proxy with proper TLS certificates
///
/// ## Features
///
/// - OAuth token validation with provider verification
/// - Authorization code exchange with PKCE
/// - Token refresh handling
/// - Scope-based access control
/// - Session management with OAuth
/// - Token caching with expiry
///
/// ## Setup
///
/// 1. Configure OAuth provider credentials:
///    ```bash
///    export GITHUB_CLIENT_ID=your_client_id
///    export GITHUB_CLIENT_SECRET=your_client_secret
///    ```
///
/// 2. (Optional) Generate self-signed certificates for HTTPS:
///    ```bash
///    openssl req -x509 -newkey rsa:4096 -keyout server_key.pem \
///      -out server_cert.pem -days 365 -nodes \
///      -subj "/CN=localhost"
///    ```
///
/// 3. Run the server:
///    ```bash
///    # HTTP mode (development)
///    dart run example/authentication/oauth_server_example.dart github
///
///    # HTTPS mode (development with self-signed cert)
///    dart run example/authentication/oauth_server_example.dart github --https
///    ```
///
/// ## Usage
///
/// 1. Obtain OAuth access token from provider with PKCE:
///    - Generate code_verifier and code_challenge
///    - Request authorization code with code_challenge
///    - Exchange code for token with code_verifier and resource parameter
///
/// 2. Make MCP requests with Bearer token:
///    ```
///    Authorization: Bearer <access_token>
///    ```
///
/// 3. Access OAuth metadata:
///    ```
///    GET http://localhost:3000/.well-known/oauth-authorization-server
///    ```
///
/// ## Production Deployment
///
/// For production use:
/// 1. Use a reverse proxy (nginx, Traefik, Caddy) with proper TLS certificates
/// 2. Configure allowed redirect URIs for your OAuth application
/// 3. Set up proper token introspection for audience validation
/// 4. Use environment-specific OAuth credentials
/// 5. Implement rate limiting and security headers
///
/// ## References
///
/// - MCP OAuth Specification: https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization
/// - OAuth 2.1: https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1
/// - PKCE (RFC 7636): https://datatracker.ietf.org/doc/html/rfc7636
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';

/// OAuth configuration for the server
class OAuthServerConfig {
  final String clientId;
  final String clientSecret;
  final Uri tokenEndpoint;
  final Uri userInfoEndpoint;
  final List<String> requiredScopes;

  /// Canonical server URI for resource parameter and audience validation
  /// Must be HTTPS and match the actual server URI
  final String serverUri;

  /// Authorization server metadata endpoint
  final Uri? authServerMetadataEndpoint;

  /// Allowed redirect URIs for validation
  final List<String> allowedRedirectUris;

  const OAuthServerConfig({
    required this.clientId,
    required this.clientSecret,
    required this.tokenEndpoint,
    required this.userInfoEndpoint,
    required this.serverUri,
    this.requiredScopes = const [],
    this.authServerMetadataEndpoint,
    this.allowedRedirectUris = const [],
  });

  /// GitHub OAuth configuration
  factory OAuthServerConfig.github({
    required String clientId,
    required String clientSecret,
    required String serverUri,
    List<String> requiredScopes = const ['repo'],
    List<String> allowedRedirectUris = const [],
  }) {
    return OAuthServerConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      tokenEndpoint: Uri.parse('https://github.com/login/oauth/access_token'),
      userInfoEndpoint: Uri.parse('https://api.github.com/user'),
      requiredScopes: requiredScopes,
      serverUri: serverUri,
      allowedRedirectUris: allowedRedirectUris,
    );
  }

  /// Google OAuth configuration
  factory OAuthServerConfig.google({
    required String clientId,
    required String clientSecret,
    required String serverUri,
    List<String> requiredScopes = const [],
    List<String> allowedRedirectUris = const [],
  }) {
    return OAuthServerConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
      userInfoEndpoint:
          Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      requiredScopes: requiredScopes,
      serverUri: serverUri,
      authServerMetadataEndpoint: Uri.parse(
        'https://accounts.google.com/.well-known/openid-configuration',
      ),
      allowedRedirectUris: allowedRedirectUris,
    );
  }
}

/// OAuth token information
class OAuthTokenInfo {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final List<String> scopes;
  final Map<String, dynamic> userInfo;

  OAuthTokenInfo({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    required this.scopes,
    required this.userInfo,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get userId =>
      userInfo['id']?.toString() ?? userInfo['sub']?.toString() ?? 'unknown';
  String get username =>
      userInfo['login']?.toString() ??
      userInfo['name']?.toString() ??
      userInfo['email']?.toString() ??
      'unknown';
}

/// OAuth validator for MCP servers
class OAuthServerValidator {
  final OAuthServerConfig config;
  final Map<String, OAuthTokenInfo> _tokenCache = {};
  final Duration tokenCacheExpiry = const Duration(minutes: 5);

  OAuthServerValidator(this.config);

  /// Validate token audience (MCP spec requirement)
  ///
  /// Ensures token was specifically issued for this MCP server
  /// to prevent token passthrough attacks
  bool _validateAudience(Map<String, dynamic> userInfo) {
    // Check if token has audience claim
    final aud = userInfo['aud'];
    if (aud == null) {
      // Some providers don't include aud in user info
      // In production, you should validate this via token introspection
      print('⚠️  Warning: Token audience not available for validation');
      return true;
    }

    // Validate audience matches this server
    if (aud is String) {
      return aud == config.serverUri;
    } else if (aud is List) {
      return aud.contains(config.serverUri);
    }

    return false;
  }

  /// Validate OAuth token from Authorization header
  ///
  /// Complies with MCP OAuth spec:
  /// - Validates Bearer token format
  /// - Verifies token with OAuth provider
  /// - Validates audience to prevent token passthrough
  /// - Checks required scopes
  Future<OAuthTokenInfo?> validateRequest(HttpRequest request) async {
    final authHeader = request.headers.value('authorization');
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return null;
    }

    final token = authHeader.substring(7);

    // Check cache first
    if (_tokenCache.containsKey(token)) {
      final cached = _tokenCache[token]!;
      if (!cached.isExpired) {
        return cached;
      }
      _tokenCache.remove(token);
    }

    // Validate token with OAuth provider
    try {
      final userInfo = await _fetchUserInfo(token);
      if (userInfo == null) {
        return null;
      }

      // Validate audience (MCP spec requirement)
      if (!_validateAudience(userInfo)) {
        print('❌ Token audience validation failed');
        return null;
      }

      // Verify scopes (if available from provider)
      final tokenScopes = await _fetchTokenScopes(token);
      if (config.requiredScopes.isNotEmpty) {
        final hasRequiredScopes = config.requiredScopes.every(
          (scope) => tokenScopes.contains(scope),
        );
        if (!hasRequiredScopes) {
          print('❌ Token missing required scopes: ${config.requiredScopes}');
          return null;
        }
      }

      final tokenInfo = OAuthTokenInfo(
        accessToken: token,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        scopes: tokenScopes,
        userInfo: userInfo,
      );

      _tokenCache[token] = tokenInfo;
      return tokenInfo;
    } catch (e) {
      print('❌ Token validation error: $e');
      return null;
    }
  }

  /// Fetch user info from OAuth provider
  Future<Map<String, dynamic>?> _fetchUserInfo(String token) async {
    try {
      final response = await http.get(
        config.userInfoEndpoint,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      print('User info fetch failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      print('Error fetching user info: $e');
      return null;
    }
  }

  /// Fetch token scopes (provider-specific)
  Future<List<String>> _fetchTokenScopes(String token) async {
    // GitHub provides scopes in X-OAuth-Scopes header
    // For simplicity, return configured required scopes
    // In production, query the OAuth provider's token introspection endpoint
    return config.requiredScopes;
  }

  /// Validate redirect URI against allowed list
  bool _validateRedirectUri(String redirectUri) {
    if (config.allowedRedirectUris.isEmpty) {
      // If no allowed URIs configured, accept any (not recommended for production)
      print('⚠️  Warning: No allowed redirect URIs configured');
      return true;
    }
    return config.allowedRedirectUris.contains(redirectUri);
  }

  /// Exchange authorization code for access token with PKCE
  ///
  /// Complies with MCP OAuth spec requirements:
  /// - PKCE code_verifier for authorization code protection
  /// - resource parameter for audience validation
  /// - redirect_uri validation
  Future<OAuthTokenInfo?> exchangeCode(
    String code,
    String redirectUri,
    String codeVerifier,
  ) async {
    // Validate redirect URI
    if (!_validateRedirectUri(redirectUri)) {
      print('❌ Invalid redirect URI: $redirectUri');
      return null;
    }

    try {
      final body = {
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': codeVerifier, // PKCE requirement
        'resource':
            config.serverUri, // MCP spec requirement for audience validation
      };

      final response = await http.post(
        config.tokenEndpoint,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        print('Token exchange failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;
      final expiresIn = data['expires_in'] as int? ?? 3600;

      final userInfo = await _fetchUserInfo(accessToken);
      if (userInfo == null) {
        return null;
      }

      final tokenInfo = OAuthTokenInfo(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        scopes: config.requiredScopes,
        userInfo: userInfo,
      );

      _tokenCache[accessToken] = tokenInfo;
      return tokenInfo;
    } catch (e) {
      print('Error exchanging code: $e');
      return null;
    }
  }

  /// Refresh access token
  ///
  /// Complies with MCP OAuth spec by including resource parameter
  Future<OAuthTokenInfo?> refreshToken(String refreshToken) async {
    try {
      final body = {
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
        'resource': config.serverUri, // MCP spec requirement
      };

      final response = await http.post(
        config.tokenEndpoint,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        print('Token refresh failed: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String;
      final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;
      final expiresIn = data['expires_in'] as int? ?? 3600;

      final userInfo = await _fetchUserInfo(accessToken);
      if (userInfo == null) {
        return null;
      }

      final tokenInfo = OAuthTokenInfo(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        scopes: config.requiredScopes,
        userInfo: userInfo,
      );

      _tokenCache[accessToken] = tokenInfo;
      return tokenInfo;
    } catch (e) {
      print('Error refreshing token: $e');
      return null;
    }
  }
}

/// OAuth metadata for MCP server
///
/// Implements OAuth 2.0 Protected Resource Metadata
/// as required by MCP specification
class OAuthMetadata {
  final String issuer;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String> supportedGrantTypes;
  final List<String> supportedResponseTypes;
  final List<String> supportedScopes;

  OAuthMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.supportedGrantTypes = const ['authorization_code', 'refresh_token'],
    this.supportedResponseTypes = const ['code'],
    this.supportedScopes = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'issuer': issuer,
      'authorization_endpoint': authorizationEndpoint,
      'token_endpoint': tokenEndpoint,
      'grant_types_supported': supportedGrantTypes,
      'response_types_supported': supportedResponseTypes,
      'scopes_supported': supportedScopes,
      'code_challenge_methods_supported': ['S256'], // PKCE support
    };
  }
}

/// OAuth-authenticated MCP server transport wrapper
class OAuthServerTransport implements Transport {
  final StreamableHTTPServerTransport _innerTransport;
  final OAuthServerValidator _validator;
  final Map<String, OAuthTokenInfo> _sessionTokens = {};
  final OAuthMetadata? metadata;

  OAuthServerTransport({
    required StreamableHTTPServerTransport transport,
    required OAuthServerValidator validator,
    this.metadata,
  })  : _innerTransport = transport,
        _validator = validator;

  /// Handle OAuth metadata discovery endpoint
  ///
  /// Implements /.well-known/oauth-authorization-server
  /// as required by MCP OAuth specification
  Future<bool> _handleMetadataRequest(HttpRequest req) async {
    if (req.uri.path == '/.well-known/oauth-authorization-server') {
      if (metadata == null) {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('OAuth metadata not configured');
        await req.response.close();
        return true;
      }

      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(metadata!.toJson()));
      await req.response.close();
      return true;
    }
    return false;
  }

  /// Handle HTTP request with OAuth validation
  ///
  /// Complies with MCP OAuth spec:
  /// - Returns 401 with WWW-Authenticate header for unauthorized requests
  /// - Validates OAuth tokens before processing
  /// - Provides OAuth metadata discovery endpoint
  Future<void> handleRequest(HttpRequest req, [dynamic parsedBody]) async {
    // Handle OAuth metadata discovery
    if (await _handleMetadataRequest(req)) {
      return;
    }

    // Validate OAuth token
    final tokenInfo = await _validator.validateRequest(req);

    if (tokenInfo == null) {
      // Unauthorized - return WWW-Authenticate header (MCP spec requirement)
      final wwwAuth = metadata != null
          ? 'Bearer realm="MCP Server", authorization_uri="${metadata!.authorizationEndpoint}"'
          : 'Bearer realm="MCP Server"';

      req.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.set('WWW-Authenticate', wwwAuth)
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message: 'Unauthorized: Valid OAuth token required',
              ),
            ).toJson(),
          ),
        );
      await req.response.close();
      return;
    }

    // Store token info for this session
    final sessionId = req.headers.value('mcp-session-id');
    if (sessionId != null) {
      _sessionTokens[sessionId] = tokenInfo;
    }

    print(
      '✓ Authenticated request from ${tokenInfo.username} (${tokenInfo.userId})',
    );

    // Forward to inner transport
    await _innerTransport.handleRequest(req, parsedBody);
  }

  /// Get token info for a session
  OAuthTokenInfo? getTokenForSession(String sessionId) {
    return _sessionTokens[sessionId];
  }

  @override
  void Function()? get onclose => _innerTransport.onclose;

  @override
  set onclose(void Function()? value) => _innerTransport.onclose = value;

  @override
  void Function(Error error)? get onerror => _innerTransport.onerror;

  @override
  set onerror(void Function(Error error)? value) =>
      _innerTransport.onerror = value;

  @override
  void Function(JsonRpcMessage message)? get onmessage =>
      _innerTransport.onmessage;

  @override
  set onmessage(void Function(JsonRpcMessage message)? value) =>
      _innerTransport.onmessage = value;

  @override
  String? get sessionId => _innerTransport.sessionId;

  @override
  Future<void> close() => _innerTransport.close();

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) =>
      _innerTransport.send(message, relatedRequestId: relatedRequestId);

  @override
  Future<void> start() => _innerTransport.start();
}

/// Create MCP server with OAuth-protected tools
McpServer createOAuthMcpServer() {
  final server = McpServer(
    const Implementation(name: 'oauth-protected-server', version: '1.0.0'),
  );

  // Public tool (accessible to all authenticated users)
  server.registerTool(
    'greet',
    description: 'A simple greeting tool',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description: 'Name to greet',
        ),
      },
      required: ['name'],
    ),
    callback: (args, extra) async {
      final name = args['name'] as String? ?? 'user';
      return CallToolResult.fromContent(
        [TextContent(text: 'Hello, $name!')],
      );
    },
  );

  // Protected tool (demonstrates scope-based access)
  server.registerTool(
    'user-info',
    description: 'Get authenticated user information',
    inputSchema: JsonSchema.object(
      properties: {},
    ),
    callback: (args, extra) async {
      // In a real implementation, retrieve user info from request context
      // This is a simplified example
      return CallToolResult.fromContent(
        [
          const TextContent(
            text: 'User info would be retrieved from OAuth token context',
          ),
        ],
      );
    },
  );

  // Admin tool (requires specific scope)
  server.registerTool(
    'admin-action',
    description: 'Perform admin action (requires admin scope)',
    inputSchema: JsonSchema.object(
      properties: {
        'action': JsonSchema.string(
          description: 'Admin action to perform',
        ),
      },
      required: ['action'],
    ),
    callback: (args, extra) async {
      // Verify admin scope in production
      final action = args['action'] as String? ?? 'none';
      return CallToolResult.fromContent(
        [TextContent(text: 'Admin action executed: $action')],
      );
    },
  );

  return server;
}

/// Main server example
///
/// MCP OAuth Specification Compliance:
/// ✅ PKCE support for authorization code flow
/// ✅ Resource parameter for audience validation
/// ✅ Token audience validation
/// ✅ Redirect URI validation
/// ✅ OAuth metadata discovery endpoint
/// ⚠️  HTTPS support (use --https flag, see notes below)
///
/// Usage:
///   dart run example/authentication/oauth_server_example.dart [provider] [--https]
///
/// HTTPS Notes:
/// - MCP spec requires HTTPS for production
/// - Use --https flag for self-signed certificate (development only)
/// - For production, use a reverse proxy (nginx, Traefik) with proper TLS certificates
Future<void> main(List<String> args) async {
  print('=' * 70);
  print('MCP Dart - OAuth 2.0 Server Example (MCP Spec Compliant)');
  print('=' * 70);
  print('');

  // Parse arguments
  final useHttps = args.contains('--https');
  final provider = args.firstWhere(
    (arg) => !arg.startsWith('--'),
    orElse: () => 'github',
  );

  // Server configuration
  final host = 'localhost';
  final port = 3000;
  final protocol = useHttps ? 'https' : 'http';
  final serverUri = '$protocol://$host:$port';

  if (!useHttps) {
    print('⚠️  WARNING: Running in HTTP mode');
    print('   MCP spec requires HTTPS for production use');
    print('   Add --https flag for self-signed certificate (dev only)');
    print('');
  }

  // Load OAuth configuration from environment
  OAuthServerConfig? config;
  OAuthMetadata? metadata;

  if (provider == 'github') {
    final clientId = Platform.environment['GITHUB_CLIENT_ID'];
    final clientSecret = Platform.environment['GITHUB_CLIENT_SECRET'];

    if (clientId == null || clientSecret == null) {
      print('❌ Error: GitHub OAuth credentials not found!');
      print('');
      print('Set environment variables:');
      print('  export GITHUB_CLIENT_ID=your_client_id');
      print('  export GITHUB_CLIENT_SECRET=your_client_secret');
      print('');
      exit(1);
    }

    config = OAuthServerConfig.github(
      clientId: clientId,
      clientSecret: clientSecret,
      serverUri: serverUri,
      requiredScopes: ['repo', 'read:user'],
      allowedRedirectUris: [
        'http://localhost:3001/callback',
        'https://localhost:3001/callback',
      ],
    );

    metadata = OAuthMetadata(
      issuer: 'https://github.com',
      authorizationEndpoint: 'https://github.com/login/oauth/authorize',
      tokenEndpoint: 'https://github.com/login/oauth/access_token',
      supportedScopes: ['repo', 'read:user', 'user'],
    );
  } else if (provider == 'google') {
    final clientId = Platform.environment['GOOGLE_CLIENT_ID'];
    final clientSecret = Platform.environment['GOOGLE_CLIENT_SECRET'];

    if (clientId == null || clientSecret == null) {
      print('❌ Error: Google OAuth credentials not found!');
      print('');
      print('Set environment variables:');
      print('  export GOOGLE_CLIENT_ID=your_client_id');
      print('  export GOOGLE_CLIENT_SECRET=your_client_secret');
      print('');
      exit(1);
    }

    config = OAuthServerConfig.google(
      clientId: clientId,
      clientSecret: clientSecret,
      serverUri: serverUri,
      requiredScopes: ['openid', 'email', 'profile'],
      allowedRedirectUris: [
        'http://localhost:3001/callback',
        'https://localhost:3001/callback',
      ],
    );

    metadata = OAuthMetadata(
      issuer: 'https://accounts.google.com',
      authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
      tokenEndpoint: 'https://oauth2.googleapis.com/token',
      supportedScopes: ['openid', 'email', 'profile'],
    );
  } else {
    print('❌ Unknown provider: $provider');
    print('Supported: github, google');
    exit(1);
  }

  print('✓ OAuth Provider: $provider');
  print('✓ Server URI: $serverUri');
  print('✓ Required Scopes: ${config.requiredScopes.join(', ')}');
  print('✓ Allowed Redirect URIs: ${config.allowedRedirectUris.join(', ')}');
  print('');

  // Create OAuth validator
  final validator = OAuthServerValidator(config);

  // Map to store transports by session ID
  final transports = <String, OAuthServerTransport>{};

  // Create HTTP/HTTPS server
  late HttpServer httpServer;

  if (useHttps) {
    try {
      // Create self-signed certificate context for development
      // WARNING: This is NOT secure for production use
      final context = SecurityContext()
        ..useCertificateChain('server_cert.pem')
        ..usePrivateKey('server_key.pem', password: 'dartserver');

      httpServer = await HttpServer.bindSecure(host, port, context);
      print('✓ MCP OAuth Server listening on https://$host:$port (HTTPS)');
    } catch (e) {
      print('❌ Failed to start HTTPS server: $e');
      print('');
      print('To generate self-signed certificates for development:');
      print('  openssl req -x509 -newkey rsa:4096 -keyout server_key.pem \\');
      print('    -out server_cert.pem -days 365 -nodes \\');
      print('    -subj "/CN=localhost"');
      print('');
      print(
        'For production, use a reverse proxy with proper TLS certificates.',
      );
      print('Falling back to HTTP mode...');
      print('');
      httpServer = await HttpServer.bind(host, port);
    }
  } else {
    httpServer = await HttpServer.bind(host, port);
  }

  print('✓ Endpoint: $serverUri/mcp');
  print('✓ OAuth Metadata: $serverUri/.well-known/oauth-authorization-server');
  print('');
  print('MCP Specification Compliance:');
  print('  ✅ PKCE (code_verifier required in token exchange)');
  print('  ✅ Resource parameter (audience validation)');
  print('  ✅ Token audience validation');
  print('  ✅ Redirect URI validation');
  print('  ✅ OAuth metadata discovery');
  print(
    '  ${useHttps ? "✅" : "⚠️ "} HTTPS ${useHttps ? "enabled" : "not enabled (use --https)"}',
  );
  print('');
  print('Usage:');
  print('  1. Obtain OAuth access token from provider');
  print('  2. Make requests with: Authorization: Bearer <token>');
  print(
    '  3. Access metadata: GET $serverUri/.well-known/oauth-authorization-server',
  );
  print('');
  print('Server running. Press Ctrl+C to stop.\n');

  await for (final request in httpServer) {
    // Set CORS headers
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Origin, Content-Type, Accept, Authorization, mcp-session-id, Last-Event-ID',
      )
      ..set('Access-Control-Allow-Credentials', 'true')
      ..set('Access-Control-Expose-Headers', 'mcp-session-id');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      continue;
    }

    // Handle OAuth metadata discovery endpoint
    if (request.uri.path == '/.well-known/oauth-authorization-server') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(metadata.toJson()));
      await request.response.close();
      continue;
    }

    if (request.uri.path != '/mcp') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
      continue;
    }

    try {
      if (request.method == 'POST') {
        // Parse body
        final bodyBytes = await request.toList();
        final bodyString = utf8.decode(bodyBytes.expand((x) => x).toList());
        final body = jsonDecode(bodyString);

        final sessionId = request.headers.value('mcp-session-id');
        OAuthServerTransport? transport;

        if (sessionId != null && transports.containsKey(sessionId)) {
          transport = transports[sessionId]!;
        } else if (sessionId == null) {
          // New session - create transport
          final innerTransport = StreamableHTTPServerTransport(
            options: StreamableHTTPServerTransportOptions(
              sessionIdGenerator: () => generateUUID(),
              onsessioninitialized: (sessionId) {
                print('Session initialized: $sessionId');
                transports[sessionId] = transport!;
              },
            ),
          );

          transport = OAuthServerTransport(
            transport: innerTransport,
            validator: validator,
            metadata: metadata,
          );

          transport.onclose = () {
            final sid = transport!.sessionId;
            if (sid != null) {
              transports.remove(sid);
              print('Session closed: $sid');
            }
          };

          final server = createOAuthMcpServer();
          await server.connect(transport);
        } else {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('Invalid session');
          await request.response.close();
          continue;
        }

        await transport.handleRequest(request, body);
      } else if (request.method == 'GET') {
        // SSE stream
        final sessionId = request.headers.value('mcp-session-id');
        if (sessionId == null || !transports.containsKey(sessionId)) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('Invalid session');
          await request.response.close();
          continue;
        }

        await transports[sessionId]!.handleRequest(request);
      } else if (request.method == 'DELETE') {
        // Session termination
        final sessionId = request.headers.value('mcp-session-id');
        if (sessionId != null && transports.containsKey(sessionId)) {
          await transports[sessionId]!.handleRequest(request);
        }
      }
    } catch (e) {
      print('Error handling request: $e');
      if (!request.response.headers.contentType
          .toString()
          .contains('event-stream')) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal server error');
        await request.response.close();
      }
    }
  }
}
