# mcp_dart_cli

CLI for creating Model Context Protocol (MCP) servers in Dart.

## Installation

```bash
dart pub global activate mcp_dart_cli
```

## Usage

### Create a new project

```bash
mcp_dart create <project_name> [directory]
```

Or simply specify the directory and let the CLI infer the project name:

```bash
mcp_dart create path/to/my_project
```

If `directory` is omitted, the project will be created in the current directory with the name `<project_name>`.


### Create from a specific template

You can use a local path, a Git URL, or a GitHub tree URL as a template.

```bash
# From a local path
mcp_dart create <project_name> --template path/to/template

# From a Git repository
mcp_dart create <project_name> --template https://github.com/username/repo.git

# From a Git repository with a specific ref and path
mcp_dart create <project_name> --template https://github.com/username/repo.git#ref:path/to/brick

# From a GitHub repository using short syntax
mcp_dart create <project_name> --template owner/repo/path/to/brick@ref

# From a specific path in a GitHub repository (tree URL)
mcp_dart create <project_name> --template https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple
```

## Commands

- `create`: Creates a new MCP server project.
- `serve`: Runs the MCP server in the current directory.
- `doctor`: Checks the project for common issues and verifies connectivity.
- `inspect`: Interacts with an MCP server (local or external).
- `update`: Updates the CLI to the latest version.

### Doctor

Run `mcp_dart doctor` in your project directory to check for configuration issues and verify that tools/resources/prompts are reachable.

```bash
mcp_dart doctor
```

### Inspect

Use `mcp_dart inspect` to interact with an MCP server by listing capabilities or executing tools, resources, and prompts.

**Local Project:**

Run inside an MCP Dart project directory:

```bash
# List all capabilities
mcp_dart inspect

# Execute a tool
mcp_dart inspect --tool add --json-args '{"a": 1, "b": 2}'

# Read a resource
mcp_dart inspect --resource manifest://app

# Get a prompt
mcp_dart inspect --prompt greeting --json-args '{"name": "World"}'
```

**External Server (via Command):**

Connect to any MCP server executable. Use `--` to separate the server command and arguments from `mcp_dart` flags:

```bash
# Using standard separator (Recommended)
mcp_dart inspect -- npx -y @modelcontextprotocol/server-filesystem /path/to/files

# Or using explicit flags
mcp_dart inspect -c npx -a "-y @modelcontextprotocol/server-filesystem /path/to/files"

# Pass environment variables
mcp_dart inspect --env API_KEY=secret -- python my_server.py
```

**External Server (via HTTP URL):**

Connect to an MCP server via Streamable HTTP:

```bash
mcp_dart inspect --url http://localhost:3000/mcp
```

**Options:**

- `--tool`: Name of a tool to execute.
- `--resource`: URI of a resource to read.
- `--prompt`: Name of a prompt to retrieve.
- `--json-args`: JSON arguments for the tool or prompt.
- `--url`: URL of the MCP server (Streamable HTTP).
- `--command` (`-c`): Executable command to start the server.
- `--server-args` (`-a`): Arguments to pass to the server command.
- `--env`: Environment variables in `KEY=VALUE` format.
- `--wait` (`-w`): Milliseconds to wait for notifications (defaults to 500ms for HTTP).

**Sampling Support:**

The CLI supports `sampling/createMessage` requests from the server (often used by tools like `summarize` that need an LLM). Currently, it returns a placeholder response to ensure tools complete successfully.

### Serve

Runs the MCP server in the current directory.

```bash
mcp_dart serve
```

**Options:**

- `--transport` (`-t`): Transport type to use (`stdio` or `http`). Defaults to `stdio`.
- `--host`: Host for HTTP transport. Defaults to `0.0.0.0`.
- `--port` (`-p`): Port for HTTP transport. Defaults to `3000`.
- `--watch`: Restart the server on file changes.

### Update

Updates the CLI to the latest version.

```bash
mcp_dart update
```

## Running Tests

To run the tests for this package:

```bash
dart test
```

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this project.

