import '../types.dart';
import 'json_rpc.dart';
import 'validation.dart';

/// The current state of a task execution.
enum TaskStatus {
  working,
  inputRequired,
  completed,
  failed,
  cancelled,
}

/// A parsed specific task status string.
typedef TaskStatusString = String;

extension TaskStatusName on TaskStatus {
  String get name {
    switch (this) {
      case TaskStatus.working:
        return 'working';
      case TaskStatus.inputRequired:
        return 'input_required';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.failed:
        return 'failed';
      case TaskStatus.cancelled:
        return 'cancelled';
    }
  }

  static TaskStatus fromString(String status) {
    switch (status) {
      case 'working':
        return TaskStatus.working;
      case 'input_required':
        return TaskStatus.inputRequired;
      case 'completed':
        return TaskStatus.completed;
      case 'failed':
        return TaskStatus.failed;
      case 'cancelled':
        return TaskStatus.cancelled;
      default:
        throw FormatException("Unknown task status: $status");
    }
  }

  /// Returns true if this status represents a terminal state (completed, failed, or cancelled).
  bool get isTerminal =>
      this == TaskStatus.completed ||
      this == TaskStatus.failed ||
      this == TaskStatus.cancelled;
}

/// Represents a task in the system.
class Task implements BaseResultData {
  /// Unique identifier for the task.
  final String taskId;

  /// Current state of the task execution.
  final TaskStatus status;

  /// Optional human-readable message describing the current state.
  final String? statusMessage;

  /// Time in milliseconds from creation before task may be deleted.
  ///
  /// Required by the MCP schema. A null value is serialized explicitly as
  /// `"ttl": null` when the task has no expiry.
  final int? ttl;

  /// Suggested time in milliseconds between status checks.
  final int? pollInterval;

  /// ISO 8601 timestamp when the task was created.
  final String createdAt;

