/// Stub implementation of stdio client transport for web platform.
///
/// Standard I/O transport is not available in web browsers. This stub provides
/// the same API surface but throws appropriate errors when used.
library;

import '../shared/transport.dart';
import '../types.dart';

/// Parameters for configuring a stdio-based MCP server connection.
///
/// This class is not available on web platforms as stdio is not supported
/// in browser environments.
class StdioServerParameters {
  /// Stub constructor that throws on web platforms.
  StdioServerParameters({
    required String command,
    List<String>? args,
    Map<String, String>? environment,
    String? workingDirectory,
    dynamic stderrMode,
  }) {
    throw UnsupportedError(
      'StdioServerParameters is not supported on web platforms. '
      'Use StreamableHttpClientTransport for web compatibility.',
    );
  }
}

/// Stdio-based transport for MCP client communication.
///
/// This transport is not available on web platforms as stdio is not supported
/// in browser environments.
class StdioClientTransport extends Transport {
  /// Stub constructor that throws on web platforms.
  StdioClientTransport(StdioServerParameters serverParams) {
    throw UnsupportedError(
      'StdioClientTransport is not supported on web platforms. '
      'Use StreamableHttpClientTransport for web compatibility.',
    );
  }

  @override
  String? get sessionId => throw UnsupportedError(
        'StdioClientTransport is not supported on web platforms.',
      );

  @override
  Future<void> start() => throw UnsupportedError(
        'StdioClientTransport is not supported on web platforms.',
      );

  @override
  Future<void> send(JsonRpcMessage message) => throw UnsupportedError(
        'StdioClientTransport is not supported on web platforms.',
      );

  @override
  Future<void> close() => throw UnsupportedError(
        'StdioClientTransport is not supported on web platforms.',
      );

  /// Stderr stream getter (not supported on web)
  Stream<List<int>>? get stderr => throw UnsupportedError(
        'StdioClientTransport.stderr is not supported on web platforms.',
      );
}
