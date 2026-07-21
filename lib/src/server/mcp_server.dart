import 'dart:async';

import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/mcp_header_validation.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/tool_parameter_headers.dart';
import 'package:mcp_dart/src/shared/tool_name_validation.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:mcp_dart/src/types.dart';

import 'server.dart';
import 'server_protocol_state.dart';
import 'tasks.dart';

final _logger = Logger("mcp_dart.server.mcp");

const _requiredClientCapabilitiesMetaKey =
    'io.modelcontextprotocol/requiredClientCapabilities';

/// Callback capable of providing completions for a partial value.
typedef CompleteCallback = FutureOr<List<String>> Function(String value);

/// Callback capable of providing completions with request context.
typedef CompleteWithContextCallback = FutureOr<List<String>> Function(
  String value,
  CompletionContext? context,
);

IconTheme? _iconThemeFromString(String? theme) {
  return switch (theme) {
    'light' => IconTheme.light,
    'dark' => IconTheme.dark,
    _ => null,
  };
}

List<McpIcon>? _iconsFromLegacyImage(ImageContent? image) {
  if (image == null) {
    return null;
  }

  return [
    McpIcon(
      src: 'data:${image.mimeType};base64,${image.data}',
      mimeType: image.mimeType,
      theme: _iconThemeFromString(image.theme),
    ),
  ];
}

bool _isStateless2026Request(String? protocolVersion) =>
    protocolVersion != null && isStatelessProtocolVersion(protocolVersion);

bool _usesModernToolValidationSemantics(String? protocolVersion) =>
    protocolVersion == latestInitializationProtocolVersion ||
    _isStateless2026Request(protocolVersion);

bool _usesStableTaskNegotiation(String? protocolVersion) =>
    protocolVersion == latestInitializationProtocolVersion;

String? _protocolVersionForToolCall(
  JsonRpcCallToolRequest request,
  String? negotiatedProtocolVersion,
) =>
    _protocolVersionForRequest(
      request.meta,
      negotiatedProtocolVersion,
    );

String? _protocolVersionForRequest(
  Map<String, dynamic>? meta,
  String? negotiatedProtocolVersion,
) {
  final requestProtocolVersion = meta?[McpMetaKey.protocolVersion];
  if (requestProtocolVersion is String &&
      _isStateless2026Request(requestProtocolVersion)) {
    return requestProtocolVersion;
  }
  return negotiatedProtocolVersion;
}

bool _isStableStructuredContentValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return true;
  }
  if (value is Map) {
    return value.keys.every((key) => key is String);
  }
  return false;
}

JsonSchema? _outputSchemaForProtocol(
  JsonSchema? schema,
  String? protocolVersion,
) {
  if (schema == null || _isStateless2026Request(protocolVersion)) {
    return schema;
  }

  // MCP 2025-11-25 restricts tool output schemas to object roots. MCP
  // 2026-07-28 allows any JSON Schema, so omit non-object schemas for
  // initialization-era callers.
  if (schema.toJson()['type'] == 'object') {
    return schema;
  }
  return null;
}

JsonSchema? _resolveToolOutputJsonSchema(
  ToolOutputSchema? outputSchema,
  JsonSchema? outputJsonSchema,
) {
  if (outputSchema != null && outputJsonSchema != null) {
    throw ArgumentError(
      'Specify only one of outputSchema or outputJsonSchema.',
    );
  }
  return outputJsonSchema ?? outputSchema;
}

int _toolOutputValidationErrorCode(String? protocolVersion) =>
    _usesModernToolValidationSemantics(protocolVersion)
        ? ErrorCode.internalError.value
        : ErrorCode.invalidParams.value;

void Function(dynamic)? _compileToolOutputValidator(
  JsonSchema? outputSchema,
  String toolName,
  String? protocolVersion,
) {
  if (outputSchema == null) {
    return null;
  }

  try {
    return compileJsonSchemaValidator(outputSchema);
  } on JsonSchemaDefinitionException catch (error, stackTrace) {
    _logger.error(
      "Invalid output schema for tool '$toolName': $error\n$stackTrace",
    );
    throw McpError(
      _toolOutputValidationErrorCode(protocolVersion),
      "Tool '$toolName' has an invalid or unsupported output schema.",
    );
  }
}

final class _TaskOutputValidationSnapshot {
  final String toolName;
  final void Function(dynamic) validateOutput;

  const _TaskOutputValidationSnapshot({
    required this.toolName,
    required this.validateOutput,
  });
}

void _validateToolOutputResult(
  CallToolResult result,
  void Function(dynamic)? validateOutput,
  String toolName,
  String? protocolVersion,
) {
  if (validateOutput == null || result.isError) {
    return;
  }

  final errorCode = _toolOutputValidationErrorCode(protocolVersion);
  if (!result.hasStructuredContent) {
    throw McpError(
      errorCode,
      "Tool '$toolName' did not return structuredContent required by its "
      'output schema.',
    );
  }

  try {
    validateOutput(result.structuredContentJson!.toJson());
  } catch (error, stackTrace) {
    _logger.error(
      "Output validation failed for tool '$toolName': $error\n$stackTrace",
    );
    throw McpError(
      errorCode,
      "Tool '$toolName' returned structured content that does not match its "
      'output schema.',
    );
  }
}

ServerTaskOutputValidator _taskOutputValidator(
  void Function(dynamic) validateOutput,
  String toolName,
  String? protocolVersion,
) {
  return (resultJson) {
    final CallToolResult result;
    try {
      result = CallToolResult.fromJson(resultJson);
    } catch (error, stackTrace) {
      _logger.error(
        "Invalid completed task result for tool '$toolName': "
        '$error\n$stackTrace',
      );
      throw ServerTaskOutputValidationError(
        _toolOutputValidationErrorCode(protocolVersion),
        "Tool '$toolName' returned an invalid completed task result.",
      );
    }
    try {
      _validateToolOutputResult(
        result,
        validateOutput,
        toolName,
        protocolVersion,
      );
    } on McpError catch (error) {
      throw ServerTaskOutputValidationError(
        error.code,
        error.message,
        error.data,
      );
    }
  };
}

CallToolResult _toolResultForProtocol(
  CallToolResult result,
  String? protocolVersion,
) {
  if (_isStateless2026Request(protocolVersion) ||
      !result.hasStructuredContent ||
      _isStableStructuredContentValue(result.structuredContentJson?.toJson())) {
    return result;
  }

  return CallToolResult(
    content: result.content,
    isError: result.isError,
    meta: result.meta,
    extra: result.extra,
  );
}

McpError _resourceNotFoundErrorForProtocol(
  String uri,
  String? protocolVersion,
) {
  return McpError(
    _isStateless2026Request(protocolVersion)
        ? ErrorCode.invalidParams.value
        : ErrorCode.resourceNotFound.value,
    'Resource not found',
    {'uri': uri},
  );
}

/// Definition for a completable argument.
class CompletableDef {
  /// The callback to invoke to get completion suggestions.
  final CompleteCallback complete;

  /// Optional callback that also receives `completion/complete` context.
  final CompleteWithContextCallback? completeWithContext;

  const CompletableDef({
    required this.complete,
    this.completeWithContext,
  });

