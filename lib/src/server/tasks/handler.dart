import 'dart:async';

import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'constants.dart';
import 'queue.dart';
import 'store.dart';

// ============================================================================
// Task Result Handler
// ============================================================================

/// A handler for a tool that creates and manages tasks.
///
/// This interface defines the contract for tools that can initiate long-running
/// operations and report their status and results asynchronously.
abstract class ToolTaskHandler {
  /// Creates a new task and returns its initial state.
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  );

  /// Retrieves the current status of a task.
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra);

  /// Cancels a running task.
  Future<void> cancelTask(String taskId, RequestHandlerExtra? extra);

  /// Retrieves the final result of a completed task.
  Future<CallToolResult> getTaskResult(
    String taskId,
    RequestHandlerExtra? extra,
  );
}

/// Handles execution and result retrieval for tasks, managing the queue loop.
class TaskResultHandler {
  final InMemoryTaskStore store;
  final InMemoryTaskMessageQueue queue;
  final McpServer server;
  final Map<dynamic, Completer<Map<String, dynamic>>> pendingRequests = {};
  Timer? _cleanupTimer;

  TaskResultHandler(this.store, this.queue, this.server) {
    _startCleanupTimer();
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      // Cleanup logic if needed, or implement request timeouts here
    });
  }

  /// Waits for a task to complete and returns its result.
  /// Handles intermediate requests (sampling, elicitation) from the task.
  Future<CallToolResult> handle(String taskId) async {
    while (true) {
      // Create waiters BEFORE checking state to avoid missing updates race condition
      final updateFuture = store.waitForUpdate(taskId);
      final messageFuture = queue.waitForMessage(taskId);

      final task = await store.getTask(taskId);
      if (task == null) {
        throw McpError(
          ErrorCode.invalidParams.value,
          "Task not found: $taskId",
        );
      }

      // Deliver queued messages (requests from client to server logic?)
      await _deliverQueuedMessages(taskId);

      // Refresh task because _deliverQueuedMessages might have unblocked execution that updated it
      final currentTask = await store.getTask(taskId);
      if (currentTask == null) {
        throw McpError(ErrorCode.invalidParams.value, "Task lost");
      }

      // Check if terminal
      if (currentTask.status.isTerminal) {
        final result = await store.getTaskResult(taskId);

        CallToolResult toolResult;
        if (result is CallToolResult) {
          toolResult = result;
        } else {
          // If we ever support other result types, handle them here.
          // For now, assume CallToolResult as that's what we store.
          throw McpError(
            ErrorCode.internalError.value,
            "Unexpected result type: ${result.runtimeType}",
          );
        }

        // Add related task meta
        final meta = Map<String, dynamic>.from(toolResult.meta ?? {});
        meta[relatedTaskMetaKey] = {'taskId': taskId};

        return CallToolResult(
          content: toolResult.content,
          isError: toolResult.isError,
          meta: meta,
          extra: toolResult.extra,
        );
      }

      // Wait for update or new message
      await Future.any([
        updateFuture,
        messageFuture,
      ]);
    }
  }

  Future<void> _deliverQueuedMessages(String taskId) async {
    while (true) {
      final message = await queue.dequeue(taskId);
      if (message == null) break;

      if (message.type == 'request') {
        Completer<Map<String, dynamic>>? resolver;
        String? originalRequestId;

        if (message is ServerQueuedMessage) {
          resolver = message.resolver;
          originalRequestId = message.originalRequestId;
        }

        if (resolver != null && originalRequestId != null) {
          pendingRequests[originalRequestId] = resolver;
        }

        try {
          final request = message.message as JsonRpcRequest;
          dynamic response;

          if (request.method == 'elicitation/create') {
            final params = ElicitRequestParams.fromJson(request.params!);
            response = await server.experimental.elicitForTask(taskId, params);
          } else if (request.method == 'sampling/createMessage') {
            final params = CreateMessageRequestParams.fromJson(request.params!);
            response =
                await server.experimental.createMessageForTask(taskId, params);
          } else {
            throw Exception("Unknown request method: ${request.method}");
          }

          if (resolver != null && !resolver.isCompleted) {
            resolver.complete(response.toJson());
          }
        } catch (e) {
          if (resolver != null && !resolver.isCompleted) {
            resolver.completeError(e);
          }
        } finally {
          if (originalRequestId != null) {
            pendingRequests.remove(originalRequestId);
          }
        }
      }
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
  }
}
