# Transport Options

Guide to choosing and configuring MCP transport layers.

## Overview

Transports handle the communication layer between MCP clients and servers. The SDK provides multiple transport options for different use cases.

## Transport Comparison

| Transport | Use Case | Platforms | Bidirectional | Complexity |
|-----------|----------|-----------|---------------|------------|
| **Stdio** | CLI tools, local processes | VM, Flutter | ✅ | Low |
| **HTTP/SSE** | Web services, remote APIs | All | ✅ | Medium |
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

### Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Dart VM** | ✅ | Full support |
| **Web** | ❌ | No process spawning in browser |
| **Flutter** | ✅ | Mobile and desktop |

### Best Practices

#### 1. Process Cleanup

```dart
// ✅ Always close client to terminate server process
try {
  final client = McpClient(...);
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

## HTTP/SSE Transport

### Overview

HTTP with Server-Sent Events for web-based communication. Best for:

- Web applications
- Remote services
- Cloud deployments
- Flutter web apps

### High-Level Streamable HTTP Server

For a simplified setup, use the `StreamableMcpServer` class which handles the server creation, session management, and transport connection for you.

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = StreamableMcpServer(
    serverFactory: (sessionId) {
      // Create a new McpServer instance for each session
      return McpServer(
        Implementation(name: 'my-server', version: '1.0.0'),
      );
    },
    host: '0.0.0.0',
    port: 3000,
    path: '/mcp',
    // Optional hardening for remote deployments
    enableDnsRebindingProtection: true,
    allowedHosts: {'localhost', 'api.example.com'},
    allowedOrigins: {'https://app.example.com'},
  );

  await server.start();
  print('Server running on http://0.0.0.0:3000/mcp');
}
```

This helper handles:
- Creating an HTTP server
- Managing sessions and event storage
- Connecting the `McpServer` to the transport
- Resumability support

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

Executable coverage for these recipes lives in
[`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart).
It verifies that local-development and production allowlists reject untrusted
Host/Origin headers before authentication runs, and that authentication still
gates requests after transport-level checks pass. The OAuth client PKCE flow is
covered by
[`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart)
with a local token endpoint.

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

  await transport.start();
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

### Session Management

#### Stateful Sessions

```dart
// Server: Enable session persistence
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
    eventStore: InMemoryEventStore(), // Enables resumability
  ),
);
```

```dart
// Client: Resume session
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: const StreamableHttpClientTransportOptions(
    sessionId: 'existing-session-id', // Resume this session
  ),
);
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

When using `StreamableHttpClientTransport` through `McpClient.request`, a
stateful `404 Session not found` clears the stale session, starts a fresh
session with a new `initialize` request that omits the stale `MCP-Session-Id`,
and retries the original request once. Direct `Transport.send` callers and
custom transports can opt into the same client recovery path by throwing
`StaleSessionError` when their stateful session is rejected.

#### Stateless Mode

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
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
  ),
);

await transport.start();
await server.connect(transport);

await for (final request in httpServer) {
  await transport.handleRequest(request); // Adds CORS headers internally
}
```

If you enable DNS rebinding protection, set explicit `allowedOrigins` for browser clients.

### Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Dart VM** | ✅ | Full HTTP server support |
| **Web** | ✅ | Client only (fetch API) |
| **Flutter** | ✅ | All platforms |

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
Future<void> connectWithRetry() async {
  var attempts = 0;
  const maxAttempts = 3;

  while (attempts < maxAttempts) {
    try {
      await client.connect(transport);
      return;
    } catch (e) {
      attempts++;
      if (attempts >= maxAttempts) rethrow;
      await Future.delayed(Duration(seconds: 2));
    }
  }
}
```

#### 4. Health Checks

```dart
// Server: Implement health endpoint
void handleRequest(HttpRequest request) async {
  if (request.uri.path == '/health') {
    request.response
      ..statusCode = 200
      ..write('OK');
    await request.response.close();
    return;
  }

  // Handle MCP requests
  final transport = StreamableHTTPServerTransport(...);
  await server.connect(transport);
}
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

    expect(result.content.first.text, '8');

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

- Replaced by StreamableHTTP (more flexible)
- Limited session management
- No resumability
- Use StreamableHTTP for new projects

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

await transport.start();
await mcpServer.connect(transport);
await transport.handleRequest(request);
```

## Choosing a Transport

### Decision Matrix

| Requirement | Best Transport |
|-------------|---------------|
| Local CLI tool | **Stdio** |
| Web application | **HTTP/SSE** |
| Remote API | **HTTP/SSE** |
| Unit testing | **Stream** |
| In-process | **Stream** |
| Node.js server | **Stdio** |
| Cloud deployment | **HTTP/SSE** |
| Mobile app (local) | **Stdio** |
| Mobile app (remote) | **HTTP/SSE** |

### Performance Comparison

| Transport | Latency | Throughput | Resource Usage |
|-----------|---------|------------|----------------|
| **Stream** | Lowest | Highest | Lowest |
| **Stdio** | Low | High | Low |
| **HTTP/SSE** | Medium | Medium | Medium |

### Security Considerations

| Transport | Security Features |
|-----------|------------------|
| **Stdio** | Process isolation, local only |
| **HTTP/SSE** | TLS/HTTPS, CORS, authentication, optional DNS rebinding protection |
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

Add logging, metrics, or filtering:

```dart
class LoggingTransport extends Transport implements RequestIdAwareTransport {
  final Transport inner;
  final Logger logger;

  LoggingTransport(this.inner, this.logger);

  @override
  Future<void> start() async {
    logger.info('Starting transport');
    await inner.start();

    inner.onmessage = (message) {
      logger.debug('Received: $message');
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
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
  }) async {
    logger.debug('Sending: $message');
    await inner.send(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    logger.debug('Sending: $message');
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
// Server: Enable CORS
request.response.headers
  ..set('Access-Control-Allow-Origin', '*')
  ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  ..set('Access-Control-Allow-Headers', 'Content-Type');
```

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

**Problem**: Session not resuming

```dart
// Client: Provide session ID
final transport = StreamableHttpClientTransport(
  Uri.parse('http://localhost:3000/mcp'),
  opts: StreamableHttpClientTransportOptions(
    sessionId: previousSessionId,
  ),
);
```

## Next Steps

- [Server Guide](server-guide.md) - Build MCP servers
- [Client Guide](client-guide.md) - Build MCP clients
- [Examples](examples.md) - Transport examples
