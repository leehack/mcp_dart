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
bound local URL, and then runs `src/client.mjs` against it. The fixture asserts:

- TypeScript client negotiation selects the modern `2026-07-28` era.
- `server/discover` advertises `2026-07-28` and exposes cache metadata through
  the TypeScript client API.
- `tools/list` returns the Dart fixture tools with 2026 cache metadata.
- Valid `x-mcp-header` annotations survive `tools/list` and the TypeScript
  client mirrors string, integer, boolean, and nested string arguments into
  `Mcp-Param-*` headers. The Dart server validates those headers against the
  body before invoking the tool.
- `tools/call` can invoke the Dart `echo` tool over modern Streamable HTTP.
- `tools/call` can complete a 2026 `input_required` elicitation retry flow
  using the TypeScript client's registered `elicitation/create` handler.

Keep this fixture anchored to the official draft/RC behavior rather than the
preview TypeScript implementation alone. In particular, `x-mcp-header` tests use
only the draft-permitted primitive types: `string`, `integer`, and `boolean`.

Keep this as a manual, non-blocking check until the TypeScript SDK publishes a
stable 2026-compatible alpha package or the upstream PR stack lands on the
`v2-2026-07-28` branch.
