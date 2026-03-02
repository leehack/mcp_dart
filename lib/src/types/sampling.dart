import 'content.dart';
import 'json_rpc.dart';
import 'tasks.dart';
import 'tools.dart';

Map<String, dynamic>? _asJsonObjectOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  throw FormatException('Expected object, got ${value.runtimeType}');
}

Map<String, dynamic> _asJsonObject(dynamic value) {
  final map = _asJsonObjectOrNull(value);
  if (map == null) {
    throw const FormatException('Expected object, got null');
  }
  return map;
}

Object _parseSamplingMessageContent(dynamic value) {
  if (value is List) {
    return value
        .map((item) => SamplingContent.fromJson(_asJsonObject(item)))
        .toList();
  }

  return SamplingContent.fromJson(_asJsonObject(value));
}

List<SamplingContent> _asSamplingContentBlocks(
  dynamic value, {
  required String context,
}) {
  if (value is SamplingContent) {
    return [value];
  }

  if (value is List<SamplingContent>) {
    return value;
  }

  if (value is List) {
    return value.map((item) {
      if (item is SamplingContent) {
        return item;
      }
      if (item is Map) {
        return SamplingContent.fromJson(item.cast<String, dynamic>());
      }
      throw FormatException(
        'Expected $context items to be SamplingContent or object, got ${item.runtimeType}',
      );
    }).toList();
  }

  if (value is Map) {
    return [SamplingContent.fromJson(value.cast<String, dynamic>())];
  }

  throw FormatException(
    'Expected $context to be SamplingContent or list, got ${value.runtimeType}',
  );
}

dynamic _samplingMessageContentToJson(Object value) {
  if (value is List) {
    return _asSamplingContentBlocks(
      value,
      context: 'sampling message content',
    ).map((item) => item.toJson()).toList();
  }

  return _asSamplingContentBlocks(
    value,
    context: 'sampling message content',
  ).first.toJson();
}

ToolChoice? _parseToolChoice(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is ToolChoice) {
    return value;
  }

  if (value is Map<String, dynamic>) {
    return ToolChoice.fromJson(value);
  }

  if (value is Map) {
    return ToolChoice.fromJson(value.cast<String, dynamic>());
  }

  throw FormatException(
    'Expected toolChoice to be an object, got ${value.runtimeType}',
  );
}

Map<String, dynamic>? _toolChoiceToLegacyMap(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.cast<String, dynamic>();
  }

  if (value is ToolChoice) {
    return {'type': value.mode.name};
  }

  throw FormatException(
    'Expected toolChoice to be an object, got ${value.runtimeType}',
  );
}

List<Content> _parseToolResultContent(dynamic rawContent) {
  if (rawContent == null) {
    return <Content>[];
  }

  if (rawContent is Content) {
    return [rawContent];
  }

  if (rawContent is List<Content>) {
    return rawContent;
  }

  if (rawContent is List) {
    return rawContent.map((item) {
      if (item is Content) {
        return item;
      }

      if (item is Map) {
        return Content.fromJson(item.cast<String, dynamic>());
      }

      return TextContent(text: item.toString());
    }).toList();
  }

  if (rawContent is Map) {
    final map = rawContent.cast<String, dynamic>();
    if (map.containsKey('type')) {
      return [Content.fromJson(map)];
    }
    return [TextContent(text: map.toString())];
  }

  return [TextContent(text: rawContent.toString())];
}

/// Hints for model selection during sampling.
class ModelHint {
  /// Hint for a model name.
  final String? name;

  const ModelHint({this.name});

  factory ModelHint.fromJson(Map<String, dynamic> json) {
    return ModelHint(name: json['name'] as String?);
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
      };
}

/// Server's preferences for model selection requested during sampling.
class ModelPreferences {
  /// Optional hints for model selection.
  final List<ModelHint>? hints;

  /// How much to prioritize cost (0-1).
  final double? costPriority;

  /// How much to prioritize sampling speed/latency (0-1).
  final double? speedPriority;

  /// How much to prioritize intelligence/capabilities (0-1).
  final double? intelligencePriority;

  const ModelPreferences({
    this.hints,
    this.costPriority,
    this.speedPriority,
    this.intelligencePriority,
  })  : assert(
          costPriority == null || (costPriority >= 0 && costPriority <= 1),
        ),
        assert(
          speedPriority == null || (speedPriority >= 0 && speedPriority <= 1),
        ),
        assert(
          intelligencePriority == null ||
              (intelligencePriority >= 0 && intelligencePriority <= 1),
        );

