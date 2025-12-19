# Templates

This directory contains the source files for project templates used by the `mcp_dart` CLI.

## `simple`

The `simple` template is a [Mason](https://github.com/felangel/mason) "brick" that provides a complete structure for building an MCP server in Dart.
Its source code lives in `simple/__brick__`.

### Structure

The template is organized to promote separation of concerns and scalability:

-   `bin/server.dart`: The entry point for the MCP server.
-   `lib/mcp/mcp.dart`: Central MCP server factory and configuration.
-   `lib/mcp/server_config.dart`: Server configuration and argument parsing.
-   `lib/mcp/tools/`: Directory for tool definitions.
-   `lib/mcp/prompts/`: Directory for prompt definitions.
-   `lib/mcp/resources/`: Directory for resource definitions.

### How to Modify

1.  **Edit Files**: Modify the files in `templates/simple/__brick__/` as needed.
2.  **Verify**: Ensure any dynamic variables (like `{{name}}`) are correctly used.
3.  **Build**: Update the bundled template used by the CLI.

### Usage

The `mcp_dart` CLI fetches templates remotely by default.

```bash
# Default: Fetches from the official repository (main branch)
dart bin/mcp_dart.dart create my_project

# GitHub Actions Style (Shortest & Best)
dart bin/mcp_dart.dart create my_project --template leehack/mcp_dart/packages/templates/simple@main

# Custom Template (GitHub Tree URL)
dart bin/mcp_dart.dart create my_project --template https://github.com/my/repo/tree/main/path/to/brick

# Custom Template (Git Syntax)
dart bin/mcp_dart.dart create my_project --template https://github.com/my/repo.git#ref:path/to/brick

# Local Template (Path)
dart bin/mcp_dart.dart create my_project --template ./my_local_brick
```
