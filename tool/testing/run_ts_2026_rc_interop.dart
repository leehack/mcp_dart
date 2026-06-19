import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current;
  final fixtureDir = Directory('test/interop/ts_2026_rc');
  final clientPackage = File(
    'test/interop/ts_2026_rc/node_modules/'
    '@modelcontextprotocol/client/package.json',
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
      '  cd test/interop/ts_2026_rc\n'
      '  npm install',
    );
    exitCode = 64;
    return;
  }

  final server = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      'test/conformance/mcp_2026_rc_server.dart',
      '--host',
      '127.0.0.1',
      '--port',
      '0',
    ],
    workingDirectory: repoRoot.path,
  );

  final serverUrl = Completer<String>();
  final urlPattern = RegExp(r'(http://[^\s]+)');

  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[dart-server]',
    onLine: (line) {
      if (serverUrl.isCompleted ||
          !line.contains('MCP 2026 RC conformance server listening on')) {
        return;
      }
      final match = urlPattern.firstMatch(line);
      if (match != null) {
        serverUrl.complete(match.group(1)!);
      }
    },
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
      exitCode = clientExit;
      return;
    }
  } on Object catch (error) {
    stderr.writeln('TS 2026 RC interop failed: $error');
    exitCode = 1;
  } finally {
    await _terminate(server);
    await Future.wait([serverStdout, serverStderr]);
  }
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
