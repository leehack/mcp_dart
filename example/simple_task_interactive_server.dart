import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

// ============================================================================
// Server Implementation
// ============================================================================

void main() async {
  final server = InteractiveServer();
  await server.start();
}

class SessionContext {
  final McpServer server;
  final InMemoryTaskStore store;
  final InMemoryTaskMessageQueue queue;
  final TaskResultHandler taskResultHandler;

  SessionContext({
    required this.server,
    required this.store,
    required this.queue,
    required this.taskResultHandler,
  });

  void dispose() {
    store.dispose();
    queue.dispose();
    taskResultHandler.dispose();
  }
}

class InteractiveServer {
  final Map<String, StreamableHTTPServerTransport> _transports = {};
  final Map<String, SessionContext> _sessions = {};

  InteractiveServer();

  /// Creates a configured McpServer instance for a specific session
  SessionContext _createSessionContext(String sessionId) {
    print('[Server] Creating new McpServer for session $sessionId');

    final server = McpServer(
      const Implementation(name: 'simple-task-interactive', version: '1.0.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          tasks: ServerCapabilitiesTasks(listChanged: true),
        ),
      ),
    );

    server.onError = (error) => print('[Server Protocol Error] $error');

    final store = InMemoryTaskStore();
    final queue = InMemoryTaskMessageQueue();
    final handler = TaskResultHandler(store, queue, server);

    final context = SessionContext(
      server: server,
      store: store,
      queue: queue,
      taskResultHandler: handler,
    );

    // Register Handlers
    _registerHandlers(context);

