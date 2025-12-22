# Example

This document demonstrates how to use `mcp_dart_cli` to create, run, and inspect MCP server projects.

## Installation

First, install the CLI globally:

```bash
dart pub global activate mcp_dart_cli
```

## Creating a Project

### Basic Usage

Create a new project with the default template:

```bash
mcp_dart create my_mcp_server
```

### Using Templates

You can create a project from various template sources.

#### From a Local Path

If you have a template on your local machine:

```bash
mcp_dart create my_custom_server --template path/to/my/template
```

#### From a Git Repository

To use a template hosted in a Git repository:

```bash
mcp_dart create my_git_server --template https://github.com/username/repo.git
```

#### From a Git Repository with a Specific Ref and Path

You can specify a reference (branch, tag, or commit) and a path to the brick:

```bash
mcp_dart create my_git_server --template https://github.com/username/repo.git#ref:path/to/brick
```

#### From a GitHub Repository using Short Syntax

You can use the GitHub short syntax `owner/repo/path/to/brick@ref`:

```bash
mcp_dart create my_github_server --template owner/repo/path/to/brick@ref
```

#### From a Subdirectory in a Git Repository

You can also use a template located in a subdirectory of a Git repository:

```bash
mcp_dart create my_simple_server --template https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple
```

## Running the Server

### Basic Usage

Run the MCP server in stdio mode (default):

```bash
cd my_mcp_server
mcp_dart serve
```

### HTTP Transport

Run the server with HTTP transport for web-based clients:

```bash
mcp_dart serve --transport http --port 8080
```

### Watch Mode

Automatically restart the server when files change:

```bash
mcp_dart serve --watch
```

## Checking Project Health

Run the `doctor` command to verify your project configuration and test connectivity:

```bash
mcp_dart doctor
```

This will:
1. Check for required files (`pubspec.yaml`, `lib/mcp/mcp.dart`, etc.)
2. Verify the `mcp_dart` dependency
3. Start the server and test all tools, resources, and prompts

## Inspecting MCP Servers

### List Capabilities

List all available tools, resources, and prompts:

```bash
# For local project
mcp_dart inspect

# For external server
mcp_dart inspect -- npx -y @modelcontextprotocol/server-filesystem /tmp
```

### Execute a Tool

```bash
mcp_dart inspect --tool add --json-args '{"a": 5, "b": 3}'
```

### Read a Resource

```bash
mcp_dart inspect --resource manifest://app
```

### Get a Prompt

```bash
mcp_dart inspect --prompt greeting --json-args '{"name": "Developer"}'
```

### Connect via HTTP

```bash
mcp_dart inspect --url http://localhost:3000/mcp
```

### Pass Environment Variables

```bash
mcp_dart inspect --env API_KEY=your_key --env DEBUG=true -- python my_server.py
```

## Updating the CLI

Update to the latest version of `mcp_dart_cli`:

```bash
mcp_dart update
```
