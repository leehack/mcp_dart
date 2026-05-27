import 'dart:convert';

import '../shared/json_schema/json_schema.dart';

import 'content.dart';
import 'json_rpc.dart';

/// Legacy alias for [JsonObject] used as tool input schema.
typedef ToolInputSchema = JsonObject;

/// Legacy alias for [JsonObject] used as tool output schema.
typedef ToolOutputSchema = JsonObject;

/// Additional properties describing a Tool to clients.
///
/// NOTE: all properties in ToolAnnotations are **hints**.
/// They are not guaranteed to provide a faithful description of
/// tool behavior (including descriptive properties like `title`).
///
/// Clients should never make tool use decisions based on ToolAnnotations
/// received from untrusted servers.
class ToolAnnotations {
  /// A human-readable title for the tool.
  final String? title;

  /// If true, the tool does not modify its environment.
  /// default: false
  final bool readOnlyHint;

  /// If true, the tool may perform destructive updates to its environment.
  /// If false, the tool performs only additive updates.
  /// (This property is meaningful only when `readOnlyHint == false`)
  /// default: true
  final bool destructiveHint;

  /// If true, calling the tool repeatedly with the same arguments
  /// will have no additional effect on the its environment.
  /// (This property is meaningful only when `readOnlyHint == false`)
  /// default: false
  final bool idempotentHint;

  /// If true, this tool may interact with an "open world" of external
  /// entities. If false, the tool's domain of interaction is closed.
  /// For example, the world of a web search tool is open, whereas that
  /// of a memory tool is not.
  /// Default: true
  final bool openWorldHint;

  /// The priority of the tool (0.0 to 1.0).
  @Deprecated(
    'MCP 2025-11-25 ToolAnnotations do not include priority; this is parsed only for legacy compatibility.',
  )
  final double? priority;

  /// The intended audience for the tool (e.g., `["user", "assistant"]`).
  @Deprecated(
    'MCP 2025-11-25 ToolAnnotations do not include audience; this is parsed only for legacy compatibility.',
  )
  final List<String>? audience;

  const ToolAnnotations({
    this.title,
    this.readOnlyHint = false,
    this.destructiveHint = true,
    this.idempotentHint = false,
    this.openWorldHint = true,
    this.priority,
    this.audience,
  }) : assert(
          priority == null || (priority >= 0 && priority <= 1),
          'priority must be between 0 and 1',
        );