  factory ModelPreferences.fromJson(Map<String, dynamic> json) {
    return ModelPreferences(
      hints: (json['hints'] as List<dynamic>?)
          ?.map((h) => ModelHint.fromJson(_asJsonObject(h)))
          .toList(),
      costPriority: (json['costPriority'] as num?)?.toDouble(),
      speedPriority: (json['speedPriority'] as num?)?.toDouble(),
      intelligencePriority: (json['intelligencePriority'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (hints != null) 'hints': hints!.map((h) => h.toJson()).toList(),
        if (costPriority != null) 'costPriority': costPriority,
        if (speedPriority != null) 'speedPriority': speedPriority,
        if (intelligencePriority != null)
          'intelligencePriority': intelligencePriority,
      };
}

/// Represents content parts within sampling messages.
sealed class SamplingContent {
  /// The type of the content block.
  final String type;

  const SamplingContent({required this.type});

  /// Creates specific subclass from JSON.
  factory SamplingContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'text' => SamplingTextContent.fromJson(json),
      'image' => SamplingImageContent.fromJson(json),
      'audio' => SamplingAudioContent.fromJson(json),
      'tool_use' => SamplingToolUseContent.fromJson(json),
      'tool_result' => SamplingToolResultContent.fromJson(json),
      _ => throw FormatException("Invalid sampling content type: $type"),
    };
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          final SamplingTextContent c => {
              'text': c.text,
              if (c.annotations != null) 'annotations': c.annotations,
              if (c.meta != null) '_meta': c.meta,
            },
          final SamplingImageContent c => {
              'data': c.data,
              'mimeType': c.mimeType,
              if (c.annotations != null) 'annotations': c.annotations,
              if (c.meta != null) '_meta': c.meta,
            },
          final SamplingAudioContent c => {
              'data': c.data,
              'mimeType': c.mimeType,
              if (c.annotations != null) 'annotations': c.annotations,
              if (c.meta != null) '_meta': c.meta,
            },
          final SamplingToolUseContent c => {
              'id': c.id,
              'name': c.name,
              'input': c.input,
              if (c.meta != null) '_meta': c.meta,
            },
          final SamplingToolResultContent c => {
              'toolUseId': c.toolUseId,
              'content': c.contentBlocks.map((item) => item.toJson()).toList(),
              if (c.structuredContent != null)
                'structuredContent': c.structuredContent,
              if (c.isError != null) 'isError': c.isError,
              if (c.meta != null) '_meta': c.meta,
            },
        },
      };
}

/// Text content for sampling messages.
class SamplingTextContent extends SamplingContent {
  /// The text content.
  final String text;

  /// Optional annotations for the content block.
  final Map<String, dynamic>? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const SamplingTextContent({
    required this.text,
    this.annotations,
    this.meta,
  }) : super(type: 'text');

  factory SamplingTextContent.fromJson(Map<String, dynamic> json) =>
      SamplingTextContent(
        text: json['text'] as String,
        annotations: _asJsonObjectOrNull(json['annotations']),
        meta: _asJsonObjectOrNull(json['_meta']),
      );
}

/// Image content for sampling messages.
class SamplingImageContent extends SamplingContent {
  /// Base64 encoded image data.
  final String data;

  /// MIME type of the image (e.g., "image/png").
  final String mimeType;

  /// Optional annotations for the content block.
  final Map<String, dynamic>? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const SamplingImageContent({
    required this.data,
    required this.mimeType,
    this.annotations,
    this.meta,
  }) : super(type: 'image');

  factory SamplingImageContent.fromJson(Map<String, dynamic> json) =>
      SamplingImageContent(
        data: json['data'] as String,
        mimeType: json['mimeType'] as String,
        annotations: _asJsonObjectOrNull(json['annotations']),
        meta: _asJsonObjectOrNull(json['_meta']),
      );
}

/// Audio content for sampling messages.
class SamplingAudioContent extends SamplingContent {
  /// Base64 encoded audio data.
  final String data;

  /// MIME type of the audio (e.g., "audio/wav").
  final String mimeType;

  /// Optional annotations for the content block.
  final Map<String, dynamic>? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const SamplingAudioContent({
    required this.data,
    required this.mimeType,
    this.annotations,
    this.meta,
  }) : super(type: 'audio');

  factory SamplingAudioContent.fromJson(Map<String, dynamic> json) =>
      SamplingAudioContent(
        data: json['data'] as String,
        mimeType: json['mimeType'] as String,
        annotations: _asJsonObjectOrNull(json['annotations']),
        meta: _asJsonObjectOrNull(json['_meta']),
      );
}

/// Tool use content for sampling messages.
class SamplingToolUseContent extends SamplingContent {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  final Map<String, dynamic>? meta;

  const SamplingToolUseContent({
    required this.id,
    required this.name,
    required this.input,
    this.meta,
  }) : super(type: 'tool_use');

