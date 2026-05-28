import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('non-credentialed examples smoke tests', () {
    test('stdio client drives stdio server tools resources and prompts',
        () async {
      final result = await _runDart(['run', 'example/client_stdio.dart']);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Connected to server.'));
      expect(result.output, contains('Result: 15'));
      expect(result.output, contains('Sample log content'));
      expect(result.output, contains('Prompt result:'));
    });

    test('iostream example connects in process', () async {
      final result = await _runDart([
        'run',
        'example/iostream-client-server/simple.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Client setup complete.'));
      expect(result.output, contains('Available tools: (calculate)'));
    });

    test('required fields demo preserves schemas', () async {
      final result = await _runDart([
        'run',
        'example/required_fields_demo.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Required parameters: [operation, a, b]'));
      expect(result.output, contains('MCP server integration works!'));
    });

    test('CLI inspect invokes completions demo over stdio', () async {
      final result = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        '--tool',
        'echo',
        '--json-args',
        '{"message":"smoke"}',
        Platform.resolvedExecutable,
        'run',
        'example/completions_capability_demo.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Connected to server!'));
      expect(result.output, contains('Echo: smoke'));
    });

    test('CLI inspect lists MCP Apps metadata server capabilities', () async {
      final result = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        Platform.resolvedExecutable,
        'run',
        'example/mcp_apps_metadata_server.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('weather_get_current'));
      expect(result.output, contains('ui://weather/dashboard'));
      expect(result.output, contains('Prompts: (None)'));
      expect(result.output, isNot(contains('Failed to list capabilities')));
    });

    test('CLI inspect invokes MCP Apps helper server tool and resource',
        () async {
      final toolResult = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        '--tool',
        'weather_get_current',
        '--json-args',
        '{"location":"Seoul"}',
        Platform.resolvedExecutable,
        'run',
        'example/mcp_apps_helpers_server.dart',
      ]);

      expect(toolResult.exitCode, 0, reason: toolResult.output);
      expect(toolResult.output, contains('Current weather for Seoul'));
      expect(toolResult.output, contains('ui://weather/dashboard.html'));

      final resourceResult = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        '--resource',
        'ui://weather/dashboard.html',
        Platform.resolvedExecutable,
        'run',
        'example/mcp_apps_helpers_server.dart',
      ]);

      expect(resourceResult.exitCode, 0, reason: resourceResult.output);
      expect(resourceResult.output, contains('MCP APP RESOURCE'));
      expect(resourceResult.output, contains('ui://weather/dashboard.html'));
    });
  });
}

Future<_CommandResult> _runDart(List<String> args) {
  return _runCommand(
    Platform.resolvedExecutable,
    args,
    timeout: const Duration(seconds: 30),
  );
}

Future<_CommandResult> _runCommand(
  String executable,
  List<String> args, {
  required Duration timeout,
}) async {
  final process = await Process.start(executable, args);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill();
    exitCode = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (Platform.isWindows) {
          process.kill();
        } else {
          process.kill(ProcessSignal.sigkill);
        }
        return -1;
      },
    );
    return _CommandResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: '${await stderrFuture}Timed out after $timeout',
    );
  }

  return _CommandResult(
    exitCode: exitCode,
    stdout: await stdoutFuture,
    stderr: await stderrFuture,
  );
}

class _CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  String get output => [
        if (stdout.isNotEmpty) stdout,
        if (stderr.isNotEmpty) stderr,
      ].join('\n');
}