  factory ToolAnnotations.fromJson(Map<String, dynamic> json) {
    return ToolAnnotations(
      title: json['title'] as String?,
      readOnlyHint: json['readOnlyHint'] as bool? ?? false,
      destructiveHint: json['destructiveHint'] as bool? ?? true,
      idempotentHint: json['idempotentHint'] as bool? ?? false,
      openWorldHint: json['openWorldHint'] as bool? ?? true,
      priority: _readUnitDouble(json['priority'], 'ToolAnnotations.priority'),
      audience: (json['audience'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    _validateUnitDouble(priority, 'ToolAnnotations.priority');
    return {
      if (title != null) 'title': title,
      'readOnlyHint': readOnlyHint,
      'destructiveHint': destructiveHint,
      'idempotentHint': idempotentHint,
      'openWorldHint': openWorldHint,
    };
  }
}

/// Describes how the tool should be executed.
class ToolExecution {
  static const Set<String> allowedTaskSupportValues = {
    'forbidden',
    'optional',
    'required',
  };

  /// Describes how the tool supports task augmentation.
  ///
  /// * `forbidden`: The tool does not support tasks.
  /// * `optional`: The tool supports tasks, but can also be called directly.
  /// * `required`: The tool must be called as a task.
  final String taskSupport;

  const ToolExecution({this.taskSupport = 'forbidden'});

  factory ToolExecution.fromJson(Map<String, dynamic> json) {
    final taskSupport = json['taskSupport'] as String? ?? 'forbidden';
    if (!allowedTaskSupportValues.contains(taskSupport)) {
      throw FormatException(
        "Invalid tool execution taskSupport '$taskSupport'. Expected one of: ${allowedTaskSupportValues.join(', ')}",
      );
    }
    return ToolExecution(taskSupport: taskSupport);
  }

  Map<String, dynamic> toJson() {
    if (!allowedTaskSupportValues.contains(taskSupport)) {
      throw ArgumentError.value(
        taskSupport,
        'taskSupport',
        "Expected one of: ${allowedTaskSupportValues.join(', ')}",
      );
    }
    return {'taskSupport': taskSupport};
  }
}

/// Definition for a tool that the client can call.
class Tool {
  /// The name of the tool.
  final String name;

  /// A human-readable title for the tool.
  final String? title;

  /// A human-readable description of the tool.
  final String? description;

  /// JSON Schema defining the tool's input parameters.
  final JsonSchema inputSchema;

  /// JSON Schema defining the tool's output parameters.
  final JsonSchema? outputSchema;

  /// Optional additional properties describing the tool.
  final ToolAnnotations? annotations;

  /// Optional metadata for the tool.
  final Map<String, dynamic>? meta;

  /// Optional tool execution configuration.
  final ToolExecution? execution;

  /// Optional icon content.
  @Deprecated(
    'MCP 2025-11-25 uses icons; singular icon is parsed only for legacy compatibility and is not serialized.',
  )
  final ImageContent? icon;

  /// Optional set of icons.
  final List<McpIcon>? icons;

  const Tool({
    required this.name,
    this.title,
    this.description,
    required this.inputSchema,
    this.outputSchema,
    this.annotations,
    this.meta,
    this.execution,
    this.icon,
    this.icons,
  });

  factory Tool.fromJson(Map<String, dynamic> json) {
    final inputSchema = JsonSchema.fromJson(
      json['inputSchema'] as Map<String, dynamic>,
    );
    _validateObjectRootSchema(
      inputSchema,
      'Tool.inputSchema',
      formatException: true,
    );

    final outputSchema = json['outputSchema'] == null
        ? null
        : JsonSchema.fromJson(json['outputSchema'] as Map<String, dynamic>);
    if (outputSchema != null) {
      _validateObjectRootSchema(
        outputSchema,
        'Tool.outputSchema',
        formatException: true,
      );
    }

    return Tool(
      name: json['name'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: json['annotations'] != null
          ? ToolAnnotations.fromJson(
              json['annotations'] as Map<String, dynamic>,
            )
          : null,
      meta: json['_meta'] as Map<String, dynamic>?,
      execution: json['execution'] != null
          ? ToolExecution.fromJson(json['execution'] as Map<String, dynamic>)
          : null,
      icon: json['icon'] != null
          ? ImageContent.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      icons: (json['icons'] as List<dynamic>?)
          ?.map((e) => McpIcon.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    _validateObjectRootSchema(inputSchema, 'Tool.inputSchema');
    if (outputSchema != null) {
      _validateObjectRootSchema(outputSchema!, 'Tool.outputSchema');
    }

    return {
      'name': name,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      'inputSchema': inputSchema.toJson(),
      if (outputSchema != null) 'outputSchema': outputSchema!.toJson(),
      if (annotations != null) 'annotations': annotations!.toJson(),
      if (meta != null) '_meta': meta,
      if (execution != null) 'execution': execution!.toJson(),
      if (icons != null) 'icons': icons!.map((icon) => icon.toJson()).toList(),
    };
  }
}

/// A request to list available tools.
class ListToolsRequest {
  /// An opaque token for pagination.
  final String? cursor;

  const ListToolsRequest({this.cursor});

  factory ListToolsRequest.fromJson(Map<String, dynamic> json) {
    return ListToolsRequest(
      cursor: json['cursor'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (cursor != null) 'cursor': cursor,
      };
}

@Deprecated('Use [ListToolsRequest] instead.')
typedef ListToolsRequestParams = ListToolsRequest;

/// The server's response to a [ListToolsRequest].
class ListToolsResult implements BaseResultData {
  /// A list of tools.
  final List<Tool> tools;

  /// An opaque token for pagination.
  final String? nextCursor;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListToolsResult({
    required this.tools,
    this.nextCursor,
    this.meta,
  });

  factory ListToolsResult.fromJson(Map<String, dynamic> json) {
    final tools = json['tools'];
    if (tools is! List) {
      throw const FormatException('ListToolsResult.tools is required');
    }
    return ListToolsResult(
      tools:
          tools.map((e) => Tool.fromJson(e as Map<String, dynamic>)).toList(),
      nextCursor: json['nextCursor'] as String?,
      meta: json['_meta'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'tools': tools.map((e) => e.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
        if (meta != null) '_meta': meta,
      };
}

@Deprecated('Use [CallToolRequest] instead.')
typedef CallToolRequestParams = CallToolRequest;

/// A request to call a tool.
class CallToolRequest {
  /// The name of the tool to call.
  final String name;

  /// The arguments to pass to the tool.
  final Map<String, dynamic> arguments;

  const CallToolRequest({
    required this.name,
    this.arguments = const {},
  });

  factory CallToolRequest.fromJson(Map<String, dynamic> json) {
    final arguments = json['arguments'];
    return CallToolRequest(
      name: json['name'] as String,
      arguments: arguments == null
          ? const {}
          : (arguments as Map).cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'arguments': arguments,
      };
}

/// The server's response to a [CallToolRequest].
class CallToolResult implements BaseResultData {
  /// The content of the result.
  final List<Content> content;

  /// Whether the tool call returned an error.
  final bool isError;

  /// Structured content returned by the tool.
  final Map<String, dynamic>? structuredContent;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  /// Additional properties merged into the result object.
  final Map<String, dynamic>? extra;

  const CallToolResult({
    required this.content,
    this.isError = false,
    this.structuredContent,
    this.meta,
    this.extra,
  });

  /// Creates a result from a list of content items.
  factory CallToolResult.fromContent(List<Content> content) {
    return CallToolResult(content: content);
  }

  /// Creates a result from arbitrary structured data.
  ///
  /// Automatically populates [content] with a JSON-serialized version of
  /// [content] for backward compatibility with clients that do not support
  /// [structuredContent].
  factory CallToolResult.fromStructuredContent(Map<String, dynamic> content) {
    return CallToolResult(
      content: [TextContent(text: jsonEncode(content))],
      structuredContent: content,
    );
  }

  factory CallToolResult.fromJson(Map<String, dynamic> json) {
    final knownKeys = {'content', 'isError', '_meta', 'structuredContent'};
    final extra = Map<String, dynamic>.from(json)
      ..removeWhere((key, value) => knownKeys.contains(key));
    final content = json['content'];
    if (content is! List) {
      throw const FormatException('CallToolResult.content is required');
    }

    return CallToolResult(
      content: content
          .map((e) => Content.fromJson(e as Map<String, dynamic>))
          .toList(),
      isError: json['isError'] as bool? ?? false,
      structuredContent: json['structuredContent'] as Map<String, dynamic>?,
      meta: json['_meta'] as Map<String, dynamic>?,
      extra: extra.isEmpty ? null : extra,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'content': content.map((e) => e.toJson()).toList(),
        if (isError) 'isError': isError,
        if (structuredContent != null) 'structuredContent': structuredContent,
        if (meta != null) '_meta': meta,
        ...?extra,
      };
}

/// Notification from server indicating the list of available tools has changed.
class JsonRpcToolListChangedNotification extends JsonRpcNotification {
  const JsonRpcToolListChangedNotification()
      : super(method: Method.notificationsToolsListChanged);

  factory JsonRpcToolListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcToolListChangedNotification();
}

void _validateObjectRootSchema(
  JsonSchema schema,
  String field, {
  bool formatException = false,
}) {
  final json = schema.toJson();
  if (json['type'] != 'object') {
    if (formatException) {
      throw FormatException('$field must have root type "object"');
    }
    throw ArgumentError.value(
      json,
      field,
      'MCP tool schemas must have root type "object"',
    );
  }
}

double? _readUnitDouble(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw FormatException('$field must be a number between 0 and 1');
  }
  final result = value.toDouble();
  if (result < 0 || result > 1) {
    throw FormatException('$field must be between 0 and 1');
  }
  return result;
}

void _validateUnitDouble(double? value, String field) {
  if (value == null) {
    return;
  }
  if (value < 0 || value > 1) {
    throw ArgumentError.value(value, field, 'must be between 0 and 1');
  }
}
