import 'dart:io';

/// Programs compiled before platform smoke tests begin their timed execution.
const smokePrograms = [
  'example/client_stdio.dart',
  'example/server_stdio.dart',
  'example/mcp_2026_07_28/client.dart',
  'example/mcp_2026_07_28/server.dart',
  'example/streamable_https/high_level_server.dart',
  'example/streamable_https/client_streamable_https.dart',
  'example/streamable_https/server_streamable_https.dart',
  'example/simple_task_interactive_server.dart',
  'example/elicitation_http_server.dart',
  'example/server_sse.dart',
  'example/client_sse.dart',
  'example/iostream-client-server/simple.dart',
  'example/required_fields_demo.dart',
  'example/completions_capability_demo.dart',
  'example/mcp_apps_metadata_server.dart',
  'example/mcp_apps_helpers_server.dart',
  'packages/mcp_dart_cli/bin/mcp_dart.dart',
];

/// Resolves an explicitly enabled, precompiled smoke program, failing closed.
String smokeProgram(String source) {
  if (Platform.environment['MCP_PRECOMPILED_SMOKE'] != '1') return source;
  if (!smokePrograms.contains(source)) {
    throw ArgumentError.value(source, 'source', 'Unknown smoke program');
  }
  final compiled = '.dart_tool/smoke/$source.dill';
  if (!File(compiled).existsSync()) {
    throw StateError('Missing $compiled; run tool/testing/compile_smoke.dart');
  }
  return compiled;
}

/// Resolves both a top-level Dart invocation and nested CLI server arguments.
List<String> smokeArguments(List<String> arguments) {
  if (Platform.environment['MCP_PRECOMPILED_SMOKE'] != '1') return arguments;
  final result = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == 'run' &&
        index + 1 < arguments.length &&
        smokePrograms.contains(arguments[index + 1])) {
      result.add(smokeProgram(arguments[++index]));
    } else {
      result.add(argument);
    }
  }
  return result;
}
