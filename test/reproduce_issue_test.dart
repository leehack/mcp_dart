import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';

class MockTransport implements Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool _started = false;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    sentMessages.add(message);
  }

  @override
  Future<void> close() async {
    _started = false;
    onclose?.call();
  }

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => "mock-session";
}

void main() {
  test('TaskStore instances should be isolated per server', () async {
    final server1 = McpServer(const Implementation(name: 's1', version: '1'));
    final transport1 = MockTransport();
    await server1.connect(transport1);
    final store1 = InMemoryTaskStore(server1);

    final server2 = McpServer(const Implementation(name: 's2', version: '1'));
    final transport2 = MockTransport();
    await server2.connect(transport2);
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
    print('Server 1 notifications: ${transport1.sentMessages.length}');
    expect(transport1.sentMessages, isNotEmpty);

    final s1TaskIds = transport1.sentMessages
        .whereType<JsonRpcTaskStatusNotification>()
        .map((n) => n.statusParams.taskId)
        .toList();

    expect(s1TaskIds, contains(task1.taskId));
    expect(s1TaskIds, isNot(contains(task2.taskId)));

    // Verify Server 2 only knows about task 2 events
    print('Server 2 notifications: ${transport2.sentMessages.length}');
    expect(transport2.sentMessages, isNotEmpty);

    final s2TaskIds = transport2.sentMessages
        .whereType<JsonRpcTaskStatusNotification>()
        .map((n) => n.statusParams.taskId)
        .toList();

    expect(s2TaskIds, contains(task2.taskId));
    expect(s2TaskIds, isNot(contains(task1.taskId)));

    await server1.close();
    await server2.close();
  });
}
