import 'misc.dart';
import 'initialization.dart';
import 'resources.dart';
import 'prompts.dart';
import 'elicitation.dart';
import 'tools.dart';
import 'logging.dart';
import 'sampling.dart';
import 'completion.dart';
import 'roots.dart';
import 'tasks.dart';

/// The latest version of the Model Context Protocol supported.
const latestProtocolVersion = "2025-11-25";

/// List of supported Model Context Protocol versions.
const supportedProtocolVersions = [
  latestProtocolVersion,
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
  "2024-10-07",
];

/// JSON-RPC protocol version string.
const jsonRpcVersion = "2.0";

/// Standard MCP JSON-RPC methods.
class Method {
  static const initialize = "initialize";
  static const ping = "ping";
  static const resourcesList = "resources/list";
  static const resourcesRead = "resources/read";
  static const resourcesTemplatesList = "resources/templates/list";
  static const resourcesSubscribe = "resources/subscribe";
  static const resourcesUnsubscribe = "resources/unsubscribe";
  static const promptsList = "prompts/list";
  static const promptsGet = "prompts/get";
  static const elicitationCreate = "elicitation/create";
  static const toolsList = "tools/list";
  static const toolsCall = "tools/call";
  static const loggingSetLevel = "logging/setLevel";
  static const samplingCreateMessage = "sampling/createMessage";
  static const completionComplete = "completion/complete";
  static const rootsList = "roots/list";
  static const tasksList = "tasks/list";
  static const tasksCancel = "tasks/cancel";
  static const tasksGet = "tasks/get";
  static const tasksResult = "tasks/result";

  static const notificationsInitialized = "notifications/initialized";
  static const notificationsCancelled = "notifications/cancelled";
  static const notificationsProgress = "notifications/progress";
  static const notificationsResourcesListChanged =
      "notifications/resources/list_changed";
  static const notificationsResourcesUpdated =
      "notifications/resources/updated";
  static const notificationsPromptsListChanged =
      "notifications/prompts/list_changed";
  static const notificationsToolsListChanged =
      "notifications/tools/list_changed";
  @Deprecated(
    'notifications/completions/list_changed is not part of stable MCP 2025-11-25. '
    'Use notifications/experimental/completions/list_changed for extension behavior.',
  )
  static const notificationsCompletionsListChanged =
      "notifications/completions/list_changed";
  static const notificationsExperimentalCompletionsListChanged =
      "notifications/experimental/completions/list_changed";
  static const notificationsMessage = "notifications/message";
  static const notificationsRootsListChanged =
      "notifications/roots/list_changed";
  static const notificationsTasksStatus = "notifications/tasks/status";
  static const notificationsElicitationComplete =
      "notifications/elicitation/complete";

  const Method._();
}

/// A progress token, used to associate progress notifications with the original request.
typedef ProgressToken = dynamic;

/// Parses a wire progress token.
///
/// MCP progress tokens are JSON strings or integers. Reject malformed wire
/// shapes at decode boundaries instead of allowing dynamic values to leak into
/// higher-level protocol code.
ProgressToken parseProgressToken(
  Object? value, {
  String fieldName = 'progressToken',
}) {
  if (value is String || value is int) {
    return value;
  }
  throw FormatException(
    'Invalid $fieldName: expected string or integer, got ${value.runtimeType}',
  );
}

/// An opaque token used to represent a cursor for pagination.
typedef Cursor = String;

/// A uniquely identifying ID for a request in JSON-RPC.
typedef RequestId = dynamic;

/// Parses a JSON-RPC request identifier.
///
/// JSON-RPC/MCP request IDs are JSON strings or integers for SDK request
/// boundaries. Notifications omit the `id` member entirely, and responses may
/// still carry `null` IDs for JSON-RPC error cases.
RequestId parseRequestId(Object? value, {String fieldName = 'id'}) {
  if (value is String || value is int) {
    return value;
  }
  throw FormatException(
    'Invalid $fieldName: expected string or integer, got ${value.runtimeType}',
  );
}

RequestId? _parseResponseId(Object? value) {
  if (value == null || value is String || value is int) {
    return value;
  }
  throw FormatException(
    'Invalid id: expected string, integer, or null, got ${value.runtimeType}',
  );
}

