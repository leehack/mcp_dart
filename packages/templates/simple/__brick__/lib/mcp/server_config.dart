import 'dart:io';

import 'package:args/args.dart';

/// Supported transport types for the MCP server.
enum TransportType {
  stdio,
  http,
}

/// Configuration for the MCP Server.
class ServerConfig {
  ServerConfig({
    required this.transport,
    required this.host,
    required this.port,
    required this.path,
    required this.verbose,
    required this.help,
  });

  /// Parses command line arguments into a [ServerConfig].
  ///
  /// Throws [FormatException] if arguments are invalid.
  factory ServerConfig.fromArgs(List<String> args) {
    final parser = _buildParser();
    final results = parser.parse(args);

    if (results.flag('help')) {
      return ServerConfig(
        transport: TransportType.stdio, // Default dummy
        host: '',
        port: 0,
        path: '',
        verbose: false,
        help: true,
      );
    }

    final transportStr = results.option('transport');
    final transport = TransportType.values.firstWhere(
      (e) => e.name == transportStr,
      orElse: () =>
          throw FormatException('Unknown transport type: $transportStr'),
    );

    final host = results.option('host')!;
    final portStr = results.option('port')!;
    final port = int.tryParse(portStr);
    if (port == null) {
      throw FormatException('Port must be a valid integer: $portStr');
    }

    if (port < 0 || port > 65535) {
      throw FormatException('Port must be between 0 and 65535');
    }

    return ServerConfig(
      transport: transport,
      host: host,
      port: port,
      path: results.option('path')!,
      verbose: results.flag('verbose'),
      help: false,
    );
  }

  final TransportType transport;
  final String host;
  final int port;
  final String path;
  final bool verbose;
  final bool help;

  static ArgParser _buildParser() {
    return ArgParser()
      ..addOption(
        'transport',
        abbr: 't',
        help: 'Transport type to use.',
        allowed: TransportType.values.map((e) => e.name).toList(),
        defaultsTo: TransportType.stdio.name,
      )
      ..addOption(
        'host',
        abbr: 'h',
        help: 'Host to bind for HTTP transport.',
        defaultsTo: '0.0.0.0',
      )
      ..addOption(
        'port',
        abbr: 'p',
        help: 'Port to bind for HTTP transport.',
        defaultsTo: '3000',
      )
      ..addOption(
        'path',
        help: 'Endpoint path for HTTP transport.',
        defaultsTo: '/mcp',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose logging.',
        negatable: false,
      )
      ..addFlag(
        'help',
        help: 'Show this help message.',
        negatable: false,
      );
  }

  /// Prints the usage information to stderr.
  static void printUsage() {
    final parser = _buildParser();
    stderr
      ..writeln('MCP Server')
      ..writeln()
      ..writeln('Usage: dart run bin/server.dart [options]')
      ..writeln()
      ..writeln('Options:')
      ..writeln(parser.usage)
      ..writeln()
      ..writeln('Examples:')
      ..writeln(
        '  dart run bin/server.dart                          # stdio transport',
      )
      ..writeln(
        '  dart run bin/server.dart -t http                  # HTTP on 0.0.0.0:3000',
      )
      ..writeln(
        '  dart run bin/server.dart -t http -p 8080          # HTTP on port 8080',
      )
      ..writeln(
        '  dart run bin/server.dart -t http -h localhost     # HTTP on localhost only',
      );
  }
}
