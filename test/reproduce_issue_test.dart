import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';

class MockMcpServer extends McpServer {
  final List<String> notifications = [];

  MockMcpServer(super.serverInfo);

  @override
  Future<void> notifyTaskStatus({
    required String taskId,
    required TaskStatus status,
    String? statusMessage,
    Map<String, dynamic>? meta,
  }) async {
    notifications.add('taskId: $taskId, status: $status');
  }
}

void main() {
  test('TaskStore instances should be isolated per server', () async {
    final server1 = MockMcpServer(Implementation(name: 's1', version: '1'));
    final store1 = InMemoryTaskStore(server1);

    final server2 = MockMcpServer(Implementation(name: 's2', version: '1'));
    final store2 = InMemoryTaskStore(server2);

    // Create task in store1
    final task1 = await store1.createTask(null, null, null, 'test1', {});

    // Update status in store1
    await store1.updateTaskStatus(task1.taskId, TaskStatus.working);

    // Create task in store2
    final task2 = await store2.createTask(null, null, null, 'test2', {});

    // Update status in store2
    await store2.updateTaskStatus(task2.taskId, TaskStatus.completed);

    // Verify Server 1 only knows about task 1 events
    print('Server 1 notifications: ${server1.notifications}');
    expect(server1.notifications, isNotEmpty);
    expect(server1.notifications.any((n) => n.contains(task1.taskId)), isTrue);
    expect(server1.notifications.any((n) => n.contains(task2.taskId)), isFalse);

    // Verify Server 2 only knows about task 2 events
    print('Server 2 notifications: ${server2.notifications}');
    expect(server2.notifications, isNotEmpty);
    expect(server2.notifications.any((n) => n.contains(task2.taskId)), isTrue);
    expect(server2.notifications.any((n) => n.contains(task1.taskId)), isFalse);
  });
}
