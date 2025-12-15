import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  test('TaskStore instances should be isolated', () async {
    final store1 = InMemoryTaskStore();
    final store2 = InMemoryTaskStore();

    // Create task in store1
    final task1 = await store1.createTask(
      const TaskCreationParams(),
      1,
      {'name': 'test1'},
      'session1',
    );

    // Create task in store2
    final task2 = await store2.createTask(
      const TaskCreationParams(),
      2,
      {'name': 'test2'},
      'session2',
    );

    expect(await store1.getTask(task1.taskId), isNotNull);
    expect(await store1.getTask(task2.taskId), isNull);

    expect(await store2.getTask(task2.taskId), isNotNull);
    expect(await store2.getTask(task1.taskId), isNull);

    store1.dispose();
    store2.dispose();
  });
}
