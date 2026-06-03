# MCP Conformance

This directory contains conformance harnesses for stable MCP 2025-11-25 and the
unreleased MCP 2026 RC suite. These fixtures are intentionally separate from the
cross-SDK interop tests because the official conformance package calls
hard-coded diagnostic tools, prompts, and resources.

## CI Coverage

Core CI runs the official stable 2025 and 2026 RC client/server conformance
suites from `.github/workflows/test_core.yml`. The server suites use dedicated
fixtures because the official conformance package calls hard-coded diagnostic
tools, prompts, and resources.

The 2026 suite still targets an RC/alpha spec package. If the official suite
changes before the spec is final, record intentional temporary gaps in
`2026_rc_expected_failures.txt` or `2026_rc_client_expected_failures.txt` so CI
distinguishes known RC churn from regressions.

## Stable MCP 2025-11-25

Run the stable server suite from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
```

The runner starts `mcp_2025_server.dart`, runs
`@modelcontextprotocol/conformance@0.2.0-alpha.1 server --suite all
--spec-version 2025-11-25`, and writes artifacts under
`.dart_tool/conformance/2025_server/`.

Run the stable client suite from the repository root:

```bash
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.1 client \
  --command "dart run test/conformance/mcp_2026_rc_client.dart" \
  --suite all \
  --spec-version 2025-11-25 \
  --verbose \
  -o .dart_tool/conformance/2025_client
```

The stable client suite reuses the dual-stack conformance client fixture because
the fixture negotiates whichever protocol version the conformance scenario
server offers.

## MCP 2026 RC

Run the current server baseline from the repository root:

```bash
dart run test/conformance/run_2026_rc_server_conformance.dart
```

The runner starts a local `StreamableMcpServer` with JSON stateless responses
enabled, runs the draft server scenarios from
`@modelcontextprotocol/conformance@0.2.0-alpha.1` one by one, and writes per-run
artifacts under `.dart_tool/conformance/2026_rc/`.

Expected failures live in `2026_rc_expected_failures.txt`. When a scenario is
fixed, remove it from that file so the baseline remains useful.

Run the current client baseline from the repository root:

```bash
dart run test/conformance/run_2026_rc_client_conformance.dart
```

The client runner invokes `mcp_2026_rc_client.dart` against the conformance
package's scenario servers and writes per-run artifacts under
`.dart_tool/conformance/2026_rc_client/`.

Client expected failures live in `2026_rc_client_expected_failures.txt`.
