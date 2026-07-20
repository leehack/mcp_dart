import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:mcp_dart_cli/src/inspect_server_command.dart';
import 'package:mcp_dart_cli/src/inspectors/inspection_report.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
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

    test(
      'json output stays parseable when server sends notifications',
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
        final json =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(json['kind'], equals('server'));
        expect(json['inventory'], isA<Map<String, dynamic>>());
      },
    );

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
    test(
      'stateless fixture stamps identity on every successful result',
      () async {
        final process = await Process.start(
          Platform.resolvedExecutable,
          <String>[
            'run',
            'test/fixtures/stateless_inventory_server.dart',
          ],
        );
        final responsesFuture = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .take(2)
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();

        for (final request in <Map<String, dynamic>>[
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': Method.serverDiscover,
          },
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 2,
            'method': Method.toolsList,
          },
        ]) {
          process.stdin.writeln(jsonEncode(request));
        }
        await process.stdin.close();

        final responses = await responsesFuture;
        expect(await process.exitCode, isZero);
        expect(responses, hasLength(2));
        for (final response in responses) {
          final result = (response['result'] as Map).cast<String, dynamic>();
          final meta = (result['_meta'] as Map).cast<String, dynamic>();
          expect(meta[McpMetaKey.serverInfo], <String, dynamic>{
            'name': 'stateless-inventory-fixture',
            'version': '1.0.0',
          });
        }
      },
    );

    test('normalizes and orders path issuer metadata probes like the SDK', () {
      final inspector = McpServerInspector(logger: MockLogger());

      expect(
        inspector
            .authorizationServerMetadataCandidates(
              Uri.parse(
                'https://auth.example.com/tenant1/?source=config#ignored',
              ),
            )
            .map((candidate) => candidate.toString()),
        <String>[
          'https://auth.example.com/.well-known/oauth-authorization-server/tenant1',
          'https://auth.example.com/.well-known/openid-configuration/tenant1',
          'https://auth.example.com/tenant1/.well-known/openid-configuration',
          'https://auth.example.com/tenant1/.well-known/oauth-authorization-server',
        ],
      );
    });

    test('does not duplicate metadata probes for a root issuer', () {
      final inspector = McpServerInspector(logger: MockLogger());

      expect(
        inspector
            .authorizationServerMetadataCandidates(
              Uri.parse('https://auth.example.com/?source=config#ignored'),
            )
            .map((candidate) => candidate.toString()),
        <String>[
          'https://auth.example.com/.well-known/oauth-authorization-server',
          'https://auth.example.com/.well-known/openid-configuration',
        ],
      );
    });

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
      expect(report.inventory, isNot(contains('toolCalls')));
      expect(report.inventory, isNot(contains('resourceReads')));
      expect(report.inventory, isNot(contains('resourceSubscriptions')));
      expect(report.inventory, isNot(contains('promptGets')));
      expect(report.inventory, isNot(contains('completions')));
      expect(report.inventory, isNot(contains('taskToolCalls')));
      expect(
        report.checks.map((check) => check.id),
        containsAll(<String>[
          'lifecycle.initialize',
          'tools.list',
          'resources.list',
        ]),
      );
    });

    test('skips removed and active probes for a 2026 server', () async {
      final report = await McpServerInspector(logger: MockLogger()).inspect(
        const ServerInspectionTarget(
          command: 'dart',
          serverArgs: <String>[
            'run',
            'test/fixtures/stateless_inventory_server.dart',
          ],
          url: null,
          env: <String, String>{},
        ),
      );

      expect(report.passed, isTrue);
      expect(report.warningCount, isZero);
      expect(report.metadata['protocolVersion'], previewProtocolVersion);
      final checksById = <String, InspectionCheck>{
        for (final check in report.checks) check.id: check,
      };
      expect(checksById['base.ping']?.status, 'info');
      expect(checksById['base.ping']?.message, contains('no probe was sent'));
      expect(checksById['logging.request-scoped']?.status, 'info');
      expect(report.inventory, isNot(contains('toolCalls')));
    });

    test('accepts anonymous 2026 server identity', () async {
      final report = await McpServerInspector(logger: MockLogger()).inspect(
        const ServerInspectionTarget(
          command: 'dart',
          serverArgs: <String>[
            'run',
            'test/fixtures/stateless_inventory_server.dart',
            '--anonymous',
          ],
          url: null,
          env: <String, String>{},
        ),
      );

      expect(report.passed, isTrue);
      expect(report.metadata, isNot(contains('serverInfo')));
      final serverInfoCheck = report.checks.singleWhere(
        (check) => check.id == 'lifecycle.server-info',
      );
      expect(serverInfoCheck.status, 'info');
      expect(serverInfoCheck.message, contains('optional'));
    });

    test(
      'fails configured tool output schema checks on invalid output',
      () async {
        final report =
            await McpServerInspector(
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
        expect(
          checksById['tools.output-schema.bad_structured']?.status,
          equals('fail'),
        );
      },
    );

    test('silent handler mode can inspect a notifying server', () async {
      final report =
          await McpServerInspector(
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

    test('inspects a full TypeScript SDK stdio server in-process', () async {
      final tsServer = _typescriptServerFixture();
      if (!_requireFile(tsServer, 'compiled TypeScript server fixture')) {
        return;
      }

      final report =
          await McpServerInspector(
            logger: MockLogger(),
            probeConfig: InspectionProbeConfig.fromJson(<String, dynamic>{
              'tools': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'structured_echo',
                  'arguments': <String, dynamic>{'message': 'configured probe'},
                },
              ],
              'resource': <String, dynamic>{'uri': 'resource://test'},
              'prompt': <String, dynamic>{
                'name': 'greeting',
                'arguments': <String, dynamic>{'language': 'English'},
              },
              'completion': <String, dynamic>{
                'prompt': 'greeting',
                'argument': 'language',
                'value': 'E',
              },
              'task': <String, dynamic>{
                'tool': 'long_running',
                'arguments': <String, dynamic>{'duration': 20},
                'ttl': 60000,
              },
            }),
          ).inspect(
            ServerInspectionTarget(
              command: 'node',
              serverArgs: <String>[
                tsServer.path,
                '--transport',
                'stdio',
              ],
              url: null,
              env: const <String, String>{},
            ),
          );

      expect(report.passed, isTrue);
      final checksById = <String, InspectionCheck>{
        for (final check in report.checks) check.id: check,
      };
      for (final id in <String>[
        'tools.call.structured_echo',
        'tools.output-schema.structured_echo',
        'resources.read',
        'prompts.get',
        'completion.complete',
        'tasks.tools.call',
        'tasks.lifecycle.created',
        'tasks.lifecycle.terminal',
      ]) {
        expect(checksById[id]?.status, equals('pass'), reason: id);
      }
    });

    test(
      'inspects a TypeScript SDK Streamable HTTP server in-process',
      () async {
        final tsServer = _typescriptServerFixture();
        if (!_requireFile(tsServer, 'compiled TypeScript server fixture')) {
          return;
        }

        final port = await _findOpenPort();
        final server = await _ManagedProcess.start('node', <String>[
          tsServer.path,
          '--transport',
          'http',
          '--port',
          '$port',
        ]);
        addTearDown(server.stop);
        final url = Uri.parse('http://127.0.0.1:$port/mcp');
        await _waitForHttpEndpoint(url);

        final report = await McpServerInspector(logger: MockLogger()).inspect(
          ServerInspectionTarget(
            command: null,
            serverArgs: const <String>[],
            url: url,
            env: const <String, String>{},
          ),
        );

        expect(report.passed, isTrue);
        expect(report.metadata['transport'], equals('streamable-http'));
        final checksById = <String, InspectionCheck>{
          for (final check in report.checks) check.id: check,
        };
        for (final id in <String>[
          'transport.streamable-http.session',
          'transport.streamable-http.get-without-session',
          'transport.streamable-http.bogus-session',
          'transport.streamable-http.delete-session',
        ]) {
          expect(checksById[id]?.status, equals('pass'), reason: id);
        }
      },
    );
  });
}

