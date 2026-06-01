import 'dart:convert';

import '../shared/json_schema/json_schema.dart';

import 'content.dart';
import 'json_rpc.dart';
import 'validation.dart';

/// Legacy alias for [JsonObject] used as tool input schema.
typedef ToolInputSchema = JsonObject;

/// Legacy alias for object-root tool output schemas.
///
/// MCP 2026-07-28 allows [Tool.outputSchema] to be any JSON Schema. Use
/// [JsonSchema] directly when the output schema root is not an object.
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
      title: readOptionalString(json['title'], 'ToolAnnotations.title'),
      readOnlyHint: readOptionalBool(
            json['readOnlyHint'],
            'ToolAnnotations.readOnlyHint',
          ) ??
          false,
      destructiveHint: readOptionalBool(
            json['destructiveHint'],
            'ToolAnnotations.destructiveHint',
          ) ??
          true,
      idempotentHint: readOptionalBool(
            json['idempotentHint'],
            'ToolAnnotations.idempotentHint',
          ) ??
          false,
      openWorldHint: readOptionalBool(
            json['openWorldHint'],
            'ToolAnnotations.openWorldHint',
          ) ??
          true,
      priority: readUnitDouble(json['priority'], 'ToolAnnotations.priority'),
      audience: readOptionalAnnotationAudience(
        json['audience'],
        'ToolAnnotations.audience',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    validateUnitDouble(priority, 'ToolAnnotations.priority');
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
    final taskSupport =
        readOptionalString(json['taskSupport'], 'ToolExecution.taskSupport') ??
            'forbidden';
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

  /// JSON Schema defining the tool's structured output.
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
      _readRequiredJsonObject(json['inputSchema'], 'Tool.inputSchema'),
    );
    _validateObjectRootSchema(
      inputSchema,
      'Tool.inputSchema',
      formatException: true,
    );

    final outputSchemaJson =
        _readOptionalJsonObject(json['outputSchema'], 'Tool.outputSchema');
    final outputSchema =
        outputSchemaJson == null ? null : JsonSchema.fromJson(outputSchemaJson);

    return Tool(
      name: readRequiredString(json['name'], 'Tool.name'),
      title: readOptionalString(json['title'], 'Tool.title'),
      description: readOptionalString(json['description'], 'Tool.description'),
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: json['annotations'] != null
          ? ToolAnnotations.fromJson(
              readJsonObject(json['annotations'], 'Tool.annotations'),
            )
          : null,
      meta: readOptionalJsonObject(json['_meta'], 'Tool._meta'),
      execution: json['execution'] != null
          ? ToolExecution.fromJson(
              readJsonObject(json['execution'], 'Tool.execution'),
            )
          : null,
      icon: json['icon'] != null
          ? ImageContent.fromJson(readJsonObject(json['icon'], 'Tool.icon'))
          : null,
      icons: _readOptionalObjectList(
        json['icons'],
        'Tool.icons',
        McpIcon.fromJson,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    _validateObjectRootSchema(inputSchema, 'Tool.inputSchema');

    return {
      'name': name,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      'inputSchema': inputSchema.toJson(),
      if (outputSchema != null) 'outputSchema': outputSchema!.toJson(),
      if (annotations != null) 'annotations': annotations!.toJson(),
      if (meta != null) '_meta': readJsonObject(meta, 'Tool._meta'),
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
      cursor: readOptionalString(json['cursor'], 'ListToolsRequest.cursor'),
    );
  }

  Map<String, dynamic> toJson() => {
        if (cursor != null) 'cursor': cursor,
      };
}

@Deprecated('Use [ListToolsRequest] instead.')
typedef ListToolsRequestParams = ListToolsRequest;

/// The server's response to a [ListToolsRequest].
class ListToolsResult implements CacheableResultData {
  /// A list of tools.
  final List<Tool> tools;

  /// An opaque token for pagination.
  final String? nextCursor;

  /// How long, in milliseconds, the client may consider this result fresh.
  @override
  final int? ttlMs;

  /// Intended cache visibility: `public` or `private`.
  @override
  final String? cacheScope;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListToolsResult({
    required this.tools,
    this.nextCursor,
    this.ttlMs,
    this.cacheScope,
    this.meta,
  });

