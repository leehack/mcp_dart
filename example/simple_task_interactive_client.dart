import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

// ============================================================================
// Input Handling
// ============================================================================

final StreamController<String> _inputController = StreamController.broadcast();
StreamSubscription<String>? _stdinSubscription;
bool _inputInitialized = false;

void _ensureInputInitialized() {
  if (_inputInitialized) return;
  _inputInitialized = true;
  _stdinSubscription = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _inputController.add(line));
}

void _disposeInput() {
  _stdinSubscription?.cancel();
  _inputController.close();
}

Future<String> question(String prompt) async {
  _ensureInputInitialized();
  stdout.write(prompt);
  return _inputController.stream.first;
}

// ============================================================================
// Main Client Implementation
// ============================================================================

String getTextContent(CallToolResult result) {
  final textContent = result.content.whereType<TextContent>().firstOrNull;
  return textContent?.text ?? '(no text)';
}

Future<ElicitResult> elicitationCallback(ElicitRequest params) async {
  // Give the polling loop a chance to print the status update
  await Future.delayed(const Duration(milliseconds: 200));

  print('\n[Elicitation] Server asks: ${params.message}');

  // Simple terminal prompt for y/n
  final response = await question('Your response (y/n): ');
  final confirmed = ['y', 'yes', 'true', '1'].contains(response.toLowerCase());

  print('[Elicitation] Responding with: confirm=$confirmed');
  return ElicitResult(
    action: 'accept',
    content: {'confirm': confirmed},
  );
}

Future<CreateMessageResult> samplingCallback(
  CreateMessageRequest params,
) async {
  // Give the polling loop a chance to print the status update
  await Future.delayed(const Duration(milliseconds: 200));

  // Get the prompt from the first message
  var prompt = 'unknown';
  if (params.messages.isNotEmpty) {
    final firstMessage = params.messages[0];
    final content = firstMessage.content;
    if (content is SamplingTextContent) {
      prompt = content.text;
    }
  }

  print('\n[Sampling] Server requests LLM completion for: $prompt');

  // Return a hardcoded haiku (in real use, call your LLM here)
  const haiku = '''
Cherry blossoms fall
Softly on the quiet pond
Spring whispers goodbye''';

  print('[Sampling] Responding with haiku');
  return const CreateMessageResult(
    model: 'mock-haiku-model',
    role: SamplingMessageRole.assistant,
    content: SamplingTextContent(text: haiku),
  );
}

Future<void> run(String url) async {
  print('Simple Task Interactive Client (Dart)');
  print('=====================================');
  print('Connecting to $url...');

  // Create client with elicitation and sampling capabilities
  final client = McpClient(
    const Implementation(
      name: 'simple-task-interactive-client',
      version: '1.0.0',
    ),
    options: const McpClientOptions(
      capabilities: ClientCapabilities(
        elicitation: ClientElicitation.formOnly(),
        sampling: ClientCapabilitiesSampling(),
        tasks: ClientCapabilitiesTasks(
          requests: ClientCapabilitiesTasksRequests(
            elicitation: ClientCapabilitiesTasksElicitation(
              create: ClientCapabilitiesTasksElicitationCreate(),
            ),
            sampling: ClientCapabilitiesTasksSampling(
              createMessage: ClientCapabilitiesTasksSamplingCreateMessage(),
            ),
          ),
        ),
      ),
    ),
  );

  // Set up elicitation request handler
  client.onElicitRequest = elicitationCallback;

  // Set up task status notification handler
  // Set up task status notification handler
  client.onTaskStatus = (params) {
    print('[Notification] Task ${params.taskId}: ${params.status.name}'
        '${params.statusMessage != null ? " - ${params.statusMessage}" : ""}');
  };

  // Set up sampling request handler
  client.onSamplingRequest = samplingCallback;

  // Connect to server
  final transport = StreamableHttpClientTransport(Uri.parse(url));
  await client.connect(transport);
  print('Connected!\n');

  // List tools
  final toolsResult = await client.listTools();
  print('Available tools: ${toolsResult.tools.map((t) => t.name).join(', ')}');

  final taskClient = TaskClient(client);

  // Demo 1: Elicitation (confirm_delete)
  print('\n--- Demo 1: Elicitation ---');
  print('Calling confirm_delete tool...');

  var lastStatus1 = '';

  await for (final message in taskClient.callToolStream(
    'confirm_delete',
    {'filename': 'important.txt'},
    task: {'ttl': 60000, 'pollInterval': 200},
  )) {
    if (message is TaskCreatedMessage) {
      print('Task created: ${message.task.taskId}');
    } else if (message is TaskStatusMessage) {
      if (message.task.status.name != lastStatus1) {
        print('Task status: ${message.task.status.name}');
        lastStatus1 = message.task.status.name;
      }
    } else if (message is TaskResultMessage) {
      print('Result: ${getTextContent(message.result as CallToolResult)}');
    } else if (message is TaskErrorMessage) {
      print('Error: ${message.error}');
    }
  }

  // Demo 2: Sampling (write_haiku)
  print('\n--- Demo 2: Sampling ---');
  print('Calling write_haiku tool...');

  var lastStatus2 = '';

  await for (final message in taskClient.callToolStream(
    'write_haiku',
    {'topic': 'autumn leaves'},
    task: {'ttl': 60000},
  )) {
    if (message is TaskCreatedMessage) {
      print('Task created: ${message.task.taskId}');
    } else if (message is TaskStatusMessage) {
      if (message.task.status.name != lastStatus2) {
        print('Task status: ${message.task.status.name}');
        lastStatus2 = message.task.status.name;
      }
    } else if (message is TaskResultMessage) {
      print('Result:\n${getTextContent(message.result as CallToolResult)}');
    } else if (message is TaskErrorMessage) {
      print('Error: ${message.error}');
    }
  }

  // Cleanup
  print('\nDemo complete. Closing connection...');
  await transport.close();
}

void main(List<String> arguments) async {
  var url = 'http://localhost:8000/mcp';

  final parser = arguments.iterator;
  while (parser.moveNext()) {
    if (parser.current == '--url' && parser.moveNext()) {
      url = parser.current;
    }
  }

  try {
    await run(url);
  } catch (e, stack) {
    print('Error running client: $e');
    print(stack);
    exit(1);
  } finally {
    _disposeInput();
  }
}
