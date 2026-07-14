# MCP OAuth resource-server guide

An MCP Streamable HTTP server is normally an OAuth protected resource, not the
authorization server that signs in users and issues tokens. `mcp_dart` handles
MCP metadata and challenge formatting; your application supplies trustworthy
token verification and authorization policy.

## Responsibility boundary

The SDK can:

- Serve OAuth Protected Resource Metadata.
- Advertise its metadata URL in `WWW-Authenticate`.
- Distinguish `401 Unauthorized` from `403 insufficient_scope`.
- Run authentication after `Host` and `Origin` validation.

Your application must:

- Verify the token signature against trusted keys or use a trusted
  introspection endpoint.
- Validate issuer, exact resource audience, expiry/not-before, and revocation
  policy.
- Derive granted scopes from verified token data, not requested/configured
  scopes.
- Propagate verified identity and authorization context to tool handlers.
- Protect secrets, logs, caches, and TLS termination.

## Configure protected-resource metadata

```dart
final resource = Uri.parse('https://mcp.example.com/mcp');
final metadataUri = Uri.parse(
  'https://mcp.example.com/.well-known/oauth-protected-resource/mcp',
);

final httpServer = StreamableMcpServer(
  serverFactory: (sessionId) => buildMcpServer(),
  host: '0.0.0.0',
  port: 3000,
  path: '/mcp',
  allowedHosts: {'mcp.example.com'},
  allowedOrigins: {'https://app.example.com'},
  authenticationHandler: authenticateRequest,
  oauthProtectedResource: OAuthProtectedResourceOptions(
    metadata: OAuthProtectedResourceMetadata(
      resource: resource,
      authorizationServers: [Uri.parse('https://auth.example.com')],
      scopesSupported: const ['tools:read', 'tools:write'],
    ),
    metadataUri: metadataUri,
    scope: 'tools:read',
  ),
);
```

Set `metadataUri` to the public HTTPS URL when a reverse proxy changes the
scheme, host, or port observed by Dart.

## Authenticate requests

The following is an integration shape, not a complete verifier. `tokenVerifier`
is application-defined and must return only cryptographically or remotely
verified claims:

```dart
Future<StreamableMcpAuthenticationResult> authenticateRequest(
  HttpRequest request,
) async {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  final token = parseBearerToken(header);
  if (token == null) {
    return const StreamableMcpAuthenticationResult.unauthorized();
  }

  final claims = await tokenVerifier.verify(token);
  if (claims == null ||
      claims.issuer != Uri.parse('https://auth.example.com') ||
      !claims.audiences.contains(Uri.parse('https://mcp.example.com/mcp')) ||
      claims.expiresAt.isBefore(DateTime.now())) {
    return const StreamableMcpAuthenticationResult.unauthorized();
  }

  if (!claims.scopes.contains('tools:read')) {
    return const StreamableMcpAuthenticationResult.insufficientScope(
      scope: 'tools:read',
      errorDescription: 'tools:read is required',
    );
  }

  return const StreamableMcpAuthenticationResult.allow();
}
```

Do not infer granted scopes from server configuration or the authorization
request. Validate them from the signed token or introspection response.

## Identity in tool handlers

Authentication occurs at the HTTP boundary. Tool authorization often needs the
same verified claims, so design an explicit request/session context. Avoid a
global "current user": concurrent sessions can otherwise see the wrong
identity. Clear cached context when a session closes and bound its lifetime to
the verified token's expiry.

The checked-in local example intentionally exposes only a generic greeting; it
does not claim tool-level scope enforcement.

## HTTP status and challenge rules

- Missing, malformed, expired, or otherwise invalid token: return
  `StreamableMcpAuthenticationResult.unauthorized()` (`401`).
- Valid token without a required scope: return
  `StreamableMcpAuthenticationResult.insufficientScope(...)` (`403`).
- Valid and authorized token: return
  `StreamableMcpAuthenticationResult.allow()`.

With `OAuthProtectedResourceOptions` configured, the SDK adds the corresponding
bearer challenge and protected-resource metadata URL.

## Deployment checklist

- Terminate TLS with a trusted certificate and preserve the public URI in
  metadata.
- Keep DNS rebinding protection enabled; configure explicit `Host` and `Origin`
  allowlists.
- Reject tokens for a different MCP resource even if they are otherwise valid.
- Cache verification only within token expiry and revocation requirements.
- Never log bearer tokens, authorization codes, client secrets, or PKCE
  verifiers.
- Rate-limit authentication failures without turning them into an account
  oracle.
- Exercise missing-token, invalid-token, wrong-audience, expired-token, and
  insufficient-scope paths in tests.

## Local demonstration

[`oauth_server_example.dart`](oauth_server_example.dart) uses one exact token
from `MCP_BEARER_TOKEN`. It is useful for metadata/challenge smoke tests and is
deliberately unsuitable for production token validation. See
[OAUTH_QUICK_START.md](OAUTH_QUICK_START.md).

## References

- [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
- [OAuth Protected Resource Metadata (RFC 9728)](https://www.rfc-editor.org/rfc/rfc9728)
- [OAuth resource indicators (RFC 8707)](https://www.rfc-editor.org/rfc/rfc8707)
- [Bearer token usage (RFC 6750)](https://www.rfc-editor.org/rfc/rfc6750)
