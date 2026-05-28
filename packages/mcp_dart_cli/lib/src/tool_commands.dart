import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import 'utils/inspect_handlers.dart';
import 'utils/inspect_printer.dart';
import 'utils/mcp_connection.dart';

/// Lists tools from an MCP server.
class ListToolsCommand extends _ToolCommand {
  /// Creates a command that lists MCP tools.
  ListToolsCommand({super.logger});

  @override
  final name = 'list-tools';

  @override
  final description = 'Lists tools advertised by an MCP server.';

  @override
  String get invocation =>
      'mcp_dart list-tools [options] [-- <server-command> ...]';

  @override
  Future<int> run() async {
    final jsonOutput = argResults?['json'] as bool? ?? false;
    final target = _parseConnectionTarget(argResults?.rest ?? const []);
    if (target == null) return ExitCode.usage.code;

    McpConnection? connection;
    try {
      connection = await _connect(target);
      registerHandlers(connection.client);

      final capabilities = connection.client.getServerCapabilities();
      if (capabilities?.tools == null) {
        if (jsonOutput) {
          _writeJson(const ListToolsResult(tools: []).toJson());
        } else {
          logger.info('Server does not advertise the tools capability.');
        }
        return ExitCode.success.code;
      }

      final result = await connection.client.listTools();
      if (jsonOutput) {
        _writeJson(result.toJson());
      } else {
        _printTools(result);
      }

      await _waitForNotifications(target);
      return ExitCode.success.code;
    } catch (error) {
      logger.err('list-tools failed: $error');
      return ExitCode.software.code;
    } finally {
      await connection?.close();
    }
  }

  void _printTools(ListToolsResult result) {
    if (result.tools.isEmpty) {
      logger.info('Tools: (None)');
      return;
    }

    logger.info('Tools:');
    for (final tool in result.tools) {
      logger
          .info('  - ${tool.name}: ${tool.description ?? "(no description)"}');
    }
  }
}

/// Calls a tool on an MCP server.
class CallToolCommand extends _ToolCommand {
  /// Creates a command that calls an MCP tool.
  CallToolCommand({super.logger}) {
    argParser.addOption(
      'json-args',
      help: 'JSON object arguments for the tool call.',
    );
  }

  @override
  final name = 'call-tool';

  @override
  final description = 'Calls a tool advertised by an MCP server.';

  @override
  String get invocation =>
      'mcp_dart call-tool <tool-name> [options] [-- <server-command> ...]';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final toolName = rest.isEmpty ? null : rest.first;
    if (toolName == null || toolName.isEmpty) {
      logger.err('Missing required tool name.');
      logger.info(usage);
      return ExitCode.usage.code;
    }

    final itemArgs = _parseJsonArgs(argResults?['json-args'] as String?);
    if (itemArgs == null) return ExitCode.usage.code;

    final target = _parseConnectionTarget(rest.sublist(1));
    if (target == null) return ExitCode.usage.code;

    final jsonOutput = argResults?['json'] as bool? ?? false;
    McpConnection? connection;
    try {
      connection = await _connect(target);
      registerHandlers(connection.client);

      final capabilities = connection.client.getServerCapabilities();
      if (capabilities?.tools == null) {
        logger.err('Server does not advertise the tools capability.');
        return ExitCode.software.code;
      }

      final result = await connection.client.callTool(
        CallToolRequest(name: toolName, arguments: itemArgs),
      );
      if (jsonOutput) {
        _writeJson(result.toJson());
      } else {
        printer.printToolResult(result);
      }

      await _waitForNotifications(target);
      return result.isError ? ExitCode.software.code : ExitCode.success.code;
    } catch (error) {
      logger.err('call-tool failed: $error');
      return ExitCode.software.code;
    } finally {
      await connection?.close();
    }
  }
}

abstract class _ToolCommand extends Command<int> {
  _ToolCommand({Logger? logger}) : logger = logger ?? Logger() {
    printer = InspectPrinter(this.logger);
    _handlers = InspectHandlers(this.logger);
    _addConnectionOptions();
  }

  final Logger logger;
  late final InspectPrinter printer;
  late final InspectHandlers _handlers;

  void registerHandlers(McpClient client) {
    _handlers.registerHandlers(client);
  }

