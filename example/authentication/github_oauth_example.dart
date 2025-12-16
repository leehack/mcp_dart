/// Example: Connecting to GitHub MCP Server with OAuth
///
/// This example demonstrates how to authenticate with GitHub's MCP server
/// using OAuth 2.0 authentication flow.
///
/// Setup:
/// 1. Create a GitHub OAuth App at https://github.com/settings/developers
/// 2. Set callback URL to http://localhost:8080/callback
/// 3. Copy Client ID and Client Secret
/// 4. Set environment variables or use .env file
///
/// Run:
/// dart run example/authentication/github_oauth_example.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';

/// GitHub OAuth configuration
class GitHubOAuthConfig {
  final String clientId;
  final String clientSecret;
  final List<String> scopes;
  final int callbackPort;

  const GitHubOAuthConfig({
    required this.clientId,
    required this.clientSecret,
    required this.scopes,
    this.callbackPort = 8090,
  });

  Uri get authorizationEndpoint =>
      Uri.parse('https://github.com/login/oauth/authorize');

  Uri get tokenEndpoint =>
      Uri.parse('https://github.com/login/oauth/access_token');

  Uri get callbackUri => Uri.parse('http://localhost:$callbackPort/callback');

  /// Recommended scopes for GitHub MCP server
  static const recommendedScopes = [
    'repo', // Repository operations
    'read:packages', // Docker image access
    'read:org', // Organization team access
  ];
}

/// GitHub OAuth tokens with expiration tracking
class GitHubOAuthTokens extends OAuthTokens {
  final DateTime issuedAt;
  final String tokenType;
  final List<String> scope;

  GitHubOAuthTokens({
    required super.accessToken,
    super.refreshToken,
    required this.tokenType,
    required this.scope,
  }) : issuedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'token_type': tokenType,
        'scope': scope.join(' '),
        'issued_at': issuedAt.toIso8601String(),
      };

  factory GitHubOAuthTokens.fromJson(Map<String, dynamic> json) {
    return GitHubOAuthTokens(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      tokenType: json['token_type'] ?? 'bearer',
      scope: (json['scope'] as String?)?.split(' ') ?? [],
    );
  }
}

/// GitHub OAuth provider with device flow support
class GitHubOAuthProvider implements OAuthClientProvider {
  final GitHubOAuthConfig config;
  final GitHubTokenStorage storage;
  HttpServer? _callbackServer;
  Completer<String>? _authorizationCodeCompleter;

  GitHubOAuthProvider({
    required this.config,
    required this.storage,
  });

  @override
  Future<OAuthTokens?> tokens() async {
    final storedTokens = await storage.loadTokens();
    return storedTokens;
  }

  @override
  Future<void> redirectToAuthorization() async {
    // Generate state for CSRF protection
    final state = _generateState();
    await storage.saveState(state);

    // Build authorization URL
    final authUrl = Uri(
      scheme: config.authorizationEndpoint.scheme,
      host: config.authorizationEndpoint.host,
      path: config.authorizationEndpoint.path,
      queryParameters: {
        'client_id': config.clientId,
        'redirect_uri': config.callbackUri.toString(),
        'scope': config.scopes.join(' '),
        'state': state,
      },
    );

    print('\n${'=' * 70}');
    print('GitHub OAuth Authorization');
    print('=' * 70);
    print('\nPlease authorize this application in your browser:');
    print('\n${authUrl.toString()}\n');
    print('Waiting for authorization callback on ${config.callbackUri}...\n');

    // Start local server to receive callback
    await _startCallbackServer();

    // Open browser (platform-specific)
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [authUrl.toString()]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [authUrl.toString()]);
      } else if (Platform.isWindows) {
        await Process.run('start', [authUrl.toString()], runInShell: true);
      } else {
        print('Please manually open the URL above in your browser.');
      }
    } catch (e) {
      print('Could not automatically open browser: $e');
      print('Please manually open the URL above.');
    }
  }

  /// Start local HTTP server to receive OAuth callback
  Future<void> _startCallbackServer() async {
    _authorizationCodeCompleter = Completer<String>();

    _callbackServer = await HttpServer.bind('localhost', config.callbackPort);

    _callbackServer!.listen((request) async {
      if (request.uri.path == '/callback') {
        await _handleCallback(request);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found');
        await request.response.close();
      }
    });
  }

  /// Handle OAuth callback
  Future<void> _handleCallback(HttpRequest request) async {
    final code = request.uri.queryParameters['code'];
    final state = request.uri.queryParameters['state'];
    final error = request.uri.queryParameters['error'];

    // Send response to browser
    request.response.headers.contentType = ContentType.html;

    if (error != null) {
      request.response.write('''
        <!DOCTYPE html>
        <html>
        <head><title>Authorization Failed</title></head>
        <body>
          <h1>❌ Authorization Failed</h1>
          <p>Error: $error</p>
          <p>You can close this window.</p>
        </body>
        </html>
      ''');
      await request.response.close();
      _authorizationCodeCompleter?.completeError(
        Exception('Authorization failed: $error'),
      );
      await _callbackServer?.close();
      return;
    }

    // Validate state
    final expectedState = await storage.getState();
    if (state != expectedState) {
      request.response.write('''
        <!DOCTYPE html>
        <html>
        <head><title>Security Error</title></head>
        <body>
          <h1>⚠️ Security Error</h1>
          <p>Invalid state parameter. Possible CSRF attack.</p>
          <p>You can close this window.</p>
        </body>
        </html>
      ''');
      await request.response.close();
      _authorizationCodeCompleter?.completeError(
        Exception('Invalid state parameter'),
      );
      await _callbackServer?.close();
      return;
    }

    if (code != null) {
      request.response.write('''
        <!DOCTYPE html>
        <html>
        <head><title>Authorization Successful</title></head>
        <body>
          <h1>✅ Authorization Successful!</h1>
          <p>You have successfully authorized the application.</p>
          <p>You can close this window and return to the terminal.</p>
          <script>window.close();</script>
        </body>
        </html>
      ''');
      await request.response.close();
      _authorizationCodeCompleter?.complete(code);
    }

    await _callbackServer?.close();
    _callbackServer = null;
  }

  /// Exchange authorization code for access token
  Future<GitHubOAuthTokens> exchangeCode(String code) async {
    try {
      final response = await http.post(
        config.tokenEndpoint,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': config.clientId,
          'client_secret': config.clientSecret,
          'code': code,
          'redirect_uri': config.callbackUri.toString(),
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Token exchange failed: ${response.body}');
      }

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw Exception('Token exchange error: ${data['error_description']}');
      }

      final tokens = GitHubOAuthTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
        tokenType: data['token_type'] ?? 'bearer',
        scope: (data['scope'] as String?)?.split(',') ?? config.scopes,
      );

      await storage.saveTokens(tokens);
      return tokens;
    } catch (e) {
      throw Exception('Failed to exchange authorization code: $e');
    }
  }

  /// Wait for authorization and exchange code
  Future<GitHubOAuthTokens> waitForAuthorization() async {
    if (_authorizationCodeCompleter == null) {
      throw StateError('No authorization in progress');
    }

    try {
      final code = await _authorizationCodeCompleter!.future;
      return await exchangeCode(code);
    } finally {
      _authorizationCodeCompleter = null;
    }
  }

  String _generateState() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return base64UrlEncode(utf8.encode(random)).replaceAll('=', '');
  }

  Future<void> cleanup() async {
    await _callbackServer?.close();
    _callbackServer = null;
    _authorizationCodeCompleter = null;
  }
}

