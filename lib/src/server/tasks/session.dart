import 'dart:async';

import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'queue.dart';
import 'store.dart';

// ============================================================================
// Task Session
// ============================================================================

/// Represents a session of a running task, allowing interaction with the server.
class TaskSession {
  final McpServer server;
  final String taskId;
  final TaskStore store;
  final TaskMessageQueue queue;
  int _requestCounter = 0;

  TaskSession(this.server, this.taskId, this.store, this.queue);

  String _nextRequestId() => 'task-$taskId-${++_requestCounter}';

  /// Requests input from the client (Elicitation).
  Future<ElicitResult> elicit(
      String message, Map<String, dynamic> requestedSchema) async {
    await store.updateTaskStatus(taskId, TaskStatus.inputRequired);

    final requestId = _nextRequestId();
    final params =
        ElicitRequestParams(message: message, requestedSchema: requestedSchema);

    final jsonRpcRequest =
        JsonRpcElicitRequest(id: requestId, elicitParams: params);

    final completer = Completer<Map<String, dynamic>>();

    queue.enqueue(
        taskId,
        QueuedMessage(
          type: 'request',
          message: jsonRpcRequest,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          resolver: completer,
          originalRequestId: requestId,
        ));

    try {
      final json = await completer.future;
      await store.updateTaskStatus(taskId, TaskStatus.working);
      return ElicitResult.fromJson(json);
    } catch (e) {
      await store.updateTaskStatus(taskId, TaskStatus.working);
      rethrow;
    }
  }

  /// Requests an LLM sampling message (Sampling).
  Future<CreateMessageResult> createMessage(
      List<SamplingMessage> messages, int maxTokens) async {
    await store.updateTaskStatus(taskId, TaskStatus.inputRequired);

    final requestId = _nextRequestId();
    final params = CreateMessageRequestParams(
      messages: messages,
      maxTokens: maxTokens,
    );

    final jsonRpcRequest =
        JsonRpcCreateMessageRequest(id: requestId, createParams: params);

    final completer = Completer<Map<String, dynamic>>();

    queue.enqueue(
        taskId,
        QueuedMessage(
          type: 'request',
          message: jsonRpcRequest,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          resolver: completer,
          originalRequestId: requestId,
        ));

    try {
      final json = await completer.future;
      await store.updateTaskStatus(taskId, TaskStatus.working);
      return CreateMessageResult.fromJson(json);
    } catch (e) {
      await store.updateTaskStatus(taskId, TaskStatus.working);
      rethrow;
    }
  }
}
