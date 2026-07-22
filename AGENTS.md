# mcp_dart Agent Guidelines

Use this file for durable, repository-specific rules. Keep detailed procedures
in focused docs and runbooks.

## Priorities

1. MCP and JSON-RPC specification correctness.
2. Backward compatibility and cross-SDK interoperability.
3. Simple, maintainable code.
4. Evidence-backed delivery: tests, examples, CI, and clean review threads.

## Repository shape

- SDK: `lib/`, public barrel `lib/mcp_dart.dart`, minimum Dart 3.4.
- CLI: `packages/mcp_dart_cli/`, minimum Dart 3.12.
- Tests: `test/` and package-local `test/` directories.
- Release automation: `.github/workflows/` and `tool/release/`.
- Release process details: `tool/release/README.md` and
  `doc/mcp-2026-07-28-release-runbook.md`.

## Engineering principles

- **KISS**: Prefer the smallest clear design that preserves protocol behavior.
  Avoid speculative features, hidden normalization, and clever control flow.
- **SOLID**: Keep types and modules cohesive, make dependencies and capability
  boundaries explicit, and extend behavior without destabilizing existing APIs.
- **DRY**: Keep protocol constants, version parsing, schemas, and release rules
  in one source of truth. Reuse shared behavior when copies must stay identical;
  do not introduce an abstraction merely to remove a few obvious lines.
- Minimize direct and transitive dependencies. Do not add a dependency or raise
  a package's minimum Dart version without explicit human approval. Before
  requesting approval, document the need, alternatives, compatibility impact,
  and transitive footprint.
- Optimize measured or structurally clear hot paths. Do not trade correctness
  or readability for unproven micro-optimizations.
- Preserve public API compatibility unless a breaking change is explicitly
  approved and documented with migration guidance.

## Protocol quality bar

- Treat the official MCP specification as authoritative. Convenience APIs must
  not distort wire-level JSON-RPC/MCP semantics.
- Preserve request IDs, metadata, method names, capability flags, error codes,
  and transport-specific behavior unless the specification permits otherwise.
- Distinguish advertised capabilities from runtime support and validate both.
- Keep lower-level protocol behavior observable and testable when adding
  ergonomic helpers.
- When a spec version is new or ambiguous, encode the compatibility decision in
  regression tests and cite the spec or rationale in focused documentation.

## Dart conventions

- Use explicit, null-safe types; avoid `dynamic` without a concrete reason.
- Document public APIs with `///`, use trailing commas, and prefer `const`.
- Order imports as Dart SDK, package, then relative imports; sort each group.
- Return `Future<void>` from asynchronous operations that callers may await.
- Use `McpError` for protocol errors, `StateError` for invalid state, and
  `ArgumentError` for invalid caller input. Do not broadly swallow errors.

## Working and verification flow

1. Inspect the relevant implementation, tests, public API, and specification.
2. Make a focused change using the simplest compatible design.
3. Add success, failure, malformed-input, and compatibility regressions as
   appropriate.
4. Run, from the repository root:

   ```bash
   dart format .
   dart analyze
   dart test
   ```

5. For CLI changes, also run `dart analyze` and `dart test` from
   `packages/mcp_dart_cli/`.
6. Treat examples as contracts. Verify affected nested Dart/Flutter examples
   when changing public APIs or protocol flows.
7. For SDK behavior or public API changes, run a representative MCP client and
   server through public package APIs as users would. Cover affected transports
   and do not rely only on mocks or `lib/src` imports.
8. For protocol changes, run the relevant official MCP conformance suites and
   pinned spec/schema audits used by CI. Never weaken a conformance expectation
   merely to make a test pass; reconcile failures with the official spec.
9. For PR work, keep the diff focused, monitor CI, and resolve every actionable
   review thread before reporting readiness.
10. Never merge a PR without explicit user approval.

## Documentation and releases

- Update user-facing documentation and migration guidance in the same PR as a
  public API, behavior, or release-process change.
- Keep changelog entries concise and user-facing. Put implementation details,
  validation logs, and maintainer notes in the PR or focused docs.
- `main` is the only release source. Checked-in release-facing links remain on
  `main`; isolated publish candidates rewrite them to immutable release tags.
- Prepare publications in a PR targeting `main` with the `release-prep` label.
  Version changes select the SDK, CLI, or both. Merging that PR authorizes the
  automatic release, so obtain explicit user approval immediately before
  merging.
- Never create, move, or push release tags manually. Use the documented recovery
  path in `tool/release/README.md` for an existing exact tag and commit.

## Keeping this file current

- At the end of relevant work, promote a session learning here only when it is
  durable, repository-specific, actionable, and likely to prevent repeated
  mistakes.
- Integrate new guidance into an existing rule and remove stale or redundant
  text. Do not append session summaries, PR numbers, transient status, or long
  procedures.
- Keep commands and invariants here; keep explanations and operational detail in
  focused documentation linked above.
- Review this file when tooling, minimum SDKs, public compatibility policy, or
  the release process changes. Concision is part of correctness.
