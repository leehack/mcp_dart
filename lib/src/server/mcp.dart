import 'dart:async';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:mcp_dart/src/types.dart';

import 'server.dart';

final _logger = Logger("mcp_dart.server.mcp");

typedef CompleteCallback = Future<List<String>> Function(String value);

class CompletableDef {
  final CompleteCallback complete;
  const CompletableDef({required this.complete});
}

class CompletableField {
  final CompletableDef def;
  final Type underlyingType;
  const CompletableField({required this.def, this.underlyingType = String});
}

typedef ToolCallback = FutureOr<BaseResultData> Function({
  Map<String, dynamic>? args,
  Map<String, dynamic>? meta,
  RequestHandlerExtra? extra,
});

typedef PromptCallback = FutureOr<GetPromptResult> Function(
  Map<String, dynamic>? args,
  RequestHandlerExtra? extra,
);

class PromptArgumentDefinition {
  final String? description;
  final bool required;
  final Type type;
  final CompletableField? completable;

  const PromptArgumentDefinition({
    this.description,
    this.required = false,
    this.type = String,
    this.completable,
  });
}

typedef ResourceMetadata = ({
  String? description,
  String? mimeType,
});

typedef ListResourcesCallback = FutureOr<ListResourcesResult> Function(
    RequestHandlerExtra extra);

typedef ReadResourceCallback = FutureOr<ReadResourceResult> Function(
    Uri uri, RequestHandlerExtra extra);

typedef ReadResourceTemplateCallback = FutureOr<ReadResourceResult> Function(
  Uri uri,
  TemplateVariables variables,
  RequestHandlerExtra extra,
);

typedef CompleteResourceTemplateCallback = FutureOr<List<String>> Function(
    String currentValue);

typedef ListTasksCallback = FutureOr<ListTasksResult> Function(
    RequestHandlerExtra extra);

typedef CancelTaskCallback = FutureOr<void> Function(
    String taskId, RequestHandlerExtra extra);

typedef GetTaskCallback = FutureOr<Task> Function(
    String taskId, RequestHandlerExtra extra);

typedef TaskResultCallback = FutureOr<CallToolResult> Function(
    String taskId, RequestHandlerExtra extra);

class ResourceTemplateRegistration {
  final UriTemplateExpander uriTemplate;
  final ListResourcesCallback? listCallback;
  final Map<String, CompleteResourceTemplateCallback>? completeCallbacks;

  ResourceTemplateRegistration(
    String templateString, {
    required this.listCallback,
    this.completeCallbacks,
  }) : uriTemplate = UriTemplateExpander(templateString);

  CompleteResourceTemplateCallback? getCompletionCallback(String variableName) {
    return completeCallbacks?[variableName];
  }
}

class _RegisteredTool {
  final String? description;
  final ToolInputSchema? toolInputSchema;
  final ToolOutputSchema? toolOutputSchema;
  final ToolAnnotations? annotations;
  final ImageContent? icon;
  final ToolCallback callback;

  const _RegisteredTool({
    this.description,
    this.toolInputSchema,
    this.toolOutputSchema,
    this.annotations,
    this.icon,
    required this.callback,
  });

  Tool toTool(String name) {
    return Tool(
      name: name,
      description: description,
      inputSchema: toolInputSchema ?? ToolInputSchema(),
      // Do not include output schema in the payload if it isn't defined
      outputSchema: toolOutputSchema,
      annotations: annotations,
      icon: icon,
    );
  }
}

class _RegisteredPrompt<Args> {
  final String? description;
  final Map<String, PromptArgumentDefinition>? argsSchemaDefinition;
  final ImageContent? icon;
  final PromptCallback? callback;

  const _RegisteredPrompt({
    this.description,
    this.argsSchemaDefinition,
    this.icon,
    this.callback,
  });

  Prompt toPrompt(String name) {
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
}

class _RegisteredResource {
  final String name;
  final ResourceMetadata? metadata;
  final ImageContent? icon;
  final ReadResourceCallback readCallback;

  const _RegisteredResource({
    required this.name,
    this.metadata,
    this.icon,
    required this.readCallback,
  });

  Resource toResource(String uri) {
    return Resource(
      uri: uri,
      name: name,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
      icon: icon,
    );
  }
}

class _RegisteredResourceTemplate {
  final ResourceTemplateRegistration resourceTemplate;
  final ResourceMetadata? metadata;
  final ReadResourceTemplateCallback readCallback;

  const _RegisteredResourceTemplate({
    required this.resourceTemplate,
    this.metadata,
    required this.readCallback,
  });

