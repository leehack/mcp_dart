import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current;
  final fixtureDir = Directory('test/interop/ts_2026_07_28_rc');
  final clientPackage = File(
    'test/interop/ts_2026_07_28_rc/node_modules/'
    '@modelcontextprotocol/client/package.json',
  );
  final serverPackage = File(
    'test/interop/ts_2026_07_28_rc/node_modules/'
    '@modelcontextprotocol/server/package.json',
  );

  if (!File('pubspec.yaml').existsSync() || !fixtureDir.existsSync()) {
    stderr.writeln(
      'Run this command from the mcp_dart repository root.',
    );
    exitCode = 64;
    return;
  }

  if (!clientPackage.existsSync()) {
    stderr.writeln(
      'Missing TypeScript fixture dependencies. Run:\n'
      '  cd test/interop/ts_2026_07_28_rc\n'
      '  npm install',
    );
    exitCode = 64;
    return;
  }
  if (!serverPackage.existsSync()) {
    stderr.writeln(
      'Missing TypeScript server fixture dependencies. Run:\n'
      '  cd test/interop/ts_2026_07_28_rc\n'
      '  npm install',
    );
    exitCode = 64;
    return;
  }

  try {
    await _runTsClientAgainstDartServer(repoRoot, fixtureDir);
    await _runDartClientAgainstTsServer(repoRoot, fixtureDir);
  } on Object catch (error) {
    stderr.writeln('TS 2026-07-28 RC interop failed: $error');
    exitCode = 1;
  }
}

Future<void> _runTsClientAgainstDartServer(
  Directory repoRoot,
  Directory fixtureDir,
) async {
  final server = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      'test/conformance/mcp_2026_07_28_rc_server.dart',
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
      'MCP 2026-07-28 RC conformance server listening on',
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
      'node',
      ['src/client.mjs', '--url', url],
      workingDirectory: fixtureDir.path,
    );
    final clientStdout = _pipeLines(client.stdout, stdout, '[ts-client]');
    final clientStderr = _pipeLines(client.stderr, stderr, '[ts-client]');
    final clientExit = await client.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await Future.wait([clientStdout, clientStderr]);

    if (clientExit != 0) {
      throw StateError(
        'TypeScript 2026-07-28 RC client exited with $clientExit',
      );
    }
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }
}

Future<void> _runDartClientAgainstTsServer(
  Directory repoRoot,
  Directory fixtureDir,
) async {
  final server = await Process.start(
    'node',
    ['src/server.mjs', '--host', '127.0.0.1', '--port', '0'],
    workingDirectory: fixtureDir.path,
  );

  final serverUrl = Completer<String>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[ts-server]',
    onLine: (line) => _completeUrlFromLine(
      serverUrl,
      line,
      'TS 2026-07-28 RC interop server listening on',
    ),
  );
  final serverStderr = _pipeLines(server.stderr, stderr, '[ts-server]');

  try {
    final url = await serverUrl.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Timed out waiting for TypeScript server URL');
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
      name: 'mcp-dart-2026-07-28-rc-client',
      version: '0.0.0',
    ),
    options: const McpClientOptions(
      protocol: McpProtocol.preview2026,
      capabilities: ClientCapabilities(
        elicitation: ClientElicitation(
          form: ClientElicitationForm(applyDefaults: true),
        ),
      ),
    ),
  );
  client.onElicitRequest = (request) async {
    if (request.message != 'What should the TypeScript fixture call you?') {
      throw StateError('Unexpected elicitation message: ${request.message}');
    }
    return const ElicitResult(
      action: 'accept',
      content: {'name': 'Dart Tester'},
    );
  };

  try {
    await client.connect(transport).timeout(const Duration(seconds: 20));
    final version = client.getProtocolVersion();
    if (version != draftProtocolVersion2026_07_28) {
      throw StateError('Expected 2026-07-28, got $version');
    }
    final serverInfo = client.getServerVersion();
    if (serverInfo?.name != 'ts-2026-07-28-rc-interop-server') {
      throw StateError('Unexpected TS server info: ${serverInfo?.toJson()}');
    }

    final tools = await client.listTools().timeout(const Duration(seconds: 10));
    if (!tools.tools.any((tool) => tool.name == 'ts_echo')) {
      throw StateError(
        'TS server tools/list did not include ts_echo: '
        '${tools.tools.map((tool) => tool.name).toList()}',
      );
    }
    if (!tools.tools.any(
      (tool) => tool.name == 'ts_input_required_elicitation',
    )) {
      throw StateError(
        'TS server tools/list did not include ts_input_required_elicitation: '
        '${tools.tools.map((tool) => tool.name).toList()}',
      );
    }

    const message = 'from Dart 2026-07-28 RC preview';
    final echo = await client
        .callTool(
          const CallToolRequest(
            name: 'ts_echo',
            arguments: {'message': message},
          ),
        )
        .timeout(const Duration(seconds: 10));
    final text = _firstText(echo, 'ts_echo');
    if (text != message) {
      throw StateError('Unexpected ts_echo result: $text');
    }

    final elicitation = await client
        .callTool(
          const CallToolRequest(name: 'ts_input_required_elicitation'),
        )
        .timeout(const Duration(seconds: 10));
    final elicitationText = _firstText(
      elicitation,
      'ts_input_required_elicitation',
    );
    if (elicitationText != 'Hello, Dart Tester!') {
      throw StateError(
        'Unexpected ts_input_required_elicitation result: $elicitationText',
      );
    }

    stdout.writeln(
      '[dart-client] ${jsonEncode({
            'protocolVersion': version,
            'serverInfo': serverInfo?.toJson(),
            'toolCount': tools.tools.length,
            'echo': text,
            'inputRequired': elicitationText,
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
  final urlPattern = RegExp(r'(http://[^\s]+)');
  final match = urlPattern.firstMatch(line);
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
