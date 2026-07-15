import 'package:mcp_dart/src/types.dart';

/// Error thrown when a stateful transport learns that its current session no
/// longer exists on the peer.
class StaleSessionError extends Error {
  /// HTTP status code or equivalent transport status, when available.
  final int? code;

  /// Session ID that was rejected by the peer, when known.
  final String? sessionId;

  /// Human-readable stale-session reason.
  final String message;

  StaleSessionError(this.message, {this.code, this.sessionId});

  @override
  String toString() => 'Stale session: $message';
}

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
/// with their full MCP shape (string or integer) for request/stream
/// correlation.
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

/// Optional capability for transports that cancel an individual outgoing
/// request through transport-specific means.
///
/// MCP 2026-07-28 Streamable HTTP uses this capability to close the matching
/// POST response stream instead of sending `notifications/cancelled`. Other
/// transports can omit it and retain protocol-level cancellation messages.
abstract class RequestCancellationAwareTransport {
  /// Whether [requestId] currently identifies an active, cancellable outgoing
  /// request.
  ///
  /// Returning false means the request is no longer active on this transport.
  /// Callers must not substitute legacy protocol-level cancellation for
  /// stateless MCP profiles.
  bool canCancelRequest(RequestId requestId);

  /// Cancels only the outgoing request identified by [requestId].
  Future<void> cancelRequest(RequestId requestId);
}

/// Optional capability for request-scoped SSE streams that can be closed and
/// later resumed from an event store.
abstract class RequestSseStreamControlAwareTransport {
  /// Whether the SSE stream for [requestId] can be closed without losing its
  /// eventual response.
  bool canCloseRequestSseStream(RequestId requestId);

  /// Closes the current SSE response stream for [requestId].
  ///
  /// The request remains active and its eventual response must be available to
  /// a client that reconnects with the last SSE event ID.
  void closeRequestSseStream(RequestId requestId);
}

extension RequestIdAwareTransportSend on Transport {
  /// Sends [message] while preserving non-integer request IDs when the transport
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

/// Maps tool names to argument selectors and their `Mcp-Param-*` header suffixes.
///
/// Top-level arguments use their argument name as the selector. Nested
/// arguments use JSON Pointer selectors such as `/auth/tenant`.
typedef ToolParameterHeaderMappings = Map<String, Map<String, String>>;

/// Optional capability for transports that can mirror tool arguments into
/// stateless HTTP headers.
abstract class ToolParameterHeaderAwareTransport {
  /// Updates the currently advertised tool parameter header mappings.
  void setToolParameterHeaderMappings(
    ToolParameterHeaderMappings mappings,
  );
}

/// Optional capability for transports that can validate incoming requests
/// before committing transport-level response details.
abstract class IncomingRequestValidationAwareTransport {
  /// Supplies the protocol-level request validator.
  void setIncomingRequestValidator(
    McpError? Function(JsonRpcRequest request) validator,
  );

  /// Supplies a live request-method support predicate.
  void setRequestMethodSupported(bool Function(String method) isSupported);
}
