# MCP SDK Interoperability

This page lists reproducible `mcp_dart` interoperability evidence. A row is
verified only when it links to an automated test, runnable example, or command
in this repository.

For requirement-level MCP 2025-11-25 coverage, see the
[`spec-coverage-2025-11-25.md`](spec-coverage-2025-11-25.md) matrix.
For MCP 2026-07-28 coverage, see the
[`spec-coverage-2026-07-28.md`](spec-coverage-2026-07-28.md) matrix.

## How to read the matrix

- **Verified** means the scenario is covered by an automated test or checked-in runnable example.
- **Documented recipe** means the SDK supports the shape and the repo contains guidance, but the exact cross-SDK pairing is not yet an automated interop test.
- **Planned** means the scenario is a good candidate for future coverage; do not treat it as a compatibility guarantee.

## Current matrix

| Scenario | Transport | Protocol version | Evidence | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Dart client -> Dart server | stdio | MCP 2026-07-28 with initialization-era fallback | [`test/integration/stdio_integration_test.dart`](../test/integration/stdio_integration_test.dart), [`example/server_stdio.dart`](../example/server_stdio.dart), [`example/client_stdio.dart`](../example/client_stdio.dart) | Verified | The default dual-era pair covers local process startup and tool/resource/prompt flows. |
| Strict Dart MCP 2026-07-28 client -> Dart server | stdio | MCP 2026-07-28 | [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/), [`test/example/non_credentialed_examples_smoke_test.dart`](../test/example/non_credentialed_examples_smoke_test.dart) | Verified | Requires `server/discover`, asserts the negotiated version, completes a `subscriptions/listen` resource update, and retries `input_required` with non-object structured output. |
| Dart client -> Dart server | Streamable HTTP | MCP 2025-11-25 and MCP 2026-07-28 | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`example/streamable_https/`](../example/streamable_https/) | Verified | Includes session handling, strict header validation, stale-session recovery, resumability coverage, and stable-profile examples that use `server/discover` negotiation. |
| Dart client -> Dart server | Legacy HTTP+SSE | MCP 2025-11-25 | [`test/client/sse_client_test.dart`](../test/client/sse_client_test.dart), [`test/interop/browser_legacy_sse_client_test.dart`](../test/interop/browser_legacy_sse_client_test.dart), [`example/server_sse.dart`](../example/server_sse.dart), [`example/client_sse.dart`](../example/client_sse.dart) | Verified in source | Covers endpoint discovery, same-origin redirect-free POST routing, initialization, tool listing, tool execution, clean shutdown, and real-Chrome client lifecycle behavior. HTTP+SSE is deprecated; use Streamable HTTP for new integrations. |
| Dart client -> TypeScript SDK server | stdio | MCP 2025-11-25 | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts/`](../test/interop/ts/) | Verified | Requires the TypeScript fixture to be built before running the tagged interop tests. |
| Dart client -> TypeScript SDK server | Streamable HTTP | MCP 2025-11-25 | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts/`](../test/interop/ts/) | Verified | Covers tool calls and stale preconfigured session-id recovery. |
| Dart SDK ↔ TypeScript SDK 1.30.0 | Legacy HTTP+SSE | MCP 2025-11-25 | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts/src/server.ts`](../test/interop/ts/src/server.ts), [`test/interop/ts/src/legacy_sse_client.ts`](../test/interop/ts/src/legacy_sse_client.ts) | Verified | The deprecated official TypeScript `SSEServerTransport` and `SSEClientTransport` each complete initialization, tool listing, and a tool call with the corresponding Dart peer over real loopback HTTP+SSE. |
| TypeScript SDK client -> Dart server | stdio | MCP 2025-11-25 | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | Verified | Runs the compiled TypeScript client fixture against a Dart server process and checks that an official TS client can list tools immediately after the lifecycle handshake. |
| TypeScript SDK client -> Dart server | Streamable HTTP | MCP 2025-11-25 | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | Verified | Includes official TS Streamable HTTP client lifecycle coverage, pre-`initialized` operation rejection, GET SSE streams, and `Last-Event-ID` replay behavior. |
| TypeScript SDK client -> Dart server | Streamable HTTP | MCP 2026-07-28 | [`test/interop/ts_2026_07_28/`](../test/interop/ts_2026_07_28/), [`tool/testing/run_ts_2026_07_28_interop.dart`](../tool/testing/run_ts_2026_07_28_interop.dart), [`interop_2026_07_28.yml`](../.github/workflows/interop_2026_07_28.yml) | Verified | Published `@modelcontextprotocol/client@2.0.0` negotiates the post-#3002 wire with a spec-correct Dart server and covers discovery, routing headers, tool calls, multi-round input, progress, subscriptions, and cancellation. |
| Dart MCP 2026-07-28 client -> TypeScript SDK server | Streamable HTTP | MCP 2026-07-28 | [`test/interop/ts_2026_07_28/src/server.mjs`](../test/interop/ts_2026_07_28/src/server.mjs), [`tool/testing/run_ts_2026_07_28_interop.dart`](../tool/testing/run_ts_2026_07_28_interop.dart), [`interop_2026_07_28.yml`](../.github/workflows/interop_2026_07_28.yml) | Verified | Uses published `@modelcontextprotocol/server@2.0.0` through its `createMcpHandler` entry; covers `server/discover`, `tools/list`, `tools/call`, one-time `HeaderMismatch` metadata refresh and retry, MCP 2026-07-28 `input_required`, request-stream cancellation, and post-cancellation recovery. |
| Dart client -> Python MCP server | stdio | Server-dependent | [`doc/transports.md`](transports.md#connect-to-python-server) | Documented recipe | The transport can spawn Python servers over stdio; the MCP 2025-11-25 recipe remains separate from the MCP 2026-07-28 fixture. |
| Python SDK 2.0.0 client -> Dart server | Streamable HTTP | MCP 2026-07-28 | [`test/interop/python_2026_07_28/`](../test/interop/python_2026_07_28/), [`tool/testing/run_python_2026_07_28_interop.dart`](../tool/testing/run_python_2026_07_28_interop.dart), [`interop_2026_07_28.yml`](../.github/workflows/interop_2026_07_28.yml) | Verified | Published `mcp==2.0.0` negotiates the canonical post-#3002 discovery wire and covers discovery, tool listing, and tool execution. |
| Dart MCP 2026-07-28 client -> Python SDK 2.0.0 server | Streamable HTTP | MCP 2026-07-28 | [`test/interop/python_2026_07_28/server.py`](../test/interop/python_2026_07_28/server.py), [`tool/testing/run_python_2026_07_28_interop.dart`](../tool/testing/run_python_2026_07_28_interop.dart), [`interop_2026_07_28.yml`](../.github/workflows/interop_2026_07_28.yml) | Verified | Uses the official Python SDK `mcp==2.0.0` server and covers discovery, protocol selection, `tools/list`, and `tools/call`. |
| Dart SDK ↔ Python SDK 2.0.0 | Legacy HTTP+SSE | MCP 2025-11-25 | [`test/interop/python_2026_07_28/legacy_sse_client.py`](../test/interop/python_2026_07_28/legacy_sse_client.py), [`test/interop/python_2026_07_28/legacy_sse_server.py`](../test/interop/python_2026_07_28/legacy_sse_server.py), [`tool/testing/run_python_2026_07_28_interop.dart`](../tool/testing/run_python_2026_07_28_interop.dart), [`interop_2026_07_28.yml`](../.github/workflows/interop_2026_07_28.yml) | Verified | Published `mcp==2.0.0` retains the deprecated SSE client and server APIs. Both directions negotiate MCP 2025-11-25 and complete initialization, tool listing, and a tool call over real loopback HTTP+SSE. |
| Dart browser client -> Dart server | Streamable HTTP | MCP 2025-11-25 and MCP 2026-07-28 | [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart), [`tool/testing/run_browser_2026_07_28_interop.dart`](../tool/testing/run_browser_2026_07_28_interop.dart) | Verified | A real Chrome client completes 12 tool-list requests and 12 tool calls in each profile over cross-origin Streamable HTTP. It also proves MCP 2026-07-28 request-stream cancellation and recovery. The MCP 2025-11-25 case waits for response-stream reconnect timers and guards against browser connection-slot exhaustion. |
| Flutter Web example -> Dart server | Streamable HTTP | MCP 2026-07-28 | [`example/flutter_http_client/test/browser_e2e_test.dart`](../example/flutter_http_client/test/browser_e2e_test.dart), [`tool/testing/run_flutter_web_example_e2e.dart`](../tool/testing/run_flutter_web_example_e2e.dart), [`test_core.yml`](../.github/workflows/test_core.yml) | Verified | The example's real service layer runs in Chrome and completes connection, 12 tool-list requests, 12 tool calls, expected RPC-error recovery, reconnect, a post-reconnect request, and disconnect. Deterministic widget tests cover the UI separately. Flutter Web cannot spawn stdio servers. |
| MCP Apps host/client metadata | stdio or Streamable HTTP | MCP 2026-07-28 plus `io.modelcontextprotocol/ui` extension | [`doc/mcp-apps.md`](mcp-apps.md), [`example/mcp_apps_helpers_server.dart`](../example/mcp_apps_helpers_server.dart), [`test/types/mcp_ui_test.dart`](../test/types/mcp_ui_test.dart), [`test/server/mcp_ui_test.dart`](../test/server/mcp_ui_test.dart) | Verified | Verified coverage is limited to SDK metadata helpers, serialization, and checked-in examples; host rendering behavior varies by host, so verify UI metadata against your target host. |
| OAuth-protected Streamable HTTP client | Streamable HTTP | MCP 2025-11-25 | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/oauth_client.ts`](../test/interop/ts/src/oauth_client.ts), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`example/authentication/`](../example/authentication/), [`doc/transports.md`](transports.md) | Verified | Covers official TypeScript Streamable HTTP client OAuth discovery, PKCE S256 authorization redirect, resource-bound token exchange, bearer reconnect, plus local Host/Origin and auth-gating deployment scenarios. |

