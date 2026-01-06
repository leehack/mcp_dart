/// MCP Service for the Jaspr client.
///
/// This module provides a type-safe MCP client service with support for
/// elicitation and sampling callbacks.
library;

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart' hide LogLevel;

// ============================================================================
// Types
// ============================================================================

/// Represents the connection state of the MCP client.
enum McpConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// A sealed class representing all possible MCP client events.
sealed class McpEvent {
  const McpEvent();
}

/// Event emitted when connection state changes.
final class ConnectionStateEvent extends McpEvent {
  final McpConnectionState state;
  final String? message;

  const ConnectionStateEvent(this.state, [this.message]);
}

/// Event emitted when tools are listed.
final class ToolsListedEvent extends McpEvent {
  final List<Tool> tools;

  const ToolsListedEvent(this.tools);
}

/// Event emitted for log messages.
final class LogEvent extends McpEvent {
  final McpLogLevel level;
  final String message;
  final DateTime timestamp;

  LogEvent(this.level, this.message) : timestamp = DateTime.now();
}

/// Log levels for events.
enum McpLogLevel { info, warning, error, debug }

/// Event emitted when a task is created.
final class TaskCreatedEvent extends McpEvent {
  final Task task;

  const TaskCreatedEvent(this.task);
}

/// Event emitted when a task status changes.
final class TaskStatusEvent extends McpEvent {
  final Task task;

  const TaskStatusEvent(this.task);
}

/// Event emitted when a task completes with a result.
final class TaskResultEvent extends McpEvent {
  final String taskId;
  final CallToolResult result;

  const TaskResultEvent(this.taskId, this.result);
}

/// Event emitted when a task fails with an error.
final class TaskErrorEvent extends McpEvent {
  final String taskId;
  final Object error;

  const TaskErrorEvent(this.taskId, this.error);
}

/// Event emitted when elicitation is requested.
final class ElicitationRequestEvent extends McpEvent {
  final String requestId;
  final ElicitRequest request;
  final Completer<ElicitResult> completer;

  const ElicitationRequestEvent(this.requestId, this.request, this.completer);
}

/// Event emitted when sampling is requested.
final class SamplingRequestEvent extends McpEvent {
  final String requestId;
  final CreateMessageRequest request;
  final Completer<CreateMessageResult> completer;

  const SamplingRequestEvent(this.requestId, this.request, this.completer);
}

/// Event emitted when resources are listed.
final class ResourcesListedEvent extends McpEvent {
  final List<Resource> resources;
  const ResourcesListedEvent(this.resources);
}

/// Event emitted when resource templates are listed.
final class ResourceTemplatesListedEvent extends McpEvent {
  final List<ResourceTemplate> templates;
  const ResourceTemplatesListedEvent(this.templates);
}

/// Event emitted when a resource is read.
final class ResourceReadEvent extends McpEvent {
  final ReadResourceResult result;
  const ResourceReadEvent(this.result);
}

/// Event emitted when prompts are listed.
final class PromptsListedEvent extends McpEvent {
  final List<Prompt> prompts;
  const PromptsListedEvent(this.prompts);
}

/// Event emitted when a prompt is retrieved.
final class PromptGetEvent extends McpEvent {
  final GetPromptResult result;
  const PromptGetEvent(this.result);
}

/// Event emitted when tasks are listed.
final class TasksListedEvent extends McpEvent {
  final List<Task> tasks;
  const TasksListedEvent(this.tasks);
}

/// Event emitted for tool progress updates.
final class ToolProgressEvent extends McpEvent {
  final String toolName;
  final double progress;
  final double total;

  const ToolProgressEvent(this.toolName, this.progress, this.total);
}

// ============================================================================
// MCP Service
// ============================================================================

