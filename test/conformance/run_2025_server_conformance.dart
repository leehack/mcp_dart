import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'conformance_scenario_inventory.dart';

const _defaultConformancePackage =
    '@modelcontextprotocol/conformance@0.2.0-alpha.9';
const _defaultTimeout = Duration(seconds: 60);

// The alpha conformance CLI can occasionally leak or stall server-initiated
// elicitation state when the complete MCP 2025-11-25 server suite runs in one
// process
// on GitHub's Linux runners. Running each pinned scenario in a fresh
// conformance process preserves coverage while isolating CLI-side state.
const _serverScenarios = [
  'server-initialize',
  'logging-set-level',
  'ping',
  'completion-complete',
  'tools-list',
  'tools-call-simple-text',
  'tools-call-image',
  'tools-call-audio',
  'tools-call-embedded-resource',
  'tools-call-mixed-content',
  'tools-call-with-logging',
  'tools-call-error',
  'tools-call-with-progress',
  'tools-call-sampling',
  'tools-call-elicitation',
  'json-schema-2020-12',
  'elicitation-sep1034-defaults',
  'server-sse-polling',
  'server-sse-multiple-streams',
  'elicitation-sep1330-enums',
  'resources-list',
  'resources-read-text',
  'resources-read-binary',
  'resources-templates-read',
  'resources-subscribe',
  'resources-unsubscribe',
  'prompts-list',
  'prompts-get-simple',
  'prompts-get-with-args',
  'prompts-get-embedded-resource',
  'prompts-get-with-image',
  'dns-rebinding-protection',
];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final scenarios =
      options.scenario == null ? _serverScenarios : [options.scenario!];
  await verifyConformanceScenarioInventory(
    conformancePackage: options.conformancePackage,
    role: 'server',
    specVersion: '2025-11-25',
    expectedScenarios: scenarios,
    requireExactMatch: options.scenario == null,
  );

  final outputRoot = await _createOutputRoot(options.outputDir);

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
          'test/conformance/mcp_2025_server.dart',
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

    stdout.writeln('MCP 2025-11-25 conformance URL: $serverUrl');
    stdout.writeln('Conformance package: ${options.conformancePackage}');
    stdout.writeln('Output: ${outputRoot.path}');
    stdout.writeln('');

    final result = options.isolateScenarios && options.scenario == null
        ? await _runIsolatedConformance(
            serverUrl: serverUrl,
            outputRoot: outputRoot,
            conformancePackage: options.conformancePackage,
            timeout: options.timeout,
          )
        : await _runConformance(
            serverUrl: serverUrl,
            outputRoot: outputRoot,
            conformancePackage: options.conformancePackage,
            scenario: options.scenario,
            timeout: options.timeout,
          );

    exitCode = result.exitCode ?? 1;
    if (result.timedOut) {
      stdout.writeln('Timed out after ${options.timeout.inSeconds}s.');
      exitCode = 1;
    }
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

Future<Directory> _createOutputRoot(String? outputDir) async {
  final root = outputDir == null
      ? Directory(
          '.dart_tool/conformance/2025_server/'
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

Future<_RunResult> _runConformance({
  required Uri serverUrl,
  required Directory outputRoot,
  required String conformancePackage,
  required String? scenario,
  required Duration timeout,
}) async {
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
      '2025-11-25',
      if (scenario != null) ...[
        '--scenario',
        scenario,
      ],
      '--verbose',
      '-o',
      outputRoot.path,
    ],
    workingDirectory: Directory.current.path,
  );

  final stdoutDone = process.stdout.listen(stdout.add).asFuture<void>();
  final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();

  try {
    final code = await process.exitCode.timeout(timeout);
    await Future.wait([stdoutDone, stderrDone]);
    return _RunResult(exitCode: code, timedOut: false);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await Future.wait([
      stdoutDone.catchError((_) {}),
      stderrDone.catchError((_) {}),
    ]);
    return const _RunResult(exitCode: null, timedOut: true);
  }
}

Future<_RunResult> _runIsolatedConformance({
  required Uri serverUrl,
  required Directory outputRoot,
  required String conformancePackage,
  required Duration timeout,
}) async {
  var failed = false;
  var timedOut = false;

  for (final scenario in _serverScenarios) {
    stdout.writeln('');
    stdout.writeln('=== Running isolated scenario: $scenario ===');
    final result = await _runConformance(
      serverUrl: serverUrl,
      outputRoot: Directory('${outputRoot.path}/$scenario'),
      conformancePackage: conformancePackage,
      scenario: scenario,
      timeout: timeout,
    );
    if (result.timedOut) {
      timedOut = true;
    }
    if (result.exitCode != 0) {
      failed = true;
    }
  }

  if (timedOut) {
    return const _RunResult(exitCode: 1, timedOut: true);
  }
  return _RunResult(exitCode: failed ? 1 : 0, timedOut: false);
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run test/conformance/run_2025_server_conformance.dart [options]

Options:
  --scenario <name>              Run one scenario instead of the full suite.
  --url <url>                    Use an already-running server.
  --port <port>                  Port for the local fixture server.
  --output-dir <path>            Directory for conformance artifacts.
  --conformance-package <pkg>    Conformance npm package.
  --timeout-seconds <seconds>    Conformance command timeout.
  --isolate-scenarios            Run each pinned MCP 2025-11-25 scenario in a fresh
                                 conformance process.
  --help                         Show this help.
''');
}

class _Options {
  final String? scenario;
  final String? url;
  final int? port;
  final String? outputDir;
  final String conformancePackage;
  final Duration timeout;
  final bool isolateScenarios;
  final bool help;

  const _Options({
    required this.scenario,
    required this.url,
    required this.port,
    required this.outputDir,
    required this.conformancePackage,
    required this.timeout,
    required this.isolateScenarios,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    String? scenario;
    String? url;
    int? port;
    String? outputDir;
    var conformancePackage = _defaultConformancePackage;
    var timeout = _defaultTimeout;
    var isolateScenarios = false;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--scenario':
          scenario = args[++i];
        case '--url':
          url = args[++i];
        case '--port':
          port = int.parse(args[++i]);
        case '--output-dir':
          outputDir = args[++i];
        case '--conformance-package':
          conformancePackage = args[++i];
        case '--timeout-seconds':
          timeout = Duration(seconds: int.parse(args[++i]));
        case '--isolate-scenarios':
          isolateScenarios = true;
        case '--help':
          help = true;
        default:
          throw ArgumentError('Unknown argument: ${args[i]}');
      }
    }

    return _Options(
      scenario: scenario,
      url: url,
      port: port,
      outputDir: outputDir,
      conformancePackage: conformancePackage,
      timeout: timeout,
      isolateScenarios: isolateScenarios,
      help: help,
    );
  }
}

class _RunResult {
  final int? exitCode;
  final bool timedOut;

  const _RunResult({
    required this.exitCode,
    required this.timedOut,
  });
}