## Running interop checks locally

The TypeScript interop tests use compiled fixtures under `test/interop/ts/dist/`.

```bash
# From repository root
dart pub get
cd test/interop/ts
npm install
npm run build
cd ../../..
dart test --tags interop
```

If the compiled fixtures are missing, local test runs skip the interop groups; CI should fail when required fixtures are unavailable.

The TypeScript MCP 2026-07-28 fixture uses the published TypeScript SDK 2.0.0
packages:

```bash
# From repository root
cd test/interop/ts_2026_07_28
npm ci
cd ../../..
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=dart-to-ts
```

That direction verifies the Dart client -> published TypeScript server path.
The published 2.0.0 client includes the post-#3002 identity shape, so CI
also requires the reverse direction to pass:

```bash
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=ts-to-dart
```

The Dart-client path includes an `input_required` elicitation retry,
request-stream cancellation observed by the TypeScript server, and successful
post-cancellation tool calls in addition to discovery and normal tool calls.

The `Run MCP 2026-07-28 Interop` workflow covers relevant PRs, manual dispatch,
and a daily schedule on `main`.

The official Python SDK 2.0.0 fixture runs each direction independently:

```bash
python3 -m venv .dart_tool/python-2026-interop
.dart_tool/python-2026-interop/bin/python -m pip install \
  -r test/interop/python_2026_07_28/requirements.txt
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart \
  --direction=dart-to-python
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart \
  --direction=python-to-dart
```

