import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('reports usage errors on stderr with a nonzero exit code', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/main.dart',
    ]);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Usage:'));
  });

  test(
    'reports missing credentials on stderr with a nonzero exit code',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/main.dart', 'unused-command'],
        environment: {...Platform.environment, 'GEMINI_API_KEY': ''},
      );

      expect(result.exitCode, 78);
      expect(result.stderr, contains('GEMINI_API_KEY'));
    },
  );

  test('reports MCP server launch failures with a nonzero exit code', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/main.dart', 'missing-gemini-mcp-server-command'],
      environment: {...Platform.environment, 'GEMINI_API_KEY': 'unused'},
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Gemini MCP client failed'));
  });

  test('isolates Gemini configuration and drains MCP child stderr', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mcp-dart-gemini-env-',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final probeFile = File('${tempDirectory.path}/environment.json');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/main.dart',
        Platform.resolvedExecutable,
        'run',
        'test/fixtures/env_probe_server.dart',
        probeFile.path,
      ],
      environment: {
        ...Platform.environment,
        'GEMINI_API_KEY': 'must-not-reach-server',
        'gemini_api_key': 'must-not-reach-server-either',
        'GEMINI_MODEL': 'must-not-reach-server',
        'GeMiNi_MoDeL': 'must-not-reach-server-either',
        'GEMINI_ENV_PROBE_MARKER': 'preserved',
      },
    );
    addTearDown(process.kill);
    final stdoutText = process.stdout.transform(utf8.decoder).join();
    final stderrText = process.stderr.transform(utf8.decoder).join();
    process.stdin.writeln('quit');
    await process.stdin.close();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 20),
    );
    final stdoutOutput = await stdoutText;
    final stderrOutput = await stderrText;

    expect(
      exitCode,
      0,
      reason: 'stdout:\n$stdoutOutput\nstderr:\n$stderrOutput',
    );
    final probe =
        (jsonDecode(await probeFile.readAsString()) as Map)
            .cast<String, Object?>();
    expect(probe, {
      'hasGeminiApiKey': false,
      'hasGeminiModel': false,
      'marker': 'preserved',
    });
  });
}
