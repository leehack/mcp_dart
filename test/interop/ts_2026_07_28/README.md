# MCP 2026-07-28 TypeScript SDK Interop

This fixture is an experimental smoke test for the unreleased MCP 2026-07-28
path against the official TypeScript SDK work in progress.

It is intentionally separate from `test/interop/ts`, which tracks the published
stable TypeScript SDK and MCP 2025-11-25 behavior. The fixture pins published
`@modelcontextprotocol/client@2.0.0-beta.4` and
`@modelcontextprotocol/server@2.0.0-beta.4` packages. The TypeScript client path
is a draft-aligned smoke check against the Dart MCP 2026-07-28 server. The
reverse Dart client path is a draft-aligned smoke check against the TypeScript
beta server.

## Run

From the repository root:

```bash
cd test/interop/ts_2026_07_28
npm ci
cd ../../..
dart run tool/testing/run_ts_2026_07_28_interop.dart
```

The runner starts `test/conformance/mcp_2026_07_28_server.dart`, waits for its
bound local URL, and then runs `src/client.mjs` against it. The fixture asserts:

- TypeScript client negotiation selects MCP 2026-07-28.
- `server/discover` advertises MCP 2026-07-28 and exposes cache metadata through
  the TypeScript client API.
- `tools/list` returns the Dart fixture tools with MCP 2026-07-28 cache
  metadata.
- Valid `x-mcp-header` annotations survive `tools/list` and the TypeScript
  client mirrors string, integer, boolean, and nested string arguments into
  `Mcp-Param-*` headers. The Dart server validates those headers against the
  body before invoking the tool.
- `tools/call` can invoke the Dart `echo` tool over modern Streamable HTTP.
- `tools/call` can complete an MCP 2026-07-28 `input_required` elicitation retry
  flow using the TypeScript client's registered `elicitation/create` handler.
- `notifications/progress` callbacks arrive for a long-running tool call and
  report monotonic progress from `0` to `100`.
- Raw Streamable HTTP requests with missing or mismatched
  `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`, and `Mcp-Param-*` headers
  are rejected with the current draft `HeaderMismatch` error code `-32020`.
- Raw Streamable HTTP requests for removed MCP 2026-07-28 core RPCs such as
  `ping` are rejected with JSON-RPC `Method not found`.
- Raw Streamable HTTP requests for unsupported protocol versions are rejected
  with the current draft `UnsupportedProtocolVersion` error code `-32022` and
  include `requested` and `supported` version data.
- `subscriptions/listen` returns an acknowledgment before list-change
  notifications and tags subscription notifications with
  `io.modelcontextprotocol/subscriptionId`.
- An `AbortController` closes an MCP 2026-07-28 HTTP SSE response, the Dart
  server observes cancellation without `notifications/cancelled`, and a
  follow-up status call succeeds.

The runner also starts `src/server.mjs` with the TypeScript beta
`createMcpHandler` entry and runs a Dart stable-profile client against it. That
reverse path asserts `server/discover` negotiation, `tools/list`, `tools/call`,
a one-time `HeaderMismatch` recovery that refreshes `tools/list` before retrying
with the discovered `Mcp-Param-*` header, an MCP 2026-07-28 `input_required`
elicitation retry, request-stream cancellation observed through the TypeScript
server's Web Request `AbortSignal`, and a successful post-cancellation tool call.
Failures are treated as interop failures.

Keep this fixture anchored to the official preview behavior rather than the
TypeScript beta implementation alone. In particular, `x-mcp-header` tests use
only the draft-permitted primitive types: `string`, `integer`, and `boolean`.
When TypeScript beta behavior conflicts with the draft, keep the draft as the
assertion source and document the beta gap near the test.

CI runs this fixture in the dedicated `Run MCP 2026-07-28 Interop` workflow for
relevant PRs, daily scheduled drift checks, and manual dispatch.
Keep the fixture pinned to a published TypeScript SDK beta that exposes the
MCP 2026-07-28 draft path and passes this runner; do not treat package
publication alone as enough to re-pin without rerunning the interop check.
