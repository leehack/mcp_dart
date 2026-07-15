# Examples

These examples are runnable from a repository checkout or the published
package archive. The default SDK profile prefers MCP `2026-07-28` and falls
back to initialization-era peers; strict and legacy examples opt into one era
explicitly.

Run these commands from the package root.

## Strict MCP 2026-07-28

The client starts its paired server and exercises `server/discover`,
`subscriptions/listen`, `input_required`, and non-object structured output:

```bash
dart run example/mcp_2026_07_28/client.dart
```

[Client source](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/mcp_2026_07_28/client.dart)
and
[server source](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/mcp_2026_07_28/server.dart).

## Default dual-era

The stdio client starts its paired server, lists capabilities, calls a tool,
reads a resource, and gets a prompt:

```bash
dart run example/client_stdio.dart
```

[Stdio client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/client_stdio.dart)
and
[stdio server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/server_stdio.dart).

For Streamable HTTP, run these in separate terminals:

```bash
dart run example/streamable_https/server_streamable_https.dart
dart run example/streamable_https/client_streamable_https.dart
```

[Streamable HTTP server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/streamable_https/server_streamable_https.dart)
and
[client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/streamable_https/client_streamable_https.dart).

## MCP 2025-11-25 and earlier compatibility

The
[interactive task client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/simple_task_interactive_client.dart)
and
[server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/simple_task_interactive_server.dart),
[elicitation server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/elicitation_http_server.dart),
and
[SSE server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/server_sse.dart)
intentionally demonstrate retained initialization-era behavior.

## Integrations

- [Authentication and OAuth](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/authentication/README.md)
- [Anthropic client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/anthropic-client/README.md)
- [Gemini client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/gemini-client/README.md)
- [Safe fetch server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/fetch-server/README.md)
- [Flutter client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/flutter_http_client/README.md)
- [Jaspr browser client](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/jaspr-client/README.md)
- [MCP Apps helpers](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/mcp_apps_helpers_server.dart)
- [MCP Apps metadata server](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/example/mcp_apps_metadata_server.dart)

## Validation

CI runs credential-free process smokes for stdio, strict MCP 2026-07-28, a
Streamable HTTP tool flow against the high-level server, and representative
legacy and MCP Apps paths. It tests and compiles the Anthropic, Gemini, and
fetch packages, builds the Jaspr production bundle, and runs the Flutter Web
service integration in Chrome through repeated tool requests, RPC-error
recovery, and reconnect. Flutter widget tests cover the UI separately.
Live provider and OAuth calls require credentials or external services; Jaspr
browser and native-device sessions remain manual.

See the complete
[examples guide](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/examples.md)
for setup, security boundaries, and additional recipes.
