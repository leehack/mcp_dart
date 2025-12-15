import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

Future<McpServer> getServer() async {
  final mcpServer = McpServer(
    const Implementation(
      name: "example-dart-iostream-server",
      version: "1.0.0",
    ),
    options: const ServerOptions(capabilities: ServerCapabilities()),
  );

  mcpServer.registerTool(
    "calculate",
    description: 'Perform basic arithmetic operations',
    inputSchema: const ToolInputSchema(
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
    callback: (args, extra) async {
      final operation = args['operation'];
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
  return mcpServer;
}
