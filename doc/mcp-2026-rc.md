# MCP 2026-07-28 Draft/RC Transition Guide

`mcp_dart` defaults to the latest stable MCP specification, currently
`2025-11-25`. MCP `2026-07-28` draft/RC support is available through explicit
protocol profiles so applications can adopt the draft without changing stable
deployments.

## Client opt-in

Use the preview profile when you want the client to prefer MCP `2026-07-28`
draft/RC and fall back to stable MCP servers when discovery is unavailable:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(
    protocol: McpProtocol.preview2026,
  ),
);
```

`McpClientOptions(protocol: McpProtocol.preview2026)` enables
`server/discover`, sends the `2026-07-28` draft/RC stateless request metadata,
and falls back to the legacy `initialize` flow when the peer looks like a
stable-only MCP server.

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

Use the server preview profile to advertise and accept MCP `2026-07-28` draft/RC
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
| `McpProtocol.preview2026` | No | Tries `server/discover`, then falls back to `initialize` | Advertises stable and `2026-07-28` draft/RC protocol versions |
| `McpProtocol.require2026` | No | Requires `2026-07-28` draft/RC discovery | Advertises only stateless `2026-07-28` draft/RC protocol versions |

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

## 2026-07-28 Draft-Only API Areas

The following features are MCP `2026-07-28` draft/RC behavior and should be
used only after opting into a `2026-07-28` profile:

- `server/discover` negotiation and stateless per-request metadata.
- `subscriptions/listen` stateless notification streams.
- Multi-result tool/resource/prompt flows such as `input_required`.
- MCP Tasks extension flows using `io.modelcontextprotocol/tasks`.
- Non-object `structuredContent` values via `JsonValue` and broader server
  `outputJsonSchema` shapes.
- Stateless result metadata such as `resultType`, `ttlMs`, and `cacheScope`.

For non-object tool results, keep the stable object-root APIs for stable MCP
callers and use the explicitly named draft APIs:

```dart
server.registerTool(
  'array-result',
  outputJsonSchema: JsonSchema.array(items: JsonSchema.string()),
  callback: (args, extra) {
    return CallToolResult.fromStructuredArray(['alpha', 'beta']);
  },
);

final result = await client.callTool(
  const CallToolRequest(name: 'array-result'),
);
final items = result.structuredContentJson?.asArray;
```

The draft/RC API surface may still change before the official spec release.
Keep applications on the stable profile unless they specifically need draft
behavior.

## Dev Release Checklist

Use dev releases for MCP `2026-07-28` draft/RC testing until the official spec
is released. Dev versions must include a prerelease suffix such as
`2.3.0-dev.0` so pub.dev and GitHub treat them as preview builds.

Before creating tags from `dev/2026-07-28-rc`, run:

```sh
dart analyze
dart pub publish --dry-run
dart pub global run pana --no-warning
dart run tool/validate_cli_publish.dart
```

Publish the SDK package first by running the `Create Release` workflow for
`mcp_dart` from `dev/2026-07-28-rc`. The publish workflow runs a dry-run check
before `dart pub publish --force`, and prerelease versions are marked as GitHub
prereleases rather than repository latest releases.

After `mcp_dart` is available on pub.dev, validate the CLI against the published
SDK package:

```sh
dart run tool/validate_cli_publish.dart --published-sdk
```

Then run the `Create Release` workflow for `mcp_dart_cli` from
`dev/2026-07-28-rc`. The CLI publish workflow removes the local SDK override
before publishing so users receive the published SDK dependency.
