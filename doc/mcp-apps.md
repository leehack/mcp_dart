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

## Example

- TypeScript-style helper example: [`example/mcp_apps_helpers_server.dart`](../example/mcp_apps_helpers_server.dart)
- Manual metadata example: [`example/mcp_apps_metadata_server.dart`](../example/mcp_apps_metadata_server.dart)
