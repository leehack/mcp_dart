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
      verify(
        () => logger.err('--report is required for inspect-client.'),
      ).called(1);
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
          workingDirectory: Directory.current.path);

      process.stdin.writeln('{not json');
      await process.stdin.close();
      final stdoutText = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.drain<void>();
      final exitCode = await process.exitCode;

      expect(exitCode, equals(ExitCode.software.code));
      final response = jsonDecode(stdoutText.trim()) as Map<String, dynamic>;
      expect(response, containsPair('id', null));
      expect(response['error'], isA<Map<String, dynamic>>());
    });

    test('failed inspection report exits non-zero', () async {
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
          workingDirectory: Directory.current.path);

      await process.stdin.close();
      await process.stdout.drain<void>();
      await process.stderr.drain<void>();
      final exitCode = await process.exitCode;

      expect(exitCode, equals(ExitCode.software.code));
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final checks =
          (json['checks'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(checks, contains(containsPair('id', 'client.connected')));
    });
  });

  group('ClientInspectorHarness', () {
    test(
      'inspects a client handshake and observed operations in-process',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'client_harness_',
        );
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
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.initialize,
              'params': <String, dynamic>{
                'protocolVersion': stableProtocolVersion2025_11_25,
                'capabilities': <String, dynamic>{},
                'clientInfo': <String, dynamic>{
                  'name': 'fixture-client',
                  'version': '1.0.0',
                },
              },
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsInitialized,
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 2,
              'method': Method.toolsList,
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 3,
              'method': Method.toolsCall,
              'params': <String, dynamic>{
                'name': 'echo',
                'arguments': <String, dynamic>{'message': 'hello'},
              },
            }),
          );
        await clientLines.close();
        await runFuture;

        final responses = outputLines.map(jsonDecode).cast<Map>().toList();
        expect(
          responses.map((response) => response['id']),
          containsAll([1, 2, 3]),
        );
        final initializeResponse = responses.singleWhere(
          (response) => response['id'] == 1,
        );
        expect(
          (initializeResponse['result'] as Map)['protocolVersion'],
          stableProtocolVersion2025_11_25,
        );
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
        expect(checks.where((check) => check['status'] == 'fail'), isEmpty);
        expect(
          checks.map((check) => check['id']),
          containsAll(<String>[
            'lifecycle.initialize-first',
            'lifecycle.initialized-notification',
            'tools.list',
            'tools.call',
          ]),
        );
      },
    );

    test(
      'records resources, prompts, and active client capability probes',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'client_harness_',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final report = File('${tempDir.path}/report.json');
        final clientLines = StreamController<String>();
        final outputLines = <String>[];
        final harness = ClientInspectorHarness(
          reportFile: report,
          idleTimeout: const Duration(milliseconds: 100),
          maxRuntime: const Duration(seconds: 2),
          clientLines: clientLines.stream,
          writeLine: outputLines.add,
        );

        final runFuture = harness.run();
        clientLines
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.initialize,
              'params': <String, dynamic>{
                'protocolVersion': stableProtocolVersion2025_11_25,
                'capabilities': <String, dynamic>{
                  'roots': <String, dynamic>{},
                  'sampling': <String, dynamic>{},
                  'elicitation': <String, dynamic>{},
                },
                'clientInfo': <String, dynamic>{
                  'name': 'active-client',
                  'version': '1.0.0',
                },
              },
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'method': Method.notificationsInitialized,
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 2,
              'method': Method.resourcesList,
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 3,
              'method': Method.resourcesTemplatesList,
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 4,
              'method': Method.resourcesRead,
              'params': <String, dynamic>{'uri': 'inspector://status'},
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 5,
              'method': Method.promptsList,
            }),
          )
          ..add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': 6,
              'method': Method.promptsGet,
              'params': <String, dynamic>{
                'name': 'inspector-summary',
                'arguments': <String, dynamic>{'topic': 'interop'},
              },
            }),
          );

        await _waitForOutputLines(outputLines, 9);
        final probeRequests = outputLines
            .map(jsonDecode)
            .cast<Map<String, dynamic>>()
            .where(
              (message) =>
                  message['method'] == Method.rootsList ||
                  message['method'] == Method.samplingCreateMessage ||
                  message['method'] == Method.elicitationCreate,
            )
            .toList();
        expect(probeRequests, hasLength(3));
        for (final request in probeRequests) {
          final method = request['method'];
          clientLines.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': jsonRpcVersion,
              'id': request['id'],
              'result': switch (method) {
                Method.rootsList => <String, dynamic>{
                    'roots': <Map<String, dynamic>>[
                      <String, dynamic>{'uri': 'file:///tmp', 'name': 'tmp'},
                    ],
                  },
                Method.samplingCreateMessage => <String, dynamic>{
                    'role': 'assistant',
                    'content': <String, dynamic>{
                      'type': 'text',
                      'text': 'sampled',
                    },
                    'model': 'fixture',
                    'stopReason': 'endTurn',
                  },
                _ => <String, dynamic>{
                    'action': 'accept',
                    'content': <String, dynamic>{'confirmed': true},
                  },
              },
            }),
          );
        }
        await clientLines.close();
        await runFuture;

        final json =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(json['passed'], isTrue);
        final checks =
            (json['checks'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final id in <String>[
          'resources.list',
          'prompts.list',
          'client.roots.list',
          'client.sampling.create-message',
          'client.elicitation.create',
        ]) {
          expect(
            checks,
            contains(
              allOf(containsPair('id', id), containsPair('status', 'pass')),
            ),
            reason: id,
          );
        }
      },
    );

    test(
      'sends JSON-RPC errors with explicit null id for malformed input',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'client_harness_',
        );
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
      },
    );
  });
}

Future<void> _waitForOutputLines(List<String> outputLines, int count) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (outputLines.length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $count harness output lines.');
}