  factory ListToolsResult.fromJson(Map<String, dynamic> json) {
    final tools = json['tools'];
    if (tools is! List) {
      throw const FormatException('ListToolsResult.tools is required');
    }
    return ListToolsResult(
      tools: [
        for (var i = 0; i < tools.length; i++)
          Tool.fromJson(
            readJsonObject(tools[i], 'ListToolsResult.tools[$i]'),
          ),
      ],
      nextCursor:
          readOptionalString(json['nextCursor'], 'ListToolsResult.nextCursor'),
      ttlMs: readOptionalTtlMs(json['ttlMs'], 'ListToolsResult.ttlMs'),
      cacheScope: readOptionalCacheScope(
        json['cacheScope'],
        'ListToolsResult.cacheScope',
      ),
      meta: readOptionalJsonObject(json['_meta'], 'ListToolsResult._meta'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    validateTtlMs(ttlMs, 'ListToolsResult.ttlMs');
    validateCacheScope(cacheScope, 'ListToolsResult.cacheScope');
    return {
      'tools': tools.map((e) => e.toJson()).toList(),
      if (nextCursor != null) 'nextCursor': nextCursor,
      if (ttlMs != null) 'ttlMs': ttlMs,
      if (cacheScope != null) 'cacheScope': cacheScope,
      if (meta != null) '_meta': readJsonObject(meta, 'ListToolsResult._meta'),
    };
  }
}

@Deprecated('Use [CallToolRequest] instead.')
typedef CallToolRequestParams = CallToolRequest;

/// A request to call a tool.
class CallToolRequest {
  /// The name of the tool to call.
  final String name;

  /// The arguments to pass to the tool.
  final Map<String, dynamic> arguments;

  /// Client responses to MRTR input requests when retrying this tool call.
  final InputResponses? inputResponses;

  /// Opaque MRTR state returned by the server and echoed on retry.
  final String? requestState;

  const CallToolRequest({
    required this.name,
    this.arguments = const {},
    this.inputResponses,
    this.requestState,
  });

  factory CallToolRequest.fromJson(Map<String, dynamic> json) {
    final arguments = json['arguments'];
    return CallToolRequest(
      name: readRequiredString(json['name'], 'CallToolRequest.name'),
      arguments: arguments == null
          ? const {}
          : _readJsonObject(arguments, 'CallToolRequest.arguments'),
      inputResponses: InputResponse.mapFromJson(
        json['inputResponses'],
        'CallToolRequest.inputResponses',
      ),
      requestState: readOptionalString(
        json['requestState'],
        'CallToolRequest.requestState',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'arguments': readJsonObject(arguments, 'CallToolRequest.arguments'),
        if (inputResponses != null)
          'inputResponses': InputResponse.mapToJson(inputResponses!),
        if (requestState != null) 'requestState': requestState,
      };
}

/// The server's response to a [CallToolRequest].
class CallToolResult implements BaseResultData {
  /// The content of the result.
  final List<Content> content;

  /// Whether the tool call returned an error.
  final bool isError;

  /// Structured content returned by the tool.
  ///
  /// MCP 2026-07-28 allows any JSON value: object, array, string, number,
  /// boolean, or null.
  final Object? structuredContent;

  /// Whether [structuredContent] was explicitly present.
  ///
  /// This distinguishes an omitted field from an explicit JSON `null`.
  final bool hasStructuredContent;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  /// Additional properties merged into the result object.
  final Map<String, dynamic>? extra;

  const CallToolResult({
    required this.content,
    this.isError = false,
    this.structuredContent,
    bool? hasStructuredContent,
    this.meta,
    this.extra,
  }) : hasStructuredContent = hasStructuredContent ?? structuredContent != null;

  /// Creates a result from a list of content items.
  factory CallToolResult.fromContent(List<Content> content) {
    return CallToolResult(content: content);
  }

  /// Creates a result from arbitrary structured JSON data.
  ///
  /// Automatically populates [content] with a JSON-serialized version of
  /// [content] for backward compatibility with clients that do not support
  /// [structuredContent].
  factory CallToolResult.fromStructuredContent(Object? content) {
    return CallToolResult(
      content: [TextContent(text: jsonEncode(content))],
      structuredContent: content,
      hasStructuredContent: true,
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
      content: [
        for (var i = 0; i < content.length; i++)
          Content.fromJson(
            readJsonObject(content[i], 'CallToolResult.content[$i]'),
          ),
      ],
      isError:
          readOptionalBool(json['isError'], 'CallToolResult.isError') ?? false,
      structuredContent: json.containsKey('structuredContent')
          ? readJsonValue(
              json['structuredContent'],
              'CallToolResult.structuredContent',
            )
          : null,
      hasStructuredContent: json.containsKey('structuredContent'),
      meta: readOptionalJsonObject(json['_meta'], 'CallToolResult._meta'),
      extra:
          extra.isEmpty ? null : readJsonObject(extra, 'CallToolResult.extra'),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'content': content.map((e) => e.toJson()).toList(),
        if (isError) 'isError': isError,
        if (hasStructuredContent)
          'structuredContent': readJsonValue(
            structuredContent,
            'CallToolResult.structuredContent',
          ),
        if (meta != null) '_meta': readJsonObject(meta, 'CallToolResult._meta'),
        if (extra != null) ...readJsonObject(extra, 'CallToolResult.extra'),
      };
}

/// Notification from server indicating the list of available tools has changed.
class JsonRpcToolListChangedNotification extends JsonRpcNotification {
  const JsonRpcToolListChangedNotification({super.meta})
      : super(method: Method.notificationsToolsListChanged);

  factory JsonRpcToolListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      JsonRpcToolListChangedNotification(meta: extractRequestMeta(json));
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

Map<String, dynamic> _readRequiredJsonObject(Object? value, String field) {
  if (value == null) {
    throw FormatException('$field is required');
  }
  return _readJsonObject(value, field);
}

Map<String, dynamic>? _readOptionalJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return _readJsonObject(value, field);
}

List<T>? _readOptionalObjectList<T>(
  Object? value,
  String field,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw FormatException('$field must be a list of JSON objects');
  }
  return [
    for (var i = 0; i < value.length; i++)
      fromJson(_readJsonObject(value[i], '$field[$i]')),
  ];
}

Map<String, dynamic> _readJsonObject(Object? value, String field) {
  return readJsonObject(value, field);
}
