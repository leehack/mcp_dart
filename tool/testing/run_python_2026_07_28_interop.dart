import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import 'mcp_2026_07_28_discovery_wire_probe.dart';

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current;
  final fixtureDir = Directory('test/interop/python_2026_07_28');
  final configuredPython = Platform.environment['MCP_PYTHON'] ?? 'python3';
  final python = configuredPython.contains(Platform.pathSeparator)
      ? File(configuredPython).absolute.path
      : configuredPython;

  if (!File('pubspec.yaml').existsSync() || !fixtureDir.existsSync()) {
    stderr.writeln('Run this command from the mcp_dart repository root.');
    exitCode = 64;
    return;
  }

  final direction = args
      .where((argument) => argument.startsWith('--direction='))
      .map((argument) => argument.substring('--direction='.length))
      .firstOrNull;
  if (direction != null &&
      direction != 'all' &&
      direction != 'dart-to-python' &&
      direction != 'python-to-dart') {
    stderr.writeln(
      'Invalid --direction. Use all, dart-to-python, or python-to-dart.',
    );
    exitCode = 64;
    return;
  }
  final selectedDirection = direction ?? 'all';
  if (args.contains('--expect-published-python-client-gap')) {
    stderr.writeln(
      '--expect-published-python-client-gap is retired: the pinned published '
      'Python stable release must pass both directions.',
    );
    exitCode = 64;
    return;
  }

  try {
    if (selectedDirection != 'dart-to-python') {
      final pythonClientExitCode = await _runPythonClientAgainstDartServer(
        repoRoot,
        fixtureDir,
        python,
      );
      if (pythonClientExitCode != 0) {
        throw StateError(
          'Python MCP 2026-07-28 client exited with $pythonClientExitCode',
        );
      }
      final pythonLegacyClientExitCode =
          await _runPythonLegacySseClientAgainstDartServer(
        repoRoot,
        fixtureDir,
        python,
      );
      if (pythonLegacyClientExitCode != 0) {
        throw StateError(
          'Python legacy SSE client exited with '
          '$pythonLegacyClientExitCode',
        );
      }
    }
    if (selectedDirection != 'python-to-dart') {
      await _runDartClientAgainstPythonServer(repoRoot, fixtureDir, python);
      await _runDartLegacySseClientAgainstPythonServer(
        repoRoot,
        fixtureDir,
        python,
      );
    }
  } on Object catch (error) {
    stderr.writeln('Python interop failed: $error');
    exitCode = 1;
  }
}

Future<int> _runPythonClientAgainstDartServer(
  Directory repoRoot,
  Directory fixtureDir,
  String python,
) async {
  final server = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      'test/conformance/mcp_2026_07_28_server.dart',
      '--host',
      '127.0.0.1',
      '--port',
      '0',
    ],
    workingDirectory: repoRoot.path,
  );

  final serverUrl = Completer<String>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[dart-server]',
    onLine: (line) => _completeUrlFromLine(
      serverUrl,
      line,
      'MCP 2026-07-28 conformance server listening on',
    ),
  );
  final serverStderr = _pipeLines(server.stderr, stderr, '[dart-server]');
  late int result;

  try {
    final url = await _waitForServerUrl(
      process: server,
      url: serverUrl.future,
      label: 'Dart MCP 2026-07-28 server',
    );
    await assertDartMcp20260728DiscoveryWire(url);
    stdout.writeln(
      '[dart-server-probe] verified anonymous spec #3002 discovery wire shape',
    );

    final client = await Process.start(
      python,
      ['client.py', '--url', url],
      workingDirectory: fixtureDir.path,
    );
    final clientStdout = _pipeLines(
      client.stdout,
      stdout,
      '[python-client]',
    );
    final clientStderr = _pipeLines(
      client.stderr,
      stderr,
      '[python-client]',
    );
    late int clientExit;
    try {
      clientExit = await client.exitCode.timeout(
        const Duration(seconds: 30),
      );
    } finally {
      await _terminate(client);
      await Future.wait([clientStdout, clientStderr]);
    }
    result = clientExit;
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }

  return result;
}

