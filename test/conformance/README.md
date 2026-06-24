# MCP Conformance

This directory contains conformance harnesses for stable MCP `2025-11-25` and
the unreleased MCP `2026-07-28` draft/RC suite. These fixtures are intentionally
separate from the cross-SDK interop tests because the official conformance
package calls hard-coded diagnostic tools, prompts, and resources.

## CI Coverage

Core CI runs the official stable `2025-11-25` and `2026-07-28` draft/RC
client/server conformance suites from `.github/workflows/test_core.yml`. The
server suites use dedicated fixtures because the official conformance package
calls hard-coded diagnostic tools, prompts, and resources.

The 2026 suite still targets a draft/RC alpha spec package. If the official
suite changes before the spec is final, record intentional temporary gaps in
`2026_rc_expected_failures.txt` or `2026_rc_client_expected_failures.txt` so CI
distinguishes known draft/RC churn from regressions.

## Stable MCP 2025-11-25

Run the stable server suite from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
```

The runner starts `mcp_2025_server.dart`, runs
`@modelcontextprotocol/conformance@0.2.0-alpha.5 server --suite all
--spec-version 2025-11-25`, and writes artifacts under
`.dart_tool/conformance/2025_server/`.

Run the stable client suite from the repository root:

```bash
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.5 client \
  --command "dart run test/conformance/mcp_2026_rc_client.dart" \
  --suite all \
  --spec-version 2025-11-25 \
  --verbose \
  -o .dart_tool/conformance/2025_client
```

The stable client suite reuses the dual-stack conformance client fixture because
the fixture negotiates whichever protocol version the conformance scenario
server offers.

## MCP 2026-07-28 Draft/RC

Run the current server baseline from the repository root:

```bash
dart run test/conformance/run_2026_rc_server_conformance.dart
```

The runner starts a local `StreamableMcpServer` in default Streamable HTTP SSE
response mode, runs the full `2026-07-28` server scenario list from
`@modelcontextprotocol/conformance@0.2.0-alpha.5` one by one with `--suite all`
and `--spec-version 2026-07-28`, and writes per-run artifacts under
`.dart_tool/conformance/2026_rc/`.

Expected failures live in `2026_rc_expected_failures.txt`. When a scenario is
fixed, remove it from that file so the baseline remains useful.

As of `@modelcontextprotocol/conformance@0.2.0-alpha.5`, the full 2026 RC server
suite has no expected failures against the Dart fixture.

Run the current client baseline from the repository root:

```bash
dart run test/conformance/run_2026_rc_client_conformance.dart
```

The client runner invokes `mcp_2026_rc_client.dart` against the conformance
package's scenario servers and writes per-run artifacts under
`.dart_tool/conformance/2026_rc_client/`.

Client expected failures live in `2026_rc_client_expected_failures.txt`.
The 2026 client wrapper is aligned with the scenarios returned by
`conformance list --client --spec-version 2026-07-28`; stable-only client
scenarios remain covered by the stable `2025-11-25` client suite above.
