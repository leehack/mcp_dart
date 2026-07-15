import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _serverPort = 3000;

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this command from the mcp_dart repository root.');
    exitCode = 64;
    return;
  }

  final server = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      'test/conformance/mcp_2026_07_28_server.dart',
      '--host',
      'localhost',
      '--port',
      '$_serverPort',
    ],
    workingDirectory: Directory.current.path,
  );
  final serverReady = Completer<void>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[flutter-e2e-server]',
    onLine: (line) {
      if (!serverReady.isCompleted &&
          line.contains('MCP 2026-07-28 conformance server listening on')) {
        serverReady.complete();
      }
    },
  );
  final serverStderr = _pipeLines(
    server.stderr,
    stderr,
    '[flutter-e2e-server]',
  );
  Process? test;
  Future<void>? testStdout;
  Future<void>? testStderr;

  try {
    await serverReady.future.timeout(const Duration(seconds: 20));
    test = await Process.start(
      'flutter',
      [
        'test',
        '--platform',
        'chrome',
        '--timeout',
        '2m',
        'test/browser_e2e_test.dart',
      ],
      workingDirectory: '${Directory.current.path}/example/flutter_http_client',
    );
    testStdout = _pipeLines(
      test.stdout,
      stdout,
      '[flutter-browser-test]',
    );
    testStderr = _pipeLines(
      test.stderr,
      stderr,
      '[flutter-browser-test]',
    );
    final testExit = await test.exitCode.timeout(const Duration(minutes: 4));
    if (testExit != 0) {
      throw StateError('Flutter Web browser test exited with $testExit');
    }
  } on Object catch (error) {
    stderr.writeln('Flutter Web example E2E failed: $error');
    exitCode = 1;
  } finally {
    if (test != null) {
      await _terminate(test);
    }
    await Future.wait([
      if (testStdout != null) testStdout,
      if (testStderr != null) testStderr,
    ]);
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
