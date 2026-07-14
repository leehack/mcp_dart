import 'dart:convert';
import 'dart:io';

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

    test(
      'json output stays parseable when server sends notifications',
      () async {
        final result = await Process.run(
          'dart',
          <String>[
            'run',
            'bin/mcp_dart.dart',
            'list-tools',
            '--json',
            '--wait',
            '50',
            '--',
            'dart',
            'run',
            'test/fixtures/raw_stdio_server.dart',
            '--notify-after-list',
          ],
          workingDirectory: Directory.current.path,
        );

        expect(result.exitCode, equals(ExitCode.success.code));
        final json =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(json['tools'], isA<List<dynamic>>());
      },
    );

    test('json mode runs in-process with silent handlers', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'list-tools',
        '--json',
        '--',
        'dart',
        'run',
        'test/fixtures/raw_stdio_server.dart',
        '--notify-after-list',
      ]);

      expect(result, equals(ExitCode.success.code));
      verifyNever(() => logger.info(any()));
      verifyNever(() => logger.warn(any()));
      verifyNever(() => logger.err(any()));
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

    test(
      'json output stays parseable when tool call sends notifications',
      () async {
        final result = await Process.run(
          'dart',
          <String>[
            'run',
            'bin/mcp_dart.dart',
            'call-tool',
            'echo',
            '--json',
            '--wait',
            '50',
            '--json-args',
            '{"message":"hello"}',
            '--',
            'dart',
            'run',
            'test/fixtures/raw_stdio_server.dart',
            '--notify-after-call',
          ],
          workingDirectory: Directory.current.path,
        );

        expect(result.exitCode, equals(ExitCode.success.code));
        final json =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final content = json['content'] as List<dynamic>;
        expect((content.single as Map<String, dynamic>)['text'], equals('ok'));
      },
    );

    test('json mode runs in-process with silent handlers', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'call-tool',
        'echo',
        '--json',
        '--json-args',
        '{"message":"hello"}',
        '--',
        'dart',
        'run',
        'test/fixtures/raw_stdio_server.dart',
        '--notify-after-call',
      ]);

      expect(result, equals(ExitCode.success.code));
      verifyNever(() => logger.info(any()));
      verifyNever(() => logger.warn(any()));
      verifyNever(() => logger.err(any()));
    });
  });
}
