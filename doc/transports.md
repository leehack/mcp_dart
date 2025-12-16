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
    options: ServerOptions(
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
final client = Client(
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
  final client = Client(...);
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
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  // Register capabilities
  server.tool(name: 'example', ...);

  // Create HTTP server
  final httpServer = await HttpServer.bind('localhost', 3000);
  print('Server listening on http://localhost:3000');

  await for (final request in httpServer) {
    // Create transport for each request
    final transport = StreamableHTTPServerTransport(
      request: request,
      response: request.response,
      sessionId: 'session-${DateTime.now().millisecondsSinceEpoch}',
    );

    // Connect MCP server to this transport
    await server.connect(transport);
  }
}
```

### Client Setup

```dart
final client = Client(
  Implementation(name: 'client', version: '1.0.0'),
);

final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
);

await client.connect(transport);
```

### Session Management

#### Stateful Sessions

```dart
// Server: Enable session persistence
final transport = StreamableHTTPServerTransport(
  request: request,
  response: response,
  sessionId: sessionId,
  enableResume: true,  // Allow resuming
);
```

```dart
// Client: Resume session
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
  sessionId: 'existing-session-id',  // Resume this session
);
```

#### Stateless Mode

```dart
// Server: Disable session persistence
final transport = StreamableHTTPServerTransport(
  request: request,
  response: response,
  enableResume: false,  // No session persistence
);
```

### CORS Configuration

```dart
void handleRequest(HttpRequest request) async {
  // Set CORS headers
  request.response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = 204;
    await request.response.close();
    return;
  }

  // Handle MCP request
  final transport = StreamableHTTPServerTransport(
    request: request,
    response: request.response,
  );
  await server.connect(transport);
}
```

### Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Dart VM** | ✅ | Full HTTP server support |
| **Web** | ✅ | Client only (fetch API) |
| **Flutter** | ✅ | All platforms |

### Best Practices

#### 1. Connection Pooling

```dart
// Reuse HTTP client connections
final httpClient = HttpClient();

final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
  httpClient: httpClient,  // Shared client
);
```

#### 2. Timeout Configuration

```dart
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
  timeout: Duration(seconds: 30),
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
    inputStream: clientToServer.stream,
    outputSink: serverToClient.sink,
  );
  await server.connect(serverTransport);

  // Client setup
  final client = Client(
    Implementation(name: 'client', version: '1.0.0'),
  );

  final clientTransport = IOStreamTransport(
    inputStream: serverToClient.stream,
    outputSink: clientToServer.sink,
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
      inputSchema: ToolInputSchema(
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
      inputStream: c2s.stream,
      outputSink: s2c.sink,
    ));

    // Create client
    final client = Client(
      Implementation(name: 'test-client', version: '1.0.0'),
    );

    await client.connect(IOStreamTransport(
      inputStream: s2c.stream,
      outputSink: c2s.sink,
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
final transport = SseServerTransport(
  request: request,
  response: response,
);

// New (recommended)
final transport = StreamableHTTPServerTransport(
  request: request,
  response: response,
  sessionId: generateSessionId(),
  enableResume: true,
);
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
| **HTTP/SSE** | TLS/HTTPS, CORS, authentication |
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
  Future<void> send(JsonRpcMessage message) async {
    // Send message
  }

  @override
  Future<void> close() async {
    // Clean up resources
  }

  // Call this when receiving messages
  void receiveMessage(JsonRpcMessage message) {
    onMessage?.call(message);
  }

  // Call this on connection close
  void handleClose() {
    onClose?.call();
  }

  // Call this on errors
  void handleError(Object error) {
    onError?.call(error);
  }
}
```

### Transport Middleware

Add logging, metrics, or filtering:

```dart
class LoggingTransport extends Transport {
  final Transport inner;
  final Logger logger;

  LoggingTransport(this.inner, this.logger);

  @override
  Future<void> start() async {
    logger.info('Starting transport');
    await inner.start();

    inner.onMessage = (message) {
      logger.fine('Received: $message');
      onMessage?.call(message);
    };

    inner.onError = (error) {
      logger.warning('Error: $error');
      onError?.call(error);
    };

    inner.onClose = () {
      logger.info('Closed');
      onClose?.call();
    };
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    logger.fine('Sending: $message');
    await inner.send(message);
  }

  @override
  Future<void> close() async {
    logger.info('Closing transport');
    await inner.close();
  }
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

**Problem**: Connection timeout

```dart
// Increase timeout
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
  timeout: Duration(seconds: 60),
);
```

**Problem**: Session not resuming

```dart
// Client: Provide session ID
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
  sessionId: previousSessionId,
);
```

## Next Steps

- [Server Guide](server-guide.md) - Build MCP servers
- [Client Guide](client-guide.md) - Build MCP clients
- [Examples](examples.md) - Transport examples