  factory SamplingToolUseContent.fromJson(Map<String, dynamic> json) =>
      SamplingToolUseContent(
        id: json['id'] as String,
        name: json['name'] as String,
        input: _asJsonObject(json['input']),
        meta: _asJsonObjectOrNull(json['_meta']),
      );
}

/// Tool result content for sampling messages.
class SamplingToolResultContent extends SamplingContent {
  final String toolUseId;
  final dynamic content;
  final Map<String, dynamic>? structuredContent;
  final bool? isError;
  final Map<String, dynamic>? meta;

  const SamplingToolResultContent({
    required this.toolUseId,
    required this.content,
    this.structuredContent,
    this.isError,
    this.meta,
  }) : super(type: 'tool_result');

  /// Normalized content blocks for tool results.
  List<Content> get contentBlocks => _parseToolResultContent(content);

  /// Legacy shape compatibility map form.
  @Deprecated('Use contentBlocks')
  dynamic get legacyContent => content;

  factory SamplingToolResultContent.fromJson(Map<String, dynamic> json) {
    return SamplingToolResultContent(
      toolUseId: json['toolUseId'] as String,
      content: _parseToolResultContent(json['content']),
      structuredContent: _asJsonObjectOrNull(json['structuredContent']),
      isError: json['isError'] as bool?,
      meta: _asJsonObjectOrNull(json['_meta']),
    );
  }
}

/// Role in a sampling message exchange.
enum SamplingMessageRole { user, assistant }

/// Describes a message issued to or received from an LLM API during sampling.
class SamplingMessage {
  /// The role of the message sender.
  final SamplingMessageRole role;

  /// The content of the message.
  ///
  /// Legacy APIs may use a single block while newer APIs may use a list.
  final dynamic content;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const SamplingMessage({
    required this.role,
    required this.content,
    this.meta,
  });

  /// Normalized content blocks representation.
  List<SamplingContent> get contentBlocks {
    return _asSamplingContentBlocks(
      content,
      context: 'sampling message content',
    );
  }

  factory SamplingMessage.fromJson(Map<String, dynamic> json) {
    return SamplingMessage(
      role: SamplingMessageRole.values.byName(json['role'] as String),
      content: _parseSamplingMessageContent(json['content']),
      meta: _asJsonObjectOrNull(json['_meta']),
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': _samplingMessageContentToJson(content),
        if (meta != null) '_meta': meta,
      };
}

/// Context inclusion options for sampling requests.
enum IncludeContext { none, thisServer, allServers }

/// Tool selection mode for sampling requests.
enum ToolChoiceMode { auto, required, none }

/// Controls how the model uses tools during sampling.
class ToolChoice {
  /// Tool selection mode.
  final ToolChoiceMode mode;

  const ToolChoice({this.mode = ToolChoiceMode.auto});

  factory ToolChoice.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode'] ?? json['type'];
    if (rawMode == null) {
      return const ToolChoice();
    }

    if (rawMode is! String) {
      throw FormatException('Expected toolChoice mode string, got $rawMode');
    }

    return ToolChoice(mode: ToolChoiceMode.values.byName(rawMode));
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
      };
}

/// Parameters for the `sampling/createMessage` request.
class CreateMessageRequest {
  /// The sequence of messages for the LLM prompt.
  final List<SamplingMessage> messages;

  /// Task metadata for task-augmented execution.
  final TaskCreation? task;

  /// Optional system prompt.
  final String? systemPrompt;

  /// Request to include context from MCP servers.
  final IncludeContext? includeContext;

  /// Sampling temperature.
  final double? temperature;

  /// Maximum number of tokens to sample.
  final int maxTokens;

  /// Sequences to stop sampling at.
  final List<String>? stopSequences;

  /// Optional provider-specific metadata.
  final Map<String, dynamic>? metadata;

  /// Server's preferences for model selection.
  final ModelPreferences? modelPreferences;

  /// Optional tools to provide to the model during sampling.
  final List<Tool>? tools;

  /// Optional tool choice configuration.
  ///
  /// For compatibility this can be either a raw map (legacy) or [ToolChoice].
  final dynamic toolChoice;

  /// Normalized tool choice configuration.
  ToolChoice? get toolChoiceConfig => _parseToolChoice(toolChoice);

  /// Legacy map representation of [toolChoice].
  @Deprecated('Use toolChoiceConfig')
  Map<String, dynamic>? get toolChoiceMap => _toolChoiceToLegacyMap(toolChoice);

  const CreateMessageRequest({
    required this.messages,
    this.task,
    this.systemPrompt,
    this.includeContext,
    this.temperature,
    required this.maxTokens,
    this.stopSequences,
    this.metadata,
    this.modelPreferences,
    this.tools,
    this.toolChoice,
  });

