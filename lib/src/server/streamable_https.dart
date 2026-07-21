import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/mcp_header_validation.dart';
import 'package:mcp_dart/src/shared/protocol_direction.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types/json_rpc.dart' as json_rpc;

import '../shared/transport.dart';
import '../types.dart';
import 'dns_rebinding_protection.dart';

const String _xAccelBufferingHeader = 'X-Accel-Buffering';
const int _maxSafeHeaderInteger = 9007199254740991;
const int _minSafeHeaderInteger = -9007199254740991;

/// ID for SSE streams
typedef StreamId = String;

/// ID for events in SSE streams
typedef EventId = String;

final Object _incomingRequestRouteZoneKey = Object();

class _IncomingRequestRoute {
  final RequestId requestId;
  final StreamId streamId;
  final bool stateless;

  const _IncomingRequestRoute({
    required this.requestId,
    required this.streamId,
    required this.stateless,
  });
}

class _DetachedHttpResponse {
  final Socket socket;
  final Map<String, List<String>> headers;

  const _DetachedHttpResponse({
    required this.socket,
    required this.headers,
  });
}

/// Interface for resumability support via event storage
abstract class EventStore {
  /// Stores an event for later retrieval
  ///
  /// [streamId] ID of the stream the event belongs to
  /// [message] The JSON-RPC message to store
  ///
  /// Returns the generated event ID for the stored event. Event IDs are written
  /// to SSE `id:` fields and later sent by clients in the `Last-Event-ID` HTTP
  /// header, so implementations must return non-empty visible ASCII without
  /// spaces or control characters.
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message);

  /// Replays events after a specified event ID.
  ///
  /// Implementations must replay only events from the stream that originally
  /// produced [lastEventId]. Events from other streams must not be replayed.
  ///
  /// [lastEventId] The last event ID received by the client
  /// [send] Callback function that will be called for each event. Replayed
  /// event IDs must follow the same SSE/header-safe requirements as IDs
  /// returned by [storeEvent].
  ///
  /// Returns the stream ID associated with the events
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
        send,
  });
}

/// Configuration options for StreamableHTTPServerTransport
class StreamableHTTPServerTransportOptions {
  /// Function that generates a session ID for the transport.
  /// The session ID SHOULD be globally unique and cryptographically secure
  /// (e.g., a securely generated UUID, a JWT, or a cryptographic hash).
  ///
  /// Generated IDs are sent in the `MCP-Session-Id` HTTP response header and
  /// therefore must be non-empty visible ASCII without spaces or control
  /// characters.
  ///
  /// Return null to disable session management.
  final String? Function()? sessionIdGenerator;

  /// A callback for session initialization events
  /// This is called when the server initializes a new session.
  /// Useful in cases when you need to register multiple MCP sessions
  /// and need to keep track of them.
  final void Function(String sessionId)? onsessioninitialized;

  /// If true, the server will return JSON responses instead of starting an SSE stream.
  /// This can be useful for simple request/response scenarios without streaming.
  /// Stateless 2026 JSON responses close their HTTP connection after the
  /// response so a peer disconnect can cancel a still-pending request.
  /// Default is false (SSE streams are preferred).
  final bool enableJsonResponse;

  /// Event store for resumability support
  /// If provided, resumability will be enabled, allowing clients to reconnect and resume messages
  final EventStore? eventStore;

  /// Enables host/origin validation to mitigate DNS rebinding attacks.
  final bool enableDnsRebindingProtection;

  /// Explicit host allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedHosts;

  /// Explicit origin allowlist used when DNS rebinding protection is enabled.
  final Set<String>? allowedOrigins;

  /// If true, reject unsupported `MCP-Protocol-Version` headers with HTTP 400.
  ///
  /// Set to false for backward-compatibility behavior.
  final bool strictProtocolVersionHeaderValidation;

  /// If true, reject JSON-RPC batch payloads for Streamable HTTP POST requests.
  ///
  /// Set to false for backward-compatibility behavior.
  final bool rejectBatchJsonRpcPayloads;

  /// The maximum number of events allowed during SSE resumption.
  /// Used to protect against out-of-memory errors from overly large replays.
  /// Default is 1000.
  final int maxReplayedEvents;

  /// Reconnection delay advertised in resumable SSE priming events.
  ///
  /// Clients use this value after a server-initiated disconnect. The field is
  /// emitted only when [eventStore] enables resumability. Defaults to one
  /// second.
  final Duration sseRetryDelay;

  /// Creates configuration options for StreamableHTTPServerTransport
  StreamableHTTPServerTransportOptions({
    this.sessionIdGenerator,
    this.onsessioninitialized,
    this.enableJsonResponse = false,
    this.eventStore,
    this.enableDnsRebindingProtection = true,
    this.allowedHosts,
    this.allowedOrigins,
    this.strictProtocolVersionHeaderValidation = true,
    this.rejectBatchJsonRpcPayloads = true,
    this.maxReplayedEvents = 1000,
    this.sseRetryDelay = const Duration(seconds: 1),
  }) {
    if (sseRetryDelay.isNegative) {
      throw ArgumentError.value(
        sseRetryDelay,
        'sseRetryDelay',
        'Must not be negative',
      );
    }
  }
}

