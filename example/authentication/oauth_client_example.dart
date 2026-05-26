/// Example demonstrating OAuth 2.0 authentication with MCP Dart SDK
///
/// **COMPLIES WITH MCP OAUTH SPECIFICATION (2025-11-25)**
///
/// This example shows how to implement a complete OAuth flow for authenticating
/// with an MCP server that requires OAuth 2.0 authorization.
///
/// ## MCP Specification Compliance
///
/// ✅ **PKCE Support** - Generates code_verifier and code_challenge
/// ✅ **Resource Parameter** - Includes resource parameter in authorization and token requests
/// ✅ **Proper Authorization** - Uses body parameters (not Basic Auth header)
///
/// Compatible with [oauth_server_example.dart](oauth_server_example.dart)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';

/// OAuth configuration for the MCP server
class OAuthConfig {
  final String clientId;
  final String clientSecret;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final List<String> scopes;
  final Uri redirectUri;

  /// MCP server URI for resource parameter (audience validation)
  final String serverUri;

  const OAuthConfig({
    required this.clientId,
    required this.clientSecret,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
    required this.redirectUri,
    required this.serverUri,
  });
}

/// Prepared OAuth authorization request with PKCE state.
class OAuthAuthorizationRequest {
  final Uri authorizationUri;
  final String codeVerifier;
  final String codeChallenge;
  final String state;

  const OAuthAuthorizationRequest({
    required this.authorizationUri,
    required this.codeVerifier,
    required this.codeChallenge,
    required this.state,
  });
}

/// Implementation of OAuthClientProvider for OAuth 2.0 flow
/// Complies with MCP OAuth specification
class OAuth2Provider implements OAuthClientProvider {
  final OAuthConfig config;
  final TokenStorage storage;
  final Random _random;

  OAuth2Provider({
    required this.config,
    required this.storage,
    Random? random,
  }) : _random = random ?? Random.secure();

  @override
  Future<OAuthTokens?> tokens() async {
    // Try to load tokens from storage
    final storedTokens = await storage.loadTokens();
    if (storedTokens == null) {
      return null;
    }

    // Check if token is expired and refresh if needed
    if (storedTokens.isExpired) {
      if (storedTokens.refreshToken != null) {
        return await _refreshToken(storedTokens.refreshToken!);
      }
      // Token expired and no refresh token available
      await storage.clearTokens();
      return null;
    }

    return storedTokens;
  }

  /// Generate PKCE code verifier (RFC 7636)
  /// Uses a cryptographically secure random string
  String _generateCodeVerifier() {
    return _base64UrlNoPadding(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
  }

  /// Generate PKCE code challenge from verifier (S256 method)
  String _generateCodeChallenge(String verifier) {
    final digest = crypto.sha256.convert(utf8.encode(verifier));
    return _base64UrlNoPadding(digest.bytes);
  }

  /// Builds and stores a PKCE S256 authorization request.
  Future<OAuthAuthorizationRequest> createAuthorizationRequest() async {
    // Generate PKCE parameters (MCP spec requirement)
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    // Save PKCE verifier for token exchange
    await storage.saveCodeVerifier(codeVerifier);

    // Generate authorization URL with PKCE
    final state = _generateRandomState();
    await storage.saveState(state);

    final authUrl = config.authorizationEndpoint.replace(
      queryParameters: {
        ...config.authorizationEndpoint.queryParameters,
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': config.redirectUri.toString(),
        'scope': config.scopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge, // PKCE parameter
        'code_challenge_method': 'S256',
        'resource': config.serverUri, // MCP spec requirement
      },
    );

    return OAuthAuthorizationRequest(
      authorizationUri: authUrl,
      codeVerifier: codeVerifier,
      codeChallenge: codeChallenge,
      state: state,
    );
  }

  @override
  Future<void> redirectToAuthorization() async {
    final authRequest = await createAuthorizationRequest();

    print('\n${'=' * 60}');
    print('AUTHORIZATION REQUIRED (MCP OAuth Spec Compliant)');
    print('=' * 60);
    print('\nPKCE Code Verifier: ${authRequest.codeVerifier}');
    print('PKCE Code Challenge: ${authRequest.codeChallenge}\n');
    print('Please open the following URL in your browser:\n');
    print(authRequest.authorizationUri.toString());
    print('\nAfter authorization, you will be redirected to:');
    print(
      '${config.redirectUri}?code=AUTHORIZATION_CODE&state=${authRequest.state}\n',
    );
    print('=' * 60 + '\n');

    // In a real application, you would:
    // - Open the URL in the system browser
    // - Set up a local HTTP server to receive the callback
    // - Extract the authorization code from the callback
  }

  /// Refreshes an expired access token using the refresh token
  /// Complies with MCP spec by including resource parameter
  Future<OAuthTokens?> _refreshToken(String refreshToken) async {
    try {
      final body = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'resource': config.serverUri, // MCP spec requirement
      };

      final response = await http.post(
        config.tokenEndpoint,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tokens = StoredOAuthTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'] ?? refreshToken,
          expiresAt: DateTime.now().add(
            Duration(seconds: data['expires_in'] ?? 3600),
          ),
        );
        await storage.saveTokens(tokens);
        return tokens;
      }

      return null;
    } catch (e) {
      print('Failed to refresh token: $e');
      return null;
    }
  }

  /// Exchanges authorization code for access token with PKCE
  /// Complies with MCP OAuth spec requirements:
  /// - PKCE code_verifier parameter
  /// - resource parameter for audience validation
  Future<StoredOAuthTokens?> exchangeCodeForTokens(String code) async {
    try {
      // Retrieve stored code verifier
      final codeVerifier = await storage.getCodeVerifier();
      if (codeVerifier == null) {
        throw Exception(
          'Code verifier not found. Complete authorization flow first.',
        );
      }

      final body = {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri.toString(),
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'code_verifier': codeVerifier, // PKCE requirement
        'resource': config.serverUri, // MCP spec requirement
      };

      final response = await http.post(
        config.tokenEndpoint,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tokens = StoredOAuthTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiresAt: DateTime.now().add(
            Duration(seconds: data['expires_in'] ?? 3600),
          ),
        );
        await storage.saveTokens(tokens);

        // Clear PKCE verifier after successful exchange
        await storage.clearCodeVerifier();

        return tokens;
      }

      throw Exception('Failed to exchange code: ${response.statusCode}');
    } catch (e) {
      print('Failed to exchange authorization code: $e');
      return null;
    }
  }

  String _generateRandomState() {
    return _base64UrlNoPadding(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
  }

  String _base64UrlNoPadding(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// Extended OAuthTokens with expiration tracking
class StoredOAuthTokens extends OAuthTokens {
  final DateTime? expiresAt;

  StoredOAuthTokens({
    required super.accessToken,
    super.refreshToken,
    this.expiresAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt?.toIso8601String(),
      };

  factory StoredOAuthTokens.fromJson(Map<String, dynamic> json) {
    return StoredOAuthTokens(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
    );
  }
}

/// Simple file-based token storage with PKCE support
/// In production, use secure storage (keychain, encrypted storage, etc.)
class TokenStorage {
  final String filePath;
  String? _state;
  String? _codeVerifier;

  TokenStorage(this.filePath);

  Future<StoredOAuthTokens?> loadTokens() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content);
      return StoredOAuthTokens.fromJson(json);
    } catch (e) {
      print('Failed to load tokens: $e');
      return null;
    }
  }

  Future<void> saveTokens(StoredOAuthTokens tokens) async {
    try {
      final file = File(filePath);
      await file.writeAsString(jsonEncode(tokens.toJson()));
    } catch (e) {
      print('Failed to save tokens: $e');
    }
  }

  Future<void> clearTokens() async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Failed to clear tokens: $e');
    }
  }

  Future<void> saveState(String state) async {
    _state = state;
  }

  Future<String?> getState() async {
    return _state;
  }

  /// Save PKCE code verifier for token exchange
  Future<void> saveCodeVerifier(String codeVerifier) async {
    _codeVerifier = codeVerifier;
  }

  /// Retrieve PKCE code verifier
  Future<String?> getCodeVerifier() async {
    return _codeVerifier;
  }

  /// Clear PKCE code verifier after use
  Future<void> clearCodeVerifier() async {
    _codeVerifier = null;
  }
}

