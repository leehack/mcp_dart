import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:mcp_dart/src/types.dart';
import 'server.dart';

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

typedef ToolCallback = FutureOr<CallToolResult> Function({
  Map<String, dynamic>? args,
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
  Map<String, dynamic> additionalProperties,
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
  final Map<String, dynamic>? inputSchemaProperties;
  final Map<String, dynamic>? additionalProperties;
  final ToolCallback callback;

  const _RegisteredTool({
    this.description,
    this.inputSchemaProperties,
    this.additionalProperties,
    required this.callback,
  });

  Tool toTool(String name) {
    final schema = ToolInputSchema(
      properties: inputSchemaProperties,
      additionalProperties: additionalProperties ?? const {},
    );
    return Tool(name: name, description: description, inputSchema: schema);
  }
}

class _RegisteredPrompt<Args> {
  final String? description;
  final Map<String, PromptArgumentDefinition>? argsSchemaDefinition;
  final PromptCallback? callback;

  const _RegisteredPrompt({
    this.description,
    this.argsSchemaDefinition,
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
    return Prompt(name: name, description: description, arguments: promptArgs);
  }
}

class _RegisteredResource {
  final String name;
  final ResourceMetadata? metadata;
  final ReadResourceCallback readCallback;

  const _RegisteredResource({
    required this.name,
    this.metadata,
    required this.readCallback,
  });

  Resource toResource(String uri) {
    return Resource(
      uri: uri,
      name: name,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
      additionalProperties: metadata?.additionalProperties ?? const {},
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
      additionalProperties: metadata?.additionalProperties ?? const {},
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

  void _ensureToolHandlersInitialized() {
    if (_toolHandlersInitialized) return;
    server.assertCanSetRequestHandler("tools/list");
    server.assertCanSetRequestHandler("tools/call");
    server.registerCapabilities(
      const ServerCapabilities(tools: ServerCapabilitiesTools()),
    );

    server.setRequestHandler<JsonRpcListToolsRequest>(
      "tools/list",
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
      "tools/call",
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
          return await Future.value(
            registeredTool.callback(args: toolArgs, extra: extra),
          );
        } catch (error) {
          print("Error executing tool '$toolName': $error");
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
    server.assertCanSetRequestHandler("completion/complete");
    server.setRequestHandler<JsonRpcCompleteRequest>(
      "completion/complete",
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
      print(
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
      print(
        "Error during resource template completion for '${ref.uri}' variable '${argInfo.name}': $e",
      );
      throw McpError(ErrorCode.internalError.value, "Completion failed");
    }
  }

  void _ensureResourceHandlersInitialized() {
    if (_resourceHandlersInitialized) return;
    server.assertCanSetRequestHandler("resources/list");
    server.assertCanSetRequestHandler("resources/templates/list");
    server.assertCanSetRequestHandler("resources/read");
    server.registerCapabilities(
      const ServerCapabilities(resources: ServerCapabilitiesResources()),
    );

    server.setRequestHandler<JsonRpcListResourcesRequest>(
      "resources/list",
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
                    additionalProperties: {
                      ...?t.metadata?.additionalProperties,
                      ...r.additionalProperties,
                    },
                  ),
                )
                .toList();
          } catch (e) {
            print("Error listing resources for template: $e");
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
      "resources/templates/list",
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
      "resources/read",
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
    server.assertCanSetRequestHandler("prompts/list");
    server.assertCanSetRequestHandler("prompts/get");
    server.registerCapabilities(
      const ServerCapabilities(prompts: ServerCapabilitiesPrompts()),
    );

    server.setRequestHandler<JsonRpcListPromptsRequest>(
      "prompts/list",
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
      "prompts/get",
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
          print("Error executing prompt '$name': $error");
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
  }) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    _registeredResources[uri] = _RegisteredResource(
      name: name,
      metadata: metadata,
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
    Map<String, dynamic>? inputSchemaProperties,
    Map<String, dynamic>? additionalProperties,
    required ToolCallback callback,
  }) {
    if (_registeredTools.containsKey(name)) {
      throw ArgumentError("Tool name '$name' already registered.");
    }
    _registeredTools[name] = _RegisteredTool(
      description: description,
      inputSchemaProperties: inputSchemaProperties,
      additionalProperties: additionalProperties,
      callback: callback,
    );
    _ensureToolHandlersInitialized();
  }

  /// Registers a prompt or prompt template.
  void prompt(
    String name, {
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    PromptCallback? callback,
  }) {
    if (_registeredPrompts.containsKey(name)) {
      throw ArgumentError("Prompt name '$name' already registered.");
    }

    _registeredPrompts[name] = _RegisteredPrompt(
      description: description,
      argsSchemaDefinition: argsSchema,
      callback: callback,
    );
    _ensurePromptHandlersInitialized();
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
}
