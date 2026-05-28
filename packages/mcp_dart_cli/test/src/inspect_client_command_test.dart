import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/inspect_client_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('InspectClientCommand', () {
    late Logger logger;
    late InspectClientCommand command;

    setUp(() {
      logger = MockLogger();
      command = InspectClientCommand(logger: logger);
    });

    test('requires report path', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run(['inspect-client']);

      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err('--report is required for inspect-client.'))
          .called(1);
    });

    test('has timeout options', () {
      expect(command.argParser.options.containsKey('report'), isTrue);
      expect(command.argParser.options.containsKey('idle-timeout-ms'), isTrue);
      expect(command.argParser.options.containsKey('max-runtime-ms'), isTrue);
    });
  });
}
