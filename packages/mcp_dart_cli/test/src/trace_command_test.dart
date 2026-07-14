import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
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

    test('rejects invalid runtime and env options', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      var result = await runner.run([
        'trace',
        '--report',
        'trace.json',
        '--max-runtime-ms',
        '0',
        '--',
        'dart',
      ]);
      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.err('--max-runtime-ms must be a positive integer.'),
      ).called(1);

      result = await runner.run([
        'trace',
        '--report',
        'trace.json',
        '--env',
        'bad',
        '--',
        'dart',
      ]);
      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.err('--env values must use KEY=VALUE syntax.'),
      ).called(1);
    });

    test('requires proxied server command', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final result = await runner.run(['trace', '--report', 'trace.json']);

      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.err('Missing proxied server command after --.'),
      ).called(1);
    });

    test('timeout marks report failed and exits non-zero', () async {
      final tempDir = await Directory.systemTemp.createTemp('trace_timeout_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/trace.json');
      final process = await Process.start('dart', <String>[
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
      ], workingDirectory: Directory.current.path);

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
      addTearDown(() async {
        if (!clientLines.isClosed) await clientLines.close();
      });
      final proxy = StdioTraceProxy(
        command: 'dart',
        args: const <String>['run', 'test/fixtures/hanging_process.dart'],
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

    test('proxy records valid client and server JSON-RPC messages', () async {
      final tempDir = await Directory.systemTemp.createTemp('trace_proxy_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/trace.json');
      final clientLines = StreamController<String>();
      addTearDown(() async {
        if (!clientLines.isClosed) await clientLines.close();
      });
      final proxy = StdioTraceProxy(
        command: 'dart',
        args: const <String>['run', 'test/fixtures/raw_stdio_server.dart'],
        workingDirectory: Directory.current.path,
        environment: const <String, String>{},
        reportFile: report,
        maxRuntime: const Duration(seconds: 2),
        pretty: false,
        clientLines: clientLines.stream,
      );

      final runFuture = proxy.run();
      clientLines.add(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, dynamic>{
            'protocolVersion': defaultProtocolVersion,
            'capabilities': <String, dynamic>{},
            'clientInfo': <String, dynamic>{
              'name': 'trace-fixture',
              'version': '1.0.0',
            },
          },
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await clientLines.close();
      await runFuture;

      expect(proxy.failed, isFalse);
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isTrue);
      final summary = json['summary'] as Map<String, dynamic>;
      final methods = summary['methods'] as Map<String, dynamic>;
      expect(methods['initialize'], greaterThanOrEqualTo(1));
      expect(summary['malformedTraffic'], isFalse);
    });

    test(
      'piped one-shot trace captures server response before finishing',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('trace_pipe_');
        addTearDown(() => tempDir.delete(recursive: true));
        final report = File('${tempDir.path}/trace.json');
        final process = await Process.start('dart', <String>[
          'run',
          'bin/mcp_dart.dart',
          'trace',
          '--report',
          report.path,
          '--max-runtime-ms',
          '2000',
          '--',
          'dart',
          'run',
          'test/fixtures/raw_stdio_server.dart',
        ], workingDirectory: Directory.current.path);

        process.stdin.writeln(
          jsonEncode(<String, dynamic>{
            'jsonrpc': jsonRpcVersion,
            'id': 1,
            'method': Method.initialize,
            'params': <String, dynamic>{
              'protocolVersion': defaultProtocolVersion,
              'capabilities': <String, dynamic>{},
              'clientInfo': <String, dynamic>{
                'name': 'trace-pipe-fixture',
                'version': '1.0.0',
              },
            },
          }),
        );
        await process.stdin.close();
        final stdoutText = await process.stdout.transform(utf8.decoder).join();
        await process.stderr.drain<void>();
        final exitCode = await process.exitCode;

        expect(exitCode, equals(ExitCode.success.code));
        expect(stdoutText, contains('"result"'));
        final json =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(json['passed'], isTrue);
        expect(json['serverExitCode'], equals(0));
        final events =
            (json['events'] as List<dynamic>).cast<Map<String, dynamic>>();
        expect(
          events.map((event) => event['direction']),
          contains('server_to_client'),
        );
      },
    );

    test('proxy marks malformed JSON-RPC traffic as failed', () async {
      final tempDir = await Directory.systemTemp.createTemp('trace_proxy_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/trace.json');
      final clientLines = StreamController<String>();
      addTearDown(clientLines.close);
      final proxy = StdioTraceProxy(
        command: 'dart',
        args: const <String>['run', 'test/fixtures/raw_stdio_server.dart'],
        workingDirectory: Directory.current.path,
        environment: const <String, String>{},
        reportFile: report,
        maxRuntime: const Duration(seconds: 2),
        pretty: true,
        clientLines: clientLines.stream,
      );

      final runFuture = proxy.run();
      clientLines.add('[]');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await clientLines.close();
      await runFuture;

      expect(proxy.hadMalformedTraffic, isTrue);
      expect(proxy.failed, isTrue);
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final events = (json['events'] as List<dynamic>).cast<Map>();
      expect(events.any((event) => event.containsKey('parseError')), isTrue);
    });
  });
}
