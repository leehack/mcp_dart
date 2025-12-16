import 'dart:async';

import 'package:mcp_dart/src/shared/task_interfaces.dart';

// ============================================================================
// Task Queue
// ============================================================================

/// A message in the task queue, with server-specific extensions.
class ServerQueuedMessage extends QueuedMessage {
  /// Completer to resolve when the message is processed (optional).
  final Completer<Map<String, dynamic>>? resolver;

  /// The original request ID associated with this message (if any).
  final String? originalRequestId;

  ServerQueuedMessage({
    required super.type,
    required super.message,
    required super.timestamp,
    this.resolver,
    this.originalRequestId,
  });
}

/// A queue for managing task-related messages, supporting waiters.
class InMemoryTaskMessageQueue implements TaskMessageQueue {
  final Map<String, List<QueuedMessage>> _queues = {};
  final Map<String, List<Completer<void>>> _waitResolvers = {};

  @override
  Future<void> enqueue(
    String taskId,
    QueuedMessage message,
    String? sessionId, [
    int? maxSize,
  ]) async {
    final queue = _queues.putIfAbsent(taskId, () => []);
    queue.add(message);
    if (maxSize != null && queue.length > maxSize) {
      queue.removeAt(0);
    }
    _notifyWaiters(taskId);
  }

  @override
  Future<QueuedMessage?> dequeue(String taskId, [String? sessionId]) async {
    final queue = _queues[taskId];
    if (queue == null || queue.isEmpty) return null;
    return queue.removeAt(0);
  }

  @override
  Future<List<QueuedMessage>> dequeueAll(
    String taskId, [
    String? sessionId,
  ]) async {
    final queue = _queues.remove(taskId);
    return queue ?? [];
  }

  /// Returns a Future that completes when a message is available for the task.
  /// If a message is already available, returns a completed Future immediately.
  Future<void> waitForMessage(String taskId) {
    final queue = _queues[taskId];
    if (queue != null && queue.isNotEmpty) return Future.value();

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
          completer.complete();
        }
      }
    }
    _waitResolvers.clear();
  }
}
