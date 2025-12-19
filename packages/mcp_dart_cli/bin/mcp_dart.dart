import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mcp_dart_cli/src/create_command.dart';

void main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'mcp_dart',
    'CLI for creating and managing MCP servers in Dart.',
  )..addCommand(CreateCommand());

  try {
    await runner.run(arguments);
  } catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
