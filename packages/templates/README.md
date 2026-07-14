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

Released versions of the `mcp_dart` CLI fetch the template from their matching,
immutable `mcp_dart_cli-v<version>` tag by default. Use `--template` to select a
different source while developing a template.

```bash
# Installed CLI: fetches the template paired with that release
mcp_dart create my_project

# Repository shorthand
mcp_dart create my_project --template leehack/mcp_dart/packages/templates/simple@main

# Custom Template (GitHub Tree URL)
mcp_dart create my_project --template https://github.com/my/repo/tree/main/path/to/brick

# Custom Template (Git Syntax)
mcp_dart create my_project --template https://github.com/my/repo.git#ref:path/to/brick

# Local Template (Path)
mcp_dart create my_project --template ./my_local_brick
```
