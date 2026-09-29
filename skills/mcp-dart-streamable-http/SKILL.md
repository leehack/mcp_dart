---
name: mcp-dart-streamable-http
description: >-
  Use when serving an MCP server over HTTP with mcp_dart or connecting to a
  remote one: StreamableMcpServer setup, Host and Origin allowlists (DNS
  rebinding protection), CORS for browser clients, bearer-token or OAuth
  protection with protected-resource metadata, and StreamableHttpClientTransport
  headers, auth providers and OAuth authorization-code discovery.
---

# Streamable HTTP servers and clients with mcp_dart

Streamable HTTP is the MCP transport for remote servers, browsers, Flutter Web
and mobile apps. `StreamableMcpServer` serves one endpoint (default `/mcp`),
routes MCP 2026-07-28 requests statelessly and manages sessions for
initialization-era (MCP 2025-11-25 and earlier) clients.
`StreamableHttpClientTransport` is the matching client transport. Server APIs
need `dart:io`; the client transport also runs on the web.

## Guidelines

- `serverFactory` runs once per stateless MCP 2026-07-28 request and once per
  legacy session. Return `createMcpServer(services)` from it (see the
  `mcp-dart-server` project structure) and build application state
  (databases, caches, clients) once, outside the factory.
- If you change `protocol`, pass the same `McpProtocol` to
  `StreamableMcpServer(protocol: ...)` and to the factory's
  `McpServerOptions(protocol: ...)`.
- Leave `enableDnsRebindingProtection` at its default (`true`), even on
  localhost. Set `allowedHosts` to the exact public hostnames and
  `allowedOrigins` to the exact browser origins (`https://app.example.com`),
  never wildcards. `allowedOrigins` also drives credentialed CORS.
- Bind to `127.0.0.1` for local development. `StreamableMcpServer` listens on
  plain HTTP: terminate TLS at a reverse proxy or load balancer for remote
  deployments, and set `OAuthProtectedResourceOptions.metadataUri` to the
  public URL when the proxy rewrites scheme, host or port.
- Authenticate with `authenticationHandler: (request) => ...` returning `StreamableMcpAuthenticationResult.allow()`,
  `.unauthorized()` or `.insufficientScope(scope: ...)`. Verify the token's
  signature or introspect it, and check issuer, audience/resource, expiry and
  scopes. Never trust claims from an unverified token. Host/Origin checks run
  before authentication. Pass a closure: `package:mcp_dart/mcp_dart.dart`
  defaults to web-safe exports, so the analyzer types `request` as `dynamic`
  (it is an `HttpRequest` at runtime on `dart:io`), and a tear-off typed
  `Function(HttpRequest)` fails analysis.
- Configure `oauthProtectedResource` so failures return `401` with a
  `WWW-Authenticate: Bearer resource_metadata="..."` challenge and the
  metadata is served at `/.well-known/oauth-protected-resource/<path>`.
  Without it, a failed check is a generic `403`. The boolean `authenticator`
  hook remains for simple allow/deny checks.
- Keep the strict defaults (`strictProtocolVersionHeaderValidation`,
  `rejectBatchJsonRpcPayloads`) unless a specific legacy peer requires
  otherwise. Stop the server with `await server.stop()`.
- Client: pass static headers through
  `StreamableHttpClientTransportOptions(requestInit: {'headers': {...}})` and
  tokens through an `OAuthClientProvider` whose `tokens()` returns
  `OAuthTokens(accessToken: ...)`. Load tokens from secure storage; never
  hard-code, log or persist them in plaintext files.
- For interactive OAuth, implement `OAuthAuthorizationCodeProvider`. The
  transport discovers protected-resource and authorization-server metadata,
  builds a PKCE S256 URL and calls `redirectToAuthorizationUrl`. When the
  redirect arrives, call `transport.finishAuthRedirect(code, state: ...,
  issuer: ...)` with the callback's `state` (and `iss` when present), then
  reconnect. Cross-origin authorization servers must be approved with a
  narrow `oauthUriValidator`.
- Legacy HTTP+SSE (`SseClientTransport`, `SseServerManager`) is deprecated.
  Use Streamable HTTP for new integrations.

