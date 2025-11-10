# MCP Dart SDK - OAuth Authentication Examples

This directory contains comprehensive OAuth 2.0 authentication examples for the MCP Dart SDK, with a focus on real-world GitHub integration.

## Overview

The MCP Dart SDK provides flexible OAuth 2.0 authentication support through the `OAuthClientProvider` interface for clients and OAuth validation for servers. These examples demonstrate production-ready OAuth implementations.

## Available Examples

### 🌟 Real-World Example: GitHub MCP Server

#### GitHub OAuth Integration

**Files**: [`github_oauth_example.dart`](github_oauth_example.dart) | [Setup Guide](GITHUB_SETUP.md)

Production-ready example connecting to GitHub's official MCP server with OAuth:

- Complete OAuth 2.0 flow with GitHub
- Automatic browser-based authorization
- Local callback server for OAuth redirect
- Token persistence and reuse
- CSRF protection with state validation
- Works with GitHub's official MCP server

```dart
final config = GitHubOAuthConfig(
  clientId: Platform.environment['GITHUB_CLIENT_ID']!,
  clientSecret: Platform.environment['GITHUB_CLIENT_SECRET']!,
  scopes: GitHubOAuthConfig.recommendedScopes,
);

final authProvider = GitHubOAuthProvider(
  config: config,
  storage: GitHubTokenStorage('.github_oauth_tokens.json'),
);

final transport = StreamableHttpClientTransport(
  Uri.parse('https://api.githubcopilot.com/mcp/'),
  opts: StreamableHttpClientTransportOptions(
    authProvider: authProvider,
  ),
);

await client.connect(transport);
```

**Setup & Run**:
See the complete [GitHub Setup Guide](GITHUB_SETUP.md) for step-by-step instructions.

```bash
# Set credentials
export GITHUB_CLIENT_ID=your_client_id
export GITHUB_CLIENT_SECRET=your_client_secret

# Run example
dart run example/authentication/github_oauth_example.dart
```

---

#### GitHub Personal Access Token (PAT)

**File**: [`github_pat_example.dart`](github_pat_example.dart)

Simpler authentication using GitHub Personal Access Tokens:

- Quick setup without OAuth app registration
- Direct token-based authentication
- Suitable for development and personal use
- Same functionality as OAuth flow

```dart
final authProvider = GitHubPATProvider(
  token: Platform.environment['GITHUB_TOKEN']!,
);

final transport = StreamableHttpClientTransport(
  Uri.parse('https://api.githubcopilot.com/mcp/'),
  opts: StreamableHttpClientTransportOptions(
    authProvider: authProvider,
  ),
);
```

**Setup & Run**:

```bash
# Create a GitHub Personal Access Token at:
# https://github.com/settings/tokens

# Set token
export GITHUB_TOKEN=your_personal_access_token

# Run example
dart run example/authentication/github_pat_example.dart
```

---

### OAuth 2.0 Client

#### Generic OAuth Client

**File**: [`oauth_client_example.dart`](oauth_client_example.dart)

**✅ COMPLIANT with MCP OAuth Specification (2025-06-18)**

Complete OAuth 2.0 authorization code flow implementation:

**MCP Specification Compliance:**

- ✅ PKCE Support - Generates code_verifier and code_challenge
- ✅ Resource Parameter - Includes resource parameter in token requests
- ✅ Proper Authorization - Uses body parameters (OAuth standard)

**Features:**

- Authorization URL generation with PKCE
- Token exchange and storage
- Automatic token refresh with resource parameter
- Secure token management

```dart
final authProvider = OAuth2Provider(
  config: OAuthConfig(
    clientId: 'your-client-id',
    clientSecret: 'your-client-secret',
    authorizationEndpoint: Uri.parse('https://auth.example.com/authorize'),
    tokenEndpoint: Uri.parse('https://auth.example.com/token'),
    scopes: ['mcp.read', 'mcp.write'],
    redirectUri: Uri.parse('http://localhost:8080/callback'),
    serverUri: 'http://localhost:3000', // MCP server URI for resource parameter
  ),
  storage: TokenStorage('.oauth_tokens.json'),
);

final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: StreamableHttpClientTransportOptions(
    authProvider: authProvider,
  ),
);
```

**Key Features**:

- Full OAuth 2.0 flow with PKCE (RFC 7636)
- Resource parameter for audience validation
- Token expiration tracking
- Automatic refresh using refresh tokens
- Persistent token storage
- Authorization callback handling
- Compatible with oauth_server_example.dart

