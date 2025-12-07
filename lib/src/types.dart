import 'dart:convert';

/// The latest version of the Model Context Protocol supported.
const latestProtocolVersion = "2025-11-25";

/// List of supported Model Context Protocol versions.
const supportedProtocolVersions = [
  latestProtocolVersion,
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
  "2024-10-07"
];

/// JSON-RPC protocol version string.
const jsonRpcVersion = "2.0";

/// A progress token, used to associate progress notifications with the original request.
typedef ProgressToken = dynamic;

/// An opaque token used to represent a cursor for pagination.
typedef Cursor = String;

/// A uniquely identifying ID for a request in JSON-RPC.
typedef RequestId = dynamic;

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

    final id = json['id'];

    if (json.containsKey('method')) {
      final method = json['method'] as String;

      if (id != null) {
        return switch (method) {
          'initialize' => JsonRpcInitializeRequest.fromJson(json),
          'ping' => JsonRpcPingRequest.fromJson(json),
          'resources/list' => JsonRpcListResourcesRequest.fromJson(json),
          'resources/read' => JsonRpcReadResourceRequest.fromJson(json),
          'resources/templates/list' =>
            JsonRpcListResourceTemplatesRequest.fromJson(json),
          'resources/subscribe' => JsonRpcSubscribeRequest.fromJson(json),
          'resources/unsubscribe' => JsonRpcUnsubscribeRequest.fromJson(json),
          'prompts/list' => JsonRpcListPromptsRequest.fromJson(json),
          'prompts/get' => JsonRpcGetPromptRequest.fromJson(json),
          'elicitation/create' => JsonRpcElicitRequest.fromJson(json),
          'tools/list' => JsonRpcListToolsRequest.fromJson(json),
          'tools/call' => JsonRpcCallToolRequest.fromJson(json),
          'logging/setLevel' => JsonRpcSetLevelRequest.fromJson(json),
          'sampling/createMessage' => JsonRpcCreateMessageRequest.fromJson(
              json,
            ),
          'completion/complete' => JsonRpcCompleteRequest.fromJson(json),
          'roots/list' => JsonRpcListRootsRequest.fromJson(json),
          'tasks/list' => JsonRpcListTasksRequest.fromJson(json),
          'tasks/cancel' => JsonRpcCancelTaskRequest.fromJson(json),
          'tasks/get' => JsonRpcGetTaskRequest.fromJson(json),
          'tasks/result' => JsonRpcGetTaskResultRequest.fromJson(json),
          _ => throw UnimplementedError(
              "fromJson for request method '$method' not implemented",
            ),
        };
      } else {
        return switch (method) {
          'notifications/initialized' =>
            JsonRpcInitializedNotification.fromJson(json),
          'notifications/cancelled' => JsonRpcCancelledNotification.fromJson(
              json,
            ),
          'notifications/progress' => JsonRpcProgressNotification.fromJson(
              json,
            ),
          'notifications/resources/list_changed' =>
            JsonRpcResourceListChangedNotification.fromJson(json),
          'notifications/resources/updated' =>
            JsonRpcResourceUpdatedNotification.fromJson(json),
          'notifications/prompts/list_changed' =>
            JsonRpcPromptListChangedNotification.fromJson(json),
          'notifications/tools/list_changed' =>
            JsonRpcToolListChangedNotification.fromJson(json),
          'notifications/message' => JsonRpcLoggingMessageNotification.fromJson(
              json,
            ),
          'notifications/roots/list_changed' =>
            JsonRpcRootsListChangedNotification.fromJson(json),
          'notifications/tasks/status' =>
            JsonRpcTaskStatusNotification.fromJson(json),
          _ => throw UnimplementedError(
              "fromJson for notification method '$method' not implemented",
            ),
        };
      }
    } else if (json.containsKey('result')) {
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
  ProgressToken? get progressToken => meta?['progressToken'];

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'id': id,
        'method': method,
        if (params != null || meta != null)
          'params': <String, dynamic>{
            ...?params,
            if (meta != null) '_meta': meta
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
            if (meta != null) '_meta': meta
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
// --- Tasks ---

/// Task status enum
enum TaskStatus {
  working,
  // ignore: constant_identifier_names
  input_required,
  completed,
  failed,
  cancelled,
}

/// Task data structure
class Task {
  final String taskId;
  final TaskStatus status;
  final String? statusMessage;
  final String createdAt; // ISO 8601
  final String lastUpdatedAt; // ISO 8601
  final int? ttl;
  final int? pollInterval;

  const Task({
    required this.taskId,
    required this.status,
    this.statusMessage,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.ttl,
    this.pollInterval,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      taskId: json['taskId'] as String,
      status: TaskStatus.values.byName(json['status'] as String),
      statusMessage: json['statusMessage'] as String?,
      createdAt: json['createdAt'] as String,
      lastUpdatedAt: json['lastUpdatedAt'] as String,
      ttl: json['ttl'] as int?,
      pollInterval: json['pollInterval'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'status': status.name,
        if (statusMessage != null) 'statusMessage': statusMessage,
        'createdAt': createdAt,
        'lastUpdatedAt': lastUpdatedAt,
        if (ttl != null) 'ttl': ttl,
        if (pollInterval != null) 'pollInterval': pollInterval,
      };
}

/// Parameters for `tasks/list`
class ListTasksRequestParams {
  final Cursor? cursor;

  const ListTasksRequestParams({this.cursor});

  factory ListTasksRequestParams.fromJson(Map<String, dynamic> json) {
    return ListTasksRequestParams(cursor: json['cursor'] as String?);
  }

  Map<String, dynamic> toJson() => {
        if (cursor != null) 'cursor': cursor,
      };
}

class JsonRpcListTasksRequest extends JsonRpcRequest {
  final ListTasksRequestParams listParams;

  JsonRpcListTasksRequest({
    required super.id,
    ListTasksRequestParams? params,
    super.meta,
  })  : listParams = params ?? const ListTasksRequestParams(),
        super(method: "tasks/list", params: params?.toJson());

  factory JsonRpcListTasksRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListTasksRequest(
      id: json['id'],
      params:
          paramsMap == null ? null : ListTasksRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

class ListTasksResult implements BaseResultData {
  final List<Task> tasks;
  final Cursor? nextCursor;

  @override
  final Map<String, dynamic>? meta;

  const ListTasksResult({required this.tasks, this.nextCursor, this.meta});

  factory ListTasksResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListTasksResult(
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((t) => Task.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for `tasks/cancel`
class CancelTaskRequestParams {
  final String taskId;

  const CancelTaskRequestParams({required this.taskId});

  factory CancelTaskRequestParams.fromJson(Map<String, dynamic> json) {
    return CancelTaskRequestParams(taskId: json['taskId'] as String);
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
      };
}

class JsonRpcCancelTaskRequest extends JsonRpcRequest {
  final CancelTaskRequestParams cancelParams;

  JsonRpcCancelTaskRequest({
    required super.id,
    required this.cancelParams,
    super.meta,
  }) : super(method: "tasks/cancel", params: cancelParams.toJson());

  factory JsonRpcCancelTaskRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for cancel task request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCancelTaskRequest(
      id: json['id'],
      cancelParams: CancelTaskRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result of `tasks/cancel` is a `Task` object.
class CancelTaskResult implements BaseResultData {
  final Task task;

  @override
  final Map<String, dynamic>? meta;

  const CancelTaskResult({required this.task, this.meta});

  factory CancelTaskResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return CancelTaskResult(
      task: Task.fromJson(json), // The result IS the task object
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => task.toJson();
}

/// Parameters for `tasks/get`
class GetTaskRequestParams {
  final String taskId;

  const GetTaskRequestParams({required this.taskId});

  factory GetTaskRequestParams.fromJson(Map<String, dynamic> json) {
    return GetTaskRequestParams(taskId: json['taskId'] as String);
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
      };
}

class JsonRpcGetTaskRequest extends JsonRpcRequest {
  final GetTaskRequestParams getParams;

  JsonRpcGetTaskRequest({
    required super.id,
    required this.getParams,
    super.meta,
  }) : super(method: "tasks/get", params: getParams.toJson());

  factory JsonRpcGetTaskRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for get task request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcGetTaskRequest(
      id: json['id'],
      getParams: GetTaskRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result of `tasks/get` is a `Task` object.
class GetTaskResult implements BaseResultData {
  final Task task;

  @override
  final Map<String, dynamic>? meta;

  const GetTaskResult({required this.task, this.meta});

  factory GetTaskResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return GetTaskResult(
      task: Task.fromJson(json),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => task.toJson();
}

/// Parameters for `tasks/result`
class GetTaskResultRequestParams {
  final String taskId;

  const GetTaskResultRequestParams({required this.taskId});

  factory GetTaskResultRequestParams.fromJson(Map<String, dynamic> json) {
    return GetTaskResultRequestParams(taskId: json['taskId'] as String);
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
      };
}

class JsonRpcGetTaskResultRequest extends JsonRpcRequest {
  final GetTaskResultRequestParams resultParams;

  JsonRpcGetTaskResultRequest({
    required super.id,
    required this.resultParams,
    super.meta,
  }) : super(method: "tasks/result", params: resultParams.toJson());

  factory JsonRpcGetTaskResultRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for get task result request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcGetTaskResultRequest(
      id: json['id'],
      resultParams: GetTaskResultRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Notification `notifications/tasks/status`
class TaskStatusNotificationParams {
  final Task task;

  const TaskStatusNotificationParams({required this.task});

  factory TaskStatusNotificationParams.fromJson(Map<String, dynamic> json) {
    return TaskStatusNotificationParams(task: Task.fromJson(json));
  }

  Map<String, dynamic> toJson() => task.toJson();
}

class JsonRpcTaskStatusNotification extends JsonRpcNotification {
  final TaskStatusNotificationParams statusParams;

  JsonRpcTaskStatusNotification({
    required this.statusParams,
    super.meta,
  }) : super(
          method: "notifications/tasks/status",
          params: statusParams.toJson(),
        );

  factory JsonRpcTaskStatusNotification.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for task status notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcTaskStatusNotification(
      statusParams: TaskStatusNotificationParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

// --- JSON-RPC Error ---

/// Standard JSON-RPC error codes.
enum ErrorCode {
  connectionClosed(-32000),
  requestTimeout(-32001),
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
        id: json['id'],
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

  /// Converts the result data (excluding meta) to its JSON representation.
  Map<String, dynamic> toJson();
}

/// A response that indicates success but carries no specific data.
class EmptyResult implements BaseResultData {
  @override
  final Map<String, dynamic>? meta;

  const EmptyResult({this.meta});

  @override
  Map<String, dynamic> toJson() => {};
}

/// Parameters for the `notifications/cancelled` notification.
class CancelledNotificationParams {
  /// The ID of the request to cancel.
  final RequestId requestId;

  /// An optional string describing the reason for the cancellation.
  final String? reason;

  const CancelledNotificationParams({required this.requestId, this.reason});

  factory CancelledNotificationParams.fromJson(Map<String, dynamic> json) =>
      CancelledNotificationParams(
        requestId: json['requestId'],
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        if (reason != null) 'reason': reason,
      };
}

/// Notification sent by either side to indicate cancellation of a request.
class JsonRpcCancelledNotification extends JsonRpcNotification {
  /// The parameters detailing which request is cancelled and why.
  final CancelledNotificationParams cancelParams;

  JsonRpcCancelledNotification({required this.cancelParams, super.meta})
      : super(method: "notifications/cancelled", params: cancelParams.toJson());

  factory JsonRpcCancelledNotification.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for cancelled notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCancelledNotification(
      cancelParams: CancelledNotificationParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Describes the name and version of an MCP implementation (client or server).
class Implementation {
  /// The name of the implementation.
  final String name;

  /// The version string of the implementation.
  final String version;

  /// A description of the implementation.
  final String? description;

  const Implementation({
    required this.name,
    required this.version,
    this.description,
  });

  factory Implementation.fromJson(Map<String, dynamic> json) {
    return Implementation(
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        if (description != null) 'description': description,
      };
}

/// Describes capabilities related to root resources (e.g., workspace folders).
class ClientCapabilitiesRoots {
  /// Whether the client supports `notifications/roots/list_changed`.
  final bool? listChanged;

  const ClientCapabilitiesRoots({
    this.listChanged,
  });

  factory ClientCapabilitiesRoots.fromJson(Map<String, dynamic> json) {
    return ClientCapabilitiesRoots(
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to tasks.
class ClientCapabilitiesTasks {
  /// Whether the client supports `tasks/list`.
  final bool? list;

  /// Whether the client supports `tasks/cancel`.
  final bool? cancel;

  /// Request types that support task augmentation.
  final Map<String, dynamic>? requests;

  const ClientCapabilitiesTasks({
    this.list,
    this.cancel,
    this.requests,
  });

  factory ClientCapabilitiesTasks.fromJson(Map<String, dynamic> json) {
    return ClientCapabilitiesTasks(
      list: json['list'] != null,
      cancel: json['cancel'] != null,
      requests: json['requests'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (list == true) 'list': {},
        if (cancel == true) 'cancel': {},
        if (requests != null) 'requests': requests,
      };
}

/// Describes capabilities related to elicitation (server-initiated user input).
class ClientCapabilitiesElicitation {
  /// Empty object indicates support for elicitation
  const ClientCapabilitiesElicitation();

  factory ClientCapabilitiesElicitation.fromJson(Map<String, dynamic> json) {
    return const ClientCapabilitiesElicitation();
  }

  Map<String, dynamic> toJson() => {};
}

/// Capabilities a client may support.
class ClientCapabilities {
  /// Experimental, non-standard capabilities.
  final Map<String, dynamic>? experimental;

  /// Present if the client supports sampling (`sampling/createMessage`).
  final Map<String, dynamic>? sampling;

  /// Present if the client supports listing roots (`roots/list`).
  final ClientCapabilitiesRoots? roots;

  /// Present if the client supports elicitation (`elicitation/create`).
  final ClientCapabilitiesElicitation? elicitation;

  /// Present if the client supports tasks.
  final ClientCapabilitiesTasks? tasks;

  const ClientCapabilities({
    this.experimental,
    this.sampling,
    this.roots,
    this.elicitation,
    this.tasks,
  });

  factory ClientCapabilities.fromJson(Map<String, dynamic> json) {
    final rootsMap = json['roots'] as Map<String, dynamic>?;
    final elicitationMap = json['elicitation'] as Map<String, dynamic>?;
    final tasksMap = json['tasks'] as Map<String, dynamic>?;
    return ClientCapabilities(
      experimental: json['experimental'] as Map<String, dynamic>?,
      sampling: json['sampling'] as Map<String, dynamic>?,
      roots:
          rootsMap == null ? null : ClientCapabilitiesRoots.fromJson(rootsMap),
      elicitation: elicitationMap == null
          ? null
          : ClientCapabilitiesElicitation.fromJson(elicitationMap),
      tasks:
          tasksMap == null ? null : ClientCapabilitiesTasks.fromJson(tasksMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (experimental != null) 'experimental': experimental,
        if (sampling != null) 'sampling': sampling,
        if (roots != null) 'roots': roots!.toJson(),
        if (elicitation != null) 'elicitation': elicitation!.toJson(),
        if (tasks != null) 'tasks': tasks!.toJson(),
      };
}

/// Parameters for the `initialize` request.
class InitializeRequestParams {
  /// The latest protocol version the client supports.
  final String protocolVersion;

  /// The capabilities the client supports.
  final ClientCapabilities capabilities;

  /// Information about the client implementation.
  final Implementation clientInfo;

  const InitializeRequestParams({
    required this.protocolVersion,
    required this.capabilities,
    required this.clientInfo,
  });

  factory InitializeRequestParams.fromJson(Map<String, dynamic> json) =>
      InitializeRequestParams(
        protocolVersion: json['protocolVersion'] as String,
        capabilities: ClientCapabilities.fromJson(
          json['capabilities'] as Map<String, dynamic>,
        ),
        clientInfo: Implementation.fromJson(
          json['clientInfo'] as Map<String, dynamic>,
        ),
      );

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'capabilities': capabilities.toJson(),
        'clientInfo': clientInfo.toJson(),
      };
}

/// Request sent from client to server upon connection to begin initialization.
class JsonRpcInitializeRequest extends JsonRpcRequest {
  /// The initialization parameters.
  final InitializeRequestParams initParams;

  JsonRpcInitializeRequest({
    required super.id,
    required this.initParams,
    super.meta,
  }) : super(method: "initialize", params: initParams.toJson());

  factory JsonRpcInitializeRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for initialize request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcInitializeRequest(
      id: json['id'],
      initParams: InitializeRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Describes capabilities related to prompts.
class ServerCapabilitiesPrompts {
  /// Whether the server supports `notifications/prompts/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesPrompts({
    this.listChanged,
  });

  factory ServerCapabilitiesPrompts.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesPrompts(
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to resources.
class ServerCapabilitiesResources {
  /// Whether the server supports `resources/subscribe` and `resources/unsubscribe`.
  final bool? subscribe;

  /// Whether the server supports `notifications/resources/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesResources({
    this.subscribe,
    this.listChanged,
  });

  factory ServerCapabilitiesResources.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesResources(
      subscribe: json['subscribe'] as bool?,
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (subscribe != null) 'subscribe': subscribe,
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to tools.
class ServerCapabilitiesTools {
  /// Whether the server supports `notifications/tools/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesTools({
    this.listChanged,
  });

  factory ServerCapabilitiesTools.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesTools(
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to completions.
class ServerCapabilitiesCompletions {
  /// Whether the server supports `notifications/completions/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesCompletions({
    this.listChanged,
  });

  factory ServerCapabilitiesCompletions.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesCompletions(
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to tasks.
class ServerCapabilitiesTasks {
  /// Whether the server supports `tasks/list`.
  final bool? list;

  /// Whether the server supports `tasks/cancel`.
  final bool? cancel;

  /// Request types that support task augmentation.
  final Map<String, dynamic>? requests;

  const ServerCapabilitiesTasks({
    this.list,
    this.cancel,
    this.requests,
  });

  factory ServerCapabilitiesTasks.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesTasks(
      list: json['list'] != null,
      cancel: json['cancel'] != null,
      requests: json['requests'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (list == true) 'list': {},
        if (cancel == true) 'cancel': {},
        if (requests != null) 'requests': requests,
      };
}

/// Capabilities a server may support.
class ServerCapabilities {
  /// Experimental, non-standard capabilities.
  final Map<String, dynamic>? experimental;

  /// Present if the server supports sending log messages (`notifications/message`).
  final Map<String, dynamic>? logging;

  /// Present if the server offers prompt templates (`prompts/list`, `prompts/get`).
  final ServerCapabilitiesPrompts? prompts;

  /// Present if the server offers resources (`resources/list`, `resources/read`, etc.).
  final ServerCapabilitiesResources? resources;

  /// Present if the server offers tools (`tools/list`, `tools/call`).
  final ServerCapabilitiesTools? tools;

  /// Present if the server offers completions (`completion/complete`).
  final ServerCapabilitiesCompletions? completions;

  /// Present if the server supports tasks.
  final ServerCapabilitiesTasks? tasks;

  const ServerCapabilities({
    this.experimental,
    this.logging,
    this.prompts,
    this.resources,
    this.tools,
    this.completions,
    this.tasks,
  });

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    final pMap = json['prompts'] as Map<String, dynamic>?;
    final rMap = json['resources'] as Map<String, dynamic>?;
    final tMap = json['tools'] as Map<String, dynamic>?;
    final cMap = json['completions'] as Map<String, dynamic>?;
    final tasksMap = json['tasks'] as Map<String, dynamic>?;
    return ServerCapabilities(
      experimental: json['experimental'] as Map<String, dynamic>?,
      logging: json['logging'] as Map<String, dynamic>?,
      prompts: pMap == null ? null : ServerCapabilitiesPrompts.fromJson(pMap),
      resources:
          rMap == null ? null : ServerCapabilitiesResources.fromJson(rMap),
      tools: tMap == null ? null : ServerCapabilitiesTools.fromJson(tMap),
      completions:
          cMap == null ? null : ServerCapabilitiesCompletions.fromJson(cMap),
      tasks:
          tasksMap == null ? null : ServerCapabilitiesTasks.fromJson(tasksMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (experimental != null) 'experimental': experimental,
        if (logging != null) 'logging': logging,
        if (prompts != null) 'prompts': prompts!.toJson(),
        if (resources != null) 'resources': resources!.toJson(),
        if (tools != null) 'tools': tools!.toJson(),
        if (completions != null) 'completions': completions!.toJson(),
        if (tasks != null) 'tasks': tasks!.toJson(),
      };
}

/// Result data for a successful `initialize` request.
class InitializeResult implements BaseResultData {
  /// The protocol version the server wants to use.
  final String protocolVersion;

  /// The capabilities the server supports.
  final ServerCapabilities capabilities;

  /// Information about the server implementation.
  final Implementation serverInfo;

  /// Instructions describing how to use the server and its features.
  final String? instructions;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const InitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
    this.meta,
  });

  factory InitializeResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return InitializeResult(
      protocolVersion: json['protocolVersion'] as String,
      capabilities: ServerCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>,
      ),
      serverInfo: Implementation.fromJson(
        json['serverInfo'] as Map<String, dynamic>,
      ),
      instructions: json['instructions'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'capabilities': capabilities.toJson(),
        'serverInfo': serverInfo.toJson(),
        if (instructions != null) 'instructions': instructions,
      };
}

/// Notification sent from the client to the server after initialization is finished.
class JsonRpcInitializedNotification extends JsonRpcNotification {
  const JsonRpcInitializedNotification()
      : super(method: "notifications/initialized");

  factory JsonRpcInitializedNotification.fromJson(Map<String, dynamic> json) =>
      const JsonRpcInitializedNotification();
}

/// A ping request, sent by either side to check liveness. Expects an empty result.
class JsonRpcPingRequest extends JsonRpcRequest {
  const JsonRpcPingRequest({required super.id}) : super(method: "ping");

  factory JsonRpcPingRequest.fromJson(Map<String, dynamic> json) =>
      JsonRpcPingRequest(id: json['id']);
}

/// Represents progress information for a long-running request.
class Progress {
  /// The progress thus far (should increase monotonically).
  final num progress;

  /// Total number of items or total progress required, if known.
  final num? total;

  const Progress({
    required this.progress,
    this.total,
  });

  factory Progress.fromJson(Map<String, dynamic> json) {
    return Progress(
      progress: json['progress'] as num,
      total: json['total'] as num?,
    );
  }

  Map<String, dynamic> toJson() => {
        'progress': progress,
        if (total != null) 'total': total,
      };
}

/// Parameters for the `notifications/progress` notification.
class ProgressNotificationParams implements Progress {
  /// The token originally provided in the request's `_meta`.
  final ProgressToken progressToken;

  /// The progress thus far.
  @override
  final num progress;

  /// Total progress required, if known.
  @override
  final num? total;

  const ProgressNotificationParams({
    required this.progressToken,
    required this.progress,
    this.total,
  });

  factory ProgressNotificationParams.fromJson(Map<String, dynamic> json) {
    final progressData = Progress.fromJson(json);
    return ProgressNotificationParams(
      progressToken: json['progressToken'],
      progress: progressData.progress,
      total: progressData.total,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'progressToken': progressToken,
        ...Progress(
          progress: progress,
          total: total,
        ).toJson(),
      };
}

/// Out-of-band notification informing the receiver of progress on a request.
class JsonRpcProgressNotification extends JsonRpcNotification {
  /// The progress parameters.
  final ProgressNotificationParams progressParams;

  /// Creates a progress notification.
  JsonRpcProgressNotification({required this.progressParams, super.meta})
      : super(
            method: "notifications/progress", params: progressParams.toJson());

  /// Creates from JSON.
  factory JsonRpcProgressNotification.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for progress notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcProgressNotification(
      progressParams: ProgressNotificationParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Sealed class representing the contents of a specific resource or sub-resource.
sealed class ResourceContents {
  /// The URI of this resource content.
  final String uri;

  /// The MIME type, if known.
  final String? mimeType;

  const ResourceContents({
    required this.uri,
    this.mimeType,
  });

  /// Creates a specific [ResourceContents] subclass from JSON.
  factory ResourceContents.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'] as String;
    final mimeType = json['mimeType'] as String?;
    if (json.containsKey('text')) {
      return TextResourceContents(
        uri: uri,
        mimeType: mimeType,
        text: json['text'] as String,
      );
    }
    if (json.containsKey('blob')) {
      return BlobResourceContents(
        uri: uri,
        mimeType: mimeType,
        blob: json['blob'] as String,
      );
    }
    return UnknownResourceContents(
      uri: uri,
      mimeType: mimeType,
    );
  }

  /// Converts resource contents to JSON.
  Map<String, dynamic> toJson() => {
        'uri': uri,
        if (mimeType != null) 'mimeType': mimeType,
        ...switch (this) {
          TextResourceContents c => {'text': c.text},
          BlobResourceContents c => {'blob': c.blob},
          UnknownResourceContents _ => {},
        },
      };
}

/// Resource contents represented as text.
class TextResourceContents extends ResourceContents {
  /// The text content.
  final String text;

  const TextResourceContents({
    required super.uri,
    super.mimeType,
    required this.text,
  });
}

/// Resource contents represented as binary data (Base64 encoded).
class BlobResourceContents extends ResourceContents {
  /// Base64 encoded binary data.
  final String blob;

  const BlobResourceContents({
    required super.uri,
    super.mimeType,
    required this.blob,
  });
}

/// Represents unknown or passthrough resource content types.
class UnknownResourceContents extends ResourceContents {
  const UnknownResourceContents({
    required super.uri,
    super.mimeType,
  });
}

/// A known resource offered by the server.
class Resource {
  /// The URI identifying this resource.
  final String uri;

  /// A human-readable name for the resource.
  final String name;

  /// A description of what the resource represents.
  final String? description;

  /// The MIME type, if known.
  final String? mimeType;

  /// The icon for the resource.
  final String? icon;

  const Resource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
    this.icon,
  });

  /// Creates from JSON.
  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      uri: json['uri'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      icon: json['icon'] as String?,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (icon != null) 'icon': icon,
      };
}

/// A template description for resources available on the server.
class ResourceTemplate {
  /// A URI template (RFC 6570) to construct resource URIs.
  final String uriTemplate;

  /// A human-readable name for the type of resource this template refers to.
  final String name;

  /// A description of what this template is for.
  final String? description;

  /// The MIME type for all resources matching this template, if consistent.
  final String? mimeType;

  /// The icon for the resource template.
  final String? icon;

  /// Creates a resource template description.
  const ResourceTemplate({
    required this.uriTemplate,
    required this.name,
    this.description,
    this.mimeType,
    this.icon,
  });

  /// Creates from JSON.
  factory ResourceTemplate.fromJson(Map<String, dynamic> json) {
    return ResourceTemplate(
      uriTemplate: json['uriTemplate'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      icon: json['icon'] as String?,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'uriTemplate': uriTemplate,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (icon != null) 'icon': icon,
      };
}

/// Parameters for the `resources/list` request. Includes pagination.
class ListResourcesRequestParams {
  /// Opaque token for pagination, requesting results after this cursor.
  final Cursor? cursor;

  /// Creates list resources parameters.
  const ListResourcesRequestParams({this.cursor});

  /// Creates from JSON.
  factory ListResourcesRequestParams.fromJson(Map<String, dynamic> json) =>
      ListResourcesRequestParams(cursor: json['cursor'] as String?);

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available resources.
class JsonRpcListResourcesRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListResourcesRequestParams listParams;

  /// Creates a list resources request.
  JsonRpcListResourcesRequest({
    required super.id,
    ListResourcesRequestParams? params,
    super.meta,
  })  : listParams = params ?? const ListResourcesRequestParams(),
        super(method: "resources/list", params: params?.toJson());

  /// Creates from JSON.
  factory JsonRpcListResourcesRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListResourcesRequest(
      id: json['id'],
      params: paramsMap == null
          ? null
          : ListResourcesRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/list` request.
class ListResourcesResult implements BaseResultData {
  /// The list of resources found.
  final List<Resource> resources;

  /// Opaque token for pagination, indicating more results might be available.
  final Cursor? nextCursor;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  /// Creates a list resources result.
  const ListResourcesResult({
    required this.resources,
    this.nextCursor,
    this.meta,
  });

  /// Creates from JSON.
  factory ListResourcesResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListResourcesResult(
      resources: (json['resources'] as List<dynamic>?)
              ?.map((e) => Resource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  /// Converts to JSON (excluding meta).
  @override
  Map<String, dynamic> toJson() => {
        'resources': resources.map((r) => r.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for the `resources/templates/list` request. Includes pagination.
class ListResourceTemplatesRequestParams {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListResourceTemplatesRequestParams({this.cursor});

  factory ListResourceTemplatesRequestParams.fromJson(
    Map<String, dynamic> json,
  ) =>
      ListResourceTemplatesRequestParams(cursor: json['cursor'] as String?);

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available resource templates.
class JsonRpcListResourceTemplatesRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListResourceTemplatesRequestParams listParams;

  JsonRpcListResourceTemplatesRequest({
    required super.id,
    ListResourceTemplatesRequestParams? params,
    super.meta,
  })  : listParams = params ?? const ListResourceTemplatesRequestParams(),
        super(method: "resources/templates/list", params: params?.toJson());

  factory JsonRpcListResourceTemplatesRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListResourceTemplatesRequest(
      id: json['id'],
      params: paramsMap == null
          ? null
          : ListResourceTemplatesRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/templates/list` request.
class ListResourceTemplatesResult implements BaseResultData {
  /// The list of resource templates found.
  final List<ResourceTemplate> resourceTemplates;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  @override
  final Map<String, dynamic>? meta;

  const ListResourceTemplatesResult({
    required this.resourceTemplates,
    this.nextCursor,
    this.meta,
  });

  factory ListResourceTemplatesResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListResourceTemplatesResult(
      resourceTemplates: (json['resourceTemplates'] as List<dynamic>?)
              ?.map((e) => ResourceTemplate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'resourceTemplates': resourceTemplates.map((t) => t.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for the `resources/read` request.
class ReadResourceRequestParams {
  /// The URI of the resource to read.
  final String uri;

  const ReadResourceRequestParams({required this.uri});

  factory ReadResourceRequestParams.fromJson(Map<String, dynamic> json) =>
      ReadResourceRequestParams(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Request sent from client to read a specific resource.
class JsonRpcReadResourceRequest extends JsonRpcRequest {
  /// The read parameters (containing URI).
  final ReadResourceRequestParams readParams;

  JsonRpcReadResourceRequest({
    required super.id,
    required this.readParams,
    super.meta,
  }) : super(method: "resources/read", params: readParams.toJson());

  factory JsonRpcReadResourceRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for read resource request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcReadResourceRequest(
      id: json['id'],
      readParams: ReadResourceRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/read` request.
class ReadResourceResult implements BaseResultData {
  /// The contents of the resource (can be multiple parts).
  final List<ResourceContents> contents;

  @override
  final Map<String, dynamic>? meta;

  const ReadResourceResult({required this.contents, this.meta});

  factory ReadResourceResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ReadResourceResult(
      contents: (json['contents'] as List<dynamic>?)
              ?.map((e) => ResourceContents.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'contents': contents.map((c) => c.toJson()).toList(),
      };
}

/// Notification from server indicating the list of available resources has changed.
class JsonRpcResourceListChangedNotification extends JsonRpcNotification {
  const JsonRpcResourceListChangedNotification()
      : super(method: "notifications/resources/list_changed");

  factory JsonRpcResourceListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcResourceListChangedNotification();
}

/// Parameters for the `resources/subscribe` request.
class SubscribeRequestParams {
  /// The URI of the resource to subscribe to for updates.
  final String uri;

  const SubscribeRequestParams({required this.uri});

  factory SubscribeRequestParams.fromJson(Map<String, dynamic> json) =>
      SubscribeRequestParams(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Request sent from client to subscribe to updates for a resource.
class JsonRpcSubscribeRequest extends JsonRpcRequest {
  /// The subscribe parameters (containing URI).
  final SubscribeRequestParams subParams;

  JsonRpcSubscribeRequest({
    required super.id,
    required this.subParams,
    super.meta,
  }) : super(method: "resources/subscribe", params: subParams.toJson());

  factory JsonRpcSubscribeRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for subscribe request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcSubscribeRequest(
      id: json['id'],
      subParams: SubscribeRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `resources/unsubscribe` request.
class UnsubscribeRequestParams {
  /// The URI of the resource to unsubscribe from.
  final String uri;

  const UnsubscribeRequestParams({required this.uri});

  factory UnsubscribeRequestParams.fromJson(Map<String, dynamic> json) =>
      UnsubscribeRequestParams(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Request sent from client to cancel a resource subscription.
class JsonRpcUnsubscribeRequest extends JsonRpcRequest {
  /// The unsubscribe parameters (containing URI).
  final UnsubscribeRequestParams unsubParams;

  JsonRpcUnsubscribeRequest({
    required super.id,
    required this.unsubParams,
    super.meta,
  }) : super(method: "resources/unsubscribe", params: unsubParams.toJson());

  factory JsonRpcUnsubscribeRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for unsubscribe request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcUnsubscribeRequest(
      id: json['id'],
      unsubParams: UnsubscribeRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `notifications/resources/updated` notification.
class ResourceUpdatedNotificationParams {
  /// The URI of the resource that has been updated (possibly a sub-resource).
  final String uri;

  const ResourceUpdatedNotificationParams({required this.uri});

  factory ResourceUpdatedNotificationParams.fromJson(
    Map<String, dynamic> json,
  ) =>
      ResourceUpdatedNotificationParams(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Notification from server indicating a subscribed resource has changed.
class JsonRpcResourceUpdatedNotification extends JsonRpcNotification {
  /// The updated parameters (containing URI).
  final ResourceUpdatedNotificationParams updatedParams;

  JsonRpcResourceUpdatedNotification({required this.updatedParams, super.meta})
      : super(
          method: "notifications/resources/updated",
          params: updatedParams.toJson(),
        );

  factory JsonRpcResourceUpdatedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for resource updated notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcResourceUpdatedNotification(
      updatedParams: ResourceUpdatedNotificationParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

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

  /// The icon for the prompt.
  final String? icon;

  const Prompt({
    required this.name,
    this.description,
    this.arguments,
    this.icon,
  });

  factory Prompt.fromJson(Map<String, dynamic> json) {
    return Prompt(
      name: json['name'] as String,
      description: json['description'] as String?,
      arguments: (json['arguments'] as List<dynamic>?)
          ?.map((a) => PromptArgument.fromJson(a as Map<String, dynamic>))
          .toList(),
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (arguments != null)
          'arguments': arguments!.map((a) => a.toJson()).toList(),
        if (icon != null) 'icon': icon,
      };
}

/// Parameters for the `prompts/list` request. Includes pagination.
class ListPromptsRequestParams {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListPromptsRequestParams({this.cursor});

  factory ListPromptsRequestParams.fromJson(Map<String, dynamic> json) =>
      ListPromptsRequestParams(cursor: json['cursor'] as String?);

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available prompts and templates.
class JsonRpcListPromptsRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListPromptsRequestParams listParams;

  JsonRpcListPromptsRequest({
    required super.id,
    ListPromptsRequestParams? params,
    super.meta,
  })  : listParams = params ?? const ListPromptsRequestParams(),
        super(method: "prompts/list", params: params?.toJson());

  factory JsonRpcListPromptsRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListPromptsRequest(
      id: json['id'],
      params: paramsMap == null
          ? null
          : ListPromptsRequestParams.fromJson(paramsMap),
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
class GetPromptRequestParams {
  /// The name of the prompt or template to retrieve.
  final String name;

  /// Arguments to use for templating the prompt.
  final Map<String, String>? arguments;

  const GetPromptRequestParams({required this.name, this.arguments});

  factory GetPromptRequestParams.fromJson(Map<String, dynamic> json) =>
      GetPromptRequestParams(
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
  final GetPromptRequestParams getParams;

  JsonRpcGetPromptRequest({
    required super.id,
    required this.getParams,
    super.meta,
  }) : super(method: "prompts/get", params: getParams.toJson());

  factory JsonRpcGetPromptRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for get prompt request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcGetPromptRequest(
      id: json['id'],
      getParams: GetPromptRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Base class for content parts within prompts or tool results.
sealed class Content {
  /// The type of the content part.
  final String type;

  const Content({
    required this.type,
  });

  factory Content.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'text' => TextContent.fromJson(json),
      'image' => ImageContent.fromJson(json),
      'audio' => AudioContent.fromJson(json),
      'resource' => EmbeddedResource.fromJson(json),
      _ => UnknownContent(type: type ?? 'unknown'),
    };
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          TextContent c => {'text': c.text},
          ImageContent c => {'data': c.data, 'mimeType': c.mimeType},
          AudioContent c => {'data': c.data, 'mimeType': c.mimeType},
          EmbeddedResource c => {'resource': c.resource.toJson()},
          UnknownContent _ => {},
        },
      };
}

/// Text content.
class TextContent extends Content {
  /// The text string.
  final String text;

  const TextContent({required this.text}) : super(type: 'text');

  factory TextContent.fromJson(Map<String, dynamic> json) {
    return TextContent(
      text: json['text'] as String,
    );
  }
}

/// Image content.
class ImageContent extends Content {
  /// Base64 encoded image data.
  final String data;

  /// MIME type of the image (e.g., "image/png").
  final String mimeType;

  const ImageContent({
    required this.data,
    required this.mimeType,
  }) : super(type: 'image');

  factory ImageContent.fromJson(Map<String, dynamic> json) {
    return ImageContent(
      data: json['data'] as String,
      mimeType: json['mimeType'] as String,
    );
  }
}

class AudioContent extends Content {
  /// Base64 encoded audio data.
  final String data;

  /// MIME type of the audio (e.g., "audio/wav").
  final String mimeType;

  const AudioContent({
    required this.data,
    required this.mimeType,
  }) : super(type: 'audio');

  factory AudioContent.fromJson(Map<String, dynamic> json) {
    return AudioContent(
      data: json['data'] as String,
      mimeType: json['mimeType'] as String,
    );
  }
}

/// Content embedding a resource.
class EmbeddedResource extends Content {
  /// The embedded resource contents.
  final ResourceContents resource;

  const EmbeddedResource({required this.resource}) : super(type: 'resource');

  factory EmbeddedResource.fromJson(Map<String, dynamic> json) {
    return EmbeddedResource(
      resource: ResourceContents.fromJson(
        json['resource'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Represents unknown or passthrough content types.
class UnknownContent extends Content {
  const UnknownContent({required super.type});
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
      : super(method: "notifications/prompts/list_changed");

  factory JsonRpcPromptListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcPromptListChangedNotification();
}

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

  const ToolAnnotations({
    required this.title,
    this.readOnlyHint = false,
    this.destructiveHint = true,
    this.idempotentHint = false,
    this.openWorldHint = true,
  });

  factory ToolAnnotations.fromJson(Map<String, dynamic> json) {
    return ToolAnnotations(
      title: json['title'] as String,
      readOnlyHint: json['readOnlyHint'] as bool? ?? false,
      destructiveHint: json['destructiveHint'] as bool? ?? true,
      idempotentHint: json['idempotentHint'] as bool? ?? false,
      openWorldHint: json['openWorldHint'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'readOnlyHint': readOnlyHint,
        'destructiveHint': destructiveHint,
        'idempotentHint': idempotentHint,
        'openWorldHint': openWorldHint,
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

  /// The icon for the tool.
  final String? icon;

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
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        'inputSchema': inputSchema.toJson(),
        if (outputSchema != null) 'outputSchema': outputSchema!.toJson(),
        if (annotations != null) 'annotation': annotations!.toJson(),
        if (icon != null) 'icon': icon,
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
        super(method: "tools/list", params: params?.toJson());

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

  JsonRpcCallToolRequest({
    required super.id,
    required this.callParams,
    super.meta,
  }) : super(method: "tools/call", params: callParams.toJson());

  factory JsonRpcCallToolRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for call tool request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCallToolRequest(
      id: json['id'],
      callParams: CallToolRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
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
      : super(method: "notifications/tools/list_changed");

  factory JsonRpcToolListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcToolListChangedNotification();
}

/// Severity levels for log messages (syslog levels).
enum LoggingLevel {
  debug,
  info,
  notice,
  warning,
  error,
  critical,
  alert,
  emergency,
}

/// Parameters for the `logging/setLevel` request.
class SetLevelRequestParams {
  /// The minimum logging level the client wants to receive.
  final LoggingLevel level;

  const SetLevelRequestParams({required this.level});

  factory SetLevelRequestParams.fromJson(Map<String, dynamic> json) =>
      SetLevelRequestParams(
        level: LoggingLevel.values.byName(json['level'] as String),
      );

  Map<String, dynamic> toJson() => {'level': level.name};
}

/// Request sent from client to enable or adjust logging level from the server.
class JsonRpcSetLevelRequest extends JsonRpcRequest {
  /// The set level parameters.
  final SetLevelRequestParams setParams;

  JsonRpcSetLevelRequest({
    required super.id,
    required this.setParams,
    super.meta,
  }) : super(method: "logging/setLevel", params: setParams.toJson());

  factory JsonRpcSetLevelRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for set level request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcSetLevelRequest(
      id: json['id'],
      setParams: SetLevelRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `notifications/message` (or `logging/message`) notification.
class LoggingMessageNotificationParams {
  /// The severity of this log message.
  final LoggingLevel level;

  /// Optional name of the logger issuing the message.
  final String? logger;

  /// The data to be logged (string, object, etc.).
  final dynamic data;

  const LoggingMessageNotificationParams({
    required this.level,
    this.logger,
    this.data,
  });

  factory LoggingMessageNotificationParams.fromJson(
    Map<String, dynamic> json,
  ) =>
      LoggingMessageNotificationParams(
        level: LoggingLevel.values.byName(json['level'] as String),
        logger: json['logger'] as String?,
        data: json['data'],
      );

  Map<String, dynamic> toJson() => {
        'level': level.name,
        if (logger != null) 'logger': logger,
        'data': data,
      };
}

/// Notification of a log message passed from server to client.
class JsonRpcLoggingMessageNotification extends JsonRpcNotification {
  /// The logging parameters.
  final LoggingMessageNotificationParams logParams;

  JsonRpcLoggingMessageNotification({required this.logParams, super.meta})
      : super(method: "notifications/message", params: logParams.toJson());

  factory JsonRpcLoggingMessageNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for logging message notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcLoggingMessageNotification(
      logParams: LoggingMessageNotificationParams.fromJson(paramsMap),
      meta: meta,
    );
  }
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
            costPriority == null || (costPriority >= 0 && costPriority <= 1)),
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
  /// The type of the content ("text" or "image").
  final String type;

  const SamplingContent({required this.type});

  /// Creates specific subclass from JSON.
  factory SamplingContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'text' => SamplingTextContent.fromJson(json),
      'image' => SamplingImageContent.fromJson(json),
      _ => throw FormatException("Invalid sampling content type: $type"),
    };
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          SamplingTextContent c => {'text': c.text},
          SamplingImageContent c => {'data': c.data, 'mimeType': c.mimeType},
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

/// Role in a sampling message exchange.
enum SamplingMessageRole { user, assistant }

/// Describes a message issued to or received from an LLM API during sampling.
class SamplingMessage {
  /// The role of the message sender.
  final SamplingMessageRole role;

  /// The content of the message (text or image).
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
class CreateMessageRequestParams {
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

  /// Tools available to the LLM.
  final List<Tool>? tools;

  /// Tool choice parameter.
  final Map<String, dynamic>? toolChoice;

  const CreateMessageRequestParams({
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

  factory CreateMessageRequestParams.fromJson(Map<String, dynamic> json) {
    final ctxStr = json['includeContext'] as String?;
    return CreateMessageRequestParams(
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
  final CreateMessageRequestParams createParams;

  JsonRpcCreateMessageRequest({
    required super.id,
    required this.createParams,
    super.meta,
  }) : super(method: "sampling/createMessage", params: createParams.toJson());

  factory JsonRpcCreateMessageRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for create message request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCreateMessageRequest(
      id: json['id'],
      createParams: CreateMessageRequestParams.fromJson(paramsMap),
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
          ResourceReference r => {'uri': r.uri},
          PromptReference p => {'name': p.name},
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
  }) : super(method: "completion/complete", params: completeParams.toJson());

  factory JsonRpcCompleteRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for complete request");
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

/// Base class for input schemas used in elicitation
sealed class InputSchema {
  /// The type of input schema
  final String type;

  /// Description of what this input is for
  final String? description;

  const InputSchema({required this.type, this.description});

  /// Creates a specific InputSchema subclass from JSON
  factory InputSchema.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'boolean' => BooleanInputSchema.fromJson(json),
      'string' => StringInputSchema.fromJson(json),
      'number' => NumberInputSchema.fromJson(json),
      'enum' => EnumInputSchema.fromJson(json),
      _ => throw FormatException('Unknown input schema type: $type'),
    };
  }

  /// Converts to JSON
  Map<String, dynamic> toJson();
}

/// Boolean input schema for yes/no questions
class BooleanInputSchema extends InputSchema {
  /// Default value for the boolean input
  final bool? defaultValue;

  const BooleanInputSchema({
    this.defaultValue,
    super.description,
  }) : super(type: 'boolean');

  factory BooleanInputSchema.fromJson(Map<String, dynamic> json) {
    return BooleanInputSchema(
      defaultValue: json['defaultValue'] as bool?,
      description: json['description'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (description != null) 'description': description,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };
}

/// String input schema for text input with validation
class StringInputSchema extends InputSchema {
  /// Default value for the string input
  final String? defaultValue;

  /// Minimum length constraint
  final int? minLength;

  /// Maximum length constraint
  final int? maxLength;

  /// Regular expression pattern for validation
  final String? pattern;

  const StringInputSchema({
    this.defaultValue,
    this.minLength,
    this.maxLength,
    this.pattern,
    super.description,
  }) : super(type: 'string');

  factory StringInputSchema.fromJson(Map<String, dynamic> json) {
    return StringInputSchema(
      defaultValue: json['defaultValue'] as String?,
      minLength: json['minLength'] as int?,
      maxLength: json['maxLength'] as int?,
      pattern: json['pattern'] as String?,
      description: json['description'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (description != null) 'description': description,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (minLength != null) 'minLength': minLength,
        if (maxLength != null) 'maxLength': maxLength,
        if (pattern != null) 'pattern': pattern,
      };
}

/// Number input schema for numeric input with range constraints
class NumberInputSchema extends InputSchema {
  /// Default value for the number input
  final num? defaultValue;

  /// Minimum value constraint
  final num? minimum;

  /// Maximum value constraint
  final num? maximum;

  const NumberInputSchema({
    this.defaultValue,
    this.minimum,
    this.maximum,
    super.description,
  }) : super(type: 'number');

  factory NumberInputSchema.fromJson(Map<String, dynamic> json) {
    return NumberInputSchema(
      defaultValue: json['defaultValue'] as num?,
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
      description: json['description'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (description != null) 'description': description,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (minimum != null) 'minimum': minimum,
        if (maximum != null) 'maximum': maximum,
      };
}

/// Enum input schema for multiple choice selection
class EnumInputSchema extends InputSchema {
  /// Available options to choose from
  final List<String> enumValues;

  /// Default selected value
  final String? defaultValue;

  /// Whether the enum is titled (visual presentation hint)
  final bool? titled;

  /// Whether the enum is untitled (visual presentation hint)
  final bool? untitled;

  /// Whether the enum allows single selection
  final bool? singleSelect;

  /// Whether the enum allows multiple selection
  final bool? multiSelect;

  const EnumInputSchema({
    required this.enumValues,
    this.defaultValue,
    this.titled,
    this.untitled,
    this.singleSelect,
    this.multiSelect,
    super.description,
  }) : super(type: 'enum');

  factory EnumInputSchema.fromJson(Map<String, dynamic> json) {
    return EnumInputSchema(
      enumValues: (json['enum'] as List<dynamic>).cast<String>(),
      defaultValue: json['defaultValue'] as String?,
      description: json['description'] as String?,
      titled: json['titled'] as bool?,
      untitled: json['untitled'] as bool?,
      singleSelect: json['singleSelect'] as bool?,
      multiSelect: json['multiSelect'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (description != null) 'description': description,
        'enum': enumValues,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (titled != null) 'titled': titled,
        if (untitled != null) 'untitled': untitled,
        if (singleSelect != null) 'singleSelect': singleSelect,
        if (multiSelect != null) 'multiSelect': multiSelect,
      };
}

/// Represents a root directory or file the server can operate on.
class Root {
  /// URI identifying the root (must start with `file://`).
  final String uri;

  /// Optional name for the root.
  final String? name;

  Root({
    required this.uri,
    this.name,
  }) : assert(uri.startsWith("file://"));

  factory Root.fromJson(Map<String, dynamic> json) {
    return Root(
      uri: json['uri'] as String,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uri': uri,
        if (name != null) 'name': name,
      };
}

/// Request sent from server to client to get the list of root URIs.
class JsonRpcListRootsRequest extends JsonRpcRequest {
  const JsonRpcListRootsRequest({required super.id})
      : super(method: "roots/list");

  factory JsonRpcListRootsRequest.fromJson(Map<String, dynamic> json) =>
      JsonRpcListRootsRequest(id: json['id']);
}

/// Result data for a successful `roots/list` request.
class ListRootsResult implements BaseResultData {
  /// The list of roots provided by the client.
  final List<Root> roots;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListRootsResult({required this.roots, this.meta});

  factory ListRootsResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListRootsResult(
      roots: (json['roots'] as List<dynamic>?)
              ?.map((r) => Root.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'roots': roots.map((r) => r.toJson()).toList(),
      };
}

/// Notification from client indicating the list of roots has changed.
class JsonRpcRootsListChangedNotification extends JsonRpcNotification {
  const JsonRpcRootsListChangedNotification()
      : super(method: "notifications/roots/list_changed");

  factory JsonRpcRootsListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcRootsListChangedNotification();
}

/// Parameters for the `elicitation/create` request
class ElicitRequestParams {
  /// The message to present to the user
  final String message;

  /// The JSON Schema defining what type of input to collect
  final Map<String, dynamic>? requestedSchema;

  /// Optional URL to start elicitation from (URL mode)
  final String? url;

  const ElicitRequestParams({
    required this.message,
    this.requestedSchema,
    this.url,
  });

  factory ElicitRequestParams.fromJson(Map<String, dynamic> json) {
    return ElicitRequestParams(
      message: json['message'] as String,
      requestedSchema: json['requestedSchema'] as Map<String, dynamic>?,
      url: json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'message': message,
        if (requestedSchema != null) 'requestedSchema': requestedSchema,
        if (url != null) 'url': url,
      };
}

/// Request sent from server to client to elicit user input
class JsonRpcElicitRequest extends JsonRpcRequest {
  /// The elicit parameters
  final ElicitRequestParams elicitParams;

  JsonRpcElicitRequest({
    required super.id,
    required this.elicitParams,
    super.meta,
  }) : super(method: "elicitation/create", params: elicitParams.toJson());

  factory JsonRpcElicitRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for elicit request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcElicitRequest(
      id: json['id'],
      elicitParams: ElicitRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `elicitation/create` response
class ElicitResult implements BaseResultData {
  /// The action taken by the user: 'accept', 'decline', or 'cancel'
  final String action;

  /// The submitted form data (only present when action is 'accept')
  final Map<String, dynamic>? content;

  /// Optional metadata
  @override
  final Map<String, dynamic>? meta;

  const ElicitResult({
    required this.action,
    this.content,
    this.meta,
  });

  factory ElicitResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ElicitResult(
      action: json['action'] as String,
      content: json['content'] as Map<String, dynamic>?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'action': action,
        if (content != null) 'content': content,
      };

  /// Helper to check if the user accepted the input
  bool get accepted => action == 'accept';

  /// Helper to check if the user declined the input
  bool get declined => action == 'decline';

  /// Helper to check if the user cancelled the input
  bool get cancelled => action == 'cancel';
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
