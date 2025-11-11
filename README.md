# MCP(Model Context Protocol) for Dart

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

## What This SDK Provides

**This SDK lets you build both MCP servers and clients in Dart/Flutter.**

- ✅ **Build MCP Servers** - Create servers that expose tools, resources, and prompts to AI hosts
- ✅ **Build MCP Clients** - Create AI applications that can connect to and use MCP servers
- ✅ **Full MCP Protocol Support** - Complete [MCP specification 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18) implementation
- ✅ **Multiple Transport Options** - Stdio, StreamableHTTP, Stream, or custom transports
- ✅ **All Capabilities** - Tools, Resources, Prompts, Sampling, Roots, Completions, Elicitation
- ✅ **OAuth2 Support** - Complete authentication with PKCE
- ✅ **Type-Safe** - Comprehensive type definitions with null safety
- ✅ **Cross-Platform** - Works on VM, Web, and Flutter

The goal is to make this SDK as similar as possible to the official SDKs available in other languages, ensuring a consistent developer experience across platforms.

## Model Context Protocol Version

The current version of the protocol is `2025-06-18`. This library is designed to be compatible with this version, and any future updates will be made to ensure continued compatibility.

It's also backward compatible with previous versions including `2025-03-26`, `2024-11-05`, and `2024-10-07`.

**New in 2025-06-18**: Elicitation support for server-initiated user input collection.

## Documentation

### Getting Started

- 📖 **[Quick Start Guide](docs/getting-started.md)** - Get up and running in 5 minutes
- 🔧 **[Server Guide](docs/server-guide.md)** - Complete guide to building MCP servers
- 💻 **[Client Guide](docs/client-guide.md)** - Complete guide to building MCP clients

### Core Concepts

- 🛠️ **[Tools Documentation](docs/tools.md)** - Implementing executable tools
- 🔌 **[Transport Options](docs/transports.md)** - Built-in and custom transport implementations
- 📚 **[Examples](docs/examples.md)** - Real-world usage examples
- ⚡ **[Quick Reference](docs/quick-reference.md)** - Fast lookup guide

### Advanced Features

- 🔐 **[OAuth Authentication](example/authentication/)** - OAuth2 guides and examples
- 📝 For resources, prompts, and other features, see the Server and Client guides

## Quick Start Example

Below is the simplest way to create an MCP server:

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  McpServer server = McpServer(
    Implementation(name: "mcp-example-server", version: "1.0.0"),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        resources: ServerCapabilitiesResources(),
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  server.tool(
    "calculate",
    description: 'Perform basic arithmetic operations',
    toolInputSchema: ToolInputSchema(
      properties: {
        'operation': {
          'type': 'string',
          'enum': ['add', 'subtract', 'multiply', 'divide'],
        },
        'a': {'type': 'number'},
        'b': {'type': 'number'},
      },
      required: ['operation', 'a', 'b'],
    ),
    callback: ({args, extra}) async {
      final operation = args!['operation'];
      final a = args['a'];
      final b = args['b'];
      return CallToolResult.fromContent(
        content: [
          TextContent(
            text: switch (operation) {
              'add' => 'Result: ${a + b}',
              'subtract' => 'Result: ${a - b}',
              'multiply' => 'Result: ${a * b}',
              'divide' => 'Result: ${a / b}',
              _ => throw Exception('Invalid operation'),
            },
          ),
        ],
      );
    },
  );

  server.connect(StdioServerTransport());
}
```

### Running Your Server

Compile your MCP server to an executable:

```bash
dart compile exe example/server_stdio.dart -o ./server_stdio
```

Or run it directly with JIT:

```bash
dart run example/server_stdio.dart
```

### Connecting to AI Hosts

To configure your server with AI hosts like Claude Desktop:

```json
{
  "mcpServers": {
    "calculator_jit": {
      "command": "path/to/dart",
      "args": [
        "/path/to/server_stdio.dart"
      ]
    },
    "calculator_aot": {
      "command": "path/to/compiled/server_stdio",
    },
  }
}
```

## Authentication

This library supports OAuth2 authentication with PKCE for both clients and servers. For complete authentication guides and examples, see the [OAuth Authentication documentation](example/authentication/).

## Platform Support

| Platform | Stdio | StreamableHTTP | Stream | Custom |
|----------|-------|----------------|--------|--------|
| **Dart VM** (CLI/Server) | ✅ | ✅ | ✅ | ✅ |
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
- **Protocol Spec**: [MCP Specification](https://modelcontextprotocol.io/specification/2025-06-18)

## Credits

This library is inspired by the following projects:

- <https://github.com/crbrotea/dart_mcp>
- <https://github.com/nmfisher/simple_dart_mcp_server>
