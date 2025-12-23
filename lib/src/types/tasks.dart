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
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListTasksRequest(
      id: json['id'],
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
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCancelTaskRequest(
      id: json['id'],
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
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcGetTaskRequest(
      id: json['id'],
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
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcTaskResultRequest(
      id: json['id'],
      resultParams: TaskResultRequest.fromJson(paramsMap),
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
  final BaseResultData result;
  const TaskResultMessage(this.result) : super('result');
}

class TaskErrorMessage extends TaskStreamMessage {
  final Object error;
  const TaskErrorMessage(this.error) : super('error');
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
  final int? ttl;

  /// Suggested time in milliseconds between status checks.
  final int? pollInterval;

  /// ISO 8601 timestamp when the task was created.
  final String? createdAt;

  /// ISO 8601 timestamp when the task status was last updated.
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
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcTaskStatusNotification(
      statusParams: TaskStatusNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
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
