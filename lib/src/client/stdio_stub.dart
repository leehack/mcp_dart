import 'dart:async';

import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

Never _unsupported() => throw UnsupportedError(
      'StdioClientTransport is only available on Dart IO platforms.',
    );

/// Configuration parameters for launching a stdio server process.
///
/// This web/default-platform stub preserves the public API shape without
/// importing `dart:io`. The real implementation is selected on Dart IO
/// platforms through the package barrel's conditional export.
class StdioServerParameters {
  /// The executable command to run to start the server process.
  final String command;

  /// Command line arguments to pass to the executable.
  final List<String> args;

  /// Environment variables to use when spawning the process.
  final Map<String, String>? environment;

  /// How to handle the stderr stream of the child process on IO platforms.
  final Object? stderrMode;

  /// The working directory to use when spawning the process.
  final String? workingDirectory;

  /// Creates parameters for launching the stdio server.
  const StdioServerParameters({
    required this.command,
    this.args = const [],
    this.environment,
    this.stderrMode,
    this.workingDirectory,
  });
}

/// Stub for the stdio client transport on platforms without `dart:io`.
class StdioClientTransport implements Transport {
  /// Creates a stdio client transport stub.
  StdioClientTransport(this.serverParams);

  /// Configuration for launching the server process.
  final StdioServerParameters serverParams;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => null;

  /// Stderr is unavailable without a spawned process.
  Stream<List<int>>? get stderr => null;

  @override
  Future<void> start() async => _unsupported();

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async =>
      _unsupported();
}
