# Transport Options

Guide to choosing and configuring MCP transport layers.

## Overview

Transports handle the communication layer between MCP clients and servers. The SDK provides multiple transport options for different use cases.

## Transport Comparison

| Transport | Use Case | Platforms | Bidirectional | Complexity |
|-----------|----------|-----------|---------------|------------|
| **Stdio** | CLI tools, local processes | Dart VM, Flutter desktop | ✅ | Low |
| **Streamable HTTP** | Web services, remote APIs | All | ✅ | Medium |
| **Stream** | In-process, testing | All | ✅ | Low |

## Stdio Transport

### Overview

Standard input/output transport for process-based communication. Best for:

- Command-line tools
- Local services
- Process spawning
- Node.js MCP servers

### Server Setup

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = McpServer(
    Implementation(
      name: 'stdio-server',
      version: '1.0.0',
    ),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  // Register capabilities
  server.registerTool('example', ...);

  // Connect stdio transport
  final transport = StdioServerTransport();
  await server.connect(transport);

  // Server now reads from stdin and writes to stdout
}
```

### Client Setup

#### Connect to Dart Server

```dart
final client = McpClient(
  Implementation(name: 'client', version: '1.0.0'),
);

final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'dart',
    args: ['run', 'server.dart'],
  ),
);

await client.connect(transport);
```

#### Connect to Node.js Server

```dart
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'node',
    args: ['server.js'],
  ),
);

await client.connect(transport);
```

#### Connect to Python Server

```dart
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'python',
    args: ['-m', 'my_server'],
  ),
);

await client.connect(transport);
```

### Configuration Options

```dart
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'node',
    args: ['server.js'],
    workingDirectory: '/path/to/server',
    environment: {
      'API_KEY': 'secret',
      'DEBUG': 'true',
    },
  ),
);
```

By default, `environment` is merged with the parent process environment. To
withhold host credentials, copy and sanitize `Platform.environment`, pass that
map as `environment`, and set `includeParentEnvironment: false`. Compare
variable names case-insensitively when sanitizing for Windows compatibility.

The default inherited stderr mode is continuously forwarded. If you choose
`ProcessStartMode.normal`, continuously drain `transport.stderr`; otherwise a
child that fills its stderr pipe can block protocol startup or later requests.

### Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Dart VM** | ✅ | Full support |
| **Web** | ❌ | No process spawning in browser |
| **Flutter desktop** | ✅ | Can launch app-managed helper processes |
| **Flutter mobile** | Platform-dependent | Use only with an app-managed native helper; mobile apps cannot assume arbitrary process spawning |

### Best Practices

#### 1. Process Cleanup

```dart
// ✅ Always close client to terminate server process
final client = McpClient(...);
try {
  final transport = StdioClientTransport(StdioServerParameters(...));
  await client.connect(transport);

  // Use client...
} finally {
  await client.close();  // Terminates server process
}
```

#### 2. Error Handling

```dart
try {
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: 'node',
      args: ['server.js'],
    ),
  );
  await client.connect(transport);
} catch (e) {
  print('Failed to start server: $e');
  // Check:
  // - Is 'node' in PATH?
  // - Does 'server.js' exist?
  // - Are permissions correct?
}
```

#### 3. Logging

```dart
// Server logs to stderr (not stdout, which is used for protocol)
void main() async {
  final server = McpServer(...);

  // Use stderr for logging
  stderr.writeln('Server starting...');

  final transport = StdioServerTransport();
  await server.connect(transport);

  stderr.writeln('Server ready');
}
```

#### 4. Concurrent Requests

`StdioClientTransport` and `StdioServerTransport` serialize concurrent `send()` calls internally, so overlapping requests such as `Future.wait([...client.callTool(...)])` are safe on a single connected transport. Stdio servers should still reserve `stdout` for MCP messages and write logs to `stderr`.

## Streamable HTTP Transport

### Overview

MCP over HTTP, with optional Server-Sent Events responses. Best for:

- Web applications
- Remote services
- Cloud deployments
- Flutter web apps

### High-Level Streamable HTTP Server

For a simplified dual-era setup, use `StreamableMcpServer`. It routes MCP 2026
requests statelessly and manages sessions when a peer negotiates the MCP 2025
initialization flow.

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = StreamableMcpServer(
    serverFactory: (connectionId) {
      // Called per stateless 2026 request or per legacy session.
      return McpServer(
        Implementation(name: 'my-server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.stable),
      );
    },
    host: 'localhost',
    port: 3000,
    path: '/mcp',
    // Optional hardening for remote deployments
    enableDnsRebindingProtection: true,
    allowedHosts: {'localhost'},
    allowedOrigins: {'http://localhost:8080'},
  );

  await server.start();
  print('Server running on http://localhost:3000/mcp');
}
```

