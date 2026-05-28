import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/inspect_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('InspectCommand', () {
    late Logger logger;
    late InspectCommand command;

    setUp(() {
      logger = MockLogger();
      command = InspectCommand(logger: logger);
    });

    test('can be instantiated', () {
      expect(command, isA<InspectCommand>());
    });

    test('has correct name', () {
      expect(command.name, 'inspect');
    });

    test('arg parser supports command and server-args flags', () {
      final parser = command.argParser;
      expect(parser.options.containsKey('command'), isTrue);
      expect(parser.options.containsKey('server-args'), isTrue);
      // env is multi-option
      expect(parser.options.containsKey('env'), isTrue);
    });

    test('arg parser supports json-args option', () {
      expect(command.argParser.options.containsKey('json-args'), isTrue);
    });

    test('lists only advertised capabilities', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'inspect',
        'dart',
        'run',
        'test/fixtures/tools_resources_server.dart',
      ]);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('Tools:')).called(1);
      verify(() => logger.info('Resources:')).called(1);
      verify(() => logger.info('Prompts: (None)')).called(1);
      verifyNever(
        () => logger.err(any(that: startsWith('Failed to list capabilities'))),
      );
    });
  });
}
