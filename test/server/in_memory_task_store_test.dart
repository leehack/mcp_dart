import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryTaskStore', () {
    late InMemoryTaskStore store;

    setUp(() {
      store = InMemoryTaskStore();
    });

    tearDown(() {
      store.dispose();
    });

    group('createTask', () {
      test('creates task with unique ID', () async {
        final task1 = await store.createTask(
          const TaskCreationParams(),
          1,
          {
            'method': 'tools/call',
            'params': {'name': 'tool1'},
          },
          'session1',
        );
        final task2 = await store.createTask(
          const TaskCreationParams(),
          2,
          {
            'method': 'tools/call',
            'params': {'name': 'tool2'},
          },
          'session1',
        );

        expect(task1.taskId, isNotEmpty);
        expect(task2.taskId, isNotEmpty);
        expect(task1.taskId, isNot(equals(task2.taskId)));
      });

      test('creates task with default status working', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {'name': 'test'},
          null,
        );
        expect(task.status, equals(TaskStatus.working));
        expect(task.statusMessage, equals('Task started'));
      });

      test('creates task with TTL from params', () async {
        final task = await store.createTask(
          const TaskCreationParams(ttl: 60000),
          1,
          {'name': 'test'},
          null,
        );
        expect(task.ttl, equals(60000));
      });

      test('extracts tool name and arguments from tools/call request',
          () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {
            'method': 'tools/call',
            'params': {
              'name': 'my_tool',
              'arguments': {'arg1': 'value1'},
            },
          },
          null,
        );
        expect(task.meta?['name'], equals('my_tool'));
        expect(task.meta?['input'], equals({'arg1': 'value1'}));
      });
    });

    group('getTask', () {
      test('returns task by ID', () async {
        final created = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );
        final retrieved = await store.getTask(created.taskId);
        expect(retrieved, isNotNull);
        expect(retrieved!.taskId, equals(created.taskId));
      });

      test('returns null for non-existent task', () async {
        final result = await store.getTask('non-existent-id');
        expect(result, isNull);
      });
    });

    group('updateTaskStatus', () {
      test('updates task status', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        await store.updateTaskStatus(task.taskId, TaskStatus.completed);
        final updated = await store.getTask(task.taskId);
        expect(updated!.status, equals(TaskStatus.completed));
      });

      test('updates task status with message', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        await store.updateTaskStatus(
          task.taskId,
          TaskStatus.inputRequired,
          'Waiting for input',
        );
        final updated = await store.getTask(task.taskId);
        expect(updated!.status, equals(TaskStatus.inputRequired));
        expect(updated.statusMessage, equals('Waiting for input'));
      });

      test('updates lastUpdatedAt timestamp', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );
        final originalUpdated = task.lastUpdatedAt;

        await Future.delayed(const Duration(milliseconds: 10));
        await store.updateTaskStatus(task.taskId, TaskStatus.completed);

        final updated = await store.getTask(task.taskId);
        expect(updated!.lastUpdatedAt, isNot(equals(originalUpdated)));
      });

      test('does nothing for non-existent task', () async {
        // Should not throw
        await store.updateTaskStatus('non-existent', TaskStatus.completed);
      });
    });

    group('storeTaskResult', () {
      test('stores result and updates status', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        final result = CallToolResult.fromContent([
          const TextContent(text: 'Result data'),
        ]);
        await store.storeTaskResult(task.taskId, TaskStatus.completed, result);

        final updated = await store.getTask(task.taskId);
        expect(updated!.status, equals(TaskStatus.completed));

        final storedResult = await store.getTaskResult(task.taskId);
        expect(storedResult, isNotNull);
      });
    });

    group('getTaskResult', () {
      test('throws for task without result', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        expect(
          () => store.getTaskResult(task.taskId),
          throwsA(isA<McpError>()),
        );
      });

      test('returns stored result', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        final result = CallToolResult.fromContent([
          const TextContent(text: 'Done'),
        ]);
        await store.storeTaskResult(task.taskId, TaskStatus.completed, result);

        final retrieved = await store.getTaskResult(task.taskId);
        expect(retrieved, isA<CallToolResult>());
      });
    });

    group('listTasks', () {
      test('returns empty list when no tasks', () async {
        final result = await store.listTasks(null);
        expect(result.tasks, isEmpty);
      });

      test('returns all created tasks', () async {
        await store.createTask(const TaskCreationParams(), 1, {}, null);
        await store.createTask(const TaskCreationParams(), 2, {}, null);
        await store.createTask(const TaskCreationParams(), 3, {}, null);

        final result = await store.listTasks(null);
        expect(result.tasks, hasLength(3));
      });
    });

    group('cancelTask', () {
      test('cancels active task', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        final cancelled = await store.cancelTask(task.taskId);
        expect(cancelled, isTrue);

        final updated = await store.getTask(task.taskId);
        expect(updated!.status, equals(TaskStatus.cancelled));
      });

      test('returns false for non-existent task', () async {
        final cancelled = await store.cancelTask('non-existent');
        expect(cancelled, isFalse);
      });

      test('returns false for already completed task', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );
        await store.updateTaskStatus(task.taskId, TaskStatus.completed);

        final cancelled = await store.cancelTask(task.taskId);
        expect(cancelled, isFalse);
      });
    });

    group('waitForUpdate', () {
      test('completes when task is updated', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        final completer = Completer<void>();
        store.waitForUpdate(task.taskId).then((_) {
          completer.complete();
        });

        // Update should trigger completion
        await store.updateTaskStatus(task.taskId, TaskStatus.completed);

        await expectLater(
          completer.future.timeout(const Duration(seconds: 1)),
          completes,
        );
      });

      test('completes multiple waiters', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        final completer1 = Completer<void>();
        final completer2 = Completer<void>();

        store.waitForUpdate(task.taskId).then((_) => completer1.complete());
        store.waitForUpdate(task.taskId).then((_) => completer2.complete());

        await store.updateTaskStatus(task.taskId, TaskStatus.completed);

        await expectLater(completer1.future, completes);
        await expectLater(completer2.future, completes);
      });
    });

    group('dispose', () {
      test('completes pending waiters', () async {
        final task = await store.createTask(
          const TaskCreationParams(),
          1,
          {},
          null,
        );

        final completer = Completer<void>();
        store.waitForUpdate(task.taskId).then((_) => completer.complete());

        store.dispose();

        await expectLater(
          completer.future.timeout(const Duration(seconds: 1)),
          completes,
        );
      });
    });
  });
}
