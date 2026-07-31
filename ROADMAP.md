# mcp_dart roadmap

The project is targeting MCP SDK Tier 1. Tier 1 is an ongoing commitment to
complete non-experimental protocol coverage, 100% applicable conformance,
timely maintenance, comprehensive documentation, and predictable releases.
The repository reports the deterministic result of its pinned self-assessment
but does not claim a formal tier until eligibility and assignment are confirmed
through the
[MCP SDK tiering process](https://modelcontextprotocol.io/community/sdk-tiers).

## Current baseline

- Stable `mcp_dart 2.4.0` and `mcp_dart_cli 0.2.0` releases.
- Complete Core client/server support for MCP 2026-07-28 with an explicit
  MCP 2025-11-25 compatibility profile.
- Exact-head CI passes the published official conformance package for both
  supported protocol profiles and both client/server roles, with no
  expected-failure allowance.
- Published TypeScript SDK 2.0.0 and Python SDK 2.0.0 interoperability runs in
  both directions.
- Protocol coverage, examples, and known gaps are tracked in
  [`doc/spec-coverage-2026-07-28.md`](doc/spec-coverage-2026-07-28.md).

Experimental features and extensions, including Tasks and MCP Apps, remain
outside the Tier 1 Core claim.

## Tier 1 work

| Work item | Exit criterion | Status |
| --- | --- | --- |
| Publish maintenance, security, dependency, and versioning policies | Policies are linked from the README and pass the official policy evaluation | Complete: the official checker finds all required policy signals; final qualitative judgment remains with reviewers |
| Adopt the MCP issue taxonomy | All required type, status, and priority labels exist; every open issue is triaged | Complete: 12/12 labels and 100% current open-issue triage |
| Audit the project-maintained Tier 1 documentation inventory | All 48 items mapped from the published non-experimental tier requirements have user-facing prose and a runnable or near-runnable example | Complete: published `mcp_dart 2.4.0` covers all 48 items |
| Join the official SDK conformance matrix | The conformance repository can build and run `mcp_dart` client and server fixtures by repository/ref | Planned |
| Resolve SDK tiering eligibility | The SDK Working Group confirms whether an external community SDK can receive a tier or accepts `mcp_dart` into the official SDK roster | Planned: the tiering page describes community-driven SDKs, while the [SDK Working Group charter](https://modelcontextprotocol.io/community/working-groups/sdk) excludes third-party SDKs outside the MCP organization |
| Produce a repository evidence scorecard | Current client and server fixtures each score 100% for applicable dated scenarios | Complete: the pinned self-assessment returns Tier 1 on deterministic checks; official matrix integration remains planned |
| Request Tier 1 assignment | A public advancement issue includes the scorecard, policy, documentation, release, and maintenance evidence | Planned after eligibility is resolved |

## Latest repository self-assessment

The official conformance repository's `tier-check` command was run on
2026-07-30 against `main` commit
`5f83a552ea27280d63b29dfc8a1898ced466d8a2`, using conformance repository
commit `49103de6ed70804e940637bf3e9e29e4a3f54e64`. The full invocation exercised
the Dart client and server fixtures instead of skipping conformance. The added
legacy SSE client has no current executable official scenario and is validated
through Dart, published TypeScript SDK, published Python SDK, and real-browser
interoperability instead.

| Check | Result |
| --- | --- |
| Published conformance in exact-head CI | MCP 2025-11-25 and MCP 2026-07-28, client and server roles, 100% with no expected failures |
| `tier-check` scored server conformance | 20/20, 100% |
| `tier-check` scored client conformance | 15/15, 100% |
| `tier-check` informational MCP 2026-07-28 conformance | Server 20/20; client Core 7/7 and Auth 25/25 |
| Required issue labels | 12/12 |
| Open-issue triage | 100% within two business days; 2 open issues, median 0 hours |
| Open `P0` issues | 0 |
| Published stable SDK release | `mcp_dart 2.4.0` |
| Published stable documentation inventory | `mcp_dart 2.4.0` is 48/48 |
| Latest-spec release gap | 0 days |
| Self-assessment result | Tier 1; all deterministic checks pass |

The self-assessment result does not assign a formal tier. Qualitative
documentation, policy, and roadmap judgment, SDK eligibility, official
SDK-matrix integration, a public advancement request, and SDK Working Group
approval remain separate gates. The deprecated legacy SSE client is published
for backward compatibility and remains outside the MCP 2026-07-28 Core claim.
The current triage score also does not erase that issue #177 was historically
labeled outside the two-business-day target; that exception must be disclosed
in any external review.

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
