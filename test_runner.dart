#!/usr/bin/env dart

import 'dart:io';

/// Comprehensive test runner for MCP Dart library
/// Runs both VM and web tests, ensuring full platform coverage
void main(List<String> args) async {
  print('🧪 MCP Dart Comprehensive Test Runner');
  print('=====================================\n');

  var exitCode = 0;
  final stopwatch = Stopwatch()..start();

  // Parse arguments
  final verbose = args.contains('--verbose') || args.contains('-v');
  final webOnly = args.contains('--web-only');
  final vmOnly = args.contains('--vm-only');

  try {
    if (!vmOnly) {
      print('🌐 Running Web Tests (Chrome)...');
      exitCode = await _runWebTests(verbose);
      if (exitCode != 0) {
        print('❌ Web tests failed!');
        exit(exitCode);
      }
      print('✅ Web tests passed!\n');
    }

    if (!webOnly) {
      print('🖥️  Running VM Tests...');
      exitCode = await _runVmTests(verbose);
      if (exitCode != 0) {
        print('❌ VM tests failed!');
        exit(exitCode);
      }
      print('✅ VM tests passed!\n');
    }

    stopwatch.stop();
    print('🎉 All tests passed! Total time: ${stopwatch.elapsed.inSeconds}s');
  } catch (e) {
    print('💥 Test runner error: $e');
    exit(1);
  }
}

Future<int> _runWebTests(bool verbose) async {
  final args = [
    'test',
    'test/web/',
    '-p',
    'chrome',
  ];

  if (verbose) {
    args.add('--reporter=expanded');
  }

  final result = await Process.run('dart', args);

  if (verbose || result.exitCode != 0) {
    print(result.stdout);
    if (result.stderr.isNotEmpty) {
      print(result.stderr);
    }
  }

  return result.exitCode;
}

Future<int> _runVmTests(bool verbose) async {
  final args = [
    'test',
    '--exclude-tags=web-only',
  ];

  if (verbose) {
    args.add('--reporter=expanded');
  }

  final result = await Process.run('dart', args);

  if (verbose || result.exitCode != 0) {
    print(result.stdout);
    if (result.stderr.isNotEmpty) {
      print(result.stderr);
    }
  }

  return result.exitCode;
}
