import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultConformancePackage =
    '@modelcontextprotocol/conformance@0.2.0-alpha.8';
const _defaultTimeout = Duration(seconds: 25);

const _serverScenarios = [
  'server-stateless',
  'completion-complete',
  'tools-list',
  'tools-call-simple-text',
  'tools-call-image',
  'tools-call-audio',
  'tools-call-embedded-resource',
  'tools-call-mixed-content',
  'tools-call-error',
  'tools-call-with-progress',
  'json-schema-2020-12',
  'server-sse-multiple-streams',
  'resources-list',
  'resources-read-text',
  'resources-read-binary',
  'resources-templates-read',
  'sep-2164-resource-not-found',
  'prompts-list',
  'prompts-get-simple',
  'prompts-get-with-args',
  'prompts-get-embedded-resource',
  'prompts-get-with-image',
  'dns-rebinding-protection',
  'caching',
  'http-header-validation',
  'http-custom-header-server-validation',
  'input-required-result-basic-elicitation',
  'input-required-result-basic-sampling',
  'input-required-result-basic-list-roots',
  'input-required-result-request-state',
  'input-required-result-multiple-input-requests',
  'input-required-result-multi-round',
  'input-required-result-missing-input-response',
  'input-required-result-non-tool-request',
  'input-required-result-result-type',
  'input-required-result-unsupported-methods',
  'input-required-result-tampered-state',
  'input-required-result-capability-check',
  'input-required-result-ignore-extra-params',
  'input-required-result-validate-input',
];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final expectedFailures = await _readExpectedFailures(
    options.expectedFailuresPath,
  );
  final outputRoot = await _createOutputRoot(options.outputDir);
  final scenarios =
      options.scenario == null ? _serverScenarios : [options.scenario!];

  Process? serverProcess;
  var serverOutputSubscriptions = <StreamSubscription<String>>[];
  late final Uri serverUrl;
  try {
    if (options.url == null) {
      final port = options.port ?? await _findFreePort();
      serverUrl = Uri.parse('http://localhost:$port/mcp');
      serverProcess = await Process.start(
        Platform.resolvedExecutable,
        [
          'test/conformance/mcp_2026_07_28_rc_server.dart',
          '--port',
          '$port',
        ],
        workingDirectory: Directory.current.path,
      );
      serverOutputSubscriptions = _pipeServerOutput(serverProcess);
      await _waitForPort('localhost', port);
    } else {
      serverUrl = Uri.parse(options.url!);
    }

    stdout.writeln('2026-07-28 RC conformance URL: $serverUrl');
    stdout.writeln('Conformance package: ${options.conformancePackage}');
    stdout.writeln('Output: ${outputRoot.path}');
    stdout.writeln('');

    final results = <_ScenarioResult>[];
    for (final scenario in scenarios) {
      final result = await _runScenario(
        scenario: scenario,
        serverUrl: serverUrl,
        outputRoot: outputRoot,
        conformancePackage: options.conformancePackage,
        timeout: options.timeout,
      );
      results.add(result);
      _printScenarioResult(result, expectedFailures);
    }

    await _writeSummary(
      outputRoot,
      results,
      expectedFailures,
      options.conformancePackage,
    );
    final unexpectedFailures = results
        .where(
          (result) =>
              !result.passed && !expectedFailures.contains(result.scenario),
        )
        .toList();
    final unexpectedPasses = results
        .where(
          (result) =>
              result.passed && expectedFailures.contains(result.scenario),
        )
        .toList();

    stdout.writeln('');
    stdout.writeln(
      'Summary: ${results.where((result) => result.passed).length} passed, '
      '${results.where((result) => !result.passed).length} failed/timeout.',
    );

    if (unexpectedFailures.isNotEmpty) {
      stdout.writeln('Unexpected failures:');
      for (final result in unexpectedFailures) {
        stdout.writeln('  - ${result.scenario} (${result.status})');
      }
    }
    if (unexpectedPasses.isNotEmpty) {
      stdout.writeln('Unexpected passes; remove these from expected failures:');
      for (final result in unexpectedPasses) {
        stdout.writeln('  - ${result.scenario}');
      }
    }

    exitCode = unexpectedFailures.isEmpty && unexpectedPasses.isEmpty ? 0 : 1;
  } finally {
    if (serverProcess != null) {
      await _stopProcess(serverProcess);
      for (final subscription in serverOutputSubscriptions) {
        unawaited(subscription.cancel());
      }
    }
  }

  exit(exitCode);
}

Future<Set<String>> _readExpectedFailures(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return const {};
  }

  final entries = <String>{};
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    entries.add(trimmed);
  }
  return entries;
}

Future<Directory> _createOutputRoot(String? outputDir) async {
  final root = outputDir == null
      ? Directory(
          '.dart_tool/conformance/2026_07_28_rc/'
          '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}',
        )
      : Directory(outputDir);
  await root.create(recursive: true);
  return root;
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

List<StreamSubscription<String>> _pipeServerOutput(Process process) {
  // ignore: cancel_subscriptions
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stdout.writeln('[server] $line'));
  // ignore: cancel_subscriptions
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr.writeln('[server] $line'));
  return [stdoutSubscription, stderrSubscription];
}

