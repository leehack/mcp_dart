import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final mcpServer = McpServer(
    const Implementation(name: "example-dart-server", version: "1.0.0"),
    options: const ServerOptions(capabilities: ServerCapabilities()),
  );

  mcpServer.tool(
    "calculate",
    description: 'Perform basic arithmetic operations',
    toolInputSchema: const ToolInputSchema(
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
    callback: ({args, meta, extra}) async {
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

  final sseServerManager = SseServerManager(mcpServer);
  try {
    final port = 3000;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Server listening on http://localhost:$port');

    await for (final request in server) {
      sseServerManager.handleRequest(request);
    }
  } catch (e) {
    print('Error starting server: $e');
    exitCode = 1;
  }
}
