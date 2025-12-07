import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Types', () {
    test('Task JSON serialization', () {
      final task = Task(
        taskId: '123',
        status: TaskStatus.working,
        statusMessage: 'In progress',
        createdAt: '2025-01-01T00:00:00Z',
        lastUpdatedAt: '2025-01-01T00:01:00Z',
        ttl: 60000,
        pollInterval: 5000,
      );

      final json = task.toJson();
      expect(json['taskId'], '123');
      expect(json['status'], 'working');
      expect(json['statusMessage'], 'In progress');
      expect(json['ttl'], 60000);

      final deserialized = Task.fromJson(json);
      expect(deserialized.taskId, task.taskId);
      expect(deserialized.status, task.status);
      expect(deserialized.pollInterval, task.pollInterval);
    });

    test('EnumInputSchema with new fields', () {
      final schema = EnumInputSchema(
        enumValues: ['a', 'b'],
        titled: true,
        untitled: false,
        singleSelect: true,
        multiSelect: false,
      );

      final json = schema.toJson();
      expect(json['titled'], true);
      expect(json['singleSelect'], true);

      final deserialized = EnumInputSchema.fromJson(json);
      expect(deserialized.titled, true);
      expect(deserialized.multiSelect, false); // From default/null in JSON? Wait, it was false in constructor.
      // json['multiSelect'] is false, so it should be false.
    });

    test('Resource with icon', () {
      final resource = Resource(
        uri: 'file:///tmp/foo',
        name: 'foo',
        icon: 'https://example.com/icon.png',
      );

      final json = resource.toJson();
      expect(json['icon'], 'https://example.com/icon.png');

      final deserialized = Resource.fromJson(json);
      expect(deserialized.icon, 'https://example.com/icon.png');
    });

    test('CreateMessageRequestParams with tools', () {
      final tool = Tool(
        name: 'my_tool',
        inputSchema: ToolInputSchema(properties: {'x': {}}),
      );
      final params = CreateMessageRequestParams(
        messages: [],
        maxTokens: 100,
        tools: [tool],
        toolChoice: {'type': 'auto'},
      );

      final json = params.toJson();
      expect(json['tools'], isNotNull);
      expect((json['tools'] as List).length, 1);
      expect(json['toolChoice'], {'type': 'auto'});

      final deserialized = CreateMessageRequestParams.fromJson(json);
      expect(deserialized.tools?.length, 1);
      expect(deserialized.tools?.first.name, 'my_tool');
      expect(deserialized.toolChoice, {'type': 'auto'});
    });

    test('ServerCapabilities with tasks', () {
      final caps = ServerCapabilities(
        tasks: ServerCapabilitiesTasks(
          list: true,
          cancel: true,
        ),
      );

      final json = caps.toJson();
      expect(json['tasks']['list'], isNotNull);
      expect(json['tasks']['cancel'], isNotNull);

      final deserialized = ServerCapabilities.fromJson(json);
      expect(deserialized.tasks?.list, true);
      expect(deserialized.tasks?.cancel, true);
    });
  });
}