Future<void> _stopProcess(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 3));
    return;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
  }
  await process.exitCode.timeout(
    const Duration(seconds: 3),
    onTimeout: () => -1,
  );
}

Future<void> _waitForPort(String host, int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      await socket.close();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
  throw StateError('Timed out waiting for $host:$port');
}

Future<_ScenarioResult> _runScenario({
  required String scenario,
  required Uri serverUrl,
  required Directory outputRoot,
  required String conformancePackage,
  required Duration timeout,
}) async {
  final outputDir = Directory('${outputRoot.path}/${_sanitize(scenario)}');
  await outputDir.create(recursive: true);

  final process = await Process.start(
    'npx',
    [
      '-y',
      conformancePackage,
      'server',
      '--url',
      serverUrl.toString(),
      '--suite',
      'all',
      '--spec-version',
      '2026-07-28',
      '--scenario',
      scenario,
      '--verbose',
      '-o',
      outputDir.path,
    ],
    workingDirectory: Directory.current.path,
  );

  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .listen(stdoutBuffer.write)
      .asFuture<void>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write)
      .asFuture<void>();

  try {
    final code = await process.exitCode.timeout(timeout);
    await Future.wait([stdoutDone, stderrDone]);
    return _ScenarioResult(
      scenario: scenario,
      exitCode: code,
      timedOut: false,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    return _ScenarioResult(
      scenario: scenario,
      exitCode: null,
      timedOut: true,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }
}

void _printScenarioResult(
  _ScenarioResult result,
  Set<String> expectedFailures,
) {
  final expected = expectedFailures.contains(result.scenario);
  final marker = result.passed
      ? expected
          ? 'UNEXPECTED PASS'
          : 'PASS'
      : expected
          ? 'EXPECTED ${result.status.toUpperCase()}'
          : 'FAIL';
  stdout.writeln('${marker.padRight(18)} ${result.scenario}');
}

Future<void> _writeSummary(
  Directory outputRoot,
  List<_ScenarioResult> results,
  Set<String> expectedFailures,
  String conformancePackage,
) async {
  final summary = {
    'package': conformancePackage,
    'expectedFailures': expectedFailures.toList()..sort(),
    'results': [
      for (final result in results)
        {
          'scenario': result.scenario,
          'status': result.status,
          'exitCode': result.exitCode,
          'expectedFailure': expectedFailures.contains(result.scenario),
        },
    ],
  };
  await File('${outputRoot.path}/summary.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
}

String _sanitize(String value) {
  return value.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run test/conformance/run_2026_07_28_rc_server_conformance.dart '
    '[--url http://localhost:33125/mcp] [--scenario scenario-name] '
    '[--timeout-seconds 25]',
  );
}

class _ScenarioResult {
  final String scenario;
  final int? exitCode;
  final bool timedOut;
  final String stdout;
  final String stderr;

  const _ScenarioResult({
    required this.scenario,
    required this.exitCode,
    required this.timedOut,
    required this.stdout,
    required this.stderr,
  });

  bool get passed => !timedOut && exitCode == 0;

  String get status {
    if (timedOut) {
      return 'timeout';
    }
    if (exitCode == 0) {
      return 'pass';
    }
    return 'exit-$exitCode';
  }
}

class _Options {
  final bool help;
  final String? url;
  final int? port;
  final String? scenario;
  final String? outputDir;
  final String expectedFailuresPath;
  final String conformancePackage;
  final Duration timeout;

  const _Options({
    required this.help,
    required this.url,
    required this.port,
    required this.scenario,
    required this.outputDir,
    required this.expectedFailuresPath,
    required this.conformancePackage,
    required this.timeout,
  });

  factory _Options.parse(List<String> args) {
    var help = false;
    String? url;
    int? port;
    String? scenario;
    String? outputDir;
    var expectedFailuresPath =
        'test/conformance/2026_07_28_rc_expected_failures.txt';
    var conformancePackage = _defaultConformancePackage;
    var timeout = _defaultTimeout;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--help':
          help = true;
        case '--url':
          if (i + 1 < args.length) {
            url = args[++i];
          }
        case '--port':
          if (i + 1 < args.length) {
            port = int.tryParse(args[++i]);
          }
        case '--scenario':
          if (i + 1 < args.length) {
            scenario = args[++i];
          }
        case '--output-dir':
          if (i + 1 < args.length) {
            outputDir = args[++i];
          }
        case '--expected-failures':
          if (i + 1 < args.length) {
            expectedFailuresPath = args[++i];
          }
        case '--conformance-package':
          if (i + 1 < args.length) {
            conformancePackage = args[++i];
          }
        case '--timeout-seconds':
          if (i + 1 < args.length) {
            final seconds = int.tryParse(args[++i]);
            if (seconds != null && seconds > 0) {
              timeout = Duration(seconds: seconds);
            }
          }
      }
    }

    return _Options(
      help: help,
      url: url,
      port: port,
      scenario: scenario,
      outputDir: outputDir,
      expectedFailuresPath: expectedFailuresPath,
      conformancePackage: conformancePackage,
      timeout: timeout,
    );
  }
}
