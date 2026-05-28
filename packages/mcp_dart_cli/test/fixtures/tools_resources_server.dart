import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final server = McpServer(
    const Implementation(name: 'tools-resources-server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
      ),
    ),
  );

  server.registerTool(
    'echo',
    description: 'Echoes text.',
    inputSchema: JsonSchema.object(
      properties: {
        'message': JsonSchema.string(),
      },
      required: ['message'],
    ),
    callback: (args, extra) async {
      return CallToolResult.fromContent(
        [
          TextContent(text: 'Echo: ${args['message']}'),
        ],
      );
    },
  );

  server.registerResource(
    'Demo Resource',
    'demo://resource',
    null,
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'text/plain',
            text: 'demo',
          ),
        ],
      );
    },
  );

  await server.connect(StdioServerTransport());
}