  void _addConnectionOptions() {
    argParser
      ..addOption(
        'url',
        help: 'The MCP Streamable HTTP endpoint to connect to.',
      )
      ..addOption(
        'command',
        abbr: 'c',
        help:
            'The executable command to start the MCP server. If omitted, the command uses the current Dart project.',
      )
      ..addMultiOption(
        'server-args',
        abbr: 'a',
        help: 'Arguments to pass to the server command.',
      )
      ..addMultiOption(
        'env',
        help: 'Environment variables for the server in KEY=VALUE format.',
      )
      ..addOption(
        'wait',
        abbr: 'w',
        help:
            'Milliseconds to wait for notifications after the command completes. Defaults to 500ms for HTTP.',
      )
      ..addFlag(
        'json',
        help: 'Print machine-readable JSON to stdout.',
        negatable: false,
      );
  }

  _ConnectionTarget? _parseConnectionTarget(List<String> rest) {
    final url = argResults?['url'] as String?;
    String? command = argResults?['command'] as String?;
    var serverArgs = argResults?['server-args'] as List<String>? ?? const [];

    if (url != null && command != null) {
      logger.err('Cannot specify both --url and --command.');
      return null;
    }
    if (url != null && rest.isNotEmpty) {
      logger.err('Cannot specify positional server arguments with --url.');
      return null;
    }

    if (rest.isNotEmpty) {
      if (command == null) {
        command = rest.first;
        serverArgs = rest.sublist(1);
      } else {
        serverArgs = [...serverArgs, ...rest];
      }
    }

    final wait = _parseWait(url);
    if (wait == null) return null;

    final env = _parseEnvArgs(argResults);
    if (env == null) return null;

    return _ConnectionTarget(
      command: command,
      serverArgs: serverArgs,
      url: url == null ? null : Uri.parse(url),
      env: env,
      wait: wait,
    );
  }

  Map<String, String>? _parseEnvArgs(ArgResults? results) {
    final envList = results?['env'] as List<String>? ?? const [];
    final env = <String, String>{};
    for (final entry in envList) {
      final separator = entry.indexOf('=');
      if (separator <= 0) {
        logger.err('--env values must use KEY=VALUE syntax.');
        return null;
      }
      env[entry.substring(0, separator)] = entry.substring(separator + 1);
    }
    return env;
  }

  int? _parseWait(String? url) {
    final waitValue = argResults?['wait'] as String?;
    if (waitValue == null) {
      return url == null ? 0 : 500;
    }

    final wait = int.tryParse(waitValue);
    if (wait == null || wait < 0) {
      logger.err('--wait must be a non-negative integer.');
      return null;
    }
    return wait;
  }

  Map<String, dynamic>? _parseJsonArgs(String? jsonArgs) {
    if (jsonArgs == null) return {};

    try {
      final decoded = jsonDecode(jsonArgs);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      logger.err('--json-args must decode to a JSON object.');
      return null;
    } catch (error) {
      logger.err('Error parsing --json-args: $error');
      return null;
    }
  }

  Future<McpConnection> _connect(_ConnectionTarget target) {
    final clientOptions = McpClientOptions(
      capabilities: const ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
      ),
    );

    if (target.command != null) {
      return McpConnection.connectToCommand(
        logger,
        target.command!,
        target.serverArgs,
        env: target.env,
        options: clientOptions,
      );
    }

    if (target.url != null) {
      return McpConnection.connectToUrl(
        logger,
        target.url!,
        options: clientOptions,
      );
    }

    if (target.serverArgs.isNotEmpty || target.env.isNotEmpty) {
      logger.info(
        'Using local project. --server-args and --env are ignored for local project runner.',
      );
    }
    return McpConnection.connectToLocalProject(logger, options: clientOptions);
  }

  Future<void> _waitForNotifications(_ConnectionTarget target) async {
    if (target.wait > 0) {
      logger.detail('Waiting ${target.wait}ms for notifications...');
      await Future.delayed(Duration(milliseconds: target.wait));
    }
  }

  void _writeJson(Map<String, dynamic> value) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
  }
}

class _ConnectionTarget {
  const _ConnectionTarget({
    required this.command,
    required this.serverArgs,
    required this.url,
    required this.env,
    required this.wait,
  });

  final String? command;
  final List<String> serverArgs;
  final Uri? url;
  final Map<String, String> env;
  final int wait;
}
