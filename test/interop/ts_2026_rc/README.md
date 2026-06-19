# TypeScript SDK 2026 RC Interop

This fixture is an experimental smoke test for the unreleased MCP
`2026-07-28` draft/RC path against the official TypeScript SDK work in
progress.

It is intentionally separate from `test/interop/ts`, which tracks the published
stable TypeScript SDK and MCP `2025-11-25` behavior. The fixture pins a
`pkg.pr.new` client preview from TypeScript SDK PR #2327 for the modern
Streamable HTTP `Mcp-Name` header support needed to interoperate with the Dart
2026 RC server. It also installs `@modelcontextprotocol/server@2.0.0-alpha.2`
for a reverse-path diagnostic, but the server alpha is not yet a strict 2026
interoperability gate.

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
- `notifications/progress` callbacks arrive for a long-running tool call and
  report monotonic progress from `0` to `100`.
- Raw Streamable HTTP requests with missing or mismatched
  `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`, and `Mcp-Param-*` headers
  are rejected with the current draft `HeaderMismatch` error code `-32020`.
- Raw Streamable HTTP requests for removed 2026 core RPCs such as `ping` are
  rejected with JSON-RPC `Method not found`.
- Raw Streamable HTTP requests for unsupported protocol versions are rejected
  with the current draft `UnsupportedProtocolVersion` error code `-32022` and
  include `requested` and `supported` version data.
- `subscriptions/listen` returns an acknowledgment before list-change
  notifications and tags subscription notifications with
  `io.modelcontextprotocol/subscriptionId`.
- Closing a 2026 HTTP SSE response stream cancels the in-flight Dart server
  request without sending `notifications/cancelled`.

The runner also starts `src/server.mjs` and attempts a Dart preview client
against the TypeScript server alpha. That reverse path is currently diagnostic:
the fixture shims `server/discover` because the TS server alpha does not answer
that mandatory 2026 method yet, and the Dart client then reports the current TS
alpha `tools/list` gap where stateless results omit `resultType`.

Keep this fixture anchored to the official draft/RC behavior rather than the
preview TypeScript implementation alone. In particular, `x-mcp-header` tests use
only the draft-permitted primitive types: `string`, `integer`, and `boolean`.
When TypeScript preview behavior conflicts with the draft, keep the draft as the
assertion source and document the preview gap near the test.

Keep this as a manual, non-blocking check until the TypeScript SDK publishes a
stable 2026-compatible alpha package or the upstream PR stack lands on the
`v2-2026-07-28` branch.
