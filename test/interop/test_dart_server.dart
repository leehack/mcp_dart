import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

McpServer createServer() {
  // Define Server
  final server = McpServer(
    const Implementation(name: 'dart-test-server', version: '1.0.0'),
  );

  // Tools
  server.registerTool(
    'echo',
    description: 'Echoes the message back',
    inputSchema: JsonSchema.object(
      properties: {
        'message': JsonSchema.string(description: 'Message to echo'),
      },
      required: ['message'],
    ),
    callback: (args, extra) async {
      return CallToolResult(
        content: [TextContent(text: args['message'] as String)],
      );
    },
  );

  server.registerTool(
    'add',
    description: 'Adds two numbers',
    inputSchema: JsonSchema.object(
      properties: {
        'a': JsonSchema.number(description: 'First number'),
        'b': JsonSchema.number(description: 'Second number'),
      },
      required: ['a', 'b'],
    ),
    callback: (args, extra) async {
      final a = args['a'] as num;
      final b = args['b'] as num;
      return CallToolResult(
        content: [TextContent(text: '${a + b}')],
      );
    },
  );

  // Resources
  server.registerResource(
    'Test Resource',
    'resource://test',
    (description: 'A test resource', mimeType: 'text/plain'),
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            text: 'This is a test resource',
            mimeType: 'text/plain',
          ),
        ],
      );
    },
  );

  // Prompts
  server.registerPrompt(
    'test_prompt',
    description: 'A test prompt',
    // argsSchema: // Optional
    callback: (args, extra) async {
      return const GetPromptResult(
        description: 'Test Prompt',
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(text: 'Test Prompt'),
          ),
        ],
      );
    },
  );

  return server;
}

void main(List<String> args) async {
  // Enable logging
  Logger.setHandler((name, level, message) {
    print('[${level.name.toUpperCase()}][$name] $message');
  });

  // Parse args
  var transportType = 'stdio';
  int? port;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--transport' && i + 1 < args.length) {
      transportType = args[i + 1];
    }
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[i + 1]);
    }
  }

  // Start Server
  if (transportType == 'stdio') {
    final server = createServer();
    final transport = StdioServerTransport();
    await server.connect(transport);
  } else if (transportType == 'http') {
    if (port == null) {
      print('Error: --port is required for http transport');
      exit(1);
    }
    final transport = StreamableMcpServer(
      serverFactory: (sessionId) => createServer(),
      port: port,
    );
    await transport.start();
    // Keep alive? StreamableMcpServer listens on http
    await ProcessSignal.sigint.watch().first;
    await transport.stop();
  } else {
    print('Unknown transport: $transportType');
    exit(1);
  }
}