/// Token storage for GitHub OAuth tokens
class GitHubTokenStorage {
  final String filePath;
  String? _state;

  GitHubTokenStorage(this.filePath);

  Future<GitHubOAuthTokens?> loadTokens() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content);
      return GitHubOAuthTokens.fromJson(json);
    } catch (e) {
      print('Failed to load tokens: $e');
      return null;
    }
  }

  Future<void> saveTokens(GitHubOAuthTokens tokens) async {
    try {
      final file = File(filePath);
      await file.writeAsString(jsonEncode(tokens.toJson()));
      print('✓ Tokens saved to $filePath');
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
}

/// Main example
Future<void> main(List<String> args) async {
  print('=' * 70);
  print('GitHub MCP Server - OAuth Authentication Example');
  print('=' * 70);
  print('');

  // Load configuration from environment or use provided values
  final clientId = Platform.environment['GITHUB_CLIENT_ID'];
  final clientSecret = Platform.environment['GITHUB_CLIENT_SECRET'];

  if (clientId == null || clientSecret == null) {
    print('Error: GitHub OAuth credentials not found!');
    print('');
    print('Please set the following environment variables:');
    print('  export GITHUB_CLIENT_ID=your_client_id');
    print('  export GITHUB_CLIENT_SECRET=your_client_secret');
    print('');
    print('To create a GitHub OAuth App:');
    print('  1. Go to https://github.com/settings/developers');
    print('  2. Click "New OAuth App"');
    print('  3. Set callback URL to: http://localhost:8090/callback');
    print('  4. Copy the Client ID and Client Secret');
    print('');
    exit(1);
  }

  final config = GitHubOAuthConfig(
    clientId: clientId,
    clientSecret: clientSecret,
    scopes: GitHubOAuthConfig.recommendedScopes,
    callbackPort: 8090,
  );

  final storage = GitHubTokenStorage('.github_oauth_tokens.json');
  final authProvider = GitHubOAuthProvider(
    config: config,
    storage: storage,
  );

  // Create MCP client
  final client = Client(
    const Implementation(name: 'github-mcp-dart-client', version: '1.0.0'),
  );

  try {
    print('Connecting to GitHub MCP server...\n');

    // Create transport with OAuth authentication
    final transport = StreamableHttpClientTransport(
      Uri.parse('https://api.githubcopilot.com/mcp/'),
      opts: StreamableHttpClientTransportOptions(
        authProvider: authProvider,
      ),
    );

    // Check if we have existing tokens
    final existingTokens = await storage.loadTokens();
    if (existingTokens == null) {
      print('No existing tokens found. Starting OAuth flow...\n');
      await authProvider.redirectToAuthorization();

      print('Waiting for authorization...');
      final tokens = await authProvider.waitForAuthorization();
      print('\n✓ Authorization successful!');
      print('  Access token: ${tokens.accessToken.substring(0, 20)}...');
      print('  Scopes: ${tokens.scope.join(', ')}\n');
    } else {
      print('✓ Using existing tokens from storage\n');
    }

    // Connect to GitHub MCP server
    await client.connect(transport);

    print('✓ Connected to GitHub MCP server!');
    print('  Server: ${client.getServerVersion()?.name}');
    print('  Version: ${client.getServerVersion()?.version}\n');

    // List available tools
    print('Fetching available tools...');
    final tools = await client.listTools();
    print('✓ Found ${tools.tools.length} tools:\n');

    for (final tool in tools.tools) {
      print('  📦 ${tool.name}');
      if (tool.description != null) {
        print('     ${tool.description}');
      }
    }

    print('\n${'=' * 70}');
    print('Connection successful! You can now use the GitHub MCP server.');
    print('=' * 70);

    // Cleanup
    await authProvider.cleanup();
    await client.close();
  } catch (e) {
    print('\n✗ Error: $e');
    await authProvider.cleanup();
    exit(1);
  }
}
