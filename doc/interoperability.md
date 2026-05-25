# MCP SDK Interoperability

This page tracks the interoperability evidence that `mcp_dart` currently carries against other MCP SDKs and hosts. It is intentionally conservative: a row is marked as verified only when it links to a test, example, or reproducible command in this repository.

## How to read the matrix

- **Verified** means the scenario is covered by an automated test or checked-in runnable example.
- **Documented recipe** means the SDK supports the shape and the repo contains guidance, but the exact cross-SDK pairing is not yet an automated interop test.
- **Planned** means the scenario is a good candidate for future coverage; do not treat it as a compatibility guarantee.

## Current matrix

| Scenario | Transport | Protocol version | Evidence | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Dart client -> Dart server | stdio | `2025-11-25` | [`test/integration/stdio_integration_test.dart`](../test/integration/stdio_integration_test.dart), [`example/server_stdio.dart`](../example/server_stdio.dart), [`example/client_stdio.dart`](../example/client_stdio.dart) | Verified | Covers local process startup, tool/resource/prompt flow, and request/response handling. |
| Dart client -> Dart server | Streamable HTTP | `2025-11-25` | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`example/streamable_https/`](../example/streamable_https/) | Verified | Includes session handling, strict header validation, stale-session recovery, and resumability coverage. |
| Dart client -> TypeScript SDK server | stdio | `2025-11-25` | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts/`](../test/interop/ts/) | Verified | Requires the TypeScript fixture to be built before running the tagged interop tests. |
| Dart client -> TypeScript SDK server | Streamable HTTP | `2025-11-25` | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts/`](../test/interop/ts/) | Verified | Covers tool calls and stale preconfigured session-id recovery. |
| TypeScript SDK client -> Dart server | stdio | `2025-11-25` | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | Verified | Runs the compiled TypeScript client fixture against a Dart server process and checks that an official TS client can list tools immediately after the lifecycle handshake. |
| TypeScript SDK client -> Dart server | Streamable HTTP | `2025-11-25` | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | Verified | Includes official TS Streamable HTTP client lifecycle coverage, pre-`initialized` operation rejection, GET SSE streams, and `Last-Event-ID` replay behavior. |
| Dart client -> Python MCP server | stdio | Server-dependent | [`doc/transports.md`](transports.md#connect-to-python-server) | Documented recipe | The transport can spawn Python servers over stdio, but this repo does not yet include an automated Python SDK fixture. |
| Flutter/Web client -> Dart server | Streamable HTTP | `2025-11-25` | [`example/flutter_http_client/`](../example/flutter_http_client/), [`doc/flutter-recipes.md`](flutter-recipes.md) | Documented recipe | Flutter Web cannot spawn stdio servers; use Streamable HTTP or another browser-safe transport. |
| MCP Apps host/client metadata | stdio or Streamable HTTP | `2025-11-25` plus `io.modelcontextprotocol/ui` extension | [`doc/mcp-apps.md`](mcp-apps.md), [`example/mcp_apps_helpers_server.dart`](../example/mcp_apps_helpers_server.dart), [`test/types/mcp_ui_test.dart`](../test/types/mcp_ui_test.dart), [`test/server/mcp_ui_test.dart`](../test/server/mcp_ui_test.dart) | Verified | Verified coverage is limited to SDK metadata helpers, serialization, and checked-in examples; host rendering behavior varies by host, so verify UI metadata against your target host. |
| OAuth-protected Streamable HTTP client | Streamable HTTP | `2025-11-25` | [`example/authentication/`](../example/authentication/), [`doc/transports.md`](transports.md) | Documented recipe | See the authentication examples for OAuth2/PKCE and GitHub MCP server flows. |

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

## Adding a new matrix row

When adding a new interoperability claim:

1. Prefer an automated fixture under `test/interop/`.
2. Link the exact test, example, or manual command in the matrix.
3. Name the transport and protocol version explicitly.
4. Document unsupported or host-specific behavior as a caveat rather than leaving it implied.
5. Keep security-sensitive values (tokens, callback secrets, signed URLs) out of logs and examples.

## Known gaps worth tracking

- Automated Python SDK fixture coverage.
- Host-specific MCP Apps rendering compatibility notes.
- More OAuth-protected remote server scenarios beyond the checked-in examples.
- A broader compatibility table once additional SDKs expose stable 2025-11-25 fixtures.
