import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _browserTestPort = 8765;
const _legacySseFixturePort = 8766;

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
      'test/conformance/mcp_2026_07_28_server.dart',
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
            'MCP 2026-07-28 conformance server listening on',
          )) {
        serverReady.complete();
      }
    },
  );
  final serverStderr = _pipeLines(server.stderr, stderr, '[dart-server]');
  Process? legacySseFixture;
  Future<void>? legacySseStdout;
  Future<void>? legacySseStderr;
  Process? browserTest;
  Future<void>? browserTestStdout;
  Future<void>? browserTestStderr;

  try {
    legacySseFixture = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        'tool/testing/legacy_sse_browser_fixture.dart',
        '--host',
        '127.0.0.1',
        '--port',
        '$_legacySseFixturePort',
      ],
      workingDirectory: repoRoot.path,
    );
    final legacySseReady = Completer<void>();
    legacySseStdout = _pipeLines(
      legacySseFixture.stdout,
      stdout,
      '[legacy-sse-fixture]',
      onLine: (line) {
        if (!legacySseReady.isCompleted &&
            line.contains('Legacy SSE browser fixture listening on')) {
          legacySseReady.complete();
        }
      },
    );
    legacySseStderr = _pipeLines(
      legacySseFixture.stderr,
      stderr,
      '[legacy-sse-fixture]',
    );

    await Future.wait([
      _waitUntilReady(
        process: server,
        ready: serverReady.future,
        label: 'Dart conformance server',
      ),
      _waitUntilReady(
        process: legacySseFixture,
        ready: legacySseReady.future,
        label: 'legacy SSE browser fixture',
      ),
    ]);
    final test = await Process.start(
      Platform.resolvedExecutable,
      [
        'test',
        '--platform',
        'chrome',
        '--timeout',
        '1m',
        'test/browser/mcp_2026_07_28_streamable_http_test.dart',
        'test/interop/browser_legacy_sse_client_test.dart',
      ],
      workingDirectory: repoRoot.path,
    );
    browserTest = test;
    browserTestStdout = _pipeLines(test.stdout, stdout, '[browser-test]');
    browserTestStderr = _pipeLines(test.stderr, stderr, '[browser-test]');
    final testExit = await test.exitCode.timeout(const Duration(minutes: 3));
    await Future.wait([browserTestStdout, browserTestStderr]);
    if (testExit != 0) {
      throw StateError('Browser interop tests exited with $testExit');
    }
  } on Object catch (error) {
    stderr.writeln('Browser interop failed: $error');
    exitCode = 1;
  } finally {
    final fixture = legacySseFixture;
    final test = browserTest;
    await Future.wait([
      if (test != null) _terminate(test),
      _terminate(server),
      if (fixture != null) _terminate(fixture),
    ]);
    await Future.wait([
      serverStdout,
      serverStderr,
      if (legacySseStdout != null) legacySseStdout,
      if (legacySseStderr != null) legacySseStderr,
      if (browserTestStdout != null) browserTestStdout,
      if (browserTestStderr != null) browserTestStderr,
    ]);
  }
}

Future<void> _waitUntilReady({
  required Process process,
  required Future<void> ready,
  required String label,
}) async {
  await Future.any<void>([
    ready,
    process.exitCode.then<void>((code) {
      throw StateError('$label exited with code $code before becoming ready');
    }),
  ]).timeout(
    const Duration(seconds: 20),
    onTimeout: () {
      throw TimeoutException('Timed out waiting for $label');
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
