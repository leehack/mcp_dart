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

    group('with temp directory', () {
      late Directory tempDir;
      late Directory originalCwd;

      setUp(() {
        originalCwd = Directory.current;
        tempDir = Directory.systemTemp.createTempSync();
        tempDir = Directory(tempDir.resolveSymbolicLinksSync());
        Directory.current = tempDir;
      });

      tearDown(() {
        Directory.current = originalCwd;
        tempDir.deleteSync(recursive: true);
      });

      test('fails if pubspec.yaml is missing', () async {
        final runner = CommandRunner<int>('mcp_dart', 'CLI')
          ..addCommand(command);
        final exitCode = await runner.run(['serve']);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(() => logger.err(
            'Error: pubspec.yaml not found in current directory.')).called(1);
      });
    });
  });
}
