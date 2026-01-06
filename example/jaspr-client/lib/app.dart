/// Main App component for the Jaspr MCP Client.
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:mcp_dart/mcp_dart.dart' hide LogLevel;

import 'components/connection_panel.dart';
import 'components/elicitation_dialog.dart';
import 'components/prompts_panel.dart';
import 'components/resources_panel.dart';
import 'components/sampling_dialog.dart';
import 'components/tasks_panel.dart';
import 'components/tools_panel.dart';
import 'services/mcp_service.dart';

enum AppTab { tools, resources, prompts, tasks }

/// The main App component that orchestrates the MCP client UI.
class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // Services
  final McpService _mcpService = McpService();

  // State
  McpConnectionState _connectionState = McpConnectionState.disconnected;
  AppTab _activeTab = AppTab.tools;
  final Map<String, double> _toolProgress = {};

  // Data State
  List<Tool> _tools = [];
  List<Resource> _resources = [];
  List<Prompt> _prompts = [];
  List<Task> _tasks = [];
  final List<LogEntry> _logs = [];

  // Operation State
  Uri? _readingResourceUri;
  String? _resourceContent;
  GetPromptResult? _promptResult;

  // Dialog state
  ElicitationRequestEvent? _pendingElicitation;
  SamplingRequestEvent? _pendingSampling;

  // Subscriptions
  StreamSubscription<McpEvent>? _eventSubscription;
  web.MutationObserver? _scrollObserver;

  @override
  void initState() {
    super.initState();
    _setupEventListener();
    // Initialize observer after initial render
    Timer(const Duration(milliseconds: 100), _setupScrollObserver);
  }

  void _setupScrollObserver() {
    if (_scrollObserver != null) return;

    final console = web.document.querySelector('#output-console');
    if (console == null) {
      // Retry if not found yet (e.g. if logs were empty and then added)
      // Actually console is always present in current build method unless removed.
      return;
    }

    _scrollObserver = web.MutationObserver(
      (JSArray mutations, web.MutationObserver observer) {
        console.scrollTop = console.scrollHeight.toDouble();
      }.toJS,
    );

    _scrollObserver!.observe(
      console,
      web.MutationObserverInit(childList: true, subtree: true),
    );
  }

  void _setupEventListener() {
    _eventSubscription = _mcpService.events.listen(_handleEvent);
  }

  void _handleEvent(McpEvent event) {
    setState(() {
      switch (event) {
        case ConnectionStateEvent(:final state, :final message):
          _connectionState = state;
          if (message != null) {
            _addLog(McpLogLevel.info, message);
          }
        case ToolsListedEvent(:final tools):
          _tools = tools;
        case ResourcesListedEvent(:final resources):
          _resources = resources;
        case PromptsListedEvent(:final prompts):
          _prompts = prompts;
        case TasksListedEvent(:final tasks):
          _tasks = tasks;
        case ResourceReadEvent(:final result):
          _readingResourceUri = null;
          final text = result.contents.whereType<TextResourceContents>().firstOrNull?.text;
          final blob = result.contents.whereType<BlobResourceContents>().firstOrNull?.blob;
          _resourceContent = text ?? (blob != null ? '[Blob data]' : '[No content]');
        case PromptGetEvent(:final result):
          _promptResult = result;
        case LogEvent(:final level, :final message, :final timestamp):
          _logs.add(
            LogEntry(level: level, message: message, timestamp: timestamp),
          );
        case TaskCreatedEvent(:final task):
          _addLog(McpLogLevel.info, 'Task created: ${task.taskId}');
          _listTasks(); // Refresh tasks
        case TaskStatusEvent(:final task):
          _addLog(McpLogLevel.debug, 'Task ${task.taskId}: ${task.status.name}');
          _listTasks(); // Refresh tasks
        case TaskResultEvent(:final result):
          final text = result.content.whereType<TextContent>().firstOrNull?.text;
          _addLog(McpLogLevel.info, 'Result: ${text ?? "(no text)"}');
        case TaskErrorEvent(:final error):
          _addLog(McpLogLevel.error, 'Error: $error');
        case ElicitationRequestEvent():
          _pendingElicitation = event;
        case SamplingRequestEvent():
          _pendingSampling = event;
        case ResourceTemplatesListedEvent():
          break;
        case ToolProgressEvent(:final toolName, :final progress, :final total):
          if (total > 0) {
            _toolProgress[toolName] = progress / total;
          }
          break;
      }
    });
  }

  void _addLog(McpLogLevel level, String message) {
    _logs.add(
      LogEntry(level: level, message: message, timestamp: DateTime.now()),
    );
    // Keep only last 100 logs
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }

    // Ensure observer is set up if it wasn't (e.g. first log)
    if (_scrollObserver == null) {
      _setupScrollObserver();
    }
  }

  // Service Calls
  Future<void> _handleConnect(String serverUrl) async {
    final success = await _mcpService.connect(serverUrl);
    if (success) {
      // Run sequentially to avoid hitting browser connection limits (max 6 per host)
      // 1. Tools
      try {
        await _mcpService.listTools();
      } catch (_) {}

      // 2. Resources
      try {
        await _mcpService.listResources();
      } catch (_) {}

      // 3. Prompts
      try {
        await _mcpService.listPrompts();
      } catch (_) {}

      // 4. Tasks
      try {
        await _mcpService.listTasks();
      } catch (_) {}
    }
  }

  Future<void> _handleDisconnect() async {
    try {
      await _mcpService.disconnect().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Ignore timeout or errors during disconnect
    }
    setState(() {
      _tools = [];
      _resources = [];
      _prompts = [];
      _tasks = [];
    });
  }

  Future<void> _ping() async {
    try {
      await _mcpService.ping();
    } catch (e) {
      // Logged by service
    }
  }

  Future<void> _handleCallTool(String name, Map<String, dynamic> args) async {
    try {
      await for (final _ in _mcpService.callTool(name, args)) {
        // Events are handled by the event listener
      }
    } catch (error) {
      _addLog(McpLogLevel.error, 'Tool call failed: $error');
    } finally {
      if (_toolProgress.containsKey(name)) {
        setState(() {
          _toolProgress.remove(name);
        });
      }
    }
  }

  Future<void> _readResource(String uri) async {
    setState(() {
      _readingResourceUri = Uri.parse(uri);
      _resourceContent = null;
    });
    try {
      await _mcpService.readResource(uri);
    } catch (e) {
      setState(() => _readingResourceUri = null);
    }
  }

  Future<void> _getPrompt(String name, Map<String, String> args) async {
    try {
      await _mcpService.getPrompt(name, args);
    } catch (e) {
      // Logged by service
    }
  }

  Future<void> _listTasks() async {
    try {
      await _mcpService.listTasks();
    } catch (e) {
      // Logged by service
    }
  }

  Future<void> _cancelTask(String taskId) async {
    try {
      await _mcpService.cancelTask(taskId);
      await _listTasks();
    } catch (e) {
      // Logged by service
    }
  }

  void _handleElicitationResponse(bool confirmed) {
    final pending = _pendingElicitation;
    if (pending == null) return;

    pending.completer.complete(
      ElicitResult(action: 'accept', content: {'confirm': confirmed}),
    );

    setState(() {
      _pendingElicitation = null;
    });
  }

  void _handleElicitationCancel() {
    final pending = _pendingElicitation;
    if (pending == null) return;

    pending.completer.complete(const ElicitResult(action: 'decline'));

    setState(() {
      _pendingElicitation = null;
    });
  }

  void _handleSamplingResponse(String text) {
    final pending = _pendingSampling;
    if (pending == null) return;

    pending.completer.complete(
      CreateMessageResult(
        model: 'user-input',
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: text),
      ),
    );

    setState(() {
      _pendingSampling = null;
    });
  }

  void _handleSamplingCancel() {
    final pending = _pendingSampling;
    if (pending == null) return;

    // For sampling, we still need to provide a response
    pending.completer.complete(
      const CreateMessageResult(
        model: 'cancelled',
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: '(cancelled)'),
      ),
    );

    setState(() {
      _pendingSampling = null;
    });
  }

  @override
  void dispose() {
    _scrollObserver?.disconnect();
    _eventSubscription?.cancel();
    _mcpService.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'app', [
      // Header
      header([
        div(classes: 'header-content', [
          h1([Component.text('MCP Jaspr Client')]),
          div(classes: 'header-actions', [
            if (_connectionState == McpConnectionState.connected)
              button(
                classes: 'btn btn-small btn-secondary',
                onClick: _ping,
                [Component.text('Ping')],
              ),
            _buildConnectionStatus(),
          ]),
        ]),
      ]),

      // Content Wrapper (Sidebar + Main)
      div(classes: 'content-wrapper', [
        // Sidebar
        aside(classes: 'sidebar', [
          // Connection
          div(classes: 'sidebar-section', [
            ConnectionPanel(
              connectionState: _connectionState,
              onConnect: _handleConnect,
              onDisconnect: _handleDisconnect,
            ),
          ]),

          // Navigation
          nav(classes: 'nav-menu', [
            _buildNavItem('Tools', AppTab.tools, '🔧'),
            _buildNavItem('Resources', AppTab.resources, '📦'),
            _buildNavItem('Prompts', AppTab.prompts, '💬'),
            _buildNavItem('Tasks', AppTab.tasks, '✓'),
          ]),
        ]),

        // Main View
        main_(classes: 'main-view', [
          switch (_activeTab) {
            AppTab.tools => ToolsPanel(
              tools: _tools,
              isConnected: _connectionState == McpConnectionState.connected,
              toolProgress: _toolProgress,
              onCallTool: _handleCallTool,
            ),
            AppTab.resources => ResourcesPanel(
              resources: _resources,
              onReadResource: _readResource,
              readingResourceUri: _readingResourceUri?.toString(),
              resourceContent: _resourceContent,
            ),
            AppTab.prompts => PromptsPanel(
              prompts: _prompts,
              onGetPrompt: _getPrompt,
              promptResult: _promptResult,
            ),
            AppTab.tasks => TasksPanel(
              tasks: _tasks,
              onCancelTask: _cancelTask,
              onRefresh: _listTasks,
            ),
          },
        ]),
      ]),

      // Bottom Panel (Logs)
      div(classes: 'bottom-panel', [
        div(classes: 'bottom-panel-header', [
          h3([Component.text('Output Log')]),
          span(classes: 'log-count', [Component.text('${_logs.length} entries')]),
        ]),
        div(classes: 'log-container', id: 'output-console', [
          if (_logs.isEmpty)
            div(classes: 'empty-state', [
              p([Component.text('Logs will appear here...')]),
            ])
          else
            for (final log in _logs) _buildLogEntry(log),
        ]),
      ]),

      // Dialogs
      if (_pendingElicitation != null)
        ElicitationDialog(
          message: _pendingElicitation!.request.message,
          onConfirm: () => _handleElicitationResponse(true),
          onCancel: _handleElicitationCancel,
          onDecline: () => _handleElicitationResponse(false),
        ),

      if (_pendingSampling != null)
        SamplingDialog(
          prompt: _getSamplingPrompt(_pendingSampling!.request),
          onSubmit: _handleSamplingResponse,
          onCancel: _handleSamplingCancel,
        ),
    ]);
  }

  Component _buildNavItem(String label, AppTab tab, String icon) {
    final isActive = _activeTab == tab;
    return div(
      classes: 'nav-item ${isActive ? 'active' : ''}',
      events: {'click': (_) => setState(() => _activeTab = tab)},
      [
        span([Component.text(icon)]),
        span([Component.text(label)]),
      ],
    );
  }

  Component _buildLogEntry(LogEntry log) {
    final levelClass = switch (log.level) {
      McpLogLevel.info => 'log-info',
      McpLogLevel.warning => 'log-warning',
      McpLogLevel.error => 'log-error',
      McpLogLevel.debug => 'log-debug',
    };

    final levelIcon = switch (log.level) {
      McpLogLevel.info => 'ℹ',
      McpLogLevel.warning => '⚠',
      McpLogLevel.error => '✗',
      McpLogLevel.debug => '⚙',
    };

    return div(classes: 'log-entry $levelClass', [
      span(classes: 'log-time', [Component.text(log.formattedTime)]),
      span(classes: 'log-level', [Component.text(levelIcon)]),
      span(classes: 'log-message', [Component.text(log.message)]),
    ]);
  }

  Component _buildConnectionStatus() {
    final (statusClass, statusText) = switch (_connectionState) {
      McpConnectionState.disconnected => ('status-disconnected', 'Disconnected'),
      McpConnectionState.connecting => ('status-connecting', 'Connecting...'),
      McpConnectionState.connected => ('status-connected', 'Connected'),
      McpConnectionState.error => ('status-error', 'Error'),
    };

    return div(classes: 'connection-status $statusClass', [
      span(classes: 'status-indicator', []),
      span([Component.text(statusText)]),
    ]);
  }

  String _getSamplingPrompt(CreateMessageRequest request) {
    if (request.messages.isEmpty) return 'Unknown prompt';
    final content = request.messages.first.content;
    if (content is SamplingTextContent) {
      return content.text;
    }
    return 'Unknown prompt';
  }
}

/// A log entry for display in the output panel.
class LogEntry {
  final McpLogLevel level;
  final String message;
  final DateTime timestamp;

  const LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}
