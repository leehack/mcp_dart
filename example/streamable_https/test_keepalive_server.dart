import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // Create HTTP server
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 3001);
  print('MCP Keep-Alive Test Server listening on port 3001');
  print('Keep-alive messages will be sent every 5 seconds');

  // Create the MCP server
  final mcpServer = McpServer(
    Implementation(name: 'keepalive-test-server', version: '1.0.0'),
  );

  // Register a simple tool
  mcpServer.tool(
    'test-keepalive',
    description: 'A tool that waits to test keep-alive',
    toolInputSchema: ToolInputSchema(
      properties: {
        'delay': {
          'type': 'number',
          'description': 'Delay in seconds before responding',
          'default': 10,
        },
      },
    ),
    callback: ({args, extra}) async {
      final delay = (args?['delay'] as num? ?? 10).toInt();
      print('Tool called, waiting $delay seconds...');
      
      // Send periodic notifications during the wait
      for (int i = 0; i < delay; i++) {
        await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
            level: LoggingLevel.info,
            data: 'Waiting... ${i + 1}/$delay seconds',
          ),
        ));
        await Future.delayed(Duration(seconds: 1));
      }
      
      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Completed after $delay seconds!'),
        ],
      );
    },
  );

  await for (final request in server) {
    // Set CORS headers
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 
        'Origin, Content-Type, Accept, mcp-session-id');
    request.response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      continue;
    }

    if (request.uri.path != '/mcp') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
      continue;
    }

    try {
      // Create transport with keep-alive enabled (5 seconds for testing)
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => generateUUID(),
          keepAliveInterval: 5, // Send keep-alive every 5 seconds
          enableJsonResponse: false, // Use SSE
        ),
      );

      // Connect transport to MCP server
      await mcpServer.connect(transport);

      // Log transport events
      transport.onclose = () {
        print('Transport closed');
      };

      transport.onerror = (error) {
        print('Transport error: $error');
      };

      // Handle the request
      await transport.handleRequest(request);
      
      print('Request handled, SSE stream should be active with keep-alive');
    } catch (error) {
      print('Error handling request: $error');
      if (!request.response.headers.contentType.toString().contains('event-stream')) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal Server Error')
          ..close();
      }
    }
  }
}
