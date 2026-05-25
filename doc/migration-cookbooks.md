# MCP Migration Cookbooks

This page collects practical migration paths into `mcp_dart`. It complements the protocol-specific [`2025-11-25 compatibility migration`](migration_2025_11_25_compat.md) guide.

## Cookbook 1: TypeScript SDK server example -> Dart server

Use this when porting a small TypeScript MCP server to Dart.

| TypeScript SDK concept | `mcp_dart` equivalent | Notes |
| --- | --- | --- |
| `McpServer` | `McpServer` | Both expose tools, resources, prompts, and capabilities. |
| Server metadata `{ name, version }` | `Implementation(name: ..., version: ...)` | Keep names stable for host diagnostics. |
| Tool registration | `server.registerTool(...)` or typed helper APIs such as `registerAppTool(...)` | Use MCP-safe tool names; some hosts reject `/` in names. |
| Zod/JSON Schema tool input | `JsonSchema.object(...)` helpers or `JsonObject.fromJson(rawObjectSchema)` | Use `JsonObject.fromJson(...)` for supported object-schema keywords, verify the serialized schema for unions/custom keywords, and do not pass raw `Map<String, dynamic>` values directly to `inputSchema`. |
| `StdioServerTransport` | `StdioServerTransport` | Keep stdout reserved for JSON-RPC; log to stderr. |
| Streamable HTTP server | `StreamableMcpServer` or `StreamableHTTPServerTransport` | Prefer `StreamableMcpServer` for app-level routing and session management. |

Minimal Dart server shape:

```dart
import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final server = McpServer(
    const Implementation(name: 'notes-server', version: '1.0.0'),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: const ServerCapabilitiesTools(),
      ),
    ),
  );

  server.registerTool(
    'notes_search',
    description: 'Search notes by query',
    inputSchema: JsonSchema.object(
      properties: {'query': JsonSchema.string()},
      required: ['query'],
    ),
    callback: (args, extra) async {
      final query = args['query'] as String;
      return CallToolResult.fromContent([
        TextContent(text: 'Results for $query'),
      ]);
    },
  );

  await server.connect(StdioServerTransport());
}
```

Migration checklist:

- Keep tool/resource/prompt names stable unless you intentionally want a host-visible breaking change.
- Re-check JSON Schema output for unions, enums, `const`, and `default: null` values.
- Replace Node-specific environment and filesystem assumptions with Dart `dart:io` code only when the target platform supports it.
- Add a stdio smoke test before migrating to Streamable HTTP.

## Cookbook 2: `dart_mcp` or another Dart package -> `mcp_dart`

Start by mapping protocol concepts rather than class names. Different Dart MCP packages may expose different convenience APIs.

| Migration area | What to check |
| --- | --- |
| Package import | Replace old package imports with `package:mcp_dart/mcp_dart.dart`. |
| Server/client construction | Move metadata into `Implementation` and capabilities into `McpServerOptions` / `McpClientOptions`. |
| Transports | Pick stdio for local process hosts, Streamable HTTP for remote/web/mobile, or custom transports for embedded use. |
| Errors | Use `McpError` with protocol error codes for request failures that should be visible to peers. |
| Progress/cancellation | Preserve string-or-integer progress tokens and request IDs at the protocol boundary. |
| OAuth/security | Use `OAuthClientProvider` and Streamable HTTP security options instead of ad-hoc headers where possible. |

Suggested migration order:

1. Port a minimal server/client that initializes and lists capabilities.
2. Migrate one tool with a small schema and one success/error test.
3. Migrate resources and prompts.
4. Add transport-specific tests for stdio or Streamable HTTP.
5. Only then migrate authentication, long-running tasks, progress, and cancellation.

## Cookbook 3: stdio-only server -> Streamable HTTP + OAuth-ready deployment

Use this when a local CLI server needs to become a remote service.

### Before: stdio process

```dart
final server = McpServer(
  const Implementation(name: 'local-server', version: '1.0.0'),
);

await server.connect(StdioServerTransport());
```

### After: high-level Streamable HTTP server

```dart
final httpServer = StreamableMcpServer(
  serverFactory: (sessionId) {
    return McpServer(
      const Implementation(name: 'remote-server', version: '1.0.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(
          tools: const ServerCapabilitiesTools(),
        ),
      ),
    );
  },
  host: '0.0.0.0',
  port: 3000,
  path: '/mcp',
  enableDnsRebindingProtection: true,
  allowedHosts: {'api.example.com'},
  allowedOrigins: {'https://app.example.com'},
);

await httpServer.start();
```

Deployment checklist:

- Put the MCP endpoint behind HTTPS in production.
- Configure `allowedHosts` and `allowedOrigins`; do not disable DNS rebinding protection for public deployments.
- Decide whether sessions should be stateful or stateless before exposing the endpoint.
- Add authentication before exposing user-specific or side-effecting tools.
- Keep compatibility toggles documented and temporary when migrating older clients.
- Verify `MCP-Protocol-Version`, `MCP-Session-Id`, and `Last-Event-ID` behavior with tests or manual curl/browser checks.

## Cookbook 4: older `mcp_dart` API usage -> current 2025-11-25 behavior

For code already using `mcp_dart`, start with [`doc/migration_2025_11_25_compat.md`](migration_2025_11_25_compat.md). The most important compatibility areas are:

- `tasks/cancel` now returns the final cancelled task object on the wire.
- Task and task-status wire shapes require `taskId`, `status`, `ttl`, `createdAt`, and `lastUpdatedAt`.
- Task-augmented requests require explicit `tasks.requests.*` subcapabilities, such as `tasks.requests.tools.call` for task-based tools.
- Streamable HTTP has stricter protocol-version and security validation defaults.
- JSON-RPC request IDs, cancellation request IDs, and progress tokens preserve the MCP string-or-integer wire shape.
- Sampling tool-use requests must be negotiated via `ClientCapabilities.sampling.tools`.

Run this baseline after migration:

```bash
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test
```

If your project includes examples or nested packages, run their analyzers/tests too; examples are part of the user-facing contract.