    return context;
  }

  void _registerHandlers(SessionContext context) {
    final server = context.server;
    final store = context.store;
    final handler = context.taskResultHandler;

    // Register Task Handlers
    server.experimental.onListTasks((extra) async {
      return await store.listTasks(null);
    });

    server.experimental.onGetTask((taskId, extra) async {
      final task = await store.getTask(taskId);
      if (task == null) {
        throw McpError(ErrorCode.invalidParams.value, "Task not found");
      }
      return task;
    });

    server.experimental.onTaskResult((taskId, extra) async {
      print('[Server] tasks/result called for task $taskId');
      return await handler.handle(taskId);
    });

    server.experimental.onCancelTask((taskId, extra) async {
      print('[Server] tasks/cancel called for task $taskId');
      final cancelled = await store.cancelTask(taskId);
      if (!cancelled) {
        throw McpError(
          ErrorCode.invalidParams.value,
          "Cannot cancel task: not found or already terminal",
        );
      }
    });

    // Register Tools
    server.experimental.registerToolTask(
      'confirm_delete',
      description:
          'Asks for confirmation before deleting (demonstrates elicitation)',
      inputSchema: JsonSchema.object(
        properties: {
          'filename': JsonSchema.string(),
        },
      ),
      execution: const ToolExecution(taskSupport: 'optional'),
      handler: SimpleToolTaskHandler(
        context,
        'confirm_delete',
        _runConfirmDelete,
      ),
    );

    server.experimental.registerToolTask(
      'write_haiku',
      description: 'Asks LLM to write a haiku (demonstrates sampling)',
      inputSchema: JsonSchema.object(
        properties: {
          'topic': JsonSchema.string(),
        },
      ),
      execution: const ToolExecution(taskSupport: 'optional'),
      handler: SimpleToolTaskHandler(
        context,
        'write_haiku',
        _runWriteHaiku,
      ),
    );
  }

  Future<void> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8000);
    print('Starting server on http://localhost:8000/mcp');

    await for (final httpRequest in httpServer) {
      if (httpRequest.method == 'POST' && httpRequest.uri.path == '/mcp') {
        await _handlePost(httpRequest);
      } else if (httpRequest.method == 'GET' &&
          httpRequest.uri.path == '/mcp') {
        await _handleGet(httpRequest);
      } else {
        httpRequest.response.statusCode = 404;
        httpRequest.response.close();
      }
    }
  }

  Future<void> _runConfirmDelete(
    SessionContext context,
    String taskId,
    Map<String, dynamic> args,
  ) async {
    _runTask(context, taskId, (session) async {
      final filename = args['filename'] ?? 'unknown.txt';
      print('[Server] confirm_delete: asking about $filename');

      final result = await session.elicit(
        "Are you sure you want to delete '$filename'?",
        JsonSchema.object(
          properties: {
            'confirm': JsonSchema.boolean(),
          },
          required: ['confirm'],
        ),
      );

      String text;
      if (result.content != null) {
        final confirmed = result.content!['confirm'] == true;
        text = confirmed ? "Deleted '$filename'" : "Deletion cancelled";
      } else {
        text = "Deletion cancelled";
      }

      await context.store.storeTaskResult(
        taskId,
        TaskStatus.completed,
        CallToolResult.fromContent([TextContent(text: text)]),
      );
    });
  }

  Future<void> _runWriteHaiku(
    SessionContext context,
    String taskId,
    Map<String, dynamic> args,
  ) async {
    _runTask(context, taskId, (session) async {
      final topic = args['topic'] ?? 'nature';
      print('[Server] write_haiku: topic $topic');

      final result = await session.createMessage(
        [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: "Write a haiku about $topic"),
          ),
        ],
        50,
      );

      String haiku = "No response";
      if (result.content is SamplingTextContent) {
        haiku = (result.content as SamplingTextContent).text;
      }

      await context.store.storeTaskResult(
        taskId,
        TaskStatus.completed,
        CallToolResult.fromContent(
          [TextContent(text: "Haiku:\n$haiku")],
        ),
      );
    });
  }

  Future<void> _runTask(
    SessionContext context,
    String taskId,
    Future<void> Function(TaskSession) action,
  ) async {
    final session =
        TaskSession(context.server, taskId, context.store, context.queue);

    try {
      await action(session);
    } catch (e) {
      print('[Server] Task $taskId failed: $e');
      await context.store.storeTaskResult(
        taskId,
        TaskStatus.failed,
        CallToolResult(
          content: [TextContent(text: "Error: $e")],
          isError: true,
        ),
      );
    }
  }

  Future<void> _handlePost(HttpRequest req) async {
    final sessionId = req.headers.value('mcp-session-id');

    if (sessionId != null && _transports.containsKey(sessionId)) {
      await _transports[sessionId]!.handleRequest(req);
      return;
    }

    final body = await utf8.decodeStream(req);
    final json = jsonDecode(body) as Map<String, dynamic>;

    if (json['method'] == 'initialize') {
      // Create a temporary server instance for this connection
      final tempContext = _createSessionContext("pending-init");

      late StreamableHTTPServerTransport createdTransport;

      final options = StreamableHTTPServerTransportOptions(
        sessionIdGenerator: () => generateUUID(),
        onsessioninitialized: (sid) {
          print('Session initialized: $sid');
          _transports[sid] = createdTransport;

          // Move server from pending to active session map
          // Note: handlers are already registered on tempServer
          _sessions[sid] = tempContext;
          print('Server mapped to session $sid');
        },
      );

      createdTransport = StreamableHTTPServerTransport(options: options);

      createdTransport.onclose = () {
        if (createdTransport.sessionId != null) {
          final sid = createdTransport.sessionId!;
          print('Transport closed for session $sid');
          _transports.remove(sid);

          final context = _sessions.remove(sid);
          context?.dispose();
        }
      };

      // Connect server to transport immediately
      await tempContext.server.connect(createdTransport);

      if (sessionId == null) {
        await createdTransport.handleRequest(req, json);
      }
    } else {
      req.response.statusCode = 400;
      req.response.write("Missing session ID");
      req.response.close();
    }
  }

  Future<void> _handleGet(HttpRequest req) async {
    final sessionId = req.headers.value('mcp-session-id');
    if (sessionId != null && _transports.containsKey(sessionId)) {
      await _transports[sessionId]!.handleRequest(req);
    } else {
      req.response.statusCode = 400;
      req.response.write("Invalid Session ID");
      req.response.close();
    }
  }
}

class SimpleToolTaskHandler implements ToolTaskHandler {
  final SessionContext context;
  final String toolName;
  final Future<void> Function(SessionContext, String, Map<String, dynamic>)
      runner;

  SimpleToolTaskHandler(this.context, this.toolName, this.runner);

  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final task = await context.store.createTask(
      const TaskCreationParams(), // ttl
      extra?.requestId ?? -1,
      {'name': toolName, 'input': args ?? {}},
      extra?.sessionId,
    );
    print('\n[Server] $toolName called, task created: ${task.taskId}');

    // Start background execution
    runner(context, task.taskId, args ?? {});

    return CreateTaskResult(task: task);
  }

  @override
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra) async {
    final task = await context.store.getTask(taskId);
    if (task == null) {
      throw McpError(ErrorCode.invalidParams.value, 'Task not found');
    }
    return task;
  }

  @override
  Future<void> cancelTask(String taskId, RequestHandlerExtra? extra) async {
    await context.store.cancelTask(taskId);
  }

  @override
  Future<CallToolResult> getTaskResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) async {
    final result = await context.store.getTaskResult(taskId);
    if (result is CallToolResult) {
      return result;
    }
    throw McpError(ErrorCode.internalError.value, 'Unexpected result type');
  }
}
