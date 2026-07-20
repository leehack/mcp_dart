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

class _HarnessClientTransport extends Transport {
  final StreamController<String> clientLines = StreamController<String>();
  bool _closed = false;
  void Function()? _onclose;
  void Function(Error error)? _onerror;
  void Function(JsonRpcMessage message)? _onmessage;

  @override
  void Function()? get onclose => _onclose;

  @override
  set onclose(void Function()? value) => _onclose = value;

  @override
  void Function(Error error)? get onerror => _onerror;

  @override
  set onerror(void Function(Error error)? value) => _onerror = value;

  @override
  void Function(JsonRpcMessage message)? get onmessage => _onmessage;

  @override
  set onmessage(void Function(JsonRpcMessage message)? value) {
    _onmessage = value;
  }

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {}

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
  }) async {
    clientLines.add(jsonEncode(message.toJson()));
  }

  Future<void> receiveLine(String line) async {
    final json = jsonDecode(line) as Map<String, dynamic>;
    onmessage?.call(JsonRpcMessage.fromJson(json));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await clientLines.close();
  }
}

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
      expect(command.argParser.options.containsKey('active-probes'), isTrue);
    });

    test('malformed client messages receive JSON-RPC error id null', () async {
      final tempDir = await Directory.systemTemp.createTemp('inspect_client_');
      addTearDown(() => tempDir.delete(recursive: true));
      final report = File('${tempDir.path}/report.json');
      final process = await Process.start('dart', <String>[
        'run',
        'bin/mcp_dart.dart',
        'inspect-client',
        '--report',
        report.path,
        '--idle-timeout-ms',
        '50',
        '--max-runtime-ms',
        '1000',
      ], workingDirectory: Directory.current.path);

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
      final process = await Process.start('dart', <String>[
        'run',
        'bin/mcp_dart.dart',
        'inspect-client',
        '--report',
        report.path,
        '--idle-timeout-ms',
        '50',
        '--max-runtime-ms',
        '1000',
      ], workingDirectory: Directory.current.path);

      await process.stdin.close();
      await process.stdout.drain<void>();
      await process.stderr.drain<void>();
      final exitCode = await process.exitCode;

      expect(exitCode, equals(ExitCode.software.code));
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final checks = (json['checks'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(checks, contains(containsPair('id', 'client.connected')));
    });
  });

  group('ClientInspectorHarness', () {
    test(
      'inspects the default stateless McpClient without legacy fallback',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'client_harness_',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final report = File('${tempDir.path}/report.json');
        final transport = _HarnessClientTransport();
        final harness = ClientInspectorHarness(
          reportFile: report,
          idleTimeout: const Duration(milliseconds: 50),
          maxRuntime: const Duration(seconds: 1),
          clientLines: transport.clientLines.stream,
          writeLine: transport.receiveLine,
        );
        final client = McpClient(
          const Implementation(name: 'default-client', version: '1.0.0'),
        );

        final runFuture = harness.run();
        try {
          await client.connect(transport);
          expect(
            client.getProtocolVersion(),
            previewProtocolVersion,
          );
          final tools = await client.listTools();
          expect(tools.tools.map((tool) => tool.name), contains('echo'));
          final result = await client.callTool(
            const CallToolRequest(
              name: 'echo',
              arguments: <String, dynamic>{'message': 'hello'},
            ),
          );
          expect(result.structuredContent, containsPair('message', 'hello'));
        } finally {
          await client.close();
        }
        await runFuture;

        final json =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(json['passed'], isTrue);
        final metadata = json['metadata'] as Map<String, dynamic>;
        expect(
          metadata['protocolVersion'],
          previewProtocolVersion,
        );
        expect(
          (metadata['observedMethods'] as List<dynamic>).cast<String>(),
          containsAll(<String>[
            Method.serverDiscover,
            Method.toolsList,
            Method.toolsCall,
          ]),
        );
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final id in <String>[
          'lifecycle.discover-first',
          'lifecycle.discover',
          'lifecycle.stateless-no-initialize',
          'lifecycle.stateless-no-initialized-notification',
          'lifecycle.stateless-request-metadata',
          'lifecycle.stateless-removed-methods',
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
      'accepts anonymous stateless clients and stamps server identity',
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
        final meta = buildProtocolRequestMeta(
          protocolVersion: previewProtocolVersion,
          clientCapabilities: const ClientCapabilities(),
        );

        final runFuture = harness.run();
        clientLines
          ..add(
            jsonEncode(
              JsonRpcServerDiscoverRequest(id: 1, meta: meta).toJson(),
            ),
          )
          ..add(
            jsonEncode(
              JsonRpcListToolsRequest(id: 2, meta: meta).toJson(),
            ),
          );
        await clientLines.close();
        await runFuture;

        final responses = outputLines
            .map(jsonDecode)
            .cast<Map<String, dynamic>>()
            .toList();
        final discoverResponse = responses.singleWhere(
          (response) => response['id'] == 1,
        );
        final toolsResponse = responses.singleWhere(
          (response) => response['id'] == 2,
        );
        expect(discoverResponse, isNot(contains('error')));
        expect(toolsResponse, isNot(contains('error')));

        for (final response in <Map<String, dynamic>>[
          discoverResponse,
          toolsResponse,
        ]) {
          final result = response['result'] as Map<String, dynamic>;
          final resultMeta = result['_meta'] as Map<String, dynamic>;
          expect(
            resultMeta[McpMetaKey.serverInfo],
            allOf(
              containsPair('name', 'mcp_dart_client_inspector'),
              containsPair('version', isNotEmpty),
            ),
          );
        }
        expect(
          discoverResponse['result'] as Map<String, dynamic>,
          isNot(contains('serverInfo')),
        );

        final json =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(json['passed'], isTrue);
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          checks.singleWhere(
            (check) => check['id'] == 'lifecycle.client-info',
          ),
          allOf(
            containsPair('status', 'info'),
            containsPair('message', contains('optional clientInfo')),
          ),
        );
      },
    );

    test(
      'inspects direct stateless requests without optional discovery',
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
          activeProbes: true,
          clientLines: clientLines.stream,
          writeLine: outputLines.add,
        );
        final meta = buildProtocolRequestMeta(
          protocolVersion: previewProtocolVersion,
          clientInfo: const Implementation(
            name: 'direct-stateless-client',
            version: '1.0.0',
          ),
          clientCapabilities: const ClientCapabilities(
            roots: ClientCapabilitiesRoots(),
            sampling: ClientCapabilitiesSampling(),
            elicitation: ClientElicitation.formOnly(),
          ),
        );

        final runFuture = harness.run();
        clientLines.add(
          jsonEncode(
            JsonRpcListToolsRequest(id: 1, meta: meta).toJson(),
          ),
        );
        await clientLines.close();
        await runFuture;

        final response = jsonDecode(outputLines.single) as Map<String, dynamic>;
        expect(response, isNot(contains('error')));
        final result = response['result'] as Map<String, dynamic>;
        expect(
          result,
          allOf(
            containsPair('resultType', resultTypeComplete),
            containsPair('ttlMs', 0),
            containsPair('cacheScope', CacheScope.private),
          ),
        );
        expect(
          (result['_meta'] as Map)[McpMetaKey.serverInfo],
          allOf(
            containsPair('name', 'mcp_dart_client_inspector'),
            containsPair('version', isNotEmpty),
          ),
        );

        final json =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(json['passed'], isTrue);
        final metadata = json['metadata'] as Map<String, dynamic>;
        expect(metadata['protocolVersion'], previewProtocolVersion);
        expect(
          metadata['clientInfo'],
          allOf(
            containsPair('name', 'direct-stateless-client'),
            containsPair('version', '1.0.0'),
          ),
        );
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          checks,
          isNot(
            contains(
              anyOf(
                containsPair('id', 'lifecycle.initialize-first'),
                containsPair('id', 'lifecycle.initialize'),
              ),
            ),
          ),
        );
        for (final id in <String>[
          'lifecycle.stateless-no-initialize',
          'lifecycle.stateless-request-metadata',
          'lifecycle.protocol-version',
          'lifecycle.client-info',
          'lifecycle.client-capabilities',
        ]) {
          expect(
            checks,
            contains(
              allOf(containsPair('id', id), containsPair('status', 'pass')),
            ),
            reason: id,
          );
        }
        for (final id in <String>[
          'lifecycle.discover-first',
          'lifecycle.discover',
        ]) {
          expect(
            checks,
            contains(
              allOf(containsPair('id', id), containsPair('status', 'info')),
            ),
            reason: id,
          );
        }
        for (final id in <String>[
          'client.roots.list',
          'client.sampling.create-message',
          'client.elicitation.create',
        ]) {
          expect(
            checks,
            contains(
              allOf(
                containsPair('id', id),
                containsPair('status', 'info'),
                containsPair('message', contains('MRTR input requests')),
              ),
            ),
            reason: id,
          );
        }
      },
    );

    test(
      'reports malformed direct stateless metadata without requiring initialize',
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
        clientLines.add(
          jsonEncode(
            const JsonRpcListToolsRequest(
              id: 1,
              meta: <String, dynamic>{
                McpMetaKey.protocolVersion: previewProtocolVersion,
              },
            ).toJson(),
          ),
        );
        await clientLines.close();
        await runFuture;

        final response = jsonDecode(outputLines.single) as Map<String, dynamic>;
        expect(
          response['error'],
          allOf(
            containsPair('code', ErrorCode.invalidParams.value),
            containsPair('message', contains(McpMetaKey.clientCapabilities)),
          ),
        );

        final json =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(json['passed'], isFalse);
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final checkIds = checks.map((check) => check['id']).toSet();
        expect(
          checkIds,
          isNot(
            anyOf(
              contains('lifecycle.initialize-first'),
              contains('lifecycle.initialize'),
            ),
          ),
        );
        expect(
          checks.singleWhere(
            (check) => check['id'] == 'lifecycle.stateless-request-metadata',
          ),
          allOf(
            containsPair('status', 'fail'),
            containsPair(
              'details',
              containsPair(
                'errors',
                contains(
                  contains(McpMetaKey.clientCapabilities),
                ),
              ),
            ),
          ),
        );
        for (final id in <String>[
          'lifecycle.discover-first',
          'lifecycle.discover',
        ]) {
          expect(
            checks,
            contains(
              allOf(containsPair('id', id), containsPair('status', 'info')),
            ),
            reason: id,
          );
        }
      },
    );

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
                'protocolVersion': stableProtocolVersion,
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
          stableProtocolVersion,
        );
        final toolsResponse = responses.singleWhere(
          (response) => response['id'] == 2,
        );
        expect(
          toolsResponse['result'] as Map,
          allOf(
            isNot(contains('resultType')),
            isNot(contains('ttlMs')),
            isNot(contains('cacheScope')),
            isNot(contains('_meta')),
          ),
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
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
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

    test('rejects invalid stateless operations', () async {
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
      final meta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientInfo: const Implementation(
          name: 'stateless-client',
          version: '1.0.0',
        ),
        clientCapabilities: const ClientCapabilities(),
      );

      final runFuture = harness.run();
      clientLines
        ..add(
          jsonEncode(
            JsonRpcServerDiscoverRequest(id: 1, meta: meta).toJson(),
          ),
        )
        ..add(
          jsonEncode(
            const JsonRpcListToolsRequest(id: 2).toJson(),
          ),
        )
        ..add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': jsonRpcVersion,
            'id': 3,
            'method': Method.tasksList,
            'params': <String, dynamic>{'_meta': meta},
          }),
        )
        ..add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': jsonRpcVersion,
            'id': 4,
            'method': Method.toolsList,
            'params': <String, dynamic>{
              '_meta': <String, dynamic>{
                ...meta,
                McpMetaKey.clientInfo: null,
              },
            },
          }),
        );
      await clientLines.close();
      await runFuture;

      final responses = outputLines.map(jsonDecode).cast<Map>().toList();
      final error = responses.singleWhere((response) => response['id'] == 2);
      expect(
        (error['error'] as Map)['code'],
        ErrorCode.invalidParams.value,
      );
      final removedMethodError = responses.singleWhere(
        (response) => response['id'] == 3,
      );
      expect(
        (removedMethodError['error'] as Map)['code'],
        ErrorCode.methodNotFound.value,
      );
      final invalidIdentityError = responses.singleWhere(
        (response) => response['id'] == 4,
      );
      expect(
        invalidIdentityError['error'] as Map,
        allOf(
          containsPair('code', ErrorCode.invalidParams.value),
          containsPair('message', contains(McpMetaKey.clientInfo)),
        ),
      );
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(json['passed'], isFalse);
      final checks = (json['checks'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        checks.singleWhere(
          (check) => check['id'] == 'lifecycle.stateless-request-metadata',
        ),
        containsPair('status', 'fail'),
      );
      expect(
        checks.singleWhere(
          (check) => check['id'] == 'lifecycle.stateless-removed-methods',
        ),
        allOf(
          containsPair('status', 'fail'),
          containsPair(
            'details',
            containsPair('methods', contains(Method.tasksList)),
          ),
        ),
      );
    });

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
          activeProbes: true,
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
                'protocolVersion': stableProtocolVersion,
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
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
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

    test('does not actively probe client capabilities by default', () async {
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
        ..add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': jsonRpcVersion,
            'id': 1,
            'method': Method.initialize,
            'params': <String, dynamic>{
              'protocolVersion': stableProtocolVersion,
              'capabilities': <String, dynamic>{
                'roots': <String, dynamic>{},
                'sampling': <String, dynamic>{},
                'elicitation': <String, dynamic>{},
              },
              'clientInfo': <String, dynamic>{
                'name': 'passive-client',
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
        );
      await clientLines.close();
      await runFuture;

      final outgoing = outputLines.map(jsonDecode).cast<Map<String, dynamic>>();
      expect(
        outgoing.where((message) => message['method'] != null),
        isEmpty,
      );
      final json =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      final metadata = json['metadata'] as Map<String, dynamic>;
      expect(metadata['activeProbesEnabled'], isFalse);
      expect(metadata['activeProbes'], isEmpty);
      final checks = (json['checks'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        checks.singleWhere((check) => check['id'] == 'client.roots.list'),
        allOf(
          containsPair('status', 'info'),
          containsPair('message', contains('disabled')),
        ),
      );
    });

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
        final checks = (json['checks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
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
