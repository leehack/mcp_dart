# CLI Inspection Coverage

`inspect-server` and `inspect-client` connect to real targets and report
observed protocol behavior. `inspect` remains the interactive primitive tool,
`trace` records a real stdio session, and `conformance` runs checked-in SDK/CLI
regression fixtures.

The CLI is a practical inspector, not a formal certification suite. A passing
report means the exercised behavior passed; it does not prove every normative
MCP requirement or every input value.

Reports and traces can contain credentials, tool arguments/results, prompt or
resource content, and raw protocol frames. Restrict file permissions, never
commit or upload reports unreviewed, and delete them when no longer needed.

## Current coverage

| Area | Exercised behavior | Important limit |
| --- | --- | --- |
| Lifecycle and JSON-RPC | Stateless discovery or legacy initialization, implementation metadata, capabilities, legacy ping, IDs, and well-formed observed frames | Removed 2026 methods are reported without probing them; raw negative cases live primarily in `conformance` |
| Transports | Live stdio and Streamable HTTP, session/protocol metadata, Origin behavior, GET/DELETE probes, stdio tracing | No automatic resumability/redelivery scenario |
| Tools | List shape, unique names, schemas, configured calls, structured output validation | Does not invoke every ordinary tool without explicit arguments |
| Resources | Resources/templates listing, URI shape, configured read, optional subscribe/unsubscribe | Reads and subscriptions require explicit probe configuration |
| Prompts | List shape, arguments, configured `prompts/get` | Prompt retrieval requires explicit probe configuration |
| Completions | Configured prompt-argument completion when advertised | Completion requires explicit probe configuration |
| Client roots, sampling, elicitation | Records capabilities; probes legacy clients only with explicit `inspect-client --active-probes` | Active probes can expose roots, incur model cost, or open UI; stateless clients use 2026 MRTR |
| Logging, progress, notifications | Logging level, observed notifications, numeric/non-decreasing progress | Does not trigger every list-change notification |
| Cancellation | Task cancellation through configured probes | General request cancellation is not actively inspected |
| Authorization | Same-origin protected-resource and authorization-server discovery, bearer challenges, PKCE S256 metadata | Server-advertised cross-origin OAuth URLs are reported but not followed; no credentialed token exchange |
| Tasks | List, configured task tool call, status/result, structured output, optional cancellation | Does not force every status transition or notification |
| 2025/2026 metadata | Preserves SDK-modeled titles, icons, descriptions, task and schema fields | Live inspection does not validate every metadata field or all JSON Schema 2020-12 semantics |

## Evidence

The CLI end-to-end suite covers Dart fixtures, official TypeScript and Python
SDK fixtures, a TypeScript Streamable HTTP server, published filesystem/time
servers, and TypeScript/Python clients connected to `inspect-client`.

Repository-wide evidence is tracked in:

- [`test/`](../../../test/)
- [MCP interoperability](../../../doc/interoperability.md)
- [MCP 2025-11-25 coverage](../../../doc/spec-coverage-2025-11-25.md)
- [MCP 2026-07-28 coverage](../../../doc/spec-coverage-2026-07-28.md)

## Good next probes

- Streamable HTTP replay and redelivery.
- Credentialed OAuth flows using caller-supplied secrets.
- General cancellation and list-change triggers.
- Broader task transition and metadata validation.
- More raw-wire negative cases where a high-level client would normalize the
  malformed input before it reaches the target.
