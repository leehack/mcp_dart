import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/create_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

class MockProgress extends Mock implements Progress {}

void main() {
  group('CreateCommand', () {
    late Logger logger;
    late CreateCommand command;

    setUp(() {
      logger = MockLogger();
      command = CreateCommand(logger: logger);
      when(() => logger.progress(any())).thenReturn(MockProgress());
    });

    test('can be instantiated', () {
      expect(command, isA<CreateCommand>());
    });

    test('has correct name and description', () {
      expect(command.name, equals('create'));
      expect(command.description, equals('Creates a new MCP server project.'));
    });

    test('validates PROJECT_NAME argument is provided', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run(['create']);

      expect(exitCode, equals(ExitCode.usage.code));
      verify(() =>
              logger.err('Usage: mcp_dart create <project_name> [arguments]'))
          .called(1);
    });
  });
}
