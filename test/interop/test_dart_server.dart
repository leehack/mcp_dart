import 'dart:convert';
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

  // Prompt: greeting - with completable language argument
  server.registerPrompt(
    'greeting',
    description: 'A greeting prompt with a completable language argument',
    argsSchema: {
      'language': PromptArgumentDefinition(
        description: 'The language for the greeting',
        required: true,
        completable: CompletableField(
          def: CompletableDef(
            complete: (value) {
              final languages = ['English', 'Spanish', 'French', 'German'];
              return languages
                  .where((l) => l.toLowerCase().startsWith(value.toLowerCase()))
                  .toList();
            },
          ),
        ),
      ),
    },
    callback: (args, extra) async {
      final language = (args?['language'] as String?) ?? 'English';
      final greetings = {
        'English': 'Hello!',
        'Spanish': '¡Hola!',
        'French': 'Bonjour!',
        'German': 'Guten Tag!',
      };
      return GetPromptResult(
        description: 'Greeting in $language',
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: greetings[language] ?? 'Hello in $language!',
            ),
          ),
        ],
      );
    },
  );

  // Tool: get_roots - Lists client's roots
  server.registerTool(
    'get_roots',
    description: 'Lists the roots provided by the client',
    callback: (args, extra) async {
      try {
        final result = await server.server.listRoots();
        final rootsJson =
            result.roots.map((r) => {'uri': r.uri, 'name': r.name}).toList();
        return CallToolResult(
          content: [TextContent(text: jsonEncode(rootsJson))],
        );
      } catch (e) {
        return CallToolResult(
          content: [TextContent(text: 'Error getting roots: $e')],
          isError: true,
        );
      }
    },
  );

  // Tool: elicit_input - Requests user input from client
  server.registerTool(
    'elicit_input',
    description: 'Requests structured input from the client',
    inputSchema: JsonSchema.object(
      properties: {
        'message':
            JsonSchema.string(description: 'The message to show the user'),
      },
      required: ['message'],
    ),
    callback: (args, extra) async {
      try {
        final message = args['message'] as String;
        final result = await server.server.elicitInput(
          ElicitRequest.form(
            message: message,
            requestedSchema: JsonSchema.object(
              properties: {
                'confirmed':
                    JsonSchema.boolean(description: 'User confirmation'),
              },
              required: ['confirmed'],
            ),
          ),
        );
        return CallToolResult(
          content: [TextContent(text: jsonEncode(result.toJson()))],
        );
      } catch (e) {
        return CallToolResult(
          content: [TextContent(text: 'Error eliciting input: $e')],
          isError: true,
        );
      }
    },
  );

  // Tool: sample_llm - Requests LLM completion from client
  server.registerTool(
    'sample_llm',
    description: 'Requests an LLM completion from the client',
    inputSchema: JsonSchema.object(
      properties: {
        'prompt':
            JsonSchema.string(description: 'The prompt to send to the LLM'),
      },
      required: ['prompt'],
    ),
    callback: (args, extra) async {
      try {
        final prompt = args['prompt'] as String;
        final result = await server.server.createMessage(
          CreateMessageRequest(
            messages: [
              SamplingMessage(
                role: SamplingMessageRole.user,
                content: SamplingTextContent(text: prompt),
              ),
            ],
            maxTokens: 100,
          ),
        );
        final content = result.content;
        final text = content is SamplingTextContent
            ? content.text
            : jsonEncode(content.toJson());
        return CallToolResult(
          content: [TextContent(text: text)],
        );
      } catch (e) {
        return CallToolResult(
          content: [TextContent(text: 'Error sampling LLM: $e')],
          isError: true,
        );
      }
    },
  );

  // Tool: progress_demo - Sends progress notifications during execution
  server.registerTool(
    'progress_demo',
    description: 'Demonstrates progress notifications',
    inputSchema: JsonSchema.object(
      properties: {
        'steps': JsonSchema.number(
          description: 'Number of progress steps (default 4)',
        ),
      },
    ),
    callback: (args, extra) async {
      final steps = (args['steps'] as num?)?.toInt() ?? 4;
      final totalSteps = steps.clamp(1, 10);

      for (int i = 0; i <= totalSteps; i++) {
        final progress = ((i / totalSteps) * 100).round();

        // Send progress notification if we have a progress token
        final progressToken = extra.meta?['progressToken'];
        if (progressToken != null) {
          await extra.sendNotification(
            // Fixed to use extra.sendNotification
            JsonRpcProgressNotification(
              progressParams: ProgressNotificationParams(
                progressToken: progressToken,
                progress: progress,
                total: 100,
              ),
            ),
          );
        }

        // Simulate work
        await Future.delayed(const Duration(milliseconds: 50));
      }

      return CallToolResult(
        content: [
          TextContent(
            text: 'Completed $totalSteps steps with progress notifications',
          ),
        ],
      );
    },
  );

  final taskHandler = TestTaskHandler();

  // Task-based Tool
  server.experimental.registerToolTask(
    'delayed_echo',
    description: 'Echoes a message after a delay',
    inputSchema: JsonSchema.object(
      properties: {
        'message': JsonSchema.string(description: 'Message to echo'),
        'delay': JsonSchema.number(description: 'Delay in milliseconds'),
      },
      required: ['message'],
    ),
    handler: taskHandler,
  );

  // Register Task Capabilities (Global)
  server.experimental.onListTasks((extra) async {
    return ListTasksResult(tasks: await taskHandler.listTasks());
  });

  server.experimental.onCancelTask((taskId, extra) async {
    await taskHandler.cancelTask(taskId, extra);
  });

  server.experimental.onGetTask((taskId, extra) async {
    // Determine which tool manages this task or simple lookup
    return await taskHandler.getTask(taskId, extra);
  });

  server.experimental.onTaskResult((taskId, extra) async {
    // Determine which tool manages this task or simple lookup
    return await taskHandler.getTaskResult(taskId, extra);
  });

  return server;
}

