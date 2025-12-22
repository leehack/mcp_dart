import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/create_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

class MockProgress extends Mock implements Progress {}

class MockMasonGenerator extends Mock implements MasonGenerator {}

class MockGeneratorTarget extends Mock implements GeneratorTarget {}

class TestCreateCommand extends CreateCommand {
  TestCreateCommand({
    super.logger,
    super.generatorFromBrick,
  });

  final List<List<String>> processCalls = [];

  @override
  Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    processCalls.add([executable, ...arguments]);
    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  group('CreateCommand', () {
    late Logger logger;
    late MasonGenerator generator;
    late TestCreateCommand command;
    late CommandRunner<int> runner;
    late Directory tempDir;
    late Directory originalCwd;

    setUpAll(() {
      registerFallbackValue(DirectoryGeneratorTarget(Directory.current));
      registerFallbackValue(Directory.current);
    });

    setUp(() {
      logger = MockLogger();
      generator = MockMasonGenerator();
      tempDir = Directory.systemTemp.createTempSync('mcp_dart_cli_test');
      originalCwd = Directory.current;
      Directory.current = tempDir;

      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.prompt(any(), defaultValue: any(named: 'defaultValue')))
          .thenReturn('test_project');
      when(
        () => generator.generate(
          any(),
          vars: any(named: 'vars'),
          fileConflictResolution: any(named: 'fileConflictResolution'),
        ),
      ).thenAnswer((_) async => []);

      command = TestCreateCommand(
        logger: logger,
        generatorFromBrick: (_) async => generator,
      );
      runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);
    });

    tearDown(() {
      try {
        Directory.current = originalCwd;
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('can be instantiated', () {
      expect(command, isA<CreateCommand>());
    });

    test('has correct name and description', () {
      expect(command.name, equals('create'));
      expect(command.description, equals('Creates a new MCP server project.'));
    });

    group('Argument Parsing', () {
      test('prompts for project name if not provided (default path)', () async {
        when(() =>
                logger.prompt(any(), defaultValue: any(named: 'defaultValue')))
            .thenReturn('my_prompted_pkg');

        final result = await runner.run(['create']);

        expect(result, equals(ExitCode.success.code));

        verify(() => logger.prompt(
              'What is the project name?',
              defaultValue: 'mcp_server',
            )).called(1);

        verify(() => generator.generate(
              any(
                  that: isA<DirectoryGeneratorTarget>().having(
                      (t) => t.dir.path,
                      'dir.path',
                      equals('my_prompted_pkg'))),
              vars:
                  any(named: 'vars', that: equals({'name': 'my_prompted_pkg'})),
            )).called(1);
      });

      test('uses explicit package name and default path', () async {
        final result = await runner.run(['create', 'my_package']);

        expect(result, equals(ExitCode.success.code));

        verify(() => generator.generate(
              any(
                  that: isA<DirectoryGeneratorTarget>().having(
                      (t) => t.dir.path, 'dir.path', equals('my_package'))),
              vars: any(named: 'vars', that: equals({'name': 'my_package'})),
            )).called(1);
      });

      test('uses explicit package name and explicit path', () async {
        final projectDir = Directory('custom_dir');

        final result =
            await runner.run(['create', 'my_package', projectDir.path]);

        expect(result, equals(ExitCode.success.code));

        verify(() => generator.generate(
              any(
                  that: isA<DirectoryGeneratorTarget>().having(
                      (t) => t.dir.path, 'dir.path', equals(projectDir.path))),
              vars: any(named: 'vars', that: equals({'name': 'my_package'})),
            )).called(1);

        expect(
            command.processCalls,
            containsAllInOrder([
              ['dart', 'pub', 'get'],
              ['dart', 'pub', 'add', 'mcp_dart'],
              ['dart', 'format', '.'],
            ]));
      });

      test('infers package name from path (valid name)', () async {
        final result = await runner.run(['create', 'valid_name']);

        expect(result, equals(ExitCode.success.code));

        verify(() => generator.generate(
              any(),
              vars: any(named: 'vars', that: equals({'name': 'valid_name'})),
            )).called(1);
      });

      test('infers package name from path . (current dir)', () async {
        final result = await runner.run(['create', '.']);

        expect(result, equals(ExitCode.success.code));

        verify(() => generator.generate(
              any(
                  that: isA<DirectoryGeneratorTarget>().having(
                      (t) =>
                          t.dir.path == '.' ||
                          t.dir.path.endsWith('mcp_dart_cli_test') ||
                          t.dir.path.contains('mcp_dart_cli_test'),
                      'dir.path',
                      isTrue)),
              vars: any(named: 'vars', that: isA<Map<String, dynamic>>()),
            )).called(1);
      });

      test('infers sanitized package name from path with dashes', () async {
        final result = await runner.run(['create', './my-project']);

        expect(result, equals(ExitCode.success.code));

        verify(() => generator.generate(
              any(),
              vars: any(named: 'vars', that: equals({'name': 'my_project'})),
            )).called(1);
      });

      test('infers sanitized package name from path starting with number',
          () async {
        final result = await runner.run(['create', './123test']);

        expect(result, equals(ExitCode.success.code));

        verify(() => generator.generate(
              any(),
              vars: any(named: 'vars', that: equals({'name': 'mcp_123test'})),
            )).called(1);
      });
    });

    test('fails if directory exists and is not empty', () async {
      final projectDir = Directory('${tempDir.path}/existing');
      projectDir.createSync();
      File('${projectDir.path}/file.txt').createSync();

      final result = await runner.run(['create', 'pkg', projectDir.path]);

      expect(result, equals(ExitCode.cantCreate.code));
      verify(() => logger.err(any(that: contains('already exists')))).called(1);

      verifyNever(() => generator.generate(any(), vars: any(named: 'vars')));
    });
  });
}