  ResourceTemplate toResourceTemplate(String name) {
    return ResourceTemplate(
      uriTemplate: resourceTemplate.uriTemplate.toString(),
      name: name,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
    );
  }
}

/// High-level Model Context Protocol (MCP) server API.
///
/// Simplifies the registration of resources, tools, and prompts by providing
/// helper methods (`resource`, `tool`, `prompt`) that configure the necessary
/// request handlers on an underlying [Server] instance.
class McpServer {
  late final Server server;

  final Map<String, _RegisteredResource> _registeredResources = {};
  final Map<String, _RegisteredResourceTemplate> _registeredResourceTemplates =
      {};
  final Map<String, _RegisteredTool> _registeredTools = {};
  final Map<String, _RegisteredPrompt> _registeredPrompts = {};

  bool _resourceHandlersInitialized = false;
  bool _toolHandlersInitialized = false;
  bool _promptHandlersInitialized = false;
  bool _completionHandlerInitialized = false;
  bool _taskHandlersInitialized = false;

  ListTasksCallback? _listTasksCallback;
  CancelTaskCallback? _cancelTaskCallback;
  GetTaskCallback? _getTaskCallback;
  TaskResultCallback? _taskResultCallback;

  /// Creates an [McpServer] instance.
  McpServer(Implementation serverInfo, {ServerOptions? options}) {
    server = Server(serverInfo, options: options);
  }

  /// Connects the server to a communication [transport].
  Future<void> connect(Transport transport) async {
    return await server.connect(transport);
  }

  /// Closes the server connection by closing the underlying transport.
  Future<void> close() async {
    await server.close();
  }

  /// Sets the error handler for the server.
  set onError(void Function(Error)? handler) {
    server.onerror = handler;
  }

  /// Gets the error handler for the server.
  void Function(Error)? get onError => server.onerror;