File _typescriptServerFixture() {
  final repoRoot = _findRepoRoot(Directory.current);
  return File(
    p.join(repoRoot.path, 'test', 'interop', 'ts', 'dist', 'server.js'),
  );
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (current.path != current.parent.path) {
    if (File(p.join(current.path, 'AGENTS.md')).existsSync() &&
        Directory(
          p.join(current.path, 'packages', 'mcp_dart_cli'),
        ).existsSync()) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('Could not locate repository root from ${start.path}.');
}

bool _requireFile(File file, String description) {
  if (file.existsSync()) return true;
  markTestSkipped('$description is missing at ${file.path}.');
  return false;
}

Future<int> _findOpenPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForHttpEndpoint(Uri uri) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(
            const Duration(milliseconds: 500),
          );
      final response = await request.close().timeout(
        const Duration(milliseconds: 500),
      );
      await response.drain<void>();
      client.close(force: true);
      return;
    } catch (_) {
      client.close(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  fail('Timed out waiting for HTTP MCP endpoint $uri.');
}

class _ManagedProcess {
  _ManagedProcess._(
    this.process,
    this._stdoutSubscription,
    this._stderrSubscription,
  );

  final Process process;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;

  static Future<_ManagedProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(executable, arguments);
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(
          (_) {},
        );
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(
          (_) {},
        );
    return _ManagedProcess._(
      process,
      stdoutSubscription,
      stderrSubscription,
    );
  }

  Future<void> stop() async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
  }
}
