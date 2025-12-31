import 'dart:async';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/tool_name_validation.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:mcp_dart/src/types.dart';

import 'server.dart';
import 'tasks.dart';

final _logger = Logger("mcp_dart.server.mcp");

/// Callback capable of providing completions for a partial value.
typedef CompleteCallback = FutureOr<List<String>> Function(String value);

/// Definition for a completable argument.
class CompletableDef {
  /// The callback to invoke to get completion suggestions.
  final CompleteCallback complete;

  const CompletableDef({required this.complete});
}

/// A field that supports auto-completion.
class CompletableField {
  /// The completion definition.
  final CompletableDef def;

  /// The underlying type of the field (defaults to String).
  final Type underlyingType;

  const CompletableField({required this.def, this.underlyingType = String});
}

/// Function signature for a tool implementation.
typedef ToolFunction = FutureOr<CallToolResult> Function(
  Map<String, dynamic> args,
  RequestHandlerExtra extra,
);

/// Legacy callback signature for tools (deprecated style).
typedef LegacyToolCallback = FutureOr<CallToolResult> Function({
  Map<String, dynamic>? args,
  RequestHandlerExtra? extra,
});

/// Base class for tool callbacks.
sealed class ToolCallback {}

/// A tool callback implemented as a simple function.
final class FunctionToolCallback extends ToolCallback {
  final ToolFunction function;
  FunctionToolCallback(this.function);
}

/// A tool callback implemented via a [ToolTaskHandler] interface.
final class InterfaceToolCallback extends ToolCallback {
  final ToolTaskHandler handler;
  InterfaceToolCallback(this.handler);
}

/// Callback signature for prompts.
typedef PromptCallback = FutureOr<GetPromptResult> Function(
  Map<String, dynamic>? args,
  RequestHandlerExtra? extra,
);

/// Definition of an argument for a prompt.
class PromptArgumentDefinition {
  /// Description of what the argument is for.
  final String? description;

  /// Whether the argument is required.
  final bool required;

  /// The expected type of the argument.
  final Type type;

  /// Configuration for auto-completion on this argument.
  final CompletableField? completable;

  const PromptArgumentDefinition({
    this.description,
    this.required = false,
    this.type = String,
    this.completable,
  });
}

/// Metadata for a resource.
typedef ResourceMetadata = ({
  String? description,
  String? mimeType,
});

/// Callback to list available resources.
typedef ListResourcesCallback = FutureOr<ListResourcesResult> Function(
  RequestHandlerExtra extra,
);

/// Callback to read a specific resource.
typedef ReadResourceCallback = FutureOr<ReadResourceResult> Function(
  Uri uri,
  RequestHandlerExtra extra,
);

/// Callback to read a resource template.
typedef ReadResourceTemplateCallback = FutureOr<ReadResourceResult> Function(
  Uri uri,
  TemplateVariables variables,
  RequestHandlerExtra extra,
);

/// Callback to complete a value within a resource template.
typedef CompleteResourceTemplateCallback = FutureOr<List<String>> Function(
  String currentValue,
);

/// Callback to list available tasks.
typedef ListTasksCallback = FutureOr<ListTasksResult> Function(
  RequestHandlerExtra extra,
);

/// Callback to cancel a running task.
typedef CancelTaskCallback = FutureOr<void> Function(
  String taskId,
  RequestHandlerExtra extra,
);

/// Callback to get the status of a task.
typedef GetTaskCallback = FutureOr<Task> Function(
  String taskId,
  RequestHandlerExtra extra,
);

/// Callback to get the result of a completed task.
typedef TaskResultCallback = FutureOr<CallToolResult> Function(
  String taskId,
  RequestHandlerExtra extra,
);

/// Registration details for a resource template.
class ResourceTemplateRegistration {
  /// The URI template expander.
  final UriTemplateExpander uriTemplate;

  /// The callback to list resources matching this template.
  final ListResourcesCallback? listCallback;

  /// Callbacks to complete variables within the template.
  final Map<String, CompleteResourceTemplateCallback>? completeCallbacks;

  ResourceTemplateRegistration(
    String templateString, {
    required this.listCallback,
    this.completeCallbacks,
  }) : uriTemplate = UriTemplateExpander(templateString);

  /// Gets the completion callback for a specific variable.
  CompleteResourceTemplateCallback? getCompletionCallback(String variableName) {
    return completeCallbacks?[variableName];
  }
}

/// Abstract interface for a registered resource.
/// Abstract interface for a registered resource.
abstract class RegisteredResource {
  /// The name of the resource.
  String get name;

  /// The title of the resource.
  String? get title;

  /// Metadata associated with the resource.
  ResourceMetadata? get metadata;

  /// The callback used to read the resource content.
  ReadResourceCallback get readCallback;

  /// Whether the resource is currently enabled.
  bool get enabled;

  /// Enables the resource.
  void enable();

  /// Disables the resource.
  void disable();

  /// Removes the resource from the server.
  void remove();

  /// Updates the resource configuration.
  void update({
    String? name,
    String? title,
    String? uri,
    ResourceMetadata? metadata,
    ReadResourceCallback? callback,
    bool? enabled,
  });
}

