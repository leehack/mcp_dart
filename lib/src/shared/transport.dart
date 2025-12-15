import 'package:mcp_dart/src/types.dart';

/// Describes the minimal contract for a MCP transport that a client or server
/// can communicate over.
abstract class Transport {
  /// Starts processing messages on the transport, including any connection steps
  /// that might need to be taken.
  Future<void> start();

  /// Sends a JSON-RPC message (request, response, or notification).
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId});

  /// Closes the connection.
  Future<void> close();

  /// Callback for when the connection is closed for any reason.
  void Function()? onclose;

  /// Callback for when an error occurs.
  void Function(Error error)? onerror;

  /// Callback for when a message (request, response, or notification) is received.
  void Function(JsonRpcMessage message)? onmessage;

  /// The session ID generated for this connection, if applicable.
  String? get sessionId;
}