Both directions are required. The reverse path also probes Dart's anonymous
`server/discover` wire response directly before the Python client connects, so
canonical identity metadata cannot regress behind a peer-side fallback.

The browser runner exercises the web implementation in Chrome against the Dart
conformance server and a dedicated CORS-aware legacy SSE fixture:

```bash
dart run tool/testing/run_browser_2026_07_28_interop.dart
```

It covers cross-origin preflight and response headers, then completes 12 tool
list requests and 12 tool calls in both the MCP 2026-07-28 default and MCP
2025-11-25 legacy profiles. It also covers MCP 2026-07-28 request cancellation
and follow-up recovery. A separate deprecated HTTP+SSE scenario proves endpoint
discovery, an exact JSON-RPC POST, the inbound SSE response, close notification,
and rejection of sends or restarts after client-side close. Browser Fetch does
not guarantee that cancelling its response reader is immediately observable as
a peer-side TCP disconnect. The short Streamable HTTP legacy reconnect delay
ensures completed POST response streams do not silently consume Chrome
connection slots.

Run the Flutter Web example's real service integration separately:

```bash
dart run tool/testing/run_flutter_web_example_e2e.dart
```

This starts the MCP 2026-07-28 conformance server and runs the example's
service layer in Chrome through connection, repeated tool requests, RPC-error
recovery, reconnect, a post-reconnect request, and disconnect. The ordinary
Flutter test suite covers UI behavior with deterministic widget tests.

The CLI spec conformance gate covers raw-wire negative cases that do not need a
cross-SDK fixture, including MCP 2025-11-25 checks and MCP 2026-07-28
stateless/discovery/task-extension checks:

```bash
cd packages/mcp_dart_cli
dart pub get
dart run bin/mcp_dart.dart conformance --suite all --json
```

## Adding a new matrix row

When adding a new interoperability claim:

1. Prefer an automated fixture under `test/interop/`.
2. Link the exact test, example, or manual command in the matrix.
3. Name the transport and protocol version explicitly.
4. Document unsupported or host-specific behavior as a caveat rather than leaving it implied.
5. Keep security-sensitive values (tokens, callback secrets, signed URLs) out of logs and examples.

## Known gaps worth tracking

- Broader Python SDK coverage for subscriptions, cache behavior, and
  multi-round-trip input once those server surfaces stabilize.
- Broader reverse-path TypeScript SDK server coverage for MCP 2026-07-28
  subscriptions/listen, cacheable result fields, and other streaming/result
  paths should follow as the TypeScript SDK server surface stabilizes.
- Host-specific MCP Apps rendering compatibility notes.
- More OAuth-protected remote server scenarios beyond the checked-in examples.
- A broader compatibility table once additional SDKs expose published MCP
  2025-11-25 fixtures.
- Request-scoped cancellation against the Python SDK and additional peer
  implementations. Published TypeScript SDK 2.0.0 is verified in both
  directions.
