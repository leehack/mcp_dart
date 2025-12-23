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
  final McpClient client;

  TaskClient(this.client);

  /// Calls a tool and returns a stream of status updates and the final result.
  ///
  /// This handles both immediate results (yielding a single [TaskResultMessage])
  /// and long-running tasks (yielding [TaskCreatedMessage], multiple
  /// [TaskStatusMessage]s, and finally [TaskResultMessage]).
  ///
  /// The [task] parameter is used for task augmentation. Pass task creation
  /// parameters (e.g., `{'ttl': 60000, 'pollInterval': 50}`) to request
  /// task-based execution from tools that support it.
  Stream<TaskStreamMessage> callToolStream(
    String name,
    Map<String, dynamic> arguments, {
    Map<String, dynamic>? task,
  }) async* {
    try {
      // 1. Call the tool using generic request to capture 'task' field if present.
      // We cannot use client.callTool() because it forces CallToolResult return type
      // which ignores the 'task' field.
      final callParamsJson =
          CallToolRequest(name: name, arguments: arguments).toJson();

      // Add task augmentation params directly to params (per MCP spec)
      final paramsWithTask = <String, dynamic>{
        ...callParamsJson,
        if (task != null) 'task': task,
      };

      final req = JsonRpcCallToolRequest(
        id: -1,
        params: paramsWithTask,
      );

      final response = await client.request<_RawResult>(
        req,
        (json) => _RawResult(json, meta: json['_meta']),
      );

      final data = response.data;

      // Check if it created a task
      if (data.containsKey('task')) {
        final taskResult = CreateTaskResult.fromJson(data);
        yield TaskCreatedMessage(taskResult.task);

        // Poll for status updates until terminal, then fetch result
        await for (final msg in _monitorTask(
          taskResult.task.taskId,
          taskResult.task,
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

  Stream<TaskStreamMessage> _monitorTask(
    String taskId,
    Task initialTask,
  ) async* {
    var currentTask = initialTask;

    // Poll until task reaches terminal state
    while (!currentTask.status.isTerminal) {
      // Wait before next poll
      final interval = currentTask.pollInterval ?? 1000;
      await Future.delayed(Duration(milliseconds: interval));

      // Poll task status
      try {
        currentTask = await _getTask(taskId);
        yield TaskStatusMessage(currentTask);
      } catch (e) {
        yield TaskErrorMessage(e);
        return;
      }

      // When input_required, call tasks/result to deliver queued messages
      // (elicitation, sampling) via SSE and block until terminal.
      // The server will send elicitation/sampling requests as side-channel
      // messages, and the Client's request handlers will process them.
      if (currentTask.status == TaskStatus.inputRequired) {
        try {
          final result = await _getTaskResult(taskId);
          yield TaskResultMessage(result);
          return; // tasks/result blocks until terminal, so we're done
        } catch (e) {
          yield TaskErrorMessage(e);
          return;
        }
      }
    }

    // Task is terminal - fetch the result
    if (currentTask.status == TaskStatus.completed) {
      try {
        final result = await _getTaskResult(taskId);
        yield TaskResultMessage(result);
      } catch (e) {
        yield TaskErrorMessage(e);
      }
    } else if (currentTask.status == TaskStatus.failed) {
      yield TaskErrorMessage(
        Exception(
          'Task failed: ${currentTask.statusMessage ?? "Unknown error"}',
        ),
      );
    } else if (currentTask.status == TaskStatus.cancelled) {
      yield TaskErrorMessage(Exception('Task was cancelled'));
    }
  }

  Future<Task> _getTask(String taskId) async {
    final req = JsonRpcGetTaskRequest(
      id: -1,
      getParams: GetTaskRequest(taskId: taskId),
    );

    return await client.request<Task>(
      req,
      (json) => Task.fromJson(json),
    );
  }

  Future<CallToolResult> _getTaskResult(String taskId) async {
    final req = JsonRpcTaskResultRequest(
      id: -1,
      resultParams: TaskResultRequest(taskId: taskId),
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
      cancelParams: CancelTaskRequest(taskId: taskId),
    );
    await client.request<EmptyResult>(
      req,
      (json) => const EmptyResult(),
    );
  }
}
