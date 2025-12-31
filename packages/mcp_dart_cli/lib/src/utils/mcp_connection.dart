import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:path/path.dart' as p;

import '../runner_script_generator.dart';

/// A wrapper around MCP Client connection lifecycle.
class McpConnection {
  final McpClient client;
  final Transport transport;

  McpConnection._(this.client, this.transport, Logger logger);

  /// Connects to a local MCP project in the current directory.
  /// Generates the runner script if needed.
  static Future<McpConnection> connectToLocalProject(
    Logger logger, {
    McpClientOptions? options,
  }) async {
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      throw 'pubspec.yaml not found in current directory.';
    }

    // simplistic package name check
    String? packageName;
    try {
      final lines = await pubspecFile.readAsLines();
      for (final line in lines) {
        if (line.trim().startsWith('name:')) {
          packageName = line.split(':')[1].trim();
          break;
        }
      }
    } catch (_) {}

    if (packageName == null) {
      throw 'Could not determine package name from pubspec.yaml.';
    }

    final dotDartToolDir = Directory(p.join('.dart_tool', 'mcp_dart'));
    if (!dotDartToolDir.existsSync()) {
      dotDartToolDir.createSync(recursive: true);
    }

    logger.detail('Generating runner script...');
    await generateRunnerScript(dotDartToolDir, packageName);
    final runnerFile = File(p.join(dotDartToolDir.path, 'runner.dart'));

    return connectToCommand(
      logger,
      'dart',
      ['run', runnerFile.path],
      options: options,
    );
  }

  /// Connects to an external MCP server command.
  static Future<McpConnection> connectToCommand(
    Logger logger,
    String command,
    List<String> args, {
    Map<String, String>? env,
    McpClientOptions? options,
  }) async {
    logger.detail('Connecting to server: $command ${args.join(' ')}');

    final serverParams = StdioServerParameters(
      command: command,
      args: args,
      environment: env,
      stderrMode: ProcessStartMode.normal,
    );

    final transport = StdioClientTransport(serverParams);
    final client = McpClient(
      Implementation(name: 'mcp_dart_cli', version: '1.0.0'),
      options: options,
    );

    await client.connect(transport);

    // Pipe stderr
    transport.stderr?.transform(utf8.decoder).listen((line) {
      logger.detail('[Server Stderr] $line');
    });

    return McpConnection._(client, transport, logger);
  }

  /// Connects to an external MCP server via URL (Streamable HTTP).
  static Future<McpConnection> connectToUrl(
    Logger logger,
    Uri url, {
    McpClientOptions? options,
  }) async {
    logger.detail('Connecting to server: $url');

    final transport = StreamableHttpClientTransport(url);
    final client = McpClient(
      Implementation(name: 'mcp_dart_cli', version: '1.0.0'),
      options: options,
    );

    await client.connect(transport);

    return McpConnection._(client, transport, logger);
  }

  Future<void> close() async {
    await client.close();
    // transport is closed by client.close() usually, but safe to verify or just let it be.
  }
}
