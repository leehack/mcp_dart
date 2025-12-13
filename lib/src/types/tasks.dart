import '../types.dart';

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
  final int? ttl;

  /// Suggested time in milliseconds between status checks.
  final int? pollInterval;

  /// ISO 8601 timestamp when the task was created.
  final String?
      createdAt; // Spec implies defined, but check optionality. Schema usually defines required. Task definition: taskId, status (implied required). Others optional? "createdAt: ISO 8601 timestamp". "optional" not explicitly stated for createdAt, but likely required for accounting. I'll make it optional to be safe or required if I'm sure. I'll make it optional.

  /// ISO 8601 timestamp when the task status was last updated.
  final String? lastUpdatedAt;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const Task({
    required this.taskId,
    required this.status,
    this.statusMessage,
    this.ttl,
    this.pollInterval,
    this.createdAt,
    this.lastUpdatedAt,
    this.meta,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return Task(
      taskId: json['taskId'] as String,
      status: TaskStatusName.fromString(json['status'] as String),
      statusMessage: json['statusMessage'] as String?,
      ttl: json['ttl'] as int?,
      pollInterval: json['pollInterval'] as int?,
      createdAt: json['createdAt'] as String?,
      lastUpdatedAt: json['lastUpdatedAt'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'status': status.name,
        if (statusMessage != null) 'statusMessage': statusMessage,
        'ttl': ttl,
        'pollInterval': pollInterval,
        if (createdAt != null) 'createdAt': createdAt,
        if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt,
        if (meta != null) '_meta': meta,
      };
}

/// Parameters for the `tasks/list` request. Includes pagination.
class ListTasksRequestParams {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListTasksRequestParams({this.cursor});

  factory ListTasksRequestParams.fromJson(Map<String, dynamic> json) =>
      ListTasksRequestParams(cursor: json['cursor'] as String?);

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available tasks.
class JsonRpcListTasksRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListTasksRequestParams listParams;

  JsonRpcListTasksRequest({
    required super.id,
    ListTasksRequestParams? params,
    super.meta,
  })  : listParams = params ?? const ListTasksRequestParams(),
        super(method: Method.tasksList, params: params?.toJson());

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
    return ListTasksResult(
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
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

/// Parameters for the `tasks/cancel` request.
class CancelTaskRequestParams {
  /// The ID of the task to cancel.
  final String taskId;

  const CancelTaskRequestParams({required this.taskId});

  factory CancelTaskRequestParams.fromJson(Map<String, dynamic> json) =>
      CancelTaskRequestParams(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Request sent from client to cancel a task.
class JsonRpcCancelTaskRequest extends JsonRpcRequest {
  /// The cancel parameters.
  final CancelTaskRequestParams cancelParams;

  JsonRpcCancelTaskRequest({
    required super.id,
    required this.cancelParams,
    super.meta,
  }) : super(method: Method.tasksCancel, params: cancelParams.toJson());

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

/// Parameters for the `tasks/get` request.
class GetTaskRequestParams {
  /// The ID of the task to get.
  final String taskId;

  const GetTaskRequestParams({required this.taskId});

  factory GetTaskRequestParams.fromJson(Map<String, dynamic> json) =>
      GetTaskRequestParams(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Request sent from client to get task status.
class JsonRpcGetTaskRequest extends JsonRpcRequest {
  /// The get task parameters.
  final GetTaskRequestParams getParams;

  JsonRpcGetTaskRequest({
    required super.id,
    required this.getParams,
    super.meta,
  }) : super(method: Method.tasksGet, params: getParams.toJson());

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

/// Parameters for the `tasks/result` request.
class TaskResultRequestParams {
  /// The ID of the task to get results for.
  final String taskId;

  const TaskResultRequestParams({required this.taskId});

  factory TaskResultRequestParams.fromJson(Map<String, dynamic> json) =>
      TaskResultRequestParams(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Request sent from client to retrieve task results.
class JsonRpcTaskResultRequest extends JsonRpcRequest {
  /// The task result parameters.
  final TaskResultRequestParams resultParams;

  JsonRpcTaskResultRequest({
    required super.id,
    required this.resultParams,
    super.meta,
  }) : super(method: Method.tasksResult, params: resultParams.toJson());

  factory JsonRpcTaskResultRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw FormatException("Missing params for task result request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcTaskResultRequest(
      id: json['id'],
      resultParams: TaskResultRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for task creation when augmenting requests.
class TaskCreationParams {
  /// Requested duration in milliseconds to retain task from creation.
  final int? ttl;

  const TaskCreationParams({this.ttl});

  factory TaskCreationParams.fromJson(Map<String, dynamic> json) =>
      TaskCreationParams(ttl: json['ttl'] as int?);

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
        'task': task.toJson(),
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
  final CallToolResult result;
  const TaskResultMessage(this.result) : super('result');
}

class TaskErrorMessage extends TaskStreamMessage {
  final Object error;
  const TaskErrorMessage(this.error) : super('error');
}

/// Parameters for the `notifications/tasks/status` notification.
class TaskStatusNotificationParams {
  /// The ID of the task.
  final String taskId;

  /// Current state of the task execution.
  final TaskStatus status;

  /// Optional human-readable message describing the current state.
  final String? statusMessage;

  /// Time in milliseconds from creation before task may be deleted.
  final int? ttl;

  /// Suggested time in milliseconds between status checks.
  final int? pollInterval;

  /// ISO 8601 timestamp when the task was created.
  final String? createdAt;

  /// ISO 8601 timestamp when the task status was last updated.
  final String? lastUpdatedAt;

  const TaskStatusNotificationParams({
    required this.taskId,
    required this.status,
    this.statusMessage,
    this.ttl,
    this.pollInterval,
    this.createdAt,
    this.lastUpdatedAt,
  });

  factory TaskStatusNotificationParams.fromJson(Map<String, dynamic> json) {
    return TaskStatusNotificationParams(
      taskId: json['taskId'] as String,
      status: TaskStatusName.fromString(json['status'] as String),
      statusMessage: json['statusMessage'] as String?,
      ttl: json['ttl'] as int?,
      pollInterval: json['pollInterval'] as int?,
      createdAt: json['createdAt'] as String?,
      lastUpdatedAt: json['lastUpdatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'status': status.name,
        if (statusMessage != null) 'statusMessage': statusMessage,
        if (ttl != null) 'ttl': ttl,
        if (pollInterval != null) 'pollInterval': pollInterval,
        if (createdAt != null) 'createdAt': createdAt,
        if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt,
      };
}

/// Notification from receiver indicating a task status has changed.
class JsonRpcTaskStatusNotification extends JsonRpcNotification {
  /// The task status parameters.
  final TaskStatusNotificationParams statusParams;

  JsonRpcTaskStatusNotification({required this.statusParams, super.meta})
      : super(
            method: Method.notificationsTasksStatus,
            params: statusParams.toJson());

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
