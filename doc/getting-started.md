# Getting Started with MCP Dart SDK

This guide will help you get up and running with the MCP Dart SDK in minutes.

## Installation

Add the MCP Dart SDK to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_dart: ^1.1.2
```

Then run:

```bash
dart pub get
```

Or for Flutter projects:

```bash
flutter pub get
```

## Basic Concepts

### What is MCP?

The Model Context Protocol enables bidirectional communication between:

- **Servers**: Provide capabilities (tools, resources, prompts)
- **Clients**: Use those capabilities (typically AI applications)

### Key Components

#### 1. **Tools**

Functions that AI can call to perform actions:

```dart
// Server provides a tool
server.registerTool(
  'search',
  description: 'Search for information',
  callback: (args, extra) async {
    // Perform search
    return CallToolResult(content: [TextContent(text: results)]);
  },
);

// Client calls the tool
await client.callTool(
  CallToolRequest(
    name: 'search',
    arguments: {'query': 'Dart programming'},
  ),
);
```

#### 2. **Resources**

Data and context that AI can access:

```dart
// Server provides a resource
server.registerResource(
  'README',
  'file:///docs/readme.md',
  null,
  (uri, extra) async => ReadResourceResult(
    contents: [TextResourceContents(
      uri: 'file:///docs/readme.md',
      text: readmeContent,
    )],
  ),
);

// Client reads the resource
await client.readResource(
  ReadResourceRequestParams(
    uri: 'file:///docs/readme.md',
  ),
);
```

#### 3. **Prompts**

Reusable prompt templates with arguments:

```dart
// Server provides a prompt
server.registerPrompt(
  'code-review',
  description: 'Review code for issues',
  argsSchema: {
    'language': PromptArgumentDefinition(
      type: String,
      description: 'Programming language',
      required: true,
    ),
  },
  callback: (args, extra) async => GetPromptResult(
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: TextContent(
          text: 'Review this ${args['language']} code...',
        ),
      ),
    ],
  ),
);

// Client gets the prompt
await client.getPrompt(
  GetPromptRequestParams(
    name: 'code-review',
    arguments: {'language': 'Dart'},
  ),
);
```

#### 4. **Transports**

How clients and servers communicate:

- **Stdio**: Process-based (stdin/stdout)
- **HTTP/SSE**: Web-based (Server-Sent Events)
- **Stream**: In-process communication

## Your First MCP Server

Create a file `my_server.dart`:

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // Create the server
  final server = McpServer(
    Implementation(
      name: 'my-first-server',
      version: '1.0.0',
    ),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
      ),
    ),
  );

  // Add a simple tool
  server.registerTool(
    'greet',
    description: 'Greet someone by name',
    inputSchema: ToolInputSchema(
      properties: {
        'name': JsonSchema.string(description: 'Name of person to greet'),
      },
      required: ['name'],
    ),
    callback: (args, extra) async {
      final name = args['name'] as String;
      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Hello, $name! Welcome to MCP!'),
        ],
      );
    },
  );

  // Add a resource
  server.registerResource(
    'Server Info',
    'info://server',
    null,
    (uri, extra) async => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: 'This is my first MCP server!',
          mimeType: 'text/plain',
        ),
      ],
    ),
  );

  // Connect via stdio
  print('Starting MCP server...');
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

Run your server:

```bash
dart run my_server.dart
```

## Your First MCP Client

Create a file `my_client.dart`:

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // Create the client
  final client = Client(
    Implementation(
      name: 'my-first-client',
      version: '1.0.0',
    ),
  );

  // Connect to the server
  print('Connecting to server...');
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: 'dart',
      args: ['run', 'my_server.dart'],
    ),
  );
  await client.connect(transport);

  // List available tools
  print('\nAvailable tools:');
  final tools = await client.listTools();
  for (final tool in tools.tools) {
    print('  - ${tool.name}: ${tool.description}');
  }

  // Call a tool
  print('\nCalling greet tool...');
  final result = await client.callTool(
    CallToolRequest(
      name: 'greet',
      arguments: {'name': 'Alice'},
    ),
  );
  print('Result: ${result.content.first.text}');

  // Read a resource
  print('\nReading server info resource...');
  final resource = await client.readResource(
    ReadResourceRequestParams(
      uri: 'info://server',
    ),
  );
  print('Content: ${resource.contents.first.text}');

  // Clean up
  await client.close();
  print('\nDone!');
}
```

Run your client:

```bash
dart run my_client.dart
```

Expected output:

```bash
Connecting to server...

Available tools:
  - greet: Greet someone by name

Calling greet tool...
Result: Hello, Alice! Welcome to MCP!

Reading server info resource...
Content: This is my first MCP server!

Done!
```

