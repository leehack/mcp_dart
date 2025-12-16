import 'json_rpc.dart';

/// Sealed class representing a reference for autocompletion targets.
sealed class Reference {
  /// The type of reference ("ref/resource" or "ref/prompt").
  final String type;

  const Reference({
    required this.type,
  });

  factory Reference.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'ref/resource' => ResourceReference.fromJson(json),
      'ref/prompt' => PromptReference.fromJson(json),
      _ => throw FormatException("Invalid reference type: $type"),
    };
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          final ResourceReference r => {'uri': r.uri},
          final PromptReference p => {'name': p.name},
        },
      };
}

/// Reference to a resource or resource template URI.
class ResourceReference extends Reference {
  final String uri;

  const ResourceReference({required this.uri}) : super(type: 'ref/resource');

  factory ResourceReference.fromJson(Map<String, dynamic> json) {
    return ResourceReference(
      uri: json['uri'] as String,
    );
  }
}

/// Reference to a prompt or prompt template name.
class PromptReference extends Reference {
  final String name;

  const PromptReference({required this.name}) : super(type: 'ref/prompt');

  factory PromptReference.fromJson(Map<String, dynamic> json) {
    return PromptReference(
      name: json['name'] as String,
    );
  }
}

/// Information about the argument being completed.
class ArgumentCompletionInfo {
  /// The name of the argument.
  final String name;

  /// The current value entered by the user for completion matching.
  final String value;

  const ArgumentCompletionInfo({
    required this.name,
    required this.value,
  });

  factory ArgumentCompletionInfo.fromJson(Map<String, dynamic> json) {
    return ArgumentCompletionInfo(
      name: json['name'] as String,
      value: json['value'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
      };
}

/// Parameters for the `completion/complete` request.
class CompleteRequestParams {
  /// The reference identifying the completion target (prompt or resource).
  final Reference ref;

  /// Information about the argument being completed.
  final ArgumentCompletionInfo argument;

  const CompleteRequestParams({required this.ref, required this.argument});

  factory CompleteRequestParams.fromJson(Map<String, dynamic> json) =>
      CompleteRequestParams(
        ref: Reference.fromJson(json['ref'] as Map<String, dynamic>),
        argument: ArgumentCompletionInfo.fromJson(
          json['argument'] as Map<String, dynamic>,
        ),
      );

  Map<String, dynamic> toJson() => {
        'ref': ref.toJson(),
        'argument': argument.toJson(),
      };
}

/// Request sent from client to ask server for completion options for an argument.
class JsonRpcCompleteRequest extends JsonRpcRequest {
  /// The completion parameters.
  final CompleteRequestParams completeParams;

  JsonRpcCompleteRequest({
    required super.id,
    required this.completeParams,
    super.meta,
  }) : super(
          method: Method.completionComplete,
          params: completeParams.toJson(),
        );

  factory JsonRpcCompleteRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for complete request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCompleteRequest(
      id: json['id'],
      completeParams: CompleteRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Data structure containing completion results.
class CompletionResultData {
  /// Array of completion values (max 100 items).
  final List<String> values;

  /// Total number of completion options available (may exceed `values.length`).
  final int? total;

  /// Indicates if more options exist beyond those returned.
  final bool? hasMore;

  const CompletionResultData({
    required this.values,
    this.total,
    this.hasMore,
  }) : assert(values.length <= 100);

  factory CompletionResultData.fromJson(Map<String, dynamic> json) {
    return CompletionResultData(
      values: (json['values'] as List<dynamic>?)?.cast<String>() ?? [],
      total: json['total'] as int?,
      hasMore: json['hasMore'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'values': values,
        if (total != null) 'total': total,
        if (hasMore != null) 'hasMore': hasMore,
      };
}

/// Result data for a successful `completion/complete` request.
class CompleteResult implements BaseResultData {
  /// The completion results.
  final CompletionResultData completion;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const CompleteResult({required this.completion, this.meta});

  factory CompleteResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return CompleteResult(
      completion: CompletionResultData.fromJson(
        json['completion'] as Map<String, dynamic>,
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {'completion': completion.toJson()};
}

/// Notification from server indicating the list of available completions has changed.
class JsonRpcCompletionListChangedNotification extends JsonRpcNotification {
  const JsonRpcCompletionListChangedNotification()
      : super(method: Method.notificationsCompletionsListChanged);

  factory JsonRpcCompletionListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcCompletionListChangedNotification();
}