/// Type-safe MCP client service for web applications.
///
/// This service manages the MCP client connection and provides a stream-based
/// API for handling events like connection state changes, tool listings,
/// elicitation requests, and sampling requests.
class McpService {
  // Private state
  McpClient? _client;
  StreamableHttpClientTransport? _transport;
  TaskClient? _taskClient;
  String? _sessionId;

  final StreamController<McpEvent> _eventController = StreamController<McpEvent>.broadcast();

  // Public getters
  McpConnectionState _connectionState = McpConnectionState.disconnected;
  McpConnectionState get connectionState => _connectionState;

  bool get isConnected => _connectionState == McpConnectionState.connected;

  String? get sessionId => _sessionId;

  /// Stream of MCP events for UI updates.
  Stream<McpEvent> get events => _eventController.stream;

  /// The current list of available tools (cached after listing).
  List<Tool> _tools = [];
  List<Tool> get tools => List.unmodifiable(_tools);

  /// Creates a new MCP service instance.
  McpService();

  /// Connects to an MCP server at the given URL.
  ///
  /// Returns `true` if connection was successful, `false` otherwise.
  Future<bool> connect(String serverUrl) async {
    if (_connectionState == McpConnectionState.connected) {
      _emitLog(McpLogLevel.warning, 'Already connected. Disconnect first.');
      return false;
    }

    _setConnectionState(
      McpConnectionState.connecting,
      'Connecting to $serverUrl',
    );

    try {
      // Create the MCP client with elicitation and sampling capabilities
      _client = McpClient(
        const Implementation(name: 'jaspr-mcp-client', version: '1.0.0'),
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

      // Set up error handler
      _client!.onerror = (error) {
        _emitLog(McpLogLevel.error, 'Client error: $error');
      };

      // Set up elicitation handler
      _client!.onElicitRequest = _handleElicitation;

      // Set up sampling handler
      _client!.onSamplingRequest = _handleSampling;

      // Set up task status notification handler
      _client!.onTaskStatus = (params) {
        _emitLog(
          McpLogLevel.info,
          'Task ${params.taskId}: ${params.status.name}'
          '${params.statusMessage != null ? " - ${params.statusMessage}" : ""}',
        );
      };

      // Set up logging notification handler
      _client!.setNotificationHandler<JsonRpcLoggingMessageNotification>(
        Method.notificationsMessage,
        (notification) async {
          final params = notification.logParams;
          final level = switch (params.level) {
            LoggingLevel.debug => McpLogLevel.debug,
            LoggingLevel.info => McpLogLevel.info,
            LoggingLevel.notice => McpLogLevel.info,
            LoggingLevel.warning => McpLogLevel.warning,
            LoggingLevel.error => McpLogLevel.error,
            LoggingLevel.critical => McpLogLevel.error,
            LoggingLevel.alert => McpLogLevel.error,
            LoggingLevel.emergency => McpLogLevel.error,
          };
          _emitLog(level, params.data.toString());
        },
        (params, meta) => JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotification.fromJson(params ?? {}),
          meta: meta,
        ),
      );

      // Create the transport
      _transport = StreamableHttpClientTransport(
        Uri.parse(serverUrl),
        opts: StreamableHttpClientTransportOptions(sessionId: _sessionId),
      );

      _transport!.onerror = (error) {
        _emitLog(McpLogLevel.error, 'Transport error: $error');
      };

      // Connect
      await _client!.connect(_transport!);
      _sessionId = _transport!.sessionId;
      _taskClient = TaskClient(_client!);

      _setConnectionState(
        McpConnectionState.connected,
        'Connected with session: $_sessionId',
      );

      return true;
    } catch (error) {
      _setConnectionState(
        McpConnectionState.error,
        'Connection failed: $error',
      );
      _cleanup();
      return false;
    }
  }

