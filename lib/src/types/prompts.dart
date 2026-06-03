import '../types.dart';
import 'json_rpc.dart';
import 'validation.dart';

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  expectJsonRpcMethod(json, expected, context);
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
    throw FormatException('$field must be a list of objects');
  }
  return [
    for (var i = 0; i < value.length; i++)
      fromJson(readJsonObject(value[i], '$field[$i]')),
  ];
}

/// Describes an argument accepted by a prompt template.
class PromptArgument {
  /// The name of the argument.
  final String name;

  /// A human-readable title of the argument.
  final String? title;

  /// A human-readable description of the argument.
  final String? description;

  /// Whether this argument must be provided.
  final bool? required;

  const PromptArgument({
    required this.name,
    this.title,
    this.description,
    this.required,
  });

  factory PromptArgument.fromJson(Map<String, dynamic> json) {
    return PromptArgument(
      name: readRequiredString(json['name'], 'PromptArgument.name'),
      title: readOptionalString(json['title'], 'PromptArgument.title'),
      description: readOptionalString(
        json['description'],
        'PromptArgument.description',
      ),
      required: readOptionalBool(json['required'], 'PromptArgument.required'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (required != null) 'required': required,
      };
}

/// A prompt or prompt template offered by the server.
class Prompt {
  /// The name of the prompt or template.
  final String name;

  /// A human-readable title of the prompt.
  final String? title;

  /// An optional description of what the prompt provides.
  final String? description;

  /// A list of arguments for templating the prompt.
  final List<PromptArgument>? arguments;

  /// Optional icon for the prompt.
  @Deprecated(
    'MCP 2025-11-25 uses icons; singular icon is parsed only for legacy compatibility and is not serialized.',
  )
  final ImageContent? icon;

  /// Optional set of icons for the prompt.
  final List<McpIcon>? icons;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const Prompt({
    required this.name,
    this.title,
    this.description,
    this.arguments,
    this.icon,
    this.icons,
    this.meta,
  });

  factory Prompt.fromJson(Map<String, dynamic> json) {
    return Prompt(
      name: readRequiredString(json['name'], 'Prompt.name'),
      title: readOptionalString(json['title'], 'Prompt.title'),
      description:
          readOptionalString(json['description'], 'Prompt.description'),
      arguments: _readOptionalObjectList(
        json['arguments'],
        'Prompt.arguments',
        PromptArgument.fromJson,
      ),
      icon: json['icon'] != null
          ? ImageContent.fromJson(readJsonObject(json['icon'], 'Prompt.icon'))
          : null,
      icons: _readOptionalObjectList(
        json['icons'],
        'Prompt.icons',
        McpIcon.fromJson,
      ),
      meta: readOptionalJsonObject(json['_meta'], 'Prompt._meta'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (arguments != null)
          'arguments': arguments!.map((a) => a.toJson()).toList(),
        if (icons != null)
          'icons': icons!.map((icon) => icon.toJson()).toList(),
        if (meta != null) '_meta': readJsonObject(meta, 'Prompt._meta'),
      };
}

/// Parameters for the `prompts/list` request. Includes pagination.
class ListPromptsRequest {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListPromptsRequest({this.cursor});

  factory ListPromptsRequest.fromJson(Map<String, dynamic> json) =>
      ListPromptsRequest(
        cursor: readOptionalString(json['cursor'], 'ListPromptsRequest.cursor'),
      );

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available prompts and templates.
class JsonRpcListPromptsRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListPromptsRequest listParams;

  JsonRpcListPromptsRequest({
    required super.id,
    ListPromptsRequest? params,
    super.meta,
  })  : listParams = params ?? const ListPromptsRequest(),
        super(method: Method.promptsList, params: params?.toJson());

  factory JsonRpcListPromptsRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.promptsList,
      'JsonRpcListPromptsRequest',
    );
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcListPromptsRequest.params',
    );
    final meta = extractRequestMeta(json);
    return JsonRpcListPromptsRequest(
      id: parseRequestId(json['id']),
      params: paramsMap == null ? null : ListPromptsRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `prompts/list` request.
class ListPromptsResult implements CacheableResultData {
  /// The list of prompts/templates found.
  final List<Prompt> prompts;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  /// How long, in milliseconds, the client may consider this result fresh.
  @override
  final int? ttlMs;

  /// Intended cache visibility: `public` or `private`.
  @override
  final String? cacheScope;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListPromptsResult({
    required this.prompts,
    this.nextCursor,
    this.ttlMs,
    this.cacheScope,
    this.meta,
  });

  factory ListPromptsResult.fromJson(Map<String, dynamic> json) {
    final meta =
        readOptionalJsonObject(json['_meta'], 'ListPromptsResult._meta');
    final prompts = json['prompts'];
    if (prompts is! List) {
      throw const FormatException('ListPromptsResult.prompts is required');
    }
    return ListPromptsResult(
      prompts: prompts
          .map(
            (p) => Prompt.fromJson(
              readJsonObject(p, 'ListPromptsResult.prompts items'),
            ),
          )
          .toList(),
      nextCursor: readOptionalString(
        json['nextCursor'],
        'ListPromptsResult.nextCursor',
      ),
      ttlMs: readOptionalTtlMs(json['ttlMs'], 'ListPromptsResult.ttlMs'),
      cacheScope: readOptionalCacheScope(
        json['cacheScope'],
        'ListPromptsResult.cacheScope',
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    validateTtlMs(ttlMs, 'ListPromptsResult.ttlMs');
    validateCacheScope(cacheScope, 'ListPromptsResult.cacheScope');
    return {
      'prompts': prompts.map((p) => p.toJson()).toList(),
      if (nextCursor != null) 'nextCursor': nextCursor,
      if (ttlMs != null) 'ttlMs': ttlMs,
      if (cacheScope != null) 'cacheScope': cacheScope,
      if (meta != null)
        '_meta': readJsonObject(meta, 'ListPromptsResult._meta'),
    };
  }
}

/// Parameters for the `prompts/get` request.
class GetPromptRequest {
  /// The name of the prompt or template to retrieve.
  final String name;

  /// Arguments to use for templating the prompt.
  final Map<String, String>? arguments;

  /// Client responses to MRTR input requests when retrying this prompt request.
  final InputResponses? inputResponses;

  /// Opaque MRTR state returned by the server and echoed on retry.
  final String? requestState;

  const GetPromptRequest({
    required this.name,
    this.arguments,
    this.inputResponses,
    this.requestState,
  });

  factory GetPromptRequest.fromJson(Map<String, dynamic> json) =>
      GetPromptRequest(
        name: readRequiredString(json['name'], 'GetPromptRequest.name'),
        arguments: readOptionalStringMap(
          json['arguments'],
          'GetPromptRequest.arguments',
        ),
        inputResponses: InputResponse.mapFromJson(
          json['inputResponses'],
          'GetPromptRequest.inputResponses',
        ),
        requestState: readOptionalString(
          json['requestState'],
          'GetPromptRequest.requestState',
        ),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (arguments != null) 'arguments': arguments,
        if (inputResponses != null)
          'inputResponses': InputResponse.mapToJson(inputResponses!),
        if (requestState != null) 'requestState': requestState,
      };
}

/// Request sent from client to get a specific prompt, potentially with template arguments.
class JsonRpcGetPromptRequest extends JsonRpcRequest {
  /// The get prompt parameters.
  final GetPromptRequest getParams;

  JsonRpcGetPromptRequest({
    required super.id,
    required this.getParams,
    super.meta,
  }) : super(method: Method.promptsGet, params: getParams.toJson());

  factory JsonRpcGetPromptRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.promptsGet,
      'JsonRpcGetPromptRequest',
    );
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcGetPromptRequest.params',
    );
    if (paramsMap == null) {
      throw const FormatException("Missing params for get prompt request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcGetPromptRequest(
      id: parseRequestId(json['id']),
      getParams: GetPromptRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Role associated with a prompt message (user or assistant).
enum PromptMessageRole { user, assistant }

/// Describes a message within a prompt structure.
class PromptMessage {
  /// The role of the message sender.
  final PromptMessageRole role;

  /// The content of the message.
  final Content content;

  const PromptMessage({
    required this.role,
    required this.content,
  });

  factory PromptMessage.fromJson(Map<String, dynamic> json) {
    return PromptMessage(
      role: PromptMessageRole.values.byName(
        readRequiredRoleString(json['role'], 'PromptMessage.role'),
      ),
      content: Content.fromJson(
        readJsonObject(json['content'], 'PromptMessage.content'),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content.toJson(),
      };
}

/// Result data for a successful `prompts/get` request.
class GetPromptResult implements BaseResultData {
  /// Optional description for the retrieved prompt.
  final String? description;

  /// The sequence of messages constituting the prompt.
  final List<PromptMessage> messages;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const GetPromptResult({this.description, required this.messages, this.meta});

  factory GetPromptResult.fromJson(Map<String, dynamic> json) {
    final meta = readOptionalJsonObject(json['_meta'], 'GetPromptResult._meta');
    final messages = json['messages'];
    if (messages is! List) {
      throw const FormatException('GetPromptResult.messages is required');
    }
    return GetPromptResult(
      description: readOptionalString(
        json['description'],
        'GetPromptResult.description',
      ),
      messages: messages
          .map(
            (m) => PromptMessage.fromJson(
              readJsonObject(m, 'GetPromptResult.messages items'),
            ),
          )
          .toList(),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (description != null) 'description': description,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (meta != null)
          '_meta': readJsonObject(meta, 'GetPromptResult._meta'),
      };
}

/// Notification from server indicating the list of available prompts has changed.
class JsonRpcPromptListChangedNotification extends JsonRpcNotification {
  const JsonRpcPromptListChangedNotification({super.meta})
      : super(method: Method.notificationsPromptsListChanged);

  factory JsonRpcPromptListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    _expectJsonRpcMethod(
      json,
      Method.notificationsPromptsListChanged,
      'JsonRpcPromptListChangedNotification',
    );
    return JsonRpcPromptListChangedNotification(meta: extractRequestMeta(json));
  }
}

/// Deprecated alias for [ListPromptsRequest].
@Deprecated('Use ListPromptsRequest instead')
typedef ListPromptsRequestParams = ListPromptsRequest;

/// Deprecated alias for [GetPromptRequest].
@Deprecated('Use GetPromptRequest instead')
typedef GetPromptRequestParams = GetPromptRequest;
