# MCP 2026-07-28 TypeScript SDK Interop

This fixture is an experimental smoke test for the unreleased MCP 2026-07-28
path against the official TypeScript SDK work in progress.

It is intentionally separate from `test/interop/ts`, which tracks the published
stable TypeScript SDK and MCP 2025-11-25 behavior. The fixture pins published
`@modelcontextprotocol/client@2.0.0-beta.4` and
`@modelcontextprotocol/server@2.0.0-beta.4` packages. Dart client to TypeScript
server passes against that pin. The published TypeScript client predates spec
PR #3002, so its reverse direction records the exact negotiation gap while a
TypeScript SDK #2513 preview is used for forward-looking bidirectional checks.

## Run

From the repository root:

```bash
cd test/interop/ts_2026_07_28
npm ci
cd ../../..
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=dart-to-ts
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=ts-to-dart \
  --expect-published-ts-client-gap
```

The published-beta reverse path first probes
`test/conformance/mcp_2026_07_28_server.dart` directly and requires
`server/discover` to advertise `2026-07-28`, omit body `serverInfo`, and expose
identity in `_meta["io.modelcontextprotocol/serverInfo"]`. It then accepts only the
known beta.4 `ERA_NEGOTIATION_FAILED` message. An unexpected pass or any other
failure is an error.

Install the TypeScript SDK #2513 preview artifact without changing the checked-in
beta.4 pin, then run the reverse path without the expected-gap flag:

```bash
(
  fixture=test/interop/ts_2026_07_28
  trap 'npm --prefix "$fixture" ci' EXIT
  npm --prefix "$fixture" install --no-save --package-lock=false \
    https://pkg.pr.new/@modelcontextprotocol/client@2513
  dart run tool/testing/run_ts_2026_07_28_interop.dart \
    --direction=ts-to-dart
)
```

The `EXIT` trap restores the published beta.4 fixture even if the preview run
fails. With the preview,
`src/client.mjs` asserts:

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

The Dart-to-TypeScript direction starts `src/server.mjs` with the TypeScript beta
`createMcpHandler` entry and runs a Dart stable-profile client against it. That
direction asserts `server/discover` negotiation, `tools/list`, `tools/call`,
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
MCP 2026-07-28 draft path. Do not restore obsolete Dart body output to make an
older peer pass, and do not treat package publication alone as enough to re-pin
without rerunning both explicit directions and removing stale expected-gap
handling.
