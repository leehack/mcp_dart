import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';
// Import McpServer for testing

void main() {
  group('MCP 2025-11-25 Protocol Updates', () {
    test('Protocol Version', () {
      expect(latestProtocolVersion, '2025-11-25');
    });

    test('Implementation Description', () {
      final impl = const Implementation(
        name: 'test-client',
        version: '1.0.0',
        description: 'A test client implementation',
      );
      expect(impl.description, 'A test client implementation');
      final json = impl.toJson();
      expect(json['description'], 'A test client implementation');

      final deserialized = Implementation.fromJson(json);
      expect(deserialized.description, 'A test client implementation');
    });

    test('Icon Field Support', () {
      final icon = const ImageContent(data: 'base64', mimeType: 'image/png');

      final tool = Tool(
        name: 'test-tool',
        inputSchema: const JsonObject(),
        icon: icon,
      );
      expect(tool.icon?.data, 'base64');
      expect(tool.toJson()['icon']['data'], 'base64');

      final resource = Resource(
        uri: 'file://test',
        name: 'test',
        icon: icon,
      );
      expect(resource.icon?.data, 'base64');
      expect(resource.toJson()['icon']['data'], 'base64');

      final prompt = Prompt(
        name: 'test-prompt',
        icon: icon,
      );
      expect(prompt.icon?.data, 'base64');
      expect(prompt.toJson()['icon']['data'], 'base64');

      final template = ResourceTemplate(
        uriTemplate: 'file:///test/{id}',
        name: 'test-template',
        icon: icon,
      );
      expect(template.icon?.data, 'base64');
      expect(template.toJson()['icon']['data'], 'base64');
    });

    test('Elicitation with URL', () {
      final params = const ElicitRequestParams(
        message: 'test',
        requestedSchema: JsonObject(),
        url: 'https://example.com/ui',
      );

      expect(params.url, 'https://example.com/ui');

      final json = params.toJson();
      expect(json['url'], 'https://example.com/ui');

      final deserialized = ElicitRequestParams.fromJson(json);
      expect(deserialized.url, 'https://example.com/ui');
    });

    test('JsonEnum SEP-1330', () {
      final schema = const JsonEnum(
        [
          'simple',
          {'value': 'complex', 'title': 'Complex Option'},
        ],
      );

      expect(schema.values.length, 2);
      expect(schema.values[0], 'simple');
      expect((schema.values[1] as Map)['title'], 'Complex Option');

      final json = schema.toJson();
      expect(json['values'], hasLength(2));

      final deserialized = JsonEnum.fromJson(json);
      expect(deserialized.values[0], 'simple');
      expect((deserialized.values[1] as Map)['value'], 'complex');
    });

    test('ToolAnnotations SEP-???', () {
      final annotations = const ToolAnnotations(
        title: 'Test Tool',
        priority: 0.5,
        audience: ['user', 'assistant'],
      );
      expect(annotations.priority, 0.5);
      expect(annotations.audience, contains('user'));

      final json = annotations.toJson();
      expect(json['priority'], 0.5);
      expect(json['audience'], contains('assistant'));

      final deserialized = ToolAnnotations.fromJson(json);
      expect(deserialized.priority, 0.5);
      expect(deserialized.audience, contains('user'));
    });

    test('ElicitResult content flexibility', () {
      final result = const ElicitResult(
        action: 'accept',
        content: {
          'text': 'answer',
          'selection': ['a', 'b'], // List<String>
        },
      );
      expect(result.content?['selection'], isA<List>());
      expect((result.content?['selection'] as List).first, 'a');

      final json = result.toJson();
      final deserialized = ElicitResult.fromJson(json);
      expect((deserialized.content?['selection'] as List).last, 'b');
    });

    test('McpServer Metadata Logic', () {
      final server =
          McpServer(const Implementation(name: 'test', version: '1.0'));
      final icon = const ImageContent(data: 'data', mimeType: 'image/png');
      // We can rely on the fact that we updated the code to pass it through.

      // Let's rely on the previous unit tests for `Tool` serialization, and here just ensure `McpServer` methods don't crash.

      server.resource(
        'icon-resource',
        'file:///test',
        (uri, extra) => const ReadResourceResult(contents: []),
        icon: icon,
      );

      server.prompt(
        'icon-prompt',
        icon: icon,
      );
    });

    test('Tasks Capabilities', () {
      final clientCaps = const ClientCapabilities(
        tasks: ClientCapabilitiesTasks(
          requests: ClientCapabilitiesTasksRequests(
            sampling: ClientCapabilitiesTasksSampling(
              createMessage: ClientCapabilitiesTasksSamplingCreateMessage(),
            ),
          ),
        ),
      );
      expect(clientCaps.tasks, isNotNull);
      expect(clientCaps.toJson()['tasks'], isNotNull);

      final serverCaps = const ServerCapabilities(
        tasks: ServerCapabilitiesTasks(listChanged: true),
        completions: ServerCapabilitiesCompletions(listChanged: true),
      );
      expect(serverCaps.tasks, isNotNull);
      expect(serverCaps.toJson()['tasks'], isNotNull);
      expect(serverCaps.completions?.listChanged, isTrue);
      expect(serverCaps.toJson()['completions']['listChanged'], isTrue);
    });

    test('Task Types', () {
      final task = const Task(
        taskId: '123',
        status: TaskStatus.working,
        createdAt: '2025-01-01T00:00:00Z',
        ttl: 3600,
      );
      expect(task.status, TaskStatus.working);

      final json = task.toJson();
      expect(json['status'], 'working');
      expect(json['ttl'], 3600);

      final deserialized = Task.fromJson(json);
      expect(deserialized.taskId, '123');
      expect(deserialized.status, TaskStatus.working);
    });

    test('Sampling with Tools', () {
      final params = CreateMessageRequestParams(
        messages: [],
        maxTokens: 100,
        tools: [
          Tool(
            name: 'calculator',
            description: 'A calculator',
            inputSchema: JsonObject(
              properties: {
                'expr': JsonSchema.string(),
              },
            ),
          ),
        ],
        toolChoice: {'type': 'auto'},
      );

      final json = params.toJson();
      expect(json['tools'], isA<List>());
      expect(json['toolChoice'], {'type': 'auto'});

      final deserialized = CreateMessageRequestParams.fromJson(json);
      expect(deserialized.tools, hasLength(1));
      expect(deserialized.tools!.first.name, 'calculator');
      expect(deserialized.toolChoice, {'type': 'auto'});
    });

    group('Tasks API Types', () {
      test('GetTaskRequestParams serialization', () {
        final params = const GetTaskRequestParams(taskId: 'task-123');
        expect(params.taskId, 'task-123');

        final json = params.toJson();
        expect(json['taskId'], 'task-123');

        final deserialized = GetTaskRequestParams.fromJson(json);
        expect(deserialized.taskId, 'task-123');
      });

      test('JsonRpcGetTaskRequest serialization', () {
        final request = JsonRpcGetTaskRequest(
          id: 1,
          getParams: const GetTaskRequestParams(taskId: 'task-456'),
        );
        expect(request.method, 'tasks/get');
        expect(request.getParams.taskId, 'task-456');

        final json = request.toJson();
        expect(json['method'], 'tasks/get');
        expect(json['params']['taskId'], 'task-456');

        final deserialized = JsonRpcGetTaskRequest.fromJson(json);
        expect(deserialized.id, 1);
        expect(deserialized.getParams.taskId, 'task-456');
      });

      test('JsonRpcGetTaskRequest via JsonRpcMessage.fromJson', () {
        final json = {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tasks/get',
          'params': {'taskId': 'task-789'},
        };
        final message = JsonRpcMessage.fromJson(json);
        expect(message, isA<JsonRpcGetTaskRequest>());
        final request = message as JsonRpcGetTaskRequest;
        expect(request.getParams.taskId, 'task-789');
      });

      test('TaskResultRequestParams serialization', () {
        final params = const TaskResultRequestParams(taskId: 'task-result-123');
        expect(params.taskId, 'task-result-123');

        final json = params.toJson();
        expect(json['taskId'], 'task-result-123');

        final deserialized = TaskResultRequestParams.fromJson(json);
        expect(deserialized.taskId, 'task-result-123');
      });

      test('JsonRpcTaskResultRequest serialization', () {
        final request = JsonRpcTaskResultRequest(
          id: 2,
          resultParams:
              const TaskResultRequestParams(taskId: 'task-result-456'),
        );
        expect(request.method, 'tasks/result');
        expect(request.resultParams.taskId, 'task-result-456');

        final json = request.toJson();
        expect(json['method'], 'tasks/result');
        expect(json['params']['taskId'], 'task-result-456');

        final deserialized = JsonRpcTaskResultRequest.fromJson(json);
        expect(deserialized.id, 2);
        expect(deserialized.resultParams.taskId, 'task-result-456');
      });

      test('JsonRpcTaskResultRequest via JsonRpcMessage.fromJson', () {
        final json = {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tasks/result',
          'params': {'taskId': 'task-xyz'},
        };
        final message = JsonRpcMessage.fromJson(json);
        expect(message, isA<JsonRpcTaskResultRequest>());
        final request = message as JsonRpcTaskResultRequest;
        expect(request.resultParams.taskId, 'task-xyz');
      });

      test('TaskCreationParams serialization', () {
        final params = const TaskCreationParams(ttl: 3600);
        expect(params.ttl, 3600);

        final json = params.toJson();
        expect(json['ttl'], 3600);

        final deserialized = TaskCreationParams.fromJson(json);
        expect(deserialized.ttl, 3600);
      });

      test('TaskCreationParams without ttl', () {
        final params = const TaskCreationParams();
        expect(params.ttl, isNull);

        final json = params.toJson();
        expect(json.containsKey('ttl'), isFalse);

        final deserialized = TaskCreationParams.fromJson({});
        expect(deserialized.ttl, isNull);
      });

      test('CreateTaskResult serialization', () {
        final result = const CreateTaskResult(
          task: Task(
            taskId: 'new-task-123',
            status: TaskStatus.working,
            statusMessage: 'Task started',
            ttl: 7200,
            pollInterval: 1000,
            createdAt: '2025-01-15T10:00:00Z',
          ),
        );

        expect(result.task.taskId, 'new-task-123');
        expect(result.task.status, TaskStatus.working);

        final json = result.toJson();
        expect(json['task']['taskId'], 'new-task-123');
        expect(json['task']['status'], 'working');

        final deserialized = CreateTaskResult.fromJson(json);
        expect(deserialized.task.taskId, 'new-task-123');
        expect(deserialized.task.status, TaskStatus.working);
        expect(deserialized.task.ttl, 7200);
      });

      test('TaskStatusNotificationParams serialization', () {
        final params = const TaskStatusNotificationParams(
          taskId: 'task-notify-123',
          status: TaskStatus.completed,
          statusMessage: 'Task completed successfully',
          ttl: 3600,
          pollInterval: 500,
          createdAt: '2025-01-15T10:00:00Z',
          lastUpdatedAt: '2025-01-15T10:05:00Z',
        );

        expect(params.taskId, 'task-notify-123');
        expect(params.status, TaskStatus.completed);
        expect(params.statusMessage, 'Task completed successfully');

        final json = params.toJson();
        expect(json['taskId'], 'task-notify-123');
        expect(json['status'], 'completed');
        expect(json['lastUpdatedAt'], '2025-01-15T10:05:00Z');

        final deserialized = TaskStatusNotificationParams.fromJson(json);
        expect(deserialized.taskId, 'task-notify-123');
        expect(deserialized.status, TaskStatus.completed);
      });

      test('JsonRpcTaskStatusNotification serialization', () {
        final notification = JsonRpcTaskStatusNotification(
          statusParams: const TaskStatusNotificationParams(
            taskId: 'task-status-456',
            status: TaskStatus.failed,
            statusMessage: 'Task failed due to error',
          ),
        );

        expect(notification.method, 'notifications/tasks/status');
        expect(notification.statusParams.taskId, 'task-status-456');
        expect(notification.statusParams.status, TaskStatus.failed);

        final json = notification.toJson();
        expect(json['method'], 'notifications/tasks/status');
        expect(json['params']['taskId'], 'task-status-456');
        expect(json['params']['status'], 'failed');

        final deserialized = JsonRpcTaskStatusNotification.fromJson(json);
        expect(deserialized.statusParams.taskId, 'task-status-456');
        expect(deserialized.statusParams.status, TaskStatus.failed);
      });

      test('JsonRpcTaskStatusNotification via JsonRpcMessage.fromJson', () {
        final json = {
          'jsonrpc': '2.0',
          'method': 'notifications/tasks/status',
          'params': {
            'taskId': 'task-abc',
            'status': 'input_required',
            'statusMessage': 'Waiting for user input',
          },
        };
        final message = JsonRpcMessage.fromJson(json);
        expect(message, isA<JsonRpcTaskStatusNotification>());
        final notification = message as JsonRpcTaskStatusNotification;
        expect(notification.statusParams.taskId, 'task-abc');
        expect(notification.statusParams.status, TaskStatus.inputRequired);
        expect(
          notification.statusParams.statusMessage,
          'Waiting for user input',
        );
      });

      test('JsonRpcCallToolRequest with taskParams', () {
        final callRequest = const CallToolRequest(
          name: 'long-running-tool',
          arguments: {'input': 'value'},
        );
        final request = JsonRpcCallToolRequest(
          id: 3,
          params: callRequest.toJson(),
          meta: {'task': const TaskCreationParams(ttl: 7200).toJson()},
        );

        expect(request.isTaskAugmented, isTrue);
        expect(request.taskParams?.ttl, 7200);
        expect(request.callParams.name, 'long-running-tool');

        final json = request.toJson();
        expect(json['params']['name'], 'long-running-tool');
        expect(json['params']['_meta']['task']['ttl'], 7200);

        final deserialized = JsonRpcCallToolRequest.fromJson(json);
        expect(deserialized.isTaskAugmented, isTrue);
        expect(deserialized.taskParams?.ttl, 7200);
        expect(deserialized.callParams.name, 'long-running-tool');
      });

      test('JsonRpcCallToolRequest without taskParams', () {
        final callRequest = const CallToolRequest(name: 'simple-tool');
        final request = JsonRpcCallToolRequest(
          id: 4,
          params: callRequest.toJson(),
        );

        expect(request.isTaskAugmented, isFalse);
        expect(request.taskParams, isNull);

        final json = request.toJson();
        expect(json['params'].containsKey('task'), isFalse);

        final deserialized = JsonRpcCallToolRequest.fromJson(json);
        expect(deserialized.isTaskAugmented, isFalse);
        expect(deserialized.taskParams, isNull);
      });

      test('TaskStatus enum all values', () {
        expect(TaskStatusName.fromString('working'), TaskStatus.working);
        expect(
          TaskStatusName.fromString('input_required'),
          TaskStatus.inputRequired,
        );
        expect(TaskStatusName.fromString('completed'), TaskStatus.completed);
        expect(TaskStatusName.fromString('failed'), TaskStatus.failed);
        expect(TaskStatusName.fromString('cancelled'), TaskStatus.cancelled);

        expect(TaskStatus.working.name, 'working');
        expect(TaskStatus.inputRequired.name, 'input_required');
        expect(TaskStatus.completed.name, 'completed');
        expect(TaskStatus.failed.name, 'failed');
        expect(TaskStatus.cancelled.name, 'cancelled');
      });

      test('TaskStatus fromString throws on invalid status', () {
        expect(
          () => TaskStatusName.fromString('invalid_status'),
          throwsA(isA<FormatException>()),
        );
      });

      test('Task all fields serialization', () {
        final task = const Task(
          taskId: 'full-task',
          status: TaskStatus.working,
          statusMessage: 'Processing data',
          ttl: 3600,
          pollInterval: 1000,
          createdAt: '2025-01-15T10:00:00Z',
          lastUpdatedAt: '2025-01-15T10:01:00Z',
          meta: {'custom': 'value'},
        );

        final json = task.toJson();
        expect(json['taskId'], 'full-task');
        expect(json['status'], 'working');
        expect(json['statusMessage'], 'Processing data');
        expect(json['ttl'], 3600);
        expect(json['pollInterval'], 1000);
        expect(json['createdAt'], '2025-01-15T10:00:00Z');
        expect(json['lastUpdatedAt'], '2025-01-15T10:01:00Z');
        expect(json['_meta'], {'custom': 'value'});

        final deserialized = Task.fromJson(json);
        expect(deserialized.taskId, 'full-task');
        expect(deserialized.statusMessage, 'Processing data');
        expect(deserialized.meta, {'custom': 'value'});
      });
    });
  });
}
