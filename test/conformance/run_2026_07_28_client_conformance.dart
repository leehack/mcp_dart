import 'dart:async';
import 'dart:io';

const _defaultConformancePackage =
    '@modelcontextprotocol/conformance@0.2.0-alpha.11';
const _requirementsRevision = '2026-07-28';
const _defaultTimeout = Duration(seconds: 90);

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final outputRoot = await _createOutputRoot(options.outputDir);
  stdout.writeln('Conformance package: ${options.conformancePackage}');
  stdout.writeln('Output: ${outputRoot.path}');
  stdout.writeln('');

  final result = await _runConformance(
    outputRoot: outputRoot,
    conformancePackage: options.conformancePackage,
    scenario: options.scenario,
    timeout: options.timeout,
  );
  if (result.timedOut) {
    stderr.writeln('Timed out after ${options.timeout.inSeconds}s.');
  }
  exit(result.exitCode ?? 1);
}

Future<Directory> _createOutputRoot(String? outputDir) async {
  final root = outputDir == null
      ? Directory(
          '.dart_tool/conformance/2026_07_28_client/'
          '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}',
        )
      : Directory(outputDir);
  await root.create(recursive: true);
  return root;
}

Future<_RunResult> _runConformance({
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
      'client',
      '--command',
      'dart run test/conformance/mcp_2026_07_28_client.dart',
      if (scenario == null) ...[
        '--requirements',
        _requirementsRevision,
      ] else ...[
        '--scenario',
        scenario,
        '--spec-version',
        _requirementsRevision,
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

void _printUsage() {
  stdout.writeln('''
Usage: dart run test/conformance/run_2026_07_28_client_conformance.dart [options]

Options:
  --scenario <name>              Run one scenario for debugging instead of the
                                 frozen MCP $_requirementsRevision requirements.
  --output-dir <path>            Directory for conformance artifacts.
  --conformance-package <pkg>    Conformance npm package.
  --timeout-seconds <seconds>    Conformance command timeout.
  --help                         Show this help.
''');
}

class _Options {
  final String? scenario;
  final String? outputDir;
  final String conformancePackage;
  final Duration timeout;
  final bool help;

  const _Options({
    required this.scenario,
    required this.outputDir,
    required this.conformancePackage,
    required this.timeout,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    String? scenario;
    String? outputDir;
    var conformancePackage = _defaultConformancePackage;
    var timeout = _defaultTimeout;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--scenario':
          scenario = args[++i];
        case '--output-dir':
          outputDir = args[++i];
        case '--conformance-package':
          conformancePackage = args[++i];
        case '--timeout-seconds':
          timeout = Duration(seconds: int.parse(args[++i]));
        case '--help':
        case '-h':
          help = true;
        default:
          throw ArgumentError('Unknown argument: ${args[i]}');
      }
    }

    return _Options(
      scenario: scenario,
      outputDir: outputDir,
      conformancePackage: conformancePackage,
      timeout: timeout,
      help: help,
    );
  }
}

class _RunResult {
  final int? exitCode;
  final bool timedOut;

  const _RunResult({required this.exitCode, required this.timedOut});
}