class TestTaskHandler implements ToolTaskHandler {
  final Map<String, _TaskState> _tasks = {};
  int _counter = 0;

  Future<List<Task>> listTasks() async {
    return _tasks.values.map((s) => s.task).toList();
  }

  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    print('DEBUG: createTask called with $args');
    try {
      final taskId = 'task-${++_counter}';
      final message = args?['message'] as String? ?? '';
      final delay = args?['delay'] as num? ?? 100;

      final task = Task(
        taskId: taskId,
        status: TaskStatus.working,
        statusMessage: 'Starting...',
        createdAt: DateTime.now().toIso8601String(),
        lastUpdatedAt: DateTime.now().toIso8601String(),
        meta: {'message': message}, // Store message in metadata
        pollInterval: 100,
      );

      _tasks[taskId] = _TaskState(task, message, delay.toInt());

      // Start processing in background
      _processTask(taskId);

      return CreateTaskResult(task: task);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _processTask(String taskId) async {
    final state = _tasks[taskId];
    if (state == null) return;

    // Simulate progress
    await Future.delayed(Duration(milliseconds: state.delay ~/ 2));
    if (!_tasks.containsKey(taskId)) return; // Cancelled?

    // Manual copyWith for progress
    state.task = Task(
      taskId: state.task.taskId,
      status: TaskStatus.working,
      statusMessage: 'Halfway there...',
      createdAt: state.task.createdAt,
      lastUpdatedAt: DateTime.now().toIso8601String(),
      pollInterval: 100,
      // meta: state.task.meta, // Optional to keep meta
    );

    await Future.delayed(Duration(milliseconds: state.delay ~/ 2));
    if (!_tasks.containsKey(taskId)) return;

    state.task = Task(
      taskId: state.task.taskId,
      status: TaskStatus.completed,
      statusMessage: 'Done!',
      createdAt: state.task.createdAt,
      lastUpdatedAt: DateTime.now().toIso8601String(),
      pollInterval: 100,
      // meta: state.task.meta,
    );
  }

  @override
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra) async {
    final state = _tasks[taskId];
    if (state == null) {
      throw McpError(ErrorCode.invalidParams.value, 'Task not found');
    }
    return state.task;
  }

  @override
  Future<void> cancelTask(String taskId, RequestHandlerExtra? extra) async {
    final state = _tasks[taskId];
    if (state != null) {
      state.task = Task(
        taskId: state.task.taskId,
        status: TaskStatus.cancelled,
        statusMessage: 'Cancelled',
        meta: state.task.meta,
        createdAt: state.task.createdAt,
        lastUpdatedAt: DateTime.now().toIso8601String(),
      );
      // Keep it for a bit or remove? Usually keep for history.
      // But for this simple test, we just mark it cancelled.
    }
  }

  @override
  Future<CallToolResult> getTaskResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) async {
    final state = _tasks[taskId];
    if (state == null) {
      throw McpError(ErrorCode.invalidParams.value, "Task not found");
    }
    if (!state.task.status.isTerminal) {
      throw McpError(ErrorCode.invalidParams.value, "Task not complete");
    }

    return CallToolResult(
      content: [TextContent(text: state.message)],
    );
  }
}

class _TaskState {
  Task task;
  final String message;
  final int delay;

  _TaskState(this.task, this.message, this.delay);
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