/// Validates request metadata that can affect protocol behavior.
///
/// `_meta.progressToken` is an MCP wire token and must be a string or integer
/// when present. Other `_meta` fields are preserved without interpretation.
Map<String, dynamic>? validateRequestMeta(Map<String, dynamic>? meta) {
  if (meta != null && meta.containsKey('progressToken')) {
    parseProgressToken(
      meta['progressToken'],
      fieldName: '_meta.progressToken',
    );
  }
  return meta;
}

Map<String, dynamic>? _parseRequestMeta(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw FormatException(
      'Invalid _meta: expected object, got ${value.runtimeType}',
    );
  }
  if (value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid _meta: expected string keys');
  }
  return validateRequestMeta(Map<String, dynamic>.from(value));
}

/// Extracts request metadata from either top-level or params-nested `_meta`.
Map<String, dynamic>? extractRequestMeta(Map<String, dynamic> json) {
  final topLevelMeta = _parseRequestMeta(json['_meta']);
  final params = json['params'];
  final paramsMeta = params is Map ? _parseRequestMeta(params['_meta']) : null;
  return topLevelMeta ?? paramsMeta;
}

/// Base class for all JSON-RPC messages (requests, notifications, responses, errors).
sealed class JsonRpcMessage {
  /// The JSON-RPC version string. Always "2.0".
  final String jsonrpc = jsonRpcVersion;

  /// Constant constructor for subclasses.
  const JsonRpcMessage();

  /// Parses a JSON map into a specific [JsonRpcMessage] subclass.
  factory JsonRpcMessage.fromJson(Map<String, dynamic> json) {
    if (json['jsonrpc'] != jsonRpcVersion) {
      throw FormatException('Invalid JSON-RPC version: ${json['jsonrpc']}');
    }

    if (json.containsKey('method')) {
      final method = json['method'] as String;
      final hasId = json.containsKey('id');

      if (hasId) {
        return switch (method) {
          Method.initialize => JsonRpcInitializeRequest.fromJson(json),
          Method.ping => JsonRpcPingRequest.fromJson(json),
          Method.resourcesList => JsonRpcListResourcesRequest.fromJson(json),
          Method.resourcesRead => JsonRpcReadResourceRequest.fromJson(json),
          Method.resourcesTemplatesList =>
            JsonRpcListResourceTemplatesRequest.fromJson(json),
          Method.resourcesSubscribe => JsonRpcSubscribeRequest.fromJson(json),
          Method.resourcesUnsubscribe =>
            JsonRpcUnsubscribeRequest.fromJson(json),
          Method.promptsList => JsonRpcListPromptsRequest.fromJson(json),
          Method.promptsGet => JsonRpcGetPromptRequest.fromJson(json),
          Method.elicitationCreate => JsonRpcElicitRequest.fromJson(json),
          Method.toolsList => JsonRpcListToolsRequest.fromJson(json),
          Method.toolsCall => JsonRpcCallToolRequest.fromJson(json),
          Method.loggingSetLevel => JsonRpcSetLevelRequest.fromJson(json),
          Method.samplingCreateMessage => JsonRpcCreateMessageRequest.fromJson(
              json,
            ),
          Method.completionComplete => JsonRpcCompleteRequest.fromJson(json),
          Method.rootsList => JsonRpcListRootsRequest.fromJson(json),
          Method.tasksList => JsonRpcListTasksRequest.fromJson(json),
          Method.tasksCancel => JsonRpcCancelTaskRequest.fromJson(json),
          Method.tasksGet => JsonRpcGetTaskRequest.fromJson(json),
          Method.tasksResult => JsonRpcTaskResultRequest.fromJson(json),
          _ => JsonRpcRequest(
              id: parseRequestId(json['id']),
              method: method,
              params: json['params'] as Map<String, dynamic>?,
              meta: extractRequestMeta(json),
            ),
        };
      } else {
        return switch (method) {
          Method.notificationsInitialized =>
            JsonRpcInitializedNotification.fromJson(json),
          Method.notificationsCancelled =>
            JsonRpcCancelledNotification.fromJson(
              json,
            ),
          Method.notificationsProgress => JsonRpcProgressNotification.fromJson(
              json,
            ),
          Method.notificationsResourcesListChanged =>
            JsonRpcResourceListChangedNotification.fromJson(json),
          Method.notificationsResourcesUpdated =>
            JsonRpcResourceUpdatedNotification.fromJson(json),
          Method.notificationsPromptsListChanged =>
            JsonRpcPromptListChangedNotification.fromJson(json),
          Method.notificationsToolsListChanged =>
            JsonRpcToolListChangedNotification.fromJson(json),
          Method.notificationsExperimentalCompletionsListChanged =>
            JsonRpcCompletionListChangedNotification.fromJson(json),
          Method.notificationsMessage =>
            JsonRpcLoggingMessageNotification.fromJson(
              json,
            ),
          Method.notificationsRootsListChanged =>
            JsonRpcRootsListChangedNotification.fromJson(json),
          Method.notificationsTasksStatus =>
            JsonRpcTaskStatusNotification.fromJson(json),
          Method.notificationsElicitationComplete =>
            JsonRpcElicitationCompleteNotification.fromJson(json),
          _ => JsonRpcNotification(
              method: method,
              params: json['params'] as Map<String, dynamic>?,
              meta: json['_meta'] as Map<String, dynamic>? ??
                  (json['params'] as Map<String, dynamic>?)?['_meta']
                      as Map<String, dynamic>?,
            ),
        };
      }
    } else if (json.containsKey('result')) {
      final id = _parseResponseId(json['id']);
      final resultData = json['result'] as Map<String, dynamic>;
      final meta = resultData['_meta'] as Map<String, dynamic>?;
      final actualResult = Map<String, dynamic>.from(resultData)
        ..remove('_meta');
      return JsonRpcResponse(id: id, result: actualResult, meta: meta);
    } else if (json.containsKey('error')) {
      return JsonRpcError.fromJson(json);
    } else {
      throw FormatException('Invalid JSON-RPC message format: $json');
    }
  }

