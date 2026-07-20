import 'package:mcp_dart/mcp_dart.dart';

McpServer createMcpServer() {
  final server = McpServer(
    const Implementation(name: 'cli-e2e-dart-server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  server.registerTool(
    'echo',
    description: 'Echoes text.',
    inputSchema: JsonSchema.object(
      properties: {'message': JsonSchema.string()},
      required: ['message'],
    ),
    callback: (args, extra) async {
      return CallToolResult.fromContent([
        TextContent(text: args['message'] as String),
      ]);
    },
  );

  return server;
}
