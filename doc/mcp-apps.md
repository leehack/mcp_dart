# MCP Apps Support

This guide shows how to use MCP Apps metadata with `mcp_dart`.

## What Is Included

`mcp_dart` provides:

- Extension capability negotiation through `ClientCapabilities.extensions` and `ServerCapabilities.extensions`
- Typed helpers for MCP Apps metadata (`McpUiToolMeta`, `McpUiResourceMeta`, `McpUiCsp`, `McpUiPermissions`)
- Constants for the extension and MIME type (`mcpUiExtensionId`, `mcpUiResourceMimeType`)
- TypeScript-style server helpers (`registerAppTool`, `registerAppResource`, `getUiCapability`)

## Advertise Client Support

Hosts/clients can advertise MCP Apps support in `initialize`:

```dart
final client = McpClient(
  const Implementation(name: 'my-host', version: '1.0.0'),
  options: McpClientOptions(
    capabilities: ClientCapabilities(
      extensions: withMcpUiExtension(),
    ),
  ),
);
```

You can check negotiated support with typed helpers:

```dart
if (getUiCapability(client.getServerCapabilities())
        ?.supportsMimeType(mcpUiResourceMimeType) ??
    false) {
  // Server supports text/html;profile=mcp-app
}
```

## Expose MCP Apps Metadata from a Server

Register a `ui://` resource and attach `_meta.ui` metadata to both the tool and the UI content.

Use tool names that follow the MCP naming guidance (for example, `weather_get_current`).
Some hosts reject names containing `/`.

```dart
final server = McpServer(
  const Implementation(name: 'weather-server', version: '1.0.0'),
  options: McpServerOptions(
    capabilities: ServerCapabilities(
      resources: const ServerCapabilitiesResources(),
      tools: const ServerCapabilitiesTools(),
      extensions: withMcpUiExtension(),
    ),
  ),
);

const resourceUri = 'ui://weather/dashboard.html';

registerAppTool(
  server,
  'weather_get_current',
  McpUiAppToolConfig(
    description: 'Get current weather',
    inputSchema: JsonSchema.object(
      properties: {
        'location': JsonSchema.string(),
      },
      required: ['location'],
    ),
    meta: const {
      'ui': {
        'resourceUri': resourceUri,
        'visibility': ['model', 'app'],
      },
    },
  ),
  (args, extra) async {
    final location = args['location'] as String;
    const temperatureC = 22;
    const condition = 'Partly Cloudy';

    return CallToolResult(
      content: [
        TextContent(
          text: 'Current weather for $location: $temperatureC C, $condition.',
        ),
        const ResourceLink(
          uri: resourceUri,
          name: 'Weather Dashboard UI',
          mimeType: mcpUiResourceMimeType,
        ),
      ],
      structuredContent: {
        'location': location,
        'temperatureC': temperatureC,
        'condition': condition,
      },
    );
  },
);

registerAppResource(
  server,
  'Weather Dashboard UI',
  resourceUri,
  const McpUiAppResourceConfig(
    description: 'UI resource for weather tool output',
    meta: {
      'ui': {
        'csp': {
          'connectDomains': ['https://api.example.com'],
        },
        'prefersBorder': true,
      },
    },
  ),
  (uri, extra) async => ReadResourceResult(
    contents: [
      TextResourceContents(
        uri: uri.toString(),
        mimeType: mcpUiResourceMimeType,
        text: '<!doctype html><html><body>Dashboard</body></html>',
        meta: const McpUiResourceMeta(prefersBorder: true).toMeta(),
      ),
    ],
  ),
);
```

## Typed Access to Incoming Metadata

```dart
final tools = await client.listTools();
for (final tool in tools.tools) {
  final ui = tool.mcpUiMeta;
  if (ui?.resourceUri != null) {
    // Tool is associated with an MCP Apps UI resource
  }
}
```

`Resource`, `ResourceTemplate`, and `ResourceContents` also expose `mcpUiMeta` helpers when `_meta.ui` is present.

## Runnable examples

- TypeScript-style helper example: [`example/mcp_apps_helpers_server.dart`](../example/mcp_apps_helpers_server.dart)
- Manual metadata example: [`example/mcp_apps_metadata_server.dart`](../example/mcp_apps_metadata_server.dart)

Run either example as a stdio MCP server:

```bash
dart run example/mcp_apps_helpers_server.dart
```

Then inspect it from another terminal or from an MCP host that understands MCP Apps metadata:

```bash
mcp_dart inspect -- dart run example/mcp_apps_helpers_server.dart
```

## Polished example patterns

### Weather dashboard card

Use this pattern when a tool returns normal model-readable text plus a UI resource for hosts that can render MCP Apps:

1. Register a `ui://weather/dashboard.html` resource with `mcpUiResourceMimeType`.
2. Attach `McpUiResourceMeta` with `prefersBorder` and a narrow CSP.
3. Return both `TextContent` and a `ResourceLink` from the tool.
4. Put machine-readable values in `structuredContent` so non-UI hosts still receive useful data.

The checked-in helper example follows this pattern and keeps the HTML self-contained for easy host testing.

### Form or approval UI

Use this pattern when the UI should collect confirmation before a side-effecting action:

- Keep the actual side effect in a tool call; the HTML resource should only present state and instructions.
- Use `visibility: ['app']` for UI-only affordances when the model does not need the resource text.
- Add `ToolAnnotations(destructiveHint: true)` or other annotations to the tool where appropriate.
- Make the tool handler validate all arguments again; never trust host-rendered form controls as the only validation layer.

### Resource-link update flow

Use this pattern when tool results should point users to an updated resource:

- Return a `ResourceLink` with a stable URI and `mcpUiResourceMimeType`.
- Keep resource content idempotent and safe to re-read.
- If the UI depends on remote assets, include only the minimum required domains in `csp.resourceDomains` and `csp.connectDomains`.

## Host compatibility notes

MCP Apps metadata is extension-based, so hosts can differ in what they render:

- A host that does not advertise `io.modelcontextprotocol/ui` support should still receive useful text or structured content.
- Some hosts reject tool names that contain `/`; prefer snake-case names such as `weather_get_current`.
- Keep CSP entries explicit and minimal. Avoid wildcard domains in production examples.
- Treat `_meta.ui` as host-facing metadata, not as an authorization boundary. Server-side handlers must still enforce authentication and permissions.
- Verify final rendering against each target host before claiming host-specific support.
