# MCP Conformance

This directory contains conformance harnesses for MCP 2025-11-25 and
MCP 2026-07-28. These fixtures are intentionally
separate from the cross-SDK interop tests because the official conformance
package calls hard-coded diagnostic tools, prompts, and resources.

## CI Coverage

Core CI runs the official MCP 2025-11-25 and MCP 2026-07-28 client/server
conformance suites from `.github/workflows/test_core.yml`. The server suites
use dedicated fixtures because the official conformance package calls
hard-coded diagnostic tools, prompts, and resources.

The suites pin the published alpha conformance package because no final package
is available. Alpha.11 freezes the scored and unscored scenario sets for each
dated revision. CI uses those requirement sets directly and fails when any
scored scenario fails or cannot be measured. Extensions, post-release
additions, and pending scenarios still run for visibility but remain unscored
according to the official requirement files.

## MCP 2025-11-25

Run the MCP 2025-11-25 server suite from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
```

The runner starts `mcp_2025_server.dart`, runs
`@modelcontextprotocol/conformance@0.2.0-alpha.11 server --requirements
2025-11-25`, and writes artifacts under
`.dart_tool/conformance/2025_server/`.

Run the MCP 2025-11-25 client suite from the repository root:

```bash
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.11 client \
  --command "dart run test/conformance/mcp_2026_07_28_client.dart" \
  --requirements 2025-11-25 \
  --verbose \
  -o .dart_tool/conformance/2025_client
```

The MCP 2025-11-25 client suite reuses the dual-stack conformance client fixture
because the fixture negotiates whichever protocol version the conformance
scenario server offers.

The frozen 2025 requirements currently score 30 server and 18 client
scenarios; all pass. Three unscored server scenarios also pass. Seven unscored
client extension or post-release scenarios currently fail and do not affect
the dated Core score.

## MCP 2026-07-28

Run the current server baseline from the repository root:

```bash
dart run test/conformance/run_2026_07_28_server_conformance.dart
```

The runner starts a local `StreamableMcpServer` in default Streamable HTTP SSE
response mode, runs the frozen MCP `2026-07-28` server requirements from
`@modelcontextprotocol/conformance@0.2.0-alpha.11`, and writes artifacts under
`.dart_tool/conformance/2026_07_28/`.

All 37 scored server scenarios pass. The official runner also reports 13
unscored extension or pending scenarios; nine current Tasks extension
scenarios fail without affecting the dated Core score.

Run the current client baseline from the repository root:

```bash
dart run test/conformance/run_2026_07_28_client_conformance.dart
```

The client runner invokes `mcp_2026_07_28_client.dart` against the conformance
package's scenario servers and writes per-run artifacts under
`.dart_tool/conformance/2026_07_28_client/`.

All 32 scored client scenarios pass, including the network-`$ref` security
canary. All seven current unscored extension or post-release scenarios fail
without affecting the dated Core score. MCP 2025-11-25-only client scenarios
remain covered by the separate frozen requirement run above.

Pass `--scenario <name>` to a Dart wrapper for focused debugging. That mode
selects the matching wire revision directly and does not represent the frozen
Tier assessment.
