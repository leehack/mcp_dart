# MCP OAuth Server Example Guide

> **Quick setup:** [5-min guide](OAUTH_QUICK_START.md) | **GitHub specifics:** [GitHub Setup](GITHUB_SETUP.md)

This guide explains how to implement an MCP server with OAuth 2.0 authentication using the mcp_dart SDK.

## Overview

The OAuth server example demonstrates:
- OAuth 2.0 token validation
- Authorization code exchange
- Token refresh handling
- Scope-based access control
- Session management with OAuth tokens
- Multi-provider support (GitHub, Google)

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Client    │         │  MCP Server  │         │   OAuth     │
│             │         │   (Dart)     │         │  Provider   │
└──────┬──────┘         └──────┬───────┘         └──────┬──────┘
       │                       │                        │
       │ 1. Request with       │                        │
       │    Bearer token       │                        │
       ├──────────────────────>│                        │
       │                       │                        │
       │                       │ 2. Validate token      │
       │                       ├───────────────────────>│
       │                       │                        │
       │                       │ 3. User info           │
       │                       │<───────────────────────┤
       │                       │                        │
       │ 4. MCP response       │                        │
       │<──────────────────────┤                        │
       │                       │                        │
```

## Setup

### 1. OAuth Provider Configuration

#### GitHub OAuth Setup

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. Click "New OAuth App"
3. Configure:
   - Application name: `MCP Dart Server`
   - Homepage URL: `http://localhost:3000`
   - Authorization callback URL: `http://localhost:8080/callback` (for client)
4. Copy Client ID and Client Secret
5. Set environment variables:

```bash
export GITHUB_CLIENT_ID=your_client_id
export GITHUB_CLIENT_SECRET=your_client_secret
```

#### Google OAuth Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable OAuth 2.0:
   - Navigate to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "OAuth client ID"
   - Application type: "Web application"
   - Authorized redirect URIs: `http://localhost:8080/callback`
4. Copy Client ID and Client Secret
5. Set environment variables:

```bash
export GOOGLE_CLIENT_ID=your_client_id
export GOOGLE_CLIENT_SECRET=your_client_secret
```

### 2. Running the Server

```bash
# GitHub OAuth
dart run example/authentication/oauth_server_example.dart github

# Google OAuth
dart run example/authentication/oauth_server_example.dart google
```

The server will start on `http://localhost:3000/mcp`

## Using the Server

### 1. Obtain Access Token

You need a valid OAuth access token from your provider. Use the client example to get one:

```bash
# Run the GitHub OAuth client example
dart run example/authentication/github_oauth_example.dart
```

This will:
1. Open browser for OAuth authorization
2. Exchange code for access token
3. Save token to `.github_oauth_tokens.json`
4. Display the access token

### 2. Connect MCP Client with Token

```dart
import 'package:mcp_dart/mcp_dart.dart';

// Create client
final client = Client(
  Implementation(name: 'my-client', version: '1.0.0'),
);

// Create transport with OAuth token
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: StreamableHttpClientTransportOptions(
    headers: {
      'Authorization': 'Bearer YOUR_ACCESS_TOKEN_HERE',
    },
  ),
);

// Connect
await client.connect(transport);

// Use tools
final result = await client.callTool(
  'greet',
  arguments: {'name': 'World'},
);
```

### 3. Test with curl

```bash
# Test authentication
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}},"id":1}' \
     http://localhost:3000/mcp

# Expected response if valid token:
# {"jsonrpc":"2.0","result":{...},"id":1}

# Expected response if invalid token:
# {"jsonrpc":"2.0","error":{"code":-32001,"message":"Unauthorized: Valid OAuth token required"},"id":null}
```

## Implementation Details

### OAuth Token Validation

The server validates tokens by:

1. Extracting Bearer token from `Authorization` header
2. Calling OAuth provider's user info endpoint
3. Verifying token scopes match required scopes
4. Caching validated tokens (5-minute TTL)
5. Storing user info in session context