This helper handles:
- Creating an HTTP server
- Stateless request routing for MCP 2026
- Sessions, event storage, and resumability for legacy MCP
- Connecting the `McpServer` to the transport

### DNS Rebinding Protection

`StreamableMcpServer` and `StreamableHTTPServerTransport` support DNS rebinding protection, enabled by default for Streamable HTTP entry points.

- Validate `Host` against `allowedHosts`
- Validate `Origin` against `allowedOrigins` (if provided)
- Reject missing/invalid host headers when protection is enabled

Use this for remote/browser-exposed deployments.

#### Deployment recipes

**Safe local development**

Bind only to loopback and allow the exact browser development origin that needs
to call the MCP endpoint:

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(
    const Implementation(name: 'local-dev-server', version: '1.0.0'),
  ),
  host: '127.0.0.1',
  port: 3000,
  path: '/mcp',
  enableDnsRebindingProtection: true,
  allowedHosts: {'localhost', '127.0.0.1'},
  allowedOrigins: {'http://localhost:5173'},
);
```

Keep DNS rebinding protection enabled even on localhost. If your browser app runs
on a different dev-server port, add that exact origin instead of using a wildcard.

**Production browser or remote deployment**

Terminate TLS at your reverse proxy or load balancer, expose only the public MCP
hostname, and allow only the trusted web origins that should reach it. If your
deployment needs the Dart process itself to accept HTTPS, provide a custom secure
`HttpServer` setup; `StreamableMcpServer` binds its listener with plain HTTP:

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(
    const Implementation(name: 'production-server', version: '1.0.0'),
  ),
  host: '0.0.0.0',
  port: 3000,
  path: '/mcp',
  enableDnsRebindingProtection: true,
  allowedHosts: {'mcp.example.com'},
  allowedOrigins: {'https://app.example.com'},
);
```

For authenticated deployments, pair these transport checks with your OAuth or
bearer-token layer. The examples in `example/authentication/` show the MCP OAuth
flow and PKCE shape; production clients should use PKCE S256 with cryptographic
randomness and keep redirect URIs/origins explicit.

### Streamable HTTP Authentication

Transport allowlists and OAuth solve different problems: validate `Host` and
`Origin` first, then authenticate the accepted request. The helpers below cover
MCP protected-resource discovery and bearer challenges; the examples use
plaintext token files only for local learning. Production applications must use
platform secure storage or an encrypted credential service.