  FutureOr<List<String>> _completeValue(
    String value,
    CompletionContext? context,
  ) {
    final completeWithContext = this.completeWithContext;
    if (completeWithContext != null) {
      return completeWithContext(value, context);
    }
    return complete(value);
  }
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

/// MCP 2026-07-28 tool callback that may request additional client input.
typedef StatelessToolFunction = FutureOr<BaseResultData> Function(
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

/// MCP 2026-07-28 prompt callback that may request additional client input.
typedef StatelessPromptCallback = FutureOr<BaseResultData> Function(
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

/// MCP 2026-07-28 resource callback that may request additional client input.
typedef StatelessReadResourceCallback = FutureOr<BaseResultData> Function(
  Uri uri,
  RequestHandlerExtra extra,
);

/// Callback to read a resource template.
typedef ReadResourceTemplateCallback = FutureOr<ReadResourceResult> Function(
  Uri uri,
  TemplateVariables variables,
  RequestHandlerExtra extra,
);

/// MCP 2026-07-28 template callback that may request additional client input.
typedef StatelessReadResourceTemplateCallback = FutureOr<BaseResultData>
    Function(
  Uri uri,
  TemplateVariables variables,
  RequestHandlerExtra extra,
);

/// Callback to complete a value within a resource template.
typedef CompleteResourceTemplateCallback = FutureOr<List<String>> Function(
  String currentValue,
);

/// Callback to complete a value within a resource template with request context.
typedef CompleteResourceTemplateWithContextCallback = FutureOr<List<String>>
    Function(
  String currentValue,
  CompletionContext? context,
);

/// Callback to list available tasks.
typedef ListTasksCallback = FutureOr<ListTasksResult> Function(
  RequestHandlerExtra extra,
);

/// Legacy callback to cancel a running task without returning its final state.
///
/// Prefer [CancelTaskCallback] for MCP 2025-11-25-compatible `tasks/cancel`
/// results.
typedef LegacyCancelTaskCallback = FutureOr<void> Function(
  String taskId,
  RequestHandlerExtra extra,
);

/// Callback to cancel a running task.
///
/// Must return the final cancelled task state for the `tasks/cancel` result.
typedef CancelTaskCallback = FutureOr<Task> Function(
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

Map<String, dynamic> _relatedTaskMeta(String taskId) => {'taskId': taskId};

CallToolResult _withRelatedTaskMeta(CallToolResult result, String taskId) {
  final relatedTaskJson = _relatedTaskMeta(taskId);
  final meta = Map<String, dynamic>.from(result.meta ?? {});
  meta[relatedTaskMetadataKey] = relatedTaskJson;
  meta[legacyRelatedTaskMetadataKey] = relatedTaskJson;

  return CallToolResult(
    content: result.content,
    isError: result.isError,
    structuredContentJson: result.structuredContentJson,
    hasStructuredContent: result.hasStructuredContent,
    meta: meta,
    extra: result.extra,
  );
}

/// Registration details for a resource template.
class ResourceTemplateRegistration {
  /// The URI template expander.
  final UriTemplateExpander uriTemplate;

  /// The callback to list resources matching this template.
  final ListResourcesCallback? listCallback;

  /// Callbacks to complete variables within the template.
  final Map<String, CompleteResourceTemplateCallback>? completeCallbacks;

  /// Context-aware callbacks to complete variables within the template.
  final Map<String, CompleteResourceTemplateWithContextCallback>?
      completeCallbacksWithContext;

  ResourceTemplateRegistration(
    String templateString, {
    required this.listCallback,
    this.completeCallbacks,
    this.completeCallbacksWithContext,
  }) : uriTemplate = UriTemplateExpander(templateString);

  /// Gets the completion callback for a specific variable.
  CompleteResourceTemplateCallback? getCompletionCallback(String variableName) {
    return completeCallbacks?[variableName];
  }

  FutureOr<List<String>>? _completeVariable(
    String variableName,
    String currentValue,
    CompletionContext? context,
  ) {
    final completeWithContext = completeCallbacksWithContext?[variableName];
    if (completeWithContext != null) {
      return completeWithContext(currentValue, context);
    }
    final complete = completeCallbacks?[variableName];
    if (complete == null) return null;
    return complete(currentValue);
  }
}

/// Abstract interface for a registered resource.
abstract class RegisteredResource {
  /// The name of the resource.
  String get name;

  /// The title of the resource.
  String? get title;

  /// Metadata associated with the resource.
  ResourceMetadata? get metadata;

  /// Optional metadata included in resource listings as `_meta`.
  Map<String, dynamic>? get meta;

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
    Map<String, dynamic>? meta,
    ReadResourceCallback? callback,
    bool? enabled,
  });
}

class _RegisteredResourceImpl implements RegisteredResource {
  @override
  String name;
  @override
  String? title;
  String uri;
  @override
  ResourceMetadata? metadata;
  @override
  Map<String, dynamic>? meta;
  final ImageContent? icon; // Kept for legacy compatibility
  ReadResourceCallback? _legacyReadCallback;
  StatelessReadResourceCallback _statelessReadCallback;

  @override
  ReadResourceCallback get readCallback {
    final legacyReadCallback = _legacyReadCallback;
    if (legacyReadCallback != null) {
      return legacyReadCallback;
    }
    return (uri, extra) async {
      final result = await Future.value(_statelessReadCallback(uri, extra));
      if (result is ReadResourceResult) {
        return result;
      }
      throw StateError(
        'The stateless resource callback returned InputRequiredResult. '
        'The v2.2.2 readCallback view can only return ReadResourceResult.',
      );
    };
  }

  FutureOr<BaseResultData> invokeReadCallback(
    Uri uri,
    RequestHandlerExtra extra,
  ) =>
      _statelessReadCallback(uri, extra);

  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredResourceImpl(
    this._server, {
    required this.name,
    this.title,
    required this.uri,
    this.metadata,
    this.meta,
    this.icon,
    ReadResourceCallback? readCallback,
    StatelessReadResourceCallback? statelessReadCallback,
  })  : assert(
          readCallback != null || statelessReadCallback != null,
          'A resource read callback is required.',
        ),
        _legacyReadCallback = readCallback,
        _statelessReadCallback = statelessReadCallback ?? readCallback!;

  Resource toResource() {
    return Resource(
      uri: uri,
      name: name,
      title: title,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
      icon: icon,
      icons: _iconsFromLegacyImage(icon),
      meta: meta,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() {
    if (_server._removeRegistration(
      _server._registeredResources,
      uri,
      this,
    )) {
      _server.sendResourceListChanged();
    }
  }

  @override
  void update({
    String? name,
    String? title,
    String? uri,
    ResourceMetadata? metadata,
    Map<String, dynamic>? meta,
    ReadResourceCallback? callback,
    bool? enabled,
  }) {
    if (uri != null && uri != this.uri) {
      final oldUri = this.uri;
      _server._updateResourceUri(oldUri, uri, this);
      this.uri = uri;
    }
    if (name != null) this.name = name;
    if (title != null) this.title = title;
    if (metadata != null) this.metadata = metadata;
    if (meta != null) this.meta = meta;
    if (callback != null) {
      _legacyReadCallback = callback;
      _statelessReadCallback = callback;
    }
    if (enabled != null) this.enabled = enabled;

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

  /// Optional metadata included in resource template listings as `_meta`.
  Map<String, dynamic>? get meta;

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
    Map<String, dynamic>? meta,
    ReadResourceTemplateCallback? callback,
    bool? enabled,
  });
}

class _RegisteredResourceTemplateImpl implements RegisteredResourceTemplate {
  String name;
  @override
  ResourceTemplateRegistration resourceTemplate;
  @override
  String? title;
  @override
  ResourceMetadata? metadata;
  @override
  Map<String, dynamic>? meta;
  ReadResourceTemplateCallback? _legacyReadCallback;
  StatelessReadResourceTemplateCallback _statelessReadCallback;

  @override
  ReadResourceTemplateCallback get readCallback {
    final legacyReadCallback = _legacyReadCallback;
    if (legacyReadCallback != null) {
      return legacyReadCallback;
    }
    return (uri, variables, extra) async {
      final result = await Future.value(
        _statelessReadCallback(uri, variables, extra),
      );
      if (result is ReadResourceResult) {
        return result;
      }
      throw StateError(
        'The stateless resource template callback returned '
        'InputRequiredResult. The v2.2.2 readCallback view can only return '
        'ReadResourceResult.',
      );
    };
  }

  FutureOr<BaseResultData> invokeReadCallback(
    Uri uri,
    TemplateVariables variables,
    RequestHandlerExtra extra,
  ) =>
      _statelessReadCallback(uri, variables, extra);

  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredResourceTemplateImpl(
    this._server, {
    required this.name,
    this.title,
    required this.resourceTemplate,
    this.metadata,
    this.meta,
    ReadResourceTemplateCallback? readCallback,
    StatelessReadResourceTemplateCallback? statelessReadCallback,
  })  : assert(
          readCallback != null || statelessReadCallback != null,
          'A resource template read callback is required.',
        ),
        _legacyReadCallback = readCallback,
        _statelessReadCallback = statelessReadCallback ?? readCallback!;

  ResourceTemplate toResourceTemplate() {
    return ResourceTemplate(
      uriTemplate: resourceTemplate.uriTemplate.toString(),
      name: name,
      title: title,
      description: metadata?.description,
      mimeType: metadata?.mimeType,
      meta: meta,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() {
    if (_server._removeRegistration(
      _server._registeredResourceTemplates,
      name,
      this,
    )) {
      _server.sendResourceListChanged();
    }
  }

  @override
  void update({
    String? name,
    String? title,
    ResourceTemplateRegistration? template,
    ResourceMetadata? metadata,
    Map<String, dynamic>? meta,
    ReadResourceTemplateCallback? callback,
    bool? enabled,
  }) {
    if (name != null && name != this.name) {
      final oldName = this.name;
      _server._updateResourceTemplateName(oldName, name, this);
      this.name = name;
    }
    if (title != null) this.title = title;
    if (template != null) resourceTemplate = template;
    if (metadata != null) this.metadata = metadata;
    if (meta != null) this.meta = meta;
    if (callback != null) {
      _legacyReadCallback = callback;
      _statelessReadCallback = callback;
    }
    if (enabled != null) this.enabled = enabled;

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
  ///
  /// This is the object-root compatibility view. For a stateless registration
  /// with a non-object schema it returns `null`; use
  /// [RegisteredStatelessTool.outputJsonSchema] for the complete schema.
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

/// A registered MCP 2026-07-28 tool with access to its stateless-only surface.
///
/// This additive subtype preserves the existing [RegisteredTool] contract while
/// exposing output schemas with non-object roots. Task-backed registrations also
/// use this handle; their [statelessCallback] is `null` because their callback is
/// represented by [RegisteredTool.callback] as an [InterfaceToolCallback].
abstract class RegisteredStatelessTool extends RegisteredTool {
  /// The complete output schema, including non-object MCP 2026-07-28 roots.
  JsonSchema? get outputJsonSchema;

  /// The stateless function callback, or `null` for task-backed registrations.
  StatelessToolFunction? get statelessCallback;

  /// Updates MCP 2026-07-28 tool configuration without narrowing its schema.
  ///
  /// Set [clearOutputSchema] to remove the advertised output schema. It cannot
  /// be combined with [outputJsonSchema]. A task-backed registration may update
  /// its schema and common metadata through this method, but its handler remains
  /// available through [RegisteredTool.callback].
  void updateStateless({
    String? name,
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    JsonSchema? outputJsonSchema,
    bool clearOutputSchema = false,
    ToolAnnotations? annotations,
    ToolExecution? execution,
    StatelessToolFunction? callback,
    bool? enabled,
  });
}

class _RegisteredToolImpl implements RegisteredStatelessTool {
  @override
  String name;
  @override
  String? title;
  @override
  String? description;
  @override
  ToolInputSchema? inputSchema;
  JsonSchema? _outputJsonSchema;
  @override
  ToolAnnotations? annotations;
  final ImageContent? icon;
  final Map<String, dynamic>? meta;
  @override
  ToolExecution? execution;
  @override
  ToolCallback? callback;
  @override
  StatelessToolFunction? statelessCallback;
  @override
  bool enabled = true;

  final McpServer _server;

  _RegisteredToolImpl(
    this._server, {
    required this.name,
    this.title,
    this.description,
    this.inputSchema,
    JsonSchema? outputJsonSchema,
    this.annotations,
    this.icon,
    this.meta,
    this.execution,
    required this.callback,
    this.statelessCallback,
  }) : _outputJsonSchema = outputJsonSchema {
    _server._registeredTools[name] = this;
  }

  @override
  ToolOutputSchema? get outputSchema {
    final schema = _outputJsonSchema;
    if (schema is JsonObject) {
      return schema;
    }
    return null;
  }

  @override
  JsonSchema? get outputJsonSchema => _outputJsonSchema;

  Tool toTool({
    bool includeExecution = true,
    ToolInputSchema? inputSchemaOverride,
    String? protocolVersion,
  }) {
    return Tool(
      name: name,
      title: title,
      description: description,
      inputSchema:
          inputSchemaOverride ?? inputSchema ?? const ToolInputSchema(),
      outputSchema:
          _outputSchemaForProtocol(_outputJsonSchema, protocolVersion),
      annotations: annotations,
      icon: icon,
      icons: _iconsFromLegacyImage(icon),
      execution: includeExecution ? execution : null,
      meta: meta,
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() {
    if (_server._removeRegistration(
      _server._registeredTools,
      name,
      this,
    )) {
      _server.sendToolListChanged();
    }
  }

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
    _update(
      name: name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputJsonSchema: outputSchema,
      annotations: annotations,
      execution: execution,
      legacyCallback: callback,
      enabled: enabled,
    );
  }

  @override
  void updateStateless({
    String? name,
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    JsonSchema? outputJsonSchema,
    bool clearOutputSchema = false,
    ToolAnnotations? annotations,
    ToolExecution? execution,
    StatelessToolFunction? callback,
    bool? enabled,
  }) {
    if (callback != null && this.callback is InterfaceToolCallback) {
      throw StateError(
        'A task-backed tool callback cannot be replaced with a stateless '
        'function. Update its InterfaceToolCallback through update() instead.',
      );
    }
    _update(
      name: name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputJsonSchema: outputJsonSchema,
      clearOutputSchema: clearOutputSchema,
      annotations: annotations,
      execution: execution,
      newStatelessCallback: callback,
      enabled: enabled,
    );
  }

  void _update({
    String? name,
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    JsonSchema? outputJsonSchema,
    bool clearOutputSchema = false,
    ToolAnnotations? annotations,
    ToolExecution? execution,
    ToolCallback? legacyCallback,
    StatelessToolFunction? newStatelessCallback,
    bool? enabled,
  }) {
    if (clearOutputSchema && outputJsonSchema != null) {
      throw ArgumentError(
        'clearOutputSchema cannot be combined with outputJsonSchema.',
        'clearOutputSchema',
      );
    }
    if (name != null && name != this.name) {
      validateAndWarnToolName(name);
      _server._updateToolName(this.name, name, this);
      this.name = name;
    }
    if (title != null) this.title = title;
    if (description != null) this.description = description;
    if (inputSchema != null) this.inputSchema = inputSchema;
    if (clearOutputSchema) {
      _outputJsonSchema = null;
    } else if (outputJsonSchema != null) {
      _outputJsonSchema = outputJsonSchema;
    }
    if (annotations != null) this.annotations = annotations;
    if (execution != null) this.execution = execution;
    if (legacyCallback != null) {
      callback = legacyCallback;
      statelessCallback = null;
    }
    if (newStatelessCallback != null) {
      callback = null;
      statelessCallback = newStatelessCallback;
    }
    if (enabled != null) this.enabled = enabled;

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
  StatelessPromptCallback? callback;
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
      title: title,
      description: description,
      arguments: promptArgs,
      icon: icon,
      icons: _iconsFromLegacyImage(icon),
    );
  }

  @override
  void enable() => update(enabled: true);

  @override
  void disable() => update(enabled: false);

  @override
  void remove() {
    if (_server._removeRegistration(
      _server._registeredPrompts,
      name,
      this,
    )) {
      _server.sendPromptListChanged();
    }
  }

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
      _server._updatePromptName(this.name, name, this);
      this.name = name;
    }
    if (title != null) this.title = title;
    if (description != null) this.description = description;
    if (argsSchema != null) argsSchemaDefinition = argsSchema;
    if (callback != null) this.callback = callback;
    if (enabled != null) this.enabled = enabled;

    _server.sendPromptListChanged();
  }
}

/// Experimental task-related functionality for the server.
class ExperimentalMcpServerTasks {
  final McpServer _server;

  ExperimentalMcpServerTasks(this._server);

  /// Registers a task-based tool with a config object and handler.
  ///
  /// Schema-invalid arguments are rejected before task acceptance, so
  /// [ToolTaskHandler.createTask] is not invoked and no task is created.
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
    return _registerToolTask(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: annotations,
      meta: meta,
      execution: execution,
      handler: handler,
    );
  }

  /// Registers a task-based tool with an arbitrary MCP 2026-07-28 output schema.
  RegisteredStatelessTool registerStatelessToolTask(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    JsonSchema? outputJsonSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    ToolExecution? execution,
    required ToolTaskHandler handler,
  }) {
    return _registerToolTask(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      outputJsonSchema: outputJsonSchema,
      annotations: annotations,
      meta: meta,
      execution: execution,
      handler: handler,
    );
  }

  _RegisteredToolImpl _registerToolTask(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    JsonSchema? outputJsonSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    ToolExecution? execution,
    required ToolTaskHandler handler,
  }) {
    // Validate that taskSupport is not 'forbidden' for task-based tools
    final effectiveExecution = ToolExecution(
      taskSupport: execution?.taskSupport ?? 'required',
    );
    // Validate against the spec-defined wire values before advertising the tool.
    effectiveExecution.toJson();
    if (effectiveExecution.taskSupport == 'forbidden') {
      throw ArgumentError(
        "Cannot register task-based tool '$name' with taskSupport 'forbidden'. Use registerTool() instead.",
      );
    }
    if (_server._registeredTools.containsKey(name)) {
      throw ArgumentError("Tool name '$name' already registered.");
    }

    final hasTaskToolCallCapability =
        _server.server.getCapabilities().tasks?.requests?.tools?.call != null;
    if (!hasTaskToolCallCapability) {
      if (_server.isConnected) {
        throw StateError(
          "Cannot register task-based tool '$name' after connect() unless "
          "server capabilities already include 'tasks.requests.tools.call'. "
          "Configure ServerCapabilities.tasks.requests.tools.call before "
          "connect() or register task-based tools before connecting.",
        );
      }
      _server.server.registerCapabilities(
        const ServerCapabilities(
          tasks: ServerCapabilitiesTasks(
            requests: ServerCapabilitiesTasksRequests(
              tools: ServerCapabilitiesTasksTools(
                call: ServerCapabilitiesTasksToolsCall(),
              ),
            ),
          ),
        ),
      );
    }

    return _server._registerTool(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      outputJsonSchema: outputJsonSchema,
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

  /// Registers a legacy callback for cancelling a task.
  ///
  /// This keeps pre-MCP-2025-11-25 code source-compatible. The callback should
  /// cancel the task; the server then calls the registered `onGetTask` callback
  /// to return the final cancelled [Task] required by `tasks/cancel`.
  @Deprecated(
    'MCP 2025-11-25 requires tasks/cancel to return a Task. '
    'Use onCancelTaskWithResult instead. '
    'This compatibility shim will be removed in the next major release.',
  )
  void onCancelTask(LegacyCancelTaskCallback callback) {
    _server._cancelTaskCallback = (taskId, extra) async {
      await Future.value(callback(taskId, extra));

      final getTask = _server._getTaskCallback;
      if (getTask == null) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'Legacy onCancelTask requires onGetTask to resolve the cancelled task',
        );
      }
      return Future.value(getTask(taskId, extra));
    };
    _server._ensureTaskHandlersInitialized();
  }

  /// Registers a callback for cancelling a task and returning its final state.
  ///
  /// The callback must cancel the task and return the final cancelled [Task]
  /// used as the `tasks/cancel` result. Throw [McpError] if the task cannot
  /// be cancelled, is missing, or is already terminal.
  void onCancelTaskWithResult(CancelTaskCallback callback) {
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

// Keep the high-level facade's session-scoped state aligned with Protocol's
// transport lifecycle without widening the deprecated Server public API.
// ignore: deprecated_member_use_from_same_package
final class _McpServerProtocol extends Server {
  final void Function() _onConnectionClosedCallback;

  _McpServerProtocol(
    super.serverInfo, {
    super.options,
    required void Function() onConnectionClosed,
  }) : _onConnectionClosedCallback = onConnectionClosed;

  @override
  void onConnectionClosed() {
    super.onConnectionClosed();
    _onConnectionClosedCallback();
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
  // Keep only the immutable validation contract captured when a task is
  // accepted. This avoids retaining mutable registration handles or changing
  // in-flight tasks when a tool is updated; terminal validation removes it.
  final Map<(String?, String), _TaskOutputValidationSnapshot>
      _taskOutputValidationsById = {};
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
    server = _McpServerProtocol(
      serverInfo,
      options: options,
      onConnectionClosed: _taskOutputValidationsById.clear,
    );
  }

  /// Connects the server to a communication [transport].
  Future<void> connect(Transport transport) async {
    _syncToolParameterHeaderMappings(transport);
    linkServerTaskOutputValidationScope(server, transport);
    await server.connect(transport);
    if (transport is IncomingRequestValidationAwareTransport) {
      final validationAwareTransport =
          transport as IncomingRequestValidationAwareTransport;
      validationAwareTransport.setIncomingRequestValidator((request) {
        final protocolError = server.validateIncomingRequest(request);
        if (protocolError != null) {
          return protocolError;
        }
        return _validateToolClientCapabilities(request);
      });
    }
  }

  /// Closes the server connection.
  Future<void> close() async {
    try {
      await server.close();
    } finally {
      _taskOutputValidationsById.clear();
      clearServerTaskOutputValidators(server);
    }
  }

  /// Checks if the server is connected to a transport.
  bool get isConnected => server.transport != null;

  McpError? _validateToolClientCapabilities(JsonRpcRequest request) {
    if (request is! JsonRpcCallToolRequest ||
        !_isStateless2026Request(request.meta?[McpMetaKey.protocolVersion])) {
      return null;
    }

    final tool = _registeredTools[request.callParams.name];
    if (tool == null) {
      return null;
    }

    final requiredCapabilities = _requiredClientCapabilities(tool);
    if (requiredCapabilities.isEmpty) {
      return null;
    }

    final clientCapabilitiesValue =
        request.meta?[McpMetaKey.clientCapabilities];
    if (clientCapabilitiesValue is! Map) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Missing required request metadata: ${McpMetaKey.clientCapabilities}',
      );
    }

    final clientCapabilities = ClientCapabilities.fromJson(
      clientCapabilitiesValue.cast<String, dynamic>(),
    );
    final missingCapabilities = requiredCapabilities
        .where(
          (capability) => !_hasClientCapability(clientCapabilities, capability),
        )
        .toList(growable: false);
    if (missingCapabilities.isEmpty) {
      return null;
    }

    return McpError(
      ErrorCode.missingRequiredClientCapability.value,
      'Missing required client capability',
      {'requiredCapabilities': _clientCapabilitiesShape(missingCapabilities)},
    );
  }

  Map<String, dynamic> _clientCapabilitiesShape(List<String> capabilities) {
    return {
      for (final capability in capabilities) capability: <String, dynamic>{},
    };
  }

  List<String> _requiredClientCapabilities(_RegisteredToolImpl tool) {
    final value = tool.meta?[_requiredClientCapabilitiesMetaKey];
    if (value is String) {
      return [value];
    }
    if (value is Iterable) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  bool _hasClientCapability(
    ClientCapabilities capabilities,
    String capability,
  ) {
    return switch (capability) {
      'sampling' => capabilities.sampling != null,
      'roots' => capabilities.roots != null,
      'elicitation' => capabilities.elicitation != null,
      'tasks' => capabilities.tasks != null,
      _ => capabilities.additionalCapabilities?.containsKey(capability) ??
          capabilities.experimental?.containsKey(capability) ??
          capabilities.extensions?.containsKey(capability) ??
          false,
    };
  }

  /// Sends a logging message to the client, if connected.
  Future<void> sendLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
  }) async {
    return server.sendLoggingMessage(
      params,
      sessionId: sessionId,
    );
  }

  /// Sends a request-scoped logging message for stateless MCP.
  ///
  /// Pass [requestMeta] from [RequestHandlerExtra.meta] so the notification
  /// honors the request's `io.modelcontextprotocol/logLevel` opt-in.
  /// Pass [requestId] from [RequestHandlerExtra.requestId] so Streamable HTTP
  /// routes the notification on the originating response stream.
  Future<void> sendStatelessLoggingMessage(
    LoggingMessageNotification params, {
    String? sessionId,
    required Map<String, dynamic>? requestMeta,
    RequestId? requestId,
  }) async {
    return server.sendStatelessLoggingMessage(
      params,
      sessionId: sessionId,
      requestMeta: requestMeta,
      requestId: requestId,
    );
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
    _replaceRegistrationKey(
      _registeredResources,
      oldUri,
      newUri,
      resource,
      'Resource URI',
    );
  }

  void _updateResourceTemplateName(
    String oldName,
    String newName,
    _RegisteredResourceTemplateImpl template,
  ) {
    _replaceRegistrationKey(
      _registeredResourceTemplates,
      oldName,
      newName,
      template,
      'Resource template name',
    );
  }

  void _updateToolName(
    String oldName,
    String newName,
    _RegisteredToolImpl tool,
  ) {
    _replaceRegistrationKey(
      _registeredTools,
      oldName,
      newName,
      tool,
      'Tool name',
    );
  }

  void _updatePromptName(
    String oldName,
    String newName,
    _RegisteredPromptImpl prompt,
  ) {
    _replaceRegistrationKey(
      _registeredPrompts,
      oldName,
      newName,
      prompt,
      'Prompt name',
    );
  }

  void _replaceRegistrationKey<T>(
    Map<String, T> registrations,
    String oldKey,
    String newKey,
    T registration,
    String label,
  ) {
    if (!identical(registrations[oldKey], registration)) {
      throw StateError('$label registration is no longer active.');
    }
    final existing = registrations[newKey];
    if (existing != null && !identical(existing, registration)) {
      throw ArgumentError("$label '$newKey' is already registered.");
    }
    registrations.remove(oldKey);
    registrations[newKey] = registration;
  }

  bool _removeRegistration<T>(
    Map<String, T> registrations,
    String key,
    T registration,
  ) {
    if (!identical(registrations[key], registration)) {
      return false;
    }
    registrations.remove(key);
    return true;
  }

  void sendResourceListChanged() {
    if (server.transport != null) {
      server.sendResourceListChanged();
    }
  }

  /// Notifies clients that the list of available tools has changed.
  void sendToolListChanged() {
    if (server.transport != null) {
      _syncToolParameterHeaderMappings();
      server.sendToolListChanged();
    }
  }

  void _syncToolParameterHeaderMappings([Transport? target]) {
    final activeTransport = target ?? server.transport;
    final headerAwareTransport =
        activeTransport is ToolParameterHeaderAwareTransport
            ? activeTransport as ToolParameterHeaderAwareTransport
            : null;
    if (headerAwareTransport != null) {
      headerAwareTransport.setToolParameterHeaderMappings(
        _buildToolParameterHeaderMappings(),
      );
    }
  }

  ToolParameterHeaderMappings _buildToolParameterHeaderMappings() {
    final mappings = <String, Map<String, String>>{};

    for (final tool in _registeredTools.values) {
      if (!tool.enabled) {
        continue;
      }

      final toolMappings = _toolParameterHeaderMappingsFor(tool);
      if (toolMappings.isNotEmpty) {
        mappings[tool.name] = toolMappings;
      }
    }

    return mappings;
  }

  ToolInputSchema _toolInputSchemaForStatelessList(
    _RegisteredToolImpl tool,
  ) {
    final inputSchema = tool.inputSchema ?? const ToolInputSchema();
    final properties = inputSchema.properties;
    final reachabilityReason =
        toolParameterHeaderReachabilityRejectionReason(inputSchema.toJson());

    final ignoredReason = properties == null || properties.isEmpty
        ? null
        : _collectToolParameterHeaderMappings(
            toolName: tool.name,
            properties: properties,
            path: const [],
            mappings: <String, String>{},
            seenHeaders: <String>{},
          );
    if (reachabilityReason == null && ignoredReason == null) {
      return inputSchema;
    }

    return _stripToolParameterHeaderMetadata(inputSchema);
  }

  ToolInputSchema _stripToolParameterHeaderMetadata(ToolInputSchema schema) {
    return JsonSchema.fromJson(
      stripToolParameterHeaderAnnotations(schema.toJson()),
    ) as ToolInputSchema;
  }

  Map<String, String> _toolParameterHeaderMappingsFor(
    _RegisteredToolImpl tool,
  ) {
    final inputSchema = tool.inputSchema;
    if (inputSchema != null) {
      final reachabilityReason =
          toolParameterHeaderReachabilityRejectionReason(inputSchema.toJson());
      if (reachabilityReason != null) {
        _logger.warn(
          'Ignoring x-mcp-header mappings for tool "${tool.name}": '
          '$reachabilityReason.',
        );
        return const {};
      }
    }

    final properties = inputSchema?.properties;
    if (properties == null || properties.isEmpty) {
      return const {};
    }

    final mappings = <String, String>{};
    final seenHeaders = <String>{};
    final ignoredReason = _collectToolParameterHeaderMappings(
      toolName: tool.name,
      properties: properties,
      path: const [],
      mappings: mappings,
      seenHeaders: seenHeaders,
    );

    if (ignoredReason != null) {
      _logger.warn(ignoredReason);
      return const {};
    }

    return mappings;
  }

  String? _collectToolParameterHeaderMappings({
    required String toolName,
    required Map<String, JsonSchema> properties,
    required List<String> path,
    required Map<String, String> mappings,
    required Set<String> seenHeaders,
  }) {
    for (final entry in properties.entries) {
      final parameterPath = [...path, entry.key];
      final parameterName = _toolParameterHeaderParameterName(parameterPath);
      final propertyJson = entry.value.toJson();
      if (!propertyJson.containsKey('x-mcp-header')) {
        if (entry.value is JsonObject) {
          final childProperties = (entry.value as JsonObject).properties;
          if (childProperties != null && childProperties.isNotEmpty) {
            final ignoredReason = _collectToolParameterHeaderMappings(
              toolName: toolName,
              properties: childProperties,
              path: parameterPath,
              mappings: mappings,
              seenHeaders: seenHeaders,
            );
            if (ignoredReason != null) {
              return ignoredReason;
            }
          }
        }
        continue;
      }

      final rawHeader = propertyJson['x-mcp-header'];
      if (rawHeader is! String || rawHeader.isEmpty) {
        return 'Ignoring x-mcp-header mapping for tool "$toolName" parameter '
            '"$parameterName": value must be a non-empty string.';
      }

      if (!_isValidMcpHeaderNameSuffix(rawHeader)) {
        return 'Ignoring x-mcp-header mapping for tool "$toolName" parameter '
            '"$parameterName": "$rawHeader" is not a valid Mcp-Param suffix.';
      }

      final normalizedHeader = rawHeader.toLowerCase();
      if (!seenHeaders.add(normalizedHeader)) {
        return 'Ignoring x-mcp-header mappings for tool "$toolName": '
            '"$rawHeader" is not unique.';
      }

      if (!_isToolParameterHeaderPrimitive(entry.value)) {
        return 'Ignoring x-mcp-header mapping for tool "$toolName" parameter '
            '"$parameterName": only string, integer, and boolean schemas can '
            'be mirrored.';
      }

      mappings[_toolParameterHeaderSelector(parameterPath)] = rawHeader;
    }

    return null;
  }

  String _toolParameterHeaderSelector(List<String> path) {
    if (path.length == 1) {
      return path.single;
    }

    return '/${path.map(_escapeJsonPointerSegment).join('/')}';
  }

  String _toolParameterHeaderParameterName(List<String> path) {
    if (path.length == 1) {
      return path.single;
    }

    return _toolParameterHeaderSelector(path);
  }

  String _escapeJsonPointerSegment(String segment) {
    return segment.replaceAll('~', '~0').replaceAll('/', '~1');
  }

  bool _isValidMcpHeaderNameSuffix(String value) {
    return isValidMcpHeaderNameSuffix(value);
  }

  bool _isToolParameterHeaderPrimitive(JsonSchema schema) {
    return schema is JsonString ||
        schema is JsonInteger ||
        schema is JsonBoolean;
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
          tasks: ServerCapabilitiesTasks(
            list: true,
            cancel: true,
            requests: ServerCapabilitiesTasksRequests(
              tools: ServerCapabilitiesTasksTools(
                call: ServerCapabilitiesTasksToolsCall(),
              ),
            ),
          ),
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
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.tasksList,
        if (params != null) 'params': params,
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
        final task = await Future.value(
          _cancelTaskCallback!(request.cancelParams.taskId, extra),
        );
        if (task.taskId != request.cancelParams.taskId) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Cancelled task result has mismatched taskId",
          );
        }
        if (task.status != TaskStatus.cancelled) {
          throw McpError(
            ErrorCode.invalidParams.value,
            "Task cancellation callback must return a cancelled task",
          );
        }
        _taskOutputValidationsById.remove((extra.sessionId, task.taskId));
        return task;
      },
      (id, params, meta) => JsonRpcCancelTaskRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.tasksCancel,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    if (_getTaskCallback != null) {
      server.setRequestHandler<JsonRpcGetTaskRequest>(
        Method.tasksGet,
        (request, extra) async {
          final taskId = request.getParams.taskId;
          final task = await Future.value(_getTaskCallback!(taskId, extra));
          if (task.status == TaskStatus.failed ||
              task.status == TaskStatus.cancelled) {
            _taskOutputValidationsById.remove((extra.sessionId, taskId));
          }
          return task;
        },
        (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksGet,
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
          final taskKey = (extra.sessionId, taskId);
          final validationSnapshot = _taskOutputValidationsById[taskKey];
          final protocolVersion = _protocolVersionForRequest(
            request.meta,
            readServerProtocolVersion(server),
          );
          final result = await Future.value(
            _taskResultCallback!(taskId, extra),
          );
          final resultWithMeta = _withRelatedTaskMeta(result, taskId);
          if (validationSnapshot != null) {
            _validateToolOutputResult(
              resultWithMeta,
              validationSnapshot.validateOutput,
              validationSnapshot.toolName,
              protocolVersion,
            );
            // Terminal task results are immutable. Once the final result has
            // passed its captured contract, repeated retrieval needs no
            // registration state.
            _taskOutputValidationsById.remove(taskKey);
          }
          return _toolResultForProtocol(resultWithMeta, protocolVersion);
        },
        (id, params, meta) => JsonRpcTaskResultRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': id,
          'method': Method.tasksResult,
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
      (request, extra) async {
        final protocolVersion = request.meta?[McpMetaKey.protocolVersion];
        final isStatelessRequest = protocolVersion is String &&
            isStatelessProtocolVersion(protocolVersion);
        final includeLegacyTaskExecution = !isStatelessRequest;
        final tools = _registeredTools.values.where((t) => t.enabled).toList();
        if (isStatelessRequest) {
          tools.sort((a, b) => a.name.compareTo(b.name));
        }

        return ListToolsResult(
          tools: tools
              .map(
                (tool) => tool.toTool(
                  includeExecution: includeLegacyTaskExecution,
                  inputSchemaOverride: isStatelessRequest
                      ? _toolInputSchemaForStatelessList(tool)
                      : null,
                  protocolVersion:
                      protocolVersion is String ? protocolVersion : null,
                ),
              )
              .toList(),
        );
      },
      (id, params, meta) => JsonRpcListToolsRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsList,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    server.setRequestHandler<JsonRpcCallToolRequest>(
      Method.toolsCall,
      (request, extra) async {
        final capabilityError = _validateToolClientCapabilities(request);
        if (capabilityError != null) {
          throw capabilityError;
        }
        final callParams = request.callParams;
        final toolName = callParams.name;
        final toolArgs = callParams.arguments;
        final protocolVersion = _protocolVersionForToolCall(
          request,
          readServerProtocolVersion(server),
        );
        final isStatelessRequest = _isStateless2026Request(protocolVersion);
        final hasTaskAugmentation =
            !isStatelessRequest && request.isTaskAugmented;
        final advertisesTaskAugmentedToolCalls =
            server.getCapabilities().tasks?.requests?.tools?.call != null;
        // MCP 2025-11-25 requires receivers without the negotiated capability
        // to ignore task augmentation. Older frozen peers retain the SDK's
        // historical interpretation of a present task member.
        final isTaskRequest = hasTaskAugmentation &&
            (!_usesStableTaskNegotiation(protocolVersion) ||
                advertisesTaskAugmentedToolCalls);
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

        final taskSupport =
            registeredTool.execution?.taskSupport ?? 'forbidden';
        final isTaskHandler = registeredTool.callback is InterfaceToolCallback;

        if ((taskSupport == 'required' || taskSupport == 'optional') &&
            !isTaskHandler) {
          throw McpError(
            ErrorCode.internalError.value,
            "Tool '$toolName' has taskSupport '$taskSupport' but was not registered with registerToolTask",
          );
        }
        if (taskSupport == 'required' &&
            !isTaskRequest &&
            !isStatelessRequest) {
          throw McpError(
            ErrorCode.methodNotFound.value,
            "Tool '$toolName' requires task augmentation (taskSupport: 'required')",
          );
        }
        if (taskSupport == 'forbidden' && isTaskRequest) {
          throw McpError(
            _usesStableTaskNegotiation(protocolVersion)
                ? ErrorCode.methodNotFound.value
                : ErrorCode.invalidParams.value,
            "Tool '$toolName' does not support task augmentation (taskSupport: 'forbidden')",
          );
        }

        // Validate arguments against schema
        if (registeredTool.inputSchema != null) {
          try {
            registeredTool.inputSchema!.validate(toolArgs);
          } on JsonSchemaDefinitionException catch (error, stackTrace) {
            _logger.error(
              "Invalid input schema for tool '$toolName': "
              '$error\n$stackTrace',
            );
            if (!_usesModernToolValidationSemantics(protocolVersion)) {
              throw McpError(
                ErrorCode.invalidParams.value,
                "Invalid arguments for tool '$toolName': $error",
              );
            }
            throw McpError(
              ErrorCode.internalError.value,
              "Tool '$toolName' has an invalid or unsupported input schema.",
            );
          } on JsonSchemaValidationException catch (error) {
            final message = "Invalid arguments for tool '$toolName': $error";
            // A legacy task request cannot return its underlying tool result
            // until after a task has been accepted. Reject invalid input before
            // invoking createTask so accepted calls retain CreateTaskResult.
            if (!_usesModernToolValidationSemantics(protocolVersion) ||
                isTaskRequest) {
              throw McpError(
                ErrorCode.invalidParams.value,
                message,
              );
            }
            return _toolResultForProtocol(
              CallToolResult(
                content: [TextContent(text: message)],
                isError: true,
              ),
              protocolVersion,
            );
          }
        }

        final validateOutput = _compileToolOutputValidator(
          registeredTool._outputJsonSchema,
          toolName,
          protocolVersion,
        );

        try {
          dynamic result;
          if (taskSupport == 'required' || taskSupport == 'optional') {
            if (!isTaskRequest) {
              result = await _handleAutomaticTaskPolling(
                registeredTool,
                toolArgs,
                extra,
              );
            } else {
              final InterfaceToolCallback taskHandler =
                  registeredTool.callback as InterfaceToolCallback;
              final taskResult =
                  await taskHandler.handler.createTask(toolArgs, extra);
              if (validateOutput != null) {
                _taskOutputValidationsById[(
                  extra.sessionId,
                  taskResult.task.taskId
                )] = _TaskOutputValidationSnapshot(
                  toolName: toolName,
                  validateOutput: validateOutput,
                );
              }
              result = taskResult;
            }
          } else {
            // taskSupport is 'forbidden' or not specified
            final statelessCallback = registeredTool.statelessCallback;
            if (statelessCallback != null) {
              result = await statelessCallback(toolArgs, extra);
            } else {
              final callback = registeredTool.callback;
              if (callback is! FunctionToolCallback) {
                throw StateError("No callback found for tool '$toolName'");
              }
              result = await callback.function(toolArgs, extra);
            }
          }

          if (result is CallToolResult) {
            _validateToolOutputResult(
              result,
              validateOutput,
              toolName,
              protocolVersion,
            );
          }

          if (result is CreateTaskExtensionResult &&
              validateOutput != null &&
              _isStateless2026Request(protocolVersion)) {
            final taskValidator = _taskOutputValidator(
              validateOutput,
              toolName,
              protocolVersion,
            );
            writeServerTaskOutputValidator(
              server,
              extra.sessionId,
              result.task.taskId,
              taskValidator,
            );
            try {
              if (result.task.status == TaskStatus.completed &&
                  result.task.result != null) {
                taskValidator(result.task.result!);
              }
            } catch (_) {
              removeServerTaskOutputValidator(
                server,
                extra.sessionId,
                result.task.taskId,
              );
              rethrow;
            }
          }

          if (result is CallToolResult) {
            return _toolResultForProtocol(
              result,
              protocolVersion,
            );
          }

          return result;
        } catch (error, stackTrace) {
          _logger.error(
            "Error executing tool '$toolName': $error\n$stackTrace",
          );
          if (error is McpError) {
            rethrow; // Pass through McpErrors (like methodNotFound)
          }
          return const CallToolResult(
            content: [TextContent(text: 'Tool execution failed.')],
            isError: true,
          );
        }
      },
      (id, params, meta) => JsonRpcCallToolRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsCall,
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
        completions: ServerCapabilitiesCompletions(),
      ),
    );
    server.setRequestHandler<JsonRpcCompleteRequest>(
      Method.completionComplete,
      (request, extra) async => switch (request.completeParams.ref) {
        final ResourceReference r => _handleResourceCompletion(
            r,
            request.completeParams.argument,
            request.completeParams.context,
          ),
        final PromptReference p => _handlePromptCompletion(
            p,
            request.completeParams.argument,
            request.completeParams.context,
          ),
      },
      (id, params, meta) => JsonRpcCompleteRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.completionComplete,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );
    _completionHandlerInitialized = true;
  }

  Future<CompleteResult> _handlePromptCompletion(
    PromptReference ref,
    ArgumentCompletionInfo argInfo,
    CompletionContext? context,
  ) async {
    final prompt = _registeredPrompts[ref.name];
    if (prompt == null || !prompt.enabled) return _emptyCompletionResult();

    final argDef = prompt.argsSchemaDefinition?[argInfo.name];
    final completer = argDef?.completable?.def;
    if (completer == null) return _emptyCompletionResult();
    try {
      return _createCompletionResult(
        await completer._completeValue(argInfo.value, context),
      );
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
    CompletionContext? context,
  ) async {
    final templateEntry = _registeredResourceTemplates.entries.firstWhere(
      (e) => e.value.resourceTemplate.uriTemplate.toString() == ref.uri,
      orElse: () => throw McpError(
        ErrorCode.invalidParams.value,
        "Resource template URI '${ref.uri}' not found for completion",
      ),
    );
    if (!templateEntry.value.enabled) return _emptyCompletionResult();

    try {
      final completions =
          templateEntry.value.resourceTemplate._completeVariable(
        argInfo.name,
        argInfo.value,
        context,
      );
      if (completions == null) return _emptyCompletionResult();
      return _createCompletionResult(await completions);
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
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesList,
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
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesTemplatesList,
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
          return await Future.value(
            fixed.invokeReadCallback(uri, extra),
          );
        }
        for (final entry in _registeredResourceTemplates.values) {
          if (!entry.enabled) continue;
          final vars = entry.resourceTemplate.uriTemplate.match(uriString);
          if (vars != null) {
            return await Future.value(
              entry.invokeReadCallback(uri, vars, extra),
            );
          }
        }
        final protocolVersion = extra.meta?[McpMetaKey.protocolVersion];
        throw _resourceNotFoundErrorForProtocol(
          uriString,
          protocolVersion is String ? protocolVersion : null,
        );
      },
      (id, params, meta) => JsonRpcReadResourceRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesRead,
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
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.promptsList,
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
          final rawArgs = args ?? <String, dynamic>{};
          final parsedArgs = registered.argsSchemaDefinition == null
              ? rawArgs
              : _validatePromptArgs(
                  Map<String, dynamic>.from(rawArgs),
                  registered.argsSchemaDefinition!,
                );
          if (registered.callback != null) {
            return await Future.value(registered.callback!(parsedArgs, extra));
          } else {
            throw StateError("No callback found");
          }
        } catch (error, stackTrace) {
          _logger.error(
            "Error executing prompt '$name': $error\n$stackTrace",
          );
          if (error is McpError) rethrow;
          throw McpError(
            ErrorCode.internalError.value,
            "Failed to generate prompt '$name'.",
          );
        }
      },
      (id, params, meta) => JsonRpcGetPromptRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.promptsGet,
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
  /// [title] is an optional display title for UIs.
  /// [metadata] provides optional description and MIME type.
  /// [readCallback] is the function called when the resource is read.
  RegisteredResource registerResource(
    String name,
    String uri,
    ResourceMetadata? metadata,
    ReadResourceCallback readCallback, {
    String? title,
    Map<String, dynamic>? meta,
  }) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    final resource = _RegisteredResourceImpl(
      this,
      name: name,
      title: title,
      uri: uri,
      metadata: metadata,
      meta: meta,
      readCallback: readCallback,
    );
    _registeredResources[uri] = resource;
    _ensureResourceHandlersInitialized();
    sendResourceListChanged();
    return resource;
  }

  /// Registers an MCP 2026-07-28 resource that may request additional input.
  RegisteredResource registerStatelessResource(
    String name,
    String uri,
    ResourceMetadata? metadata,
    StatelessReadResourceCallback readCallback, {
    String? title,
    Map<String, dynamic>? meta,
  }) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    final resource = _RegisteredResourceImpl(
      this,
      name: name,
      title: title,
      uri: uri,
      metadata: metadata,
      meta: meta,
      statelessReadCallback: readCallback,
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
  /// [title] is an optional display title for UIs.
  /// [metadata] provides optional description and MIME type for resources matching this template.
  /// [readCallback] is the function called when a matching resource is read.
  RegisteredResourceTemplate registerResourceTemplate(
    String name,
    ResourceTemplateRegistration template,
    ResourceMetadata? metadata,
    ReadResourceTemplateCallback readCallback, {
    String? title,
    Map<String, dynamic>? meta,
  }) {
    if (_registeredResourceTemplates.containsKey(name)) {
      throw ArgumentError(
        "Resource template name '$name' already registered.",
      );
    }
    final resourceTemplate = _RegisteredResourceTemplateImpl(
      this,
      name: name,
      title: title,
      resourceTemplate: template,
      metadata: metadata,
      meta: meta,
      readCallback: readCallback,
    );
    _registeredResourceTemplates[name] = resourceTemplate;
    _ensureResourceHandlersInitialized();
    sendResourceListChanged();
    return resourceTemplate;
  }

  /// Registers an MCP 2026-07-28 resource template with multi-round reads.
  RegisteredResourceTemplate registerStatelessResourceTemplate(
    String name,
    ResourceTemplateRegistration template,
    ResourceMetadata? metadata,
    StatelessReadResourceTemplateCallback readCallback, {
    String? title,
    Map<String, dynamic>? meta,
  }) {
    if (_registeredResourceTemplates.containsKey(name)) {
      throw ArgumentError(
        "Resource template name '$name' already registered.",
      );
    }
    final resourceTemplate = _RegisteredResourceTemplateImpl(
      this,
      name: name,
      title: title,
      resourceTemplate: template,
      metadata: metadata,
      meta: meta,
      statelessReadCallback: readCallback,
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
  /// [inputSchema] defines the expected arguments. For normal tool calls,
  /// arguments that do not match it skip [callback] and, for MCP `2025-11-25`
  /// and newer, produce a [CallToolResult] with `isError: true`. Frozen MCP
  /// `2025-06-18` and earlier peers retain JSON-RPC `invalidParams`
  /// compatibility. Unknown tools and malformed `tools/call` requests remain
  /// JSON-RPC errors.
  /// [outputSchema] defines the initialization-era object-root result structure.
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

  /// Registers an MCP 2026-07-28 tool with stateless-only capabilities.
  ///
  /// Use this instead of [registerTool] when [callback] can return an
  /// [InputRequiredResult] or when the tool has a non-object [outputJsonSchema].
  /// A callback that always returns [CallToolResult] can continue to use
  /// [registerTool] when its output schema is object-rooted.
  ///
  /// Arguments that do not satisfy [inputSchema] skip [callback] and return a
  /// [CallToolResult] with `isError: true`. A successful [CallToolResult] that
  /// does not satisfy [outputSchema] or [outputJsonSchema] produces JSON-RPC
  /// `internalError` because it violates the server's advertised contract.
  RegisteredStatelessTool registerStatelessTool(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    JsonSchema? outputJsonSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    required StatelessToolFunction callback,
  }) {
    return _registerTool(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      outputJsonSchema: outputJsonSchema,
      annotations: annotations,
      meta: meta,
      execution: const ToolExecution(taskSupport: 'forbidden'),
      statelessCallback: callback,
    );
  }

  /// Internal registration method.
  _RegisteredToolImpl _registerTool(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    JsonSchema? outputJsonSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    ToolExecution? execution,
    ToolCallback? callback,
    StatelessToolFunction? statelessCallback,
  }) {
    if (callback == null && statelessCallback == null) {
      throw ArgumentError('A tool callback is required.');
    }
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
      outputJsonSchema:
          _resolveToolOutputJsonSchema(outputSchema, outputJsonSchema),
      annotations: annotations,
      meta: meta,
      execution: execution,
      callback: callback,
      statelessCallback: statelessCallback,
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

  /// Registers an MCP 2026-07-28 prompt that may request additional input.
  ///
  /// Use this instead of [registerPrompt] when [callback] can return an
  /// [InputRequiredResult].
  RegisteredPrompt registerStatelessPrompt(
    String name, {
    String? title,
    String? description,
    Map<String, PromptArgumentDefinition>? argsSchema,
    required StatelessPromptCallback callback,
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
    String? title,
    ImageContent? icon,
  }) {
    if (_registeredResources.containsKey(uri)) {
      throw ArgumentError("Resource URI '$uri' already registered.");
    }
    final resource = _RegisteredResourceImpl(
      this,
      name: name,
      title: title,
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
    String? title,
  }) {
    return registerResourceTemplate(
      name,
      templateRegistration,
      metadata,
      readCallback,
      title: title,
    );
  }

  /// Deprecated helper that registers a tool the client can invoke.
  ///
  /// Use [registerTool] with [ToolFunction]. The
  /// [inputSchemaProperties] and [outputSchemaProperties] parameters are
  /// deprecated compatibility shims for [toolInputSchema] and
  /// [toolOutputSchema].
  @Deprecated('Use registerTool instead')
  RegisteredTool tool(
    String name, {
    String? description,
    ToolInputSchema? toolInputSchema,
    ToolOutputSchema? toolOutputSchema,

    /// Deprecated schema-property map shim. Use [toolInputSchema].
    @Deprecated('Use toolInputSchema instead')
    Map<String, dynamic>? inputSchemaProperties,

    /// Deprecated schema-property map shim. Use [toolOutputSchema].
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
                    (key, value) =>
                        MapEntry(key, JsonSchema.fromJsonValue(value)),
                  ),
                )
              : null),
      outputJsonSchema: toolOutputSchema ??
          (outputSchemaProperties != null
              ? ToolOutputSchema(
                  properties: outputSchemaProperties.map(
                    (key, value) =>
                        MapEntry(key, JsonSchema.fromJsonValue(value)),
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

  /// Handles automatic task polling for task-backed tools invoked without
  /// legacy task augmentation.
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
