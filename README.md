# MCP (Model Context Protocol) for Dart

[![Coverage](https://img.shields.io/codecov/c/github/leehack/mcp_dart)](https://app.codecov.io/gh/leehack/mcp_dart)
[![Pub Version](https://img.shields.io/pub/v/mcp_dart?color=blueviolet)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

The Model Context Protocol (MCP) is a standardized protocol for communication between AI applications and external services. It enables:

- **Tools**: Allow AI to execute actions (API calls, computations, etc.)
- **Resources**: Provide context and data to AI (files, databases, APIs)
- **Prompts**: Pre-built prompt templates with arguments

## Understanding MCP: Client, Server, and Host

MCP follows a **client-server architecture** with three key components:

- **MCP Host**: The AI application that provides the user interface and manages connections to multiple MCP servers.
  - Example: Claude Desktop, IDEs like VS Code, custom AI applications
  - Manages server lifecycle, discovers capabilities, and orchestrates interactions

- **MCP Client**: The protocol implementation within the host that communicates with servers.
  - Handles protocol negotiation, capability discovery, and request/response flow
  - Typically built into or used by the MCP host

- **MCP Server**: Provides capabilities (tools, resources, prompts) that AI can use through the host.
  - Example: Servers for file system access, database queries, or API integrations
  - Runs as a separate process and communicates via standardized transports (stdio, StreamableHTTP)

**Typical Flow**: User ↔ MCP Host (with Client) ↔ MCP Protocol ↔ Your Server ↔ External Services/Data

## Requirements

- Dart SDK version ^3.0.0 or higher

Ensure you have the correct Dart SDK version installed. See <https://dart.dev/get-dart> for installation instructions.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_dart: ^2.0.0
```

Then install dependencies:

```bash
dart pub get
```

## What This SDK Provides

**This SDK lets you build both MCP servers and clients in Dart/Flutter.**

- ✅ **Build MCP Servers** - Create servers that expose tools, resources, and prompts to AI hosts
- ✅ **Build MCP Clients** - Create AI applications that can connect to and use MCP servers
- ✅ **Full MCP Protocol Support** - Complete [MCP specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25) implementation
- ✅ **Multiple Transport Options** - Stdio, StreamableHTTP, IOStream, or custom transports
- ✅ **All Capabilities** - Tools, Resources, Prompts, Sampling, Roots, Completions, Elicitation, Tasks
- ✅ **Extension Support** - Generic `extensions` negotiation with typed MCP Apps helpers and TypeScript-style `registerAppTool` / `registerAppResource`
- ✅ **Latest Content/Metadata Types** - `resource_link`, themed `icons`, and `annotations.lastModified`
- ✅ **OAuth2 Support** - Complete authentication with PKCE
- ✅ **Transport Security Controls** - Optional DNS rebinding protection with host/origin allowlists
- ✅ **Type-Safe** - Comprehensive type definitions with null safety
- ✅ **Cross-Platform** - Works on Linux, Windows, macOS, Web, and Flutter

The goal is to make this SDK as similar as possible to the official SDKs available in other languages, ensuring a consistent developer experience across platforms.

## Model Context Protocol Version

The current version of the protocol is `2025-11-25`. This library is designed to be compatible with this version, and any future updates will be made to ensure continued compatibility.

It's also backward compatible with previous versions including `2025-06-18`, `2025-03-26`, `2024-11-05`, and `2024-10-07`.

## Documentation

### Getting Started

- 📖 **[Quick Start Guide](https://github.com/leehack/mcp_dart/blob/main/doc/getting-started.md)** - Get up and running in 5 minutes
- 🔧 **[Server Guide](https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md)** - Complete guide to building MCP servers
- 💻 **[Client Guide](https://github.com/leehack/mcp_dart/blob/main/doc/client-guide.md)** - Complete guide to building MCP clients

### Core Concepts

- 🛠️ **[Tools Documentation](https://github.com/leehack/mcp_dart/blob/main/doc/tools.md)** - Implementing executable tools
- 🔌 **[Transport Options](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md)** - Built-in and custom transport implementations
- 📚 **[Examples](https://github.com/leehack/mcp_dart/blob/main/doc/examples.md)** - Real-world usage examples
- ⚡ **[Quick Reference](https://github.com/leehack/mcp_dart/blob/main/doc/quick-reference.md)** - Fast lookup guide
- 🪵 **[Runtime Logging](https://github.com/leehack/mcp_dart/blob/main/doc/getting-started.md#sdk-runtime-logging)** - Configure and route internal SDK logs
- 🧩 **[MCP Apps Guide](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-apps.md)** - Using `io.modelcontextprotocol/ui` metadata

### Advanced Features

- 🔐 **[OAuth Authentication](https://github.com/leehack/mcp_dart/tree/main/example/authentication)** - OAuth2 guides and examples
- 📝 For resources, prompts, and other features, see the Server and Client guides

## Quick Start with CLI

The fastest way to create an MCP server is using the `mcp_dart_cli`:

```bash
# Install the CLI
dart pub global activate mcp_dart_cli

# Create a new project
mcp_dart create my_server

# Navigate and run
cd my_server
mcp_dart serve
```

Your server is now running! Use `mcp_dart inspect` to test it:

```bash
mcp_dart inspect              # List all capabilities
mcp_dart inspect --tool add --json-args '{"a": 1, "b": 2}'   # Call a tool
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `create` | Scaffold a new MCP server project |
| `serve` | Run your server (stdio or HTTP) |
| `doctor` | Check project health and connectivity |
| `inspect` | Test and debug server capabilities |

📖 **[Full CLI Documentation](https://github.com/leehack/mcp_dart/tree/main/packages/mcp_dart_cli)**

### Connecting to AI Hosts

Configure your server with AI hosts like Claude Desktop:

```json
{
  "mcpServers": {
    "my_server": {
      "command": "mcp_dart",
      "args": ["serve"],
      "cwd": "/path/to/my_server"
    }
  }
}
```

> [!TIP]
> For manual server implementation or advanced use cases, see the [Server Guide](https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md).

## Authentication

This library supports OAuth2 authentication with PKCE for both clients and servers. For complete authentication guides and examples, see the [OAuth Authentication documentation](https://github.com/leehack/mcp_dart/tree/main/example/authentication).

## Platform Support

| Platform | Stdio | StreamableHTTP | IOStream | Custom |
|----------|-------|----------------|----------|--------|
| **Desktop** (CLI/Server) | ✅ | ✅ | ✅ | ✅ |
| **Web** (Browser) | ❌ | ✅ | ✅ | ✅ |
| **Flutter** (Mobile/Desktop) | ✅ | ✅ | ✅ | ✅ |

**Custom Transports**: You can implement your own transport layer by extending the transport interfaces if you need specific communication patterns not covered by the built-in options.

## More Examples

For additional examples including authentication, HTTP clients, and advanced features:

- [All Examples](https://github.com/leehack/mcp_dart/tree/main/example)
- [Authentication Examples](https://github.com/leehack/mcp_dart/tree/main/example/authentication)

## Community & Support

- **Issues & Bug Reports**: [GitHub Issues](https://github.com/leehack/mcp_dart/issues)
- **Package**: [pub.dev/packages/mcp_dart](https://pub.dev/packages/mcp_dart)
- **API Docs**: [pub.dev documentation](https://pub.dev/documentation/mcp_dart/latest/)
- **Changelog**: [CHANGELOG.md](https://github.com/leehack/mcp_dart/blob/main/CHANGELOG.md)
- **Protocol Spec**: [MCP Specification](https://modelcontextprotocol.io/specification/2025-11-25)

## Credits

This library is inspired by the following projects:

- <https://github.com/crbrotea/dart_mcp>
- <https://github.com/nmfisher/simple_dart_mcp_server>
