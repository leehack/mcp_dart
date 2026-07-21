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

/// Optional capability for transports that distinguish independent incoming
/// requests which happen to reuse the same JSON-RPC request ID.
///
/// The context is an opaque, transport-owned value. It is available while an
/// incoming message is being delivered and can be retained by the protocol
/// until every response and request-scoped notification has been sent.
abstract class IncomingRequestContextAwareTransport {
  /// Context for the incoming message currently being delivered, if any.
  Object? get incomingRequestContext;

  /// Sends [message] on the HTTP exchange identified by [requestContext].
  Future<void> sendWithRequestContext(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
    required Object requestContext,
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

/// Optional capability for transports that replay active subscriptions after
/// reconnecting to a replacement peer.
///
/// A replay opens a new physical `subscriptions/listen` stream for an existing
/// logical subscription, so its first acknowledgment is valid even though the
/// high-level subscription handle has already observed the original stream's
/// acknowledgment. Implementations return `true` exactly while delivering that
/// replacement acknowledgment.
abstract interface class SubscriptionReplayAcknowledgmentTransport {
  /// Consumes the replay marker for [subscriptionId], if the currently
  /// delivered acknowledgment belongs to a replacement subscription stream.
  bool consumeSubscriptionReplayAcknowledgment(RequestId subscriptionId);
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

/// Context-aware counterpart to [RequestSseStreamControlAwareTransport].
///
/// This keeps stream control unambiguous when independent clients use the same
/// JSON-RPC request ID concurrently on one transport instance.
abstract class RequestContextSseStreamControlAwareTransport {
  /// Whether the request identified by both [requestId] and [requestContext]
  /// has an active resumable SSE stream.
  bool canCloseRequestSseStreamWithContext(
    RequestId requestId,
    Object requestContext,
  );

  /// Closes the resumable SSE stream identified by [requestContext].
  void closeRequestSseStreamWithContext(
    RequestId requestId,
    Object requestContext,
  );
}

/// Marker for server transports that close subscription streams with an MCP
/// `notifications/cancelled` control message.
///
/// MCP 2026-07-28 requires this on stdio, where there is no per-request stream
/// to close. Streamable HTTP transports must not implement this marker.
abstract interface class ServerSubscriptionCancellationTransport {}

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

  /// Sends [message] on a specific incoming-request context when supported.
  ///
  /// Transports without request contexts retain the existing request-ID-aware
  /// behavior.
  Future<void> sendPreservingRequestContext(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
    Object? requestContext,
  }) {
    final transport = this;
    if (requestContext != null &&
        transport is IncomingRequestContextAwareTransport) {
      return (transport as IncomingRequestContextAwareTransport)
          .sendWithRequestContext(
        message,
        relatedRequestId: relatedRequestId,
        requestContext: requestContext,
      );
    }

    return sendPreservingRequestId(
      message,
      relatedRequestId: relatedRequestId,
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

/// Optional capability for server transports that validate protocol-version
/// metadata before forwarding a request to the protocol layer.
abstract class ServerSupportedProtocolVersionsAwareTransport {
  /// Supplies the exact protocol versions accepted by the connected server.
  void setServerSupportedProtocolVersions(Iterable<String> versions);
}
