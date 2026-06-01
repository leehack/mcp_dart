import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('MCP Tasks extension capabilities', () {
    test('declares task extension support', () {
      final extensions = withMcpTasksExtension({
        'example/extension': {'enabled': true},
      });

      expect(extensions[mcpTasksExtensionId], <String, dynamic>{});
      expect(extensions['example/extension'], {'enabled': true});
      expect(
        ClientCapabilities(extensions: extensions).supportsTasksExtension,
        isTrue,
      );
      expect(
        ServerCapabilities(extensions: extensions).supportsTasksExtension,
        isTrue,
      );
    });
  });

  group('Task extension wire types', () {
    test('serializes create task results with flat resultType task shape', () {
      const result = CreateTaskExtensionResult(
        task: TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.working,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:00:00Z',
          ttlMs: 60000,
          pollIntervalMs: 5000,
        ),
        meta: {'trace': 'abc'},
      );

      final json = result.toJson();
      expect(json['resultType'], resultTypeTask);
      expect(json['taskId'], 'task-1');
      expect(json['ttlMs'], 60000);
      expect(json['pollIntervalMs'], 5000);
      expect(json['_meta'], {'trace': 'abc'});

      final parsed = CreateTaskExtensionResult.fromJson(json);
      expect(parsed.task.status, TaskStatus.working);
      expect(parsed.task.ttlMs, 60000);
    });

    test('serializes tasks/get input required results', () {
      final result = GetTaskExtensionResult(
        task: TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.inputRequired,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:01:00Z',
          ttlMs: null,
          inputRequests: {
            'approval': InputRequest.elicit(
              ElicitRequest.form(
                message: 'Approve deployment?',
                requestedSchema: JsonSchema.object(
                  properties: {'approved': JsonSchema.boolean()},
                  required: ['approved'],
                ),
              ),
            ),
          },
        ),
      );

      final json = result.toJson();
      expect(json['resultType'], resultTypeComplete);
      expect(json['status'], 'input_required');
      expect(json['ttlMs'], isNull);
      expect(
        json['inputRequests']['approval']['method'],
        Method.elicitationCreate,
      );

      final parsed = GetTaskExtensionResult.fromJson(json);
      expect(
        parsed.task.inputRequests!['approval']!.elicitParams.message,
        'Approve deployment?',
      );
    });

    test('serializes tasks/update requests with input responses', () {
      final request = JsonRpcUpdateTaskRequest(
        id: 7,
        updateParams: UpdateTaskRequest(
          taskId: 'task-1',
          inputResponses: {
            'approval': InputResponse.fromResult(
              const ElicitResult(
                action: 'accept',
                content: {'approved': true},
              ),
            ),
          },
        ),
      );

      final json = request.toJson();
      expect(json['method'], Method.tasksUpdate);
      expect(json['params']['taskId'], 'task-1');
      expect(json['params']['inputResponses']['approval']['action'], 'accept');

      final parsed = JsonRpcMessage.fromJson(json) as JsonRpcUpdateTaskRequest;
      expect(parsed.updateParams.taskId, 'task-1');
      expect(
        parsed.updateParams.inputResponses['approval']!.toJson()['content'],
        {'approved': true},
      );
    });

    test('serializes task update and cancel acknowledgements', () {
      const result = TaskExtensionAcknowledgementResult(
        meta: {'trace': 'abc'},
      );

      final json = result.toJson();
      expect(json['resultType'], resultTypeComplete);
      expect(json['_meta'], {'trace': 'abc'});

      final parsed = TaskExtensionAcknowledgementResult.fromJson(json);
      expect(parsed.meta, {'trace': 'abc'});
    });

    test('rejects non-JSON task extension object values', () {
      final taskJson = {
        'taskId': 'task-1',
        'status': 'completed',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:02:00Z',
        'ttlMs': 60000,
        'result': {'bad': Object()},
      };

      expect(
        () => TaskExtensionTask.fromJson(taskJson),
        throwsFormatException,
      );
      expect(
        () => const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.completed,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: 60000,
          result: {'bad': Object()},
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => TaskExtensionAcknowledgementResult.fromJson({
          'resultType': resultTypeComplete,
          '_meta': {'bad': Object()},
        }),
        throwsFormatException,
      );
      expect(
        () => const TaskExtensionAcknowledgementResult(
          meta: {'bad': Object()},
        ).toJson(),
        throwsFormatException,
      );
    });

    test('serializes notifications/tasks with detailed task state', () {
      final notification = JsonRpcTaskNotification(
        task: const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.completed,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: 60000,
          result: {
            'content': [
              {'type': 'text', 'text': 'done'},
            ],
          },
        ),
        meta: const {McpMetaKey.subscriptionId: 'sub-1'},
      );

      final json = notification.toJson();
      expect(json['method'], Method.notificationsTasks);
      expect(json['params']['resultType'], isNull);
      expect(json['params']['result']['content'][0]['text'], 'done');
      expect(json['params']['_meta'][McpMetaKey.subscriptionId], 'sub-1');

      final parsed = JsonRpcMessage.fromJson(json) as JsonRpcTaskNotification;
      expect(parsed.task.status, TaskStatus.completed);
      expect(parsed.task.result!['content'][0]['text'], 'done');
    });

    test('rejects malformed task extension payloads', () {
      final updateParams = {
        'taskId': 'task-1',
        'inputResponses': <String, dynamic>{},
      };
      final taskParams = {
        'taskId': 'task-1',
        'status': 'working',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:00:01Z',
        'ttlMs': null,
      };

      expect(
        () => CreateTaskExtensionResult.fromJson(
          const {
            'resultType': resultTypeComplete,
            'taskId': 'task-1',
          },
        ),
        throwsFormatException,
      );
      expect(
        () => UpdateTaskRequest.fromJson(
          const {'taskId': 'task-1'},
        ),
        throwsFormatException,
      );
      expect(
        () => TaskExtensionAcknowledgementResult.fromJson(
          const {'resultType': resultTypeInputRequired},
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcUpdateTaskRequest.fromJson(
          const {
            'jsonrpc': jsonRpcVersion,
            'id': 1,
            'method': Method.tasksUpdate,
            'params': 'bad',
          },
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcUpdateTaskRequest.fromJson(
          const {
            'jsonrpc': jsonRpcVersion,
            'id': 1,
            'method': Method.tasksUpdate,
            'params': null,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcUpdateTaskRequest.fromJson({
          'jsonrpc': '1.0',
          'id': 1,
          'method': Method.tasksUpdate,
          'params': updateParams,
        }),
        throwsFormatException,
      );
      expect(
        () => JsonRpcUpdateTaskRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.tasksGet,
          'params': updateParams,
        }),
        throwsFormatException,
      );
      expect(
        () => JsonRpcTaskNotification.fromJson(
          const {
            'jsonrpc': jsonRpcVersion,
            'method': Method.notificationsTasks,
            'params': 'bad',
          },
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcTaskNotification.fromJson(
          const {
            'jsonrpc': jsonRpcVersion,
            'method': Method.notificationsTasks,
            'params': null,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcTaskNotification.fromJson({
          'jsonrpc': '1.0',
          'method': Method.notificationsTasks,
          'params': taskParams,
        }),
        throwsFormatException,
      );
      expect(
        () => JsonRpcTaskNotification.fromJson({
          'jsonrpc': jsonRpcVersion,
          'method': Method.notificationsTasksStatus,
          'params': taskParams,
        }),
        throwsFormatException,
      );
    });
  });
}
