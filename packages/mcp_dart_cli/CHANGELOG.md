## 0.1.8

- Make `mcp_dart inspect` capability listing respect the server's advertised
  capabilities instead of probing unsupported list methods.
- Improve pub.dev metadata with a clearer description, documentation and issue
  links, topics, platform declarations, and package page summary copy.
- Update the CLI dependency constraint to `mcp_dart ^2.2.0`.
- Add `mcp_dart conformance` with built-in JSON-RPC and protocol-version fixture checks, deterministic JSON-RPC fuzz cases, exact-case filtering, and JSON output for CI/scripts.
- Add `mcp_dart conformance --suite spec` for MCP 2025-11-25 lifecycle,
  capability, elicitation, task-metadata, and progress-token raw-wire checks.
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
