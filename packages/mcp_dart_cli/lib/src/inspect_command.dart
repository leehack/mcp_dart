import 'dart:convert';
import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import 'utils/mcp_connection.dart';
import 'utils/inspect_printer.dart';
import 'utils/inspect_handlers.dart';

/// Inspects an MCP server, listing capabilities or executing specific items.
class InspectCommand extends Command<int> {
  @override
  final name = 'inspect';

  @override
  final description =
      'Inspects an MCP server, listing capabilities or executing specific tools/resources/prompts.';

  final Logger _logger;
  late final InspectPrinter _printer;
  late final InspectHandlers _handlers;

  InspectCommand({Logger? logger}) : _logger = logger ?? Logger() {
    _printer = InspectPrinter(_logger);
    _handlers = InspectHandlers(_logger);

    argParser
      ..addOption(
        'tool',
        help: 'The name of a tool to execute.',
      )
      ..addOption(
        'url',
        help: 'The URL of the MCP server to connect to (Streamable HTTP).',
      )
      ..addOption(
        'resource',
        help: 'The URI of a resource to read.',
      )
      ..addOption(
        'prompt',
        help: 'The name of a prompt to retrieve.',
      )
      ..addOption(
        'json-args',
        help: 'JSON arguments for the tool or prompt.',
      )
      ..addOption(
        'command',
        abbr: 'c',
        help:
            'The executable command to start the MCP server (e.g. "npx", "python"). '
            'If omitted, attempts to run the local dart project.',
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
            'Milliseconds to wait for notifications after executing a tool/prompt/resource. '
            'Defaults to 500ms for HTTP connections to allow notifications to arrive.',
      );
  }

  @override
  Future<int> run() async {
    final toolName = argResults?['tool'] as String?;
    final resourceUri = argResults?['resource'] as String?;
    final promptName = argResults?['prompt'] as String?;
    final jsonArgsStr = argResults?['json-args'] as String?;
    final urlStr = argResults?['url'] as String?;
    final waitStr = argResults?['wait'] as String?;
    String? command = argResults?['command'] as String?;
    List<String> serverArgs = argResults?['server-args'] as List<String>? ?? [];

    // Handle positional arguments
    final parseResult = _parsePositionalArgs(urlStr, command, serverArgs);
    if (parseResult == null) return ExitCode.usage.code;
    command = parseResult.command;
    serverArgs = parseResult.serverArgs;

    if (urlStr != null && command != null) {
      _logger.err('Cannot specify both --url and --command.');
      return ExitCode.usage.code;
    }

    // Parse wait time - default to 500ms for HTTP connections to allow notifications to arrive
    final isHttpConnection = urlStr != null;
    final waitMs = waitStr != null
        ? int.tryParse(waitStr) ?? (isHttpConnection ? 500 : 0)
        : (isHttpConnection ? 500 : 0);

    final envMap = _parseEnvArgs();
    final itemArgs = _parseJsonArgs(jsonArgsStr);
    if (itemArgs == null) return ExitCode.usage.code;

    McpConnection? connection;
    try {
      connection = await _connect(command, urlStr, serverArgs, envMap);
      _handlers.registerHandlers(connection.client);

      _logger.success('Connected to server!');

      if (toolName != null) {
        await _executeTool(connection.client, toolName, itemArgs);
      } else if (resourceUri != null) {
        await _readResource(connection.client, resourceUri);
      } else if (promptName != null) {
        await _getPrompt(connection.client, promptName, itemArgs);
      } else {
        await _listCapabilities(connection.client);
      }

      // Wait for notifications to arrive before closing
      if (waitMs > 0) {
        _logger.detail('Waiting ${waitMs}ms for notifications...');
        await Future.delayed(Duration(milliseconds: waitMs));
      }

      return ExitCode.success.code;
    } catch (e) {
      _logger.err('Inspect error: $e');
      return ExitCode.software.code;
    } finally {
      await connection?.close();
    }
  }

