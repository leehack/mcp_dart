import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mcp_dart_cli/src/agent_skill_command.dart';
import 'package:mcp_dart_cli/src/conformance_command.dart';
import 'package:mcp_dart_cli/src/create_command.dart';
import 'package:mcp_dart_cli/src/doctor_command.dart';
import 'package:mcp_dart_cli/src/inspect_client_command.dart';
import 'package:mcp_dart_cli/src/inspect_command.dart';
import 'package:mcp_dart_cli/src/inspect_server_command.dart';
import 'package:mcp_dart_cli/src/serve_command.dart';
import 'package:mcp_dart_cli/src/tool_commands.dart';
import 'package:mcp_dart_cli/src/trace_command.dart';
import 'package:mcp_dart_cli/src/update_command.dart';
import 'package:mcp_dart_cli/src/version.dart';
import 'package:mcp_dart_cli/src/version_check.dart';

bool shouldCheckForUpdate(List<String> arguments) {
  if (arguments.contains('update')) {
    return false;
  }

  if (arguments.isNotEmpty && arguments.first == 'inspect-client') {
    return false;
  }

  if (arguments.isNotEmpty && arguments.first == 'trace') {
    return false;
  }

  if (arguments.contains('--json')) {
    return false;
  }

  if (arguments.length >= 2 &&
      arguments.first == 'skills' &&
      arguments[1] == 'print') {
    return false;
  }

  return true;
}

void main(List<String> arguments) async {
  if (arguments.contains('--version') || arguments.contains('-v')) {
    stdout.writeln(packageVersion);
    exit(0);
  }

  final logger = Logger();
  final runner = CommandRunner<int>(
    'mcp_dart',
    'CLI for creating and managing MCP servers in Dart.',
  )
    ..addCommand(CreateCommand())
    ..addCommand(ServeCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(InspectCommand(logger: logger))
    ..addCommand(InspectServerCommand(logger: logger))
    ..addCommand(InspectClientCommand(logger: logger))
    ..addCommand(ListToolsCommand(logger: logger))
    ..addCommand(CallToolCommand(logger: logger))
    ..addCommand(TraceCommand(logger: logger))
    ..addCommand(ConformanceCommand(logger: logger))
    ..addCommand(AgentSkillsCommand(logger: logger))
    ..addCommand(UpdateCommand(logger: logger));

  try {
    final exitCode = await runner.run(arguments);
    if (shouldCheckForUpdate(arguments)) {
      await checkForUpdate(logger);
    }
    exit(exitCode ?? 0);
  } catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
