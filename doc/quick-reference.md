# Quick Reference

Use this page for common `mcp_dart` calls. The [server guide](server-guide.md),
[client guide](client-guide.md), [tools guide](tools.md), and
[transport guide](transports.md) explain the full APIs and edge cases.

## Install and import

```yaml
dependencies:
  mcp_dart: ^2.3.0-dev.2
```

```dart
import 'package:mcp_dart/mcp_dart.dart';
```

The SDK requires Dart 3.5 or later. The dev.2 CLI requires Dart 3.7 or later.

## Protocol profile

The 2.3.0 preview defaults to `McpProtocol.stable`: try MCP `2026-07-28`
preview, then fall back to legacy initialization when needed.

```dart
const legacyClientOptions = McpClientOptions(protocol: McpProtocol.legacy);
const strictServerOptions = McpServerOptions(
  protocol: McpProtocol.require2026,
);
```

See the [MCP 2026-07-28 transition guide](mcp-2026-07-28.md) before depending on
draft-only behavior.

## Server

### Create and connect

```dart
final server = McpServer(
  const Implementation(name: 'example-server', version: '1.0.0'),
  options: const McpServerOptions(
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(listChanged: true),
      resources: ServerCapabilitiesResources(
        subscribe: true,
        listChanged: true,
      ),
      prompts: ServerCapabilitiesPrompts(listChanged: true),
    ),
  ),
);

await server.connect(StdioServerTransport());
```

Use `StreamableMcpServer` for a high-level HTTP server:

```dart
final httpServer = StreamableMcpServer(
  serverFactory: (_) => McpServer(
    const Implementation(name: 'remote-server', version: '1.0.0'),
  ),
  host: '127.0.0.1',
  port: 3000,
  path: '/mcp',
  allowedHosts: {'localhost', '127.0.0.1'},
  allowedOrigins: {'http://localhost:5173'},
);

await httpServer.start();
```

