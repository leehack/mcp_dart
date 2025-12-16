# Examples

## Stdio Server

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  McpServer server = McpServer(
    Implementation(name: "example-server", version: "1.0.0"),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        resources: ServerCapabilitiesResources(),
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  server.registerTool(
    "calculate",
    description: 'Perform basic arithmetic operations',
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
      final operation = args['operation'];
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

## Streamable HTTP Server

```dart
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = McpServer(
    Implementation(name: "example-http-server", version: "1.0.0"),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  server.registerTool(
    "echo",
    description: 'Echoes back the input',
    inputSchema: ToolInputSchema(properties: {
      'message': JsonSchema.string(),
    }),
    callback: (args, extra) async {
      return CallToolResult(
        content: [TextContent(text: "Echo: ${args['message']}")],
      );
    },
  );

  final transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions());
  await server.connect(transport);

  final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 3000);
  print('Server listening on http://localhost:3000/mcp');

  await for (final request in httpServer) {
    if (request.uri.path == '/mcp') {
      await transport.handleRequest(request);
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }
}
```

For a more complex example handling multiple sessions, tasks, and interactive capabilities, see [`simple_task_interactive_server.dart`](https://github.com/leehack/mcp_dart/tree/main/example/simple_task_interactive_server.dart).

## [More Examples](https://github.com/leehack/mcp_dart/tree/main/example)
