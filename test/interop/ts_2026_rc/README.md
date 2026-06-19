# TypeScript SDK 2026 RC Interop

This fixture is an experimental smoke test for the unreleased MCP
`2026-07-28` draft/RC path against the official TypeScript SDK work in
progress.

It is intentionally separate from `test/interop/ts`, which tracks the published
stable TypeScript SDK and MCP `2025-11-25` behavior. The published split
TypeScript packages still do not advertise `2026-07-28`, so this fixture pins a
`pkg.pr.new` preview package from TypeScript SDK PR #2327. That PR includes the
modern Streamable HTTP `Mcp-Name` header support needed to interoperate with the
Dart 2026 RC server.

## Run

From the repository root:

```bash
cd test/interop/ts_2026_rc
npm install
cd ../../..
dart run tool/testing/run_ts_2026_rc_interop.dart
```

The runner starts `test/conformance/mcp_2026_rc_server.dart`, waits for its
bound local URL, and then runs `src/client.mjs` against it. The smoke asserts:

- TypeScript client negotiation selects the modern `2026-07-28` era.
- `tools/list` returns the Dart fixture tools.
- `tools/call` can invoke the Dart `echo` tool over modern Streamable HTTP.

Keep this as a manual, non-blocking check until the TypeScript SDK publishes a
stable 2026-compatible alpha package or the upstream PR stack lands on the
`v2-2026-07-28` branch.