Keep DNS rebinding protection enabled and use exact host/origin allowlists for
browser or remote deployments. See [Streamable HTTP](transports.md#streamable-http-transport).

### Register a tool

```dart
server.registerTool(
  'add',
  description: 'Add two numbers',
  inputSchema: JsonSchema.object(
    properties: {
      'a': JsonSchema.number(),
      'b': JsonSchema.number(),
    },
    required: ['a', 'b'],
  ),
  callback: (arguments, extra) async {
    final a = arguments['a'] as num;
    final b = arguments['b'] as num;
    return CallToolResult(
      content: [TextContent(text: '${a + b}')],
    );
  },
);
```

Return `CallToolResult(isError: true, ...)` for an expected tool failure. Throw
`McpError` for a protocol-level failure. See [Tools](tools.md).

### Register a resource

```dart
server.registerResource(
  'Status',
  'status://current',
  (description: 'Current service status', mimeType: 'application/json'),
  (uri, extra) async => ReadResourceResult(
    contents: [
      TextResourceContents(
        uri: uri.toString(),
        mimeType: 'application/json',
        text: '{"status":"ok"}',
      ),
    ],
  ),
);
```

Use `registerResourceTemplate` for parameterized URIs and declare
`resources.subscribe` only when supporting legacy MCP 2025-11-25 resource
subscriptions. MCP 2026-07-28 sends resource updates through
`subscriptions/listen`.

### Register a prompt

```dart
server.registerPrompt(
  'review',
  description: 'Review a code change',
  argsSchema: {
    'diff': PromptArgumentDefinition(
      description: 'Patch to review',
      required: true,
    ),
  },
  callback: (arguments, extra) async {
    final diff = arguments?['diff'] as String? ?? '';
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: diff),
        ),
      ],
    );
  },
);
```

For tasks, MCP Apps metadata, completions, and advanced resource templates, see
the [server guide](server-guide.md).

## Client

### Connect

```dart
final client = McpClient(
  const Implementation(name: 'example-client', version: '1.0.0'),
);

await client.connect(
  StdioClientTransport(
    const StdioServerParameters(
      command: 'dart',
      args: ['run', 'bin/server.dart'],
    ),
  ),
);
```

Remote or browser client:

```dart
await client.connect(
  StreamableHttpClientTransport(Uri.parse('https://mcp.example.com/mcp')),
);
```

Always close the client:

```dart
try {
  // Use the client.
} finally {
  await client.close();
}
```

### Discover and use primitives

```dart
final tools = await client.listTools();
final toolResult = await client.callTool(
  const CallToolRequest(
    name: 'add',
    arguments: {'a': 2, 'b': 3},
  ),
);

final resources = await client.listResources();
final resource = await client.readResource(
  const ReadResourceRequest(uri: 'status://current'),
);

final prompts = await client.listPrompts();
final prompt = await client.getPrompt(
  const GetPromptRequest(
    name: 'review',
    arguments: {'diff': '...'},
  ),
);
```

Check advertised capabilities before optional operations:

```dart
final updates = client.listenSubscriptions(
  const SubscriptionsListenRequest(
    notifications: SubscriptionFilter(
      resourceSubscriptions: ['status://current'],
    ),
  ),
);
await updates.acknowledged;
```

For MCP 2025-11-25 stateful peers, check `resources.subscribe` before using
the legacy `subscribeResource`/`unsubscribeResource` methods.

See the [client guide](client-guide.md) for progress, sampling, roots,
elicitation, completions, tasks, reconnect behavior, and subscriptions.

## Content types

```dart
TextContent(text: 'hello');

ImageContent(
  data: base64Data,
  mimeType: 'image/png',
);

ResourceLink(
  uri: 'file:///report.txt',
  name: 'Report',
  mimeType: 'text/plain',
);

EmbeddedResource(
  resource: TextResourceContents(
    uri: 'memo://1',
    text: 'embedded text',
    mimeType: 'text/plain',
  ),
);
```

Tool results can contain multiple content items. The MCP 2026-07-28 preview also
supports the documented draft-only structured-content helpers.

## JSON Schema

```dart
final schema = JsonSchema.object(
  properties: {
    'query': JsonSchema.string(description: 'Search text'),
    'limit': JsonSchema.integer(minimum: 1, maximum: 100),
    'tags': JsonSchema.array(items: JsonSchema.string()),
    'mode': JsonSchema.string(enumValues: ['fast', 'thorough']),
  },
  required: ['query'],
);
```

The SDK validates JSON Schema Draft 2020-12 by default and accepts an explicitly
declared Draft 7 schema for MCP 2025-11-25 compatibility. Same-document `$ref`
and `$dynamicRef` references are supported; relative and network references,
unsupported dialects, and custom vocabularies are rejected. Validate business
rules in the callback as well as describing inputs in the schema.

## Errors

```dart
return CallToolResult(
  isError: true,
  content: [TextContent(text: 'The requested record was not found.')],
);

throw McpError(
  ErrorCode.invalidParams.value,
  'Expected a non-empty query.',
);
```

Common JSON-RPC codes are available through `ErrorCode`, including
`parseError`, `invalidRequest`, `methodNotFound`, `invalidParams`, and
`internalError`.

## Notifications and logging

For MCP 2026-07-28, acknowledge the caller's `subscriptions/listen` filter
before sending correlated notifications on that request stream:

```dart
server.server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
  Method.subscriptionsListen,
  (request, extra) async {
    final acknowledged = request.listenParams.notifications.acknowledgedBy(
      server.server.getCapabilities(),
    );
    await extra.sendSubscriptionAcknowledged(acknowledged);
    await extra.sendSubscriptionNotification(
      const JsonRpcToolListChangedNotification(),
    );
    return const EmptyResult();
  },
  (id, params, meta) => JsonRpcSubscriptionsListenRequest(
    id: id,
    listenParams: SubscriptionsListenRequest.fromJson(params!),
    meta: meta,
  ),
);

```

MCP 2026-07-28 deprecates protocol logging. The compatibility API belongs
inside a request handler, must receive `requestMeta: extra.meta`, and emits only
messages allowed by that request's log level. Legacy MCP 2025-11-25 peers
instead use global capability-gated methods such as `sendToolListChanged`,
`sendResourceUpdated`, and `logging/setLevel`.

Stdio servers must reserve stdout for MCP frames; send application logs to
stderr. Configure internal SDK logs with `setMcpLogHandler`,
`silenceMcpLogs`, or `resetMcpLogHandler`.

## Testing and verification

- Use IO stream/custom transports for in-process unit tests.
- Use `mcp_dart inspect-server` or `inspect-client` for a live target.
- Use `mcp_dart conformance` for this repository's built-in regression cases;
  it is not a certification tool for arbitrary peers.
- Run the linked [interop fixtures](interoperability.md) for cross-SDK claims.

## Platform reminders

| Target | Recommended transport |
| --- | --- |
| Dart VM / desktop helper | Stdio or Streamable HTTP |
| Browser / Flutter Web | Streamable HTTP client |
| Flutter mobile | Remote Streamable HTTP; app-managed helper only for local IPC |
| Unit tests / in-process | IO stream or custom transport |

See [Flutter recipes](flutter-recipes.md) for lifecycle and secure-storage
guidance.

## Next steps

- [Getting started](getting-started.md)
- [Server guide](server-guide.md)
- [Client guide](client-guide.md)
- [Tools](tools.md)
- [Transports](transports.md)
- [Examples](examples.md)
- [MCP Apps](mcp-apps.md)
- [Migration cookbooks](migration-cookbooks.md)