/// Main example demonstrating MCP-compliant OAuth authentication
/// Compatible with oauth_server_example.dart
Future<void> main(List<String> args) async {
  // Configuration for MCP server with OAuth
  // This example is configured for the oauth_server_example.dart
  final config = OAuthConfig(
    clientId: 'your-client-id',
    clientSecret: 'your-client-secret',
    authorizationEndpoint: Uri.parse('https://auth.example.com/authorize'),
    tokenEndpoint: Uri.parse('https://auth.example.com/token'),
    scopes: ['mcp.read', 'mcp.write'],
    redirectUri: Uri.parse('http://localhost:8080/callback'),
    serverUri: 'http://localhost:3000', // MCP server URI for resource parameter
  );

  // Set up token storage
  final storage = TokenStorage('.oauth_tokens.json');

  // Create OAuth provider
  final authProvider = OAuth2Provider(config: config, storage: storage);

  // Create MCP client
  final client = McpClient(
    const Implementation(name: 'oauth-example-client', version: '1.0.0'),
  );

  try {
    // Create transport with authentication
    final transport = StreamableHttpClientTransport(
      Uri.parse('https://api.example.com/mcp'),
      opts: StreamableHttpClientTransportOptions(
        authProvider: authProvider,
      ),
    );

    print('Connecting to MCP server with OAuth authentication...\n');

    // Connect to the server
    // If no tokens are available, this will trigger the authorization flow
    await client.connect(transport);

    print('✓ Successfully connected to MCP server!');
    print('Server: ${client.getServerVersion()?.name}');
    print('Protocol: ${client.getServerCapabilities()}\n');

    // Example: List available tools
    final tools = await client.listTools();
    print('Available tools: ${tools.tools.length}');
    for (final tool in tools.tools) {
      print('  - ${tool.name}: ${tool.description}');
    }

    // Keep the connection alive
    await Future.delayed(const Duration(seconds: 5));

    await client.close();
  } catch (e) {
    if (e is UnauthorizedError) {
      print('\n⚠ Authorization required!');
      print('Please complete the OAuth flow and run the following command:');
      print('dart run example/authentication/oauth_finish_auth.dart <CODE>\n');
    } else {
      print('Error: $e');
    }
  }
}

/// Helper function to finish OAuth flow after receiving authorization code
/// This would typically be in a separate callback handler
Future<void> finishOAuthFlow(
  StreamableHttpClientTransport transport,
  OAuth2Provider authProvider,
  String authorizationCode,
) async {
  // Exchange authorization code for tokens
  final tokens = await authProvider.exchangeCodeForTokens(authorizationCode);
  if (tokens != null) {
    // Complete the auth flow with the transport
    await transport.finishAuth(authorizationCode);
    print('✓ Authentication completed successfully!');
  } else {
    print('✗ Failed to exchange authorization code');
  }
}
