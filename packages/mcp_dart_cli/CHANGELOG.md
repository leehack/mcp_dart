## 0.2.0-dev.1

- Update the dev CLI package to depend on `mcp_dart ^2.3.0-dev.1`.
- Refresh built-in 2026 RC conformance checks for the current draft error
  codes and cacheable `server/discover` behavior.
- Keep CLI standalone binary release automation current with GitHub runner and
  artifact action updates.
- Add installer fallback behavior for resolving the latest stable CLI GitHub
  release when the GitHub Releases API is unavailable.

## 0.2.0-dev.0

- Prepare the CLI for the MCP `2026-07-28` draft/RC SDK dev line with a
  dependency on `mcp_dart ^2.3.0-dev.0`.
- Keep the local monorepo SDK override in `pubspec_overrides.yaml` so published
  CLI pubspec metadata does not expose path overrides.
- Point dev CLI package documentation metadata at the `dev/2026-07-28-rc`
  branch and document explicit prerelease activation.
- Document that generated projects still resolve the stable SDK by default and
  need an explicit `mcp_dart ^2.3.0-dev.0` dependency for draft/RC testing.

## 0.1.9

- Add `mcp_dart inspect-server` for structured MCP server inspection reports
  covering handshake, capabilities, ping, tools, resources, resource templates,
  prompts, completions, logging, task-capable tool calls, notifications,
  Streamable HTTP session handling, and OAuth protected-resource metadata
  discovery, with optional JSON probe configs for app-specific tool, resource,
  prompt, completion, and task arguments.
- Add `mcp_dart inspect-client` as a stdio MCP harness for inspecting client
  initialization, advertised capabilities, primitive discovery/call behavior,
  and active roots/sampling/elicitation request handling.
- Add `mcp_dart trace` as a stdio proxy that forwards client/server traffic and
  writes a JSON trace report with raw frames, parsed messages, ids, methods,
  timings, server stderr, and malformed-frame errors.
- Add `mcp_dart list-tools` and `mcp_dart call-tool` as scriptable MCP
  debugging commands for Dart, TypeScript, Python, and other spec-compatible
  servers.
- Add `mcp_dart skills install/print` with a bundled MCP developer agent skill.
- Add CLI e2e interop coverage against official TypeScript/Python MCP SDK
  servers and clients, Streamable HTTP, and published TypeScript filesystem and
  Python time MCP servers.
- Clarify that `inspect-server` and `inspect-client` are the live inspection
  workflow, while `conformance` is a built-in SDK/CLI regression fixture suite.
- Add standalone GitHub release binary build automation and one-line installer
  scripts for users without the Dart SDK.
- Extend `mcp_dart update` to upgrade standalone GitHub release binaries.

## 0.1.8

- Make `mcp_dart inspect` capability listing respect the server's advertised
  capabilities instead of probing unsupported list methods.
- Improve pub.dev metadata with a clearer description, documentation and issue
  links, topics, platform declarations, and package page summary copy.
- Update the CLI dependency constraint to `mcp_dart ^2.2.0`.
- Add `mcp_dart conformance` with built-in JSON-RPC and protocol-version fixture checks, deterministic JSON-RPC fuzz cases, exact-case filtering, and JSON output for CI/scripts.
- Add `mcp_dart conformance --suite spec` for MCP 2025-11-25 lifecycle,
  capability, elicitation, task-metadata, and progress-token raw-wire checks.
- Extend `mcp_dart conformance --suite spec` with MCP 2026-07-28 RC checks for
  draft protocol advertisement, `server/discover`, stateless result/cache
  defaults, removed core RPCs, stateless HTTP parameter header encoding, and
  task subscription missing-capability errors.
- Add conformance coverage for `sampling.context` negotiation before deprecated
  sampling `includeContext` values are sent.
- Add conformance coverage that aborted `initialize` requests do not emit
  `notifications/cancelled`.
- Add conformance coverage that `notifications/cancelled` payloads require a
  valid `requestId`.
- Add conformance coverage that `notifications/subscriptions/acknowledged`
  typed parsers reject mismatched JSON-RPC wrapper constants.
- Add JSON-RPC fixture conformance coverage for rejecting envelopes that mix
  request/notification `method` fields with response `result` or `error`
  fields, including direct typed parser coverage.
- Document `mcp_dart conformance --suite all` as the stable non-fuzz coverage
  gate used by CI.

## 0.1.7

- Fix `mcp_dart inspect` for local projects whose `pubspec.yaml` package name is quoted.
- Parse local project package names with the YAML parser shared by `inspect` and `serve`.
- Update the CLI and simple template dependency constraint to `mcp_dart ^2.1.1`.

## 0.1.6

- Update to mcp_dart 1.2.0

## 0.1.5

- **`update` command**:
  - Update the CLI to the latest version via `mcp_dart update`.
  - Automatic update checks on command execution.

## 0.1.4


- **`create` command**:
  - Improved package name inference when creating a project from a path (e.g. `mcp_dart create ./my-project`).
  - Internal refactoring for better testability.

## 0.1.3

- **`create` command**:
  - Optional project path argument: `mcp_dart create <project_name> [path]`
  - General code cleanup and improvements

## 0.1.2

- **`serve` command** for running MCP servers:
  - Supports stdio and HTTP transport (`--transport http`)
  - `--watch` flag for automatic server restart on file changes

- **`doctor` command** for checking project configuration:
  - Dynamic verification that starts the server and tests all tools, resources, and prompts
  - Detailed status output for each check

- **`inspect` command** for interacting with MCP servers:
  - `--url` flag for connecting via Streamable HTTP
  - `--wait` flag to wait for server notifications
  - `--resource` and `--prompt` flags for reading resources and prompts
  - `sampling/createMessage` request handler for LLM-based tools
  - Detailed tool schema information in capabilities listing

## 0.1.1

- Add GitHub Actions workflows for mcp_dart_cli

## 0.1.0

- Initial release of the `mcp_dart_cli` package.
- `create` command for creating new MCP servers from templates.
