import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/serve_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('ServeCommand', () {
    late Logger logger;
    late ServeCommand command;

    setUp(() {
      logger = MockLogger();
      command = ServeCommand(logger: logger);
    });

    test('can be instantiated', () {
      expect(command, isA<ServeCommand>());
    });

    test('has correct name and description', () {
      expect(command.name, equals('serve'));
      expect(command.description,
          equals('Runs the MCP server in the current directory.'));
    });

    test('fails if pubspec.yaml is missing', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      await IOOverrides.runZoned(
        () async {
          final tempDir = Directory.systemTemp.createTempSync();
          addTearDown(() => tempDir.deleteSync(recursive: true));

          // We can't easily change Directory.current for the *code under test* unless we spawn a process or use IOOverrides to intercept File calls?
          // No, IOOverrides intercepts `File()` but `File('foo')` still resolves relative to `Directory.current`.

          // Actually, `Directory.current` is settable.
          final originalCwd = Directory.current;
          Directory.current = tempDir;
          addTearDown(() => Directory.current = originalCwd);

          final exitCode = await runner.run(['serve']);

          expect(exitCode, equals(ExitCode.usage.code));
          verify(() => logger.err(
              'Error: pubspec.yaml not found in current directory.')).called(1);
        },
      );
    });
  });
}