  /// ISO 8601 timestamp when the task status was last updated.
  final String lastUpdatedAt;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const Task({
    required this.taskId,
    required this.status,
    required this.ttl,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.statusMessage,
    this.pollInterval,
    this.meta,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final createdAt = _readRequiredTaskString(json, 'createdAt');
    final lastUpdatedAt = _readRequiredTaskString(json, 'lastUpdatedAt');

    final meta = json['_meta'] as Map<String, dynamic>?;
    return Task(
      taskId: _readRequiredTaskString(json, 'taskId'),
      status: TaskStatusName.fromString(
        _readRequiredTaskString(json, 'status'),
      ),
      statusMessage: _readOptionalTaskString(json, 'statusMessage'),
      ttl: _readTaskInt(json, 'ttl', requiredField: true),
      pollInterval: _readTaskInt(json, 'pollInterval'),
      createdAt: createdAt,
      lastUpdatedAt: lastUpdatedAt,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson({bool includeMeta = true}) => {
        'taskId': taskId,
        'status': status.name,
        if (statusMessage != null) 'statusMessage': statusMessage,
        'ttl': ttl,
        if (pollInterval != null) 'pollInterval': pollInterval,
        'createdAt': createdAt,
        'lastUpdatedAt': lastUpdatedAt,
        if (includeMeta && meta != null) '_meta': meta,
      };

  /// Serializes this task where MCP expects the bare `Task` schema.
  Map<String, dynamic> toBareJson() => toJson(includeMeta: false);
}

String _readRequiredTaskString(
  Map<String, dynamic> json,
  String field, {
  String owner = 'Task',
}) {
  if (!json.containsKey(field)) {
    throw FormatException('$owner.$field is required');
  }
  final value = json[field];
  if (value is! String) {
    throw FormatException('$owner.$field must be a string');
  }
  return value;
}

String? _readOptionalTaskString(
  Map<String, dynamic> json,
  String field, {
  String owner = 'Task',
}) {
  if (!json.containsKey(field)) {
    return null;
  }
  final value = json[field];
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException('$owner.$field must be a string');
}

int? _readTaskInt(
  Map<String, dynamic> json,
  String field, {
  bool requiredField = false,
  String owner = 'Task',
}) {
  if (!json.containsKey(field)) {
    if (requiredField) {
      throw FormatException('$owner.$field is required');
    }
    return null;
  }

  final value = json[field];
  if (value == null || value is int) {
    return value as int?;
  }

  throw FormatException('$owner.$field must be an integer or null');
}

/// Parameters for the `tasks/list` request. Includes pagination.
class ListTasksRequest {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListTasksRequest({this.cursor});

  factory ListTasksRequest.fromJson(Map<String, dynamic> json) =>
      ListTasksRequest(cursor: json['cursor'] as String?);

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available tasks.
class JsonRpcListTasksRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListTasksRequest listParams;

  JsonRpcListTasksRequest({
    required super.id,
    ListTasksRequest? params,
    super.meta,
  })  : listParams = params ?? const ListTasksRequest(),
        super(method: Method.tasksList, params: params?.toJson());

  factory JsonRpcListTasksRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = extractRequestMeta(json);
    return JsonRpcListTasksRequest(
      id: parseRequestId(json['id']),
      params: paramsMap == null ? null : ListTasksRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `tasks/list` request.
class ListTasksResult implements BaseResultData {
  /// The list of tasks found.
  final List<Task> tasks;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListTasksResult({required this.tasks, this.nextCursor, this.meta});

  factory ListTasksResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    final tasks = json['tasks'];
    if (tasks is! List) {
      throw const FormatException('ListTasksResult.tasks is required');
    }
    return ListTasksResult(
      tasks:
          tasks.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList(),
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toBareJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
        if (meta != null) '_meta': meta,
      };
}

/// Parameters for the `tasks/cancel` request.
class CancelTaskRequest {
  /// The ID of the task to cancel.
  final String taskId;

  const CancelTaskRequest({required this.taskId});

  factory CancelTaskRequest.fromJson(Map<String, dynamic> json) =>
      CancelTaskRequest(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Request sent from client to cancel a task.
class JsonRpcCancelTaskRequest extends JsonRpcRequest {
  /// The cancel parameters.
  final CancelTaskRequest cancelParams;

  JsonRpcCancelTaskRequest({
    required super.id,
    required this.cancelParams,
    super.meta,
  }) : super(method: Method.tasksCancel, params: cancelParams.toJson());

  factory JsonRpcCancelTaskRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for cancel task request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcCancelTaskRequest(
      id: parseRequestId(json['id']),
      cancelParams: CancelTaskRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `tasks/get` request.
class GetTaskRequest {
  /// The ID of the task to get.
  final String taskId;

  const GetTaskRequest({required this.taskId});

  factory GetTaskRequest.fromJson(Map<String, dynamic> json) =>
      GetTaskRequest(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Request sent from client to get task status.
class JsonRpcGetTaskRequest extends JsonRpcRequest {
  /// The get task parameters.
  final GetTaskRequest getParams;

  JsonRpcGetTaskRequest({
    required super.id,
    required this.getParams,
    super.meta,
  }) : super(method: Method.tasksGet, params: getParams.toJson());

  factory JsonRpcGetTaskRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for get task request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcGetTaskRequest(
      id: parseRequestId(json['id']),
      getParams: GetTaskRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `tasks/result` request.
class TaskResultRequest {
  /// The ID of the task to get results for.
  final String taskId;

  const TaskResultRequest({required this.taskId});

  factory TaskResultRequest.fromJson(Map<String, dynamic> json) =>
      TaskResultRequest(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Request sent from client to retrieve task results.
class JsonRpcTaskResultRequest extends JsonRpcRequest {
  /// The task result parameters.
  final TaskResultRequest resultParams;

  JsonRpcTaskResultRequest({
    required super.id,
    required this.resultParams,
    super.meta,
  }) : super(method: Method.tasksResult, params: resultParams.toJson());

  factory JsonRpcTaskResultRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for task result request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcTaskResultRequest(
      id: parseRequestId(json['id']),
      resultParams: TaskResultRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the MCP Tasks extension `tasks/update` request.
class UpdateTaskRequest {
  /// The ID of the task to update.
  final String taskId;

  /// Responses to outstanding task input requests.
  final InputResponses inputResponses;

  const UpdateTaskRequest({
    required this.taskId,
    required this.inputResponses,
  });

  factory UpdateTaskRequest.fromJson(Map<String, dynamic> json) {
    final inputResponses = InputResponse.mapFromJson(
      json['inputResponses'],
      'UpdateTaskRequest.inputResponses',
    );
    if (inputResponses == null) {
      throw const FormatException(
        'UpdateTaskRequest.inputResponses is required',
      );
    }

    return UpdateTaskRequest(
      taskId: _readRequiredTaskString(
        json,
        'taskId',
        owner: 'UpdateTaskRequest',
      ),
      inputResponses: inputResponses,
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'inputResponses': InputResponse.mapToJson(inputResponses),
      };
}

/// Request sent by a client to provide input for a task.
class JsonRpcUpdateTaskRequest extends JsonRpcRequest {
  /// The update parameters.
  final UpdateTaskRequest updateParams;

  JsonRpcUpdateTaskRequest({
    required super.id,
    required this.updateParams,
    super.meta,
  }) : super(method: Method.tasksUpdate, params: updateParams.toJson());

  factory JsonRpcUpdateTaskRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for update task request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcUpdateTaskRequest(
      id: parseRequestId(json['id']),
      updateParams: UpdateTaskRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for task creation when augmenting requests.
class TaskCreation {
  /// Requested duration in milliseconds to retain task from creation.
  final int? ttl;

  const TaskCreation({this.ttl});

  factory TaskCreation.fromJson(Map<String, dynamic> json) =>
      TaskCreation(ttl: json['ttl'] as int?);

  Map<String, dynamic> toJson() => {
        if (ttl != null) 'ttl': ttl,
      };
}

/// Result data for a task creation response.
class CreateTaskResult implements BaseResultData {
  /// The created task.
  final Task task;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const CreateTaskResult({required this.task, this.meta});

  factory CreateTaskResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return CreateTaskResult(
      task: Task.fromJson(json['task'] as Map<String, dynamic>),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'task': task.toBareJson(),
        if (meta != null) '_meta': meta,
      };
}

/// Message yielded by the task stream helper.
sealed class TaskStreamMessage {
  final String type;
  const TaskStreamMessage(this.type);
}

class TaskCreatedMessage extends TaskStreamMessage {
  final Task task;
  const TaskCreatedMessage(this.task) : super('taskCreated');
}

class TaskStatusMessage extends TaskStreamMessage {
  final Task task;
  const TaskStatusMessage(this.task) : super('taskStatus');
}

class TaskResultMessage extends TaskStreamMessage {
  final BaseResultData result;
  const TaskResultMessage(this.result) : super('result');
}

class TaskErrorMessage extends TaskStreamMessage {
  final Object error;
  const TaskErrorMessage(this.error) : super('error');
}

/// Task state shape used by the MCP Tasks extension.
class TaskExtensionTask {
  /// Unique identifier for the task.
  final String taskId;

  /// Current state of the task execution.
  final TaskStatus status;

  /// Optional human-readable message describing the current state.
  final String? statusMessage;

  /// ISO 8601 timestamp when the task was created.
  final String createdAt;

  /// ISO 8601 timestamp when the task was last updated.
  final String lastUpdatedAt;

  /// Time in milliseconds from creation before task may be deleted.
  final int? ttlMs;

  /// Suggested time in milliseconds between status checks.
  final int? pollIntervalMs;

  /// Outstanding input requests when [status] is `input_required`.
  final InputRequests? inputRequests;

  /// Final result when [status] is `completed`.
  final Map<String, dynamic>? result;

  /// JSON-RPC error when [status] is `failed`.
  final JsonRpcErrorData? error;

  const TaskExtensionTask({
    required this.taskId,
    required this.status,
    required this.createdAt,
    required this.lastUpdatedAt,
    required this.ttlMs,
    this.statusMessage,
    this.pollIntervalMs,
    this.inputRequests,
    this.result,
    this.error,
  });

  factory TaskExtensionTask.fromJson(Map<String, dynamic> json) {
    return TaskExtensionTask(
      taskId: _readRequiredTaskString(
        json,
        'taskId',
        owner: 'TaskExtensionTask',
      ),
      status: TaskStatusName.fromString(
        _readRequiredTaskString(json, 'status', owner: 'TaskExtensionTask'),
      ),
      statusMessage: _readOptionalTaskString(
        json,
        'statusMessage',
        owner: 'TaskExtensionTask',
      ),
      createdAt: _readRequiredTaskString(
        json,
        'createdAt',
        owner: 'TaskExtensionTask',
      ),
      lastUpdatedAt: _readRequiredTaskString(
        json,
        'lastUpdatedAt',
        owner: 'TaskExtensionTask',
      ),
      ttlMs: _readTaskInt(
        json,
        'ttlMs',
        requiredField: true,
        owner: 'TaskExtensionTask',
      ),
      pollIntervalMs: _readTaskInt(
        json,
        'pollIntervalMs',
        owner: 'TaskExtensionTask',
      ),
      inputRequests: InputRequest.mapFromJson(
        json['inputRequests'],
        'TaskExtensionTask.inputRequests',
      ),
      result: _readOptionalJsonObject(
        json['result'],
        'TaskExtensionTask.result',
      ),
      error: json['error'] == null
          ? null
          : JsonRpcErrorData.fromJson(
              _readRequiredJsonObject(
                json['error'],
                'TaskExtensionTask.error',
              ),
            ),
    );
  }

  Map<String, dynamic> toJson({String? resultType}) => {
        if (resultType != null) 'resultType': resultType,
        'taskId': taskId,
        'status': status.name,
        if (statusMessage != null) 'statusMessage': statusMessage,
        'createdAt': createdAt,
        'lastUpdatedAt': lastUpdatedAt,
        'ttlMs': ttlMs,
        if (pollIntervalMs != null) 'pollIntervalMs': pollIntervalMs,
        if (inputRequests != null)
          'inputRequests': InputRequest.mapToJson(inputRequests!),
        if (result != null)
          'result': readJsonObject(result, 'TaskExtensionTask.result'),
        if (error != null) 'error': error!.toJson(),
      };
}

/// `resultType: "task"` response from the MCP Tasks extension.
class CreateTaskExtensionResult implements BaseResultData {
  /// The created task state.
  final TaskExtensionTask task;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const CreateTaskExtensionResult({required this.task, this.meta});

  factory CreateTaskExtensionResult.fromJson(Map<String, dynamic> json) {
    if (json['resultType'] != resultTypeTask) {
      throw const FormatException(
        'CreateTaskExtensionResult.resultType must be task',
      );
    }
    return CreateTaskExtensionResult(
      task: TaskExtensionTask.fromJson(json),
      meta: _readOptionalJsonObject(
        json['_meta'],
        'CreateTaskExtensionResult._meta',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...task.toJson(resultType: resultTypeTask),
        if (meta != null)
          '_meta': readJsonObject(meta, 'CreateTaskExtensionResult._meta'),
      };
}

/// `tasks/get` result from the MCP Tasks extension.
class GetTaskExtensionResult implements BaseResultData {
  /// The current task state.
  final TaskExtensionTask task;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const GetTaskExtensionResult({required this.task, this.meta});

  factory GetTaskExtensionResult.fromJson(Map<String, dynamic> json) {
    if (json['resultType'] != resultTypeComplete) {
      throw const FormatException(
        'GetTaskExtensionResult.resultType must be complete',
      );
    }
    return GetTaskExtensionResult(
      task: TaskExtensionTask.fromJson(json),
      meta: _readOptionalJsonObject(
        json['_meta'],
        'GetTaskExtensionResult._meta',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...task.toJson(resultType: resultTypeComplete),
        if (meta != null)
          '_meta': readJsonObject(meta, 'GetTaskExtensionResult._meta'),
      };
}

/// Empty `tasks/update` or `tasks/cancel` acknowledgement result.
class TaskExtensionAcknowledgementResult implements BaseResultData {
  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const TaskExtensionAcknowledgementResult({this.meta});

  factory TaskExtensionAcknowledgementResult.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json['resultType'] != resultTypeComplete) {
      throw const FormatException(
        'TaskExtensionAcknowledgementResult.resultType must be complete',
      );
    }
    return TaskExtensionAcknowledgementResult(
      meta: _readOptionalJsonObject(
        json['_meta'],
        'TaskExtensionAcknowledgementResult._meta',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'resultType': resultTypeComplete,
        if (meta != null)
          '_meta': readJsonObject(
            meta,
            'TaskExtensionAcknowledgementResult._meta',
          ),
      };
}

/// Parameters for the `notifications/tasks/status` notification.
class TaskStatusNotification {
  /// The ID of the task.
  final String taskId;

  /// Current state of the task execution.
  final TaskStatus status;

  /// Optional human-readable message describing the current state.
  final String? statusMessage;

  /// Time in milliseconds from creation before task may be deleted.
  ///
  /// Required by the MCP schema. A null value is serialized explicitly as
  /// `"ttl": null` when the task has no expiry.
  final int? ttl;

  /// Suggested time in milliseconds between status checks.
  final int? pollInterval;

  /// ISO 8601 timestamp when the task was created.
  ///
  /// Required by the MCP schema and required for serialization. The constructor
  /// keeps this nullable for source compatibility with earlier SDK versions.
  final String? createdAt;

  /// ISO 8601 timestamp when the task status was last updated.
  ///
  /// Required by the MCP schema and required for serialization. The constructor
  /// keeps this nullable for source compatibility with earlier SDK versions.
  final String? lastUpdatedAt;

  const TaskStatusNotification({
    required this.taskId,
    required this.status,
    this.statusMessage,
    this.ttl,
    this.pollInterval,
    this.createdAt,
    this.lastUpdatedAt,
  });

  factory TaskStatusNotification.fromJson(Map<String, dynamic> json) {
    return TaskStatusNotification(
      taskId: _readRequiredTaskString(
        json,
        'taskId',
        owner: 'TaskStatusNotification',
      ),
      status: TaskStatusName.fromString(
        _readRequiredTaskString(
          json,
          'status',
          owner: 'TaskStatusNotification',
        ),
      ),
      statusMessage: _readOptionalTaskString(
        json,
        'statusMessage',
        owner: 'TaskStatusNotification',
      ),
      ttl: _readTaskInt(
        json,
        'ttl',
        requiredField: true,
        owner: 'TaskStatusNotification',
      ),
      pollInterval: _readTaskInt(
        json,
        'pollInterval',
        owner: 'TaskStatusNotification',
      ),
      createdAt: _readRequiredTaskString(
        json,
        'createdAt',
        owner: 'TaskStatusNotification',
      ),
      lastUpdatedAt: _readRequiredTaskString(
        json,
        'lastUpdatedAt',
        owner: 'TaskStatusNotification',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'status': status.name,
        if (statusMessage != null) 'statusMessage': statusMessage,
        'ttl': ttl,
        if (pollInterval != null) 'pollInterval': pollInterval,
        'createdAt': _requireTaskStatusNotificationString(
          createdAt,
          'createdAt',
        ),
        'lastUpdatedAt': _requireTaskStatusNotificationString(
          lastUpdatedAt,
          'lastUpdatedAt',
        ),
      };
}

String _requireTaskStatusNotificationString(String? value, String field) {
  if (value == null) {
    throw StateError('TaskStatusNotification.$field is required');
  }
  return value;
}

/// Notification from receiver indicating a task status has changed.
class JsonRpcTaskStatusNotification extends JsonRpcNotification {
  /// The task status parameters.
  final TaskStatusNotification statusParams;

  JsonRpcTaskStatusNotification({required this.statusParams, super.meta})
      : super(
          method: Method.notificationsTasksStatus,
          params: statusParams.toJson(),
        );

  factory JsonRpcTaskStatusNotification.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException(
        "Missing params for task status notification",
      );
    }
    final meta = _readOptionalJsonObject(
      paramsMap['_meta'],
      'JsonRpcTaskStatusNotification._meta',
    );
    return JsonRpcTaskStatusNotification(
      statusParams: TaskStatusNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// `notifications/tasks` notification from the MCP Tasks extension.
class JsonRpcTaskNotification extends JsonRpcNotification {
  /// The task state carried by the notification.
  final TaskExtensionTask task;

  JsonRpcTaskNotification({required this.task, super.meta})
      : super(method: Method.notificationsTasks, params: task.toJson());

  factory JsonRpcTaskNotification.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for task notification");
    }
    return JsonRpcTaskNotification(
      task: TaskExtensionTask.fromJson(paramsMap),
      meta: _readOptionalJsonObject(
        paramsMap['_meta'],
        'JsonRpcTaskNotification._meta',
      ),
    );
  }
}

Map<String, dynamic> _readRequiredJsonObject(Object? value, String field) {
  return readJsonObject(value, field);
}

Map<String, dynamic>? _readOptionalJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return _readRequiredJsonObject(value, field);
}

/// Deprecated alias for [ListTasksRequest].
@Deprecated('Use ListTasksRequest instead')
typedef ListTasksRequestParams = ListTasksRequest;

/// Deprecated alias for [CancelTaskRequest].
@Deprecated('Use CancelTaskRequest instead')
typedef CancelTaskRequestParams = CancelTaskRequest;

/// Deprecated alias for [GetTaskRequest].
@Deprecated('Use GetTaskRequest instead')
typedef GetTaskRequestParams = GetTaskRequest;

/// Deprecated alias for [TaskResultRequest].
@Deprecated('Use TaskResultRequest instead')
typedef TaskResultRequestParams = TaskResultRequest;

/// Deprecated alias for [TaskStatusNotification].
@Deprecated('Use TaskStatusNotification instead')
typedef TaskStatusNotificationParams = TaskStatusNotification;

/// Deprecated alias for [TaskCreation].
@Deprecated('Use TaskCreation instead')
typedef TaskCreationParams = TaskCreation;
