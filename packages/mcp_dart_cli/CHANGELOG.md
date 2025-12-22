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
