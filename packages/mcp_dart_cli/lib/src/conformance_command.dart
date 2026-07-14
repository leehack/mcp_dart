import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';

import 'conformance_runner.dart';

/// Runs MCP protocol conformance regression checks against built-in fixtures.
class ConformanceCommand extends Command<int> {
  @override
  final name = 'conformance';

  @override
  final description =
      'Runs built-in MCP conformance regression checks; not a live target inspector.';

  final Logger _logger;
  final ConformanceRunner _runner;

  ConformanceCommand({Logger? logger, ConformanceRunner? runner})
    : _logger = logger ?? Logger(),
      _runner = runner ?? ConformanceRunner() {
    argParser
      ..addOption(
        'suite',
        help: 'Conformance suite to run.',
        defaultsTo: 'fixture',
        allowed: conformanceSuiteNames,
        allowedHelp: const <String, String>{
          'fixture': 'JSON-RPC and protocol-version fixture checks.',
          'spec': 'MCP 2025-11-25 spec-critical raw-wire checks.',
          'all': 'All non-fuzz conformance checks.',
        },
      )
      ..addOption(
        'case',
        help: 'Run one built-in conformance case by exact name.',
      )
      ..addFlag(
        'fuzz',
        help: 'Run deterministic generated JSON-RPC fuzz cases.',
        negatable: false,
      )
      ..addOption(
        'iterations',
        help: 'Number of fuzz cases to generate when --fuzz is set.',
        defaultsTo: '32',
      )
      ..addFlag(
        'json',
        help: 'Print machine-readable JSON results.',
        negatable: false,
      );
  }

  @override
  Future<int> run() async {
    final suite = argResults?['suite'] as String? ?? 'fixture';
    final filter = argResults?['case'] as String?;
    final fuzz = argResults?['fuzz'] as bool? ?? false;
    final iterations = int.tryParse(argResults?['iterations'] as String? ?? '');
    final json = argResults?['json'] as bool? ?? false;

    if (iterations == null || iterations < 1) {
      _logger.err('--iterations must be a positive integer.');
      return ExitCode.usage.code;
    }
    if (fuzz && filter != null) {
      _logger.err('--case cannot be combined with --fuzz.');
      return ExitCode.usage.code;
    }
    if (fuzz && (argResults?.wasParsed('suite') ?? false)) {
      _logger.err('--suite cannot be combined with --fuzz.');
      return ExitCode.usage.code;
    }

    if (!json) {
      _logger.info(
        fuzz
            ? 'Running MCP conformance fuzz suite...'
            : 'Running MCP conformance $suite suite...',
      );
    }

    final result =
        fuzz
            ? await _runner.runFuzzSuite(iterations: iterations)
            : await _runner.runSuite(suite: suite, filter: filter);
    if (result.total == 0) {
      _logger.err('No conformance cases matched: $filter');
      return ExitCode.usage.code;
    }

    if (json) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
    } else {
      for (final testCase in result.cases) {
        final marker = testCase.passed ? '[✓]' : '[x]';
        final line = '$marker ${testCase.name} — ${testCase.description}';
        if (testCase.passed) {
          _logger.detail(line);
        } else {
          _logger.err(line);
          if (testCase.diagnostic != null) {
            _logger.err('    ${testCase.diagnostic}');
          }
        }
      }
    }

    if (result.passed) {
      if (!json) {
        _logger.success(
          'Conformance passed: ${result.passedCount}/${result.total} cases.',
        );
      }
      return ExitCode.success.code;
    }

    if (!json) {
      _logger.err(
        'Conformance failed: ${result.failedCount}/${result.total} cases failed.',
      );
    }
    return ExitCode.software.code;
  }
}
