import '../types.dart';

/// Metadata key for associating a request/notification with a task.
const String relatedTaskMetadataKey = 'io.modelcontextprotocol/related-task';

/// Legacy metadata key retained for backward compatibility.
@Deprecated('Use relatedTaskMetadataKey instead')
const String legacyRelatedTaskMetadataKey = 'relatedTask';

/// Interface for storing and retrieving legacy task-augmented requests.
///
/// This API preserves MCP initialization-era task behavior. It is not a
/// persistence adapter for the independent `io.modelcontextprotocol/tasks`
/// extension. A dual-era server may configure both, but must register and
/// implement the modern extension handlers separately.
abstract class TaskStore {
  /// Creates a new task with the given creation parameters.
  ///
  /// [taskParams] - The task creation parameters from the request.
  /// [requestId] - The ID of the request that initiated the task.
  /// [requestData] - The original request method and params.
  /// [sessionId] - The session ID of the client.
  Future<Task> createTask(
    TaskCreation taskParams,
    RequestId requestId,
    Map<String, dynamic> requestData,
    String? sessionId,
  );

  /// Gets the current status of a task.
  Future<Task?> getTask(String taskId, [String? sessionId]);

  /// Stores the result of a task and sets its final status.
  ///
  /// Implementations must treat terminal tasks (`completed`, `failed`, or
  /// `cancelled`) as immutable and ignore attempts to replace their status or
  /// result.
  Future<void> storeTaskResult(
    String taskId,
    TaskStatus status,
    BaseResultData result, [
    String? sessionId,
  ]);

  /// Retrieves the stored result of a task.
  Future<BaseResultData> getTaskResult(String taskId, [String? sessionId]);

  /// Updates a task's status.
  ///
  /// Implementations must treat terminal tasks (`completed`, `failed`, or
  /// `cancelled`) as immutable and ignore attempts to transition them to any
  /// later status.
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
    String? sessionId,
  ]);

  /// Lists tasks, optionally starting from a pagination cursor.
  Future<ListTasksResult> listTasks(String? cursor, [String? sessionId]);
}

/// Interface for managing legacy server-initiated task messages.
abstract class TaskMessageQueue {
  /// Enqueues a message for delivery.
  Future<void> enqueue(
    String taskId,
    QueuedMessage message,
    String? sessionId, [
    int? maxSize,
  ]);

  /// Dequeues the next message for a task.
  Future<QueuedMessage?> dequeue(String taskId, [String? sessionId]);

  /// Dequeues all messages for a task (e.g., during cleanup).
  Future<List<QueuedMessage>> dequeueAll(String taskId, [String? sessionId]);
}

/// A message queued for side-channel delivery.
class QueuedMessage {
  final String type; // 'request', 'response', 'notification', 'error'
  final JsonRpcMessage message;
  final int timestamp;

  QueuedMessage({
    required this.type,
    required this.message,
    required this.timestamp,
  });
}

/// Request-scoped interface for legacy task augmentation.
abstract class RequestTaskStore {
  Future<Task> createTask(TaskCreation taskParams);
  Future<Task> getTask(String taskId);
  Future<void> storeTaskResult(
    String taskId,
    TaskStatus status,
    BaseResultData result,
  );
  Future<BaseResultData> getTaskResult(String taskId);
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
  ]);
  Future<ListTasksResult> listTasks([String? cursor]);
}

/// Metadata about a related task.
class RelatedTaskMetadata {
  final String taskId;

  const RelatedTaskMetadata({required this.taskId});

  factory RelatedTaskMetadata.fromJson(Map<String, dynamic> json) =>
      RelatedTaskMetadata(taskId: json['taskId'] as String);

  Map<String, dynamic> toJson() => {'taskId': taskId};
}

/// Generic authentication info.
class AuthInfo {
  final Map<String, dynamic> data;
  const AuthInfo(this.data);
}

/// Generic request info.
class RequestInfo {
  final Map<String, dynamic> data;
  const RequestInfo(this.data);
}
