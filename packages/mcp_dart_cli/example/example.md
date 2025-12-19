# Example

This example demonstrates how to use `mcp_dart_cli` to create new MCP server projects.

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

#### From a Git Repository with a specific ref and path

You can specify a reference (branch, tag, or commit) and a path to the brick:

```bash
mcp_dart create my_git_server --template https://github.com/username/repo.git#ref:path/to/brick
```

#### From a GitHub Repository using short syntax

You can use the GitHub short syntax `owner/repo/path/to/brick@ref`:

```bash
mcp_dart create my_github_server --template owner/repo/path/to/brick@ref
```

#### From a Subdirectory in a Git Repository

You can also use a template located in a subdirectory of a Git repository:

```bash
mcp_dart create my_simple_server --template https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple
```