## Examples

A protected Streamable HTTP server behind a TLS-terminating proxy:

```dart
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

void registerTools(McpServer server) {
  server.registerTool(
    'echo',
    description: 'Echo a message.',
    inputSchema: JsonSchema.object(
      properties: {'message': JsonSchema.string()},
      required: ['message'],
    ),
    annotations: const ToolAnnotations(readOnlyHint: true),
    callback: (args, extra) async => CallToolResult(
      content: [TextContent(text: args['message'] as String)],
    ),
  );
}

/// Application-defined: verify the JWT signature or introspect the token and
/// check issuer, audience/resource and expiry. Return its scopes, or null.
Future<Set<String>?> verifyBearerToken(String token) async => null;

Future<StreamableMcpAuthenticationResult> authenticate(
  HttpRequest request,
) async {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  if (header == null || !header.startsWith('Bearer ')) {
    return const StreamableMcpAuthenticationResult.unauthorized();
  }
  final scopes = await verifyBearerToken(header.substring(7));
  if (scopes == null) {
    return const StreamableMcpAuthenticationResult.unauthorized(
      errorDescription: 'Invalid or expired token',
    );
  }
  if (!scopes.contains('tools:read')) {
    return const StreamableMcpAuthenticationResult.insufficientScope(
      scope: 'tools:read',
    );
  }
  return const StreamableMcpAuthenticationResult.allow();
}

Future<void> main() async {
  final server = StreamableMcpServer(
    serverFactory: (sessionId) {
      final mcpServer = McpServer(
        const Implementation(name: 'echo-server', version: '1.0.0'),
      );
      registerTools(mcpServer);
      return mcpServer;
    },
    host: '0.0.0.0',
    port: 3000,
    path: '/mcp',
    allowedHosts: {'mcp.example.com'},
    allowedOrigins: {'https://app.example.com'},
    authenticationHandler: (request) => authenticate(request),
    oauthProtectedResource: OAuthProtectedResourceOptions(
      metadata: OAuthProtectedResourceMetadata(
        resource: Uri.parse('https://mcp.example.com/mcp'),
        authorizationServers: [Uri.parse('https://auth.example.com')],
        scopesSupported: const ['tools:read'],
      ),
      metadataUri: Uri.parse(
        'https://mcp.example.com/.well-known/oauth-protected-resource/mcp',
      ),
      scope: 'tools:read',
    ),
  );

  await server.start();
  stderr.writeln('Listening on :3000/mcp');
  await ProcessSignal.sigint.watch().first;
  await server.stop();
}
```

A client that sends a pre-issued bearer token and a custom header:

```dart
import 'package:mcp_dart/mcp_dart.dart';

class StaticTokenProvider implements OAuthClientProvider {
  StaticTokenProvider(this._loadToken);

  final Future<String> Function() _loadToken;

  @override
  Future<OAuthTokens?> tokens() async =>
      OAuthTokens(accessToken: await _loadToken());

  @override
  Future<void> redirectToAuthorization() async {
    throw UnauthorizedError('The MCP server rejected the stored token.');
  }
}

Future<void> listRemoteTools(Future<String> Function() loadToken) async {
  final client = McpClient(
    const Implementation(name: 'remote-client', version: '1.0.0'),
  );
  try {
    await client.connect(
      StreamableHttpClientTransport(
        Uri.parse('https://mcp.example.com/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: StaticTokenProvider(loadToken),
          requestInit: const {
            'headers': {'X-Client-Name': 'remote-client'},
          },
        ),
      ),
    );
    final tools = await client.listTools();
    print(tools.tools.map((tool) => tool.name).join(', '));
  } on UnauthorizedError catch (error) {
    print('Sign-in required: $error');
  } finally {
    await client.close();
  }
}
```

## More

- Transport guide (DNS rebinding, CORS, strict defaults, OAuth): https://github.com/leehack/mcp_dart/blob/main/doc/transports.md
- OAuth client and resource-server examples: https://github.com/leehack/mcp_dart/tree/main/example/authentication
- Building the server itself: the `mcp-dart-server` skill.