  /// Disconnects from the MCP server.
  Future<void> disconnect() async {
    if (_connectionState != McpConnectionState.connected) {
      _emitLog(McpLogLevel.warning, 'Not connected.');
      return;
    }

    try {
      // Try to politely terminate the session first
      try {
        await _transport?.terminateSession().timeout(const Duration(seconds: 1));
      } catch (_) {
        // Ignore termination errors (e.g. timeout or already closed)
      }
      await _transport?.close();
      _emitLog(McpLogLevel.info, 'Disconnected from server');
    } catch (error) {
      _emitLog(McpLogLevel.error, 'Error during disconnect: $error');
    } finally {
      _sessionId = null;
      _cleanup();
      _setConnectionState(McpConnectionState.disconnected, 'Disconnected');
    }
  }

  /// Lists available tools from the server.
  Future<List<Tool>> listTools() async {
    _ensureConnected();

    final capabilities = _client!.getServerCapabilities();
    if (capabilities?.tools == null) {
      _emitLog(McpLogLevel.debug, 'Server does not support tools.');
      _tools = [];
      _eventController.add(ToolsListedEvent(_tools));
      return _tools;
    }

    try {
      final result = await _client!.listTools();
      _tools = result.tools;
      _eventController.add(ToolsListedEvent(_tools));
      _emitLog(
        McpLogLevel.info,
        'Listed ${_tools.length} tools: ${_tools.map((t) => t.name).join(", ")}',
      );
      return _tools;
    } catch (error) {
      _emitLog(McpLogLevel.error, 'Failed to list tools: $error');
      rethrow;
    }
  }

  /// Lists available resources from the server.
  Future<void> listResources() async {
    _ensureConnected();

    final capabilities = _client!.getServerCapabilities();
    if (capabilities?.resources == null) {
      _emitLog(McpLogLevel.debug, 'Server does not support resources.');
      _eventController.add(const ResourcesListedEvent([]));
      return;
    }

    try {
      final result = await _client!.listResources();
      _eventController.add(ResourcesListedEvent(result.resources));
      _emitLog(McpLogLevel.info, 'Listed ${result.resources.length} resources');
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to list resources: $e');
      rethrow;
    }
  }

  /// Lists available resource templates from the server.
  Future<void> listResourceTemplates() async {
    _ensureConnected();

    final capabilities = _client!.getServerCapabilities();
    if (capabilities?.resources == null) {
      _emitLog(McpLogLevel.debug, 'Server does not support resource templates.');
      _eventController.add(const ResourceTemplatesListedEvent([]));
      return;
    }

    try {
      final result = await _client!.listResourceTemplates();
      _eventController.add(
        ResourceTemplatesListedEvent(result.resourceTemplates),
      );
      _emitLog(
        McpLogLevel.info,
        'Listed ${result.resourceTemplates.length} resource templates',
      );
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to list resource templates: $e');
      rethrow;
    }
  }

  /// Reads a specific resource by URI.
  Future<void> readResource(String uri) async {
    _ensureConnected();
    try {
      final result = await _client!.readResource(ReadResourceRequest(uri: uri));
      _eventController.add(ResourceReadEvent(result));
      _emitLog(McpLogLevel.info, 'Read resource: $uri');
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to read resource: $e');
      rethrow;
    }
  }

  /// Lists available prompts from the server.
  Future<void> listPrompts() async {
    _ensureConnected();

    final capabilities = _client!.getServerCapabilities();
    if (capabilities?.prompts == null) {
      _emitLog(McpLogLevel.debug, 'Server does not support prompts.');
      _eventController.add(const PromptsListedEvent([]));
      return;
    }

    try {
      final result = await _client!.listPrompts();
      _eventController.add(PromptsListedEvent(result.prompts));
      _emitLog(McpLogLevel.info, 'Listed ${result.prompts.length} prompts');
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to list prompts: $e');
      rethrow;
    }
  }

  /// Gets a prompt by name with optional arguments.
  Future<void> getPrompt(
    String name, [
    Map<String, String>? arguments,
  ]) async {
    _ensureConnected();
    try {
      final result = await _client!.getPrompt(
        GetPromptRequest(name: name, arguments: arguments),
      );
      _eventController.add(PromptGetEvent(result));
      _emitLog(McpLogLevel.info, 'Got prompt: $name');
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to get prompt: $e');
      rethrow;
    }
  }

