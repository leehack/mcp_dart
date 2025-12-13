import 'dart:async';

import 'package:mcp_dart/src/types.dart';

// ============================================================================
// Task Queue
// ============================================================================

/// A message in the task queue, waiting to be processed.
class QueuedMessage {
  /// The type of message: 'request' | 'notification' | 'response' | 'error'.
  final String type;

  /// The underlying JSON-RPC message.
  final JsonRpcMessage message;

  /// The timestamp when the message was enqueued (milliseconds since epoch).
  final int timestamp;

  /// Completer to resolve when the message is processed (optional).
  final Completer<Map<String, dynamic>>? resolver;

  /// The original request ID associated with this message (if any).
  final RequestId? originalRequestId;

  QueuedMessage({
    required this.type,
    required this.message,
    required this.timestamp,
    this.resolver,
    this.originalRequestId,
  });
}

/// A queue for managing task-related messages, supporting waiters.
class TaskMessageQueue {
  final Map<String, List<QueuedMessage>> _queues = {};
  final Map<String, List<Completer<void>>> _waitResolvers = {};

  List<QueuedMessage> _getQueue(String taskId) {
    return _queues.putIfAbsent(taskId, () => []);
  }

  /// Enqueues a message for a specific task and notifies any waiters.
  void enqueue(String taskId, QueuedMessage message) {
    final queue = _getQueue(taskId);
    queue.add(message);
    _notifyWaiters(taskId);
  }

  /// Dequeues the next message for a task, returning null if empty.
  QueuedMessage? dequeue(String taskId) {
    final queue = _getQueue(taskId);
    if (queue.isEmpty) return null;
    return queue.removeAt(0);
  }

  /// Returns a Future that completes when a message is available for the task.
  /// If a message is already available, returns a completed Future immediately.
  Future<void> waitForMessage(String taskId) {
    final queue = _getQueue(taskId);
    if (queue.isNotEmpty) return Future.value();

    final completer = Completer<void>();
    _waitResolvers.putIfAbsent(taskId, () => []).add(completer);
    return completer.future;
  }

  void _notifyWaiters(String taskId) {
    final waiters = _waitResolvers.remove(taskId);
    if (waiters != null) {
      for (final completer in waiters) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
  }

  /// Clears all queues and waiters.
  void dispose() {
    _queues.clear();
    for (var waiters in _waitResolvers.values) {
      for (var completer in waiters) {
        if (!completer.isCompleted) {
          // completer.completeError(StateError('Queue disposed')); // Optional: could error instead
          completer.complete();
        }
      }
    }
    _waitResolvers.clear();
  }
}
