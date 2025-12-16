import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

// Global client and transport for interactive commands
Client? client;
StreamableHttpClientTransport? transport;
String serverUrl = 'http://localhost:3000/mcp';
String? notificationsToolLastEventId;
String? sessionId;

// Track received notifications for debugging resumability
int notificationCount = 0;

Future<void> main() async {
  print('MCP Interactive Client');
  print('=====================');

  // Connect to server immediately with default settings
  await connect();

  // Print help and start the command loop
  printHelp();
  await commandLoop();
}

void printHelp() {
  print('\nAvailable commands:');
  print(
    '  connect [url]              - Connect to MCP server (default: http://localhost:3000/mcp)',
  );
  print('  disconnect                 - Disconnect from server');
  print('  terminate-session          - Terminate the current session');
  print('  reconnect                  - Reconnect to the server');
  print('  list-tools                 - List available tools');
  print(
    '  call-tool <name> [args]    - Call a tool with optional JSON arguments',
  );
  print('  greet [name]               - Call the greet tool');
  print(
    '  multi-greet [name]         - Call the multi-greet tool with notifications',
  );
  print(
    '  start-notifications [interval] [count] - Start periodic notifications',
  );
  print('  list-prompts               - List available prompts');
  print(
    '  get-prompt [name] [args]   - Get a prompt with optional JSON arguments',
  );
  print('  list-resources             - List available resources');
  print('  help                       - Show this help');
  print('  quit                       - Exit the program');
}

Future<void> commandLoop() async {
  final inputController = StreamController<String>.broadcast();
  final stdinStream =
      stdin.transform(utf8.decoder).transform(const LineSplitter());

  // Pass stdin data to our controller
  stdinStream.listen((input) {
    inputController.add(input);
  });

  bool running = true;
  while (running) {
    stdout.write('\n> ');
    final String input = await inputController.stream.first;
    final args = input.trim().split(RegExp(r'\s+'));
    final command = args.isNotEmpty ? args[0].toLowerCase() : '';

    try {
      switch (command) {
        case 'connect':
          await connect(args.length > 1 ? args[1] : null);
          break;

        case 'disconnect':
          await disconnect();
          break;

        case 'terminate-session':
          await terminateSession();
          break;

        case 'reconnect':
          await reconnect();
          break;

        case 'list-tools':
          await listTools();
          break;

        case 'call-tool':
          if (args.length < 2) {
            print('Usage: call-tool <name> [args]');
          } else {
            final toolName = args[1];
            Map<String, dynamic> toolArgs = {};
            if (args.length > 2) {
              try {
                toolArgs = jsonDecode(args.sublist(2).join(' '));
              } catch (_) {
                print('Invalid JSON arguments. Using empty args.');
              }
            }
            await callTool(toolName, toolArgs);
          }
          break;

        case 'greet':
          await callGreetTool(args.length > 1 ? args[1] : 'MCP User');
          break;

        case 'multi-greet':
          await callMultiGreetTool(args.length > 1 ? args[1] : 'MCP User');
          break;

        case 'start-notifications':
          final interval =
              args.length > 1 ? int.tryParse(args[1]) ?? 2000 : 2000;
          final count = args.length > 2 ? int.tryParse(args[2]) : 10;
          await startNotifications(interval, count);
          break;

        case 'list-prompts':
          await listPrompts();
          break;

        case 'get-prompt':
          if (args.length < 2) {
            print('Usage: get-prompt <name> [args]');
          } else {
            final promptName = args[1];
            Map<String, dynamic> promptArgs = {};
            if (args.length > 2) {
              try {
                promptArgs = jsonDecode(args.sublist(2).join(' '));
              } catch (_) {
                print('Invalid JSON arguments. Using empty args.');
              }
            }
            await getPrompt(promptName, promptArgs);
          }
          break;

        case 'list-resources':
          await listResources();
          break;

        case 'help':
          printHelp();
          break;

        case 'quit':
        case 'exit':
          await cleanup();
          running = false;
          inputController.close();
          break;

        default:
          if (command.isNotEmpty) {
            print('Unknown command: $command');
          }
          break;
      }
    } catch (error) {
      print('Error executing command: $error');
    }
  }
}