`StreamableMcpServer` can advertise OAuth Protected Resource Metadata and return
the MCP-required bearer challenge when authentication fails:

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(
    const Implementation(name: 'protected-server', version: '1.0.0'),
  ),
  host: '0.0.0.0',
  port: 3000,
  path: '/mcp',
  enableDnsRebindingProtection: true,
  allowedHosts: {'mcp.example.com'},
  allowedOrigins: {'https://app.example.com'},
  // Application-defined: verify signature or introspection, issuer, exact
  // resource audience, expiry, and scopes before returning allow.
  authenticationHandler: authenticateRequest,
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
```

`authenticateRequest` is application-defined. See the
[resource-server guide](../example/authentication/OAUTH_SERVER_GUIDE.md) for
the verification boundary. The static-token server in `example/authentication`
is explicitly a local metadata/challenge smoke test, not deployment guidance.

With this option enabled, failed authentication returns `401 Unauthorized` with
`WWW-Authenticate: Bearer resource_metadata="..."`. Metadata is served at the
endpoint-specific well-known path, such as
`/.well-known/oauth-protected-resource/mcp`, and also at the root
`/.well-known/oauth-protected-resource` by default. Without
`oauthProtectedResource`, the generic `authenticator` hook keeps its historical
`403 Forbidden` response. Set `metadataUri` to the public metadata URL when a
reverse proxy or TLS terminator rewrites the scheme, host, or port observed by
the Dart server.

Use `authenticationHandler` when authorization needs to distinguish invalid
credentials from insufficient scope:

```dart
authenticationHandler: (request) async {
  final principal = await tokenVerifier.verifyBearerRequest(request);
  if (principal == null) {
    return const StreamableMcpAuthenticationResult.unauthorized();
  }
  if (!principal.scopes.contains('tools:write')) {
    return const StreamableMcpAuthenticationResult.insufficientScope(
      scope: 'tools:write',
      errorDescription: 'Need tools:write',
    );
  }
  return const StreamableMcpAuthenticationResult.allow();
},
```

Here `tokenVerifier` and its verified `principal` are application-defined; do
not derive scopes or identity from an unverified token payload.

With `oauthProtectedResource` configured, `insufficientScope` returns
`403 Forbidden` plus a bearer challenge containing
`error="insufficient_scope"`, `scope="..."`, and `resource_metadata="..."`.
The existing bool `authenticator` callback remains source-compatible for simple
allow/deny checks.

On the client side, `StreamableHttpClientTransport` keeps existing
`OAuthClientProvider` implementations working. Providers that also implement
`OAuthAuthorizationCodeProvider` let the transport perform MCP OAuth discovery:
it parses bearer challenges, fetches OAuth Protected Resource Metadata, falls
back to the endpoint/root well-known protected-resource paths when needed,
discovers OAuth Authorization Server Metadata or OpenID Connect Discovery
metadata, builds a PKCE S256 authorization URL with the MCP `resource`
parameter, and exchanges the authorization code with `code_verifier` and
`resource` when `finishAuth(code, state: callbackState)` is called. Always read
the returned `state` from the callback URI and pass it back; the transport
rejects missing or mismatched state before contacting the token endpoint. If
authorization-server metadata advertises the authorization response `iss`
parameter, pass the callback's `iss` value through `issuer:` as well.

OAuth discovery is same-origin by default. Loopback MCP endpoints may discover
other loopback endpoints for local development. For a separate production
authorization host, approve only the expected HTTPS hosts:

```dart
final transport = StreamableHttpClientTransport(
  Uri.parse('https://mcp.example.com/mcp'),
  opts: StreamableHttpClientTransportOptions(
    authProvider: authProvider,
    oauthUriValidator: (uri, endpointKind) =>
        uri.host == 'auth.example.com',
  ),
);
```

The transport rejects user information, fragments, non-HTTP(S) URLs, and
non-loopback plaintext HTTP. OAuth metadata, registration, and token requests
do not follow redirects automatically. The exchanged value passed to
`saveTokens` is an `OAuthAuthorizationCodeTokens` instance, so providers that
want `tokenType`, `expiresIn`, or granted `scope` can read them by type-checking
that subtype while older `OAuthTokens` implementations stay source-compatible.
Authorization server metadata must explicitly advertise
`code_challenge_methods_supported` with `S256`; missing metadata is treated as
no PKCE support and the transport refuses the authorization-code flow.

Executable coverage for these recipes lives in
[`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart).
It verifies that local-development and production allowlists reject untrusted
Host/Origin headers before authentication runs, and that authentication still
gates requests after transport-level checks pass. The OAuth client PKCE flow is
covered by
[`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart)
with a local token endpoint, and the client transport discovery path is covered
by [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart).
The first-class OAuth protected-resource helper is covered by
[`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart)
and the official TypeScript SDK OAuth interop path in
[`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart),
including insufficient-scope upscoping from `tools:read` to `tools:write`.

### Streamable HTTP Strict Defaults

By default, Streamable HTTP server transports also enforce:

- Strict `MCP-Protocol-Version` request header validation
- Rejection of JSON-RPC batch POST payloads

These defaults make compatibility failures visible instead of accepting requests
that the Streamable HTTP spec no longer allows. If you need a temporary migration
mode, disable only the specific check that blocks a known legacy client:

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
  ),
  // Only if a legacy client still sends older or experimental versions.
  strictProtocolVersionHeaderValidation: false,
  // Keep DNS rebinding protection enabled and explicit.
  enableDnsRebindingProtection: true,
  allowedHosts: {'mcp.example.com'},
  allowedOrigins: {'https://app.example.com'},
);
```

Or with low-level transport options for a legacy client that temporarily still
sends JSON-RPC batch payloads:

```dart
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    // Prefer migrating clients to non-batch Streamable HTTP requests.
    rejectBatchJsonRpcPayloads: false,
    enableDnsRebindingProtection: true,
    allowedHosts: {'mcp.example.com'},
    allowedOrigins: {'https://app.example.com'},
  ),
);
```

Avoid disabling `enableDnsRebindingProtection` on browser-exposed or remote
servers. If you must disable it for an internal compatibility test, bind to
loopback/private networking and put the exception behind a short-lived migration
plan. The compatibility-toggle harness keeps Host/Origin protection enabled
while selectively disabling protocol-version or batch rejection checks, so
legacy-client migration does not silently weaken DNS rebinding defenses.

### Server Setup (Streamable HTTP)

```dart
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = McpServer(
    Implementation(
      name: 'http-server',
      version: '1.0.0',
    ),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  // Register capabilities
  server.registerTool(
    'example',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      return CallToolResult(content: [TextContent(text: 'ok')]);
    },
  );

  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => generateUUID(),
      eventStore: InMemoryEventStore(),
      enableDnsRebindingProtection: true,
      allowedHosts: {'localhost'},
      allowedOrigins: {'http://localhost:5173'},
    ),
  );

  await server.connect(transport);

  // Create HTTP server
  final httpServer = await HttpServer.bind('localhost', 3000);
  print('Server listening on http://localhost:3000/mcp');

  await for (final request in httpServer) {
    if (request.uri.path != '/mcp') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
      continue;
    }

    await transport.handleRequest(request);
  }
}
```

### Client Setup

```dart
final client = McpClient(
  Implementation(name: 'client', version: '1.0.0'),
);

final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
);

await client.connect(transport);
```

### MCP 2025 and Earlier Session Management

The following session and replay controls apply only when the initialization-era
flow is selected. Two default `McpProtocol.stable` peers negotiate MCP 2026 and
therefore do not use protocol sessions, `MCP-Session-Id`, GET/DELETE session
operations, or replay. Select `McpProtocol.legacy` explicitly when building a
session-dependent deployment.

#### Stateful Sessions

```dart
final server = McpServer(
  Implementation(name: 'legacy-server', version: '1.0.0'),
  options: const McpServerOptions(protocol: McpProtocol.legacy),
);

// Enable legacy session persistence.
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
    eventStore: InMemoryEventStore(), // Enables resumability
  ),
);

await server.connect(transport);
```

```dart
final client = McpClient(
  Implementation(name: 'legacy-client', version: '1.0.0'),
  options: const McpClientOptions(protocol: McpProtocol.legacy),
);

// Resume a legacy session.
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: const StreamableHttpClientTransportOptions(
    sessionId: 'existing-session-id', // Resume this session
  ),
);

await client.connect(transport);
```

Generated session IDs are sent in the `MCP-Session-Id` response header. Keep
custom `sessionIdGenerator` output non-empty visible ASCII without spaces or
control characters; UUIDs such as `generateUUID()` are a safe default. Invalid
generated IDs are rejected before the header is written.

With an `eventStore`, resumability follows Streamable HTTP SSE event IDs:
custom event IDs must be non-empty visible ASCII without spaces or control
characters because they are written to SSE `id:` fields and later sent in the
`Last-Event-ID` HTTP header. `Last-Event-ID` replays only events from the
owning live transport/session stream, and unknown or foreign event IDs are
rejected instead of replaying unrelated stream history. Concurrent standalone
GET SSE streams are not fan-out subscriptions: each server-originated JSON-RPC
message is routed to one active stream, not broadcast to every open GET stream.
When a server opens an SSE stream and an event store is configured, the SDK
writes an initial SSE frame with an `id` and empty `data` field so reconnecting
clients can resume from a concrete stream event even before JSON-RPC messages
are available.

When using `StreamableHttpClientTransport` through `McpClient.request`, a
stateful `404 Session not found` clears the stale session, starts a fresh
session with a new `initialize` request that omits the stale `MCP-Session-Id`,
and retries the original request once. Direct `Transport.send` callers and
custom transports can opt into the same client recovery path by throwing
`StaleSessionError` when their stateful session is rejected.

#### Legacy Transport Without Session Persistence

For a legacy-profile deployment that intentionally disables session
persistence:

```dart
// Server: Disable session persistence
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => null, // Stateless mode
  ),
);
```

### CORS Configuration

```dart
final httpServer = StreamableMcpServer(
  serverFactory: (_) => createServer(),
  host: '127.0.0.1',
  port: 3000,
  allowedHosts: const {'localhost', '127.0.0.1'},
  allowedOrigins: const {'http://localhost:5173'},
);

await httpServer.start();
```

The high-level server validates Host and Origin and handles preflight requests.
Matching `allowedOrigins` receive exact, credentialed CORS responses. Without
an explicit origin allowlist, servers using the default DNS-rebinding protection
grant credentialed CORS only to loopback-to-loopback development requests;
other allowed requests receive wildcard CORS without credentials. If DNS
protection is disabled, loopback requests also require explicit
`allowedOrigins` for credentials. Low-level
`StreamableHTTPServerTransport.handleRequest` callers own their HTTP routing and
CORS headers. Keep explicit `allowedOrigins` for browser clients.

### Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Dart VM** | ✅ | Full HTTP server support |
| **Web** | ✅ | Client only (fetch API) |
| **Flutter web** | ✅ | Client only, using the browser fetch API |
| **Flutter mobile** | ✅ | Client for remote endpoints; secure tokens with platform storage |
| **Flutter desktop** | ✅ | Client and VM-hosted server support |

### Best Practices

#### 1. Request Headers

```dart
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: const StreamableHttpClientTransportOptions(
    requestInit: <String, dynamic>{
      'headers': <String, dynamic>{'X-Client-Name': 'mcp-dart-example'},
    },
  ),
);
```

#### 2. Reconnection Configuration

```dart
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: const StreamableHttpClientTransportOptions(
    reconnectionOptions: const StreamableHttpReconnectionOptions(
      maxReconnectionDelay: 30000,
      initialReconnectionDelay: 1000,
      reconnectionDelayGrowFactor: 1.5,
      maxRetries: 3,
    ),
  ),
);
```

#### 3. Error Recovery

```dart
Future<McpClient> connectWithRetry(
  McpClient Function() createClient,
  Transport Function() createTransport,
) async {
  const maxAttempts = 3;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final client = createClient();
    try {
      await client.connect(createTransport());
      return client;
    } catch (_) {
      await client.close();
      if (attempt == maxAttempts) rethrow;
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  throw StateError('Unreachable');
}
```

#### 4. Health Checks

```dart
final mcpServer = StreamableMcpServer(
  serverFactory: (_) => createServer(),
  host: '127.0.0.1',
  port: 3000,
);
await mcpServer.start();

// Keep health checks separate from the MCP listener, or terminate them at a
// reverse proxy. Do not create and connect a new MCP transport per request.
final healthServer = await HttpServer.bind('127.0.0.1', 3001);
healthServer.listen((request) async {
  if (request.uri.path == '/health' && request.method == 'GET') {
    request.response
      ..statusCode = 200
      ..write('OK');
  } else {
    request.response.statusCode = 404;
  }
  await request.response.close();
});
```

## Stream Transport

### Overview

In-process stream-based communication. Best for:

- Unit testing
- In-process communication
- Isolate communication
- Mock servers

### Setup

```dart
import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // Create bidirectional streams
  final serverToClient = StreamController<String>();
  final clientToServer = StreamController<String>();

  // Server setup
  final server = McpServer(
    Implementation(name: 'server', version: '1.0.0'),
  );
  server.registerTool('example', ...);

  final serverTransport = IOStreamTransport(
    stream: clientToServer.stream,
    sink: serverToClient.sink,
  );
  await server.connect(serverTransport);

  // Client setup
  final client = McpClient(
    Implementation(name: 'client', version: '1.0.0'),
  );

  final clientTransport = IOStreamTransport(
    stream: serverToClient.stream,
    sink: clientToServer.sink,
  );
  await client.connect(clientTransport);

  // Use client and server
  final result = await client.callTool(
    CallToolRequest(
      name: 'example',
      arguments: {},
    ),
  );

  // Cleanup
  await client.close();
  await server.close();
  await serverToClient.close();
  await clientToServer.close();
}
```

### Testing Example

```dart
import 'package:test/test.dart';

void main() {
  test('tool execution', () async {
    // Setup streams
    final s2c = StreamController<String>();
    final c2s = StreamController<String>();

    // Create server
    final server = McpServer(
      Implementation(name: 'test-server', version: '1.0.0'),
    );

    server.registerTool(
      'add',
      description: 'Add numbers',
      inputSchema: JsonSchema.object(
        properties: {
          'a': JsonSchema.number(),
          'b': JsonSchema.number(),
        },
      ),
      callback: (args, extra) async {
        final result = (args['a'] as num) + (args['b'] as num);
        return CallToolResult(
          content: [TextContent(text: '$result')],
        );
      },
    );

    await server.connect(IOStreamTransport(
      stream: c2s.stream,
      sink: s2c.sink,
    ));

    // Create client
    final client = McpClient(
      Implementation(name: 'test-client', version: '1.0.0'),
    );

    await client.connect(IOStreamTransport(
      stream: s2c.stream,
      sink: c2s.sink,
    ));

    // Test
    final result = await client.callTool(
      CallToolRequest(
        name: 'add',
        arguments: {'a': 5, 'b': 3},
      ),
    );

    expect(
      result.content.first,
      isA<TextContent>().having((content) => content.text, 'text', '8'),
    );

    // Cleanup
    await client.close();
    await server.close();
    await s2c.close();
    await c2s.close();
  });
}
```

### Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Dart VM** | ✅ | Full support |
| **Web** | ✅ | Full support |
| **Flutter** | ✅ | All platforms |

## Legacy SSE Transport (Deprecated)

The SDK includes an older SSE transport implementation that is deprecated but still supported for backward compatibility.

### Why Deprecated?

- Replaced by Streamable HTTP (more flexible)
- Limited session management
- No resumability
- Use Streamable HTTP for new projects

### Migration Guide

```dart
// Old (deprecated)
final manager = SseServerManager(mcpServer);
await manager.handleRequest(request);

// New (recommended)
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
    eventStore: InMemoryEventStore(),
    enableDnsRebindingProtection: true,
    allowedHosts: {'localhost'},
    allowedOrigins: {'http://localhost:5173'},
  ),
);

await mcpServer.connect(transport);
await transport.handleRequest(request);
```

## Choosing a Transport

### Decision Matrix

| Requirement | Best Transport |
|-------------|---------------|
| Local CLI tool | **Stdio** |
| Web application | **Streamable HTTP** |
| Remote API | **Streamable HTTP** |
| Unit testing | **Stream** |
| In-process | **Stream** |
| Node.js server | **Stdio** |
| Cloud deployment | **Streamable HTTP** |
| Mobile app (local helper) | **App-managed native helper or custom transport** |
| Mobile app (remote) | **Streamable HTTP** |

### Performance Comparison

| Transport | Latency | Throughput | Resource Usage |
|-----------|---------|------------|----------------|
| **Stream** | Lowest | Highest | Lowest |
| **Stdio** | Low | High | Low |
| **Streamable HTTP** | Medium | Medium | Medium |

### Security Considerations

| Transport | Security Features |
|-----------|------------------|
| **Stdio** | Process isolation, local only |
| **Streamable HTTP** | CORS, authentication, DNS rebinding protection by default; TLS through an HTTPS endpoint or reverse proxy |
| **Stream** | In-process only |

## Advanced Configuration

### Custom Transport

Implement your own transport:

```dart
class CustomTransport extends Transport {
  @override
  Future<void> start() async {
    // Initialize transport
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
  }) async {
    // Send message. Existing transports can keep the int? relatedRequestId
    // signature for source compatibility.
  }

  @override
  Future<void> close() async {
    // Clean up resources
  }

  @override
  String? get sessionId => null;

  // Call this when receiving messages
  void receiveMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }

  // Call this on connection close
  void handleClose() {
    onclose?.call();
  }

  // Call this on errors
  void handleError(Error error) {
    onerror?.call(error);
  }
}
```

### Request ID-aware Transports

If a custom transport routes messages by JSON-RPC request ID or stream
correlation key, implement `RequestIdAwareTransport` in addition to `Transport`
so string request IDs are preserved:

```dart
class StreamRoutingTransport extends CustomTransport
    implements RequestIdAwareTransport {
  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    // Route with the full JSON-RPC request ID shape: String or int.
  }
}
```

### Transport Middleware

Add logging, metrics, or filtering. Log only envelope metadata by default: raw
MCP messages can contain credentials, tool arguments/results, prompt content,
or resource data.

```dart
String describeMessage(JsonRpcMessage message) => switch (message) {
  JsonRpcRequest(:final method, :final id) => 'request method=$method id=$id',
  JsonRpcNotification(:final method) => 'notification method=$method',
  JsonRpcResponse(:final id) => 'response id=$id',
  JsonRpcError(:final id) => 'error id=$id',
};

class LoggingTransport extends Transport implements RequestIdAwareTransport {
  final Transport inner;
  final Logger logger;

  LoggingTransport(this.inner, this.logger);

  @override
  Future<void> start() async {
    logger.info('Starting transport');
    inner.onmessage = (message) {
      logger.debug('Received ${describeMessage(message)}');
      onmessage?.call(message);
    };

    inner.onerror = (error) {
      logger.warn('Error: $error');
      onerror?.call(error);
    };

    inner.onclose = () {
      logger.info('Closed');
      onclose?.call();
    };

    await inner.start();
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
  }) async {
    logger.debug('Sending ${describeMessage(message)}');
    await inner.send(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    logger.debug('Sending ${describeMessage(message)}');
    await inner.sendPreservingRequestId(
      message,
      relatedRequestId: relatedRequestId,
    );
  }

  @override
  Future<void> close() async {
    logger.info('Closing transport');
    await inner.close();
  }

  @override
  String? get sessionId => inner.sessionId;
}

// Usage
final transport = LoggingTransport(
  StdioClientTransport(
    StdioServerParameters(
      command: 'node',
      args: ['server.js'],
    ),
  ),
  Logger('Transport'),
);
```

## Troubleshooting

### Stdio Issues

**Problem**: Process not starting

```dart
// Check command exists
try {
  final result = await Process.run('node', ['--version']);
  print('Node version: ${result.stdout}');
} catch (e) {
  print('Node not found in PATH');
}
```

**Problem**: Server not responding

```dart
// Enable debug logging
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'node',
    args: ['server.js'],
    environment: {'DEBUG': 'mcp:*'},
  ),
);
```

### HTTP Issues

**Problem**: CORS errors

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) => createServer(),
  host: '0.0.0.0',
  allowedHosts: {'mcp.example.com'},
  allowedOrigins: {'https://app.example.com'},
);
```

Use exact origins for credentialed MCP traffic. Do not work around CORS with a
wildcard; align the browser origin, reverse proxy, and server allowlists.

**Problem**: SSE reconnects give up too quickly

```dart
// Increase retry attempts and maximum backoff
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: const StreamableHttpClientTransportOptions(
    reconnectionOptions: const StreamableHttpReconnectionOptions(
      maxReconnectionDelay: 60000,
      initialReconnectionDelay: 1000,
      reconnectionDelayGrowFactor: 1.5,
      maxRetries: 5,
    ),
  ),
);
```

**Problem**: MCP 2025/legacy session not resuming

```dart
final client = McpClient(
  Implementation(name: 'legacy-client', version: '1.0.0'),
  options: const McpClientOptions(protocol: McpProtocol.legacy),
);

final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: StreamableHttpClientTransportOptions(
    sessionId: previousSessionId,
  ),
);

await client.connect(transport);
```

## Next Steps

- [Server Guide](server-guide.md) - Build MCP servers
- [Client Guide](client-guide.md) - Build MCP clients
- [Examples](examples.md) - Transport examples