/// Server transport for Streamable HTTP: this implements the MCP Streamable HTTP transport specification.
/// It supports both SSE streaming and direct HTTP responses.
///
/// Usage example:
///
/// ```dart
/// // Stateful mode - server sets the session ID
/// final statefulTransport = StreamableHTTPServerTransport(
///   options: StreamableHTTPServerTransportOptions(
///     sessionIdGenerator: () => generateUUID(),
///   ),
/// );
///
/// // Stateless mode - explicitly set session ID to null
/// final statelessTransport = StreamableHTTPServerTransport(
///   options: StreamableHTTPServerTransportOptions(
///     sessionIdGenerator: () => null,
///   ),
/// );
///
/// // Using with HTTP server
/// final server = await HttpServer.bind('localhost', 8080);
/// server.listen((request) {
///   if (request.uri.path == '/mcp') {
///     statefulTransport.handleRequest(request);
///   }
/// });
/// ```
///
/// In stateful mode:
/// - Session ID is generated and included in response headers
/// - Session ID is always included in initialization responses
/// - Requests with invalid session IDs are rejected with 404 Not Found
/// - Non-initialization requests without a session ID are rejected with 400 Bad Request
/// - State is maintained in-memory (connections, message history)
///
/// In stateless mode:
/// - Session ID is only included in initialization responses
/// - No session validation is performed
class StreamableHTTPServerTransport
    implements
        Transport,
        RequestIdAwareTransport,
        IncomingRequestContextAwareTransport,
        RequestSseStreamControlAwareTransport,
        RequestContextSseStreamControlAwareTransport,
        IncomingRequestValidationAwareTransport,
        ServerSupportedProtocolVersionsAwareTransport,
        ToolParameterHeaderAwareTransport {
  static const Set<String> _statelessRemovedRequestMethods = {
    Method.initialize,
    Method.ping,
    Method.loggingSetLevel,
    Method.resourcesSubscribe,
    Method.resourcesUnsubscribe,
  };

  // when sessionId is not set (null), it means the transport is in stateless mode
  final String? Function()? _sessionIdGenerator;
  bool _started = false;
  bool _closed = false;
  final Map<String, HttpResponse> _streamMapping = {};
  final Set<StreamId> _standaloneSseStreamIds = {};
  final Map<StreamId, Set<HttpResponse>> _standaloneSseResponses = {};
  final Map<HttpResponse, Future<void>> _responseWriteTails = Map.identity();
  final Set<StreamId> _ownedStreamIds = {};
  final Map<RequestId, List<_IncomingRequestRoute>> _requestRoutesById = {};
  final Map<StreamId, Set<_IncomingRequestRoute>> _requestRoutesByStream = {};
  final Map<_IncomingRequestRoute, JsonRpcMessage> _requestResponseMap = {};
  final Set<StreamId> _jsonResponseStreamIds = {};
  final Map<StreamId, HttpRequest> _pendingJsonResponseRequests = {};
  final Map<StreamId, _DetachedHttpResponse> _detachedJsonResponses = {};
  final Map<StreamId, Future<void>> _jsonResponseToSseTransitions = {};
  final Set<StreamId> _detachingJsonResponseStreamIds = {};
  final Map<StreamId, Socket> _responseStreamSockets = {};
  final Map<StreamId, Completer<void>> _detachedResponseLifecycles = {};
  final Set<StreamId> _detachedResumableStreamIds = {};
  bool _initialized = false;
  bool _terminated = false;
  final bool _enableJsonResponse;
  final String _standaloneSseStreamIdPrefix = '_GET_stream:';
  final String _legacyStandaloneSseStreamId = '_GET_stream';
  final EventStore? _eventStore;
  final void Function(String sessionId)? _onsessioninitialized;
  final bool _enableDnsRebindingProtection;
  final Set<String>? _allowedHosts;
  final Set<String>? _allowedOrigins;
  final bool _strictProtocolVersionHeaderValidation;
  final bool _rejectBatchJsonRpcPayloads;
  final int _maxReplayedEvents;
  final Duration _sseRetryDelay;
  ToolParameterHeaderMappings _toolParameterHeaderMappings = const {};
  McpError? Function(JsonRpcRequest request)? _incomingRequestValidator;
  bool Function(String method)? _isRequestMethodSupported;
  Set<String> _supportedProtocolVersions =
      Set<String>.of(allSupportedProtocolVersions);
  static const JsonRpcNotification _ssePrimingMessage =
      JsonRpcNotification(method: 'notifications/experimental/sse/priming');

  @override
  String? sessionId;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Creates a new StreamableHTTPServerTransport
  StreamableHTTPServerTransport({
    required StreamableHTTPServerTransportOptions options,
  })  : _sessionIdGenerator = options.sessionIdGenerator,
        _enableJsonResponse = options.enableJsonResponse,
        _eventStore = options.eventStore,
        _onsessioninitialized = options.onsessioninitialized,
        _enableDnsRebindingProtection = options.enableDnsRebindingProtection,
        _allowedHosts = options.allowedHosts,
        _allowedOrigins = options.allowedOrigins,
        _strictProtocolVersionHeaderValidation =
            options.strictProtocolVersionHeaderValidation,
        _rejectBatchJsonRpcPayloads = options.rejectBatchJsonRpcPayloads,
        _maxReplayedEvents = options.maxReplayedEvents,
        _sseRetryDelay = options.sseRetryDelay;

  /// Starts the transport. This is required by the Transport interface but is a no-op
  /// for the Streamable HTTP transport as connections are managed per-request.
  @override
  Future<void> start() async {
    if (_closed) {
      throw StateError("Transport is closed");
    }
    if (_started) {
      throw StateError("Transport already started");
    }
    _started = true;
  }

  @override
  void setToolParameterHeaderMappings(
    ToolParameterHeaderMappings mappings,
  ) {
    _toolParameterHeaderMappings = {
      for (final entry in mappings.entries)
        entry.key: Map.unmodifiable(Map<String, String>.from(entry.value)),
    };
  }

  @override
  void setIncomingRequestValidator(
    McpError? Function(JsonRpcRequest request) validator,
  ) {
    _incomingRequestValidator = validator;
  }

  @override
  void setRequestMethodSupported(bool Function(String method) isSupported) {
    _isRequestMethodSupported = isSupported;
  }

  @override
  void setServerSupportedProtocolVersions(Iterable<String> versions) {
    _supportedProtocolVersions = Set<String>.unmodifiable(versions);
  }

  @override
  Object? get incomingRequestContext {
    final route = Zone.current[_incomingRequestRouteZoneKey];
    return route is _IncomingRequestRoute ? route : null;
  }

  void _registerRequestRoute(_IncomingRequestRoute route) {
    _requestRoutesById.putIfAbsent(route.requestId, () => []).add(route);
    _requestRoutesByStream.putIfAbsent(route.streamId, () => {}).add(route);
  }

  bool _isActiveRequestRoute(_IncomingRequestRoute route) =>
      _requestRoutesByStream[route.streamId]?.contains(route) ?? false;

  void _removeRequestRoute(_IncomingRequestRoute route) {
    _requestResponseMap.remove(route);
    final routesForId = _requestRoutesById[route.requestId];
    routesForId?.remove(route);
    if (routesForId?.isEmpty ?? false) {
      _requestRoutesById.remove(route.requestId);
    }
    final routesForStream = _requestRoutesByStream[route.streamId];
    routesForStream?.remove(route);
    if (routesForStream?.isEmpty ?? false) {
      _requestRoutesByStream.remove(route.streamId);
    }
  }

  List<_IncomingRequestRoute> _routesForStream(StreamId streamId) =>
      List<_IncomingRequestRoute>.of(
        _requestRoutesByStream[streamId] ?? const {},
      );

  void _completeDetachedResponseLifecycle(StreamId streamId) {
    final lifecycle = _detachedResponseLifecycles.remove(streamId);
    if (lifecycle != null && !lifecycle.isCompleted) {
      lifecycle.complete();
    }
  }

  _IncomingRequestRoute? _resolveRequestRoute(
    RequestId requestId, {
    Object? requestContext,
    bool throwIfAmbiguous = true,
  }) {
    final context = requestContext ?? incomingRequestContext;
    if (context is _IncomingRequestRoute &&
        context.requestId == requestId &&
        _isActiveRequestRoute(context)) {
      return context;
    }
    if (context != null) {
      return null;
    }

    final routes = _requestRoutesById[requestId] ?? const [];
    if (routes.length == 1) {
      return routes.single;
    }
    if (routes.length > 1 && throwIfAmbiguous) {
      throw StateError(
        'Multiple connections are active for request ID $requestId; '
        'send the response from its incoming request context.',
      );
    }
    return null;
  }

  void _deliverIncomingMessage(
    JsonRpcMessage message, [
    _IncomingRequestRoute? route,
  ]) {
    if (route == null) {
      onmessage?.call(message);
      return;
    }
    runZoned(
      () => onmessage?.call(message),
      zoneValues: {_incomingRequestRouteZoneKey: route},
    );
  }

  @override
  bool canCloseRequestSseStream(RequestId requestId) {
    final route = _resolveRequestRoute(
      requestId,
      throwIfAmbiguous: false,
    );
    return route != null && _canCloseRequestSseStream(route);
  }

  @override
  void closeRequestSseStream(RequestId requestId) {
    final route = _resolveRequestRoute(requestId);
    if (route == null || !_canCloseRequestSseStream(route)) {
      throw StateError(
        'No resumable SSE stream established for request ID: $requestId',
      );
    }

    _closeRequestSseStream(route);
  }

  @override
  bool canCloseRequestSseStreamWithContext(
    RequestId requestId,
    Object requestContext,
  ) {
    final route = _resolveRequestRoute(
      requestId,
      requestContext: requestContext,
      throwIfAmbiguous: false,
    );
    return route != null && _canCloseRequestSseStream(route);
  }

  @override
  void closeRequestSseStreamWithContext(
    RequestId requestId,
    Object requestContext,
  ) {
    final route = _resolveRequestRoute(
      requestId,
      requestContext: requestContext,
    );
    if (route == null || !_canCloseRequestSseStream(route)) {
      throw StateError(
        'No resumable SSE stream established for request ID: $requestId',
      );
    }

    _closeRequestSseStream(route);
  }

  bool _canCloseRequestSseStream(_IncomingRequestRoute route) =>
      _eventStore != null &&
      !_jsonResponseStreamIds.contains(route.streamId) &&
      !route.stateless &&
      _streamMapping.containsKey(route.streamId);

  void _closeRequestSseStream(_IncomingRequestRoute route) {
    final streamId = route.streamId;
    final response = _streamMapping.remove(streamId)!;
    _detachedResumableStreamIds.add(streamId);
    unawaited(_safeClose(response));
  }

  /// Handles an incoming HTTP request, whether GET or POST.
  ///
  /// For detached stateless response streams, the returned future completes
  /// when that request's raw HTTP connection closes.
  Future<void> handleRequest(HttpRequest req, [dynamic parsedBody]) async {
    final wasOpenAtStart = !_closed;
    if (!wasOpenAtStart && sessionId == null) {
      await _safeClose(req.response);
      return;
    }
    req.response.bufferOutput = false;
    if (_enableDnsRebindingProtection &&
        !isRequestAllowedByDnsRebindingProtection(
          req,
          allowedHosts: _allowedHosts,
          allowedOrigins: _allowedOrigins,
        )) {
      req.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden: blocked by DNS rebinding protection');
      await _safeClose(req.response);
      return;
    }

    if (!await _validateProtocolVersionHeader(
      req,
      req.response,
      parsedBody: parsedBody,
    )) {
      return;
    }
    if (wasOpenAtStart && _closed) {
      await _safeClose(req.response);
      return;
    }

    if (req.method == "POST") {
      await _handlePostRequest(req, parsedBody, wasOpenAtStart);
    } else if (_isStatelessProtocolVersionRequest(req)) {
      await _handleStatelessUnsupportedRequest(req.response);
    } else if (req.method == "GET") {
      await _handleGetRequest(req);
    } else if (req.method == "DELETE") {
      await _handleDeleteRequest(req);
    } else {
      await _handleUnsupportedRequest(req.response);
    }
  }

  Future<bool> _validateProtocolVersionHeader(
    HttpRequest req,
    HttpResponse res, {
    dynamic parsedBody,
  }) async {
    if (!_strictProtocolVersionHeaderValidation) {
      return true;
    }

    final versionHeader = req.headers.value('mcp-protocol-version');
    if (versionHeader == null || versionHeader.trim().isEmpty) {
      return true;
    }

    final requestedVersion = versionHeader.trim();
    if (_supportedProtocolVersions.contains(requestedVersion)) {
      return true;
    }

    var bodyForRequestId = parsedBody;
    if (bodyForRequestId == null && req.method == 'POST') {
      try {
        final bodyBytes = await _collectBytes(req);
        bodyForRequestId = jsonDecode(utf8.decode(bodyBytes));
      } catch (_) {
        // The unsupported-version response still takes precedence. JSON-RPC
        // requires null only when the request ID cannot be established.
      }
    }

    await _writeJsonRpcErrorResponse(
      res,
      httpStatus: HttpStatus.badRequest,
      errorCode: ErrorCode.unsupportedProtocolVersion,
      message: 'Unsupported protocol version',
      id: _requestIdFromParsedBody(bodyForRequestId),
      data: {
        'requested': requestedVersion,
        'supported': _supportedProtocolVersions.toList(growable: false),
      },
    );
    return false;
  }

  bool _isStatelessProtocolVersionRequest(HttpRequest req) {
    final versionHeader = req.headers.value('mcp-protocol-version');
    return versionHeader != null &&
        isStatelessProtocolVersion(versionHeader.trim());
  }

  bool _isValidHeaderValue(String value) {
    if (value.trim() != value) {
      return false;
    }

    return value.codeUnits.every(
      (unit) => unit == 0x09 || unit == 0x20 || unit >= 0x21 && unit <= 0x7E,
    );
  }

  bool _isValidVisibleAsciiToken(String value) {
    if (value.isEmpty) {
      return false;
    }

    return value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7E);
  }

  bool _isValidSessionId(String sessionId) {
    return _isValidVisibleAsciiToken(sessionId);
  }

  Map<String, String> _sseResponseHeaders() {
    return {
      HttpHeaders.contentTypeHeader: 'text/event-stream; charset=utf-8',
      HttpHeaders.cacheControlHeader: 'no-cache, no-transform',
      HttpHeaders.connectionHeader: 'keep-alive',
      _xAccelBufferingHeader: 'no',
    };
  }

  void _validateSseEventId(EventId eventId) {
    if (!_isValidVisibleAsciiToken(eventId)) {
      throw StateError(
        'Invalid SSE event ID generated by EventStore: event IDs must be '
        'non-empty visible ASCII without spaces or control characters',
      );
    }
  }

  Future<void> _writeJsonRpcErrorResponse(
    HttpResponse response, {
    required int httpStatus,
    required ErrorCode errorCode,
    required String message,
    RequestId? id,
    Object? data,
  }) {
    return _writeJsonRpcErrorCodeResponse(
      response,
      httpStatus: httpStatus,
      errorCode: errorCode.value,
      message: message,
      id: id,
      data: data,
    );
  }

  Future<void> _writeJsonRpcErrorCodeResponse(
    HttpResponse response, {
    required int httpStatus,
    required int errorCode,
    required String message,
    RequestId? id,
    Object? data,
  }) async {
    response.statusCode = httpStatus;
    response.headers.contentType = ContentType.json;
    response.write(
      jsonEncode(
        JsonRpcError(
          id: id,
          error: JsonRpcErrorData(
            code: errorCode,
            message: message,
            data: data,
          ),
        ).toJson(),
      ),
    );
    await _safeClose(response);
  }

  int _statelessHttpStatusForErrorCode(int code) {
    if (code == ErrorCode.methodNotFound.value) {
      return HttpStatus.notFound;
    }

    return HttpStatus.badRequest;
  }

  Future<void> _writeHeaderMismatchResponse(
    HttpResponse response,
    JsonRpcMessage message,
    String detail,
  ) {
    return _writeJsonRpcErrorResponse(
      response,
      httpStatus: HttpStatus.badRequest,
      errorCode: ErrorCode.headerMismatch,
      id: message is JsonRpcRequest ? message.id : null,
      message: 'Header mismatch: $detail',
    );
  }

  String? _metadataProtocolVersion(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      final version = message.meta?[McpMetaKey.protocolVersion];
      return version is String ? version : null;
    }
    if (message is JsonRpcNotification) {
      final version = message.meta?[McpMetaKey.protocolVersion];
      return version is String ? version : null;
    }
    return null;
  }

  String? _nestedMetadataProtocolVersion(Map<String, dynamic> messageJson) {
    final params = messageJson['params'];
    if (params is Map) {
      final meta = params['_meta'];
      if (meta is Map) {
        final version = meta[McpMetaKey.protocolVersion];
        return version is String ? version : null;
      }
    }
    return null;
  }

  RequestId? _requestIdFromParsedBody(dynamic parsedBody) {
    if (parsedBody is! Map || !parsedBody.containsKey('id')) {
      return null;
    }

    try {
      return json_rpc.parseRequestId(parsedBody['id']);
    } catch (_) {
      return null;
    }
  }

  RequestId? _singleRequestId(List<JsonRpcMessage> messages) {
    if (messages.length != 1) {
      return null;
    }
    final message = messages.single;
    return message is JsonRpcRequest ? message.id : null;
  }

  RequestId? _rawRequestId(Map<String, dynamic> messageJson) {
    if (!messageJson.containsKey('id')) {
      return null;
    }
    try {
      return json_rpc.parseRequestId(messageJson['id']);
    } catch (_) {
      return null;
    }
  }

  bool _hasValidJsonRpcRequestEnvelope(
    Map<String, dynamic> messageJson,
  ) {
    if (messageJson['jsonrpc'] != jsonRpcVersion ||
        messageJson['method'] is! String ||
        !messageJson.containsKey('id') ||
        messageJson.containsKey('result') ||
        messageJson.containsKey('error')) {
      return false;
    }
    return _rawRequestId(messageJson) != null;
  }

  bool _isStatelessRemovedRequestJson(
    HttpRequest req,
    Map<String, dynamic> messageJson,
  ) {
    final method = messageJson['method'];
    return method is String &&
        _statelessRemovedRequestMethods.contains(method) &&
        messageJson.containsKey('id') &&
        _isStatelessRequestJson(req, messageJson);
  }

  bool _isStatelessRequestJson(
    HttpRequest req,
    Map<String, dynamic> messageJson,
  ) {
    final headerVersion = req.headers.value('mcp-protocol-version')?.trim();
    if (headerVersion != null && isStatelessProtocolVersion(headerVersion)) {
      return true;
    }

    final metadataVersion = _nestedMetadataProtocolVersion(messageJson);
    return metadataVersion != null &&
        isStatelessProtocolVersion(metadataVersion);
  }

  String? _rawStatelessRequestMetadataError(
    HttpRequest req,
    Map<String, dynamic> messageJson,
  ) {
    if (!_hasValidJsonRpcRequestEnvelope(messageJson) ||
        !_isStatelessRequestJson(req, messageJson)) {
      return null;
    }

    final params = messageJson['params'];
    final meta = params is Map ? params['_meta'] : null;
    if (meta != null && meta is! Map) {
      return 'Invalid stateless request metadata.';
    }
    final protocolVersion =
        meta is Map ? meta[McpMetaKey.protocolVersion] : null;
    if (protocolVersion is! String || protocolVersion.isEmpty) {
      return 'Missing required request metadata: '
          '${McpMetaKey.protocolVersion}';
    }
    return null;
  }

  String? _rawStatelessRequestHeaderMismatch(
    HttpRequest req,
    Map<String, dynamic> messageJson,
  ) {
    if (!_hasValidJsonRpcRequestEnvelope(messageJson) ||
        !_isStatelessRequestJson(req, messageJson)) {
      return null;
    }

    final protocolHeader = req.headers.value('mcp-protocol-version')?.trim();
    if (protocolHeader == null || protocolHeader.isEmpty) {
      return 'MCP-Protocol-Version header is required';
    }
    if (!_isValidHeaderValue(protocolHeader)) {
      return 'MCP-Protocol-Version header value is malformed';
    }

    final metadataVersion = _nestedMetadataProtocolVersion(messageJson);
    if (metadataVersion == null) {
      return 'MCP-Protocol-Version header has no matching request _meta '
          'protocol version in params._meta';
    }
    if (protocolHeader != metadataVersion) {
      return "MCP-Protocol-Version header value '$protocolHeader' does not "
          "match body value '$metadataVersion'";
    }

    final method = messageJson['method'] as String;
    final methodHeader = req.headers.value('mcp-method');
    if (methodHeader == null) {
      return 'Mcp-Method header is required';
    }
    if (methodHeader != method) {
      return "Mcp-Method header value '$methodHeader' does not match body "
          "value '$method'";
    }

    final requiredNameSourceField = _requiredNameHeaderSourceField(method);
    if (requiredNameSourceField == null) {
      return null;
    }
    final nameHeader = req.headers.value('mcp-name');
    if (nameHeader == null || nameHeader.isEmpty) {
      return 'Mcp-Name header is required';
    }
    final decodedName = _decodeMcpHeaderValue(nameHeader);
    if (decodedName == null) {
      return 'Mcp-Name header value is malformed';
    }

    final params = messageJson['params'];
    final requiredName = params is Map ? params[requiredNameSourceField] : null;
    if (requiredName is String && decodedName != requiredName) {
      return "Mcp-Name header value '$nameHeader' does not match body value "
          "'$requiredName'";
    }

    return null;
  }

  bool _usesStatelessHttpValidation(
    HttpRequest req,
    List<JsonRpcMessage> messages,
  ) {
    final headerVersion = req.headers.value('mcp-protocol-version')?.trim();
    if (headerVersion != null && isStatelessProtocolVersion(headerVersion)) {
      return true;
    }

    return messages.any((message) {
      final version = _metadataProtocolVersion(message);
      return version != null && isStatelessProtocolVersion(version);
    });
  }

  String? _messageMethod(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.method;
    }
    if (message is JsonRpcNotification) {
      return message.method;
    }
    return null;
  }

  Map<String, dynamic>? _messageParams(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.params;
    }
    if (message is JsonRpcNotification) {
      return message.params;
    }
    return null;
  }

  String? _requiredNameHeaderSourceField(String method) {
    return switch (method) {
      Method.toolsCall || Method.promptsGet => 'name',
      Method.resourcesRead => 'uri',
      Method.tasksGet || Method.tasksUpdate || Method.tasksCancel => 'taskId',
      _ => null,
    };
  }

  String? _decodeMcpHeaderValue(String value) {
    if (value.startsWith('=?base64?') && value.endsWith('?=')) {
      final encoded = value.substring('=?base64?'.length, value.length - 2);
      try {
        return utf8.decode(base64Decode(encoded));
      } catch (_) {
        return null;
      }
    }

    return _isValidHeaderValue(value) ? value : null;
  }

  String? _primitiveHeaderString(Object? value) {
    if (value is num) {
      if (!value.isFinite) {
        return null;
      }
      if (value is double && value.truncateToDouble() == value) {
        return value.toInt().toString();
      }
      return value.toString();
    }

    return switch (value) {
      null => null,
      String() => value,
      bool() => value.toString(),
      _ => null,
    };
  }

  bool _isUnsafeHeaderInteger(Object? value) {
    if (value is int) {
      return value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger;
    }
    return value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        (value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger);
  }

  bool _headerValueMatchesPrimitive(Object? bodyValue, String headerValue) {
    if (bodyValue is num) {
      if (!bodyValue.isFinite) {
        return false;
      }
      final headerNumber = num.tryParse(headerValue);
      return headerNumber != null &&
          headerNumber.isFinite &&
          headerNumber == bodyValue;
    }

    final value = _primitiveHeaderString(bodyValue);
    return value != null && headerValue == value;
  }

  String? _toolName(JsonRpcMessage message) {
    if (_messageMethod(message) != Method.toolsCall) {
      return null;
    }

    final name = _messageParams(message)?['name'];
    return name is String ? name : null;
  }

  Future<bool> _validateMcpParamHeaders(
    HttpRequest req,
    HttpResponse res,
    JsonRpcMessage message,
  ) async {
    final toolName = _toolName(message);
    final headerMappings =
        toolName == null ? null : _toolParameterHeaderMappings[toolName];
    final recognizedHeaderSuffixes = <String>{
      for (final suffix in headerMappings?.values ?? const <String>[])
        suffix.toLowerCase(),
    };
    final headers = <String, _McpParamHeader>{};
    req.headers.forEach((name, values) {
      const prefix = 'mcp-param-';
      final lowerName = name.toLowerCase();
      if (!lowerName.startsWith(prefix)) {
        return;
      }

      final headerSuffix = name.substring(prefix.length);
      if (!recognizedHeaderSuffixes.contains(headerSuffix.toLowerCase())) {
        return;
      }

      if (!isValidMcpHeaderNameSuffix(headerSuffix)) {
        headers[lowerName] = _McpParamHeader.invalidName(
          name: name,
          suffix: headerSuffix,
        );
        return;
      }

      final headerValue = req.headers.value(name);
      final decodedValue =
          headerValue == null ? null : _decodeMcpHeaderValue(headerValue);
      if (decodedValue == null) {
        headers[lowerName] = _McpParamHeader.invalidValue(
          name: name,
          suffix: headerSuffix,
        );
        return;
      }

      headers[headerSuffix.toLowerCase()] = _McpParamHeader(
        name: name,
        suffix: headerSuffix,
        value: decodedValue,
      );
    });

    _McpParamHeader? invalidHeader;
    for (final header in headers.values) {
      if (header.validationError != null) {
        invalidHeader = header;
        break;
      }
    }
    if (invalidHeader != null) {
      final messageText =
          invalidHeader.validationError == _McpParamHeaderValidationError.name
              ? '${invalidHeader.name} header name is malformed'
              : '${invalidHeader.name} header value is malformed';
      await _writeHeaderMismatchResponse(res, message, messageText);
      return false;
    }

    if (headerMappings == null) {
      return true;
    }

    final params = _messageParams(message);
    final arguments = params?['arguments'];
    final argumentMap = arguments is Map
        ? arguments.cast<String, dynamic>()
        : const <String, dynamic>{};

    for (final entry in headerMappings.entries) {
      final argumentName = entry.key;
      final headerSuffix = entry.value;
      final header = headers[headerSuffix.toLowerCase()];
      final argument = _toolParameterHeaderArgument(argumentMap, entry.key);
      final hasArgument = argument.exists;
      final bodyArgument = argument.value;

      if (hasArgument && _isUnsafeHeaderInteger(bodyArgument)) {
        await _writeHeaderMismatchResponse(
          res,
          message,
          "Body argument '$argumentName' must be within the JavaScript safe "
          'integer range ($_minSafeHeaderInteger to '
          '$_maxSafeHeaderInteger)',
        );
        return false;
      }

      final bodyValue =
          hasArgument ? _primitiveHeaderString(bodyArgument) : null;
      if (!hasArgument || bodyValue == null) {
        if (header != null) {
          await _writeHeaderMismatchResponse(
            res,
            message,
            '${header.name} header has no matching primitive body argument '
            "'$argumentName'",
          );
          return false;
        }
        continue;
      }

      if (header == null) {
        await _writeHeaderMismatchResponse(
          res,
          message,
          'Mcp-Param-$headerSuffix header is required for body argument '
          "'$argumentName'",
        );
        return false;
      }

      if (!_headerValueMatchesPrimitive(bodyArgument, header.value!)) {
        await _writeHeaderMismatchResponse(
          res,
          message,
          '${header.name} header value does not match body argument '
          "'$argumentName'",
        );
        return false;
      }
    }

    return true;
  }

  ({bool exists, Object? value}) _toolParameterHeaderArgument(
    Map<String, dynamic> arguments,
    String selector,
  ) {
    if (!selector.startsWith('/')) {
      return (
        exists: arguments.containsKey(selector),
        value: arguments[selector],
      );
    }

    Object? current = arguments;
    for (final segment in _jsonPointerSegments(selector)) {
      if (current is! Map || !current.containsKey(segment)) {
        return (exists: false, value: null);
      }
      current = current[segment];
    }
    return (exists: true, value: current);
  }

  Iterable<String> _jsonPointerSegments(String selector) {
    if (selector == '/') {
      return const [''];
    }
    return selector
        .substring(1)
        .split('/')
        .map((segment) => segment.replaceAll('~1', '/').replaceAll('~0', '~'));
  }

  Future<bool> _validateStatelessHttpHeaders(
    HttpRequest req,
    List<JsonRpcMessage> messages,
    List<Map<String, dynamic>> messageJsons,
  ) async {
    if (!_usesStatelessHttpValidation(req, messages)) {
      return true;
    }

    if (messages.length != 1) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidRequest,
        message:
            'Invalid Request: stateless MCP POST body must contain one JSON-RPC message',
      );
      return false;
    }

    final message = messages.single;
    final messageJson = messageJsons.single;
    final protocolHeader = req.headers.value('mcp-protocol-version')?.trim();
    if (protocolHeader == null || protocolHeader.isEmpty) {
      await _writeHeaderMismatchResponse(
        req.response,
        message,
        'MCP-Protocol-Version header is required',
      );
      return false;
    }
    if (!_isValidHeaderValue(protocolHeader)) {
      await _writeHeaderMismatchResponse(
        req.response,
        message,
        'MCP-Protocol-Version header value is malformed',
      );
      return false;
    }

    if (message is JsonRpcResponse || message is JsonRpcError) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidRequest,
        message:
            'Invalid Request: stateless MCP clients must not POST JSON-RPC responses',
      );
      return false;
    }
    if (message is JsonRpcCancelledNotification) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidRequest,
        message: 'Invalid Request: stateless Streamable HTTP cancels a '
            'request by closing its response stream, not by POSTing '
            '${Method.notificationsCancelled}.',
      );
      return false;
    }
    if (message is JsonRpcNotification &&
        isStatelessForbiddenClientNotification(message.method)) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidRequest,
        message: 'Invalid Request: ${message.method} is a server-to-client '
            'notification in stateless MCP.',
      );
      return false;
    }
    if (message is JsonRpcNotification) {
      // Core 2026-07-28 defines no accepted HTTP client notifications and no
      // request-metadata header contract for notification POSTs. Preserve the
      // generic transport mechanics for negotiated extensions without
      // applying request-only body metadata checks to them.
      return true;
    }

    final metadataVersion = _nestedMetadataProtocolVersion(messageJson);
    if (metadataVersion == null) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.invalidParams,
        id: message is JsonRpcRequest ? message.id : null,
        message: 'Missing required request metadata: '
            '${McpMetaKey.protocolVersion}',
      );
      return false;
    } else if (protocolHeader != metadataVersion) {
      await _writeHeaderMismatchResponse(
        req.response,
        message,
        "MCP-Protocol-Version header value '$protocolHeader' does not match body value '$metadataVersion'",
      );
      return false;
    }
    final method = _messageMethod(message);
    if (method == null) {
      return true;
    }

    final methodHeader = req.headers.value('mcp-method');
    if (methodHeader == null) {
      await _writeHeaderMismatchResponse(
        req.response,
        message,
        'Mcp-Method header is required',
      );
      return false;
    }
    if (methodHeader != method) {
      await _writeHeaderMismatchResponse(
        req.response,
        message,
        "Mcp-Method header value '$methodHeader' does not match body value '$method'",
      );
      return false;
    }

    final requiredNameSourceField = _requiredNameHeaderSourceField(method);
    if (requiredNameSourceField != null) {
      final nameHeader = req.headers.value('mcp-name');
      if (nameHeader == null) {
        await _writeHeaderMismatchResponse(
          req.response,
          message,
          'Mcp-Name header is required',
        );
        return false;
      }
      final decodedName = _decodeMcpHeaderValue(nameHeader);
      if (decodedName == null) {
        await _writeHeaderMismatchResponse(
          req.response,
          message,
          'Mcp-Name header value is malformed',
        );
        return false;
      }
      final requiredName = _messageParams(message)?[requiredNameSourceField];
      if (decodedName != requiredName) {
        await _writeHeaderMismatchResponse(
          req.response,
          message,
          "Mcp-Name header value '$nameHeader' does not match body value '$requiredName'",
        );
        return false;
      }
    }

    if (!await _validateMcpParamHeaders(req, req.response, message)) {
      return false;
    }

    if (message is JsonRpcRequest) {
      final validationError = _incomingRequestValidator?.call(message);
      if (validationError != null) {
        await _writeJsonRpcErrorCodeResponse(
          req.response,
          httpStatus: _statelessHttpStatusForErrorCode(validationError.code),
          errorCode: validationError.code,
          id: message.id,
          message: validationError.message,
          data: validationError.data,
        );
        return false;
      }

      final isRequestMethodSupported = _isRequestMethodSupported;
      if (isRequestMethodSupported != null &&
          !isRequestMethodSupported(message.method)) {
        await _writeJsonRpcErrorResponse(
          req.response,
          httpStatus: HttpStatus.notFound,
          errorCode: ErrorCode.methodNotFound,
          id: message.id,
          message: 'Method not found: ${message.method}',
        );
        return false;
      }
    }

    return true;
  }

  bool _isStandaloneSseStreamId(StreamId streamId) {
    return streamId == _legacyStandaloneSseStreamId ||
        streamId.startsWith(_standaloneSseStreamIdPrefix);
  }

  void _addStandaloneSseResponse(StreamId streamId, HttpResponse response) {
    // Ownership only participates in Last-Event-ID replay validation. Do not
    // retain every ordinary SSE stream for the lifetime of the transport.
    if (_eventStore != null) {
      _ownedStreamIds.add(streamId);
    }
    _standaloneSseStreamIds.add(streamId);
    _standaloneSseResponses.putIfAbsent(streamId, () => {}).add(response);
    _streamMapping.putIfAbsent(streamId, () => response);
  }

  MapEntry<StreamId, HttpResponse>? _selectStandaloneSseTarget() {
    for (final streamId
        in List<StreamId>.from(_standaloneSseStreamIds).reversed) {
      final responses = _standaloneSseResponses[streamId];
      if (responses == null || responses.isEmpty) {
        _standaloneSseStreamIds.remove(streamId);
        _streamMapping.remove(streamId);
        continue;
      }

      return MapEntry(streamId, responses.last);
    }

    return null;
  }

  void _removeStandaloneSseResponse(
    StreamId streamId,
    HttpResponse response,
  ) {
    final responses = _standaloneSseResponses[streamId];
    responses?.remove(response);

    if (responses == null || responses.isEmpty) {
      _standaloneSseResponses.remove(streamId);
      _standaloneSseStreamIds.remove(streamId);
      if (identical(_streamMapping[streamId], response)) {
        _streamMapping.remove(streamId);
      }
      return;
    }

    if (identical(_streamMapping[streamId], response)) {
      _streamMapping[streamId] = responses.first;
    }
  }

  Set<String> _parseAcceptedMediaTypes(HttpRequest req) {
    final acceptHeaderValues = req.headers[HttpHeaders.acceptHeader];
    if (acceptHeaderValues == null || acceptHeaderValues.isEmpty) {
      return const <String>{};
    }

    return acceptHeaderValues
        .expand((value) => value.split(','))
        .map((value) => value.split(';').first.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  bool _acceptsMediaType(
    Set<String> acceptedMediaTypes,
    String expectedMediaType,
  ) {
    final normalizedExpectedMediaType = expectedMediaType.toLowerCase();
    return acceptedMediaTypes.contains(normalizedExpectedMediaType);
  }

  /// Handles GET requests for SSE stream
  Future<void> _handleGetRequest(HttpRequest req) async {
    // The client MUST include an Accept header, listing text/event-stream as a supported content type.
    final acceptedMediaTypes = _parseAcceptedMediaTypes(req);
    if (!_acceptsMediaType(acceptedMediaTypes, 'text/event-stream')) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.notAcceptable,
        errorCode: ErrorCode.connectionClosed,
        message: 'Not Acceptable: Client must accept text/event-stream',
      );
      return;
    }

    // If an Mcp-Session-Id is returned by the server during initialization,
    // clients using the Streamable HTTP transport MUST include it
    // in the Mcp-Session-Id header on all of their subsequent HTTP requests.
    if (!await _validateSession(req, req.response)) {
      return;
    }

    // Handle resumability: check for Last-Event-ID header
    if (_eventStore != null) {
      final lastEventId = req.headers.value('Last-Event-ID');
      if (lastEventId != null) {
        await _replayEvents(lastEventId, req.response);
        return;
      }
    }

    // The server MUST either return Content-Type: text/event-stream in response to this HTTP GET,
    // or else return HTTP 405 Method Not Allowed
    final headers = _sseResponseHeaders();

    // After initialization, always include the session ID if we have one
    if (sessionId != null) {
      headers["mcp-session-id"] = sessionId!;
    }

    // We need to send headers immediately as messages will arrive much later,
    // otherwise the client will just wait for the first message
    req.response.statusCode = HttpStatus.ok;
    req.response.bufferOutput = false;
    headers.forEach((key, value) {
      req.response.headers.set(key, value);
    });

    final streamId = '$_standaloneSseStreamIdPrefix${generateUUID()}';

    // Assign the response to the standalone SSE stream before flushing
    // to ensure it's available if a task tries to send a message immediately
    _addStandaloneSseResponse(streamId, req.response);

    if (!await _primeSseStream(streamId, req.response)) {
      _removeStandaloneSseResponse(streamId, req.response);
      _ownedStreamIds.remove(streamId);
      await _safeClose(req.response);
      return;
    }

    // Set up close handler for client disconnects
    req.response.done.then((_) {
      _removeStandaloneSseResponse(streamId, req.response);
    });
  }

  /// Replays events that would have been sent after the specified event ID
  /// Only used when resumability is enabled
  Future<void> _replayEvents(String lastEventId, HttpResponse res) async {
    if (_eventStore == null) {
      return;
    }

    try {
      final maxEvents = _maxReplayedEvents;
      final replayedEvents = <({EventId eventId, JsonRpcMessage message})>[];
      final streamId = await _eventStore.replayEventsAfter(
        lastEventId,
        send: (eventId, message) async {
          _validateSseEventId(eventId);
          if (replayedEvents.length >= maxEvents) {
            throw StateError(
              'Event replay limit exceeded: maximum of $maxEvents events can be replayed',
            );
          }
          replayedEvents.add((eventId: eventId, message: message));
        },
      );

      if (!_ownedStreamIds.contains(streamId)) {
        await _writeJsonRpcErrorResponse(
          res,
          httpStatus: HttpStatus.notFound,
          errorCode: ErrorCode.connectionClosed,
          message: 'Event ID not found',
        );
        return;
      }

      final headers = _sseResponseHeaders();

      if (sessionId != null) {
        headers["mcp-session-id"] = sessionId!;
      }

      res.statusCode = HttpStatus.ok;
      headers.forEach((key, value) {
        res.headers.set(key, value);
      });

      final primingEventId = await _eventStore.storeEvent(
        streamId,
        _ssePrimingMessage,
      );
      final replayBatch = BytesBuilder(copy: false);
      for (final event in replayedEvents) {
        replayBatch.add(_encodeSSEEvent(event.message, event.eventId));
      }
      replayBatch.add(_encodeSSEPrimingEvent(primingEventId));

      final isStandaloneStream = _isStandaloneSseStreamId(streamId);
      if (isStandaloneStream) {
        _addStandaloneSseResponse(streamId, res);
      } else {
        _streamMapping[streamId] = res;
        _detachedResumableStreamIds.remove(streamId);
      }

      try {
        // Queue the entire replay before the first await. A client can react as
        // soon as the first replayed event arrives, so the resumed response
        // must already be attached and later replay events must already be
        // ordered ahead of any new live message.
        final replayWritten = await _enqueueSseWrite(
          res,
          replayBatch.takeBytes(),
        );
        if (!replayWritten) {
          throw StateError('Failed to replay events');
        }
      } catch (error) {
        if (isStandaloneStream) {
          _removeStandaloneSseResponse(streamId, res);
        } else if (identical(_streamMapping[streamId], res)) {
          _streamMapping.remove(streamId);
          _detachedResumableStreamIds.add(streamId);
        }
        onerror?.call(
          error is Error
              ? error
              : StateError('Failed to replay events: $error'),
        );
        await _safeClose(res);
        return;
      }

      res.done.then((_) {
        if (isStandaloneStream) {
          _removeStandaloneSseResponse(streamId, res);
        } else if (identical(_streamMapping[streamId], res)) {
          _streamMapping.remove(streamId);
        }
      });
    } catch (error) {
      onerror?.call(error is Error ? error : StateError(error.toString()));
      final errorStr = error.toString().toLowerCase();
      final isNotFound = errorStr.contains('not found') ||
          errorStr.contains('unknown') ||
          errorStr.contains('invalid sse event id');
      final isLimitExceeded = errorStr.contains('replay limit exceeded');
      await _writeJsonRpcErrorResponse(
        res,
        httpStatus: isLimitExceeded
            ? 413
            : (isNotFound
                ? HttpStatus.notFound
                : HttpStatus.internalServerError),
        errorCode: ErrorCode.connectionClosed,
        message: isLimitExceeded
            ? 'Event replay limit exceeded'
            : (isNotFound
                ? 'Event ID not found'
                : 'Internal server error during replay: $error'),
      );
    }
  }

  /// Safely closes an HTTP response, ignoring errors if client disconnected
  Future<void> _safeClose(HttpResponse res) async {
    final pendingWrite = _responseWriteTails[res];
    if (pendingWrite != null) {
      try {
        await pendingWrite.timeout(const Duration(milliseconds: 100));
      } catch (_) {
        // Continue closing even if an in-flight write is stuck or failed.
      }
    }

    try {
      await res.close().timeout(const Duration(milliseconds: 100));
    } catch (e) {
      // Ignore close errors - client may have already disconnected
    } finally {
      if (pendingWrite != null &&
          identical(_responseWriteTails[res], pendingWrite)) {
        _responseWriteTails.remove(res);
      }
    }
  }

  Future<void> _safeCloseSocket(Socket socket) async {
    try {
      await socket.close().timeout(const Duration(milliseconds: 100));
    } catch (e) {
      socket.destroy();
    }
  }

  /// Writes an event to the SSE stream with proper formatting
  Future<bool> _writeSSEEvent(
    HttpResponse res,
    JsonRpcMessage message, [
    String? eventId,
  ]) async {
    try {
      return await _enqueueSseWrite(res, _encodeSSEEvent(message, eventId));
    } catch (e) {
      return false;
    }
  }

  Future<bool> _enqueueSseWrite(HttpResponse res, List<int> bytes) {
    final previousWrite = _responseWriteTails[res] ?? Future<void>.value();
    final writeCompleted = Completer<void>();
    final writeTail = writeCompleted.future;

    // Install the tail before awaiting the previous write. A client may react
    // as soon as bytes arrive, before the corresponding flush future completes.
    _responseWriteTails[res] = writeTail;
    return _performSseWrite(
      res,
      bytes,
      previousWrite: previousWrite,
      writeCompleted: writeCompleted,
      writeTail: writeTail,
    );
  }

  Future<bool> _performSseWrite(
    HttpResponse res,
    List<int> bytes, {
    required Future<void> previousWrite,
    required Completer<void> writeCompleted,
    required Future<void> writeTail,
  }) async {
    try {
      await previousWrite;
      res.add(bytes);
      await res.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      writeCompleted.complete();
      if (identical(_responseWriteTails[res], writeTail)) {
        _responseWriteTails.remove(res);
      }
    }
  }

  List<int> _encodeSSEEvent(
    JsonRpcMessage message, [
    String? eventId,
  ]) {
    var eventData = "event: message\n";
    // Include event ID if provided - this is important for resumability.
    if (eventId != null) {
      _validateSseEventId(eventId);
      eventData += "id: $eventId\n";
    }
    eventData += "data: ${jsonEncode(message.toJson())}\n\n";
    return utf8.encode(eventData);
  }

  Future<Socket> _detachSseSocket(
    HttpRequest req,
    Map<String, String> headers,
  ) async {
    final response = await _detachHttpResponse(req);
    try {
      await _writeDetachedResponseHead(
        response,
        statusCode: HttpStatus.ok,
        headers: headers,
      );
    } catch (_) {
      response.socket.destroy();
      rethrow;
    }
    return response.socket;
  }

  Future<_DetachedHttpResponse> _detachHttpResponse(HttpRequest req) async {
    final responseHeaders = <String, List<String>>{};
    req.response.headers.forEach((name, values) {
      final normalizedName = name.toLowerCase();
      if (normalizedName == HttpHeaders.contentLengthHeader ||
          normalizedName == HttpHeaders.transferEncodingHeader ||
          normalizedName == HttpHeaders.connectionHeader) {
        return;
      }
      responseHeaders[normalizedName] = List<String>.of(values);
    });
    final socket = await req.response.detachSocket(writeHeaders: false);
    return _DetachedHttpResponse(
      socket: socket,
      headers: responseHeaders,
    );
  }

  Future<void> _writeDetachedResponseHead(
    _DetachedHttpResponse response, {
    required int statusCode,
    Map<String, String> headers = const {},
    int? contentLength,
    List<int> body = const [],
  }) async {
    final responseHeaders = <String, List<String>>{
      for (final entry in response.headers.entries)
        entry.key: List<String>.of(entry.value),
    };
    for (final entry in headers.entries) {
      responseHeaders[entry.key.toLowerCase()] = [entry.value];
    }
    if (contentLength != null) {
      responseHeaders[HttpHeaders.contentLengthHeader] = ['$contentLength'];
    }
    responseHeaders[HttpHeaders.connectionHeader] = const ['close'];

    final reasonPhrase = switch (statusCode) {
      HttpStatus.ok => 'OK',
      HttpStatus.badRequest => 'Bad Request',
      HttpStatus.notFound => 'Not Found',
      _ => 'Status',
    };
    final responseHead = StringBuffer(
      'HTTP/1.1 $statusCode $reasonPhrase\r\n',
    );
    responseHeaders.forEach((key, values) {
      for (final value in values) {
        responseHead.write('$key: $value\r\n');
      }
    });
    responseHead.write('\r\n');
    response.socket.add(utf8.encode(responseHead.toString()));
    if (body.isNotEmpty) {
      response.socket.add(body);
    }
    await response.socket.flush();
  }

  Future<void> _writeDetachedJsonResponse(
    _DetachedHttpResponse response, {
    required int statusCode,
    required Map<String, String> headers,
    required List<int> body,
  }) async {
    try {
      await _writeDetachedResponseHead(
        response,
        statusCode: statusCode,
        headers: headers,
        contentLength: body.length,
        body: body,
      );
    } catch (_) {
      // The client can close the response stream at any time.
    } finally {
      await _safeCloseSocket(response.socket);
    }
  }

  Future<bool> _writeSSEEventToSocket(
    Socket socket,
    JsonRpcMessage message,
  ) async {
    try {
      var eventData = "event: message\n";
      eventData += "data: ${jsonEncode(message.toJson())}\n\n";

      socket.add(utf8.encode(eventData));
      await socket.flush();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _writeSSEPrimingEvent(
    HttpResponse res,
    EventId eventId,
  ) async {
    try {
      return await _enqueueSseWrite(res, _encodeSSEPrimingEvent(eventId));
    } catch (e) {
      return false;
    }
  }

  List<int> _encodeSSEPrimingEvent(EventId eventId) {
    _validateSseEventId(eventId);
    return utf8.encode(
      'id: $eventId\n'
      'retry: ${_sseRetryDelay.inMilliseconds}\n'
      'data:\n\n',
    );
  }

  Future<bool> _writeSSECommentToSocket(Socket socket) async {
    try {
      socket.add(utf8.encode(':\n\n'));
      await socket.flush();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _primeSseStream(StreamId streamId, HttpResponse res) async {
    try {
      final store = _eventStore;
      if (store == null) {
        return _enqueueSseWrite(res, const <int>[]);
      }

      final eventId = await store.storeEvent(streamId, _ssePrimingMessage);
      _validateSseEventId(eventId);
      final sent = await _writeSSEPrimingEvent(res, eventId);
      if (!sent) {
        onerror?.call(StateError('Failed to send initial SSE event ID'));
      }
      return sent;
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(StateError(error.toString()));
      }
      return false;
    }
  }

  Future<bool> _primeSseSocket(Socket socket) async {
    final sent = await _writeSSECommentToSocket(socket);
    if (!sent) {
      onerror?.call(StateError('Failed to send initial SSE comment'));
    }
    return sent;
  }

  /// Handles unsupported requests (PUT, PATCH, etc.)
  Future<void> _handleUnsupportedRequest(HttpResponse res) async {
    res.headers.set(HttpHeaders.allowHeader, "GET, POST, DELETE");
    await _writeJsonRpcErrorResponse(
      res,
      httpStatus: HttpStatus.methodNotAllowed,
      errorCode: ErrorCode.connectionClosed,
      message: 'Method not allowed.',
    );
  }

  Future<void> _handleStatelessUnsupportedRequest(HttpResponse res) async {
    res.headers.set(HttpHeaders.allowHeader, "POST");
    await _writeJsonRpcErrorResponse(
      res,
      httpStatus: HttpStatus.methodNotAllowed,
      errorCode: ErrorCode.connectionClosed,
      message: 'Method not allowed for stateless MCP requests.',
    );
  }

  /// Handles POST requests containing JSON-RPC messages
  Future<void> _handlePostRequest(
    HttpRequest req, [
    dynamic parsedBody,
    bool abortIfClosed = true,
  ]) async {
    var jsonParsed = parsedBody != null;
    var parsedRequestId = _requestIdFromParsedBody(parsedBody);
    try {
      // Validate the Accept header
      final acceptedMediaTypes = _parseAcceptedMediaTypes(req);
      // The client MUST include an Accept header, listing both application/json and text/event-stream as supported content types.
      if (!_acceptsMediaType(acceptedMediaTypes, 'application/json') ||
          !_acceptsMediaType(acceptedMediaTypes, 'text/event-stream')) {
        await _writeJsonRpcErrorResponse(
          req.response,
          httpStatus: HttpStatus.notAcceptable,
          errorCode: ErrorCode.connectionClosed,
          id: parsedRequestId,
          message:
              'Not Acceptable: Client must accept both application/json and text/event-stream',
        );
        return;
      }

      final contentType = req.headers.contentType?.value ?? '';
      if (!contentType.contains("application/json")) {
        await _writeJsonRpcErrorResponse(
          req.response,
          httpStatus: HttpStatus.unsupportedMediaType,
          errorCode: ErrorCode.connectionClosed,
          id: parsedRequestId,
          message:
              'Unsupported Media Type: Content-Type must be application/json',
        );
        return;
      }

      dynamic rawMessage;
      if (parsedBody != null) {
        rawMessage = parsedBody;
      } else {
        // Read and parse request body
        final bodyBytes = await _collectBytes(req);
        final bodyString = utf8.decode(bodyBytes);
        rawMessage = jsonDecode(bodyString);
      }
      jsonParsed = true;

      final List<dynamic> rawMessages;
      if (rawMessage is List) {
        if (_rejectBatchJsonRpcPayloads) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.badRequest,
            errorCode: ErrorCode.invalidRequest,
            message:
                'Invalid Request: Batch JSON-RPC payloads are not supported',
          );
          return;
        }
        rawMessages = rawMessage;
      } else if (rawMessage is Map) {
        rawMessages = [rawMessage];
      } else {
        await _writeJsonRpcErrorResponse(
          req.response,
          httpStatus: HttpStatus.badRequest,
          errorCode: ErrorCode.invalidRequest,
          message:
              'Invalid Request: POST body must contain a JSON-RPC message object',
        );
        return;
      }

      final List<JsonRpcMessage> messages = [];
      final List<Map<String, dynamic>> messageJsons = [];
      if (rawMessages.isEmpty) {
        await _writeJsonRpcErrorResponse(
          req.response,
          httpStatus: HttpStatus.badRequest,
          errorCode: ErrorCode.invalidRequest,
          message: 'Invalid Request: JSON-RPC payload must not be empty',
        );
        return;
      }

      for (final rawItem in rawMessages) {
        if (rawItem is! Map) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.badRequest,
            errorCode: ErrorCode.invalidRequest,
            message:
                'Invalid Request: each JSON-RPC message in the payload must be an object',
          );
          return;
        }

        try {
          final messageJson = rawItem is Map<String, dynamic>
              ? rawItem
              : rawItem.cast<String, dynamic>();
          final rawMetadataError = rawMessages.length == 1
              ? _rawStatelessRequestMetadataError(req, messageJson)
              : null;
          if (rawMetadataError != null) {
            await _writeJsonRpcErrorResponse(
              req.response,
              httpStatus: HttpStatus.badRequest,
              errorCode: ErrorCode.invalidParams,
              id: _rawRequestId(messageJson),
              message: rawMetadataError,
            );
            return;
          }
          final rawHeaderMismatch = rawMessages.length == 1
              ? _rawStatelessRequestHeaderMismatch(req, messageJson)
              : null;
          if (rawHeaderMismatch != null) {
            await _writeJsonRpcErrorResponse(
              req.response,
              httpStatus: HttpStatus.badRequest,
              errorCode: ErrorCode.headerMismatch,
              id: _rawRequestId(messageJson),
              message: 'Header mismatch: $rawHeaderMismatch',
            );
            return;
          }
          if (_isStatelessRemovedRequestJson(req, messageJson)) {
            final method = messageJson['method'] as String;
            await _writeJsonRpcErrorResponse(
              req.response,
              httpStatus: HttpStatus.notFound,
              errorCode: ErrorCode.methodNotFound,
              id: _rawRequestId(messageJson),
              message:
                  '$method is not part of MCP stateless protocol versions.',
            );
            return;
          }
          messageJsons.add(messageJson);
          messages.add(JsonRpcMessage.fromJson(messageJson));
        } catch (e) {
          final messageJson = rawItem is Map<String, dynamic>
              ? rawItem
              : rawItem.cast<String, dynamic>();
          final hasRequestEnvelope =
              _hasValidJsonRpcRequestEnvelope(messageJson);
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.badRequest,
            errorCode: hasRequestEnvelope
                ? ErrorCode.invalidParams
                : ErrorCode.invalidRequest,
            id: _rawRequestId(messageJson),
            message: hasRequestEnvelope ? 'Invalid params' : 'Invalid Request',
            data: e.toString(),
          );
          onerror?.call(e is Error ? e : StateError(e.toString()));
          return;
        }
      }

      final usesStatelessHttpValidation =
          _usesStatelessHttpValidation(req, messages);
      parsedRequestId = _singleRequestId(messages);
      if (!await _validateStatelessHttpHeaders(req, messages, messageJsons)) {
        return;
      }

      // Check if this is an initialization request
      // https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle/
      final isInitializationRequest = messages.any(_isInitializeRequest);
      final isStatelessRequest = messages.any(_isStatelessJsonRpcRequest);
      final isStatelessMessage =
          usesStatelessHttpValidation || isStatelessRequest;
      if (isInitializationRequest) {
        final requestSessionId = req.headers.value('mcp-session-id');

        // If it's a server with session management and the session ID is already set we should reject the request
        // to avoid re-initialization. A mismatched or terminated session ID means the client referenced a session
        // this transport cannot serve, so return the Streamable HTTP stale-session 404.
        if (_initialized && sessionId != null) {
          if (_terminated ||
              requestSessionId != null && requestSessionId != sessionId) {
            await _writeJsonRpcErrorResponse(
              req.response,
              httpStatus: HttpStatus.notFound,
              errorCode: ErrorCode.connectionClosed,
              id: parsedRequestId,
              message: 'Session not found',
            );
            return;
          }

          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.badRequest,
            errorCode: ErrorCode.invalidRequest,
            id: parsedRequestId,
            message: 'Invalid Request: Server already initialized',
          );
          return;
        }
        if (messages.length > 1) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.badRequest,
            errorCode: ErrorCode.invalidRequest,
            id: parsedRequestId,
            message:
                'Invalid Request: Only one initialization request is allowed',
          );
          return;
        }

        final generatedSessionId = _sessionIdGenerator?.call();
        if (generatedSessionId != null &&
            !_isValidSessionId(generatedSessionId)) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.internalServerError,
            errorCode: ErrorCode.internalError,
            id: parsedRequestId,
            message: 'Invalid session ID generated by server',
          );
          return;
        }

        if (requestSessionId != null &&
            generatedSessionId != null &&
            requestSessionId != generatedSessionId) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.notFound,
            errorCode: ErrorCode.connectionClosed,
            id: parsedRequestId,
            message: 'Session not found',
          );
          return;
        }

        sessionId = generatedSessionId;
        _initialized = true;

        // If we have a session ID and an onsessioninitialized handler, call it immediately
        // This is needed in cases where the server needs to keep track of multiple sessions
        if (sessionId != null && _onsessioninitialized != null) {
          _onsessioninitialized(sessionId!);
        }
      }

      // If an Mcp-Session-Id is returned by the server during initialization,
      // clients using the Streamable HTTP transport MUST include it
      // in the Mcp-Session-Id header on all of their subsequent HTTP requests.
      if (!isInitializationRequest &&
          !isStatelessMessage &&
          !await _validateSession(
            req,
            req.response,
            requestId: parsedRequestId,
          )) {
        return;
      }

      // Check if it contains requests
      final hasRequests = messages.any(_isJsonRpcRequest);

      if (abortIfClosed && _closed) {
        await _safeClose(req.response);
        return;
      }

      if (!hasRequests) {
        // If it only contains notifications or responses, return 202
        // Handle each message first to ensure processing
        for (final message in messages) {
          try {
            onmessage?.call(message);
          } catch (e) {
            // Don't let handler errors affect the response - message was received successfully
            onerror?.call(e is Error ? e : StateError(e.toString()));
          }
        }

        req.response.statusCode = HttpStatus.accepted;
        await _safeClose(req.response);
      } else if (hasRequests) {
        // The default behavior is to use SSE streaming
        // but in some cases server will return JSON responses
        final streamId = generateUUID();
        final requestRoutes =
            Map<JsonRpcRequest, _IncomingRequestRoute>.identity();
        final requiresSseResponse = messages.any(
          (message) =>
              message is JsonRpcRequest &&
              message.method == Method.subscriptionsListen,
        );
        final useJsonResponse = _enableJsonResponse && !requiresSseResponse;
        Socket? responseSocket;
        _DetachedHttpResponse? detachedJsonResponse;
        if (useJsonResponse && isStatelessRequest) {
          // HttpResponse.done does not observe a peer disconnect until Dart
          // starts the response. Detach before dispatch so stateless MCP can
          // treat closing a pending JSON response as request cancellation.
          detachedJsonResponse = await _detachHttpResponse(req);
        } else if (!useJsonResponse) {
          final headers = _sseResponseHeaders();

          // After initialization, always include the session ID if we have one
          if (sessionId != null && !isStatelessRequest) {
            headers["mcp-session-id"] = sessionId!;
          }

          if (isStatelessRequest) {
            responseSocket = await _detachSseSocket(req, headers);
          } else {
            req.response.statusCode = HttpStatus.ok;
            req.response.bufferOutput = false;
            headers.forEach((key, value) {
              req.response.headers.set(key, value);
            });
          }
        }

        if (abortIfClosed && _closed) {
          responseSocket?.destroy();
          detachedJsonResponse?.socket.destroy();
          await _safeClose(req.response);
          return;
        }

        // Store the response for this request to send messages back through this connection
        // We need to track by request ID to maintain the connection
        for (final message in messages) {
          if (_isJsonRpcRequest(message)) {
            final request = message as JsonRpcRequest;
            final route = _IncomingRequestRoute(
              requestId: request.id,
              streamId: streamId,
              stateless: _isStatelessJsonRpcRequest(request),
            );
            requestRoutes[request] = route;
            _registerRequestRoute(route);
            // Stateless request streams are never resumable, even when an
            // EventStore is configured for the transport. Retaining them here
            // would grow the replay-ownership set once per request.
            if (_eventStore != null && !route.stateless) {
              _ownedStreamIds.add(streamId);
            }
            if (detachedJsonResponse != null) {
              _detachedJsonResponses[streamId] = detachedJsonResponse;
            } else if (responseSocket == null) {
              _streamMapping[streamId] = req.response;
            } else {
              _responseStreamSockets[streamId] = responseSocket;
            }
          }
        }
        if (useJsonResponse) {
          _jsonResponseStreamIds.add(streamId);
          _pendingJsonResponseRequests[streamId] = req;
        }

        final ssePrimed = useJsonResponse ||
            (responseSocket == null
                ? await _primeSseStream(
                    streamId,
                    req.response,
                  )
                : await _primeSseSocket(
                    responseSocket,
                  ));
        if (!ssePrimed) {
          _streamMapping.remove(streamId);
          _responseStreamSockets.remove(streamId)?.destroy();
          _ownedStreamIds.remove(streamId);
          _jsonResponseStreamIds.remove(streamId);
          _pendingJsonResponseRequests.remove(streamId);
          _detachedJsonResponses.remove(streamId)?.socket.destroy();
          for (final route in requestRoutes.values) {
            _removeRequestRoute(route);
          }
          await _safeClose(req.response);
          return;
        }
        if (abortIfClosed && _closed) {
          _streamMapping.remove(streamId);
          _responseStreamSockets.remove(streamId)?.destroy();
          _ownedStreamIds.remove(streamId);
          _jsonResponseStreamIds.remove(streamId);
          _pendingJsonResponseRequests.remove(streamId);
          _detachedJsonResponses.remove(streamId)?.socket.destroy();
          for (final route in requestRoutes.values) {
            _removeRequestRoute(route);
          }
          await _safeClose(req.response);
          return;
        }

        var responseDoneHandled = false;
        void handleResponseDone({required bool fromDetachedSocket}) {
          if (!fromDetachedSocket &&
              _detachingJsonResponseStreamIds.contains(streamId)) {
            // detachSocket completes HttpResponse.done; the detached socket's
            // listener owns cleanup after the response switches to SSE.
            return;
          }
          if (responseDoneHandled) {
            return;
          }
          responseDoneHandled = true;
          try {
            _pendingJsonResponseRequests.remove(streamId);
            _detachedJsonResponses.remove(streamId);
            if (_jsonResponseStreamIds.remove(streamId)) {
              // A response that remained JSON never produced resumable SSE
              // events, so it must not retain replay ownership after either a
              // normal close or a client disconnect.
              _ownedStreamIds.remove(streamId);
              final relatedRoutes = _routesForStream(streamId);
              _notifyUnresolvedStatelessRequestCancellations(
                relatedRoutes,
                reason: 'JSON response stream closed by client',
              );
              _streamMapping.remove(streamId);
              for (final route in relatedRoutes) {
                _removeRequestRoute(route);
              }
            } else {
              _handleResponseStreamClosed(streamId);
            }
          } finally {
            _completeDetachedResponseLifecycle(streamId);
          }
        }

        // Set up close handler for client disconnects
        final disconnectSocket = responseSocket ?? detachedJsonResponse?.socket;
        Completer<void>? detachedResponseLifecycle;
        if (disconnectSocket == null) {
          req.response.done.then(
            (_) => handleResponseDone(fromDetachedSocket: false),
            onError: (Object _, StackTrace __) =>
                handleResponseDone(fromDetachedSocket: false),
          );
        } else {
          detachedResponseLifecycle = Completer<void>();
          _detachedResponseLifecycles[streamId] = detachedResponseLifecycle;
          try {
            disconnectSocket.listen(
              null,
              onDone: () => handleResponseDone(fromDetachedSocket: true),
              onError: (Object _, StackTrace __) =>
                  handleResponseDone(fromDetachedSocket: true),
              cancelOnError: true,
            );
          } catch (_) {
            _handleResponseStreamClosed(streamId);
            rethrow;
          }
        }

        // Handle each message
        for (final message in messages) {
          try {
            _deliverIncomingMessage(
              message,
              message is JsonRpcRequest ? requestRoutes[message] : null,
            );
          } catch (e) {
            // Don't let handler errors affect the response - message was received successfully
            onerror?.call(e is Error ? e : StateError(e.toString()));
          }
        }
        // The server SHOULD NOT close the SSE stream before sending all JSON-RPC responses
        // This will be handled by the send() method when responses are ready
        if (detachedResponseLifecycle != null) {
          await detachedResponseLifecycle.future;
        }
      }
    } catch (error) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus:
            jsonParsed ? HttpStatus.internalServerError : HttpStatus.badRequest,
        errorCode: jsonParsed ? ErrorCode.internalError : ErrorCode.parseError,
        id: parsedRequestId,
        message: jsonParsed ? 'Internal error' : 'Parse error',
        data: error.toString(),
      );

      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(StateError(error.toString()));
      }
    }
  }

  /// Collects all bytes from an HTTP request
  Future<Uint8List> _collectBytes(HttpRequest request) async {
    final completer = Completer<Uint8List>();
    final sink = BytesBuilder();

    request.listen(
      sink.add,
      onDone: () => completer.complete(sink.takeBytes()),
      onError: completer.completeError,
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Handles DELETE requests to terminate sessions
  Future<void> _handleDeleteRequest(HttpRequest req) async {
    if (!await _validateSession(req, req.response)) {
      return;
    }
    await close();
    req.response.statusCode = HttpStatus.ok;
    await _safeClose(req.response);
  }

  /// Validates session ID for non-initialization requests
  /// Returns true if the session is valid, false otherwise
  Future<bool> _validateSession(
    HttpRequest req,
    HttpResponse res, {
    RequestId? requestId,
  }) async {
    if (!_initialized) {
      // If the server has not been initialized yet, reject all requests
      await _writeJsonRpcErrorResponse(
        res,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.connectionClosed,
        id: requestId,
        message: 'Bad Request: Server not initialized',
      );
      return false;
    }

    if (sessionId == null) {
      // If the session ID is not set, the session management is disabled
      // and we don't need to validate the session ID
      return true;
    }

    final requestSessionId = req.headers.value("mcp-session-id");

    if (requestSessionId == null) {
      // Non-initialization requests without a session ID should return 400 Bad Request
      await _writeJsonRpcErrorResponse(
        res,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.connectionClosed,
        id: requestId,
        message: 'Bad Request: Mcp-Session-Id header is required',
      );
      return false;
    } else if (_terminated || requestSessionId != sessionId) {
      // Reject terminated or invalid session IDs with 404 Not Found.
      await _writeJsonRpcErrorResponse(
        res,
        httpStatus: HttpStatus.notFound,
        errorCode: ErrorCode.connectionClosed,
        id: requestId,
        message: 'Session not found',
      );
      return false;
    }

    return true;
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (sessionId != null) {
      _terminated = true;
    }

    // Close all SSE connections, including multiple standalone responses that
    // may share one replay stream identity.
    final responses = <HttpResponse>{
      ..._streamMapping.values,
      for (final streamResponses in _standaloneSseResponses.values)
        ...streamResponses,
    };
    for (final response in responses) {
      await _safeClose(response);
    }
    final sockets = _responseStreamSockets.values.toList();
    for (final socket in sockets) {
      await _safeCloseSocket(socket);
    }
    final detachedJsonResponses = _detachedJsonResponses.values.toList();
    for (final response in detachedJsonResponses) {
      await _safeCloseSocket(response.socket);
    }
    _responseStreamSockets.clear();
    _detachedJsonResponses.clear();
    _streamMapping.clear();
    _detachedResumableStreamIds.clear();
    _standaloneSseStreamIds.clear();
    _standaloneSseResponses.clear();
    _responseWriteTails.clear();
    _ownedStreamIds.clear();

    // Clear any pending responses
    _requestResponseMap.clear();
    _requestRoutesById.clear();
    _requestRoutesByStream.clear();
    _jsonResponseStreamIds.clear();
    _pendingJsonResponseRequests.clear();
    _jsonResponseToSseTransitions.clear();
    _detachingJsonResponseStreamIds.clear();
    final detachedResponseLifecycles =
        _detachedResponseLifecycles.values.toList();
    _detachedResponseLifecycles.clear();
    for (final lifecycle in detachedResponseLifecycles) {
      if (!lifecycle.isCompleted) {
        lifecycle.complete();
      }
    }
    onclose?.call();
  }

  Future<void> _ensureJsonResponseStreamUsesSse(
    _IncomingRequestRoute route,
  ) async {
    final streamId = route.streamId;
    final existingTransition = _jsonResponseToSseTransitions[streamId];
    if (existingTransition != null) {
      await existingTransition;
      return;
    }

    final transition = _promoteJsonResponseStreamToSse(route);
    _jsonResponseToSseTransitions[streamId] = transition;
    try {
      await transition;
    } finally {
      if (identical(_jsonResponseToSseTransitions[streamId], transition)) {
        _jsonResponseToSseTransitions.remove(streamId);
      }
    }
  }

  Future<void> _promoteJsonResponseStreamToSse(
    _IncomingRequestRoute route,
  ) async {
    final streamId = route.streamId;
    if (!_jsonResponseStreamIds.contains(streamId)) {
      return;
    }
    final request = _pendingJsonResponseRequests[streamId];
    if (request == null) {
      throw StateError(
        'Cannot switch JSON response stream $streamId to SSE: request is no '
        'longer active.',
      );
    }

    final headers = _sseResponseHeaders();
    if (sessionId != null && !route.stateless) {
      headers['mcp-session-id'] = sessionId!;
    }

    if (route.stateless) {
      _detachingJsonResponseStreamIds.add(streamId);
      try {
        final detachedResponse = _detachedJsonResponses.remove(streamId);
        final Socket socket;
        if (detachedResponse == null) {
          socket = await _detachSseSocket(request, headers);
        } else {
          socket = detachedResponse.socket;
        }
        _responseStreamSockets[streamId] = socket;
        _streamMapping.remove(streamId);
        _jsonResponseStreamIds.remove(streamId);
        _pendingJsonResponseRequests.remove(streamId);
        if (detachedResponse != null) {
          await _writeDetachedResponseHead(
            detachedResponse,
            statusCode: HttpStatus.ok,
            headers: headers,
          );
        } else {
          socket.listen(
            null,
            onDone: () => _handleResponseStreamClosed(streamId),
            onError: (Object _, StackTrace __) =>
                _handleResponseStreamClosed(streamId),
            cancelOnError: true,
          );
        }
        if (!await _primeSseSocket(socket)) {
          throw StateError('Failed to initialize promoted SSE response stream');
        }
      } catch (_) {
        _handleResponseStreamClosed(streamId);
        rethrow;
      } finally {
        _detachingJsonResponseStreamIds.remove(streamId);
      }
      return;
    }

    final response = _streamMapping[streamId];
    if (response == null) {
      throw StateError(
        'Cannot switch JSON response stream $streamId to SSE: response is no '
        'longer active.',
      );
    }
    response
      ..statusCode = HttpStatus.ok
      ..bufferOutput = false;
    headers.forEach(response.headers.set);
    _jsonResponseStreamIds.remove(streamId);
    _pendingJsonResponseRequests.remove(streamId);
    if (!await _primeSseStream(streamId, response)) {
      throw StateError('Failed to initialize promoted SSE response stream');
    }
  }

  @override
  Future<void> send(JsonRpcMessage message, {dynamic relatedRequestId}) {
    return sendWithRequestId(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) =>
      _sendWithRequestContext(
        message,
        relatedRequestId: relatedRequestId,
        requestContext: incomingRequestContext,
      );

  @override
  Future<void> sendWithRequestContext(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
    required Object requestContext,
  }) =>
      _sendWithRequestContext(
        message,
        relatedRequestId: relatedRequestId,
        requestContext: requestContext,
      );

  Future<void> _sendWithRequestContext(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
    Object? requestContext,
  }) async {
    dynamic requestId = relatedRequestId;
    if (_isJsonRpcResponse(message) || _isJsonRpcError(message)) {
      // If the message is a response, use the request ID from the message
      requestId = _getMessageId(message);
    }

    // Check if this message should be sent on the standalone SSE stream (no request ID)
    // Ignore notifications from tools (which have relatedRequestId set)
    // Those will be sent via dedicated response SSE streams
    if (requestId == null) {
      // For standalone SSE streams, we can only send requests and notifications
      if (_isJsonRpcResponse(message) || _isJsonRpcError(message)) {
        throw StateError(
          "Cannot send a response on a standalone SSE stream unless resuming a previous client request",
        );
      }

      if (_standaloneSseStreamIds.isEmpty) {
        // The spec says the server MAY send messages on the stream, so it's ok to discard if no stream
        return;
      }

      while (true) {
        final target = _selectStandaloneSseTarget();
        if (target == null) {
          return;
        }

        // Generate and store a stream-specific event ID if event store is provided.
        String? eventId;
        if (_eventStore != null) {
          eventId = await _eventStore.storeEvent(target.key, message);
        }

        final sent = await _writeSSEEvent(target.value, message, eventId);
        if (sent) {
          return;
        }

        _removeStandaloneSseResponse(target.key, target.value);
      }
    }

    final route = _resolveRequestRoute(
      requestId as RequestId,
      requestContext: requestContext,
    );
    if (route == null) {
      throw StateError("No connection established for request ID: $requestId");
    }
    if (message is JsonRpcRequest && route.stateless) {
      throw StateError(
        "Cannot send JSON-RPC requests on stateless MCP response streams; "
        "return an InputRequiredResult for client input instead.",
      );
    }

    final streamId = route.streamId;
    var response = _streamMapping[streamId];
    var responseSocket = _responseStreamSockets[streamId];
    var detachedJsonResponse = _detachedJsonResponses[streamId];
    final isStatelessRequestStream = route.stateless;
    var useJsonResponse = _jsonResponseStreamIds.contains(streamId);

    if (useJsonResponse &&
        !_isJsonRpcResponse(message) &&
        !_isJsonRpcError(message)) {
      await _ensureJsonResponseStreamUsesSse(route);
      response = _streamMapping[streamId];
      responseSocket = _responseStreamSockets[streamId];
      detachedJsonResponse = null;
      useJsonResponse = false;
    }

    if (!useJsonResponse) {
      if (response == null && responseSocket == null) {
        if (isStatelessRequestStream) {
          _handleResponseStreamClosed(streamId);
          return;
        }
      }

      // For SSE responses, generate event ID if event store is provided
      String? eventId;

      if (_eventStore != null && !isStatelessRequestStream) {
        eventId = await _eventStore.storeEvent(streamId, message);
        response = _streamMapping[streamId];
      }

      if (responseSocket != null) {
        final sent = await _writeSSEEventToSocket(
          responseSocket,
          message,
        );
        if (!sent && isStatelessRequestStream) {
          _handleResponseStreamClosed(streamId);
          return;
        }
      } else if (response != null) {
        // Write the event to the response stream
        final sent = await _writeSSEEvent(response, message, eventId);
        if (!sent && isStatelessRequestStream) {
          _handleResponseStreamClosed(streamId);
          return;
        }
      }
    }

    if (_isJsonRpcResponse(message) || _isJsonRpcError(message)) {
      if (!_isActiveRequestRoute(route)) {
        return;
      }

      _requestResponseMap[route] = message;
      final relatedRoutes = _routesForStream(streamId);

      // Check if we have responses for all requests using this connection
      final allResponsesReady = relatedRoutes.every(
        _requestResponseMap.containsKey,
      );

      if (allResponsesReady) {
        if (response == null &&
            responseSocket == null &&
            detachedJsonResponse == null) {
          if (!_detachedResumableStreamIds.contains(streamId)) {
            throw StateError(
              "No connection established for request ID: $requestId",
            );
          }

          for (final relatedRoute in relatedRoutes) {
            _removeRequestRoute(relatedRoute);
          }
          _detachedResumableStreamIds.remove(streamId);
          _jsonResponseStreamIds.remove(streamId);
          return;
        }

        if (useJsonResponse) {
          // All responses ready, send as JSON
          final headers = {
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          };
          var statusCode = HttpStatus.ok;

          final isStatelessResponse = relatedRoutes.any(
            (relatedRoute) => relatedRoute.stateless,
          );
          if (sessionId != null && !isStatelessResponse) {
            headers['mcp-session-id'] = sessionId!;
          }

          final responses = relatedRoutes
              .map((relatedRoute) => _requestResponseMap[relatedRoute]!)
              .toList();

          if (isStatelessResponse &&
              responses.length == 1 &&
              responses.single is JsonRpcError) {
            final error = responses.single as JsonRpcError;
            statusCode = _statelessHttpStatusForErrorCode(error.error.code);
          }

          final body = utf8.encode(
            jsonEncode(
              responses.length == 1
                  ? responses[0].toJson()
                  : responses.map((response) => response.toJson()).toList(),
            ),
          );
          if (detachedJsonResponse != null) {
            await _writeDetachedJsonResponse(
              detachedJsonResponse,
              statusCode: statusCode,
              headers: headers,
              body: body,
            );
          } else {
            response!.statusCode = statusCode;
            headers.forEach(response.headers.set);
            response.add(body);
            await _safeClose(response);
          }
        } else if (responseSocket != null) {
          await _safeCloseSocket(responseSocket);
        } else {
          // End the SSE stream
          await _safeClose(response!);
        }

        // Clean up
        _responseStreamSockets.remove(streamId);
        _detachedResumableStreamIds.remove(streamId);
        _jsonResponseStreamIds.remove(streamId);
        if (useJsonResponse) {
          _ownedStreamIds.remove(streamId);
        }
        _pendingJsonResponseRequests.remove(streamId);
        _detachedJsonResponses.remove(streamId);
        for (final relatedRoute in relatedRoutes) {
          _removeRequestRoute(relatedRoute);
        }
      }
    }
  }

  void _handleResponseStreamClosed(StreamId streamId) {
    try {
      _responseStreamSockets.remove(streamId)?.destroy();
      final relatedRoutes = _routesForStream(streamId);

      _streamMapping.remove(streamId);
      _jsonResponseStreamIds.remove(streamId);
      _pendingJsonResponseRequests.remove(streamId);
      _detachedJsonResponses.remove(streamId);

      final statelessRoutes =
          relatedRoutes.where((route) => route.stateless).toList();
      final resumableRoutes =
          relatedRoutes.where((route) => !route.stateless).toList();
      if (_eventStore != null && resumableRoutes.isNotEmpty) {
        _detachedResumableStreamIds.add(streamId);
      } else {
        for (final route in resumableRoutes) {
          _removeRequestRoute(route);
        }
      }
      if (statelessRoutes.isEmpty) {
        return;
      }

      _notifyUnresolvedStatelessRequestCancellations(
        statelessRoutes,
        reason: 'SSE response stream closed by client',
      );

      for (final route in statelessRoutes) {
        _removeRequestRoute(route);
      }
    } finally {
      _completeDetachedResponseLifecycle(streamId);
    }
  }

  void _notifyUnresolvedStatelessRequestCancellations(
    Iterable<_IncomingRequestRoute> routes, {
    required String reason,
  }) {
    for (final route in routes) {
      if (_requestResponseMap.containsKey(route)) {
        continue;
      }

      try {
        _deliverIncomingMessage(
          JsonRpcCancelledNotification(
            cancelParams: CancelledNotification(
              requestId: route.requestId,
              reason: reason,
            ),
          ),
          route,
        );
      } catch (error) {
        onerror?.call(
          error is Error ? error : StateError(error.toString()),
        );
      }
    }
  }

  /// Checks if a message is an initialize request
  bool _isInitializeRequest(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.method == Method.initialize;
    }
    return false;
  }

  /// Checks if a message uses stateless MCP `2026-07-28` metadata.
  bool _isStatelessJsonRpcRequest(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      final version = message.meta?[McpMetaKey.protocolVersion];
      return version is String && isStatelessProtocolVersion(version);
    }
    return false;
  }

  /// Checks if a message is a JSON-RPC request
  bool _isJsonRpcRequest(JsonRpcMessage message) {
    return message is JsonRpcRequest;
  }

  /// Checks if a message is a JSON-RPC response
  bool _isJsonRpcResponse(JsonRpcMessage message) {
    return message is JsonRpcResponse;
  }

  /// Checks if a message is a JSON-RPC error
  bool _isJsonRpcError(JsonRpcMessage message) {
    return message is JsonRpcError;
  }

  /// Gets the ID from a JSON-RPC message
  dynamic _getMessageId(JsonRpcMessage message) {
    if (message is JsonRpcResponse) {
      return message.id;
    } else if (message is JsonRpcError) {
      return message.id;
    }
    return null;
  }
}

enum _McpParamHeaderValidationError { name, value }

class _McpParamHeader {
  final String name;
  final String suffix;
  final String? value;
  final _McpParamHeaderValidationError? validationError;

  const _McpParamHeader({
    required this.name,
    required this.suffix,
    required String this.value,
  }) : validationError = null;

  const _McpParamHeader.invalidName({
    required this.name,
    required this.suffix,
  })  : value = null,
        validationError = _McpParamHeaderValidationError.name;

  const _McpParamHeader.invalidValue({
    required this.name,
    required this.suffix,
  })  : value = null,
        validationError = _McpParamHeaderValidationError.value;
}
