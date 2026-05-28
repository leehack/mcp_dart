@Tags(['e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final cliDir = Directory.current;
  final repoRoot = _findRepoRoot(cliDir);
  final tsServer = File(
    p.join(repoRoot.path, 'test', 'interop', 'ts', 'dist', 'server.js'),
  );
  final tsClient = File(
    p.join(repoRoot.path, 'test', 'interop', 'ts', 'dist', 'basic_client.js'),
  );
  final filesystemServer = File(
    p.join(
      repoRoot.path,
      'test',
      'interop',
      'ts',
      'node_modules',
      '@modelcontextprotocol',
      'server-filesystem',
      'dist',
      'index.js',
    ),
  );
  final pythonServer = File(
    p.join(repoRoot.path, 'test', 'interop', 'python', 'server.py'),
  );
  final pythonClient = File(
    p.join(repoRoot.path, 'test', 'interop', 'python', 'basic_client.py'),
  );
  final dartFixture = Directory(
    p.join(cliDir.path, 'test', 'fixtures', 'dart_mcp_project'),
  );

  group('CLI e2e interop', () {
    test('lists tools from an official TypeScript SDK server', () async {
      if (!_requireFile(tsServer, 'compiled TypeScript server fixture')) {
        return;
      }

      final result = await _runCli([
        'list-tools',
        '--json',
        '--',
        'node',
        tsServer.path,
        '--transport',
        'stdio',
      ], workingDirectory: cliDir);

      _expectSuccess(result);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final tools = json['tools'] as List<dynamic>;
      expect(
        tools.map((tool) => (tool as Map<String, dynamic>)['name']),
        containsAll(['echo', 'add']),
      );
    });

    test('inspects an official TypeScript SDK server', () async {
      if (!_requireFile(tsServer, 'compiled TypeScript server fixture')) {
        return;
      }

      final probeConfig = File(
        p.join(cliDir.path, '.dart_tool', 'inspect-probes-ts.json'),
      );
      await probeConfig.parent.create(recursive: true);
      await probeConfig.writeAsString(jsonEncode(<String, dynamic>{
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
      }));

      final result = await _runCli([
        'inspect-server',
        '--json',
        '--probe-config',
        probeConfig.path,
        '--',
        'node',
        tsServer.path,
        '--transport',
        'stdio',
      ], workingDirectory: cliDir);

      _expectSuccess(result);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['kind'], equals('server'));
      expect(json['passed'], isTrue);
      final inventory = json['inventory'] as Map<String, dynamic>;
      final tools = inventory['tools'] as List<dynamic>;
      expect(
        tools.map((tool) => (tool as Map<String, dynamic>)['name']),
        containsAll(['echo', 'add', 'structured_echo']),
      );
      _expectChecksPass(json, [
        'tools.call.structured_echo',
        'tools.output-schema.structured_echo',
        'resources.read',
        'prompts.get',
        'completion.complete',
        'tasks.tools.call',
        'tasks.lifecycle.created',
        'tasks.lifecycle.terminal',
      ]);
    });

    test('inspects an official TypeScript SDK Streamable HTTP server',
        () async {
      if (!_requireFile(tsServer, 'compiled TypeScript server fixture')) {
        return;
      }

      final port = await _findOpenPort();
      final server = await _ManagedProcess.start(
        'node',
        [
          tsServer.path,
          '--transport',
          'http',
          '--port',
          '$port',
        ],
      );
      try {
        final url = Uri.parse('http://127.0.0.1:$port/mcp');
        await _waitForHttpEndpoint(url);

        final result = await _runCli([
          'inspect-server',
          '--json',
          '--url',
          url.toString(),
        ], workingDirectory: cliDir);

        _expectSuccess(result, process: server);
        final json =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(json['kind'], equals('server'));
        expect(json['passed'], isTrue);
        expect(
          ((json['metadata'] as Map<String, dynamic>)['transport']),
          equals('streamable-http'),
        );
        final inventory = json['inventory'] as Map<String, dynamic>;
        final tools = inventory['tools'] as List<dynamic>;
        expect(
          tools.map((tool) => (tool as Map<String, dynamic>)['name']),
          containsAll(['echo', 'add', 'structured_echo']),
        );
        _expectChecksPass(json, [
          'transport.streamable-http.session',
          'transport.streamable-http.get-without-session',
          'transport.streamable-http.bogus-session',
          'transport.streamable-http.delete-session',
          'resources.read',
          'prompts.get',
          'completion.complete',
          'tasks.tools.call',
        ]);

        final call = await _runCli([
          'call-tool',
          'echo',
          '--json',
          '--json-args',
          '{"message":"from http inspector"}',
          '--url',
          url.toString(),
        ], workingDirectory: cliDir);
        _expectSuccess(call, process: server);
        final callJson =
            jsonDecode(call.stdout as String) as Map<String, dynamic>;
        final content = callJson['content'] as List<dynamic>;
        expect(
          (content.first as Map<String, dynamic>)['text'],
          equals('from http inspector'),
        );
      } finally {
        await server.stop();
      }
    });

    test('inspects and calls a published TypeScript filesystem MCP server',
        () async {
      if (!_requireFile(filesystemServer, 'published filesystem MCP server')) {
        return;
      }

      final root = await Directory.systemTemp.createTemp('mcp_fs_interop_');
      final canonicalRoot = Directory(root.resolveSymbolicLinksSync());
      final file = File(p.join(canonicalRoot.path, 'hello.txt'));
      await file.writeAsString('hello from filesystem server\n');
      try {
        final result = await _runCli([
          'inspect-server',
          '--json',
          '--',
          'node',
          filesystemServer.path,
          canonicalRoot.path,
        ], workingDirectory: cliDir);

        _expectSuccess(result);
        final json =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(json['kind'], equals('server'));
        expect(json['passed'], isTrue);
        final inventory = json['inventory'] as Map<String, dynamic>;
        final tools = inventory['tools'] as List<dynamic>;
        expect(
          tools.map((tool) => (tool as Map<String, dynamic>)['name']),
          containsAll(['read_text_file', 'list_directory']),
        );

        final call = await _runCli([
          'call-tool',
          'read_text_file',
          '--json',
          '--json-args',
          jsonEncode(<String, dynamic>{'path': file.path}),
          '--',
          'node',
          filesystemServer.path,
          canonicalRoot.path,
        ], workingDirectory: cliDir);
        _expectSuccess(call);
        final callJson =
            jsonDecode(call.stdout as String) as Map<String, dynamic>;
        final content = callJson['content'] as List<dynamic>;
        expect(
          (content.first as Map<String, dynamic>)['text'],
          contains('hello from filesystem server'),
        );
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('calls a tool on an official Python SDK server', () async {
      if (!_requireFile(pythonServer, 'Python server fixture')) {
        return;
      }
      final python = await _pythonWithMcpSdk();
      if (python == null) return;

      final result = await _runCli([
        'call-tool',
        'echo',
        '--json',
        '--json-args',
        '{"message":"hello"}',
        '--',
        python,
        pythonServer.path,
      ], workingDirectory: cliDir);

      _expectSuccess(result);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final content = json['content'] as List<dynamic>;
      expect(
        (content.first as Map<String, dynamic>)['text'],
        equals('python: hello'),
      );
    });

    test('inspects an official Python SDK server', () async {
      if (!_requireFile(pythonServer, 'Python server fixture')) {
        return;
      }
      final python = await _pythonWithMcpSdk();
      if (python == null) return;

      final result = await _runCli([
        'inspect-server',
        '--json',
        '--',
        python,
        pythonServer.path,
      ], workingDirectory: cliDir);

      _expectSuccess(result);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['kind'], equals('server'));
      expect(json['passed'], isTrue);
      final inventory = json['inventory'] as Map<String, dynamic>;
      final tools = inventory['tools'] as List<dynamic>;
      expect(
        tools.map((tool) => (tool as Map<String, dynamic>)['name']),
        containsAll(['echo', 'add']),
      );
    });

    test('inspects a published Python time MCP server', () async {
      final python = await _pythonWithMcpSdk();
      if (python == null) return;
      final timeServer = await _pythonConsoleScript(python, 'mcp-server-time');
      if (!_requireFile(timeServer, 'published Python time MCP server')) {
        return;
      }

      final result = await _runCli([
        'inspect-server',
        '--json',
        '--',
        timeServer.path,
        '--local-timezone',
        'UTC',
      ], workingDirectory: cliDir);

      _expectSuccess(result);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['kind'], equals('server'));
      expect(json['passed'], isTrue);
      final inventory = json['inventory'] as Map<String, dynamic>;
      final tools = inventory['tools'] as List<dynamic>;
      expect(
        tools.map((tool) => (tool as Map<String, dynamic>)['name']),
        containsAll(['get_current_time', 'convert_time']),
      );
    });

    test('serves a Dart project to an official TypeScript SDK client',
        () async {
      if (!_requireFile(tsClient, 'compiled TypeScript client fixture')) {
        return;
      }
      await _prepareDartFixture(dartFixture);

      final result = await Process.run(
        'node',
        [
          tsClient.path,
          '--server-command',
          'dart',
          '--server-args',
          'run mcp_dart_cli:mcp_dart serve',
          '--server-cwd',
          dartFixture.path,
        ],
      );

      _expectSuccess(result);
      expect(result.stdout, contains('typescript client interop passed'));
    });

    test('traces an official TypeScript SDK client/server session', () async {
      if (!_requireFile(tsClient, 'compiled TypeScript client fixture') ||
          !_requireFile(tsServer, 'compiled TypeScript server fixture')) {
        return;
      }

      final reportFile = File(
        p.join(cliDir.path, '.dart_tool', 'trace-ts.json'),
      );
      if (reportFile.existsSync()) {
        reportFile.deleteSync();
      }

      final result = await Process.run(
        'node',
        [
          tsClient.path,
          '--server-command',
          'dart',
          '--server-args',
          'run bin/mcp_dart.dart trace --report ${reportFile.path} -- node ${tsServer.path} --transport stdio',
          '--server-cwd',
          cliDir.path,
        ],
      );

      _expectSuccess(result);
      expect(result.stdout, contains('typescript client interop passed'));

      final report = await _readReport(reportFile);
      expect(report['kind'], equals('trace'));
      expect(report['passed'], isTrue);
      final summary = report['summary'] as Map<String, dynamic>;
      final methods = summary['methods'] as Map<String, dynamic>;
      expect(methods.keys, containsAll(['initialize', 'tools/list']));
      final events = report['events'] as List<dynamic>;
      expect(events.length, greaterThan(4));
    });

    test('inspects an official TypeScript SDK client', () async {
      if (!_requireFile(tsClient, 'compiled TypeScript client fixture')) {
        return;
      }

      final reportFile = File(
        p.join(cliDir.path, '.dart_tool', 'client-inspector-ts.json'),
      );
      if (reportFile.existsSync()) {
        reportFile.deleteSync();
      }

      final result = await Process.run(
        'node',
        [
          tsClient.path,
          '--server-command',
          'dart',
          '--server-args',
          'run bin/mcp_dart.dart inspect-client --report ${reportFile.path} --idle-timeout-ms 1000',
          '--server-cwd',
          cliDir.path,
          '--expect-inspector-primitives',
          '--active-client-capabilities',
        ],
      );

      _expectSuccess(result);
      expect(result.stdout, contains('typescript client interop passed'));

      final report = await _readReport(reportFile);
      expect(report['kind'], equals('client'));
      expect(report['passed'], isTrue);
      final metadata = report['metadata'] as Map<String, dynamic>;
      final observed =
          (metadata['observedMethods'] as List<dynamic>).cast<String>();
      expect(
        observed,
        containsAll([
          'initialize',
          'tools/list',
          'tools/call',
          'resources/list',
          'prompts/list',
        ]),
      );
      final checks =
          (report['checks'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final id in [
        'client.roots.list',
        'client.sampling.create-message',
        'client.elicitation.create',
      ]) {
        expect(
          checks,
          contains(
            allOf(
              containsPair('id', id),
              containsPair('status', 'pass'),
            ),
          ),
        );
      }
    });

    test('serves a Dart project to an official Python SDK client', () async {
      if (!_requireFile(pythonClient, 'Python client fixture')) {
        return;
      }
      final python = await _pythonWithMcpSdk();
      if (python == null) return;
      await _prepareDartFixture(dartFixture);

      final result = await Process.run(
        python,
        [
          pythonClient.path,
          '--server-command',
          'dart',
          '--server-args',
          'run mcp_dart_cli:mcp_dart serve',
          '--server-cwd',
          dartFixture.path,
        ],
      );

      _expectSuccess(result);
      expect(result.stdout, contains('python client interop passed'));
    });

    test('inspects an official Python SDK client', () async {
      if (!_requireFile(pythonClient, 'Python client fixture')) {
        return;
      }
      final python = await _pythonWithMcpSdk();
      if (python == null) return;

      final reportFile = File(
        p.join(cliDir.path, '.dart_tool', 'client-inspector-python.json'),
      );
      if (reportFile.existsSync()) {
        reportFile.deleteSync();
      }

      final result = await Process.run(
        python,
        [
          pythonClient.path,
          '--server-command',
          'dart',
          '--server-args',
          'run bin/mcp_dart.dart inspect-client --report ${reportFile.path} --idle-timeout-ms 100',
          '--server-cwd',
          cliDir.path,
          '--expect-inspector-primitives',
        ],
      );

      _expectSuccess(result);
      expect(result.stdout, contains('python client interop passed'));

      final report = await _readReport(reportFile);
      expect(report['kind'], equals('client'));
      expect(report['passed'], isTrue);
      final metadata = report['metadata'] as Map<String, dynamic>;
      final observed =
          (metadata['observedMethods'] as List<dynamic>).cast<String>();
      expect(
        observed,
        containsAll([
          'initialize',
          'tools/list',
          'tools/call',
          'resources/list',
          'prompts/list',
        ]),
      );
    });
  });
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (current.path != current.parent.path) {
    if (File(p.join(current.path, 'AGENTS.md')).existsSync() &&
        Directory(p.join(current.path, 'packages', 'mcp_dart_cli'))
            .existsSync()) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('Could not locate repository root from ${start.path}.');
}

Future<ProcessResult> _runCli(
  List<String> args, {
  required Directory workingDirectory,
}) {
  return Process.run(
    'dart',
    ['run', 'bin/mcp_dart.dart', ...args],
    workingDirectory: workingDirectory.path,
  );
}

Future<void> _prepareDartFixture(Directory fixture) async {
  final result = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: fixture.path,
  );
  _expectSuccess(result);
}

Future<String?> _pythonWithMcpSdk() async {
  for (final candidate in [
    Platform.environment['PYTHON'],
    'python3',
    'python',
  ].whereType<String>()) {
    final result = await Process.run(
      candidate,
      ['-c', 'import mcp, sys; print(sys.executable)'],
    );
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  }

  final message = 'Python MCP SDK is not installed.';
  if (_isCi) {
    fail(message);
  }
  markTestSkipped(message);
  return null;
}

Future<File> _pythonConsoleScript(String python, String scriptName) async {
  final pythonFile = File(python);
  final siblingNames = Platform.isWindows
      ? <String>['$scriptName.exe', '$scriptName.cmd', scriptName]
      : <String>[scriptName];
  for (final siblingName in siblingNames) {
    final candidate = File(p.join(pythonFile.parent.path, siblingName));
    if (candidate.existsSync()) {
      return candidate;
    }
  }

  final result = await Process.run(
    python,
    [
      '-c',
      'import shutil, sys; sys.stdout.write(shutil.which(${jsonEncode(scriptName)}) or "")',
    ],
  );
  final resolved = (result.stdout as String).trim();
  if (resolved.isNotEmpty) {
    return File(resolved);
  }
  return File(p.join(pythonFile.parent.path, scriptName));
}

Future<Map<String, dynamic>> _readReport(File reportFile) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (reportFile.existsSync()) {
      return jsonDecode(await reportFile.readAsString())
          as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Inspector report was not written at ${reportFile.path}.');
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
      final request = await client.getUrl(uri).timeout(
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

bool _requireFile(File file, String description) {
  if (file.existsSync()) return true;

  final message = '$description is missing at ${file.path}.';
  if (_isCi) {
    fail(message);
  }
  markTestSkipped(message);
  return false;
}

void _expectChecksPass(Map<String, dynamic> report, List<String> ids) {
  final checks = (report['checks'] as List<dynamic>)
      .map((check) => (check as Map).cast<String, dynamic>())
      .toList();
  for (final id in ids) {
    expect(
      checks,
      contains(
        allOf(
          containsPair('id', id),
          containsPair('status', 'pass'),
        ),
      ),
    );
  }
}

void _expectSuccess(ProcessResult result, {_ManagedProcess? process}) {
  if (result.exitCode != 0) {
    fail(
      'Process failed with exit code ${result.exitCode}\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}'
      '${process == null ? '' : '\nserver stdout:\n${process.stdoutText}\nserver stderr:\n${process.stderrText}'}',
    );
  }
}

bool get _isCi => Platform.environment['CI'] == 'true';

class _ManagedProcess {
  _ManagedProcess._(
    this.process,
    this._stdoutSubscription,
    this._stderrSubscription,
    this._stdout,
    this._stderr,
  );

  final Process process;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;
  final StringBuffer _stdout;
  final StringBuffer _stderr;

  String get stdoutText => _stdout.toString();
  String get stderrText => _stderr.toString();

  static Future<_ManagedProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(executable, arguments);
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutSubscription =
        process.stdout.transform(utf8.decoder).listen(stdout.write);
    final stderrSubscription =
        process.stderr.transform(utf8.decoder).listen(stderr.write);
    return _ManagedProcess._(
      process,
      stdoutSubscription,
      stderrSubscription,
      stdout,
      stderr,
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