```dart
// Validate token
final tokenInfo = await validator.validateRequest(request);

if (tokenInfo == null) {
  // Return 401 Unauthorized
  return;
}

// Token is valid, user info available
print('User: ${tokenInfo.username} (${tokenInfo.userId})');
```

### Scope-Based Access Control

Configure required scopes for your server:

```dart
final config = OAuthServerConfig.github(
  clientId: clientId,
  clientSecret: clientSecret,
  requiredScopes: ['repo', 'read:user'],  // Require these scopes
);
```

Implement tool-level scope checks:

```dart
server.tool(
  'admin-action',
  description: 'Admin tool requiring special scope',
  callback: ({args, extra}) async {
    // Get token info from request context
    final tokenInfo = getTokenForSession(sessionId);

    // Check if user has admin scope
    if (!tokenInfo.scopes.contains('admin')) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        'Insufficient permissions: admin scope required',
      );
    }

    // Execute admin action
    return CallToolResult.fromContent(...);
  },
);
```

### Token Refresh Flow

The server supports token refresh for long-running sessions:

```dart
// Complete token refresh implementation
Future<OAuthTokenInfo?> refreshAccessToken(
  String refreshToken,
  String sessionId,
) async {
  try {
    final response = await http.post(
      config.tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newTokenInfo = OAuthTokenInfo(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'] ?? refreshToken,
        scopes: (data['scope'] as String?)?.split(' ') ?? [],
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] ?? 3600),
        ),
      );

      // Update session with new token
      _sessionTokens[sessionId] = newTokenInfo;

      return newTokenInfo;
    }

    return null;
  } catch (e) {
    print('Token refresh failed: $e');
    return null;
  }
}

// Use in request handler
if (tokenInfo.isExpired && tokenInfo.refreshToken != null) {
  final newToken = await refreshAccessToken(
    tokenInfo.refreshToken,
    sessionId,
  );

  if (newToken != null) {
    tokenInfo = newToken;  // Use refreshed token
  } else {
    // Refresh failed, require re-authentication
    return unauthorized();
  }
}
```

### Session Management

OAuth tokens are associated with MCP sessions:

```dart
// Session token storage
final Map<String, OAuthTokenInfo> _sessionTokens = {};

// Store token for session
void storeTokenForSession(String sessionId, OAuthTokenInfo tokenInfo) {
  _sessionTokens[sessionId] = tokenInfo;
}

// Retrieve token for session
OAuthTokenInfo? getTokenForSession(String sessionId) {
  return _sessionTokens[sessionId];
}

// Clear token when session closes
void clearSession(String sessionId) {
  _sessionTokens.remove(sessionId);
}

// In request handler
final sessionId = request.headers.value('mcp-session-id') ??
                  request.headers.value('x-session-id');

if (sessionId != null) {
  // Try to get existing token for session
  var tokenInfo = getTokenForSession(sessionId);

  if (tokenInfo == null) {
    // First request - validate and store token
    tokenInfo = await validator.validateRequest(request);
    if (tokenInfo != null) {
      storeTokenForSession(sessionId, tokenInfo);
    }
  }

  // Use tokenInfo for request processing
}
```

## Security Considerations

### Token Storage

- Tokens are cached in memory with short TTL (5 minutes)
- Never log or expose tokens in responses
- Clear tokens when session closes

```dart
transport.onclose = () {
  final sid = transport.sessionId;
  if (sid != null) {
    _sessionTokens.remove(sid);  // Clear token
  }
};
```

### HTTPS in Production

Always use HTTPS in production:

```dart
// Development
final server = await HttpServer.bind('localhost', 3000);

// Production - use HTTPS
final context = SecurityContext()
  ..useCertificateChain('cert.pem')
  ..usePrivateKey('key.pem');

final server = await HttpServer.bindSecure(
  '0.0.0.0',
  443,
  context,
);
```

### Rate Limiting

Implement rate limiting to prevent abuse:

```dart
class RateLimiter {
  final Map<String, List<DateTime>> _requests = {};
  final int maxRequests;
  final Duration window;

  bool allowRequest(String userId) {
    final now = DateTime.now();
    final userRequests = _requests.putIfAbsent(userId, () => []);

    // Remove old requests
    userRequests.removeWhere(
      (time) => now.difference(time) > window,
    );

    if (userRequests.length >= maxRequests) {
      return false;  // Rate limit exceeded
    }

    userRequests.add(now);
    return true;
  }
}
```

### Scope Validation

Always validate scopes for sensitive operations:

```dart
void validateScopes(OAuthTokenInfo token, List<String> required) {
  final missing = required.where(
    (scope) => !token.scopes.contains(scope),
  ).toList();

  if (missing.isNotEmpty) {
    throw McpError(
      ErrorCode.invalidRequest.value,
      'Missing required scopes: ${missing.join(", ")}',
    );
  }
}
```

## Advanced Features

### Custom OAuth Provider

Add support for custom OAuth providers:

```dart
factory OAuthServerConfig.custom({
  required String clientId,
  required String clientSecret,
  required Uri tokenEndpoint,
  required Uri userInfoEndpoint,
  List<String> requiredScopes = const [],
}) {
  return OAuthServerConfig(
    clientId: clientId,
    clientSecret: clientSecret,
    tokenEndpoint: tokenEndpoint,
    userInfoEndpoint: userInfoEndpoint,
    requiredScopes: requiredScopes,
  );
}

// Usage
final config = OAuthServerConfig.custom(
  clientId: 'custom_client_id',
  clientSecret: 'custom_secret',
  tokenEndpoint: Uri.parse('https://oauth.example.com/token'),
  userInfoEndpoint: Uri.parse('https://api.example.com/user'),
  requiredScopes: ['read', 'write'],
);
```

### User Context in Tools

Access user information in tool handlers:

```dart
// Extend RequestHandlerExtra to include user context
extension UserContext on RequestHandlerExtra {
  OAuthTokenInfo? getUserInfo() {
    // Retrieve from transport or session storage
    return null;  // Implement based on your architecture
  }
}

// Use in tool
server.tool(
  'get-user-data',
  callback: ({args, extra}) async {
    final user = extra?.getUserInfo();

    return CallToolResult.fromContent(
      content: [
        TextContent(
          text: 'User: ${user?.username ?? "unknown"}',
        ),
      ],
    );
  },
);
```

### Token Introspection

For advanced security, use OAuth token introspection:

```dart
Future<Map<String, dynamic>?> introspectToken(String token) async {
  final response = await http.post(
    Uri.parse('https://oauth.example.com/introspect'),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Basic ${base64Encode(utf8.encode("$clientId:$clientSecret"))}',
    },
    body: {'token': token},
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    if (data['active'] == true) {
      return data;
    }
  }

  return null;
}
```

## Troubleshooting

### Invalid Token Error

```
Error: Unauthorized: Valid OAuth token required
```

**Solutions:**
- Verify token is valid and not expired
- Check Authorization header format: `Bearer <token>`
- Ensure token has required scopes
- Test token with provider's API directly

### Scope Permission Error

```
Error: Token missing required scopes
```

**Solutions:**
- Request additional scopes during OAuth flow
- Update OAuth app configuration in provider
- Check token scopes in provider dashboard

### Token Refresh Failed

```
Error: Token refresh failed
```

**Solutions:**
- Verify refresh token is valid
- Check OAuth app credentials
- Ensure refresh token hasn't been revoked
- Re-authenticate if refresh token expired

## Examples

Complete examples are available in the repository:

- [oauth_server_example.dart](oauth_server_example.dart) - Full OAuth server implementation
- [oauth_client_example.dart](oauth_client_example.dart) - Generic OAuth client
- [github_oauth_example.dart](github_oauth_example.dart) - GitHub OAuth client
- [github_pat_example.dart](github_pat_example.dart) - GitHub PAT authentication

## References

- [OAuth 2.0 RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749)
- [GitHub OAuth Documentation](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [Google OAuth Documentation](https://developers.google.com/identity/protocols/oauth2)
- [MCP Protocol Specification](https://spec.modelcontextprotocol.io/)