  void _ensureTaskHandlersInitialized() {
    if (_taskHandlersInitialized) return;
    server.assertCanSetRequestHandler(Method.tasksList);
    server.assertCanSetRequestHandler(Method.tasksCancel);
    server.assertCanSetRequestHandler(Method.tasksGet);
    server.assertCanSetRequestHandler(Method.tasksResult);
    server.registerCapabilities(
      const ServerCapabilities(
        tasks: ServerCapabilitiesTasks(listChanged: true),
      ),
    );

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

    _taskHandlersInitialized = true;
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
        tools:
            _registeredTools.entries.map((e) => e.value.toTool(e.key)).toList(),
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
            ErrorCode.methodNotFound.value,
            "Tool '$toolName' not found",
          );
        }
        try {
          // Cast the result to BaseResultData
          return await Future.value(
            registeredTool.callback(
                args: toolArgs, meta: request.meta, extra: extra),
          );
        } catch (error) {
          _logger.warn("Error executing tool '$toolName': $error");
          return CallToolResult.fromContent(
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
        ResourceReference r => _handleResourceCompletion(
            r,
            request.completeParams.argument,
          ),
        PromptReference p => _handlePromptCompletion(
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
    final argDef =
        _registeredPrompts[ref.name]?.argsSchemaDefinition?[argInfo.name];
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
        final fixed = _registeredResources.entries
            .map((e) => e.value.toResource(e.key))
            .toList();
        final templateFutures = _registeredResourceTemplates.values
            .where((t) => t.resourceTemplate.listCallback != null)
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
            .map((e) => e.value.toResourceTemplate(e.key))
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
          return await Future.value(fixed.readCallback(uri, extra));
        }
        for (final entry in _registeredResourceTemplates.values) {
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
        prompts: _registeredPrompts.entries
            .map((e) => e.value.toPrompt(e.key))
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
            "Failed to generate prompt '$name'",
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
    List<String> errors = [];
    schema.forEach((name, def) {
      final value = rawArgs[name];
      if (value == null) {
        if (def.required) errors.add("Missing required '$name'");
      } else {
        bool typeOk = (value.runtimeType == def.type ||
            (def.type == num && value is num));
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

  /// Registers a resource with a fixed, non-template [uri].
  void resource(
    String name,
    String uri,
    ReadResourceCallback readCallback, {
    ResourceMetadata? metadata,
    ImageContent? icon,
  }) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    _registeredResources[uri] = _RegisteredResource(
      name: name,
      metadata: metadata,
      icon: icon,
      readCallback: readCallback,
    );
    _ensureResourceHandlersInitialized();
  }

  /// Registers resources based on a [templateRegistration] defining a URI pattern.
  void resourceTemplate(
    String name,
    ResourceTemplateRegistration templateRegistration,
    ReadResourceTemplateCallback readCallback, {
    ResourceMetadata? metadata,
  }) {
    if (_registeredResourceTemplates.containsKey(name)) {
      throw ArgumentError("Resource template name '$name' already registered.");
    }
    _registeredResourceTemplates[name] = _RegisteredResourceTemplate(
      resourceTemplate: templateRegistration,
      metadata: metadata,
      readCallback: readCallback,
    );
    _ensureResourceHandlersInitialized();
  }

  /// Registers a tool the client can invoke.
  void tool(
    String name, {
    String? description,
    ToolInputSchema? toolInputSchema,
    ToolOutputSchema? toolOutputSchema,
    @Deprecated('Use toolInputSchema instead')
    Map<String, dynamic>? inputSchemaProperties,
    @Deprecated('Use toolOutputSchema instead')
    Map<String, dynamic>? outputSchemaProperties,
    ToolAnnotations? annotations,
    ImageContent? icon,
    required ToolCallback callback,
  }) {
    if (_registeredTools.containsKey(name)) {
      throw ArgumentError("Tool name '$name' already registered.");
    }
    _registeredTools[name] = _RegisteredTool(
      description: description,
      toolInputSchema: toolInputSchema ??
          (inputSchemaProperties != null
              ? ToolInputSchema(properties: inputSchemaProperties)
              : null),
      toolOutputSchema: toolOutputSchema ??
          (outputSchemaProperties != null
              ? ToolOutputSchema(properties: outputSchemaProperties)
              : null),
      annotations: annotations,
      icon: icon,
      callback: callback,
    );
    _ensureToolHandlersInitialized();
  }

  /// Registers a prompt or prompt template.
  void prompt(
    String name, {
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    ImageContent? icon,
    PromptCallback? callback,
  }) {
    if (_registeredPrompts.containsKey(name)) {
      throw ArgumentError("Prompt name '$name' already registered.");
    }

    _registeredPrompts[name] = _RegisteredPrompt(
      description: description,
      argsSchemaDefinition: argsSchema,
      icon: icon,
      callback: callback,
    );
    _ensurePromptHandlersInitialized();
  }

  /// Registers task handlers for the server.
  void tasks({
    required ListTasksCallback listCallback,
    required CancelTaskCallback cancelCallback,
    GetTaskCallback? getCallback,
    TaskResultCallback? resultCallback,
  }) {
    if (_listTasksCallback != null) {
      throw StateError("Task handlers already registered");
    }
    _listTasksCallback = listCallback;
    _cancelTaskCallback = cancelCallback;
    _getTaskCallback = getCallback;
    _taskResultCallback = resultCallback;
    _ensureTaskHandlersInitialized();
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

  /// Requests structured user input from the client using form mode.
  ///
  /// This sends an `elicitation/create` request to the client with the specified
  /// [message] text and [requestedSchema] defining the input structure.
  ///
  /// Form mode collects structured data directly through the MCP client,
  /// where the data is visible to the client.
  ///
  /// The client must have the elicitation capability (with form support) for this to work.
  ///
  /// Returns an [ElicitResult] containing the action taken ('accept', 'decline',
  /// or 'cancel') and the submitted content when accepted.
  ///
  /// Example:
  /// ```dart
  /// final result = await server.elicitUserInput(
  ///   "Enter your name",
  ///   {
  ///     'type': 'object',
  ///     'properties': {
  ///       'name': {'type': 'string', 'minLength': 1}
  ///     },
  ///     'required': ['name']
  ///   },
  /// );
  ///
  /// if (result.accepted) {
  ///   print("User entered: ${result.content}");
  /// }
  /// ```
  Future<ElicitResult> elicitUserInput(
    String message,
    Map<String, dynamic> requestedSchema, {
    Map<String, dynamic>? meta,
    RequestOptions? options,
  }) async {
    server.assertCapabilityForMethod(Method.elicitationCreate);

    final request = JsonRpcElicitRequest(
      id: -1,
      elicitParams: ElicitRequestParams.form(
        message: message,
        requestedSchema: requestedSchema,
      ),
      meta: meta,
    );

    return await server.request<ElicitResult>(
      request,
      (json) => ElicitResult.fromJson(json),
      options,
    );
  }

  /// Requests user interaction via URL mode elicitation.
  ///
  /// This sends an `elicitation/create` request to the client with the specified
  /// [message] and [url] for the user to navigate to.
  ///
  /// URL mode directs users to external URLs for sensitive interactions where
  /// the data should NOT be exposed to the MCP client. Use this for:
  /// - OAuth/authentication flows
  /// - Payment processing
  /// - Sensitive data entry (passwords, credit cards)
  ///
  /// The [elicitationId] is a unique identifier that correlates the URL navigation
  /// with subsequent completion notifications.
  ///
  /// The client must have the elicitation capability (with url support) for this to work.
  ///
  /// After the user completes the URL interaction, the server should send a
  /// `notifications/elicitation/complete` notification using [notifyElicitationComplete].
  ///
  /// Example:
  /// ```dart
  /// final result = await server.elicitUserInputViaUrl(
  ///   message: "Please authenticate with your provider",
  ///   url: "https://oauth.example.com/authorize?client_id=xxx",
  ///   elicitationId: "oauth-session-123",
  /// );
  ///
  /// if (result.accepted) {
  ///   // User acknowledged the URL - wait for callback or poll for completion
  /// }
  /// ```
  Future<ElicitResult> elicitUserInputViaUrl({
    required String message,
    required String url,
    required String elicitationId,
    Map<String, dynamic>? meta,
    RequestOptions? options,
  }) async {
    server.assertCapabilityForMethod(Method.elicitationCreate);

    final request = JsonRpcElicitRequest(
      id: -1,
      elicitParams: ElicitRequestParams.url(
        message: message,
        url: url,
        elicitationId: elicitationId,
      ),
      meta: meta,
    );

    return await server.request<ElicitResult>(
      request,
      (json) => ElicitResult.fromJson(json),
      options,
    );
  }

  /// Sends a notification that a URL mode elicitation has completed.
  ///
  /// This should be called after the out-of-band interaction started by
  /// [elicitUserInputViaUrl] has been completed (e.g., OAuth callback received).
  ///
  /// Example:
  /// ```dart
  /// // After OAuth callback is received
  /// await server.notifyElicitationComplete("oauth-session-123");
  /// ```
  Future<void> notifyElicitationComplete(String elicitationId) async {
    await server.notification(
      JsonRpcElicitationCompleteNotification(
        completeParams: ElicitationCompleteParams(
          elicitationId: elicitationId,
        ),
      ),
    );
  }

  /// Requests the client to generate a message using sampling.
  ///
  /// This sends a `sampling/createMessage` request to the client with the specified
  /// [messages] and [maxTokens] (and other optional parameters).
  ///
  /// The client must have the sampling capability for this to work.
  ///
  /// Example:
  /// ```dart
  /// final result = await server.createSamplingMessage(
  ///   messages: [
  ///     SamplingMessage(
  ///       role: SamplingMessageRole.user,
  ///       content: SamplingTextContent(text: "Write a haiku"),
  ///     ),
  ///   ],
  ///   maxTokens: 50,
  /// );
  ///
  /// if (result.content is SamplingTextContent) {
  ///   print("Haiku: ${(result.content as SamplingTextContent).text}");
  /// }
  /// ```
  Future<CreateMessageResult> createSamplingMessage({
    required List<SamplingMessage> messages,
    required int maxTokens,
    String? systemPrompt,
    double? temperature,
    ModelPreferences? modelPreferences,
    List<String>? stopSequences,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? meta,
    RequestOptions? options,
  }) async {
    server.assertCapabilityForMethod(Method.samplingCreateMessage);

    final request = JsonRpcCreateMessageRequest(
      id: -1,
      createParams: CreateMessageRequestParams(
        messages: messages,
        maxTokens: maxTokens,
        systemPrompt: systemPrompt,
        temperature: temperature,
        modelPreferences: modelPreferences,
        stopSequences: stopSequences,
        metadata: metadata,
      ),
      meta: meta,
    );

    return await server.request<CreateMessageResult>(
      request,
      (json) => CreateMessageResult.fromJson(json),
      options,
    );
  }

  /// Sends a `notifications/tasks/status` notification to the client.
  ///
  /// This notifies the client of a change in a task's status.
  ///
  /// The server must have the task capability for this to work.
  ///
  /// Example:
  /// ```dart
  /// await server.notifyTaskStatus(
  ///   taskId: "task-123",
  ///   status: TaskStatus.running,
  ///   statusMessage: "Processing...",
  /// );
  /// ```
  Future<void> notifyTaskStatus({
    required String taskId,
    required TaskStatus status,
    String? statusMessage,
    Map<String, dynamic>? meta,
  }) async {
    server.assertNotificationCapability(Method.notificationsTasksStatus);

    final notif = JsonRpcTaskStatusNotification(
      statusParams: TaskStatusNotificationParams(
        taskId: taskId,
        status: status,
        statusMessage: statusMessage,
      ),
      meta: meta,
    );

    return await server.notification(notif);
  }
}