Future<void> _runDartClientAgainstPythonServer(
  Directory repoRoot,
  Directory fixtureDir,
  String python,
) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  final server = await Process.start(
    python,
    ['server.py', '--host', '127.0.0.1', '--port', '$port'],
    workingDirectory: fixtureDir.path,
  );

  final serverUrl = Completer<String>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[python-server]',
    onLine: (line) => _completeUrlFromLine(
      serverUrl,
      line,
      'Python 2026-07-28 interop server listening on',
    ),
  );
  final serverStderr = _pipeLines(server.stderr, stderr, '[python-server]');

  try {
    final url = await _waitForServerUrl(
      process: server,
      url: serverUrl.future,
      label: 'Python MCP 2026-07-28 server',
    );
    await _exerciseDartClient(url);
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }
}

Future<void> _exerciseDartClient(String url) async {
  final transport = StreamableHttpClientTransport(Uri.parse(url));
  final client = McpClient(
    const Implementation(
      name: 'mcp-dart-python-2026-07-28-client',
      version: '0.0.0',
    ),
    options: const McpClientOptions(protocol: McpProtocol.stable),
  );

  try {
    await client.connect(transport).timeout(const Duration(seconds: 20));
    final version = client.getProtocolVersion();
    if (version != stableProtocolVersion) {
      throw StateError('Expected 2026-07-28, got $version');
    }
    final serverInfo = client.getServerVersion();
    if (serverInfo?.name != 'python-2026-07-28-interop-server') {
      throw StateError(
        'Unexpected Python server info: ${serverInfo?.toJson()}',
      );
    }

    final tools = await client.listTools().timeout(const Duration(seconds: 10));
    if (!tools.tools.any((tool) => tool.name == 'python_echo')) {
      throw StateError(
        'Python server tools/list did not include python_echo: '
        '${tools.tools.map((tool) => tool.name).toList()}',
      );
    }

    const message = 'from Dart 2026-07-28';
    final echo = await client
        .callTool(
          const CallToolRequest(
            name: 'python_echo',
            arguments: {'message': message},
          ),
        )
        .timeout(const Duration(seconds: 10));
    final text = _firstText(echo, 'python_echo');
    if (text != message) {
      throw StateError('Unexpected python_echo result: $text');
    }

    stdout.writeln(
      '[dart-client] ${jsonEncode({
            'protocolVersion': version,
            'serverInfo': serverInfo?.toJson(),
            'toolCount': tools.tools.length,
            'echo': text,
          })}',
    );
  } finally {
    await client.close();
  }
}

Future<int> _runPythonLegacySseClientAgainstDartServer(
  Directory repoRoot,
  Directory fixtureDir,
  String python,
) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  final server = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'example/server_sse.dart'],
    workingDirectory: repoRoot.path,
    environment: {
      ...Platform.environment,
      'PORT': '$port',
      'MCP_ALLOWED_ORIGIN': 'http://localhost:$port',
    },
  );

  final serverUrl = Completer<String>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[dart-legacy-sse-server]',
    onLine: (line) => _completeUrlFromLine(
      serverUrl,
      line,
      'Server listening on',
    ),
  );
  final serverStderr = _pipeLines(
    server.stderr,
    stderr,
    '[dart-legacy-sse-server]',
  );
  late int result;

  try {
    final baseUrl = await _waitForServerUrl(
      process: server,
      url: serverUrl.future,
      label: 'Dart legacy SSE server',
    );
    final client = await Process.start(
      python,
      ['legacy_sse_client.py', '--url', '$baseUrl/sse'],
      workingDirectory: fixtureDir.path,
    );
    final clientStdout = _pipeLines(
      client.stdout,
      stdout,
      '[python-legacy-sse-client]',
    );
    final clientStderr = _pipeLines(
      client.stderr,
      stderr,
      '[python-legacy-sse-client]',
    );
    try {
      result = await client.exitCode.timeout(const Duration(seconds: 30));
    } finally {
      await _terminate(client);
      await Future.wait([clientStdout, clientStderr]);
    }
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }

  return result;
}

