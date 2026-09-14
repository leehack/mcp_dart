import 'dart:io';

import 'package:test/test.dart';

import '../../tool/testing/smoke_programs.dart';

void main() {
  test('resolves nested CLI server arguments without mutating input', () {
    const arguments = [
      'run',
      'packages/mcp_dart_cli/bin/mcp_dart.dart',
      'inspect',
      'dart',
      'run',
      'example/mcp_apps_helpers_server.dart',
    ];
    final compiled = Platform.environment['MCP_PRECOMPILED_SMOKE'] == '1';
    expect(
      smokeArguments(arguments),
      compiled
          ? [
              '.dart_tool/smoke/packages/mcp_dart_cli/bin/mcp_dart.dart.dill',
              'inspect',
              'dart',
              '.dart_tool/smoke/example/mcp_apps_helpers_server.dart.dill',
            ]
          : arguments,
    );
    expect(arguments.first, 'run');
  });

  test('preserves unrelated arguments and a trailing run', () {
    const arguments = ['--flag', 'run', 'unknown.dart', 'run'];
    expect(smokeArguments(arguments), arguments);
  });

  test('rejects unknown programs only in precompiled mode', () {
    if (Platform.environment['MCP_PRECOMPILED_SMOKE'] == '1') {
      expect(() => smokeProgram('unknown.dart'), throwsArgumentError);
    } else {
      expect(smokeProgram('unknown.dart'), 'unknown.dart');
    }
  });
}
