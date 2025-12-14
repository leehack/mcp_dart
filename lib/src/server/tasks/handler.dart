import 'dart:async';

import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'constants.dart';
import 'queue.dart';
import 'store.dart';

// ============================================================================
// Task Result Handler
// ============================================================================

/// Handles execution and result retrieval for tasks, managing the queue loop.
class TaskResultHandler {
  final TaskStore store;
  final TaskMessageQueue queue;
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
            ErrorCode.invalidParams.value, "Task not found: $taskId");
      }

      // Deliver queued messages (requests from client to server logic?)
      // Actually, this delivers messages FROM the task execution context (if it was external)
      // In the current architecture:
      // Client -> [elicitation/submit] -> Server (TaskSession) -> Queue
      // TaskResultHandler (execution loop) <- Queue
      await _deliverQueuedMessages(taskId);

      // Refresh task because _deliverQueuedMessages might have unblocked execution that updated it
      final currentTask = await store.getTask(taskId);
      if (currentTask == null) {
        throw McpError(ErrorCode.invalidParams.value, "Task lost");
      }

      // Check if terminal
      if (currentTask.status.isTerminal) {
        final result = await store.getTaskResult(taskId);
        if (result == null) {
          return CallToolResult.fromContent(content: [
            TextContent(text: "Task completed but no result found")
          ]);
        }

        // Add related task meta
        final meta = Map<String, dynamic>.from(result.meta ?? {});
        meta[relatedTaskMetaKey] = {'taskId': taskId};

        // Return structured or unstructured result based on what was stored
        if (result.structuredContent.isNotEmpty) {
          return CallToolResult.fromStructuredContent(
            structuredContent: result.structuredContent,
            unstructuredFallback: result.content,
            meta: meta,
          );
        } else {
          return CallToolResult.fromContent(
            content: result.content,
            isError: result.isError,
            meta: meta,
          );
        }
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
      final message = queue.dequeue(taskId);
      if (message == null) break;

      if (message.type == 'request') {
        if (message.resolver != null && message.originalRequestId != null) {
          pendingRequests[message.originalRequestId] = message.resolver!;
        }

        try {
          final request = message.message as JsonRpcRequest;
          dynamic response;

          if (request.method == 'elicitation/create') {
            final params = ElicitRequestParams.fromJson(request.params!);
            response = await _elicit(server, params, taskId);
          } else if (request.method == 'sampling/createMessage') {
            final params = CreateMessageRequestParams.fromJson(request.params!);
            response = await _createMessage(server, params, taskId);
          } else {
            throw Exception("Unknown request method: ${request.method}");
          }

          if (message.resolver != null && !message.resolver!.isCompleted) {
            message.resolver!.complete(response.toJson());
          }
        } catch (e) {
          if (message.resolver != null && !message.resolver!.isCompleted) {
            message.resolver!.completeError(e);
          }
        } finally {
          if (message.originalRequestId != null) {
            pendingRequests.remove(message.originalRequestId);
          }
        }
      }
    }
  }

  // Helpers to call server methods but inject relatedTask meta
  Future<ElicitResult> _elicit(
      McpServer server, ElicitRequestParams params, String taskId) async {
    final req = JsonRpcElicitRequest(id: -1, elicitParams: params, meta: {
      relatedTaskMetaKey: {'taskId': taskId}
    });
    return server.server.request(req, (json) => ElicitResult.fromJson(json));
  }

  Future<CreateMessageResult> _createMessage(McpServer server,
      CreateMessageRequestParams params, String taskId) async {
    final req =
        JsonRpcCreateMessageRequest(id: -1, createParams: params, meta: {
      relatedTaskMetaKey: {'taskId': taskId}
    });
    return server.server
        .request(req, (json) => CreateMessageResult.fromJson(json));
  }

  void dispose() {
    _cleanupTimer?.cancel();
  }
}
