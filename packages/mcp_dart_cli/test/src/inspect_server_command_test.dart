import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/inspect_server_command.dart';
import 'package:mcp_dart_cli/src/inspectors/inspection_report.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('InspectServerCommand', () {
    late Logger logger;
    late InspectServerCommand command;

    setUp(() {
      logger = MockLogger();
      command = InspectServerCommand(logger: logger);
    });

    test('has connection and report options', () {
      expect(command.argParser.options.containsKey('command'), isTrue);
      expect(command.argParser.options.containsKey('server-args'), isTrue);
      expect(command.argParser.options.containsKey('env'), isTrue);
      expect(command.argParser.options.containsKey('probe-config'), isTrue);
      expect(command.argParser.options.containsKey('json'), isTrue);
      expect(command.argParser.options.containsKey('strict'), isTrue);
    });

    test('parses explicit probe config', () {
      final config = InspectionProbeConfig.fromJson(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'echo',
            'arguments': <String, dynamic>{'message': 'hello'},
          },
        ],
        'resource': <String, dynamic>{
          'uri': 'resource://test',
          'subscribe': true,
        },
        'prompt': <String, dynamic>{
          'name': 'greeting',
          'arguments': <String, dynamic>{'name': 'Dart'},
        },
        'completion': <String, dynamic>{
          'prompt': 'greeting',
          'argument': 'name',
          'value': 'D',
        },
        'task': <String, dynamic>{
          'tool': 'delayed_echo',
          'arguments': <String, dynamic>{'message': 'cancel me'},
          'cancel': true,
        },
      });

      expect(config.toolCalls.single.name, equals('echo'));
      expect(config.resource?.uri, equals('resource://test'));
      expect(config.resource?.subscribe, isTrue);
      expect(config.prompt?.arguments, containsPair('name', 'Dart'));
      expect(config.completion?.value, equals('D'));
      expect(config.task?.tool, equals('delayed_echo'));
      expect(config.task?.cancel, isTrue);
    });

    test('inspects a Dart stdio server command', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'inspect-server',
        '--',
        'dart',
        'run',
        'test/fixtures/tools_resources_server.dart',
      ]);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info(
          any(that: startsWith('MCP server inspection: dart run')),
        ),
      ).called(1);
      verify(
        () => logger.info(
          any(that: contains('Inventory: 1 tools, 1 resources')),
        ),
      ).called(1);
    });

    test('json output stays parseable when server sends notifications',
        () async {
      final result = await Process.run(
        'dart',
        <String>[
          'run',
          'bin/mcp_dart.dart',
          'inspect-server',
          '--json',
          '--',
          'dart',
          'run',
          'test/fixtures/raw_stdio_server.dart',
          '--notify-after-list',
        ],
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, equals(ExitCode.success.code));
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['kind'], equals('server'));
      expect(json['inventory'], isA<Map<String, dynamic>>());
    });

    test('json mode runs in-process with silent handlers', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run([
        'inspect-server',
        '--json',
        '--',
        'dart',
        'run',
        'test/fixtures/raw_stdio_server.dart',
        '--notify-after-list',
      ]);

      expect(result, equals(ExitCode.success.code));
      verifyNever(() => logger.warn(any()));
      verifyNever(() => logger.err(any()));
    });
  });

  group('McpServerInspector', () {
    test('returns a structured report for a Dart stdio server', () async {
      final report = await McpServerInspector(logger: MockLogger()).inspect(
        const ServerInspectionTarget(
          command: 'dart',
          serverArgs: <String>[
            'run',
            'test/fixtures/tools_resources_server.dart',
          ],
          url: null,
          env: <String, String>{},
        ),
      );

      expect(report.kind, equals('server'));
      expect(report.passed, isTrue);
      expect(report.inventory['tools'], isA<List<dynamic>>());
      expect(
        report.checks.map((check) => check.id),
        containsAll(<String>[
          'lifecycle.initialize',
          'tools.list',
          'resources.list',
        ]),
      );
    });

    test('fails configured tool output schema checks on invalid output',
        () async {
      final report = await McpServerInspector(
        logger: MockLogger(),
        probeConfig: InspectionProbeConfig.fromJson(<String, dynamic>{
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'bad_structured',
              'arguments': <String, dynamic>{'message': 'hello'},
            },
          ],
        }),
      ).inspect(
        const ServerInspectionTarget(
          command: 'dart',
          serverArgs: <String>[
            'run',
            'test/fixtures/raw_stdio_server.dart',
            '--invalid-output-schema',
          ],
          url: null,
          env: <String, String>{},
        ),
      );

      expect(report.passed, isFalse);
      final checksById = <String, InspectionCheck>{
        for (final check in report.checks) check.id: check,
      };
      expect(checksById['tools.call.bad_structured']?.status, equals('fail'));
      expect(checksById['tools.output-schema.bad_structured']?.status,
          equals('fail'));
    });

    test('silent handler mode can inspect a notifying server', () async {
      final report = await McpServerInspector(
        logger: MockLogger(),
        silentHandlers: true,
      ).inspect(
        const ServerInspectionTarget(
          command: 'dart',
          serverArgs: <String>[
            'run',
            'test/fixtures/raw_stdio_server.dart',
            '--notify-after-list',
          ],
          url: null,
          env: <String, String>{},
        ),
      );

      expect(report.passed, isTrue);
    });
  });
}
