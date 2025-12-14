import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

// Extension to access server from extra (optional, but good practice)
extension McpRequestHandlerExtra on RequestHandlerExtra {
  Server? get mcpServer => null;
}

void main() async {
  final server = StreamableMcpServer(
    serverFactory: (sessionId) {
      print('Creating new server for session: $sessionId');
      return getServer();
    },
    host: '0.0.0.0', // Listen on all interfaces
    port: 3000,
    path: '/mcp',
    eventStore: InMemoryEventStore(), // Use the built-in in-memory event store
  );

  await server.start();
  print('High-level Streamable MCP Server running! Use Ctrl+C to stop.');
}

// Create an MCP server with implementation details
McpServer getServer() {
  // Create the McpServer with the implementation details and options
  final server = McpServer(
    Implementation(name: 'simple-streamable-http-server', version: '1.0.0'),
  );

  // Register a simple tool that returns a greeting
  server.tool(
    'greet',
    description: 'A simple greeting tool',
    toolInputSchema: ToolInputSchema(
      properties: {
        'name': {
          'type': 'string',
          'description': 'Name to greet',
        },
      },
      required: ['name'],
    ),
    callback: ({args, meta, extra}) async {
      final name = args?['name'] as String? ?? 'world';
      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Hello, $name!'),
        ],
      );
    },
  );

  // Register a tool that sends multiple greetings with notifications
  server.tool(
    'multi-greet',
    description:
        'A tool that sends different greetings with delays between them',
    toolInputSchema: ToolInputSchema(
      properties: {
        'name': {
          'type': 'string',
          'description': 'Name to greet',
        },
      },
      required: [],
    ),
    annotations: ToolAnnotations(
      title: 'Multiple Greeting Tool',
      readOnlyHint: true,
      openWorldHint: false,
    ),
    callback: ({args, meta, extra}) async {
      final name = args?['name'] as String? ?? 'world';

      // Helper function for sleeping
      Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

      // Send debug notification
      await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
        level: LoggingLevel.debug,
        data: 'Starting multi-greet for $name',
      )));

      await sleep(1000); // Wait 1 second before first greeting

      // Send first info notification
      await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
        level: LoggingLevel.info,
        data: 'Sending first greeting to $name',
      )));

      await sleep(1000); // Wait another second before second greeting

      // Send second info notification
      await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
        level: LoggingLevel.info,
        data: 'Sending second greeting to $name',
      )));

      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Good morning, $name!'),
        ],
      );
    },
  );

  // Register a simple prompt
  server.prompt(
    'greeting-template',
    description: 'A simple greeting prompt template',
    argsSchema: {
      'name': PromptArgumentDefinition(
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

  // Register a tool specifically for testing resumability
  server.tool(
    'start-notification-stream',
    description:
        'Starts sending periodic notifications for testing resumability',
    toolInputSchema: ToolInputSchema(
      properties: {
        'interval': {
          'type': 'number',
          'description': 'Interval in milliseconds between notifications',
          'default': 100,
        },
        'count': {
          'type': 'number',
          'description': 'Number of notifications to send (0 for 100)',
          'default': 50,
        },
      },
    ),
    callback: ({args, meta, extra}) async {
      final interval = args?['interval'] as num? ?? 100;
      final count = args?['count'] as num? ?? 50;

      // Helper function for sleeping
      Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

      var counter = 0;

      while (count == 0 || counter < count) {
        counter++;
        try {
          await extra?.sendNotification(JsonRpcLoggingMessageNotification(
              logParams: LoggingMessageNotificationParams(
            level: LoggingLevel.info,
            data:
                'Periodic notification #$counter at ${DateTime.now().toIso8601String()}',
          )));
        } catch (error) {
          print('Error sending notification: $error');
        }

        // Wait for the specified interval
        await sleep(interval.toInt());
      }

      return CallToolResult.fromContent(
        content: [
          TextContent(
            text: 'Started sending periodic notifications every ${interval}ms',
          ),
        ],
      );
    },
  );

  // Create a simple resource at a fixed URI
  server.resource(
    'greeting-resource',
    'https://example.com/greetings/default',
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          ResourceContents.fromJson({
            'uri': 'https://example.com/greetings/default',
            'text': 'Hello, world!',
            'mimeType': 'text/plain'
          }),
        ],
      );
    },
    metadata: (mimeType: 'text/plain', description: null),
  );

  return server;
}