  /// Lists available tasks from the server.
  Future<void> listTasks() async {
    _ensureConnected();

    final capabilities = _client!.getServerCapabilities();
    if (capabilities?.tasks == null) {
      _emitLog(McpLogLevel.debug, 'Server does not support tasks.');
      _eventController.add(const TasksListedEvent([]));
      return;
    }

    try {
      final tasks = await _taskClient!.listTasks();
      _eventController.add(TasksListedEvent(tasks));
      _emitLog(McpLogLevel.info, 'Listed ${tasks.length} tasks');
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to list tasks: $e');
      rethrow;
    }
  }

  /// Cancels a task by ID.
  Future<void> cancelTask(String taskId) async {
    _ensureConnected();
    try {
      await _taskClient!.cancelTask(taskId);
      _emitLog(McpLogLevel.info, 'Cancelled task: $taskId');
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Failed to cancel task: $e');
      rethrow;
    }
  }

  /// Pings the server and returns latency in milliseconds.
  Future<double> ping() async {
    _ensureConnected();
    try {
      final start = DateTime.now();
      await _client!.ping();
      final end = DateTime.now();
      final latency = end.difference(start).inMilliseconds.toDouble();
      _emitLog(McpLogLevel.debug, 'Ping: ${latency}ms');
      return latency;
    } catch (e) {
      _emitLog(McpLogLevel.error, 'Ping failed: $e');
      rethrow;
    }
  }

  /// Calls a tool and returns a stream of task messages.
  ///
  /// This method uses the TaskClient to call tools that may involve
  /// long-running operations, elicitation, or sampling.
  ///
  /// If [onProgress] is provided, it attempts to use a standard tool call
  /// with progress monitoring. If the tool requires task-based execution,
  /// it falls back to the TaskClient (and progress updates may be lost).
  Stream<TaskStreamMessage> callTool(
    String name,
    Map<String, dynamic> arguments, {
    int ttlMs = 60000,
    int pollIntervalMs = 500,
    void Function(double progress, double total)? onProgress,
  }) async* {
    _ensureConnected();

    _emitLog(McpLogLevel.info, 'Calling tool: $name with args: $arguments');

    // Check if server supports tasks
    final serverCaps = _client?.getServerCapabilities();
    final supportsTasks = serverCaps?.tasks != null;

    if (!supportsTasks) {
      _emitLog(McpLogLevel.debug, 'Server does not support tasks. Using standard tool call.');
      try {
        final result = await _client!.callTool(
          CallToolRequest(name: name, arguments: arguments),
        );

        // Emit events
        _eventController.add(TaskResultEvent('', result));

        final textContent = result.content.whereType<TextContent>().firstOrNull;
        _emitLog(
          McpLogLevel.info,
          'Tool result: ${textContent?.text ?? "(no text)"}',
        );

        yield TaskResultMessage(result);
        return;
      } catch (error) {
        _emitLog(McpLogLevel.error, 'Tool call failed: $error');
        yield TaskErrorMessage(error);
        rethrow;
      }
    }

    // Attempt standard call if progress callback is requested
    if (onProgress != null) {
      try {
        final result = await _client!.callTool(
          CallToolRequest(name: name, arguments: arguments),
          options: RequestOptions(
            onprogress: (progress) {
              final p = progress.progress.toDouble();
              final t = progress.total?.toDouble() ?? 0.0;
              onProgress(p, t);
              _eventController.add(ToolProgressEvent(name, p, t));
            },
          ),
        );

        final textContent = result.content.whereType<TextContent>().firstOrNull;
        _emitLog(
          McpLogLevel.info,
          'Tool result: ${textContent?.text ?? "(no text)"}',
        );
        _eventController.add(TaskResultEvent('', result));
        yield TaskResultMessage(result);
        return;
      } catch (error) {
        if (error is McpError && error.message.contains('requires task-based execution')) {
          _emitLog(
            McpLogLevel.warning,
            'Tool "$name" requires task execution. Progress callbacks will be ignored.',
          );
          // Fallback to TaskClient below
        } else {
          _emitLog(McpLogLevel.error, 'Tool call failed: $error');
          yield TaskErrorMessage(error);
          rethrow;
        }
      }
    }

    try {
      await for (final message in _taskClient!.callToolStream(
        name,
        arguments,
        task: {'ttl': ttlMs, 'pollInterval': pollIntervalMs},
      )) {
        // Emit events for UI to consume
        switch (message) {
          case TaskCreatedMessage(:final task):
            _eventController.add(TaskCreatedEvent(task));
            _emitLog(McpLogLevel.info, 'Task created: ${task.taskId}');
          case TaskStatusMessage(:final task):
            _eventController.add(TaskStatusEvent(task));
          case TaskResultMessage(:final result):
            if (result is CallToolResult) {
              _eventController.add(TaskResultEvent('', result));
              final textContent = result.content.whereType<TextContent>().firstOrNull;
              _emitLog(
                McpLogLevel.info,
                'Task result: ${textContent?.text ?? "(no text)"}',
              );
            }
          case TaskErrorMessage(:final error):
            _eventController.add(TaskErrorEvent('', error));
            _emitLog(McpLogLevel.error, 'Task error: $error');
        }
        yield message;
      }
    } catch (error) {
      _emitLog(McpLogLevel.error, 'Tool call failed: $error');
      rethrow;
    }
  }

