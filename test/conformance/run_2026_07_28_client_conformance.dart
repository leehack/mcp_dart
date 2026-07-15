import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'conformance_scenario_inventory.dart';

const _defaultConformancePackage =
    '@modelcontextprotocol/conformance@0.2.0-alpha.9';
const _defaultTimeout = Duration(seconds: 30);
const _draftSpecVersion = '2026-07-28';
const _stableFixtureSpecVersion = '2025-11-25';

// alpha.9's network-ref canary server has not adopted the draft protocol yet.
// The security requirement is protocol-version independent, so run that exact
// official canary against its newest supported fixture version. A local MCP
// 2026-07-28 regression separately verifies that the draft Tool wire shape is
// preserved.
const _scenarioSpecVersionOverrides = {
  'json-schema-ref-no-deref': _stableFixtureSpecVersion,
};

const _draftClientScenarios = [
  'tools_call',
  'request-metadata',
  'auth/metadata-default',
  'auth/metadata-var1',
  'auth/metadata-var2',
  'auth/metadata-var3',
  'auth/basic-cimd',
  'auth/scope-from-www-authenticate',
  'auth/scope-from-scopes-supported',
  'auth/scope-omitted-when-undefined',
  'auth/scope-step-up',
  'auth/scope-retry-limit',
  'auth/token-endpoint-auth-basic',
  'auth/token-endpoint-auth-post',
  'auth/token-endpoint-auth-none',
  'auth/pre-registration',
  'auth/resource-mismatch',
  'auth/offline-access-scope',
  'auth/offline-access-not-supported',
  'auth/authorization-server-migration',
  'auth/iss-supported',
  'auth/iss-not-advertised',
  'auth/iss-supported-missing',
  'auth/iss-wrong-issuer',
  'auth/iss-unexpected',
  'auth/iss-normalized',
  'auth/metadata-issuer-mismatch',
  'sep-2322-client-request-state',
  'http-standard-headers',
  'http-custom-headers',
  'http-invalid-tool-headers',
  'json-schema-ref-no-deref',
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
      options.scenario == null ? _draftClientScenarios : [options.scenario!];

  await verifyConformanceScenarioInventory(
    conformancePackage: options.conformancePackage,
    role: 'client',
    specVersion: _draftSpecVersion,
    expectedScenarios: scenarios,
    requireExactMatch: options.scenario == null,
  );

  stdout.writeln('Conformance package: ${options.conformancePackage}');
  stdout.writeln('Output: ${outputRoot.path}');
  stdout.writeln('');

  final results = <_ScenarioResult>[];
  for (final scenario in scenarios) {
    final result = await _runScenario(
      scenario: scenario,
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
        (result) => result.passed && expectedFailures.contains(result.scenario),
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
          '.dart_tool/conformance/2026_07_28_client/'
          '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}',
        )
      : Directory(outputDir);
  await root.create(recursive: true);
  return root;
}

Future<_ScenarioResult> _runScenario({
  required String scenario,
  required Directory outputRoot,
  required String conformancePackage,
  required Duration timeout,
}) async {
  final outputDir = Directory('${outputRoot.path}/${_sanitize(scenario)}');
  await outputDir.create(recursive: true);
  final specVersion =
      _scenarioSpecVersionOverrides[scenario] ?? _draftSpecVersion;

  final process = await Process.start(
    'npx',
    [
      '-y',
      conformancePackage,
      'client',
      '--command',
      'dart run test/conformance/mcp_2026_07_28_client.dart',
      '--scenario',
      scenario,
      '--spec-version',
      specVersion,
      if (specVersion != _draftSpecVersion) '--force',
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
      specVersion: specVersion,
      exitCode: code,
      timedOut: false,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await Future.wait([
      stdoutDone.catchError((_) {}),
      stderrDone.catchError((_) {}),
    ]);
    return _ScenarioResult(
      scenario: scenario,
      specVersion: specVersion,
      exitCode: null,
      timedOut: true,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }
}

String _sanitize(String scenario) {
  return scenario.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
}

void _printScenarioResult(
  _ScenarioResult result,
  Set<String> expectedFailures,
) {
  final expected = expectedFailures.contains(result.scenario);
  final label = result.passed
      ? expected
          ? 'UNEXPECTED PASS'
          : 'PASS'
      : expected
          ? 'EXPECTED FAIL'
          : 'FAIL';
  final versionSuffix = result.specVersion == _draftSpecVersion
      ? ''
      : ' (fixture protocol ${result.specVersion})';
  stdout.writeln('${label.padRight(18)} ${result.scenario}$versionSuffix');
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
          'specVersion': result.specVersion,
          'status': result.status,
          'exitCode': result.exitCode,
          'timedOut': result.timedOut,
        },
    ],
  };
  await File('${outputRoot.path}/summary.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
  );
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run test/conformance/run_2026_07_28_client_conformance.dart [options]

Options:
  --scenario <name>              Run one scenario instead of the full draft list.
  --expected-failures <path>     Expected-failure list.
  --output-dir <path>            Directory for conformance artifacts.
  --conformance-package <pkg>    Conformance npm package.
  --timeout-seconds <seconds>    Per-scenario timeout.
  --help                         Show this help.
''');
}

class _ScenarioResult {
  final String scenario;
  final String specVersion;
  final int? exitCode;
  final bool timedOut;
  final String stdout;
  final String stderr;

  const _ScenarioResult({
    required this.scenario,
    required this.specVersion,
    required this.exitCode,
    required this.timedOut,
    required this.stdout,
    required this.stderr,
  });

  bool get passed => !timedOut && exitCode == 0;
  String get status => timedOut ? 'timeout' : 'exit ${exitCode ?? 'unknown'}';
}

class _Options {
  final String? scenario;
  final String expectedFailuresPath;
  final String? outputDir;
  final String conformancePackage;
  final Duration timeout;
  final bool help;

  const _Options({
    required this.scenario,
    required this.expectedFailuresPath,
    required this.outputDir,
    required this.conformancePackage,
    required this.timeout,
    required this.help,
  });

  static _Options parse(List<String> args) {
    String? scenario;
    var expectedFailuresPath =
        'test/conformance/2026_07_28_client_expected_failures.txt';
    String? outputDir;
    var conformancePackage = _defaultConformancePackage;
    var timeout = _defaultTimeout;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--scenario':
          if (i + 1 < args.length) {
            scenario = args[++i];
          }
        case '--expected-failures':
          if (i + 1 < args.length) {
            expectedFailuresPath = args[++i];
          }
        case '--output-dir':
          if (i + 1 < args.length) {
            outputDir = args[++i];
          }
        case '--conformance-package':
          if (i + 1 < args.length) {
            conformancePackage = args[++i];
          }
        case '--timeout-seconds':
          if (i + 1 < args.length) {
            final seconds = int.tryParse(args[++i]);
            if (seconds != null) {
              timeout = Duration(seconds: seconds);
            }
          }
        case '--help':
        case '-h':
          help = true;
      }
    }

    return _Options(
      scenario: scenario,
      expectedFailuresPath: expectedFailuresPath,
      outputDir: outputDir,
      conformancePackage: conformancePackage,
      timeout: timeout,
      help: help,
    );
  }
}