**Note**: The example uses PKCE "plain" method for simplicity. For production, add the `crypto` package to `pubspec.yaml` and use S256 method for better security.

**Run Example**:

```bash
dart run example/authentication/oauth_client_example.dart
```

---

### OAuth 2.0 Server

#### OAuth Server

**File**: [`oauth_server_example.dart`](oauth_server_example.dart)

**✅ FULLY COMPLIANT with MCP OAuth Specification (2025-06-18)**

Production-ready MCP server with OAuth 2.0 authentication that meets all MCP security requirements:

**MCP Specification Compliance:**

- ✅ PKCE Support (RFC 7636) - Requires code_verifier in authorization code exchange
- ✅ Resource Parameter - Includes resource parameter in all token requests for audience validation
- ✅ Token Audience Validation - Validates tokens are specific to this MCP server
- ✅ Redirect URI Validation - Validates redirect URIs against allowed list
- ✅ OAuth Metadata Discovery - Implements /.well-known/oauth-authorization-server endpoint
- ✅ WWW-Authenticate Header - Returns proper 401 responses with authorization server location
- ⚠️ HTTPS Support - Optional HTTPS with self-signed cert (use reverse proxy for production)

**Additional Features:**

- OAuth token validation with provider APIs
- Multi-provider support (GitHub, Google, custom)
- Authorization code exchange with PKCE
- Token refresh handling
- Scope-based access control
- Session management with OAuth tokens
- User context in tool handlers

```dart
// Create OAuth configuration
final config = OAuthServerConfig.github(
  clientId: Platform.environment['GITHUB_CLIENT_ID']!,
  clientSecret: Platform.environment['GITHUB_CLIENT_SECRET']!,
  requiredScopes: ['repo', 'read:user'],
);

// Create OAuth validator
final validator = OAuthServerValidator(config);

// Wrap transport with OAuth authentication
final authenticatedTransport = OAuthServerTransport(
  transport: innerTransport,
  validator: validator,
);

// Create server
final server = createOAuthMcpServer();
await server.connect(authenticatedTransport);
```

**Key Features**:

- Real OAuth provider integration (GitHub, Google)
- Token validation with user info lookup
- Scope verification and access control
- Token caching with TTL
- Session-token association
- User context in request handlers
- Production security best practices

**Run Example**:

```bash
# GitHub OAuth (HTTP mode - development only)
export GITHUB_CLIENT_ID=your_client_id
export GITHUB_CLIENT_SECRET=your_client_secret
dart run example/authentication/oauth_server_example.dart github

# GitHub OAuth (HTTPS mode with self-signed certificate)
dart run example/authentication/oauth_server_example.dart github --https

# Google OAuth
export GOOGLE_CLIENT_ID=your_client_id
export GOOGLE_CLIENT_SECRET=your_client_secret
dart run example/authentication/oauth_server_example.dart google
```

**Test MCP Compliance:**

```bash
# 1. Check OAuth metadata discovery
curl http://localhost:3000/.well-known/oauth-authorization-server | jq

# 2. Verify WWW-Authenticate header on unauthorized request
curl -v http://localhost:3000/mcp 2>&1 | grep "WWW-Authenticate"

# 3. Test with valid OAuth token (requires actual token from provider)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  http://localhost:3000/mcp
```

---

## Quick Start

### Client Authentication

1. **Choose your OAuth provider** (GitHub, Google, or custom)
2. **Implement the `OAuthClientProvider` interface**
3. **Configure your transport with the auth provider**
4. **Connect and use the MCP client**

```dart
// 1. Create auth provider
final authProvider = GitHubOAuthProvider(
  config: config,
  storage: GitHubTokenStorage('.tokens.json'),
);

// 2. Create transport with auth
final transport = StreamableHttpClientTransport(
  Uri.parse('https://api.githubcopilot.com/mcp/'),
  opts: StreamableHttpClientTransportOptions(
    authProvider: authProvider,
  ),
);

// 3. Create and connect client
final client = Client(
  Implementation(name: 'my-client', version: '1.0.0'),
);

await client.connect(transport);

// 4. Use the client
final tools = await client.listTools();
```

### Server Authentication

1. **Create your base server transport**
2. **Configure OAuth validator with provider settings**
3. **Wrap the transport with OAuth authentication**
4. **Handle requests through the authenticated transport**

