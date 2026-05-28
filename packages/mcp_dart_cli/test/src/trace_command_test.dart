import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/trace_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('TraceCommand', () {
    late Logger logger;
    late TraceCommand command;

    setUp(() {
      logger = MockLogger();
      command = TraceCommand(logger: logger);
    });

    test('requires report path', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run(['trace', '--', 'dart']);

      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err('--report is required for trace.')).called(1);
    });

    test('has proxy options', () {
      expect(command.argParser.options.containsKey('report'), isTrue);
      expect(command.argParser.options.containsKey('server-cwd'), isTrue);
      expect(command.argParser.options.containsKey('env'), isTrue);
      expect(command.argParser.options.containsKey('max-runtime-ms'), isTrue);
    });
  });
}
