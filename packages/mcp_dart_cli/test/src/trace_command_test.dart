import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    test('timeout marks report failed and exits non-zero', () async {
      final tempDir = await Directory.systemTemp.createTemp('trace_timeout_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/trace.json');
      final process = await Process.start(
        'dart',
        <String>[
          'run',
          'bin/mcp_dart.dart',
          'trace',
          '--report',
          report.path,
          '--max-runtime-ms',
          '100',
          '--',
          'dart',
          'run',
          'test/fixtures/hanging_process.dart',
        ],
        workingDirectory: Directory.current.path,
      );

      await process.stdout.drain<void>();
      await process.stderr.drain<void>();
      final exitCode = await process.exitCode;

      expect(exitCode, equals(ExitCode.software.code));
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final summary = json['summary'] as Map<String, dynamic>;
      expect(summary['timedOut'], isTrue);
    });

    test('proxy timeout marks in-process trace failed', () async {
      final tempDir = await Directory.systemTemp.createTemp('trace_proxy_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/trace.json');
      final clientLines = StreamController<String>();
      addTearDown(clientLines.close);
      final proxy = StdioTraceProxy(
        command: 'dart',
        args: const <String>[
          'run',
          'test/fixtures/hanging_process.dart',
        ],
        workingDirectory: Directory.current.path,
        environment: const <String, String>{},
        reportFile: report,
        maxRuntime: const Duration(milliseconds: 100),
        pretty: true,
        clientLines: clientLines.stream,
      );

      await proxy.run();

      expect(proxy.timedOut, isTrue);
      expect(proxy.failed, isTrue);
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final summary = json['summary'] as Map<String, dynamic>;
      expect(summary['timedOut'], isTrue);
    });
  });
}