class _RegisteredResourceImpl implements RegisteredResource {
  @override
  String name;
  @override
  String? title;
  final String uri;
  @override
  ResourceMetadata? metadata;
  final ImageContent? icon; // Kept for legacy compatibility
  @override
  ReadResourceCallback readCallback;
  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredResourceImpl(
    this._server, {
    required this.name,
    required this.uri,
    this.metadata,
    this.icon,
    required this.readCallback,
  });

  Resource toResource() {
    return Resource(
      uri: uri,
      name: name,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
      icon: icon,
      annotations: title != null ? ResourceAnnotations(title: title) : null,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() => update(uri: null);

  @override
  void update({
    String? name,
    String? title,
    String? uri,
    ResourceMetadata? metadata,
    ReadResourceCallback? callback,
    bool? enabled,
  }) {
    if (uri != null && uri != this.uri) {
      _server._registeredResources.remove(this.uri);
    }

    if (name != null) this.name = name;
    if (title != null) this.title = title;
    if (metadata != null) this.metadata = metadata;
    if (callback != null) readCallback = callback;
    if (enabled != null) this.enabled = enabled;

    if (uri != null && uri != this.uri) {
      _server._updateResourceUri(this.uri, uri, this);
    }
    _server.sendResourceListChanged();
  }
}

/// Abstract interface for a registered resource template.
abstract class RegisteredResourceTemplate {
  /// The template registration details.
  ResourceTemplateRegistration get resourceTemplate;

  /// The title of the template.
  String? get title;

  /// Metadata associated with the template.
  ResourceMetadata? get metadata;

  /// The callback to read resources matching this template.
  ReadResourceTemplateCallback get readCallback;

  /// Whether the template is currently enabled.
  bool get enabled;

  /// Enables the template.
  void enable();

  /// Disables the template.
  void disable();

  /// Removes the template from the server.
  void remove();

  /// Updates the template configuration.
  void update({
    String? name,
    String? title,
    ResourceTemplateRegistration? template,
    ResourceMetadata? metadata,
    ReadResourceTemplateCallback? callback,
    bool? enabled,
  });
}

class _RegisteredResourceTemplateImpl implements RegisteredResourceTemplate {
  final String name;
  @override
  ResourceTemplateRegistration resourceTemplate;
  @override
  String? title;
  @override
  ResourceMetadata? metadata;
  @override
  ReadResourceTemplateCallback readCallback;
  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredResourceTemplateImpl(
    this._server, {
    required this.name,
    required this.resourceTemplate,
    this.metadata,
    required this.readCallback,
  });

  ResourceTemplate toResourceTemplate() {
    return ResourceTemplate(
      uriTemplate: resourceTemplate.uriTemplate.toString(),
      name: name,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
      annotations: title != null ? ResourceAnnotations(title: title) : null,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() => update(name: null);

  @override
  void update({
    String? name,
    String? title,
    ResourceTemplateRegistration? template,
    ResourceMetadata? metadata,
    ReadResourceTemplateCallback? callback,
    bool? enabled,
  }) {
    if (name != null && name != this.name) {
      _server._registeredResourceTemplates.remove(this.name);
    }
    if (title != null) this.title = title;
    if (template != null) resourceTemplate = template;
    if (metadata != null) this.metadata = metadata;
    if (callback != null) readCallback = callback;
    if (enabled != null) this.enabled = enabled;

    if (name != null && name != this.name) {
      _server._updateResourceTemplateName(this.name, name, this);
    }
    _server.sendResourceListChanged();
  }
}

/// Abstract interface for a registered tool.
abstract class RegisteredTool {
  /// The name of the tool.
  String get name;

  /// The title of the tool.
  String? get title;

  /// The description of the tool.
  String? get description;

  /// The input schema for the tool.
  ToolInputSchema? get inputSchema;

  /// The output schema for the tool.
  ToolOutputSchema? get outputSchema;

  /// Annotations for the tool.
  ToolAnnotations? get annotations;

  /// Execution configuration for the tool.
  ToolExecution? get execution;

  /// The processing callback for the tool.
  ToolCallback? get callback;

  /// Whether the tool is currently enabled.
  bool get enabled;

  /// Enables the tool.
  void enable();

  /// Disables the tool.
  void disable();

  /// Removes the tool from the server.
  void remove();

  /// Updates the tool configuration.
  void update({
    String? name,
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    ToolExecution? execution,
    ToolCallback? callback,
    bool? enabled,
  });
}

class _RegisteredToolImpl implements RegisteredTool {
  @override
  String name;
  @override
  String? title;
  @override
  String? description;
  @override
  ToolInputSchema? inputSchema;
  @override
  ToolOutputSchema? outputSchema;
  @override
  ToolAnnotations? annotations;
  final ImageContent? icon;
  final Map<String, dynamic>? meta;
  @override
  ToolExecution? execution;
  @override
  ToolCallback? callback;
  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredToolImpl(
    this._server, {
    required this.name,
    this.title,
    this.description,
    this.inputSchema,
    this.outputSchema,
    this.annotations,
    this.icon,
    this.meta,
    this.execution,
    required this.callback,
  }) {
    _server._registeredTools[name] = this;
  }

  Tool toTool() {
    return Tool(
      name: name,
      description: description,
      inputSchema: inputSchema ?? const ToolInputSchema(),
      outputSchema: outputSchema,
      annotations: annotations,
      icon: icon,
      execution: execution,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() => update(name: null);

  @override
  void update({
    String? name,
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    ToolExecution? execution,
    ToolCallback? callback,
    bool? enabled,
  }) {
    if (name != null && name != this.name) {
      _server._registeredTools.remove(this.name);
    }

    if (name != null) {
      validateAndWarnToolName(name);
      this.name = name;
    }
    if (title != null) this.title = title;
    if (description != null) this.description = description;
    if (inputSchema != null) this.inputSchema = inputSchema;
    if (outputSchema != null) this.outputSchema = outputSchema;
    if (annotations != null) this.annotations = annotations;
    if (execution != null) this.execution = execution;
    if (callback != null) this.callback = callback;
    if (enabled != null) this.enabled = enabled;

    if (name != null) {
      _server._registeredTools[name] = this;
    }
    _server.sendToolListChanged();
  }
}

/// Abstract interface for a registered prompt.
abstract class RegisteredPrompt {
  /// The name of the prompt.
  String get name;

  /// The title of the prompt.
  String? get title;

  /// The description of the prompt.
  String? get description;

  /// The arguments definition for the prompt.
  Map<String, PromptArgumentDefinition>? get argsSchemaDefinition;

  /// Whether the prompt is currently enabled.
  bool get enabled;

  /// Enables the prompt.
  void enable();

  /// Disables the prompt.
  void disable();

  /// Removes the prompt from the server.
  void remove();

  /// Updates the prompt configuration.
  void update({
    String? name,
    String? title,
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    PromptCallback? callback,
    bool? enabled,
  });
}

class _RegisteredPromptImpl implements RegisteredPrompt {
  @override
  String name;
  @override
  String? title;
  @override
  String? description;
  @override
  Map<String, PromptArgumentDefinition>? argsSchemaDefinition;
  final ImageContent? icon;
  PromptCallback? callback;
  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredPromptImpl(
    this._server, {
    required this.name,
    this.title,
    this.description,
    this.argsSchemaDefinition,
    this.icon,
    this.callback,
  });

  Prompt toPrompt() {
    final promptArgs = argsSchemaDefinition?.entries.map((entry) {
      return PromptArgument(
        name: entry.key,
        description: entry.value.description,
        required: entry.value.required,
      );
    }).toList();
    return Prompt(
      name: name,
      description: description,
      arguments: promptArgs,
      icon: icon,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() => update(name: null);

  @override
  void update({
    String? name,
    String? title,
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    PromptCallback? callback,
    bool? enabled,
  }) {
    if (name != null && name != this.name) {
      _server._registeredPrompts.remove(this.name);
    }
    if (name != null) this.name = name;
    if (title != null) this.title = title;
    if (description != null) this.description = description;
    if (argsSchema != null) argsSchemaDefinition = argsSchema;
    if (callback != null) this.callback = callback;
    if (enabled != null) this.enabled = enabled;

    if (name != null) {
      _server._registeredPrompts[name] = this;
    }
    _server.sendPromptListChanged();
  }
}

/// Experimental task-related functionality for the server.
class ExperimentalMcpServerTasks {
  final McpServer _server;

  ExperimentalMcpServerTasks(this._server);

  /// Registers a task-based tool with a config object and handler.
  RegisteredTool registerToolTask(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    ToolExecution? execution,
    required ToolTaskHandler handler,
  }) {
    // Validate that taskSupport is not 'forbidden' for task-based tools
    final effectiveExecution = ToolExecution(
      taskSupport: execution?.taskSupport ?? 'required',
    );
    if (effectiveExecution.taskSupport == 'forbidden') {
      throw ArgumentError(
        "Cannot register task-based tool '$name' with taskSupport 'forbidden'. Use registerTool() instead.",
      );
    }

    return _server._registerTool(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: annotations,
      meta: meta,
      execution: effectiveExecution,
      callback: InterfaceToolCallback(handler),
    );
  }

  /// Sends an `elicitation/create` request associated with a specific task.
  Future<ElicitResult> elicitForTask(
    String taskId,
    ElicitRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcElicitRequest(
      id: -1,
      elicitParams: params,
      meta: {
        relatedTaskMetaKey: {'taskId': taskId},
      },
    );
    return _server.server.request<ElicitResult>(
      req,
      (json) => ElicitResult.fromJson(json),
      options,
    );
  }

  /// Sends a `sampling/createMessage` request associated with a specific task.
  Future<CreateMessageResult> createMessageForTask(
    String taskId,
    CreateMessageRequest params, [
    RequestOptions? options,
  ]) {
    final req = JsonRpcCreateMessageRequest(
      id: -1,
      createParams: params,
      meta: {
        relatedTaskMetaKey: {'taskId': taskId},
      },
    );
    return _server.server.request<CreateMessageResult>(
      req,
      (json) => CreateMessageResult.fromJson(json),
      options,
    );
  }

  /// Registers a callback for listing tasks.
  void onListTasks(ListTasksCallback callback) {
    _server._listTasksCallback = callback;
    _server._ensureTaskHandlersInitialized();
  }

  /// Registers a callback for cancelling a task.
  void onCancelTask(CancelTaskCallback callback) {
    _server._cancelTaskCallback = callback;
    _server._ensureTaskHandlersInitialized();
  }

  /// Registers a callback for getting task details.
  void onGetTask(GetTaskCallback callback) {
    _server._getTaskCallback = callback;
    _server._ensureTaskHandlersInitialized();
  }

  /// Registers a callback for retrieving task results.
  void onTaskResult(TaskResultCallback callback) {
    _server._taskResultCallback = callback;
    _server._ensureTaskHandlersInitialized();
  }
}

/// High-level Model Context Protocol (MCP) server API.
///
/// This class provides a set of high-level methods to register resources, tools,
/// and prompts, and to handle server lifecycle events.
class McpServer {
  // ignore: deprecated_member_use_from_same_package
  late final Server server;

  final Map<String, _RegisteredResourceImpl> _registeredResources = {};
  final Map<String, _RegisteredResourceTemplateImpl>
      _registeredResourceTemplates = {};
  final Map<String, _RegisteredToolImpl> _registeredTools = {};
  final Map<String, _RegisteredPromptImpl> _registeredPrompts = {};

  bool _resourceHandlersInitialized = false;
  bool _toolHandlersInitialized = false;
  bool _promptHandlersInitialized = false;
  bool _completionHandlerInitialized = false;
  bool _taskHandlersInitialized = false;

  ListTasksCallback? _listTasksCallback;
  CancelTaskCallback? _cancelTaskCallback;
  GetTaskCallback? _getTaskCallback;
  TaskResultCallback? _taskResultCallback;

  ExperimentalMcpServerTasks? _experimental;

  /// Experimental features related to tasks.
  ExperimentalMcpServerTasks get experimental =>
      _experimental ??= ExperimentalMcpServerTasks(this);

  /// Creates an [McpServer] instance.
  McpServer(Implementation serverInfo, {McpServerOptions? options}) {
    // ignore: deprecated_member_use_from_same_package
    server = Server(serverInfo, options: options);
  }

  /// Connects the server to a communication [transport].
  Future<void> connect(Transport transport) async {
    return await server.connect(transport);
  }

  /// Closes the server connection.
  Future<void> close() async {
    await server.close();
  }

  /// Checks if the server is connected to a transport.
  bool get isConnected => server.transport != null;

  /// Sends a logging message to the client, if connected.
  Future<void> sendLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
  }) async {
    return server.sendLoggingMessage(params, sessionId: sessionId);
  }

  /// Sets the error handler for the server.
  set onError(void Function(Error)? handler) {
    server.onerror = handler;
  }

  /// Gets the error handler for the server.
  void Function(Error)? get onError => server.onerror;

  void _updateResourceUri(
    String oldUri,
    String newUri,
    _RegisteredResourceImpl resource,
  ) {
    _registeredResources.remove(oldUri);
    _registeredResources[newUri] = resource;
  }

  void _updateResourceTemplateName(
    String oldName,
    String newName,
    _RegisteredResourceTemplateImpl template,
  ) {
    _registeredResourceTemplates.remove(oldName);
    _registeredResourceTemplates[newName] = template;
  }

  void sendResourceListChanged() {
    if (server.transport != null) {
      server.sendResourceListChanged();
    }
  }

  /// Notifies clients that the list of available tools has changed.
  void sendToolListChanged() {
    if (server.transport != null) {
      server.sendToolListChanged();
    }
  }

  /// Notifies clients that the list of available prompts has changed.
  void sendPromptListChanged() {
    if (server.transport != null) {
      server.sendPromptListChanged();
    }
  }

  // --- Handlers ---

  void _ensureTaskHandlersInitialized() {
    if (!_taskHandlersInitialized) {
      server.assertCanSetRequestHandler(Method.tasksList);
      server.assertCanSetRequestHandler(Method.tasksCancel);
      server.assertCanSetRequestHandler(Method.tasksGet);
      server.assertCanSetRequestHandler(Method.tasksResult);
      server.registerCapabilities(
        const ServerCapabilities(
          tasks: ServerCapabilitiesTasks(listChanged: true),
        ),
      );
      _taskHandlersInitialized = true;
    }

    server.setRequestHandler<JsonRpcListTasksRequest>(
      Method.tasksList,
      (request, extra) async {
        if (_listTasksCallback == null) {
          throw McpError(
            ErrorCode.methodNotFound.value,
            "Task listing not supported",
          );
        }
        return await Future.value(_listTasksCallback!(extra));
      },
      (id, params, meta) => JsonRpcListTasksRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    server.setRequestHandler<JsonRpcCancelTaskRequest>(
      Method.tasksCancel,
      (request, extra) async {
        if (_cancelTaskCallback == null) {
          throw McpError(
            ErrorCode.methodNotFound.value,
            "Task cancellation not supported",
          );
        }
        await Future.value(
          _cancelTaskCallback!(request.cancelParams.taskId, extra),
        );
        return const EmptyResult();
      },
      (id, params, meta) => JsonRpcCancelTaskRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    if (_getTaskCallback != null) {
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async {
          final taskId = request.getParams.taskId;
          return await Future.value(_getTaskCallback!(taskId, extra));
        },
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
    }

    if (_taskResultCallback != null) {
      server.setRequestHandler<JsonRpcTaskResultRequest>(
        Method.tasksResult,
        (request, extra) async {
          final taskId = request.resultParams.taskId;
          return await Future.value(_taskResultCallback!(taskId, extra));
        },
        (id, params, meta) => JsonRpcTaskResultRequest.fromJson({
          'id': id,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );
    }
  }

  void _ensureToolHandlersInitialized() {
    if (_toolHandlersInitialized) return;
    server.assertCanSetRequestHandler(Method.toolsList);
    server.assertCanSetRequestHandler(Method.toolsCall);
    server.registerCapabilities(
      const ServerCapabilities(tools: ServerCapabilitiesTools()),
    );

    server.setRequestHandler<JsonRpcListToolsRequest>(
      Method.toolsList,
      (request, extra) async => ListToolsResult(
        tools: _registeredTools.values
            .where((t) => t.enabled)
            .map((e) => e.toTool())
            .toList(),
      ),
      (id, params, meta) => JsonRpcListToolsRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    server.setRequestHandler<JsonRpcCallToolRequest>(
      Method.toolsCall,
      (request, extra) async {
        final toolName = request.callParams.name;
        final toolArgs = request.callParams.arguments;
        final registeredTool = _registeredTools[toolName];
        if (registeredTool == null) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Tool '$toolName' not found",
          );
        }
        if (!registeredTool.enabled) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Tool '$toolName' is disabled",
          );
        }

        // Validate arguments against schema
        if (registeredTool.inputSchema != null) {
          try {
            registeredTool.inputSchema!.validate(toolArgs);
          } catch (e) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Invalid arguments for tool '$toolName': $e",
            );
          }
        }

        try {
          final isTaskRequest = request.isTaskAugmented;
          final taskSupport =
              registeredTool.execution?.taskSupport ?? 'forbidden';

          final isTaskHandler =
              registeredTool.callback is InterfaceToolCallback;

          // Validate task hint configuration
          if ((taskSupport == 'required' || taskSupport == 'optional') &&
              !isTaskHandler) {
            throw McpError(
              ErrorCode.internalError.value,
              "Tool '$toolName' has taskSupport '$taskSupport' but was not registered with registerToolTask",
            );
          }

          dynamic result;
          if (taskSupport == 'required') {
            if (!isTaskRequest) {
              throw McpError(
                ErrorCode.methodNotFound.value,
                "Tool '$toolName' requires task augmentation (taskSupport: 'required')",
              );
            }
            final InterfaceToolCallback taskHandler =
                registeredTool.callback as InterfaceToolCallback;
            result = await taskHandler.handler.createTask(toolArgs, extra);
          } else if (taskSupport == 'optional') {
            if (!isTaskRequest) {
              // Ensure we have a task handler for automatic polling (checked above, but safe cast)
              result = await _handleAutomaticTaskPolling(
                registeredTool,
                toolArgs,
                extra,
              );
            } else {
              final InterfaceToolCallback taskHandler =
                  registeredTool.callback as InterfaceToolCallback;
              result = await taskHandler.handler.createTask(toolArgs, extra);
            }
          } else {
            // taskSupport is 'forbidden' or not specified
            if (isTaskRequest) {
              throw McpError(
                ErrorCode.invalidParams.value,
                "Tool '$toolName' does not support task augmentation (taskSupport: 'forbidden')",
              );
            }
            final FunctionToolCallback toolCallback =
                registeredTool.callback as FunctionToolCallback;
            result = await toolCallback.function(
              toolArgs,
              extra,
            );
          }

          if (registeredTool.outputSchema != null && result is CallToolResult) {
            if (result.isError != true) {
              try {
                registeredTool.outputSchema!.validate(
                  result.structuredContent,
                );
              } catch (e) {
                throw McpError(
                  ErrorCode.invalidParams.value,
                  "Output validation error: Invalid structured content for tool '$toolName': $e",
                );
              }
            }
          }

          return result;
        } catch (error) {
          _logger.warn("Error executing tool '$toolName': $error");
          if (error is McpError) {
            rethrow; // Pass through McpErrors (like methodNotFound)
          }
          return CallToolResult(
            content: [TextContent(text: error.toString())],
            isError: true,
          );
        }
      },
      (id, params, meta) => JsonRpcCallToolRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );
    _toolHandlersInitialized = true;
  }

  void _ensureCompletionHandlerInitialized() {
    if (_completionHandlerInitialized) return;
    server.assertCanSetRequestHandler(Method.completionComplete);
    server.registerCapabilities(
      const ServerCapabilities(
        completions: ServerCapabilitiesCompletions(listChanged: true),
      ),
    );
    server.setRequestHandler<JsonRpcCompleteRequest>(
      Method.completionComplete,
      (request, extra) async => switch (request.completeParams.ref) {
        final ResourceReference r => _handleResourceCompletion(
            r,
            request.completeParams.argument,
          ),
        final PromptReference p => _handlePromptCompletion(
            p,
            request.completeParams.argument,
          ),
      },
      (id, params, meta) => JsonRpcCompleteRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );
    _completionHandlerInitialized = true;
  }

  Future<CompleteResult> _handlePromptCompletion(
    PromptReference ref,
    ArgumentCompletionInfo argInfo,
  ) async {
    final prompt = _registeredPrompts[ref.name];
    if (prompt == null || !prompt.enabled) return _emptyCompletionResult();

    final argDef = prompt.argsSchemaDefinition?[argInfo.name];
    final completer = argDef?.completable?.def.complete;
    if (completer == null) return _emptyCompletionResult();
    try {
      return _createCompletionResult(await completer(argInfo.value));
    } catch (e) {
      _logger.warn(
        "Error during prompt argument completion for '${ref.name}.${argInfo.name}': $e",
      );
      throw McpError(ErrorCode.internalError.value, "Completion failed");
    }
  }

  Future<CompleteResult> _handleResourceCompletion(
    ResourceReference ref,
    ArgumentCompletionInfo argInfo,
  ) async {
    final templateEntry = _registeredResourceTemplates.entries.firstWhere(
      (e) => e.value.resourceTemplate.uriTemplate.toString() == ref.uri,
      orElse: () => throw McpError(
        ErrorCode.invalidParams.value,
        "Resource template URI '${ref.uri}' not found for completion",
      ),
    );
    if (!templateEntry.value.enabled) return _emptyCompletionResult();

    final completer = templateEntry.value.resourceTemplate
        .getCompletionCallback(argInfo.name);
    if (completer == null) return _emptyCompletionResult();
    try {
      return _createCompletionResult(await completer(argInfo.value));
    } catch (e) {
      _logger.warn(
        "Error during resource template completion for '${ref.uri}' variable '${argInfo.name}': $e",
      );
      throw McpError(ErrorCode.internalError.value, "Completion failed");
    }
  }

  void _ensureResourceHandlersInitialized() {
    if (_resourceHandlersInitialized) return;
    server.assertCanSetRequestHandler(Method.resourcesList);
    server.assertCanSetRequestHandler(Method.resourcesTemplatesList);
    server.assertCanSetRequestHandler(Method.resourcesRead);
    server.registerCapabilities(
      const ServerCapabilities(resources: ServerCapabilitiesResources()),
    );

    server.setRequestHandler<JsonRpcListResourcesRequest>(
      Method.resourcesList,
      (request, extra) async {
        final fixed = _registeredResources.values
            .where((r) => r.enabled)
            .map((e) => e.toResource())
            .toList();
        final templateFutures = _registeredResourceTemplates.values
            .where((t) => t.resourceTemplate.listCallback != null && t.enabled)
            .map((t) async {
          try {
            final result = await Future.value(
              t.resourceTemplate.listCallback!(extra),
            );
            return result.resources
                .map(
                  (r) => Resource(
                    uri: r.uri,
                    name: r.name,
                    description: r.description ?? t.metadata?.description,
                    mimeType: r.mimeType ?? t.metadata?.mimeType,
                  ),
                )
                .toList();
          } catch (e) {
            _logger.warn("Error listing resources for template: $e");
            return <Resource>[];
          }
        });
        final templateLists = await Future.wait(templateFutures);
        final templates = templateLists.expand((list) => list).toList();
        return ListResourcesResult(resources: [...fixed, ...templates]);
      },
      (id, params, meta) => JsonRpcListResourcesRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    server.setRequestHandler<JsonRpcListResourceTemplatesRequest>(
      Method.resourcesTemplatesList,
      (request, extra) async => ListResourceTemplatesResult(
        resourceTemplates: _registeredResourceTemplates.entries
            .where((e) => e.value.enabled)
            .map((e) => e.value.toResourceTemplate())
            .toList(),
      ),
      (id, params, meta) => JsonRpcListResourceTemplatesRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    server.setRequestHandler<JsonRpcReadResourceRequest>(
      Method.resourcesRead,
      (request, extra) async {
        final uriString = request.readParams.uri;
        Uri uri;
        try {
          uri = Uri.parse(uriString);
        } catch (e) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Invalid URI: $uriString",
          );
        }
        final fixed = _registeredResources[uriString];
        if (fixed != null) {
          if (!fixed.enabled) {
            throw McpError(
              ErrorCode.invalidParams.value,
              "Resource disabled: $uriString",
            );
          }
          return await Future.value(fixed.readCallback(uri, extra));
        }
        for (final entry in _registeredResourceTemplates.values) {
          if (!entry.enabled) continue;
          final vars = entry.resourceTemplate.uriTemplate.match(uriString);
          if (vars != null) {
            return await Future.value(entry.readCallback(uri, vars, extra));
          }
        }
        throw McpError(
          ErrorCode.invalidParams.value,
          "Resource not found: $uriString",
        );
      },
      (id, params, meta) => JsonRpcReadResourceRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    _ensureCompletionHandlerInitialized();
    _resourceHandlersInitialized = true;
  }

  void _ensurePromptHandlersInitialized() {
    if (_promptHandlersInitialized) return;
    server.assertCanSetRequestHandler(Method.promptsList);
    server.assertCanSetRequestHandler(Method.promptsGet);
    server.registerCapabilities(
      const ServerCapabilities(prompts: ServerCapabilitiesPrompts()),
    );

    server.setRequestHandler<JsonRpcListPromptsRequest>(
      Method.promptsList,
      (request, extra) async => ListPromptsResult(
        prompts: _registeredPrompts.values
            .where((p) => p.enabled)
            .map((p) => p.toPrompt())
            .toList(),
      ),
      (id, params, meta) => JsonRpcListPromptsRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    server.setRequestHandler<JsonRpcGetPromptRequest>(
      Method.promptsGet,
      (request, extra) async {
        final name = request.getParams.name;
        final args = request.getParams.arguments;
        final registered = _registeredPrompts[name];
        if (registered == null) {
          throw McpError(
            ErrorCode.methodNotFound.value,
            "Prompt '$name' not found",
          );
        }
        if (!registered.enabled) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Prompt '$name' is disabled",
          );
        }

        try {
          dynamic parsedArgs = args ?? {};
          if (registered.argsSchemaDefinition != null) {
            parsedArgs = _validatePromptArgs(
              Map<String, dynamic>.from(parsedArgs),
              registered.argsSchemaDefinition!,
            );
          }
          if (registered.callback != null) {
            return await Future.value(registered.callback!(parsedArgs, extra));
          } else {
            throw StateError("No callback found");
          }
        } catch (error) {
          _logger.warn("Error executing prompt '$name': $error");
          if (error is McpError) rethrow;
          throw McpError(
            ErrorCode.internalError.value,
            "Failed to generate prompt '$name': $error",
          );
        }
      },
      (id, params, meta) => JsonRpcGetPromptRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    _ensureCompletionHandlerInitialized();
    _promptHandlersInitialized = true;
  }

  Map<String, dynamic> _validatePromptArgs(
    Map<String, dynamic> rawArgs,
    Map<String, PromptArgumentDefinition> schema,
  ) {
    final validatedArgs = <String, dynamic>{};
    final List<String> errors = [];
    schema.forEach((name, def) {
      final value = rawArgs[name];
      if (value == null) {
        if (def.required) errors.add("Missing required '$name'");
      } else {
        // Basic type checking
        bool typeOk = false;
        if (def.type == String) typeOk = value is String;
        if (def.type == int) typeOk = value is int;
        if (def.type == double) typeOk = value is num;
        if (def.type == num) typeOk = value is num;
        if (def.type == bool) typeOk = value is bool;

        if (!typeOk) {
          errors.add(
            "Invalid type for '$name'. Expected ${def.type}, got ${value.runtimeType}",
          );
        } else {
          validatedArgs[name] = value;
        }
      }
    });
    if (errors.isNotEmpty) {
      throw McpError(
        ErrorCode.invalidParams.value,
        "Invalid arguments: ${errors.join('; ')}",
      );
    }
    return validatedArgs;
  }

  // --- Registration Methods ---

  /// Registers a resource.
  ///
  /// [name] is the human-readable name of the resource.
  /// [uri] is the unique URI for the resource.
  /// [metadata] provides optional description and MIME type.
  /// [readCallback] is the function called when the resource is read.
  RegisteredResource registerResource(
    String name,
    String uri,
    ResourceMetadata? metadata,
    ReadResourceCallback readCallback,
  ) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    final resource = _RegisteredResourceImpl(
      this,
      name: name,
      uri: uri,
      metadata: metadata,
      readCallback: readCallback,
    );
    _registeredResources[uri] = resource;
    _ensureResourceHandlersInitialized();
    sendResourceListChanged();
    return resource;
  }

  /// Registers a resource template.
  ///
  /// [name] is the unique name for this template registration.
  /// [template] defines the URI pattern and completion behavior.
  /// [metadata] provides optional description and MIME type for resources matching this template.
  /// [readCallback] is the function called when a matching resource is read.
  RegisteredResourceTemplate registerResourceTemplate(
    String name,
    ResourceTemplateRegistration template,
    ResourceMetadata? metadata,
    ReadResourceTemplateCallback readCallback,
  ) {
    if (_registeredResourceTemplates.containsKey(name)) {
      throw ArgumentError(
        "Resource template name '$name' already registered.",
      );
    }
    final resourceTemplate = _RegisteredResourceTemplateImpl(
      this,
      name: name,
      resourceTemplate: template,
      metadata: metadata,
      readCallback: readCallback,
    );
    _registeredResourceTemplates[name] = resourceTemplate;
    _ensureResourceHandlersInitialized();
    sendResourceListChanged();
    return resourceTemplate;
  }

  /// Registers a tool.
  ///
  /// [name] is the unique name of the tool.
  /// [title] is a human-readable title.
  /// [description] explains what the tool does.
  /// [inputSchema] defines the expected arguments.
  /// [outputSchema] defines the expected result structure.
  /// [annotations] provides additional metadata.
  /// [callback] is the function executed when the tool is called.
  RegisteredTool registerTool(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    required ToolFunction callback,
  }) {
    return _registerTool(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: annotations,
      meta: meta,
      execution: const ToolExecution(taskSupport: 'forbidden'),
      callback: FunctionToolCallback(callback),
    );
  }

  /// Internal registration method.
  RegisteredTool _registerTool(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    ToolExecution? execution,
    required ToolCallback callback,
  }) {
    if (_registeredTools.containsKey(name)) {
      throw ArgumentError("Tool name '$name' already registered.");
    }
    validateAndWarnToolName(name);
    final tool = _RegisteredToolImpl(
      this,
      name: name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: annotations,
      meta: meta,
      execution: execution,
      callback: callback,
    );
    _registeredTools[name] = tool;
    _ensureToolHandlersInitialized();
    sendToolListChanged();
    return tool;
  }

  /// Registers a prompt.
  ///
  /// [name] is the unique name of the prompt.
  /// [title] is a human-readable title.
  /// [description] explains what the prompt generates.
  /// [argsSchema] defines the arguments acceptable by this prompt.
  /// [callback] is the function to generate the prompt content.
  RegisteredPrompt registerPrompt(
    String name, {
    String? title,
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    required PromptCallback callback,
  }) {
    if (_registeredPrompts.containsKey(name)) {
      throw ArgumentError("Prompt name '$name' already registered.");
    }
    final prompt = _RegisteredPromptImpl(
      this,
      name: name,
      title: title,
      description: description,
      argsSchemaDefinition: argsSchema,
      callback: callback,
    );
    _registeredPrompts[name] = prompt;
    _ensurePromptHandlersInitialized();
    sendPromptListChanged();
    return prompt;
  }

  // --- Legacy Methods (Wrappers) ---

  /// Registers a resource with a fixed, non-template [uri].
  @Deprecated('Use registerResource instead')
  RegisteredResource resource(
    String name,
    String uri,
    ReadResourceCallback readCallback, {
    ResourceMetadata? metadata,
    ImageContent? icon,
  }) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    final resource = _RegisteredResourceImpl(
      this,
      name: name,
      uri: uri,
      metadata: metadata,
      icon: icon,
      readCallback: readCallback,
    );
    _registeredResources[uri] = resource;
    _ensureResourceHandlersInitialized();
    sendResourceListChanged();
    return resource;
  }

  /// Registers resources based on a [templateRegistration] defining a URI pattern.
  @Deprecated('Use registerResourceTemplate instead')
  RegisteredResourceTemplate resourceTemplate(
    String name,
    ResourceTemplateRegistration templateRegistration,
    ReadResourceTemplateCallback readCallback, {
    ResourceMetadata? metadata,
  }) {
    return registerResourceTemplate(
      name,
      templateRegistration,
      metadata,
      readCallback,
    );
  }

  /// Registers a tool the client can invoke.
  /// Registers a tool the client can invoke.
  @Deprecated('Use registerTool instead')
  RegisteredTool tool(
    String name, {
    String? description,
    ToolInputSchema? toolInputSchema,
    ToolOutputSchema? toolOutputSchema,
    @Deprecated('Use toolInputSchema instead')
    Map<String, dynamic>? inputSchemaProperties,
    @Deprecated('Use toolOutputSchema instead')
    Map<String, dynamic>? outputSchemaProperties,
    ToolAnnotations? annotations,
    required LegacyToolCallback callback,
  }) {
    if (_registeredTools.containsKey(name)) {
      throw ArgumentError("Tool name '$name' already registered.");
    }
    validateAndWarnToolName(name);

    final toolCallback = FunctionToolCallback(
      (args, extra) => callback(args: args, extra: extra),
    );

    final tool = _RegisteredToolImpl(
      this,
      name: name,
      description: description,
      inputSchema: toolInputSchema ??
          (inputSchemaProperties != null
              ? ToolInputSchema(
                  properties: inputSchemaProperties.map(
                    (key, value) => MapEntry(key, JsonSchema.fromJson(value)),
                  ),
                )
              : null),
      outputSchema: toolOutputSchema ??
          (outputSchemaProperties != null
              ? ToolOutputSchema(
                  properties: outputSchemaProperties.map(
                    (key, value) => MapEntry(key, JsonSchema.fromJson(value)),
                  ),
                )
              : null),
      annotations: annotations,
      icon: null,
      execution: const ToolExecution(taskSupport: 'forbidden'),
      callback: toolCallback,
    );
    _registeredTools[name] = tool;
    _ensureToolHandlersInitialized();
    sendToolListChanged();
    return tool;
  }

  /// Registers a prompt or prompt template.
  @Deprecated('Use registerPrompt instead')
  RegisteredPrompt prompt(
    String name, {
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    ImageContent? icon,
    PromptCallback? callback,
  }) {
    if (_registeredPrompts.containsKey(name)) {
      throw ArgumentError("Prompt name '$name' already registered.");
    }

    final prompt = _RegisteredPromptImpl(
      this,
      name: name,
      description: description,
      argsSchemaDefinition: argsSchema,
      icon: icon,
      callback: callback,
    );
    _registeredPrompts[name] = prompt;
    _ensurePromptHandlersInitialized();
    sendPromptListChanged();
    return prompt;
  }

  CompleteResult _createCompletionResult(List<String> suggestions) {
    final limited = suggestions.take(100).toList();
    return CompleteResult(
      completion: CompletionResultData(
        values: limited,
        total: suggestions.length,
        hasMore: suggestions.length > 100,
      ),
    );
  }

  CompleteResult _emptyCompletionResult() => CompleteResult(
        completion: CompletionResultData(values: [], hasMore: false),
      );

  /// Handles automatic task polling for tools with taskSupport 'optional'.
  Future<CallToolResult> _handleAutomaticTaskPolling(
    _RegisteredToolImpl tool,
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final InterfaceToolCallback taskHandler =
        tool.callback as InterfaceToolCallback;

    // Create task using the tool's task handler
    final CreateTaskResult createTaskResult =
        await taskHandler.handler.createTask(args, extra);
    final String taskId = createTaskResult.task.taskId;
    Task task = createTaskResult.task;
    final int pollInterval =
        task.pollInterval ?? 5000; // Default to 5000ms if not specified

    // Poll until completion
    while (task.status != TaskStatus.completed &&
        task.status != TaskStatus.failed &&
        task.status != TaskStatus.cancelled) {
      await Future.delayed(Duration(milliseconds: pollInterval));
      final updatedTask = await taskHandler.handler.getTask(taskId, extra);
      task = updatedTask;
    }

    // Return the final result
    return await taskHandler.handler.getTaskResult(taskId, extra);
  }

  /// Requests structured user input from the client using form mode.
  Future<ElicitResult> elicitInput(
    ElicitRequest params, [
    RequestOptions? options,
  ]) async {
    return server.elicitInput(params, options);
  }
}
