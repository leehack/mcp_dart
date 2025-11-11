# MCP(Model Context Protocol) for Dart

[![Pub Version](https://img.shields.io/pub/v/mcp_dart?color=blueviolet)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

[Model Context Protocol](https://modelcontextprotocol.io/) (MCP) is an open protocol designed to enable seamless integration between LLM applications and external data sources and tools.

This library aims to provide a simple and intuitive way to implement MCP servers and clients in Dart, while adhering to the [MCP protocol spec 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18). The goal is to make this SDK as similar as possible to the official SDKs available in other languages, ensuring a consistent developer experience across platforms.

## Requirements

- Dart SDK version ^3.0.0 or higher

Ensure you have the correct Dart SDK version installed. See <https://dart.dev/get-dart> for installation instructions.

## Features

- Stdio support (Server and Client)
- StreamableHTTP support (Server and Client)
- SSE support (Server only) - Deprecated
- Stream Transport using dart streams (Server and Client in shared process)
- Tools
- Resources
- Prompts
- Sampling
- Roots
- Completions
- Elicitation (Server-initiated user input collection)
- OAuth2 Authentication (Client and Server)

## Model Context Protocol Version

The current version of the protocol is `2025-06-18`. This library is designed to be compatible with this version, and any future updates will be made to ensure continued compatibility.

It's also backward compatible with previous versions including `2025-03-26`, `2024-11-05`, and `2024-10-07`.

**New in 2025-06-18**: Elicitation support for server-initiated user input collection.

## Getting started

Below code is the simplest way to start the MCP server.

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
    inputSchemaProperties: {
      'operation': {
        'type': 'string',
        'enum': ['add', 'subtract', 'multiply', 'divide'],
      },
      'a': {'type': 'number'},
      'b': {'type': 'number'},
    },
    callback: ({args, extra}) async {
      final operation = args!['operation'];
      final a = args['a'];
      final b = args['b'];
      return CallToolResult(
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

## Usage

Once you compile your MCP server, you can compile the client using the below code.

```bash
dart compile exe example/server_stdio.dart -o ./server_stdio
```

Or just run it with JIT.

```bash
dart run example/server_stdio.dart
```

To configure it with the client (ex, Claude Desktop), you can use the below code.

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

This library supports OAuth2 authentication for both clients and servers, allowing secure integration with external services.

### OAuth2 Support

- **Client Authentication**: Implement OAuth2 flows in MCP clients to authenticate with protected servers
- **Server Authentication**: Add OAuth2 protection to your MCP servers to secure access to tools and resources
- **Provider Integration**: Built-in support for GitHub OAuth and extensible for other providers

### Quick Start Guides

- **[OAuth Quick Start](https://github.com/leehack/mcp_dart/blob/main/example/authentication/OAUTH_QUICK_START.md)**: Get started with OAuth2 in 5 minutes
- **[OAuth Server Guide](https://github.com/leehack/mcp_dart/blob/main/example/authentication/OAUTH_SERVER_GUIDE.md)**: Comprehensive guide for implementing OAuth2 servers
- **[GitHub Setup Guide](https://github.com/leehack/mcp_dart/blob/main/example/authentication/GITHUB_SETUP.md)**: Configure GitHub OAuth for your MCP server

### Example Implementations

- **[OAuth Server Example](https://github.com/leehack/mcp_dart/blob/main/example/authentication/oauth_server_example.dart)**: Full OAuth2 server implementation
- **[OAuth Client Example](https://github.com/leehack/mcp_dart/blob/main/example/authentication/oauth_client_example.dart)**: OAuth2 client integration
- **[GitHub OAuth Example](https://github.com/leehack/mcp_dart/blob/main/example/authentication/github_oauth_example.dart)**: Complete GitHub OAuth integration
- **[GitHub PAT Example](https://github.com/leehack/mcp_dart/blob/main/example/authentication/github_pat_example.dart)**: Personal Access Token authentication

## More examples

For additional examples including authentication, HTTP clients, and advanced features, see:

<https://github.com/leehack/mcp_dart/tree/main/example>

For authentication-specific examples and guides, see:

<https://github.com/leehack/mcp_dart/tree/main/example/authentication>

## Credits

This library is inspired by the following projects:

- <https://github.com/crbrotea/dart_mcp>
- <https://github.com/nmfisher/simple_dart_mcp_server>