  /// Parses positional arguments for command and server args.
  ({String? command, List<String> serverArgs})? _parsePositionalArgs(
    String? urlStr,
    String? command,
    List<String> serverArgs,
  ) {
    if (argResults?.rest.isNotEmpty != true) {
      return (command: command, serverArgs: serverArgs);
    }

    if (urlStr != null) {
      _logger
          .err('Cannot specify positional command arguments when using --url.');
      return null;
    }

    if (command == null) {
      command = argResults!.rest.first;
      serverArgs = argResults!.rest.sublist(1);
    } else {
      serverArgs = [...serverArgs, ...argResults!.rest];
    }

    return (command: command, serverArgs: serverArgs);
  }

  /// Parses environment variable arguments.
  Map<String, String> _parseEnvArgs() {
    final envList = argResults?['env'] as List<String>? ?? [];
    final envMap = <String, String>{};

    for (final e in envList) {
      final parts = e.split('=');
      if (parts.length >= 2) {
        envMap[parts[0]] = parts.sublist(1).join('=');
      }
    }

    return envMap;
  }

  /// Parses JSON arguments string.
  Map<String, dynamic>? _parseJsonArgs(String? jsonArgsStr) {
    if (jsonArgsStr == null) return {};

    try {
      return jsonDecode(jsonArgsStr) as Map<String, dynamic>;
    } catch (e) {
      _logger.err('Error parsing --json-args: $e');
      return null;
    }
  }

  /// Establishes connection to the MCP server.
  Future<McpConnection> _connect(
    String? command,
    String? urlStr,
    List<String> serverArgs,
    Map<String, String> envMap,
  ) async {
    final clientOptions = ClientOptions(
      capabilities: const ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
      ),
    );

    if (command != null) {
      return McpConnection.connectToCommand(
        _logger,
        command,
        serverArgs,
        env: envMap,
        options: clientOptions,
      );
    } else if (urlStr != null) {
      final uri = Uri.parse(urlStr);
      return McpConnection.connectToUrl(
        _logger,
        uri,
        options: clientOptions,
      );
    } else {
      if (serverArgs.isNotEmpty || envMap.isNotEmpty) {
        _logger.info(
            "Using local project. --server-args and --env are ignored for local project runner.");
      }
      return McpConnection.connectToLocalProject(
        _logger,
        options: clientOptions,
      );
    }
  }

  Future<void> _executeTool(
      Client client, String name, Map<String, dynamic> args) async {
    _logger.info('Executing tool: $name...');
    try {
      final result =
          await client.callTool(CallToolRequest(name: name, arguments: args));
      _printer.printToolResult(result);
    } catch (e) {
      _logger.err('Tool execution failed: $e');
    }
  }

  Future<void> _readResource(Client client, String uri) async {
    _logger.info('Reading resource: $uri...');
    try {
      final result =
          await client.readResource(ReadResourceRequestParams(uri: uri));
      _printer.printResourceResult(result);
    } catch (e) {
      _logger.err('Resource read failed: $e');
    }
  }

  Future<void> _getPrompt(
      Client client, String name, Map<String, dynamic> args) async {
    _logger.info('Getting prompt: $name...');
    try {
      final stringArgs = args.map((k, v) => MapEntry(k, v.toString()));
      final result = await client
          .getPrompt(GetPromptRequestParams(name: name, arguments: stringArgs));
      _printer.printPromptResult(result);
    } catch (e) {
      _logger.err('Get prompt failed: $e');
    }
  }

  Future<void> _listCapabilities(Client client) async {
    try {
      final tools = await client.listTools();
      final resources = await client.listResources();
      final prompts = await client.listPrompts();
      _printer.printCapabilities(tools, resources, prompts);
    } catch (e) {
      _logger.err('Failed to list capabilities: $e');
    }
  }
}
