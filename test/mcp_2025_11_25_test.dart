import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';
// Import McpServer for testing

void main() {
  group('MCP 2025-11-25 Protocol Updates', () {
    test('Protocol Version', () {
      expect(latestProtocolVersion, '2025-11-25');
    });

    test('Implementation Description', () {
      final impl = Implementation(
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
      final icon = ImageContent(data: 'base64', mimeType: 'image/png');

      final tool = Tool(
        name: 'test-tool',
        inputSchema: ToolInputSchema(),
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
      final params = ElicitRequestParams(
        message: 'test',
        requestedSchema: {},
        url: 'https://example.com/ui',
      );

      expect(params.url, 'https://example.com/ui');

      final json = params.toJson();
      expect(json['url'], 'https://example.com/ui');

      final deserialized = ElicitRequestParams.fromJson(json);
      expect(deserialized.url, 'https://example.com/ui');
    });

    test('EnumInputSchema SEP-1330', () {
      final schema = EnumInputSchema(
        values: [
          'simple',
          {'value': 'complex', 'title': 'Complex Option'},
        ],
      );

      expect(schema.values.length, 2);
      expect(schema.values[0], 'simple');
      expect((schema.values[1] as Map)['title'], 'Complex Option');

      final json = schema.toJson();
      expect(json['values'], hasLength(2));

      final deserialized = EnumInputSchema.fromJson(json);
      expect(deserialized.values[0], 'simple');
      expect((deserialized.values[1] as Map)['value'], 'complex');
    });

    test('ToolAnnotations SEP-???', () {
      final annotations = ToolAnnotations(
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
      final result = ElicitResult(
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
      final server = McpServer(Implementation(name: 'test', version: '1.0'));
      final icon = ImageContent(data: 'data', mimeType: 'image/png');
      // We can rely on the fact that we updated the code to pass it through.

      // Let's rely on the previous unit tests for `Tool` serialization, and here just ensure `McpServer` methods don't crash.

      server.resource(
        'icon-resource',
        'file:///test',
        (uri, extra) => ReadResourceResult(contents: []),
        icon: icon,
      );

      server.prompt(
        'icon-prompt',
        icon: icon,
      );
    });

    test('Tasks Capabilities', () {
      final clientCaps = ClientCapabilities(
        tasks: {
          'requests': {
            'sampling': {'createMessage': {}}
          }
        },
      );
      expect(clientCaps.tasks, isNotNull);
      expect(clientCaps.toJson()['tasks'], isNotNull);

      final serverCaps = ServerCapabilities(
        tasks: {'list': {}, 'cancel': {}},
        completions: ServerCapabilitiesCompletions(listChanged: true),
      );
      expect(serverCaps.tasks, isNotNull);
      expect(serverCaps.toJson()['tasks'], isNotNull);
      expect(serverCaps.completions?.listChanged, isTrue);
      expect(serverCaps.toJson()['completions']['listChanged'], isTrue);
    });

    test('Task Types', () {
      final task = Task(
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
            inputSchema: ToolInputSchema(
              properties: {
                'expr': {'type': 'string'}
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
  });
}
