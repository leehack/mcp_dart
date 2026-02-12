import '../types.dart';

/// Describes an argument accepted by a prompt template.
class PromptArgument {
  /// The name of the argument.
  final String name;

  /// A human-readable description of the argument.
  final String? description;

  /// Whether this argument must be provided.
  final bool? required;

  const PromptArgument({
    required this.name,
    this.description,
    this.required,
  });

  factory PromptArgument.fromJson(Map<String, dynamic> json) {
    return PromptArgument(
      name: json['name'] as String,
      description: json['description'] as String?,
      required: json['required'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (required != null) 'required': required,
      };
}

/// A prompt or prompt template offered by the server.
class Prompt {
  /// The name of the prompt or template.
  final String name;

  /// An optional description of what the prompt provides.
  final String? description;

  /// A list of arguments for templating the prompt.
  final List<PromptArgument>? arguments;

  /// Optional icon for the prompt.
  final ImageContent? icon;

  /// Optional set of icons for the prompt.
  final List<McpIcon>? icons;

  const Prompt({
    required this.name,
    this.description,
    this.arguments,
    this.icon,
    this.icons,
  });

  factory Prompt.fromJson(Map<String, dynamic> json) {
    return Prompt(
      name: json['name'] as String,
      description: json['description'] as String?,
      arguments: (json['arguments'] as List<dynamic>?)
          ?.map((a) => PromptArgument.fromJson(a as Map<String, dynamic>))
          .toList(),
      icon: json['icon'] != null
          ? ImageContent.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      icons: (json['icons'] as List<dynamic>?)
          ?.map((e) => McpIcon.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (arguments != null)
          'arguments': arguments!.map((a) => a.toJson()).toList(),
        if (icon != null) 'icon': icon!.toJson(),
        if (icons != null)
          'icons': icons!.map((icon) => icon.toJson()).toList(),
      };
}

/// Parameters for the `prompts/list` request. Includes pagination.
class ListPromptsRequest {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListPromptsRequest({this.cursor});

  factory ListPromptsRequest.fromJson(Map<String, dynamic> json) =>
      ListPromptsRequest(cursor: json['cursor'] as String?);

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
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListPromptsRequest(
      id: json['id'],
      params: paramsMap == null ? null : ListPromptsRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `prompts/list` request.
class ListPromptsResult implements BaseResultData {
  /// The list of prompts/templates found.
  final List<Prompt> prompts;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListPromptsResult({required this.prompts, this.nextCursor, this.meta});

  factory ListPromptsResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListPromptsResult(
      prompts: (json['prompts'] as List<dynamic>?)
              ?.map((p) => Prompt.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'prompts': prompts.map((p) => p.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for the `prompts/get` request.
class GetPromptRequest {
  /// The name of the prompt or template to retrieve.
  final String name;

  /// Arguments to use for templating the prompt.
  final Map<String, String>? arguments;

  const GetPromptRequest({required this.name, this.arguments});

  factory GetPromptRequest.fromJson(Map<String, dynamic> json) =>
      GetPromptRequest(
        name: json['name'] as String,
        arguments: (json['arguments'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (arguments != null) 'arguments': arguments,
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
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for get prompt request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcGetPromptRequest(
      id: json['id'],
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
      role: PromptMessageRole.values.byName(json['role'] as String),
      content: Content.fromJson(json['content'] as Map<String, dynamic>),
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
    final meta = json['_meta'] as Map<String, dynamic>?;
    return GetPromptResult(
      description: json['description'] as String?,
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => PromptMessage.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (description != null) 'description': description,
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}

/// Notification from server indicating the list of available prompts has changed.
class JsonRpcPromptListChangedNotification extends JsonRpcNotification {
  const JsonRpcPromptListChangedNotification()
      : super(method: Method.notificationsPromptsListChanged);

  factory JsonRpcPromptListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcPromptListChangedNotification();
}

/// Deprecated alias for [ListPromptsRequest].
@Deprecated('Use ListPromptsRequest instead')
typedef ListPromptsRequestParams = ListPromptsRequest;

/// Deprecated alias for [GetPromptRequest].
@Deprecated('Use GetPromptRequest instead')
typedef GetPromptRequestParams = GetPromptRequest;