## Understanding the Flow

1. **Server Startup**: Server declares its capabilities (tools, resources, prompts)
2. **Client Connection**: Client connects and negotiates protocol version
3. **Capability Exchange**: Client and server exchange supported features
4. **Client Requests**: Client discovers and uses server capabilities
5. **Server Responses**: Server processes requests and returns results

## Next Steps

### Learn More About Servers

- [Server Guide](server-guide.md) - Comprehensive server development guide
- [Tools](tools.md) - Building powerful tools with validation

### Learn More About Clients

- [Client Guide](client-guide.md) - Building MCP clients
- [Calling Tools](client-guide.md#calling-tools) - Advanced tool usage
- [Reading Resources](client-guide.md#reading-resources) - Resource subscriptions

### Choose Your Transport

- [Transports Guide](transports.md) - Detailed transport options
- [Stdio](transports.md#stdio-transport) - Best for CLI tools and local services
- [HTTP/SSE](transports.md#http-transport) - Best for web and remote services

## Common Patterns

### Error Handling

```dart
try {
  final result = await client.callTool(
    CallToolRequest(
      name: 'unknown-tool',
      arguments: {},
    ),
  );
} catch (e) {
  if (e is McpError) {
    print('MCP Error: ${e.message} (code: ${e.code})');
  } else {
    print('Unexpected error: $e');
  }
}
```

### Type-Safe Tool Inputs

```dart
server.registerTool(
  'calculate',
  description: 'Perform calculation',
  inputSchema: ToolInputSchema(
    properties: {
      'operation': JsonSchema.string(
        enumValues: ['add', 'subtract', 'multiply', 'divide'],
      ),
      'a': JsonSchema.number(),
      'b': JsonSchema.number(),
    },
    required: ['operation', 'a', 'b'],
  ),
  callback: (args, extra) async {
    final op = args['operation'] as String;
    final a = args['a'] as num;
    final b = args['b'] as num;

    final result = switch (op) {
      'add' => a + b,
      'subtract' => a - b,
      'multiply' => a * b,
      'divide' => a / b,
      _ => throw McpError(
        ErrorCode.invalidParams,
        'Invalid operation',
      ),
    };

    return CallToolResult(
      content: [TextContent(text: '$result')],
    );
  },
);
```

### Resource with URI Template

```dart
server.registerResourceTemplate(
  'User Profile',
  ResourceTemplateRegistration(
    'user://{username}/profile',
    listCallback: null,
  ),
  ResourceMetadata(description: 'Get user profile by username'),
  (uri, vars, extra) async {
    final username = vars['username'];
    final profile = await fetchUserProfile(username);

    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: jsonEncode(profile),
          mimeType: 'application/json',
        ),
      ],
    );
  },
);
```

## Troubleshooting

### Server Not Responding

Ensure the transport is properly initialized:

```dart
// Stdio: Check process is running
final transport = StdioClientTransport(
  StdioServerParameters(command: 'dart', args: ['server.dart']),
);

// HTTP: Check port is available
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
);
```

### Tool Validation Errors

Ensure your input matches the schema:

```dart
// Schema requires 'name' as string
inputSchema: ToolInputSchema(
  properties: {
    'name': JsonSchema.string(),
  },
  required: ['name'],
)

// Correct call
await client.callTool(
  CallToolRequest(
    name: 'greet',
    arguments: {'name': 'Alice'},  // ✅ Valid
  ),
);

// Incorrect call
await client.callTool(
  CallToolRequest(
    name: 'greet',
    arguments: {'name': 123},  // ❌ Wrong type
  ),
);
```

### Connection Timeout

Increase timeout for slow operations:

```dart
final client = Client(
  Implementation(name: 'client', version: '1.0.0'),
  requestTimeout: Duration(seconds: 30),  // Default is 10 seconds
);
```

## Examples in Repository

The SDK includes many examples in the `example/` directory:

- **[server_stdio.dart](../example/server_stdio.dart)** - Complete stdio server
- **[client_stdio.dart](../example/client_stdio.dart)** - Stdio client
- **[weather.dart](../example/weather.dart)** - Real weather API integration
- **[oauth_server_example.dart](../example/oauth_server_example.dart)** - OAuth2 server
- **[completions_capability_demo.dart](../example/completions_capability_demo.dart)** - Auto-completion
- **[elicitation_http_server.dart](../example/elicitation_http_server.dart)** - User input collection

Browse the examples to see real-world usage patterns!

## Further Reading

- [Server Guide](server-guide.md) - Build comprehensive MCP servers
- [Client Guide](client-guide.md) - Build MCP clients and applications
- [Examples](examples.md) - Real-world usage examples
