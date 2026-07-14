import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Legacy MCP SSE transport example.
///
/// New servers should use Streamable HTTP. This example intentionally uses the
/// 2025-era initialization profile because the SSE transport is deprecated.
Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
  final allowedBrowserOrigin =
      Platform.environment['MCP_ALLOWED_ORIGIN'] ?? 'http://localhost:$port';
  final mcpServer = McpServer(
    const Implementation(name: "example-dart-server", version: "1.0.0"),
    options: const McpServerOptions(
      protocol: McpProtocol.legacy,
      capabilities: ServerCapabilities(),
    ),
  );

  mcpServer.registerTool(
    "calculate",
    description: 'Perform basic arithmetic operations',
    inputSchema: JsonSchema.object(
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
      return CallToolResult.fromContent(
        [
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

  final sseServerManager = SseServerManager(
    mcpServer,
    enableDnsRebindingProtection: true,
    allowedHosts: const {'localhost', '127.0.0.1'},
    allowedOrigins: {allowedBrowserOrigin},
  );
  try {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    print('Server listening on http://localhost:$port');

    await for (final request in server) {
      await sseServerManager.handleRequest(request);
    }
  } catch (e) {
    print('Error starting server: $e');
    exitCode = 1;
  }
}
