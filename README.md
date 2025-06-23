# MCP (Model Context Protocol) for Dart

[![Pub
Version](https://img.shields.io/pub/v/mcp_dart?color=blueviolet)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

[Model Context Protocol](https://modelcontextprotocol.io/) (MCP) is an open
protocol designed to enable seamless integration between LLM applications and
external data sources and tools.

This library provides a simple and intuitive way to implement MCP servers and
clients in Dart. **MCP clients now support all platforms including web browsers
and WASM**, while MCP servers remain optimized for Dart VM environments. It
adheres to the [MCP protocol spec](https://spec.modelcontextprotocol.io/) while
ensuring a consistent developer experience across all platforms.

## Requirements

- Dart SDK version ^3.0.0 or higher

Ensure you have the correct Dart SDK version installed. See
<https://dart.dev/get-dart> for installation instructions.

## Features

- **Cross-Platform Client Support** - MCP clients work on all platforms: Dart
  VM, Flutter (mobile/desktop), web browsers, and WASM
- **Conditional Compilation** - Platform-optimized implementations with
  identical APIs
- **MCP Servers** (Dart VM only):
  - Stdio support (Server and Client)
  - StreamableHTTP support (Server only)
  - SSE support (Server only) - Deprecated  
  - Stream Transport using dart streams (Server and Client in shared process)
- **MCP Clients** (Cross-platform):
  - Stdio support (VM only)
  - **StreamableHTTP support** - **Works everywhere: VM, web browsers, WASM!**
- **Protocol Features**:
  - Tools, Resources, Prompts
  - Sampling, Roots

## Model Context Protocol Version

The current version of the protocol is `2025-03-26`. This library is designed to
be compatible with this version, and any future updates will be made to ensure
continued compatibility.

It's also backward compatible with the previous version `2024-11-05` and
`2024-10-07`.

## Getting started

### Server (Dart VM)

Below code is the simplest way to start an MCP server:

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

### Client (Cross-Platform: VM, Web, WASM)

The MCP client now works on **all Dart platforms** - Dart VM, Flutter
mobile/desktop, web browsers, and WASM! 

**Simple client example (works everywhere):**
```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final client = McpClient(
    Implementation(name: "example-client", version: "1.0.0"),
  );
  
  // StreamableHttpClientTransport works on ALL platforms: VM, mobile, desktop, web, WASM!
  await client.connect(StreamableHttpClientTransport(
    Uri.parse('https://your-mcp-server.com/mcp'),
  ));
}
```

**Try it yourself - Flutter Demo:**
```bash
cd example/flutter_client
flutter pub get
flutter run -d chrome    # Web browser (includes WASM support)
flutter run -d macos     # Desktop  
flutter run               # Mobile
```

See [`example/flutter_client/`](example/flutter_client/) for the complete
cross-platform demo.

**Important Notes:**
- **MCP Client**: Full cross-platform support (VM, web, WASM) via
  `StreamableHttpClientTransport`
- **MCP Server**: Dart VM only (web environments receive API-compatible stubs
  that throw `UnsupportedError`)

**Technical Implementation:**
- Uses `dart:io.HttpClient` on native platforms for optimal performance
- Uses `package:http` on web browsers for cross-platform compatibility  
- WASM compatibility achieved through conditional compilation with web-safe defaults
- Zero runtime overhead - platform detection happens at compile time
- Comprehensive test coverage: 120 VM tests + 69 web-specific tests

For technical details about web and WASM support, see the [Web Design
Document](WEB_DESIGN_DOC.md).

## Usage

Once you compile your MCP server, you can compile the client using the below
code.

```bash
dart compile exe example/server_stdio.dart -o ./server_stdio
```

Or just run it with JIT.

```bash
dart run example/server_stdio.dart
```

To configure it with the client (ex, Claude Desktop), you can use the below
code.

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

## Testing

This library includes comprehensive tests for both Dart VM and web environments.

### Running All Tests

**Option 1: Using the test runner (Recommended)**
```bash
dart run test_runner.dart
```

**Option 2: Using Make**
```bash
make test              # Run all tests
make test-vm          # Run VM tests only  
make test-web         # Run web tests only
make test-verbose     # Run with verbose output
```

**Option 3: Using shell script**
```bash
./scripts/test-all.sh
```

### Running Specific Test Types

**VM Tests Only:**
```bash
dart test --exclude-tags=web-only
```

**Web Tests Only:**
```bash
dart test test/web/ -p chrome
```

**VS Code Integration:**
- Use `Ctrl+Shift+P` → "Tasks: Run Task" → Select test type
- Or use the debug configurations in Run and Debug panel

### Web Platform Testing

The library includes dedicated web tests that validate cross-platform
compatibility, browser integration, and web-specific features.

**For comprehensive testing details, see:**
- **[Testing Guide](TESTING_GUIDE.md)** - Complete testing instructions and
  troubleshooting
- **[Web Design Document](web-design-doc.md)** - Technical implementation
  details and architecture
- **[test/web/README.md](test/web/README.md)** - Web-specific test documentation

## Credits

This library is inspired by the following projects:

- <https://github.com/crbrotea/dart_mcp>
- <https://github.com/nmfisher/simple_dart_mcp_server>
