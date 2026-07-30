# Contributing to mcp_dart

Thanks for helping improve the Dart and Flutter MCP ecosystem.

## Before opening an issue

- Use a private vulnerability report for security-sensitive findings; see
  [SECURITY.md](SECURITY.md).
- Search existing issues and include the affected package version, Dart or
  Flutter version, platform, transport, negotiated MCP version, and a minimal
  reproduction when reporting a bug.
- Keep experimental extension behavior separate from Core MCP behavior.

Maintainers commit to initial issue triage within two business days. Triage
means classifying the report and deciding whether it has enough information to
act; it does not promise resolution within that window.

Issues use the MCP SDK tiering taxonomy:

- Type: `bug`, `enhancement`, or `question`.
- Status: `needs confirmation`, `needs repro`, `ready for work`,
  `good first issue`, or `help wanted`.
- Priority, when actionable: `P0`, `P1`, `P2`, or `P3`.

`P0` is reserved for a CVSS 7.0-or-higher vulnerability or a failure that
prevents connection establishment, message exchange, or use of the core tools,
resources, and prompts primitives. Maintainers commit to resolving it through a
released fix or safe mitigation that removes user exposure within seven
calendar days. Other priorities describe impact, not queue order:
`P1` is a significant defect affecting many users, `P2` is a moderate defect or
valuable feature, and `P3` is a low-impact improvement.

## Proposing a change

1. Open or reference an issue for behavior changes that affect public APIs,
   protocol semantics, compatibility, dependencies, or the minimum Dart SDK.
2. Create a focused branch from the latest `main`.
3. Preserve public API and MCP 2025-11-25 compatibility unless a breaking
   change has been explicitly approved and documented according to
   [VERSIONING.md](VERSIONING.md).
4. Update implementation, tests, examples, and user-facing documentation
   together.
5. Open a pull request against `main` with the behavior change, compatibility
   impact, and exact validation listed in its description.

Do not add a dependency or raise a package's minimum Dart version without
maintainer approval. Explain the need, alternatives, compatibility impact, and
transitive footprint first. See [DEPENDENCY_POLICY.md](DEPENDENCY_POLICY.md).

## Validation

Run from the repository root:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

For CLI changes, also run `dart analyze` and `dart test` from
`packages/mcp_dart_cli/`. Public API, transport, or protocol changes require the
affected official conformance and published TypeScript/Python interoperability
paths documented in [doc/interoperability.md](doc/interoperability.md).

The CLI has additional contribution notes in
[`packages/mcp_dart_cli/CONTRIBUTING.md`](packages/mcp_dart_cli/CONTRIBUTING.md).

## Releases

`main` is the only release source. Releases are prepared through reviewed pull
requests and repository automation; contributors must not create or move
release tags. The complete process is documented in
[`tool/release/README.md`](tool/release/README.md).
