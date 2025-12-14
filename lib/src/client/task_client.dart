import 'dart:async';
import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/types.dart';

/// Wrapper for raw JSON result to satisfy BaseResultData constraint.
class _RawResult implements BaseResultData {
  final Map<String, dynamic> data;

  @override
  final Map<String, dynamic>? meta;

  _RawResult(this.data, {this.meta});

  @override
  Map<String, dynamic> toJson() => data;
}

/// Helper to handle task-augmented tool calls and interactions.
///
/// This client wrapper abstracts the complexity of task-based tool calls,
/// which may either return an immediate result or create a long-running task.
/// It handles polling for task status and retrieving the final result.
class TaskClient {
  final Client client;

  TaskClient(this.client);

  /// Calls a tool and returns a stream of status updates and the final result.
  ///
  /// This handles both immediate results (yielding a single [TaskResultMessage])
  /// and long-running tasks (yielding [TaskCreatedMessage], multiple
  /// [TaskStatusMessage]s, and finally [TaskResultMessage]).
  Stream<TaskStreamMessage> callToolStream(
    String name,
    Map<String, dynamic> arguments, {
    Map<String, dynamic>? meta,
  }) async* {
    try {
      // 1. Call the tool using generic request to capture 'task' field if present.
      // 1. Call the tool using generic request to capture 'task' field if present.
      // We cannot use client.callTool() because it forces CallToolResult return type
      // which ignores the 'task' field.
      final callParams =
          CallToolRequestParams(name: name, arguments: arguments);
      final req =
          JsonRpcCallToolRequest(id: -1, callParams: callParams, meta: meta);

      final response = await client.request<_RawResult>(
        req,
        (json) => _RawResult(json, meta: json['_meta']),
      );

      final data = response.data;

      // Check if it created a task
      if (data.containsKey('task')) {
        final taskResult = CreateTaskResult.fromJson(data);
        yield TaskCreatedMessage(taskResult.task);

        // Start the result promise (this triggers the task processing on server if needed)
        final resultFuture = _getTaskResult(taskResult.task.taskId);

        // Poll for status updates while waiting for result
        await for (final msg in _monitorTaskWithResult(
          taskResult.task.taskId,
          taskResult.task,
          resultFuture,
        )) {
          yield msg;
        }
      } else {
        // Immediate result
        final toolResult = CallToolResult.fromJson(data);
        yield TaskResultMessage(toolResult);
      }
    } catch (e) {
      yield TaskErrorMessage(e);
    }
  }

  Stream<TaskStreamMessage> _monitorTaskWithResult(
    String taskId,
    Task initialTask,
    Future<CallToolResult> resultFuture,
  ) async* {
    var currentTask = initialTask;
    var resultCompleted = false;
    CallToolResult? finalResult;
    Object? finalError;

    // Hook up completion
    resultFuture.then((r) {
      resultCompleted = true;
      finalResult = r;
    }).catchError((e) {
      resultCompleted = true;
      finalError = e;
    });

    while (!resultCompleted) {
      // Poll task status immediately
      try {
        currentTask = await _getTask(taskId);
        yield TaskStatusMessage(currentTask);
      } catch (e) {
        // Only yield error if not just a momentary glitch?
        // For now, assume critical error if polling fails repeatedly or at all
        yield TaskErrorMessage(e);
        break;
      }

      // If result finished during poll
      if (resultCompleted) break;

      // Wait before next poll
      final interval = currentTask.pollInterval ?? 1000;
      await Future.delayed(Duration(milliseconds: interval));
    }

    if (finalError != null) {
      yield TaskErrorMessage(finalError!);
    } else if (finalResult != null) {
      yield TaskResultMessage(finalResult!);
    }
  }

  Future<Task> _getTask(String taskId) async {
    final req = JsonRpcGetTaskRequest(
      id: -1,
      getParams: GetTaskRequestParams(taskId: taskId),
    );

    return await client.request<Task>(
      req,
      (json) => Task.fromJson(json),
    );
  }

  Future<CallToolResult> _getTaskResult(String taskId) async {
    final req = JsonRpcTaskResultRequest(
      id: -1,
      resultParams: TaskResultRequestParams(taskId: taskId),
    );
    return await client.request<CallToolResult>(
      req,
      (json) => CallToolResult.fromJson(json),
    );
  }

  /// List all tasks on the server
  Future<List<Task>> listTasks() async {
    final req = JsonRpcListTasksRequest(id: -1);
    final result = await client.request<ListTasksResult>(
      req,
      (json) => ListTasksResult.fromJson(json),
    );
    return result.tasks;
  }

  /// Cancel a task by ID
  Future<void> cancelTask(String taskId) async {
    final req = JsonRpcCancelTaskRequest(
      id: -1,
      cancelParams: CancelTaskRequestParams(taskId: taskId),
    );
    await client.request<EmptyResult>(
      req,
      (json) => const EmptyResult(),
    );
  }
}
