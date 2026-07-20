# MCP Conformance

This directory contains conformance harnesses for MCP 2025-11-25 and the
unreleased MCP 2026-07-28 suite. These fixtures are intentionally
separate from the cross-SDK interop tests because the official conformance
package calls hard-coded diagnostic tools, prompts, and resources.

## CI Coverage

Core CI runs the official MCP 2025-11-25 and MCP 2026-07-28 client/server
conformance suites from `.github/workflows/test_core.yml`. The server suites
use dedicated fixtures because the official conformance package calls
hard-coded diagnostic tools, prompts, and resources.

The MCP 2026-07-28 suite still targets a preview alpha conformance package. If
the official suite changes before the specification is final, record
intentional temporary gaps in `2026_07_28_expected_failures.txt` or
`2026_07_28_client_expected_failures.txt` so CI distinguishes known preview
churn from regressions.

## MCP 2025-11-25

Run the MCP 2025-11-25 server suite from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
```

The runner starts `mcp_2025_server.dart`, runs
`@modelcontextprotocol/conformance@0.2.0-alpha.9 server --suite all
--spec-version 2025-11-25`, and writes artifacts under
`.dart_tool/conformance/2025_server/`.

Run the MCP 2025-11-25 client suite from the repository root:

```bash
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.9 client \
  --command "dart run test/conformance/mcp_2026_07_28_client.dart" \
  --suite all \
  --spec-version 2025-11-25 \
  --verbose \
  -o .dart_tool/conformance/2025_client
```

The MCP 2025-11-25 client suite reuses the dual-stack conformance client fixture
because the fixture negotiates whichever protocol version the conformance
scenario server offers.

## MCP 2026-07-28

Run the current server baseline from the repository root:

```bash
dart run test/conformance/run_2026_07_28_server_conformance.dart
```

The runner starts a local `StreamableMcpServer` in default Streamable HTTP SSE
response mode, runs the full MCP `2026-07-28` server scenario list from
`@modelcontextprotocol/conformance@0.2.0-alpha.9` one by one with `--suite all`
and `--spec-version 2026-07-28`, and writes per-run artifacts under
`.dart_tool/conformance/2026_07_28/`.

Expected failures live in `2026_07_28_expected_failures.txt` as exact JSON
diagnostics. The runner accepts only the complete pinned diagnostic set with
exit code 1; a timeout, unreadable report, or different failure fails CI.

As of `@modelcontextprotocol/conformance@0.2.0-alpha.9`, the
`server-stateless` scenario is expected to fail because that published referee
predates spec PR #3002: it still requires request `clientInfo` and body
`DiscoverResult.serverInfo`. The three checked-in diagnostics must be removed
when a published conformance package includes PR #403.

Until then, reproduce the corrected `server-stateless` check against the
immutable merged PR #403 source:

```bash
dart run test/conformance/run_2026_07_28_server_conformance.dart \
  --scenario server-stateless \
  --conformance-package \
    github:modelcontextprotocol/conformance#d1c0b9591786726d8a4bec05306eb103ba6894ff \
  --expected-failures \
    test/conformance/2026_07_28_post_3002_expected_failures.txt
```

Run the current client baseline from the repository root:

```bash
dart run test/conformance/run_2026_07_28_client_conformance.dart
```

The client runner invokes `mcp_2026_07_28_client.dart` against the conformance
package's scenario servers and writes per-run artifacts under
`.dart_tool/conformance/2026_07_28_client/`.

The alpha.9 `json-schema-ref-no-deref` canary server rejects the draft protocol,
so the runner executes that exact version-independent security scenario with
`--spec-version 2025-11-25 --force`. The local MCP 2026-07-28 protocol tests
separately verify that network `$ref` values remain opaque and are preserved on
the wire.

Client expected failures live in `2026_07_28_client_expected_failures.txt`.
The MCP 2026-07-28 client wrapper is aligned with the scenarios returned by
`conformance list --client --spec-version 2026-07-28`; MCP 2025-11-25-only
client scenarios remain covered by the MCP 2025-11-25 client suite above.
As of alpha.9, the client baseline has no expected failures.
