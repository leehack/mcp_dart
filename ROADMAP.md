# mcp_dart roadmap

The project is targeting MCP SDK Tier 1. Tier 1 is an ongoing commitment to
complete non-experimental protocol coverage, 100% applicable conformance,
timely maintenance, comprehensive documentation, and predictable releases. It
is not claimed until the MCP SDK Working Group assigns it.

## Current baseline

- Stable `mcp_dart 2.3.0` and `mcp_dart_cli 0.2.0` releases.
- Complete Core client/server support for MCP 2026-07-28 with an explicit
  MCP 2025-11-25 compatibility profile.
- The official Tier 1 scorecard passes 20/20 server scenarios and 32/32 client
  scenarios for the applicable dated specifications, with no expected-failure
  allowance.
- Published TypeScript SDK 2.0.0 and Python SDK 2.0.0 interoperability runs in
  both directions.
- Protocol coverage, examples, and known gaps are tracked in
  [`doc/spec-coverage-2026-07-28.md`](doc/spec-coverage-2026-07-28.md).

Experimental features and extensions, including Tasks and MCP Apps, remain
outside the Tier 1 Core claim.

## Tier 1 work

| Work item | Exit criterion | Status |
| --- | --- | --- |
| Publish maintenance, security, dependency, and versioning policies | Policies are linked from the README and pass the official policy evaluation | In progress |
| Adopt the MCP issue taxonomy | All required type, status, and priority labels exist; every open issue is triaged | In progress: labels complete; 2/3 open issues triaged; issue #177 requires explicit approval |
| Audit the canonical documentation inventory | All 48 non-experimental features have user-facing prose and a runnable or near-runnable example | Complete in source: 48/48; publish the additive legacy SSE client in the next approved minor release |
| Join the official SDK conformance matrix | The conformance repository can build and run `mcp_dart` client and server fixtures by repository/ref | Planned |
| Produce an official scorecard | Current stable client and server each score 100% for applicable dated scenarios | Complete |
| Request Tier 1 assignment | A public advancement issue includes the scorecard, policy, documentation, release, and maintenance evidence | Planned |

## Latest deterministic scorecard

The conformance portion of the official repository's `tier-check` command was
run on 2026-07-30 against `mcp_dart` source at
`85af40702c25da39d30eb6673414fd079b6273e1`. The added legacy SSE client has no
current executable official scenario and is validated separately. Policy,
label, triage, release, and specification-tracking checks query GitHub `main`;
the checker cannot evaluate unpushed local policy files.

| Check | Result |
| --- | --- |
| Server conformance | 20/20, 100% |
| Client conformance | 32/32, 100% |
| Required issue labels | 12/12 |
| Open-issue triage | 2/3, 66.7%; issue #177 is protected from automatic changes |
| Open `P0` issues | 0 |
| Stable SDK release | `2.3.0` |
| Latest-spec release gap | 0 days |
| Deterministic implied tier | Tier 2; Tier 1 blocker: triage |

The deterministic result does not assign a tier. Publishing the source-level
legacy SSE client, the remaining policy judgment, official SDK-matrix
integration, public advancement request, and SDK Working Group approval are
separate gates.

## Specification release commitment

For each new dated MCP specification:

1. Open a tracking issue when the release candidate and applicable conformance
   scenarios are available.
2. Review every non-experimental Core delta and agree a public implementation
   timeline based on its complexity before the final specification release.
3. Publish compatible prereleases early enough for cross-SDK testing.
4. Require the supported client and server conformance suites, minimum-Dart
   lanes, public API comparison, examples, and published-peer interoperability
   to pass without unexplained exclusions.
5. Publish the stable SDK only after the final inputs and compatibility
   decisions are documented.

If a feature cannot be completed on the agreed timeline, the tracking issue
must name the blocker and revised plan before the specification is released;
the project must not continue to claim Tier 1 silently.

## Ongoing maintenance

- Triage issues within two business days.
- Resolve validated `P0` bugs within seven calendar days through a released fix
  or documented mitigation that removes user exposure.
- Review automated dependency updates weekly and security alerts when received.
- Keep the current stable and claimed legacy protocol profiles in CI.
- Treat any applicable conformance regression as release-blocking and restore
  green status before four continuous weeks elapse.

Progress is tracked through GitHub issues and pull requests. This file records
durable commitments and exit criteria rather than speculative feature ideas.
