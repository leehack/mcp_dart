# Dependency update policy

`mcp_dart` minimizes direct and transitive dependencies and treats dependency
changes as compatibility changes, not routine lockfile churn.

## Cadence

Dependabot checks GitHub Actions, Dart/pub, npm, and Python fixtures weekly
using [`.github/dependabot.yml`](.github/dependabot.yml). Compatible updates are
grouped by ecosystem so CI and interoperability evidence cover the complete
resolution.

Security alerts are reviewed when received. A reachable vulnerability with
CVSS 7.0 or higher follows the `P0` response commitment in
[SECURITY.md](SECURITY.md); lower-severity findings are prioritized by
reachability, exploitability, and user impact.

## Review requirements

Every dependency update must:

- preserve the SDK's Dart 3.4 minimum and the CLI's Dart 3.12 minimum unless a
  separate, explicitly approved compatibility change says otherwise;
- keep public API and supported MCP wire behavior backward compatible;
- pass the affected analyzer, test, example, conformance, interoperability, and
  publish-dry-run gates;
- document a new direct dependency's purpose, alternatives, license,
  maintenance health, and transitive footprint;
- update exact fixture pins and lockfiles together when they represent the same
  tested peer.

The repository may temporarily hold an update when an upstream release is
incompatible with the supported Dart/Flutter range, an official peer has not
published the required artifact, or the update breaks conformance. Each
Dependabot ignore must state its reason and removal condition in
`.github/dependabot.yml`.

## Protocol and test inputs

MCP specification commits, the experimental Tasks checkout, the official
conformance package, JSON Schema suites, and published TypeScript/Python
fixtures are reviewed inputs rather than ordinary application dependencies.
They are pinned to exact reviewed versions and advanced only with their
schemas, normative prose, tests, compatibility decisions, and documentation.
Green installation alone is not sufficient evidence.

Dependency constraints and minimum SDK versions are never raised solely to
silence tooling. When a change is necessary, it is proposed with migration
guidance and released according to [VERSIONING.md](VERSIONING.md).