  factory CreateMessageRequest.fromJson(Map<String, dynamic> json) {
    final ctxStr = json['includeContext'] as String?;
    final task = _asJsonObjectOrNull(json['task']);
    final toolChoice = _asJsonObjectOrNull(json['toolChoice']);
    return CreateMessageRequest(
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => SamplingMessage.fromJson(_asJsonObject(m)))
              .toList() ??
          [],
      task: task == null ? null : TaskCreation.fromJson(task),
      systemPrompt: json['systemPrompt'] as String?,
      includeContext:
          ctxStr == null ? null : IncludeContext.values.byName(ctxStr),
      temperature: (json['temperature'] as num?)?.toDouble(),
      maxTokens: json['maxTokens'] as int,
      stopSequences: (json['stopSequences'] as List<dynamic>?)?.cast<String>(),
      metadata: _asJsonObjectOrNull(json['metadata']),
      modelPreferences: json['modelPreferences'] == null
          ? null
          : ModelPreferences.fromJson(
              _asJsonObject(json['modelPreferences']),
            ),
      tools: (json['tools'] as List<dynamic>?)
          ?.map((t) => Tool.fromJson(_asJsonObject(t)))
          .toList(),
      toolChoice: toolChoice,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'messages': messages.map((m) => m.toJson()).toList(),
        if (task != null) 'task': task!.toJson(),
        if (systemPrompt != null) 'systemPrompt': systemPrompt,
        if (includeContext != null) 'includeContext': includeContext!.name,
        if (temperature != null) 'temperature': temperature,
        'maxTokens': maxTokens,
        if (stopSequences != null) 'stopSequences': stopSequences,
        if (metadata != null) 'metadata': metadata,
        if (modelPreferences != null)
          'modelPreferences': modelPreferences!.toJson(),
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
        if (toolChoiceConfig != null) 'toolChoice': toolChoiceConfig!.toJson(),
      };
}

/// Request sent from server to client to sample an LLM.
class JsonRpcCreateMessageRequest extends JsonRpcRequest {
  /// The create message parameters.
  final CreateMessageRequest createParams;

  JsonRpcCreateMessageRequest({
    required super.id,
    required this.createParams,
    super.meta,
  }) : super(
          method: Method.samplingCreateMessage,
          params: createParams.toJson(),
        );

  factory JsonRpcCreateMessageRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for create message request");
    }
    final meta = _asJsonObjectOrNull(paramsMap['_meta']);
    return JsonRpcCreateMessageRequest(
      id: json['id'],
      createParams: CreateMessageRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Reasons why LLM sampling might stop.
enum StopReason { endTurn, stopSequence, maxTokens, toolUse }

/// Type alias allowing [StopReason] or a custom [String] reason.
typedef DynamicStopReason = dynamic; // StopReason or String

/// Result data for a successful `sampling/createMessage` request.
class CreateMessageResult implements BaseResultData {
  /// Name of the model that generated the message.
  final String model;

  /// Reason why sampling stopped ([StopReason] or custom string).
  final DynamicStopReason stopReason;

  /// Role of the generated message (usually assistant).
  final SamplingMessageRole role;

  /// Content generated by the model.
  ///
  /// Legacy APIs may use a single block while newer APIs may use a list.
  final dynamic content;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const CreateMessageResult({
    required this.model,
    this.stopReason,
    required this.role,
    required this.content,
    this.meta,
  });

  /// Normalized content blocks representation.
  List<SamplingContent> get contentBlocks {
    return _asSamplingContentBlocks(
      content,
      context: 'createMessage result content',
    );
  }

  factory CreateMessageResult.fromJson(Map<String, dynamic> json) {
    final meta = _asJsonObjectOrNull(json['_meta']);
    dynamic reason = json['stopReason'];
    if (reason is String) {
      try {
        reason = StopReason.values.byName(reason);
      } catch (_) {}
    }
    return CreateMessageResult(
      model: json['model'] as String,
      stopReason: reason,
      role: SamplingMessageRole.values.byName(json['role'] as String),
      content: _parseSamplingMessageContent(json['content']),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'model': model,
        if (stopReason != null)
          'stopReason': (stopReason is StopReason)
              ? (stopReason as StopReason).name
              : stopReason,
        'role': role.name,
        'content': _samplingMessageContentToJson(content),
        if (meta != null) '_meta': meta,
      };
}

/// Deprecated alias for [CreateMessageRequest].
@Deprecated('Use CreateMessageRequest instead')
typedef CreateMessageRequestParams = CreateMessageRequest;
