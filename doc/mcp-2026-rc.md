# MCP 2026 RC Transition Guide

`mcp_dart` defaults to the latest stable MCP specification, currently
`2025-11-25`. MCP `2026-07-28` RC support is available through explicit
protocol profiles so applications can adopt the draft without changing stable
deployments.

## Client opt-in

Use the preview profile when you want the client to prefer MCP `2026-07-28` RC
and fall back to stable MCP servers when discovery is unavailable:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(
    protocol: McpProtocol.preview2026,
  ),
);
```

`McpClientOptions(protocol: McpProtocol.preview2026)` enables
`server/discover`, sends the 2026 stateless request metadata, and falls back to
the legacy `initialize` flow when the peer looks like a stable-only MCP server.

Use the strict profile for conformance tests or deployments where fallback is
not acceptable:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(
    protocol: McpProtocol.require2026,
  ),
);
```

## Server opt-in

Use the server preview profile to advertise and accept MCP `2026-07-28` RC
stateless requests:

```dart
final server = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
  options: const McpServerOptions(
    protocol: McpProtocol.preview2026,
  ),
);
```

`McpServerOptions()` remains stable by default and does not advertise draft
stateless protocol versions.

## Profile summary

| Profile | Default? | Client behavior | Server behavior |
| ------- | -------- | --------------- | --------------- |
| `McpProtocol.stable` | Yes | Uses stable `initialize` | Advertises stable protocol versions |
| `McpProtocol.preview2026` | No | Tries `server/discover`, then falls back to `initialize` | Advertises stable and 2026 RC protocol versions |
| `McpProtocol.require2026` | No | Requires 2026 RC discovery | Advertises only stateless 2026 RC protocol versions |

## Low-level overrides

The existing low-level options remain available for advanced callers:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(
    protocolVersion: draftProtocolVersion2026_07_28,
    useServerDiscover: true,
  ),
);
```

Prefer the `protocol` profile unless you need to target a specific protocol
version for tests or interoperability debugging.

## 2026-only API areas

The following features are MCP `2026-07-28` RC behavior and should be used only
after opting into a 2026 profile:

- `server/discover` negotiation and stateless per-request metadata.
- `subscriptions/listen` stateless notification streams.
- Multi-result tool/resource/prompt flows such as `input_required`.
- MCP Tasks extension flows using `io.modelcontextprotocol/tasks`.
- Non-object `structuredContent` values and broader tool `outputSchema` shapes.
- Stateless result metadata such as `resultType`, `ttlMs`, and `cacheScope`.

The RC API surface may still change before the official spec release. Keep
applications on the stable profile unless they specifically need RC behavior.
