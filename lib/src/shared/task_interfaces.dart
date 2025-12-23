import '../types.dart';

/// Interface for storing and retrieving tasks.
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
  Future<void> storeTaskResult(
    String taskId,
    TaskStatus status,
    BaseResultData result, [
    String? sessionId,
  ]);

  /// Retrieves the stored result of a task.
  Future<BaseResultData> getTaskResult(String taskId, [String? sessionId]);

  /// Updates a task's status.
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
    String? sessionId,
  ]);

  /// Lists tasks, optionally starting from a pagination cursor.
  Future<ListTasksResult> listTasks(String? cursor, [String? sessionId]);
}

/// Interface for managing server-initiated messages for tasks.
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

/// Request-scoped TaskStore interface.
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
