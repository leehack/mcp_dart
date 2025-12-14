import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Example client using the StdioClientTransport to communicate with a server.
/// This client connects to a server, sends requests, and handles responses.
/// It demonstrates how to use the MCP client library with standard I/O.
/// It runs the server example from `example/server_stdio.dart`
/// and communicates with it using the StdioClientTransport.
/// The client sends various requests to the server, including ping, tool calls,
/// resource reads, and prompt calls.
Future<void> main() async {
  // Define the server executable and arguments
  const serverCommand = 'dart';
  // Adjust the path to the server script as needed
  const serverArgs = <String>['run', 'example/server_stdio.dart'];

  // Create StdioServerParameters
  final serverParams = const StdioServerParameters(
    command: serverCommand,
    args: serverArgs,
    stderrMode: ProcessStartMode.normal,
  );

  // Create the StdioClientTransport
  final transport = StdioClientTransport(serverParams);

  // Define client information
  final clientInfo =
      const Implementation(name: 'ExampleClient', version: '1.0.0');

  // Create the MCP client
  final client = Client(clientInfo);

  // Set up error and close handlers
  transport.onerror = (error) {
    print('Transport error: $error');
  };

  transport.onclose = () {
    print('Transport closed.');
  };

  // Connect to the server
  try {
    print('Connecting to server...');
    await client.connect(transport);
    print('Connected to server.');

    // Example: Send a ping request
    print('Sending ping...');
    final pingResult = await client.ping();
    print('Ping successful: ${pingResult.toJson()}');

    print('Listing tools...');
    final tools = await client.listTools();
    print('Resources: ${tools.toJson()}');

    print('Listing resources...');
    final resources = await client.listResources();
    print('Resources: ${resources.resources}');

    print('Listing prompts...');
    final prompts = await client.listPrompts();
    print('Resources: ${prompts.prompts}');

    print('Calling a tool...');
    final toolResult = await client.callTool(
      const CallToolRequestParams(
        name: 'calculate',
        arguments: {'operation': 'add', 'a': 5, 'b': 10},
      ),
    );
    print('Tool result: ${toolResult.toJson()}');

    print('Calling a tool...');
    final resourceResult = await client.readResource(
      const ReadResourceRequestParams(uri: 'file:///logs'),
    );
    print('Tool result: ${resourceResult.toJson()}');

    print('Calling a prompt...');
    final promptResult = await client.getPrompt(
      const GetPromptRequestParams(
        name: 'analyze-code',
        arguments: {'language': "python"},
      ),
    );
    print('Prompt result: ${promptResult.toJson()}');
  } catch (e) {
    print('Error: $e');
  } finally {
    // Close the client and transport
    print('Closing client...');
    await client.close();
    print('Client closed.');
  }
}
