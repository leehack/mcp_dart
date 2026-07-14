import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

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

  try {
    await _runPythonClientAgainstDartServer(repoRoot, fixtureDir, python);
    await _runDartClientAgainstPythonServer(repoRoot, fixtureDir, python);
  } on Object catch (error) {
    stderr.writeln('Python 2026-07-28 interop failed: $error');
    exitCode = 1;
  }
}

Future<void> _runPythonClientAgainstDartServer(
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

  try {
    final url = await serverUrl.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Timed out waiting for Dart server URL');
      },
    );
    final client = await Process.start(
      python,
      ['client.py', '--url', url],
      workingDirectory: fixtureDir.path,
    );
    final clientStdout = _pipeLines(client.stdout, stdout, '[python-client]');
    final clientStderr = _pipeLines(client.stderr, stderr, '[python-client]');
    final clientExit = await client.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await Future.wait([clientStdout, clientStderr]);
    if (clientExit != 0) {
      throw StateError(
        'Python 2026-07-28 client exited with $clientExit',
      );
    }
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }
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
    final url = await serverUrl.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Timed out waiting for Python server URL');
      },
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
    if (version != previewProtocolVersion) {
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

String _firstText(CallToolResult result, String label) {
  final content = result.content;
  if (content.isEmpty || content.first is! TextContent) {
    throw StateError('$label expected text content: ${result.toJson()}');
  }
  return (content.first as TextContent).text;
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
