import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
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

    test('malformed client messages receive JSON-RPC error id null', () async {
      final tempDir = await Directory.systemTemp.createTemp('inspect_client_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/report.json');
      final process = await Process.start(
        'dart',
        <String>[
          'run',
          'bin/mcp_dart.dart',
          'inspect-client',
          '--report',
          report.path,
          '--idle-timeout-ms',
          '50',
          '--max-runtime-ms',
          '1000',
        ],
        workingDirectory: Directory.current.path,
      );

      process.stdin.writeln('{not json');
      await process.stdin.close();
      final stdoutText = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.drain<void>();
      final exitCode = await process.exitCode;

      expect(exitCode, equals(ExitCode.success.code));
      final response = jsonDecode(stdoutText.trim()) as Map<String, dynamic>;
      expect(response, containsPair('id', null));
      expect(response['error'], isA<Map<String, dynamic>>());
    });
  });

  group('ClientInspectorHarness', () {
    test('inspects a client handshake and observed operations in-process',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('client_harness_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/report.json');
      final clientLines = StreamController<String>();
      final outputLines = <String>[];
      final harness = ClientInspectorHarness(
        reportFile: report,
        idleTimeout: const Duration(milliseconds: 50),
        maxRuntime: const Duration(seconds: 1),
        clientLines: clientLines.stream,
        writeLine: outputLines.add,
      );

      final runFuture = harness.run();
      clientLines
        ..add(jsonEncode(<String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.initialize,
          'params': <String, dynamic>{
            'protocolVersion': latestProtocolVersion,
            'capabilities': <String, dynamic>{},
            'clientInfo': <String, dynamic>{
              'name': 'fixture-client',
              'version': '1.0.0',
            },
          },
        }))
        ..add(jsonEncode(<String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'method': Method.notificationsInitialized,
        }))
        ..add(jsonEncode(<String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 2,
          'method': Method.toolsList,
        }))
        ..add(jsonEncode(<String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 3,
          'method': Method.toolsCall,
          'params': <String, dynamic>{
            'name': 'echo',
            'arguments': <String, dynamic>{'message': 'hello'},
          },
        }));
      await clientLines.close();
      await runFuture;

      final responses = outputLines.map(jsonDecode).cast<Map>().toList();
      expect(
          responses.map((response) => response['id']), containsAll([1, 2, 3]));
      final toolCallResponse = responses.singleWhere(
        (response) => response['id'] == 3,
      );
      expect(
        (toolCallResponse['result'] as Map)['structuredContent'],
        containsPair('message', 'hello'),
      );

      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isTrue);
      final checks =
          (json['checks'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(
        checks.where((check) => check['status'] == 'fail'),
        isEmpty,
      );
      expect(
        checks.map((check) => check['id']),
        containsAll(<String>[
          'lifecycle.initialize-first',
          'lifecycle.initialized-notification',
          'tools.list',
          'tools.call',
        ]),
      );
    });

    test('sends JSON-RPC errors with explicit null id for malformed input',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('client_harness_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/report.json');
      final clientLines = StreamController<String>();
      final outputLines = <String>[];
      final harness = ClientInspectorHarness(
        reportFile: report,
        idleTimeout: const Duration(milliseconds: 50),
        maxRuntime: const Duration(seconds: 1),
        clientLines: clientLines.stream,
        writeLine: outputLines.add,
      );

      final runFuture = harness.run();
      clientLines.add('{not json');
      await clientLines.close();
      await runFuture;

      final error = jsonDecode(outputLines.single) as Map<String, dynamic>;
      expect(error, containsPair('id', null));
      expect(error['error'], isA<Map<String, dynamic>>());

      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final checks =
          (json['checks'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(
        checks.singleWhere((check) => check['id'] == 'jsonrpc.well-formed'),
        containsPair('status', 'fail'),
      );
    });
  });
}
