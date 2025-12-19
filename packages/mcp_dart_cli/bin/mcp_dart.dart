import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mcp_dart_cli/src/create_command.dart';
import 'package:mcp_dart_cli/src/serve_command.dart';
import 'package:mcp_dart_cli/src/doctor_command.dart';
import 'package:mcp_dart_cli/src/inspect_command.dart';

void main(List<String> arguments) async {
  final logger = Logger();
  final runner = CommandRunner<int>(
    'mcp_dart',
    'CLI for creating and managing MCP servers in Dart.',
  )
    ..addCommand(CreateCommand())
    ..addCommand(ServeCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(InspectCommand(logger: logger));

  try {
    final exitCode = await runner.run(arguments);
    exit(exitCode ?? 0);
  } catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
