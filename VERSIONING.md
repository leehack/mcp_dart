# Versioning and compatibility policy

`mcp_dart` and `mcp_dart_cli` are independently versioned packages. The SDK
uses semantic versioning. The CLI remains on the `0.x` line and treats minor
releases as potentially breaking until it reaches `1.0.0`.

## SDK compatibility

For `mcp_dart`:

- Patch releases contain backward-compatible fixes and documentation updates.
- Minor releases add backward-compatible APIs and protocol support.
- Major releases may contain approved breaking changes.
- Prereleases use Dart-compatible suffixes such as `-dev.1` and are not
  production-stable contracts.

A breaking SDK change includes:

- removing or incompatibly changing a public API;
- changing an existing default in a way that breaks valid applications;
- dropping a supported MCP initialization version;
- changing established wire behavior contrary to a previously supported
  specification;
- raising the minimum Dart SDK or a dependency constraint so existing
  supported applications can no longer resolve the package.

Adding support for a new dated MCP specification is not itself breaking when
the existing profiles and initialization versions remain available.

## Deprecation and migration

Public APIs are deprecated with Dart's `@Deprecated` annotation and migration
guidance before removal whenever protocol correctness and security permit.
Deprecated MCP features are surfaced according to the official feature
lifecycle, while explicit legacy profiles preserve supported older wire
behavior.

Approved breaking changes require:

- a major SDK version;
- a changelog section naming the affected APIs and behavior;
- a migration guide or focused migration section;
- public API compatibility and multi-protocol tests that make the boundary
  explicit.

An immediate security or specification-correctness fix may narrow unsafe
behavior without a deprecation window. The release notes must explain the risk,
the affected versions, and the safe migration.

## Release communication

Every release has an exact version heading in the relevant changelog, an
immutable Git tag and GitHub release, and package metadata that identifies the
source repository. Stable releases are built only from `main` through the
reviewed process in [`tool/release/README.md`](tool/release/README.md).

Protocol profiles are versioned independently from package releases.
Applications should select `McpProtocol.stable`, `McpProtocol.legacy`, or
`McpProtocol.require2026` instead of inferring wire behavior from the package
version.
