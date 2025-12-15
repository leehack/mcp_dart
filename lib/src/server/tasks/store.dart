import 'dart:async';

import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';
import 'constants.dart';

// ============================================================================
// Task Store Implementation
// ============================================================================

/// An in-memory implementation of [TaskStore].
class InMemoryTaskStore implements TaskStore {
  final Map<String, Task> _tasks = {};
  final Map<String, BaseResultData> _results = {};
  final Map<String, List<Completer<void>>> _updateResolvers = {};
  Timer? _ttlCleanupTimer;

  InMemoryTaskStore() {
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
        _notifyUpdate(id);
      }
    });
  }

  @override
  Future<ListTasksResult> listTasks(String? cursor, [String? sessionId]) async {
    return ListTasksResult(tasks: _tasks.values.toList());
  }

  /// Cancels a task. Returns true if cancelled, false if not found or already terminal.
  Future<bool> cancelTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    if (task.status.isTerminal) return false;

    await updateTaskStatus(
      taskId,
      TaskStatus.cancelled,
      "Task cancelled by client",
    );
    return true;
  }

  @override
  Future<Task> createTask(
    TaskCreationParams taskParams,
    RequestId requestId,
    Map<String, dynamic> requestData,
    String? sessionId,
  ) async {
    final taskId = generateUUID().replaceAll('-', '');
    final now = DateTime.now().toIso8601String();

    String? name;
    Map<String, dynamic>? input;

    if (requestData['method'] == 'tools/call') {
      final params = requestData['params'] as Map<String, dynamic>?;
      name = params?['name'] as String?;
      input = params?['arguments'] as Map<String, dynamic>?;
    } else if (requestData['name'] != null) {
      // Fallback if requestData is not method/params but direct data
      name = requestData['name'] as String?;
      input = requestData['input'] as Map<String, dynamic>?;
    }

    final task = Task(
      taskId: taskId,
      status: TaskStatus.working,
      statusMessage: "Task started",
      ttl: taskParams.ttl,
      pollInterval: 1000,
      createdAt: now,
      lastUpdatedAt: now,
      meta: {
        'createdFromRequestId': requestId,
        if (name != null) taskNameKey: name,
        if (input != null) taskInputKey: input,
      },
    );
    _tasks[taskId] = task;
    _notifyUpdate(taskId);
    return task;
  }

  @override
  Future<Task?> getTask(String taskId, [String? sessionId]) async {
    return _tasks[taskId];
  }

  @override
  Future<BaseResultData> getTaskResult(
    String taskId, [
    String? sessionId,
  ]) async {
    final result = _results[taskId];
    if (result == null) {
      throw McpError(ErrorCode.invalidParams.value, 'Result not available');
    }
    return result;
  }

  @override
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? message,
    String? sessionId,
  ]) async {
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
    String taskId,
    TaskStatus status,
    BaseResultData result, [
    String? sessionId,
  ]) async {
    _results[taskId] = result;
    await updateTaskStatus(taskId, status, null, sessionId);
  }

  /// Returns a future that completes when the specified task is updated.
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
  }

  void dispose() {
    _ttlCleanupTimer?.cancel();
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
