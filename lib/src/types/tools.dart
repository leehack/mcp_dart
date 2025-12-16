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
  final String title;

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
  final double? priority;

  /// The intended audience for the tool (e.g., `["user", "assistant"]`).
  final List<String>? audience;

  const ToolAnnotations({
    required this.title,
    this.readOnlyHint = false,
    this.destructiveHint = true,
    this.idempotentHint = false,
    this.openWorldHint = true,
    this.priority,
    this.audience,
  });

  factory ToolAnnotations.fromJson(Map<String, dynamic> json) {
    return ToolAnnotations(
      title: json['title'] as String,
      readOnlyHint: json['readOnlyHint'] as bool? ?? false,
      destructiveHint: json['destructiveHint'] as bool? ?? true,
      idempotentHint: json['idempotentHint'] as bool? ?? false,
      openWorldHint: json['openWorldHint'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toDouble(),
      audience: (json['audience'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'readOnlyHint': readOnlyHint,
        'destructiveHint': destructiveHint,
        'idempotentHint': idempotentHint,
        'openWorldHint': openWorldHint,
        if (priority != null) 'priority': priority,
        if (audience != null) 'audience': audience,
      };
}

/// Describes how the tool should be executed.
class ToolExecution {
  /// Describes how the tool supports task augmentation.
  ///
  /// * `forbidden`: The tool does not support tasks.
  /// * `optional`: The tool supports tasks, but can also be called directly.
  /// * `required`: The tool must be called as a task.
  final String taskSupport;

  const ToolExecution({this.taskSupport = 'forbidden'});

  factory ToolExecution.fromJson(Map<String, dynamic> json) {
    return ToolExecution(
      taskSupport: json['taskSupport'] as String? ?? 'forbidden',
    );
  }

  Map<String, dynamic> toJson() => {
        'taskSupport': taskSupport,
      };
}

/// Definition for a tool that the client can call.
class Tool {
  /// The name of the tool.
  final String name;

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
  final ImageContent? icon;

  const Tool({
    required this.name,
    this.description,
    required this.inputSchema,
    this.outputSchema,
    this.annotations,
    this.meta,
    this.execution,
    this.icon,
  });

  factory Tool.fromJson(Map<String, dynamic> json) {
    return Tool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: JsonSchema.fromJson(
        json['inputSchema'] as Map<String, dynamic>,
      ),
      outputSchema: json['outputSchema'] != null
          ? JsonSchema.fromJson(json['outputSchema'] as Map<String, dynamic>)
          : null,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        'inputSchema': inputSchema.toJson(),
        if (outputSchema != null) 'outputSchema': outputSchema!.toJson(),
        if (annotations != null) 'annotations': annotations!.toJson(),
        if (meta != null) '_meta': meta,
        if (execution != null) 'execution': execution!.toJson(),
        if (icon != null) 'icon': icon!.toJson(),
      };
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
    return ListToolsResult(
      tools: (json['tools'] as List<dynamic>)
          .map((e) => Tool.fromJson(e as Map<String, dynamic>))
          .toList(),
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
    return CallToolRequest(
      name: json['name'] as String,
      arguments: json['arguments'] as Map<String, dynamic>? ?? const {},
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

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  /// Additional properties merged into the result object.
  final Map<String, dynamic>? extra;

  const CallToolResult({
    required this.content,
    this.isError = false,
    this.meta,
    this.extra,
  });

  /// Creates a result from a list of content items.
  factory CallToolResult.fromContent(List<Content> content) {
    return CallToolResult(content: content);
  }

  /// Creates a result from arbitrary structured data.
  factory CallToolResult.fromStructuredContent(Map<String, dynamic> content) {
    return CallToolResult(
      content: [],
      extra: content,
    );
  }

  factory CallToolResult.fromJson(Map<String, dynamic> json) {
    final knownKeys = {'content', 'isError', '_meta'};
    final extra = Map<String, dynamic>.from(json)
      ..removeWhere((key, value) => knownKeys.contains(key));

    return CallToolResult(
      content: (json['content'] as List<dynamic>?)
              ?.map((e) => Content.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isError: json['isError'] as bool? ?? false,
      meta: json['_meta'] as Map<String, dynamic>?,
      extra: extra.isEmpty ? null : extra,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'content': content.map((e) => e.toJson()).toList(),
        if (isError) 'isError': isError,
        if (meta != null) '_meta': meta,
        ...?extra,
      };

  Map<String, dynamic> get structuredContent => toJson();
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
