import 'json_rpc.dart';
import 'tools.dart';

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
          ?.map((h) => ModelHint.fromJson(h as Map<String, dynamic>))
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
  /// The type of the content ("text", "image", "tool_use", or "tool_result").
  final String type;

  const SamplingContent({required this.type});

  /// Creates specific subclass from JSON.
  factory SamplingContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'text' => SamplingTextContent.fromJson(json),
      'image' => SamplingImageContent.fromJson(json),
      'tool_use' => SamplingToolUseContent.fromJson(json),
      'tool_result' => SamplingToolResultContent.fromJson(json),
      _ => throw FormatException("Invalid sampling content type: $type"),
    };
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          final SamplingTextContent c => {'text': c.text},
          final SamplingImageContent c => {
              'data': c.data,
              'mimeType': c.mimeType,
            },
          final SamplingToolUseContent c => {
              'id': c.id,
              'name': c.name,
              'input': c.input,
            },
          final SamplingToolResultContent c => {
              'toolUseId': c.toolUseId,
              'content': c.content,
              if (c.isError != null) 'isError': c.isError,
            },
        },
      };
}

/// Text content for sampling messages.
class SamplingTextContent extends SamplingContent {
  /// The text content.
  final String text;

  const SamplingTextContent({required this.text}) : super(type: 'text');

  factory SamplingTextContent.fromJson(Map<String, dynamic> json) =>
      SamplingTextContent(text: json['text'] as String);
}

/// Image content for sampling messages.
class SamplingImageContent extends SamplingContent {
  /// Base64 encoded image data.
  final String data;

  /// MIME type of the image (e.g., "image/png").
  final String mimeType;

  const SamplingImageContent({required this.data, required this.mimeType})
      : super(type: 'image');

  factory SamplingImageContent.fromJson(Map<String, dynamic> json) =>
      SamplingImageContent(
        data: json['data'] as String,
        mimeType: json['mimeType'] as String,
      );
}

/// Tool use content for sampling messages.
class SamplingToolUseContent extends SamplingContent {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const SamplingToolUseContent({
    required this.id,
    required this.name,
    required this.input,
  }) : super(type: 'tool_use');

  factory SamplingToolUseContent.fromJson(Map<String, dynamic> json) =>
      SamplingToolUseContent(
        id: json['id'] as String,
        name: json['name'] as String,
        input: json['input'] as Map<String, dynamic>,
      );
}

/// Tool result content for sampling messages.
class SamplingToolResultContent extends SamplingContent {
  final String toolUseId;
  final dynamic content;
  final bool? isError;

  const SamplingToolResultContent({
    required this.toolUseId,
    required this.content,
    this.isError,
  }) : super(type: 'tool_result');

  factory SamplingToolResultContent.fromJson(Map<String, dynamic> json) =>
      SamplingToolResultContent(
        toolUseId: json['toolUseId'] as String,
        content: json['content'],
        isError: json['isError'] as bool?,
      );
}

/// Role in a sampling message exchange.
enum SamplingMessageRole { user, assistant }

/// Describes a message issued to or received from an LLM API during sampling.
class SamplingMessage {
  /// The role of the message sender.
  final SamplingMessageRole role;

  /// The content of the message (text, image, tool_use, or tool_result).
  final SamplingContent content;

  const SamplingMessage({
    required this.role,
    required this.content,
  });

  factory SamplingMessage.fromJson(Map<String, dynamic> json) {
    return SamplingMessage(
      role: SamplingMessageRole.values.byName(json['role'] as String),
      content: SamplingContent.fromJson(
        json['content'] as Map<String, dynamic>,
      ),
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content.toJson(),
      };
}

/// Context inclusion options for sampling requests.
enum IncludeContext { none, thisServer, allServers }

/// Parameters for the `sampling/createMessage` request.
class CreateMessageRequest {
  /// The sequence of messages for the LLM prompt.
  final List<SamplingMessage> messages;

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
  final Map<String, dynamic>? toolChoice;

  const CreateMessageRequest({
    required this.messages,
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
    return CreateMessageRequest(
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => SamplingMessage.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      systemPrompt: json['systemPrompt'] as String?,
      includeContext:
          ctxStr == null ? null : IncludeContext.values.byName(ctxStr),
      temperature: (json['temperature'] as num?)?.toDouble(),
      maxTokens: json['maxTokens'] as int,
      stopSequences: (json['stopSequences'] as List<dynamic>?)?.cast<String>(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      modelPreferences: json['modelPreferences'] == null
          ? null
          : ModelPreferences.fromJson(
              json['modelPreferences'] as Map<String, dynamic>,
            ),
      tools: (json['tools'] as List<dynamic>?)
          ?.map((t) => Tool.fromJson(t as Map<String, dynamic>))
          .toList(),
      toolChoice: json['toolChoice'] as Map<String, dynamic>?,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'messages': messages.map((m) => m.toJson()).toList(),
        if (systemPrompt != null) 'systemPrompt': systemPrompt,
        if (includeContext != null) 'includeContext': includeContext!.name,
        if (temperature != null) 'temperature': temperature,
        'maxTokens': maxTokens,
        if (stopSequences != null) 'stopSequences': stopSequences,
        if (metadata != null) 'metadata': metadata,
        if (modelPreferences != null)
          'modelPreferences': modelPreferences!.toJson(),
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
        if (toolChoice != null) 'toolChoice': toolChoice,
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
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCreateMessageRequest(
      id: json['id'],
      createParams: CreateMessageRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Reasons why LLM sampling might stop.
enum StopReason { endTurn, stopSequence, maxTokens }

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
  final SamplingContent content;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const CreateMessageResult({
    required this.model,
    this.stopReason,
    required this.role,
    required this.content,
    this.meta,
  }) : assert(
          stopReason == null ||
              stopReason is StopReason ||
              stopReason is String,
        );

  factory CreateMessageResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
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
      content: SamplingContent.fromJson(
        json['content'] as Map<String, dynamic>,
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'model': model,
        if (stopReason != null)
          'stopReason':
              (stopReason is StopReason) ? stopReason.toString() : stopReason,
        'role': role.name,
        'content': content.toJson(),
      };
}

/// Deprecated alias for [CreateMessageRequest].
@Deprecated('Use CreateMessageRequest instead')
typedef CreateMessageRequestParams = CreateMessageRequest;
