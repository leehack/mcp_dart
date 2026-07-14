# {{name}}

A Model Context Protocol (MCP) server created with `mcp_dart`.

The generated server uses the default dual-era profile: it prefers MCP
`2026-07-28` RC discovery and retains MCP `2025-11-25` and earlier
initialization fallback. Select `McpProtocol.require2026` or
`McpProtocol.legacy` in `lib/mcp/mcp.dart` when a deployment must require one
era.

## Running the Server

```bash
dart run bin/server.dart
# or
mcp_dart serve
```

Run Streamable HTTP on loopback when testing with a browser or remote-style
client:

```bash
dart run bin/server.dart --transport http --host 127.0.0.1 --port 3000
```

Before sharing the project, run its local quality gates:

```bash
dart analyze
dart test
```

## Extending the server

Add implementations under `lib/mcp/tools/`, `lib/mcp/resources/`, or
`lib/mcp/prompts/`, then include them in the corresponding `createAll...`
function. Keep `bin/server.dart` focused on transport and process startup.
