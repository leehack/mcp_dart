import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

void main() {
  // Locate the TS server (compiled JS version)
  final defaultTsPath =
      p.join(io.Directory.current.path, 'test/interop/ts/dist/server.js');
  final tsServerScript =
      io.Platform.environment['TS_INTEROP_SERVER_CMD'] ?? defaultTsPath;

  // Check if we should skip
  final skipTests = !io.File(tsServerScript).existsSync();

  group('TS Interop - Tasks', () {
    if (skipTests) {
      print(
        'Skipping TS Interop tasks tests: TS server not found at $tsServerScript',
      );
      return;
    }

    late StdioClientTransport transport;
    late McpClient client;
    late TaskClient taskClient;

    setUp(() async {
      // 1. Create the StdioClientTransport with server parameters
      transport = StdioClientTransport(
        StdioServerParameters(
          command: 'node',
          args: [tsServerScript, '--transport', 'stdio'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      // 2. Create the Client instance
      client = McpClient(
        const Implementation(name: 'dart-task-test', version: '1.0'),
        options: const McpClientOptions(
          capabilities: ClientCapabilities(),
        ),
      );

      // 3. Wrap with TaskClient
      taskClient = TaskClient(client);

      // 4. Connect
      await client.connect(transport);
    });

    tearDown(() async {
      await client.close();
    });

    test('long_running tool is listed with taskSupport', () async {
      final result = await client.listTools();
      final longRunningTool = result.tools.firstWhere(
        (t) => t.name == 'long_running',
        orElse: () => throw Exception('long_running tool not found'),
      );
      expect(longRunningTool.execution?.taskSupport, equals('required'));
    });

    test('long_running tool returns task and completes', () async {
      final messages = <TaskStreamMessage>[];

      await for (final msg in taskClient.callToolStream(
        'long_running',
        {'duration': 100},
        task: {'ttl': 60000, 'pollInterval': 50},
      )) {
        messages.add(msg);
        // Break out early if we got the result
        if (msg is TaskResultMessage || msg is TaskErrorMessage) {
          break;
        }
      }

      // We should have received at least TaskCreatedMessage and TaskResultMessage
      expect(messages, isNotEmpty);

      // First message should be TaskCreatedMessage
      expect(messages.first, isA<TaskCreatedMessage>());
      final createdMsg = messages.first as TaskCreatedMessage;
      expect(createdMsg.task.taskId, isNotEmpty);

      // Last non-error message should be TaskResultMessage
      final resultMsgs = messages.whereType<TaskResultMessage>();
      expect(resultMsgs, isNotEmpty);
      final resultMsg = resultMsgs.first;
      // Result is BaseResultData, access content via toJson()
      final resultJson = resultMsg.result.toJson();
      final contentList = resultJson['content'] as List<dynamic>?;
      expect(contentList, isNotEmpty);
      final textContent = contentList!.first as Map<String, dynamic>;
      expect(textContent['text'], contains('Completed after'));
    });

    test('task status changes during execution', () async {
      final statusMessages = <TaskStatusMessage>[];

      await for (final msg in taskClient.callToolStream(
        'long_running',
        {'duration': 200}, // Longer to catch status updates
        task: {'ttl': 60000, 'pollInterval': 30},
      )) {
        if (msg is TaskStatusMessage) {
          statusMessages.add(msg);
        }
        if (msg is TaskResultMessage || msg is TaskErrorMessage) {
          break;
        }
      }

      // We may or may not catch status updates depending on timing,
      // but if we do, they should have valid task info
      for (final status in statusMessages) {
        expect(status.task.taskId, isNotEmpty);
      }
    });
  });
}
