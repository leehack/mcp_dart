import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  final inheritedKey = arguments.single;
  stdout.writeln(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'environment/probe',
      'params': {
        'inherited': Platform.environment[inheritedKey],
        'explicit': Platform.environment['MCP_DART_EXPLICIT_SENTINEL'],
      },
    }),
  );
}
