import 'dart:convert';
import '../types.dart';

/// Describes the input schema for a tool, based on JSON Schema.
class ToolInputSchema {
  /// Must be "object".
  final String type = "object";

  /// JSON Schema properties definition.
  final Map<String, dynamic>? properties;

  /// List of required property names.
  final List<String>? required;

  const ToolInputSchema({
    this.properties,
    this.required,
  });

  factory ToolInputSchema.fromJson(Map<String, dynamic> json) {
    return ToolInputSchema(
      properties: json['properties'] as Map<String, dynamic>?,
      required: (json['required'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (properties != null) 'properties': properties,
        if (required != null && required!.isNotEmpty) 'required': required,
      };
}

/// Describes the output schema for a tool, based on JSON Schema.
class ToolOutputSchema {
  /// Must be "object".
  final String type = "object";

  /// JSON Schema properties definition.
  final Map<String, dynamic>? properties;

  /// List of required property names.
  final List<String>? required;

  const ToolOutputSchema({
    this.properties,
    this.required,
  });

  factory ToolOutputSchema.fromJson(Map<String, dynamic> json) {
    return ToolOutputSchema(
      properties: json['properties'] as Map<String, dynamic>?,
      required: (json['required'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (properties != null) 'properties': properties,
        if (required != null && required!.isNotEmpty) 'required': required,
      };
}

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

/// Definition for a tool offered by the server.
class Tool {
  /// The name of the tool.
  final String name;

  /// A human-readable description of the tool.
  final String? description;

  /// JSON Schema defining the tool's input parameters.
  final ToolInputSchema inputSchema;

  /// JSON Schema defining the tool's output parameters.
  final ToolOutputSchema? outputSchema;

  /// Optional additional properties describing the tool.
  final ToolAnnotations? annotations;

  /// Optional icon for the tool.
  final ImageContent? icon;

  const Tool({
    required this.name,
    this.description,
    required this.inputSchema,
    this.outputSchema,
    this.annotations,
    this.icon,
  });

  factory Tool.fromJson(Map<String, dynamic> json) {
    return Tool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: ToolInputSchema.fromJson(
        json['inputSchema'] as Map<String, dynamic>,
      ),
      outputSchema: json['outputSchema'] != null
          ? ToolOutputSchema.fromJson(
              json['outputSchema'] as Map<String, dynamic>,
            )
          : null,
      annotations: json['annotation'] != null
          ? ToolAnnotations.fromJson(json['annotation'] as Map<String, dynamic>)
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
        if (annotations != null) 'annotation': annotations!.toJson(),
        if (icon != null) 'icon': icon!.toJson(),
      };
}

/// Parameters for the `tools/list` request. Includes pagination.
class ListToolsRequestParams {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListToolsRequestParams({this.cursor});

  factory ListToolsRequestParams.fromJson(Map<String, dynamic> json) =>
      ListToolsRequestParams(cursor: json['cursor'] as String?);

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available tools.
class JsonRpcListToolsRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListToolsRequestParams listParams;

  JsonRpcListToolsRequest({
    required super.id,
    ListToolsRequestParams? params,
    super.meta,
  })  : listParams = params ?? const ListToolsRequestParams(),
        super(method: Method.toolsList, params: params?.toJson());

  factory JsonRpcListToolsRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListToolsRequest(
      id: json['id'],
      params:
          paramsMap == null ? null : ListToolsRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `tools/list` request.
class ListToolsResult implements BaseResultData {
  /// The list of tools found.
  final List<Tool> tools;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListToolsResult({required this.tools, this.nextCursor, this.meta});

  factory ListToolsResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListToolsResult(
      tools: (json['tools'] as List<dynamic>?)
              ?.map((t) => Tool.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'tools': tools.map((t) => t.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for the `tools/call` request.
class CallToolRequestParams {
  /// The name of the tool to call.
  final String name;

  /// The arguments for the tool call, matching its `inputSchema`.
  final Map<String, dynamic>? arguments;

  const CallToolRequestParams({required this.name, this.arguments});

  factory CallToolRequestParams.fromJson(Map<String, dynamic> json) =>
      CallToolRequestParams(
        name: json['name'] as String,
        arguments: json['arguments'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (arguments != null) 'arguments': arguments,
      };
}

/// Request sent from client to invoke a tool provided by the server.
class JsonRpcCallToolRequest extends JsonRpcRequest {
  /// The call parameters.
  final CallToolRequestParams callParams;

  /// Optional task creation parameters for task-augmented requests.
  final TaskCreationParams? taskParams;

  JsonRpcCallToolRequest({
    required super.id,
    required this.callParams,
    this.taskParams,
    super.meta,
  }) : super(
          method: Method.toolsCall,
          params: {
            ...callParams.toJson(),
            if (taskParams != null) 'task': taskParams.toJson(),
          },
        );

  factory JsonRpcCallToolRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for call tool request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    final taskMap = paramsMap['task'] as Map<String, dynamic>?;

    return JsonRpcCallToolRequest(
      id: json['id'],
      callParams: CallToolRequestParams.fromJson(paramsMap),
      taskParams: taskMap != null ? TaskCreationParams.fromJson(taskMap) : null,
      meta: meta,
    );
  }

  /// Whether this is a task-augmented request.
  bool get isTaskAugmented => taskParams != null;
}

/// Result data for a successful `tools/call` request.
class CallToolResult implements BaseResultData {
  /// The content returned by the tool.
  final List<Content> content;

  /// The structured content returned by the tool.
  final Map<String, dynamic> structuredContent;

  /// Indicates if the tool call resulted in an error condition. Defaults to false.
  final bool? isError;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  @Deprecated(
      'This constructor is replaced by the fromContent factory constructor and may be removed in a future version.')
  CallToolResult({required this.content, this.isError, this.meta})
      : structuredContent = {};

  CallToolResult.fromContent({required this.content, this.isError, this.meta})
      : structuredContent = {};

  CallToolResult.fromStructuredContent(
      {required this.structuredContent,
      List<Content>? unstructuredFallback,
      this.meta})
      : content = unstructuredFallback ?? [],
        isError = null;

  factory CallToolResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    if (json.containsKey('toolResult')) {
      final toolResult = json['toolResult'];
      final bool isErr = json['isError'] as bool? ?? false;
      List<Content> mappedContent = (toolResult is String)
          ? [TextContent(text: toolResult)]
          : [TextContent(text: jsonEncode(toolResult))];
      return CallToolResult.fromContent(
          content: mappedContent, isError: isErr, meta: meta);
    } else {
      // Structured?
      if (json.containsKey('structuredContent')) {
        return CallToolResult.fromStructuredContent(
          structuredContent: json['structuredContent'] as Map<String, dynamic>,
          unstructuredFallback: (json['content'] as List<dynamic>?)
              ?.map((c) => Content.fromJson(c as Map<String, dynamic>))
              .toList(),
          meta: meta,
        );
      } else {
        // Unstructured
        return CallToolResult.fromContent(
          content: (json['content'] as List<dynamic>?)
                  ?.map((c) => Content.fromJson(c as Map<String, dynamic>))
                  .toList() ??
              [],
          isError: json['isError'] as bool? ?? false,
          meta: meta,
        );
      }
    }
  }

  @override
  Map<String, dynamic> toJson() {
    // Create the map to return
    final Map<String, dynamic> result = {};

    // Content may optionally be included even if structured based on the unstructuredCompatibility flag.
    result['content'] = content.map((c) => c.toJson()).toList();
    result['meta'] = meta;

    // Structured or unstructured?
    // Error can only be included if unstructured.
    if (structuredContent.isNotEmpty) {
      // Structured?
      result['structuredContent'] = structuredContent;
    } else {
      // Unstructured
      if (isError == true) result['isError'] = true;
    }
    return result;
  }
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