  /// Responds to an elicitation request.
  void respondToElicitation(String requestId, ElicitResult result) {
    // This is handled internally by the completer mechanism
    _emitLog(McpLogLevel.debug, 'Elicitation response: ${result.action}');
  }

  /// Responds to a sampling request.
  void respondToSampling(String requestId, CreateMessageResult result) {
    // This is handled internally by the completer mechanism
    _emitLog(McpLogLevel.debug, 'Sampling response: ${result.model}');
  }

  /// Disposes of the service and releases resources.
  void dispose() {
    disconnect();
    _eventController.close();
  }

  // ============================================================================
  // Private methods
  // ============================================================================

  void _setConnectionState(McpConnectionState state, String? message) {
    _connectionState = state;
    _eventController.add(ConnectionStateEvent(state, message));
  }

  void _emitLog(McpLogLevel level, String message) {
    _eventController.add(LogEvent(level, message));
  }

  void _ensureConnected() {
    if (_client == null || _connectionState != McpConnectionState.connected) {
      throw StateError('Not connected to server');
    }
  }

  void _cleanup() {
    _client = null;
    _transport = null;
    _taskClient = null;
    _tools = [];
  }

  Future<ElicitResult> _handleElicitation(ElicitRequest params) async {
    final requestId = generateUUID();
    final completer = Completer<ElicitResult>();

    _emitLog(McpLogLevel.info, 'Elicitation request: ${params.message}');
    _eventController.add(ElicitationRequestEvent(requestId, params, completer));

    // Wait for the UI to respond via the completer
    return completer.future;
  }

  Future<CreateMessageResult> _handleSampling(
    CreateMessageRequest params,
  ) async {
    final requestId = generateUUID();
    final completer = Completer<CreateMessageResult>();

    // Extract prompt from first message
    String prompt = 'unknown';
    if (params.messages.isNotEmpty) {
      final content = params.messages.first.content;
      if (content is SamplingTextContent) {
        prompt = content.text;
      }
    }

    _emitLog(McpLogLevel.info, 'Sampling request: $prompt');
    _eventController.add(SamplingRequestEvent(requestId, params, completer));

    // Wait for the UI to respond via the completer
    return completer.future;
  }
}
