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

/// Optional capability for transports that can preserve JSON-RPC request IDs
/// with their full MCP shape (string or integer) for request/stream correlation.
///
/// Existing custom transports can keep implementing [Transport.send] with
/// `int? relatedRequestId`. Transports that need to route messages by string
/// request IDs should also implement this interface.
abstract class RequestIdAwareTransport {
  /// Sends a JSON-RPC message while preserving a string-or-integer request ID.
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  });
}

extension RequestIdAwareTransportSend on Transport {
  /// Sends [message] while preserving string request IDs when the transport
  /// supports [RequestIdAwareTransport].
  ///
  /// Legacy transports receive only integer IDs, matching the existing public
  /// [Transport.send] contract and keeping custom implementations source-compatible.
  Future<void> sendPreservingRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) {
    final transport = this;
    if (transport is RequestIdAwareTransport) {
      return (transport as RequestIdAwareTransport).sendWithRequestId(
        message,
        relatedRequestId: relatedRequestId,
      );
    }

    return send(
      message,
      relatedRequestId: relatedRequestId is int ? relatedRequestId : null,
    );
  }
}

/// Optional capability for transports that can attach MCP protocol version
/// headers to outbound requests.
abstract class ProtocolVersionAwareTransport {
  /// Currently negotiated MCP protocol version for this transport.
  String? get protocolVersion;

  /// Updates the negotiated MCP protocol version.
  set protocolVersion(String? value);
}
