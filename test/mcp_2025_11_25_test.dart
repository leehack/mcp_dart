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

    test('Implementation Extended Metadata', () {
      final icons = [
        const McpIcon(
          src: 'https://example.com/client-icon.png',
          mimeType: 'image/png',
          theme: IconTheme.light,
        ),
      ];

      final impl = Implementation(
        name: 'test-client',
        title: 'Test Client',
        version: '1.0.0',
        description: 'A test client implementation',
        icons: icons,
        websiteUrl: 'https://example.com',
      );

      final json = impl.toJson();
      expect(json['title'], 'Test Client');
      expect(
        (json['icons'] as List).single['src'],
        'https://example.com/client-icon.png',
      );
      expect(json['websiteUrl'], 'https://example.com');

      final deserialized = Implementation.fromJson(json);
      expect(deserialized.title, 'Test Client');
      expect(deserialized.icons, isNotNull);
      expect(deserialized.icons!.single.theme, IconTheme.light);
      expect(deserialized.websiteUrl, 'https://example.com');
    });

    test('Icon Field Support', () {
      const iconData = 'YmFzZTY0';
      final icon = const ImageContent(data: iconData, mimeType: 'image/png');
      final icons = [
        const McpIcon(
          src: 'https://example.com/icon.png',
          mimeType: 'image/png',
          theme: IconTheme.dark,
        ),
      ];

      final tool = Tool(
        name: 'test-tool',
        inputSchema: const JsonObject(),
        icon: icon,
        icons: icons,
      );
      expect(tool.icon?.data, iconData);
      expect(tool.toJson().containsKey('icon'), isFalse);
      expect((tool.toJson()['icons'] as List).first['theme'], 'dark');
      expect(
        Tool.fromJson({...tool.toJson(), 'icon': icon.toJson()}).icon?.data,
        iconData,
      );

      final resource = Resource(
        uri: 'file://test',
        name: 'test',
        icon: icon,
        icons: icons,
      );
      expect(resource.icon?.data, iconData);
      expect(resource.toJson().containsKey('icon'), isFalse);
      expect((resource.toJson()['icons'] as List).first['theme'], 'dark');
      expect(
        Resource.fromJson(
          {...resource.toJson(), 'icon': icon.toJson()},
        ).icon?.data,
        iconData,
      );

      final prompt = Prompt(
        name: 'test-prompt',
        icon: icon,
        icons: icons,
      );
      expect(prompt.icon?.data, iconData);
      expect(prompt.toJson().containsKey('icon'), isFalse);
      expect((prompt.toJson()['icons'] as List).first['theme'], 'dark');
      expect(
        Prompt.fromJson({...prompt.toJson(), 'icon': icon.toJson()}).icon?.data,
        iconData,
      );

      final template = ResourceTemplate(
        uriTemplate: 'file:///test/{id}',
        name: 'test-template',
        icon: icon,
        icons: icons,
      );
      expect(template.icon?.data, iconData);
      expect(template.toJson().containsKey('icon'), isFalse);
      expect((template.toJson()['icons'] as List).first['theme'], 'dark');
      expect(
        ResourceTemplate.fromJson(
          {...template.toJson(), 'icon': icon.toJson()},
        ).icon?.data,
        iconData,
      );
    });

    test('BaseMetadata title fields are supported', () {
      final tool = const Tool(
        name: 'tool-name',
        title: 'Tool Title',
        inputSchema: JsonObject(),
      );
      expect(tool.toJson()['title'], 'Tool Title');
      expect(Tool.fromJson(tool.toJson()).title, 'Tool Title');

      final resource = const Resource(
        uri: 'file://resource',
        name: 'resource-name',
        title: 'Resource Title',
      );
      expect(resource.toJson()['title'], 'Resource Title');
      expect(Resource.fromJson(resource.toJson()).title, 'Resource Title');

      final template = const ResourceTemplate(
        uriTemplate: 'file:///{id}',
        name: 'template-name',
        title: 'Template Title',
      );
      expect(template.toJson()['title'], 'Template Title');
      expect(
        ResourceTemplate.fromJson(template.toJson()).title,
        'Template Title',
      );

      final prompt = const Prompt(
        name: 'prompt-name',
        title: 'Prompt Title',
        arguments: [
          PromptArgument(name: 'arg', title: 'Argument Title'),
        ],
        meta: {'scope': 'test'},
      );
      final promptJson = prompt.toJson();
      expect(promptJson['title'], 'Prompt Title');
      expect(promptJson['_meta'], {'scope': 'test'});
      expect(
        (promptJson['arguments'] as List).single['title'],
        'Argument Title',
      );

      final deserializedPrompt = Prompt.fromJson(promptJson);
      expect(deserializedPrompt.title, 'Prompt Title');
      expect(deserializedPrompt.meta, {'scope': 'test'});
      expect(deserializedPrompt.arguments?.single.title, 'Argument Title');
    });

    test('CompleteRequest supports context arguments and prompt title', () {
      final request = const CompleteRequest(
        ref: PromptReference(
          name: 'translate',
          title: 'Translate prompt',
        ),
        argument: ArgumentCompletionInfo(
          name: 'target_language',
          value: 'Spa',
        ),
        context: CompletionContext(
          arguments: {
            'source_language': 'English',
            'formality': 'formal',
          },
        ),
      );

      final json = request.toJson();
      expect(json['ref']['type'], 'ref/prompt');
      expect(json['ref']['name'], 'translate');
      expect(json['ref']['title'], 'Translate prompt');
      expect(json['context']['arguments']['source_language'], 'English');
      expect(json['context']['arguments']['formality'], 'formal');

      final deserialized = CompleteRequest.fromJson(json);
      final ref = deserialized.ref as PromptReference;
      expect(ref.name, 'translate');
      expect(ref.title, 'Translate prompt');
      expect(deserialized.context?.arguments, {
        'source_language': 'English',
        'formality': 'formal',
      });

      final message = JsonRpcMessage.fromJson({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'completion/complete',
        'params': json,
      });
      expect(message, isA<JsonRpcCompleteRequest>());

      final completeRequest = message as JsonRpcCompleteRequest;
      final promptRef = completeRequest.completeParams.ref as PromptReference;
      expect(promptRef.title, 'Translate prompt');
      expect(completeRequest.completeParams.context?.arguments, {
        'source_language': 'English',
        'formality': 'formal',
      });
      expect(
        completeRequest.toJson()['params']['context']['arguments'],
        {
          'source_language': 'English',
          'formality': 'formal',
        },
      );
    });

    test('Elicitation with URL', () {
      final params = const ElicitRequestParams.url(
        message: 'test',
        url: 'https://example.com/ui',
        elicitationId: 'ui-123',
        task: TaskCreationParams(ttl: 7200),
      );

      expect(params.url, 'https://example.com/ui');
      expect(params.elicitationId, 'ui-123');
      expect(params.task?.ttl, 7200);

      final json = params.toJson();
      expect(json['mode'], 'url');
      expect(json['url'], 'https://example.com/ui');
      expect(json['elicitationId'], 'ui-123');
      expect(json['task'], {'ttl': 7200});

      final deserialized = ElicitRequestParams.fromJson(json);
      expect(deserialized.url, 'https://example.com/ui');
      expect(deserialized.elicitationId, 'ui-123');
      expect(deserialized.task?.ttl, 7200);
    });

    test('Elicitation URL must be absolute URI', () {
      expect(
        () => ElicitRequestParams.fromJson({
          'mode': 'url',
          'message': 'test',
          'url': '/relative/ui',
          'elicitationId': 'ui-123',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitRequestParams.url(
          message: 'test',
          url: '/relative/ui',
          elicitationId: 'ui-123',
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
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
      expect(json['type'], 'string');
      expect(json['oneOf'], [
        {'const': 'simple'},
        {'const': 'complex', 'title': 'Complex Option'},
      ]);
      expect(json.containsKey('values'), isFalse);

      final deserialized = JsonEnum.fromJson(json);
      expect(deserialized.values[0], 'simple');
      expect((deserialized.values[1] as Map)['value'], 'complex');
      expect((deserialized.values[1] as Map)['title'], 'Complex Option');
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
      expect(json.containsKey('priority'), isFalse);
      expect(json.containsKey('audience'), isFalse);

      final deserialized = ToolAnnotations.fromJson({
        ...json,
        'priority': 0.5,
        'audience': ['user', 'assistant'],
      });
      expect(deserialized.priority, 0.5);
      expect(deserialized.audience, contains('user'));
    });

    test('ElicitResult content flexibility', () {
      final result = const ElicitResult(
        action: 'accept',
        content: {
          'text': 'answer',
          'confidence': 75,
          'selection': ['a', 'b'], // List<String>
        },
      );
      expect(result.content?['confidence'], 75);
      expect(result.content?['selection'], isA<List>());
      expect((result.content?['selection'] as List).first, 'a');

      final json = result.toJson();
      final deserialized = ElicitResult.fromJson(json);
      expect(deserialized.content?['confidence'], 75);
      expect((deserialized.content?['selection'] as List).last, 'b');
    });

    test('McpServer Metadata Logic', () {
      final server =
          McpServer(const Implementation(name: 'test', version: '1.0'));
      final icon = const ImageContent(data: 'ZGF0YQ==', mimeType: 'image/png');
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
        sampling: ClientCapabilitiesSampling(context: true, tools: true),
        tasks: ClientCapabilitiesTasks(
          list: true,
          cancel: true,
          requests: ClientCapabilitiesTasksRequests(
            sampling: ClientCapabilitiesTasksSampling(
              createMessage: ClientCapabilitiesTasksSamplingCreateMessage(),
            ),
          ),
        ),
      );
      expect(clientCaps.tasks, isNotNull);
      expect(clientCaps.toJson()['tasks'], isNotNull);
      expect(clientCaps.toJson()['sampling']['context'], isA<Map>());
      expect(clientCaps.toJson()['sampling']['tools'], isA<Map>());
      expect(clientCaps.toJson()['tasks']['list'], isA<Map>());
      expect(clientCaps.toJson()['tasks']['cancel'], isA<Map>());

      final serverCaps = const ServerCapabilities(
        tasks: ServerCapabilitiesTasks(
          list: true,
          cancel: true,
          requests: ServerCapabilitiesTasksRequests(
            tools: ServerCapabilitiesTasksTools(
              call: ServerCapabilitiesTasksToolsCall(),
            ),
          ),
        ),
        completions: ServerCapabilitiesCompletions(),
      );
      expect(serverCaps.tasks, isNotNull);
      expect(serverCaps.toJson()['tasks'], isNotNull);
      expect(serverCaps.toJson()['tasks']['list'], isA<Map>());
      expect(serverCaps.toJson()['tasks']['cancel'], isA<Map>());
      expect(
        serverCaps.toJson()['tasks']['requests']['tools']['call'],
        isA<Map>(),
      );
      expect(serverCaps.toJson()['completions'], isA<Map>());
      expect(serverCaps.toJson()['completions'].isEmpty, isTrue);
    });

    test('Capability object markers parse from JSON', () {
      final parsedClient = ClientCapabilities.fromJson({
        'sampling': {
          'context': {},
          'tools': {},
        },
        'tasks': {
          'list': {},
          'cancel': {},
          'requests': {
            'sampling': {'createMessage': {}},
            'elicitation': {'create': {}},
          },
        },
      });

      expect(parsedClient.sampling?.context, isTrue);
      expect(parsedClient.sampling?.tools, isTrue);
      expect(parsedClient.tasks?.list, isTrue);
      expect(parsedClient.tasks?.cancel, isTrue);

      final parsedServer = ServerCapabilities.fromJson({
        'tasks': {
          'list': {},
          'cancel': {},
          'requests': {
            'tools': {'call': {}},
          },
        },
      });

      expect(parsedServer.tasks?.list, isTrue);
      expect(parsedServer.tasks?.cancel, isTrue);
      expect(parsedServer.tasks?.requests?.tools?.call, isNotNull);
    });

    test('Task Types', () {
      final task = const Task(
        taskId: '123',
        status: TaskStatus.working,
        createdAt: '2025-01-01T00:00:00Z',
        lastUpdatedAt: '2025-01-01T00:01:00Z',
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
        toolChoice: const ToolChoice(mode: ToolChoiceMode.auto),
      );

      final json = params.toJson();
      expect(json['tools'], isA<List>());
      expect(json['toolChoice'], {'mode': 'auto'});

      final deserialized = CreateMessageRequestParams.fromJson(json);
      expect(deserialized.tools, hasLength(1));
      expect(deserialized.tools!.first.name, 'calculator');
      expect(deserialized.toolChoiceConfig?.mode, ToolChoiceMode.auto);

      final legacyDeserialized = CreateMessageRequestParams.fromJson({
        ...json,
        'toolChoice': {'type': 'required'},
      });
      expect(
        legacyDeserialized.toolChoiceConfig?.mode,
        ToolChoiceMode.required,
      );
    });

    test('Sampling result supports content arrays and toolUse stopReason', () {
      final result = CreateMessageResult.fromJson({
        'model': 'test-model',
        'stopReason': 'toolUse',
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'call-1',
            'name': 'calculator',
            'input': {'expr': '2+2'},
          },
        ],
      });

      expect(result.stopReason, StopReason.toolUse);
      expect(result.contentBlocks, hasLength(1));
      expect(result.contentBlocks.single, isA<SamplingToolUseContent>());

      final json = result.toJson();
      expect(json['stopReason'], 'toolUse');
      expect((json['content'] as List).single['type'], 'tool_use');
    });

    test('Sampling JSON object fields reject non-JSON Dart maps', () {
      expect(
        () => SamplingToolUseContent.fromJson({
          'type': 'tool_use',
          'id': 'call-1',
          'name': 'calculator',
          'input': {'expr': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingMessage.fromJson({
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
          '_meta': {'provider': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageResult.fromJson({
          'role': 'assistant',
          'content': {'type': 'text', 'text': 'Hello'},
          'model': 'model-x',
          '_meta': {'provider': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Hello'},
            },
          ],
          'maxTokens': 100,
          'metadata': {'provider': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('Content JSON object fields reject non-JSON Dart maps', () {
      expect(
        () => TextContent.fromJson({
          'type': 'text',
          'text': 'Hello',
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceContents.fromJson({
          'uri': 'file:///docs/readme.md',
          'text': 'README body',
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ResourceLink.fromJson({
          'type': 'resource_link',
          'uri': 'file:///docs/readme.md',
          'name': 'readme',
          'annotations': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('Tool JSON object fields reject non-JSON Dart maps', () {
      expect(
        () => Tool.fromJson({
          'name': 'search',
          'inputSchema': {'type': 'object'},
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CallToolRequest.fromJson({
          'name': 'search',
          'arguments': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CallToolResult.fromJson({
          'content': <Map<String, dynamic>>[],
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('Tool wire fields reject malformed values', () {
      for (final parse in <Object Function()>[
        () => ToolAnnotations.fromJson({'title': 1}),
        () => ToolAnnotations.fromJson({'readOnlyHint': 'true'}),
        () => ToolExecution.fromJson({'taskSupport': 1}),
        () => Tool.fromJson({
              'name': 1,
              'inputSchema': {'type': 'object'},
            }),
        () => Tool.fromJson({
              'name': 'search',
              'inputSchema': {'type': 'object'},
              'annotations': 'bad',
            }),
        () => Tool.fromJson({
              'name': 'search',
              'inputSchema': {'type': 'object'},
              'icons': [1],
            }),
        () => ListToolsRequest.fromJson({'cursor': 1}),
        () => ListToolsResult.fromJson({
              'tools': <Map<String, dynamic>>[],
              'nextCursor': 1,
            }),
        () => CallToolRequest.fromJson({'name': 1}),
        () => CallToolResult.fromJson({
              'content': <Map<String, dynamic>>[],
              'isError': 'true',
            }),
        () => JsonRpcListToolsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.toolsList,
              'params': 'bad',
            }),
        () => JsonRpcCallToolRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.toolsCall,
              'params': 'bad',
            }),
      ]) {
        expect(parse, throwsA(isA<FormatException>()));
      }
    });

    test('Root wire fields reject malformed values', () {
      for (final parse in <Object Function()>[
        () => Root.fromJson({'uri': 'file:///repo', 'name': 1}),
        () => ListRootsResult.fromJson({
              'roots': [1],
            }),
        () => JsonRpcListRootsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.rootsList,
              'params': 'bad',
            }),
        () => JsonRpcListRootsRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.rootsList,
              'params': null,
            }),
        () => JsonRpcRootsListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsRootsListChanged,
              'params': 'bad',
            }),
        () => JsonRpcRootsListChangedNotification.fromJson({
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsRootsListChanged,
              'params': null,
            }),
      ]) {
        expect(parse, throwsA(isA<FormatException>()));
      }
    });

    test('Result metadata fields reject non-JSON Dart maps', () {
      expect(
        () => Root.fromJson({
          'uri': 'file:///repo',
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ListResourcesResult.fromJson({
          'resources': [],
          '_meta': {'bad': Object()},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRpcMessage.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'result': {
            'ok': true,
            '_meta': {'bad': Object()},
          },
        }),
        throwsA(isA<FormatException>()),
      );
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

      test('TaskCreationParams accepts whole-number JSON ttl values', () {
        final deserialized = TaskCreationParams.fromJson({'ttl': 3600.0});
        expect(deserialized.ttl, 3600);
        expect(deserialized.toJson()['ttl'], 3600);

        expect(
          () => TaskCreationParams.fromJson({'ttl': 3600.5}),
          throwsA(isA<FormatException>()),
        );
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
            lastUpdatedAt: '2025-01-15T10:01:00Z',
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

      test('task request and result wire fields reject malformed values', () {
        for (final parse in <Object Function()>[
          () => ListTasksRequest.fromJson({'cursor': 1}),
          () => JsonRpcListTasksRequest.fromJson({
                'jsonrpc': jsonRpcVersion,
                'id': 1,
                'method': Method.tasksList,
                'params': 'bad',
              }),
          () => JsonRpcListTasksRequest.fromJson({
                'jsonrpc': jsonRpcVersion,
                'id': 1,
                'method': Method.tasksList,
                'params': null,
              }),
          () => ListTasksResult.fromJson({
                'tasks': [1],
              }),
          () => ListTasksResult.fromJson({
                'tasks': <Map<String, dynamic>>[],
                'nextCursor': 1,
              }),
          () => CancelTaskRequest.fromJson({'taskId': 1}),
          () => JsonRpcCancelTaskRequest.fromJson({
                'jsonrpc': jsonRpcVersion,
                'id': 1,
                'method': Method.tasksCancel,
                'params': 'bad',
              }),
          () => GetTaskRequest.fromJson({'taskId': 1}),
          () => JsonRpcGetTaskRequest.fromJson({
                'jsonrpc': jsonRpcVersion,
                'id': 1,
                'method': Method.tasksGet,
                'params': 'bad',
              }),
          () => TaskResultRequest.fromJson({'taskId': 1}),
          () => JsonRpcTaskResultRequest.fromJson({
                'jsonrpc': jsonRpcVersion,
                'id': 1,
                'method': Method.tasksResult,
                'params': null,
              }),
          () => CreateTaskResult.fromJson({'task': 'bad'}),
          () => JsonRpcTaskStatusNotification.fromJson({
                'jsonrpc': jsonRpcVersion,
                'method': Method.notificationsTasksStatus,
                'params': 'bad',
              }),
          () => JsonRpcTaskStatusNotification.fromJson({
                'jsonrpc': jsonRpcVersion,
                'method': Method.notificationsTasksStatus,
                'params': null,
              }),
        ]) {
          expect(parse, throwsA(isA<FormatException>()));
        }
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

      test('TaskStatusNotificationParams requires full Task fields', () {
        final params = const TaskStatusNotificationParams(
          taskId: 'task-no-expiry',
          status: TaskStatus.working,
          ttl: null,
          createdAt: '2025-01-15T10:00:00Z',
          lastUpdatedAt: '2025-01-15T10:01:00Z',
        );

        final json = params.toJson();
        expect(json, containsPair('ttl', null));
        expect(json['createdAt'], '2025-01-15T10:00:00Z');
        expect(json['lastUpdatedAt'], '2025-01-15T10:01:00Z');

        expect(
          () => const TaskStatusNotificationParams(
            taskId: 'task-missing-created',
            status: TaskStatus.working,
            ttl: null,
            lastUpdatedAt: '2025-01-15T10:01:00Z',
          ).toJson(),
          throwsA(isA<StateError>()),
        );
        expect(
          () => const TaskStatusNotificationParams(
            taskId: 'task-missing-updated',
            status: TaskStatus.working,
            ttl: null,
            createdAt: '2025-01-15T10:00:00Z',
          ).toJson(),
          throwsA(isA<StateError>()),
        );

        for (final field in ['ttl', 'createdAt', 'lastUpdatedAt']) {
          final malformed = Map<String, dynamic>.from(json)..remove(field);
          expect(
            () => TaskStatusNotificationParams.fromJson(malformed),
            throwsA(isA<FormatException>()),
            reason: 'missing $field should be rejected',
          );
          expect(
            () => JsonRpcMessage.fromJson({
              'jsonrpc': '2.0',
              'method': 'notifications/tasks/status',
              'params': malformed,
            }),
            throwsA(isA<FormatException>()),
            reason: 'missing $field should fail at the JSON-RPC boundary',
          );
        }

        expect(
          () => TaskStatusNotificationParams.fromJson(
            Map<String, dynamic>.from(json)..remove('ttl'),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'TaskStatusNotification.ttl is required',
            ),
          ),
        );
        expect(
          () => TaskStatusNotificationParams.fromJson({
            ...json,
            'createdAt': 42,
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'TaskStatusNotification.createdAt must be a string',
            ),
          ),
        );
        expect(
          () => TaskStatusNotificationParams.fromJson({
            ...json,
            'pollInterval': '1000',
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'TaskStatusNotification.pollInterval must be an integer or null',
            ),
          ),
        );
        expect(
          () => TaskStatusNotificationParams.fromJson({
            ...json,
            'statusMessage': 42,
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'TaskStatusNotification.statusMessage must be a string',
            ),
          ),
        );
      });

      test('JsonRpcTaskStatusNotification serialization', () {
        final notification = JsonRpcTaskStatusNotification(
          statusParams: const TaskStatusNotificationParams(
            taskId: 'task-status-456',
            status: TaskStatus.failed,
            statusMessage: 'Task failed due to error',
            createdAt: '2025-01-15T10:00:00Z',
            lastUpdatedAt: '2025-01-15T10:05:00Z',
            ttl: null,
          ),
        );

        expect(notification.method, 'notifications/tasks/status');
        expect(notification.statusParams.taskId, 'task-status-456');
        expect(notification.statusParams.status, TaskStatus.failed);

        final json = notification.toJson();
        expect(json['method'], 'notifications/tasks/status');
        expect(json['params']['taskId'], 'task-status-456');
        expect(json['params']['status'], 'failed');
        expect(json['params'], containsPair('ttl', null));
        expect(json['params']['createdAt'], '2025-01-15T10:00:00Z');
        expect(json['params']['lastUpdatedAt'], '2025-01-15T10:05:00Z');

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
            'createdAt': '2025-01-15T10:00:00Z',
            'lastUpdatedAt': '2025-01-15T10:05:00Z',
            'ttl': null,
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

      test('Task omits null optional pollInterval but keeps required ttl', () {
        final task = const Task(
          taskId: 'cancelled-task',
          status: TaskStatus.cancelled,
          ttl: null,
          createdAt: '2025-01-15T10:00:00Z',
          lastUpdatedAt: '2025-01-15T10:01:00Z',
        );

        final json = task.toJson();
        expect(json, containsPair('ttl', null));
        expect(json, isNot(contains('pollInterval')));
      });

      test('Task accepts whole-number JSON ttl and poll interval values', () {
        final task = Task.fromJson({
          'taskId': 'numeric-task',
          'status': 'working',
          'ttl': 3600.0,
          'pollInterval': 500.0,
          'createdAt': '2025-01-15T10:00:00Z',
          'lastUpdatedAt': '2025-01-15T10:01:00Z',
        });

        expect(task.ttl, 3600);
        expect(task.pollInterval, 500);
        expect(task.toJson(), containsPair('ttl', 3600));
        expect(task.toJson(), containsPair('pollInterval', 500));
      });

      test('Task rejects missing MCP-required fields', () {
        expect(
          () => Task.fromJson({
            'taskId': 'missing-ttl',
            'status': 'working',
            'createdAt': '2025-01-15T10:00:00Z',
            'lastUpdatedAt': '2025-01-15T10:01:00Z',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Task.fromJson({
            'taskId': 'missing-created-at',
            'status': 'working',
            'ttl': null,
            'lastUpdatedAt': '2025-01-15T10:01:00Z',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Task.fromJson({
            'taskId': 'missing-last-updated-at',
            'status': 'working',
            'ttl': null,
            'createdAt': '2025-01-15T10:00:00Z',
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('Task rejects malformed field types with FormatException', () {
        final validJson = {
          'taskId': 'typed-task',
          'status': 'working',
          'ttl': null,
          'createdAt': '2025-01-15T10:00:00Z',
          'lastUpdatedAt': '2025-01-15T10:01:00Z',
        };

        expect(
          () => Task.fromJson({...validJson, 'createdAt': 42}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.createdAt must be a string',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson, 'taskId': 42}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.taskId must be a string',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson, 'status': false}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.status must be a string',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson}..remove('taskId')),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.taskId is required',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson}..remove('status')),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.status is required',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson, 'lastUpdatedAt': false}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.lastUpdatedAt must be a string',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson, 'ttl': 1.5}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.ttl must be an integer or null',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson, 'pollInterval': '1000'}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.pollInterval must be an integer or null',
            ),
          ),
        );
        expect(
          () => Task.fromJson({...validJson, 'statusMessage': 42}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Task.statusMessage must be a string',
            ),
          ),
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

    group('Spec gap regressions', () {
      test('metadata helpers emit stable 2025-11-25 shapes', () {
        final root = Root(
          uri: 'file:///workspace',
          name: 'workspace',
          meta: {'scope': 'repo'},
        );
        expect(root.toJson()['_meta'], {'scope': 'repo'});

        final resource = const Resource(
          uri: 'file:///workspace/file.txt',
          name: 'file',
          size: 123,
          annotations: ResourceAnnotations(title: 'legacy-title'),
        );
        final resourceJson = resource.toJson();
        expect(resourceJson['size'], 123);
        expect(resourceJson['annotations'], isNot(contains('title')));
        expect(
          ResourceAnnotations.fromJson({
            'title': 'legacy-title',
            'priority': 0.5,
          }).title,
          'legacy-title',
        );
      });

      test('request parsing prefers params metadata over top-level metadata',
          () {
        final parsed = JsonRpcMessage.fromJson(
          const {
            'jsonrpc': jsonRpcVersion,
            'id': 'tools',
            'method': Method.toolsList,
            '_meta': {'progressToken': 'top-level'},
            'params': {
              '_meta': {'progressToken': 'params-nested'},
            },
          },
        );

        expect(parsed, isA<JsonRpcListToolsRequest>());
        final request = parsed as JsonRpcListToolsRequest;
        expect(request.meta, {'progressToken': 'params-nested'});
        expect(request.progressToken, 'params-nested');
      });

      test('server capabilities omit non-stable fields while parsing legacy',
          () {
        final capabilities = const ServerCapabilities(
          tasks: ServerCapabilitiesTasks(listChanged: true),
          elicitation: ServerCapabilitiesElicitation.formOnly(),
        );

        final json = capabilities.toJson();
        expect(json['tasks'], isNot(contains('listChanged')));
        expect(json.containsKey('elicitation'), isFalse);

        final parsed = ServerCapabilities.fromJson({
          'tasks': {'listChanged': true},
          'elicitation': {
            'form': {},
          },
        });
        expect(parsed.tasks?.listChanged, isTrue);
        expect(parsed.elicitation?.form, isNotNull);
      });

      test('JSON-RPC response id follows MCP result/error schema', () {
        expect(
          () => JsonRpcMessage.fromJson({
            'jsonrpc': '2.0',
            'id': null,
            'result': {},
          }),
          throwsA(isA<FormatException>()),
        );

        final error = JsonRpcError(
          id: null,
          error: JsonRpcErrorData(
            code: ErrorCode.invalidRequest.value,
            message: 'Invalid request',
          ),
        ).toJson();
        expect(error.containsKey('id'), isFalse);

        final parsed = JsonRpcError.fromJson({
          'jsonrpc': '2.0',
          'error': {
            'code': ErrorCode.invalidRequest.value,
            'message': 'Invalid request',
          },
        });
        expect(parsed.id, isNull);
      });

      test('tool schemas must be object-root JSON Schema objects', () {
        expect(
          () => const Tool(
            name: 'bad-tool',
            inputSchema: JsonString(),
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => Tool.fromJson({
            'name': 'bad-tool',
            'inputSchema': {'type': 'string'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Tool.fromJson({'name': 'missing-schema'}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Tool.inputSchema is required'),
            ),
          ),
        );
        expect(
          () => Tool.fromJson({
            'name': 'bad-input-schema',
            'inputSchema': 'not-an-object',
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Tool.inputSchema must be a JSON object'),
            ),
          ),
        );
        expect(
          () => Tool.fromJson({
            'name': 'bad-output-schema',
            'inputSchema': {'type': 'object'},
            'outputSchema': 'not-an-object',
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Tool.outputSchema must be a JSON object'),
            ),
          ),
        );
      });

      test('elicitation validates restricted form and result wire shapes', () {
        final request = ElicitRequest.form(
          message: 'Choose',
          requestedSchema: JsonObject(
            properties: {
              'size': JsonSchema.string(enumValues: ['small', 'large']),
            },
            required: const ['size'],
          ),
        );
        expect(request.toJson()['requestedSchema']['type'], 'object');

        expect(
          () => ElicitRequest.form(
            message: 'Fractional bounds',
            requestedSchema: JsonSchema.object(
              properties: {
                'ratio': JsonSchema.number(
                  minimum: 0.1,
                  maximum: 0.9,
                  defaultValue: 0.5,
                ),
              },
            ),
          ).toJson(),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const ElicitRequest.form(
            message: 'Nested',
            requestedSchema: JsonObject(
              properties: {'nested': JsonObject()},
            ),
          ).toJson(),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ElicitResult.fromJson({
            'action': 'accept',
            'content': {
              'bad': ['ok', 1],
            },
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const ElicitResult(
            action: 'accept',
            content: {
              'bad': ['ok', 1],
            },
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => ElicitResult.fromJson({
            'action': 'accept',
            'content': {
              'fractional': 1.5,
            },
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const ElicitResult(
            action: 'accept',
            content: {
              'fractional': 1.5,
            },
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => URLElicitationRequiredErrorData.fromJson({
            'elicitations': [
              request.toJson(),
            ],
          }),
          throwsA(isA<FormatException>()),
        );
        for (final parse in <Object Function()>[
          () => JsonRpcElicitRequest.fromJson({
                'jsonrpc': jsonRpcVersion,
                'id': 1,
                'method': Method.elicitationCreate,
                'params': 'bad',
              }),
          () => ElicitRequest.fromJson({
                'message': 'Bad schema',
                'requestedSchema': 'bad',
              }),
          () => ElicitResult.fromJson({
                'action': 'accept',
                'elicitationId': 1,
              }),
          () => ElicitationCompleteNotification.fromJson({
                'elicitationId': 1,
              }),
          () => JsonRpcElicitationCompleteNotification.fromJson({
                'jsonrpc': jsonRpcVersion,
                'method': Method.notificationsElicitationComplete,
                'params': null,
              }),
          () => URLElicitationRequiredErrorData.fromJson({
                'elicitations': [1],
              }),
        ]) {
          expect(parse, throwsA(isA<FormatException>()));
        }
      });

      test('initialization and capability wire fields reject bad shapes', () {
        final initializeRequest = {
          'protocolVersion': latestProtocolVersion,
          'capabilities': <String, dynamic>{},
          'clientInfo': {'name': 'client', 'version': '1.0.0'},
        };
        final initializeResult = {
          'protocolVersion': latestProtocolVersion,
          'capabilities': <String, dynamic>{},
          'serverInfo': {'name': 'server', 'version': '1.0.0'},
        };

        for (final parse in <Object Function()>[
          () => InitializeRequest.fromJson({
                ...initializeRequest,
                'protocolVersion': 1,
              }),
          () => InitializeRequest.fromJson({
                ...initializeRequest,
                'capabilities': 'bad',
              }),
          () => InitializeRequest.fromJson({
                ...initializeRequest,
                'clientInfo': 'bad',
              }),
          () => InitializeResult.fromJson({
                ...initializeResult,
                'capabilities': 'bad',
              }),
          () => InitializeResult.fromJson({
                ...initializeResult,
                'instructions': 1,
              }),
          () => ClientCapabilitiesRoots.fromJson({'listChanged': 'true'}),
          () => ServerCapabilitiesResources.fromJson({'subscribe': 'true'}),
        ]) {
          expect(parse, throwsA(isA<FormatException>()));
        }
      });

      test('runtime value constraints are enforced without asserts', () {
        expect(
          () => Annotations(priority: 2).toJson(),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
        expect(
          () => Annotations.fromJson({'priority': -0.1}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Annotations(priority: double.nan).toJson(),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
        expect(
          () => Annotations.fromJson({'priority': double.infinity}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Annotations.fromJson({
            'audience': ['model'],
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Annotations.fromJson({'lastModified': 1}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CompletionResultData(
            values: List.generate(101, (index) => '$index'),
          ).toJson(),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
        expect(
          () => CompletionResultData.fromJson({
            'values': List.generate(101, (index) => '$index'),
          }),
          throwsA(isA<FormatException>()),
        );
        final completion = CompletionResultData.fromJson({
          'values': ['a'],
          'total': 10.0,
        });
        expect(completion.total, 10);
        expect(completion.toJson()['total'], 10);
        expect(
          () => CompletionResultData.fromJson({
            'values': ['a'],
            'total': 10.5,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Root(uri: 'https://example.com'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => Root.fromJson({'uri': 'relative/path'}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ModelPreferences(costPriority: 2).toJson(),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
        expect(
          () => ModelPreferences.fromJson({'costPriority': -1}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingMessage.fromJson({
            'role': 'system',
            'content': {'type': 'text', 'text': 'Hello'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageResult.fromJson({
            'role': 'system',
            'content': {'type': 'text', 'text': 'Hello'},
            'model': 'model',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => PromptMessage.fromJson({
            'role': 'system',
            'content': {'type': 'text', 'text': 'Hello'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SetLevelRequestParams.fromJson({'level': 'verbose'}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LoggingMessageNotificationParams.fromJson({
            'level': 'verbose',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LoggingMessageNotificationParams.fromJson({
            'level': 'info',
            'data': Object(),
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => PromptArgument.fromJson({'name': 1}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Prompt.fromJson({
            'name': 'prompt',
            'arguments': [1],
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => GetPromptRequest.fromJson({
            'name': 'prompt',
            'arguments': {'arg': 1},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CompleteRequest.fromJson({
            'ref': {'type': 'ref/prompt', 'name': 'prompt'},
            'argument': {'name': 'arg', 'value': 1},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CompletionResultData.fromJson({
            'values': ['a'],
            'hasMore': 'true',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ProgressNotification.fromJson({
            'progressToken': 'progress-1',
            'progress': 1,
            'message': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequestParams.fromJson({
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Hello'},
              },
            ],
            'maxTokens': 100,
            'includeContext': 'nearbyServers',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequestParams.fromJson({
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Hello'},
              },
            ],
            'maxTokens': 100,
            'toolChoice': {'mode': 'sometimes'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequestParams.fromJson({
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Hello'},
              },
            ],
            'maxTokens': 100,
            'tools': 'bad',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequestParams.fromJson({
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Hello'},
              },
            ],
            'maxTokens': 100,
            'tools': [1],
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ModelHint.fromJson({'name': 1}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingContent.fromJson({
            'type': 'text',
            'text': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingTextContent.fromJson({
            'text': 'Hello',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingTextContent.fromJson({
            'type': 'image',
            'text': 'Hello',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingImageContent.fromJson({
            'type': 'text',
            'data': 'aW1nZGF0YQ==',
            'mimeType': 'image/png',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingAudioContent.fromJson({
            'type': 'image',
            'data': 'YXVkaW8tZGF0YQ==',
            'mimeType': 'audio/wav',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolUseContent.fromJson({
            'type': 'tool_result',
            'id': 'call-1',
            'name': 'search',
            'input': <String, dynamic>{},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolResultContent.fromJson({
            'type': 'tool_use',
            'toolUseId': 'call-1',
            'content': [
              {'type': 'text', 'text': 'Hello'},
            ],
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolResultContent.fromJson({
            'type': 'tool_result',
            'toolUseId': 'call-1',
            'content': [
              {'type': 'text', 'text': 'Hello'},
            ],
            'isError': 'false',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequestParams.fromJson({
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Hello'},
              },
            ],
            'maxTokens': 100,
            'stopSequences': ['STOP', 1],
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageResult.fromJson({
            'role': 'assistant',
            'content': {'type': 'text', 'text': 'Hello'},
            'model': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Content.fromJson({
            'type': 1,
            'text': 'Hello',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Content.fromJson({
            'text': 'Hello',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Content.fromJson({
            'type': 'unknown',
            'text': 'Hello',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => TextContent.fromJson({
            'type': 'image',
            'text': 'Hello',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => TextContent.fromJson({
            'type': 'text',
            'text': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ResourceContents.fromJson({
            'uri': 'file:///docs/readme.md',
            'text': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ResourceContents.fromJson({
            'uri': 'file:///docs/readme.md',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ResourceLink.fromJson({
            'type': 'resource_link',
            'uri': 'file:///docs/readme.md',
            'name': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ResourceLink.fromJson({
            'type': 'resource',
            'uri': 'file:///docs/readme.md',
            'name': 'readme',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Resource.fromJson({
            'uri': 'file:///docs/readme.md',
            'name': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ResourceTemplate.fromJson({
            'uriTemplate': 'file:///{path}',
            'name': 1,
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('bare task containers strip task metadata', () {
        const task = Task(
          taskId: 'task-1',
          status: TaskStatus.working,
          ttl: null,
          createdAt: '2025-01-15T10:00:00Z',
          lastUpdatedAt: '2025-01-15T10:01:00Z',
          meta: {'trace': 'result-only'},
        );

        expect(task.toJson(), contains('_meta'));
        expect(
          const ListTasksResult(tasks: [task]).toJson()['tasks'].single,
          isNot(contains('_meta')),
        );
        expect(
          const CreateTaskResult(task: task).toJson()['task'],
          isNot(contains('_meta')),
        );
      });

      test('strict incoming result arrays reject missing required lists', () {
        expect(
          () => ListRootsResult.fromJson({}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ListResourcesResult.fromJson({}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ListPromptsResult.fromJson({}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ListToolsResult.fromJson({}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ListTasksResult.fromJson({}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequest.fromJson({'maxTokens': 1}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolResultContent.fromJson({
            'toolUseId': 'tool-use-1',
            'content': {'type': 'text', 'text': 'legacy'},
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
