import 'dart:async';

import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'constants.dart';

// ============================================================================
// Task Store Interface & Implementation
// ============================================================================

/// Interface for storing and managing tasks.
///
/// Users can implement this to back tasks with a database or other persistent storage.
abstract class TaskStore {
  /// Returns all tasks.
  FutureOr<List<Task>> getAllTasks();

  /// Retrieves a specific task by ID.
  FutureOr<Task?> getTask(String taskId);

  /// Creates a new task.
  Future<Task> createTask(
    int? ttl,
    int? pollInterval,
    RequestId? requestId,
    String name,
    Map<String, dynamic> input,
  );

  /// Cancels a task. Returns true if cancelled, false if not found or already terminal.
  Future<bool> cancelTask(String taskId);

  /// Updates the status of a task.
  Future<void> updateTaskStatus(String taskId, TaskStatus status,
      [String? message]);

  /// Stores the result of a task and marks it as completed (or failed).
  Future<void> storeTaskResult(
      String taskId, TaskStatus status, CallToolResult result);

  /// Retrieves the result of a completed task.
  FutureOr<CallToolResult?> getTaskResult(String taskId);

  /// Returns a future that completes when the specified task is updated.
  Future<void> waitForUpdate(String taskId);

  /// Cleans up resources.
  void dispose();
}

/// An in-memory implementation of [TaskStore].
class InMemoryTaskStore implements TaskStore {
  final McpServer server;
  final Map<String, Task> _tasks = {};
  final Map<String, CallToolResult> _results = {};
  final Map<String, List<Completer<void>>> _updateResolvers = {};
  Timer? _ttlCleanupTimer;

  InMemoryTaskStore(this.server) {
    _startTtlCleanup();
  }

  void _startTtlCleanup() {
    _ttlCleanupTimer?.cancel();
    _ttlCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      final expiredIds = <String>[];
      for (final entry in _tasks.entries) {
        final task = entry.value;
        if (task.ttl != null && task.createdAt != null) {
          final created = DateTime.parse(task.createdAt!);
          if (now.difference(created).inMilliseconds > task.ttl!) {
            expiredIds.add(entry.key);
          }
        }
      }
      for (final id in expiredIds) {
        _tasks.remove(id);
        _results.remove(id);
        _notifyUpdate(id); // Notify waiters that task is gone (or changed)
      }
    });
  }

  @override
  List<Task> getAllTasks() {
    return _tasks.values.toList();
  }

  @override
  Future<bool> cancelTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    if (task.status.isTerminal) return false;

    await updateTaskStatus(
        taskId, TaskStatus.cancelled, "Task cancelled by client");
    return true;
  }

  @override
  Future<Task> createTask(
    int? ttl,
    int? pollInterval,
    RequestId? requestId,
    String name,
    Map<String, dynamic> input,
  ) async {
    final taskId = generateUUID().replaceAll('-', '');
    final now = DateTime.now().toIso8601String();
    final task = Task(
      taskId: taskId,
      status: TaskStatus.working,
      statusMessage: "Task started",
      ttl: ttl,
      pollInterval: pollInterval,
      createdAt: now,
      lastUpdatedAt: now,
      meta: {
        if (requestId != null) 'createdFromRequestId': requestId,
        taskNameKey: name,
        taskInputKey: input,
      },
    );
    _tasks[taskId] = task;
    _notifyUpdate(taskId);
    return task;
  }

  @override
  Task? getTask(String taskId) {
    return _tasks[taskId];
  }

  @override
  CallToolResult? getTaskResult(String taskId) {
    return _results[taskId];
  }

  @override
  Future<void> updateTaskStatus(String taskId, TaskStatus status,
      [String? message]) async {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = Task(
        taskId: task.taskId,
        status: status,
        statusMessage: message ?? task.statusMessage,
        ttl: task.ttl,
        pollInterval: task.pollInterval,
        createdAt: task.createdAt,
        lastUpdatedAt: DateTime.now().toIso8601String(),
        meta: task.meta,
      );
      _notifyUpdate(taskId);
    }
  }

  @override
  Future<void> storeTaskResult(
      String taskId, TaskStatus status, CallToolResult result) async {
    _results[taskId] = result;
    await updateTaskStatus(taskId, status);
  }

  @override
  Future<void> waitForUpdate(String taskId) {
    final completer = Completer<void>();
    _updateResolvers.putIfAbsent(taskId, () => []).add(completer);
    return completer.future;
  }

  void _notifyUpdate(String taskId) {
    final waiters = _updateResolvers.remove(taskId);
    if (waiters != null) {
      for (final completer in waiters) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }

    // Send task status notification to the server
    final task = _tasks[taskId];
    if (task != null) {
      try {
        server.notifyTaskStatus(
          taskId: taskId,
          status: task.status,
          statusMessage: task.statusMessage,
        );
      } catch (e) {
        // Ignore errors broadcasting
      }
    }
  }

  @override
  void dispose() {
    _ttlCleanupTimer?.cancel();
    // Clear waiters
    for (var waiters in _updateResolvers.values) {
      for (var completer in waiters) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
    _updateResolvers.clear();
  }
}
