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

    test('requires prefixed extension identifiers', () {
      const validExtensions = {
        'example/extension': {'enabled': true},
      };

      expect(
        ClientCapabilities.fromJson(
          const {'extensions': validExtensions},
        ).extensions,
        validExtensions,
      );
      expect(
        ServerCapabilities.fromJson(
          const {'extensions': validExtensions},
        ).extensions,
        validExtensions,
      );
      expect(
        const ClientCapabilities(extensions: validExtensions).toJson(),
        {'extensions': validExtensions},
      );
      expect(
        const ServerCapabilities(extensions: validExtensions).toJson(),
        {'extensions': validExtensions},
      );

      for (final parse in <void Function()>[
        () => ClientCapabilities.fromJson(
              const {
                'extensions': {
                  'unprefixed': <String, dynamic>{},
                },
              },
            ),
        () => ServerCapabilities.fromJson(
              const {
                'extensions': {
                  'unprefixed': <String, dynamic>{},
                },
              },
            ),
      ]) {
        expect(parse, throwsFormatException);
      }
      for (final serialize in <void Function()>[
        () => const ClientCapabilities(
              extensions: {'unprefixed': <String, dynamic>{}},
            ).toJson(),
        () => const ServerCapabilities(
              extensions: {'unprefixed': <String, dynamic>{}},
            ).toJson(),
      ]) {
        expect(serialize, throwsArgumentError);
      }
    });

    test('requires an empty official tasks extension settings object', () {
      for (final parse in <void Function()>[
        () => ClientCapabilities.fromJson(
              const {
                'extensions': {
                  mcpTasksExtensionId: {'enabled': true},
                },
              },
            ),
        () => ServerCapabilities.fromJson(
              const {
                'extensions': {
                  mcpTasksExtensionId: {'enabled': true},
                },
              },
            ),
      ]) {
        expect(parse, throwsFormatException);
      }
      for (final serialize in <void Function()>[
        () => const ClientCapabilities(
              extensions: {
                mcpTasksExtensionId: {'enabled': true},
              },
            ).toJson(),
        () => const ServerCapabilities(
              extensions: {
                mcpTasksExtensionId: {'enabled': true},
              },
            ).toJson(),
      ]) {
        expect(serialize, throwsArgumentError);
      }
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

    test('uses integer milliseconds for task timing fields', () {
      final parsed = TaskExtensionTask.fromJson(const {
        'taskId': 'task-1',
        'status': 'working',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:00:01Z',
        'ttlMs': 60000.0,
        'pollIntervalMs': 5000.0,
      });
      expect(parsed.ttlMs, 60000);
      expect(parsed.pollIntervalMs, 5000);

      for (final field in const ['ttlMs', 'pollIntervalMs']) {
        expect(
          () => TaskExtensionTask.fromJson({
            'taskId': 'task-1',
            'status': 'working',
            'createdAt': '2026-07-28T00:00:00Z',
            'lastUpdatedAt': '2026-07-28T00:00:01Z',
            'ttlMs': field == 'ttlMs' ? 1.5 : null,
            if (field == 'pollIntervalMs') 'pollIntervalMs': 1.5,
          }),
          throwsFormatException,
          reason: field,
        );
      }
    });

    test('keeps create task results base-only', () {
      const task = TaskExtensionTask(
        taskId: 'task-1',
        status: TaskStatus.completed,
        statusMessage: 'ready',
        createdAt: '2026-07-28T00:00:00Z',
        lastUpdatedAt: '2026-07-28T00:01:00Z',
        ttlMs: 60000,
        pollIntervalMs: 1,
        inputRequests: {},
        result: {'content': 'must be omitted'},
        error: JsonRpcErrorData(
          code: -32000,
          message: 'must be omitted',
        ),
      );

      final json = const CreateTaskExtensionResult(task: task).toJson();
      expect(json['resultType'], resultTypeTask);
      expect(json, isNot(contains('inputRequests')));
      expect(json, isNot(contains('result')));
      expect(json, isNot(contains('error')));

      final parsed = CreateTaskExtensionResult.fromJson(json);
      expect(parsed.task.status, TaskStatus.completed);
      expect(parsed.task.statusMessage, 'ready');
      expect(parsed.task.inputRequests, isNull);
      expect(parsed.task.result, isNull);
      expect(parsed.task.error, isNull);

      final extended = CreateTaskExtensionResult.fromJson({
        ...json,
        'status': TaskStatus.completed.name,
        'inputRequests': <String, dynamic>{},
        'result': <String, dynamic>{'content': 'legacy detail'},
        'error': <String, dynamic>{'code': -32000, 'message': 'legacy detail'},
        'com.example/trace': <String, dynamic>{'id': 'trace-1'},
      });
      expect(extended.task.inputRequests, isNull);
      expect(extended.task.result, isNull);
      expect(extended.task.error, isNull);
      expect(
        extended.task.extra,
        {
          'inputRequests': <String, dynamic>{},
          'result': <String, dynamic>{'content': 'legacy detail'},
          'error': <String, dynamic>{
            'code': -32000,
            'message': 'legacy detail',
          },
          'com.example/trace': <String, dynamic>{'id': 'trace-1'},
        },
      );
      final extendedJson = extended.toJson();
      expect(extendedJson, isNot(contains('inputRequests')));
      expect(extendedJson, isNot(contains('result')));
      expect(extendedJson, isNot(contains('error')));
      expect(extendedJson['com.example/trace'], <String, dynamic>{
        'id': 'trace-1',
      });
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
        extra: {
          'com.example/receipt': {'sequence': 7},
        },
      );

      final json = result.toJson();
      expect(json['resultType'], resultTypeComplete);
      expect(json['_meta'], {'trace': 'abc'});
      expect(json['com.example/receipt'], {'sequence': 7});

      final parsed = TaskExtensionAcknowledgementResult.fromJson(json);
      expect(parsed.meta, {'trace': 'abc'});
      expect(parsed.extra, {
        'com.example/receipt': {'sequence': 7},
      });
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
      expect(
        () => const TaskExtensionAcknowledgementResult(
          extra: {'bad': Object()},
        ).toJson(),
        throwsFormatException,
      );
    });

    test('rejects missing status-specific task payload fields', () {
      final baseTask = {
        'taskId': 'task-1',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:02:00Z',
        'ttlMs': null,
      };

      expect(
        () => TaskExtensionTask.fromJson({
          ...baseTask,
          'status': 'input_required',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('inputRequests'),
          ),
        ),
      );
      expect(
        () => TaskExtensionTask.fromJson({
          ...baseTask,
          'status': 'completed',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('result'),
          ),
        ),
      );
      expect(
        () => TaskExtensionTask.fromJson({
          ...baseTask,
          'status': 'failed',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('error'),
          ),
        ),
      );
      expect(
        () => const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.inputRequired,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
        ).toJson(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('inputRequests'),
          ),
        ),
      );
      expect(
        () => const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.completed,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
        ).toJson(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('result'),
          ),
        ),
      );
      expect(
        () => const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.failed,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
        ).toJson(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('error'),
          ),
        ),
      );
    });

    test('accepts but does not emit status-incompatible detailed fields', () {
      final baseTask = <String, dynamic>{
        'taskId': 'task-1',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:02:00Z',
        'ttlMs': null,
      };
      final parsedWorking = TaskExtensionTask.fromJson({
        ...baseTask,
        'status': 'working',
        'result': <String, dynamic>{'value': 1},
      });
      expect(parsedWorking.result, isNull);
      expect(parsedWorking.extra, {
        'result': <String, dynamic>{'value': 1},
      });
      expect(parsedWorking.toJson(), isNot(contains('result')));

      final parsedCompleted = TaskExtensionTask.fromJson({
        ...baseTask,
        'status': 'completed',
        'result': <String, dynamic>{'value': 2},
        'inputRequests': <String, dynamic>{},
      });
      expect(parsedCompleted.result, {'value': 2});
      expect(parsedCompleted.inputRequests, isNull);
      expect(parsedCompleted.extra, {'inputRequests': <String, dynamic>{}});
      expect(parsedCompleted.toJson(), isNot(contains('inputRequests')));

      final tasks = <TaskExtensionTask>[
        const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.working,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
          result: {},
        ),
        const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.inputRequired,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
          inputRequests: {},
          error: JsonRpcErrorData(code: -32000, message: 'failed'),
        ),
        const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.completed,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
          result: {},
          inputRequests: {},
        ),
        const TaskExtensionTask(
          taskId: 'task-1',
          status: TaskStatus.failed,
          createdAt: '2026-07-28T00:00:00Z',
          lastUpdatedAt: '2026-07-28T00:02:00Z',
          ttlMs: null,
          error: JsonRpcErrorData(code: -32000, message: 'failed'),
          result: {},
        ),
      ];
      final serialized = tasks.map((task) => task.toJson()).toList();
      expect(serialized[0], isNot(contains('result')));
      expect(serialized[1], isNot(contains('error')));
      expect(serialized[2], isNot(contains('inputRequests')));
      expect(serialized[3], isNot(contains('result')));
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

    test('preserves additional detailed task fields', () {
      final result = GetTaskExtensionResult.fromJson(const {
        'resultType': resultTypeComplete,
        'taskId': 'task-1',
        'status': 'working',
        'createdAt': '2026-07-28T00:00:00Z',
        'lastUpdatedAt': '2026-07-28T00:01:00Z',
        'ttlMs': null,
        'com.example/worker': 'worker-7',
      });

      expect(
        result.task.extra,
        const {'com.example/worker': 'worker-7'},
      );
      expect(result.toJson()['com.example/worker'], 'worker-7');

      final notification = JsonRpcTaskNotification.fromJson(const {
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsTasks,
        'params': <String, dynamic>{
          'taskId': 'task-1',
          'status': 'working',
          'createdAt': '2026-07-28T00:00:00Z',
          'lastUpdatedAt': '2026-07-28T00:01:00Z',
          'ttlMs': null,
          'com.example/worker': 'worker-8',
        },
      });
      expect(
        notification.task.extra,
        const {'com.example/worker': 'worker-8'},
      );
      expect(
        notification.toJson()['params']['com.example/worker'],
        'worker-8',
      );
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
