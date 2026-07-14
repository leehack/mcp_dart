import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _browserTestPort = 8765;

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current;
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this command from the mcp_dart repository root.');
    exitCode = 64;
    return;
  }

  final server = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      'test/conformance/mcp_2026_07_28_rc_server.dart',
      '--host',
      'localhost',
      '--port',
      '$_browserTestPort',
    ],
    workingDirectory: repoRoot.path,
  );
  final serverReady = Completer<void>();
  final serverStdout = _pipeLines(
    server.stdout,
    stdout,
    '[dart-server]',
    onLine: (line) {
      if (!serverReady.isCompleted &&
          line.contains(
            'MCP 2026-07-28 RC conformance server listening on',
          )) {
        serverReady.complete();
      }
    },
  );
  final serverStderr = _pipeLines(server.stderr, stderr, '[dart-server]');

  try {
    await serverReady.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Timed out waiting for Dart server');
      },
    );
    final test = await Process.start(
      Platform.resolvedExecutable,
      [
        'test',
        '--platform',
        'chrome',
        '--timeout',
        '1m',
        'test/browser/mcp_2026_07_28_streamable_http_test.dart',
      ],
      workingDirectory: repoRoot.path,
    );
    final testStdout = _pipeLines(test.stdout, stdout, '[browser-test]');
    final testStderr = _pipeLines(test.stderr, stderr, '[browser-test]');
    final testExit = await test.exitCode.timeout(const Duration(minutes: 3));
    await Future.wait([testStdout, testStderr]);
    if (testExit != 0) {
      throw StateError('Browser 2026-07-28 test exited with $testExit');
    }
  } on Object catch (error) {
    stderr.writeln('Browser 2026-07-28 RC interop failed: $error');
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
