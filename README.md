# MCP(Model Context Protocol) for Dart

[![Pub Version](https://img.shields.io/pub/v/mcp_dart?color=blueviolet)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

[Model Context Protocol](https://modelcontextprotocol.io/) (MCP) is an open protocol designed to enable seamless integration between LLM applications and external data sources and tools.

This library aims to provide a simple and intuitive way to implement MCP servers and clients in Dart, while adhering to the [MCP protocol spec](https://spec.modelcontextprotocol.io/). The goal is to make this SDK as similar as possible to the official SDKs available in other languages, ensuring a consistent developer experience across platforms.

## Requirements

- Dart SDK version ^3.0.0 or higher

Ensure you have the correct Dart SDK version installed. See <https://dart.dev/get-dart> for installation instructions.

## Features

- Stdio support (Server and Client)
- SSE support (Server only for now)
- Tools
- Resources
- Prompts
- Sampling
- Roots

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
    inputSchema: {
      'properties': {
        'operation': {
          'type': 'string',
          'enum': ['add', 'subtract', 'multiply', 'divide'],
        },
        'a': {'type': 'number'},
        'b': {'type': 'number'},
      },
      'required': ['operation', 'a', 'b'],
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

## More examples

<https://github.com/leehack/mcp_dart/tree/main/example>

## Credits

This library is inspired by the following projects:

- <https://github.com/crbrotea/dart_mcp>
- <https://github.com/nmfisher/simple_dart_mcp_server>