Future<void> connect([String? url]) async {
  if (client != null) {
    print('Already connected. Disconnect first.');
    return;
  }

  if (url != null) {
    serverUrl = url;
  }

  print('Connecting to $serverUrl...');

  try {
    // Create a new client
    client = Client(
      const Implementation(name: 'example-client', version: '1.0.0'),
    );
    client!.onerror = (error) {
      print('\x1b[31mClient error: $error\x1b[0m');
    };

    transport = StreamableHttpClientTransport(
      Uri.parse(serverUrl),
      opts: StreamableHttpClientTransportOptions(
        sessionId: sessionId,
      ),
    );

    // Set up notification handlers
    client!.setNotificationHandler(
      "notifications/message",
      (notification) async {
        // Type check is not needed since the notification factory ensures correct type
        notificationCount++;
        final params = notification.logParams;
        print(
          '\nNotification #$notificationCount: ${params.level} - ${params.data}',
        );
        // Re-display the prompt
        stdout.write('> ');
        return Future.value();
      },
      (params, meta) => JsonRpcLoggingMessageNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    client!.setNotificationHandler(
      "notifications/resources/list_changed",
      (notification) async {
        print('\nResource list changed notification received!');
        try {
          if (client == null) {
            print('Client disconnected, cannot fetch resources');
            return;
          }
          final resourcesResult = await client!.listResources();
          print(
            'Available resources count: ${resourcesResult.resources.length}',
          );
        } catch (_) {
          print('Failed to list resources after change notification');
        }
        // Re-display the prompt
        stdout.write('> ');
        return Future.value();
      },
      (params, meta) => JsonRpcResourceListChangedNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    // Connect the client
    await client!.connect(transport!);
    sessionId = transport!.sessionId;
    print('Transport created with session ID: $sessionId');
    print('Connected to MCP server');
  } catch (error) {
    print('Failed to connect: $error');
    client = null;
    transport = null;
  }
}

Future<void> disconnect() async {
  if (client == null || transport == null) {
    print('Not connected.');
    return;
  }

  try {
    await transport!.close();
    print('Disconnected from MCP server');
    client = null;
    transport = null;
  } catch (error) {
    print('Error disconnecting: $error');
  }
}

Future<void> terminateSession() async {
  if (client == null || transport == null) {
    print('Not connected.');
    return;
  }

  try {
    print('Terminating session with ID: ${transport!.sessionId}');
    await transport!.terminateSession();
    print('Session terminated successfully');

    // Check if sessionId was cleared after termination
    if (transport!.sessionId == null) {
      print('Session ID has been cleared');
      sessionId = null;

      // Also close the transport and clear client objects
      await transport!.close();
      print('Transport closed after session termination');
      client = null;
      transport = null;
    } else {
      print(
        'Server responded with 405 Method Not Allowed (session termination not supported)',
      );
      print('Session ID is still active: ${transport!.sessionId}');
    }
  } catch (error) {
    print('Error terminating session: $error');
  }
}

Future<void> reconnect() async {
  if (client != null) {
    await disconnect();
  }
  await connect();
}

Future<void> listTools() async {
  if (client == null) {
    print('Not connected to server.');
    return;
  }

  try {
    final toolsResult = await client!.listTools();

    print('Available tools:');
    if (toolsResult.tools.isEmpty) {
      print('  No tools available');
    } else {
      for (final tool in toolsResult.tools) {
        print('  - ${tool.name}: ${tool.description}');
      }
    }
  } catch (error) {
    print('Tools not supported by this server ($error)');
  }
}

// Removed the RequestOptions class since it conflicts with the one from the library

Future<void> callTool(String name, Map<String, dynamic> args) async {
  if (client == null) {
    print('Not connected to server.');
    return;
  }

  try {
    final params = CallToolRequest(
      name: name,
      arguments: args,
    );

    print('Calling tool \'$name\' with args: $args');

    final result = await client!.callTool(
      params,
      options: RequestOptions(
        onprogress: (progress) {
          // Optional progress handler
          print('Progress: ${progress.progress}/${progress.total ?? '?'}');
        },
        timeout: const Duration(seconds: 30),
        resetTimeoutOnProgress: true,
      ),
    );

    print('Tool result:');
    for (final item in result.content) {
      if (item is TextContent) {
        print('  ${item.text}');
      } else {
        print('  ${item.runtimeType} content: $item');
      }
    }
  } catch (error) {
    print('Error calling tool $name: $error');
  }
}

Future<void> callGreetTool(String name) async {
  await callTool('greet', {'name': name});
}

Future<void> callMultiGreetTool(String name) async {
  print('Calling multi-greet tool with notifications...');
  await callTool('multi-greet', {'name': name});
}

Future<void> startNotifications(int interval, int? count) async {
  print(
    'Starting notification stream: interval=${interval}ms, count=${count ?? 'unlimited'}',
  );
  await callTool(
    'start-notification-stream',
    {'interval': interval, 'count': count},
  );
}

Future<void> listPrompts() async {
  if (client == null) {
    print('Not connected to server.');
    return;
  }

  try {
    final promptsResult = await client!.listPrompts();
    print('Available prompts:');
    if (promptsResult.prompts.isEmpty) {
      print('  No prompts available');
    } else {
      for (final prompt in promptsResult.prompts) {
        print('  - ${prompt.name}: ${prompt.description}');
      }
    }
  } catch (error) {
    print('Prompts not supported by this server ($error)');
  }
}

Future<void> getPrompt(String name, Map<String, dynamic> args) async {
  if (client == null) {
    print('Not connected to server.');
    return;
  }

  try {
    final params = GetPromptRequestParams(
      name: name,
      arguments: Map<String, String>.from(
        args.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
      ),
    );

    final promptResult = await client!.getPrompt(params);
    print('Prompt template:');
    for (int i = 0; i < promptResult.messages.length; i++) {
      final msg = promptResult.messages[i];
      if (msg.content is TextContent) {
        print('  [${i + 1}] ${msg.role}: ${(msg.content as TextContent).text}');
      } else {
        print('  [${i + 1}] ${msg.role}: [Non-text content]');
      }
    }
  } catch (error) {
    print('Error getting prompt $name: $error');
  }
}

Future<void> listResources() async {
  if (client == null) {
    print('Not connected to server.');
    return;
  }

  try {
    final resourcesResult = await client!.listResources();

    print('Available resources:');
    if (resourcesResult.resources.isEmpty) {
      print('  No resources available');
    } else {
      for (final resource in resourcesResult.resources) {
        print('  - ${resource.name}: ${resource.uri}');
      }
    }
  } catch (error) {
    print('Resources not supported by this server ($error)');
  }
}

Future<void> cleanup() async {
  if (client != null && transport != null) {
    try {
      // First try to terminate the session gracefully
      if (transport!.sessionId != null) {
        try {
          print('Terminating session before exit...');
          await transport!.terminateSession();
          print('Session terminated successfully');
        } catch (error) {
          print('Error terminating session: $error');
        }
      }

      // Then close the transport
      await transport!.close();
    } catch (error) {
      print('Error closing transport: $error');
    }
  }

  print('\nGoodbye!');
  exit(0);
}

// Set up special keyboard handler for Escape key
void setupKeyboardHandler() {
  // In Dart, handling raw keyboard input outside of terminal packages
  // is not as straightforward as in Node.js.
  // For simplicity in this example, we'll skip the raw mode keyboard handling.
  // A complete implementation would use a package like 'dart_console' or similar.

  // This would be the place to set up special key handling like the Escape key in the TypeScript version
  print(
    'Note: Raw keyboard handling (like ESC to disconnect) is not implemented in this example.',
  );
}

// Handle program exit
void handleSigInt() {
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nReceived SIGINT. Cleaning up...');
    await cleanup();
  });
}

// Initialize keyboard and signal handlers
void setupHandlers() {
  setupKeyboardHandler();
  handleSigInt();
}

// Call handlers setup before starting the client
void initClient() {
  setupHandlers();
}

// Initialize and run the client
Future<void> main2() async {
  initClient();
  await main();
}