```dart
// 1. Create base transport
final innerTransport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
  ),
);

// 2. Create OAuth validator
final validator = OAuthServerValidator(
  OAuthServerConfig.github(
    clientId: githubClientId,
    clientSecret: githubClientSecret,
    requiredScopes: ['repo', 'read:user'],
  ),
);

// 3. Wrap with OAuth authentication
final authenticatedTransport = OAuthServerTransport(
  transport: innerTransport,
  validator: validator,
);

// 4. Create server and handle requests
final server = Server(
  Implementation(name: 'secure-server', version: '1.0.0'),
);

await authenticatedTransport.start();
await server.connect(authenticatedTransport);

// Handle HTTP requests
httpServer.listen((request) async {
  await authenticatedTransport.handleRequest(request);
});
```

---

## OAuth 2.0 Flow

```
Client                    Auth Server              MCP Server
  |                           |                        |
  |--Request Access---------->|                        |
  |<--Authorization URL-------|                        |
  |                           |                        |
  |--User Authorizes--------->|                        |
  |<--Authorization Code------|                        |
  |                           |                        |
  |--Exchange Code + PKCE---->|                        |
  |<--Access + Refresh--------|                        |
  |                                                    |
  |--Connect with Token---------------------------->  |
  |<--Session Established---------------------------  |
  |                                                    |
  |--Token Expired--------------------------------->  |
  |<--Refresh Token---------------------------------  |
```

---

## Security Best Practices

### Token Storage

- **Never hardcode** tokens or secrets in your code
- Use **environment variables** for development
- Implement **secure storage** (system keychain, encrypted storage) for production
- **Clear tokens** on logout or session end

```dart
// ❌ Bad - hardcoded
final authProvider = GitHubPATProvider(token: 'ghp_xxxxx');

// ✅ Good - from environment
final authProvider = GitHubPATProvider(
  token: Platform.environment['GITHUB_TOKEN']!,
);

// ✅ Better - from secure storage
final token = await secureStorage.read(key: 'github_token');
final authProvider = GitHubPATProvider(token: token);
```

### Token Expiration

- **Track expiration** times for all tokens
- **Refresh proactively** before expiration
- **Handle refresh failures** gracefully
- Implement **exponential backoff** for retries

```dart
class SmartOAuthProvider implements OAuthClientProvider {
  @override
  Future<OAuthTokens?> tokens() async {
    if (_currentToken?.isExpiringSoon ?? false) {
      await _refreshToken(); // Proactive refresh
    }
    return _currentToken;
  }
}
```

### Server-Side Validation

- **Always validate** tokens on the server
- **Verify token audience** matches your server URI
- **Check scopes** match required permissions
- **Cache validation results** with appropriate TTL
- **Rate limit** authentication attempts

### HTTPS Only

- **Always use HTTPS** in production
- **Never send** tokens over unencrypted connections
- **Use reverse proxy** (nginx, Caddy) for production HTTPS

```dart
// ✅ Good - HTTPS
final transport = StreamableHttpClientTransport(
  Uri.parse('https://api.example.com/mcp'),
  // ...
);

// ❌ Bad - HTTP (only for local development)
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  // ...
);
```

---

## Troubleshooting

### "Unauthorized" Errors

1. **Verify token validity**: Check if the token has expired
2. **Check token format**: Ensure Bearer prefix is included
3. **Validate scopes**: Verify required scopes are present
4. **Server validation**: Confirm server is configured correctly

### Token Refresh Failures

1. **Check refresh token**: Verify refresh token is valid and not expired
2. **Network issues**: Ensure connectivity to auth server
3. **Rate limiting**: Implement backoff for retry attempts
4. **Token revocation**: Handle revoked tokens gracefully

### OAuth Flow Issues

1. **Redirect URI mismatch**: Ensure redirect URIs match exactly
2. **State parameter**: Verify state validation for CSRF protection
3. **PKCE validation**: Check code_verifier matches code_challenge
4. **Scope requests**: Verify requested scopes are allowed by provider

---

## Additional Resources

- [MCP OAuth Specification](https://spec.modelcontextprotocol.io/specification/2025-11-05/basic/authentication/)
- [OAuth 2.0 Specification](https://oauth.net/2/)
- [PKCE (RFC 7636)](https://tools.ietf.org/html/rfc7636)
- [MCP Dart SDK Documentation](https://pub.dev/packages/mcp_dart)

## Need Help?

- **Issues**: [GitHub Issues](https://github.com/leehack/mcp_dart/issues)
- **Discussions**: [GitHub Discussions](https://github.com/leehack/mcp_dart/discussions)
- **Documentation**: [API Reference](https://pub.dev/documentation/mcp_dart/)

---

## License

These examples are provided under the same license as the MCP Dart SDK.
