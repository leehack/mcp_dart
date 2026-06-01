import 'json_rpc.dart';
import 'validation.dart';

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  final version = readRequiredString(json['jsonrpc'], '$context.jsonrpc');
  if (version != jsonRpcVersion) {
    throw FormatException('$context.jsonrpc must be "$jsonRpcVersion"');
  }
  final method = readRequiredString(json['method'], '$context.method');
  if (method != expected) {
    throw FormatException('$context.method must be "$expected"');
  }
}

void _expectType(
  Map<String, dynamic> json,
  String expected,
  String field,
) {
  final value = readRequiredString(json['type'], field);
  if (value != expected) {
    throw FormatException('$field must be "$expected"');
  }
}

/// Sealed class representing a reference for autocompletion targets.
sealed class Reference {
  /// The type of reference ("ref/resource" or "ref/prompt").
  final String type;

  const Reference({
    required this.type,
  });

  factory Reference.fromJson(Map<String, dynamic> json) {
    final type = readRequiredString(json['type'], 'Reference.type');
    return switch (type) {
      'ref/resource' => ResourceReference.fromJson(json),
      'ref/prompt' => PromptReference.fromJson(json),
      _ => throw FormatException("Invalid reference type: $type"),
    };
  }

  Map<String, dynamic> toJson() {
    return switch (this) {
      final ResourceReference r => _resourceReferenceToJson(r),
      final PromptReference p => {
          'type': p.type,
          'name': p.name,
          if (p.title != null) 'title': p.title,
        },
    };
  }
}

Map<String, dynamic> _resourceReferenceToJson(ResourceReference reference) {
  validateUriTemplateString(reference.uri, 'ResourceReference.uri');
  return {
    'type': reference.type,
    'uri': reference.uri,
  };
}

/// Reference to a resource or resource template URI.
class ResourceReference extends Reference {
  final String uri;

  const ResourceReference({required this.uri}) : super(type: 'ref/resource');

  factory ResourceReference.fromJson(Map<String, dynamic> json) {
    _expectType(json, 'ref/resource', 'ResourceReference.type');
    return ResourceReference(
      uri: readRequiredUriTemplateString(json['uri'], 'ResourceReference.uri'),
    );
  }
}

/// Reference to a prompt or prompt template name.
class PromptReference extends Reference {
  final String name;

  /// A human-readable title of the prompt.
  final String? title;

  const PromptReference({
    required this.name,
    this.title,
  }) : super(type: 'ref/prompt');

  factory PromptReference.fromJson(Map<String, dynamic> json) {
    _expectType(json, 'ref/prompt', 'PromptReference.type');
    return PromptReference(
      name: readRequiredString(json['name'], 'PromptReference.name'),
      title: readOptionalString(json['title'], 'PromptReference.title'),
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
      name: readRequiredString(json['name'], 'ArgumentCompletionInfo.name'),
      value: readRequiredString(json['value'], 'ArgumentCompletionInfo.value'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
      };
}

/// Additional context for completion requests.
class CompletionContext {
  /// Previously-resolved variables in a URI template or prompt.
  final Map<String, String>? arguments;

  const CompletionContext({this.arguments});

  factory CompletionContext.fromJson(Map<String, dynamic> json) {
    return CompletionContext(
      arguments: readOptionalStringMap(
        json['arguments'],
        'CompletionContext.arguments',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (arguments != null) 'arguments': arguments,
      };
}

/// Parameters for the `completion/complete` request.
class CompleteRequest {
  /// The reference identifying the completion target (prompt or resource).
  final Reference ref;

  /// Information about the argument being completed.
  final ArgumentCompletionInfo argument;

  /// Additional context for resolving completions.
  final CompletionContext? context;

  const CompleteRequest({
    required this.ref,
    required this.argument,
    this.context,
  });

  factory CompleteRequest.fromJson(Map<String, dynamic> json) =>
      CompleteRequest(
        ref: Reference.fromJson(
          readJsonObject(json['ref'], 'CompleteRequest.ref'),
        ),
        argument: ArgumentCompletionInfo.fromJson(
          readJsonObject(json['argument'], 'CompleteRequest.argument'),
        ),
        context: json['context'] == null
            ? null
            : CompletionContext.fromJson(
                readJsonObject(json['context'], 'CompleteRequest.context'),
              ),
      );

  Map<String, dynamic> toJson() => {
        'ref': ref.toJson(),
        'argument': argument.toJson(),
        if (context != null) 'context': context!.toJson(),
      };
}

/// Request sent from client to ask server for completion options for an argument.
class JsonRpcCompleteRequest extends JsonRpcRequest {
  /// The completion parameters.
  final CompleteRequest completeParams;

  JsonRpcCompleteRequest({
    required super.id,
    required this.completeParams,
    super.meta,
  }) : super(
          method: Method.completionComplete,
          params: completeParams.toJson(),
        );

  factory JsonRpcCompleteRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.completionComplete,
      'JsonRpcCompleteRequest',
    );
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcCompleteRequest.params',
    );
    if (paramsMap == null) {
      throw const FormatException("Missing params for complete request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcCompleteRequest(
      id: parseRequestId(json['id']),
      completeParams: CompleteRequest.fromJson(paramsMap),
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
    final values = json['values'];
    if (values is! List) {
      throw const FormatException('CompletionResultData.values is required');
    }
    if (values.length > 100) {
      throw const FormatException(
        'CompletionResultData.values must not exceed 100 items',
      );
    }
    return CompletionResultData(
      values: [
        for (final value in values)
          readRequiredString(value, 'CompletionResultData.values items'),
      ],
      total: readOptionalInteger(json['total'], 'CompletionResultData.total'),
      hasMore: readOptionalBool(
        json['hasMore'],
        'CompletionResultData.hasMore',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    if (values.length > 100) {
      throw ArgumentError.value(
        values.length,
        'values.length',
        'CompletionResultData.values must not exceed 100 items',
      );
    }
    return {
      'values': values,
      if (total != null) 'total': total,
      if (hasMore != null) 'hasMore': hasMore,
    };
  }
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
    final meta = readOptionalJsonObject(json['_meta'], 'CompleteResult._meta');
    return CompleteResult(
      completion: CompletionResultData.fromJson(
        readJsonObject(json['completion'], 'CompleteResult.completion'),
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'completion': completion.toJson(),
        if (meta != null) '_meta': readJsonObject(meta, 'CompleteResult._meta'),
      };
}

/// Experimental notification indicating available completions have changed.
///
/// Stable MCP 2025-11-25 does not define a completion list changed
/// notification. This class emits an explicit experimental method namespace.
@Deprecated(
  'Stable MCP 2025-11-25 does not define completion list-changed notifications.',
)
class JsonRpcCompletionListChangedNotification extends JsonRpcNotification {
  const JsonRpcCompletionListChangedNotification({super.meta})
      : super(method: Method.notificationsExperimentalCompletionsListChanged);

  factory JsonRpcCompletionListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      JsonRpcCompletionListChangedNotification(meta: extractRequestMeta(json));
}

/// Deprecated alias for [CompleteRequest].
@Deprecated('Use CompleteRequest instead')
typedef CompleteRequestParams = CompleteRequest;
