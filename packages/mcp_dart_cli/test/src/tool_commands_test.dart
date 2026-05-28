import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/tool_commands.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('ListToolsCommand', () {
    late Logger logger;
    late ListToolsCommand command;

    setUp(() {
      logger = MockLogger();
      command = ListToolsCommand(logger: logger);
    });

    test('has connection and JSON options', () {
      expect(command.argParser.options.containsKey('command'), isTrue);
      expect(command.argParser.options.containsKey('server-args'), isTrue);
      expect(command.argParser.options.containsKey('env'), isTrue);
      expect(command.argParser.options.containsKey('json'), isTrue);
    });

    test('lists tools from a Dart stdio server command', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'list-tools',
        '--',
        'dart',
        'run',
        'test/fixtures/tools_resources_server.dart',
      ]);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('Tools:')).called(1);
      verify(
        () => logger.info('  - echo: Echoes text.'),
      ).called(1);
    });
  });

  group('CallToolCommand', () {
    late Logger logger;
    late CallToolCommand command;

    setUp(() {
      logger = MockLogger();
      command = CallToolCommand(logger: logger);
    });

    test('requires a tool name', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run(['call-tool']);

      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err('Missing required tool name.')).called(1);
    });

    test('calls a tool on a Dart stdio server command', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'call-tool',
        'echo',
        '--json-args',
        '{"message":"hello"}',
        '--',
        'dart',
        'run',
        'test/fixtures/tools_resources_server.dart',
      ]);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('Result:')).called(1);
      verify(
        () => logger.info(
          any(that: contains('Echo: hello')),
        ),
      ).called(1);
    });
  });
}