  /// Converts the message object to its JSON representation.
  Map<String, dynamic> toJson();
}

/// Base class for JSON-RPC requests that expect a response.
class JsonRpcRequest extends JsonRpcMessage {
  /// The request identifier.
  final RequestId id;

  /// The method to be invoked.
  final String method;

  /// The parameters for the method, if any.
  final Map<String, dynamic>? params;

  /// Optional metadata associated with the request.
  final Map<String, dynamic>? meta;

  /// Creates a JSON-RPC request.
  const JsonRpcRequest({
    required this.id,
    required this.method,
    this.params,
    this.meta,
  });

  /// The progress token for out-of-band progress notifications.
  ProgressToken? get progressToken {
    final token = meta?['progressToken'];
    return token == null ? null : parseProgressToken(token);
  }

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'id': id,
        'method': method,
        if (params != null || meta != null)
          'params': <String, dynamic>{
            ...?params,
            if (meta != null) '_meta': meta,
          },
      };
}

/// Base class for JSON-RPC notifications which do not expect a response.
class JsonRpcNotification extends JsonRpcMessage {
  /// The method to be invoked.
  final String method;

  /// The parameters for the method, if any.
  final Map<String, dynamic>? params;

  /// Optional metadata associated with the notification.
  final Map<String, dynamic>? meta;

  /// Creates a JSON-RPC notification.
  const JsonRpcNotification({required this.method, this.params, this.meta});

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'method': method,
        if (params != null || meta != null)
          'params': <String, dynamic>{
            ...?params,
            if (meta != null) '_meta': meta,
          },
      };
}

/// Represents a successful (non-error) response to a request.
class JsonRpcResponse extends JsonRpcMessage {
  /// The identifier matching the original request.
  final RequestId id;

  /// The result data of the method invocation.
  final Map<String, dynamic> result;

  /// Optional metadata associated with the response.
  final Map<String, dynamic>? meta;

  /// Creates a successful JSON-RPC response.
  const JsonRpcResponse({required this.id, required this.result, this.meta});

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'id': id,
        'result': <String, dynamic>{...result, if (meta != null) '_meta': meta},
      };
}
// --- JSON-RPC Error ---

/// Standard JSON-RPC error codes.
enum ErrorCode {
  connectionClosed(-32000),
  requestTimeout(-32001),

  /// URL mode elicitation is required before the request can be processed.
  /// The error data contains elicitations that must be completed.
  urlElicitationRequired(-32042),

  parseError(-32700),
  invalidRequest(-32600),
  methodNotFound(-32601),
  invalidParams(-32602),
  internalError(-32603);

  final int value;
  const ErrorCode(this.value);

