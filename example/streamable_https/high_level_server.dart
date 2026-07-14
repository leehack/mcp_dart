import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final allowedBrowserOrigin =
      Platform.environment['MCP_ALLOWED_ORIGIN'] ?? 'http://localhost:8080';
  final server = StreamableMcpServer(
    serverFactory: (sessionId) {
      print('Creating new server for session: $sessionId');
      return getServer();
    },
    host: 'localhost',
    port: 3000,
    path: '/mcp',
    eventStore: InMemoryEventStore(), // Use the built-in in-memory event store
    allowedHosts: const {'localhost', '127.0.0.1'},
    allowedOrigins: {allowedBrowserOrigin},
  );

  await server.start();
  print('Server running on http://localhost:3000/mcp');
  print('Allowed browser origin: $allowedBrowserOrigin');
}

// Create an MCP server with implementation details
McpServer getServer() {
  // Create the McpServer with the implementation details and options
  final server = McpServer(
    const Implementation(
      name: 'simple-streamable-http-server',
      version: '1.0.0',
    ),
    options: const McpServerOptions(protocol: McpProtocol.stable),
  );

  // Register a simple tool that returns a greeting
  server.registerTool(
    'greet',
    description: 'A simple greeting tool',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description: 'Name to greet',
        ),
      },
      required: ['name'],
    ),
    callback: (args, extra) async {
      final name = args['name'] as String? ?? 'world';
      return CallToolResult.fromContent(
        [
          TextContent(text: 'Hello, $name!'),
        ],
      );
    },
  );

  // Register a tool that reports progress while preparing a greeting.
  server.registerTool(
    'multi-greet',
    description: 'A tool that prepares a greeting with progress updates',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(
          description: 'Name to greet',
        ),
      },
    ),
    annotations: const ToolAnnotations(
      title: 'Multiple Greeting Tool',
      readOnlyHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final name = args['name'] as String? ?? 'world';

      // Helper function for sleeping
      Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

      await extra.sendProgress(
        0,
        total: 2,
        message: 'Starting multi-greet',
      );

      await sleep(1000); // Wait 1 second before first greeting

      await extra.sendProgress(
        1,
        total: 2,
        message: 'First greeting prepared',
      );

      await sleep(1000); // Wait another second before second greeting

      await extra.sendProgress(
        2,
        total: 2,
        message: 'Greeting complete',
      );

      return CallToolResult.fromContent(
        [
          TextContent(text: 'Good morning, $name!'),
        ],
      );
    },
  );

  // Register a simple prompt
  server.registerPrompt(
    'greeting-template',
    description: 'A simple greeting prompt template',
    argsSchema: {
      'name': const PromptArgumentDefinition(
        description: 'Name to include in greeting',
        required: true,
      ),
    },
    callback: (args, extra) async {
      final name = args!['name'] as String;
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: 'Please greet $name in a friendly manner.',
            ),
          ),
        ],
      );
    },
  );

  // Register a tool that emits periodic request-scoped progress.
  server.registerTool(
    'start-notification-stream',
    description: 'Sends periodic progress notifications during one tool call',
    inputSchema: JsonSchema.object(
      properties: {
        'interval': JsonSchema.number(
          description: 'Interval in milliseconds between notifications',
          defaultValue: 100,
        ),
        'count': JsonSchema.number(
          description: 'Number of progress updates to send (0 for 100)',
          defaultValue: 50,
        ),
      },
    ),
    callback: (args, extra) async {
      final interval = args['interval'] as num? ?? 100;
      final count = args['count'] as num? ?? 50;

      // Helper function for sleeping
      Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

      final total = count == 0 ? 100 : count.toInt();

      for (var counter = 1; counter <= total; counter++) {
        await extra.sendProgress(
          counter.toDouble(),
          total: total.toDouble(),
          message: 'Progress update $counter',
        );

        // Wait for the specified interval
        await sleep(interval.toInt());
      }

      return CallToolResult.fromContent(
        [
          TextContent(
            text: 'Sent $total progress updates every ${interval}ms',
          ),
        ],
      );
    },
  );

  // Create a simple resource at a fixed URI
  server.registerResource(
    'greeting-resource',
    'https://example.com/greetings/default',
    (mimeType: 'text/plain', description: null),
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          ResourceContents.fromJson({
            'uri': 'https://example.com/greetings/default',
            'text': 'Hello, world!',
            'mimeType': 'text/plain',
          }),
        ],
      );
    },
  );

  return server;
}
