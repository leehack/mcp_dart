# mcp_dart_cli

CLI for creating Model Context Protocol (MCP) servers in Dart.

## Installation

```bash
dart pub global activate mcp_dart_cli
```

## Usage

### Create a new project

```bash
mcp_dart create <project_name>
```

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

### Serve the project

Runs the MCP server in the current directory.

```bash
mcp_dart serve
```

Options:
- `--transport` (`-t`): Transport type to use (`stdio` or `http`). Defaults to `stdio`.
- `--host`: Host for HTTP transport. Defaults to `0.0.0.0`.
- `--port` (`-p`): Port for HTTP transport. Defaults to `3000`.
- `--watch`: Restart the server on file changes.

## Running Tests

To run the tests for this package:

```bash
dart test
```

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this project.