  /// Finds an [ErrorCode] based on its integer [value], or returns null.
  static ErrorCode? fromValue(int value) => values
      .cast<ErrorCode?>()
      .firstWhere((e) => e?.value == value, orElse: () => null);
}

/// Represents the `error` object in a JSON-RPC error response.
class JsonRpcErrorData {
  final int code;
  final String message;
  final dynamic data;

  const JsonRpcErrorData({
    required this.code,
    required this.message,
    this.data,
  });

  factory JsonRpcErrorData.fromJson(Map<String, dynamic> json) =>
      JsonRpcErrorData(
        code: json['code'] as int,
        message: json['message'] as String,
        data: json['data'],
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };
}

/// Represents a response indicating an error occurred during a request.
class JsonRpcError extends JsonRpcMessage {
  final RequestId id;
  final JsonRpcErrorData error;

  const JsonRpcError({required this.id, required this.error});

  factory JsonRpcError.fromJson(Map<String, dynamic> json) => JsonRpcError(
        id: _parseResponseId(json['id']),
        error: JsonRpcErrorData.fromJson(json['error'] as Map<String, dynamic>),
      );

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'id': id,
        'error': error.toJson(),
      };
}

/// Base class for specific MCP result types.
abstract class BaseResultData {
  /// Optional metadata associated with the result.
  Map<String, dynamic>? get meta;

  /// Converts the result data to its JSON representation.
  ///
  /// Implementations must include `_meta` when [meta] is non-null so typed
  /// results preserve the MCP `Result._meta` field during direct serialization.
  Map<String, dynamic> toJson();
}

/// Custom error class for MCP specific errors.
class McpError extends Error {
  /// The error code (typically from [ErrorCode] or custom).
  final int code;

  /// The error message.
  final String message;

  /// Optional additional data associated with the error.
  final dynamic data;

  McpError(this.code, this.message, [this.data]);

  @override
  String toString() =>
      'McpError $code: $message ${data != null ? '(data: $data)' : ''}';
}

/// JSON-RPC request to list tools.
class JsonRpcListToolsRequest extends JsonRpcRequest {
  const JsonRpcListToolsRequest({
    required super.id,
    super.params,
    super.meta,
  }) : super(method: Method.toolsList);

  @Deprecated(
    'Use JsonRpcListToolsRequest(id: ..., params: params?.toJson(), meta: meta) instead.',
  )
  factory JsonRpcListToolsRequest.fromListParams({
    required RequestId id,
    ListToolsRequest? params,
    Map<String, dynamic>? meta,
  }) {
    return JsonRpcListToolsRequest(
      id: id,
      params: params?.toJson(),
      meta: meta,
    );
  }

  factory JsonRpcListToolsRequest.fromJson(Map<String, dynamic> json) {
    return JsonRpcListToolsRequest(
      id: parseRequestId(json['id']),
      params: json['params'] as Map<String, dynamic>?,
      meta: extractRequestMeta(json),
    );
  }

  ListToolsRequest get listParams {
    final requestParams = params;
    if (requestParams == null) {
      return const ListToolsRequest();
    }
    return ListToolsRequest.fromJson(requestParams);
  }
}

/// JSON-RPC request to call a tool.
class JsonRpcCallToolRequest extends JsonRpcRequest {
  const JsonRpcCallToolRequest({
    required super.id,
    required Map<String, dynamic> params,
    super.meta,
  }) : super(method: Method.toolsCall, params: params);

  factory JsonRpcCallToolRequest.fromJson(Map<String, dynamic> json) {
    return JsonRpcCallToolRequest(
      id: parseRequestId(json['id']),
      params: json['params'] as Map<String, dynamic>? ?? {},
      meta: extractRequestMeta(json),
    );
  }

  CallToolRequest get callParams {
    final requestParams = params;
    if (requestParams == null) {
      throw const FormatException('Missing params for call tool request');
    }
    return CallToolRequest.fromJson(requestParams);
  }

  bool get isTaskAugmented {
    // Check for task augmentation in meta or params as per convention
    // Usually handled by side-channel or specific params
    return meta?.containsKey('task') == true ||
        params?.containsKey('task') == true;
  }

  TaskCreation? get taskParams {
    final taskMap = meta?['task'] ?? params?['task'];
    if (taskMap is Map<String, dynamic>) {
      return TaskCreation.fromJson(taskMap);
    }
    return null;
  }
}