Future<void> _runDartLegacySseClientAgainstPythonServer(
  Directory repoRoot,
  Directory fixtureDir,
  String python,
) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  final server = await Process.start(
    python,
    [
      'legacy_sse_server.py',
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
    ],
    workingDirectory: fixtureDir.path,
  );

  final serverUrl = Completer<String>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[python-legacy-sse-server]',
    onLine: (line) => _completeUrlFromLine(
      serverUrl,
      line,
      'Python legacy SSE interop server listening on',
    ),
  );
  final serverStderr = _pipeLines(
    server.stderr,
    stderr,
    '[python-legacy-sse-server]',
  );

  try {
    final url = await _waitForServerUrl(
      process: server,
      url: serverUrl.future,
      label: 'Python legacy SSE server',
    );
    await _exerciseDartLegacySseClient(url);
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }
}

Future<void> _exerciseDartLegacySseClient(String url) async {
  // This fixture intentionally exercises the deprecated compatibility path.
  // ignore: deprecated_member_use_from_same_package
  final transport = SseClientTransport(Uri.parse(url));
  final client = McpClient(
    const Implementation(
      name: 'mcp-dart-python-legacy-sse-client',
      version: '0.0.0',
    ),
    options: const McpClientOptions(protocol: McpProtocol.legacy),
  );

  try {
    await client.connect(transport).timeout(const Duration(seconds: 20));
    final version = client.getProtocolVersion();
    if (version != latestInitializationProtocolVersion) {
      throw StateError('Expected 2025-11-25, got $version');
    }
    final serverInfo = client.getServerVersion();
    if (serverInfo?.name != 'python-2.0.0-legacy-sse-server') {
      throw StateError(
        'Unexpected Python legacy server info: ${serverInfo?.toJson()}',
      );
    }

    final tools = await client.listTools().timeout(const Duration(seconds: 10));
    if (!tools.tools.any((tool) => tool.name == 'calculate')) {
      throw StateError(
        'Python legacy server tools/list did not include calculate: '
        '${tools.tools.map((tool) => tool.name).toList()}',
      );
    }

    final result = await client
        .callTool(
          const CallToolRequest(
            name: 'calculate',
            arguments: {'operation': 'add', 'a': 5, 'b': 10},
          ),
        )
        .timeout(const Duration(seconds: 10));
    final text = _firstText(result, 'calculate');
    if (text != 'Result: 15') {
      throw StateError('Unexpected calculate result: $text');
    }

    stdout.writeln(
      '[dart-legacy-sse-client] ${jsonEncode({
            'protocolVersion': version,
            'serverInfo': serverInfo?.toJson(),
            'toolCount': tools.tools.length,
            'result': text,
          })}',
    );
  } finally {
    await client.close();
  }
}

String _firstText(CallToolResult result, String label) {
  final content = result.content;
  if (content.isEmpty || content.first is! TextContent) {
    throw StateError('$label expected text content: ${result.toJson()}');
  }
  return (content.first as TextContent).text;
}

Future<String> _waitForServerUrl({
  required Process process,
  required Future<String> url,
  required String label,
}) async {
  return Future.any<String>([
    url,
    process.exitCode.then<String>((code) {
      throw StateError('$label exited with code $code before becoming ready');
    }),
  ]).timeout(
    const Duration(seconds: 20),
    onTimeout: () {
      throw TimeoutException('Timed out waiting for $label URL');
    },
  );
}

Future<void> _pipeLines(
  Stream<List<int>> stream,
  IOSink sink,
  String prefix, {
  void Function(String line)? onLine,
}) async {
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    onLine?.call(line);
    sink.writeln('$prefix $line');
  }
}

void _completeUrlFromLine(
  Completer<String> completer,
  String line,
  String marker,
) {
  if (completer.isCompleted || !line.contains(marker)) {
    return;
  }
  final match = RegExp(r'(http://[^\s]+)').firstMatch(line);
  if (match != null) {
    completer.complete(match.group(1)!);
  }
}

Future<void> _terminate(Process process) async {
  final exitFuture = process.exitCode;
  process.kill(ProcessSignal.sigterm);
  try {
    await exitFuture.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await exitFuture;
  }
}
