import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/uuid.dart';

import '../shared/transport.dart';
import '../types.dart';
import 'dns_rebinding_protection.dart';

const int _maxSafeHeaderInteger = 9007199254740991;
const int _minSafeHeaderInteger = -9007199254740991;

/// ID for SSE streams
typedef StreamId = String;

/// ID for events in SSE streams
typedef EventId = String;

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
  });
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
        IncomingRequestValidationAwareTransport,
        ToolParameterHeaderAwareTransport {
  // when sessionId is not set (null), it means the transport is in stateless mode
  final String? Function()? _sessionIdGenerator;
  bool _started = false;
  final Map<String, HttpResponse> _streamMapping = {};
  final Set<StreamId> _standaloneSseStreamIds = {};
  final Map<StreamId, Set<HttpResponse>> _standaloneSseResponses = {};
  final Set<StreamId> _ownedStreamIds = {};
  final Map<dynamic, String> _requestToStreamMapping = {};
  final Map<dynamic, JsonRpcMessage> _requestResponseMap = {};
  final Set<dynamic> _statelessRequestIds = {};
  final Map<StreamId, Socket> _responseStreamSockets = {};
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
  ToolParameterHeaderMappings _toolParameterHeaderMappings = const {};
  McpError? Function(JsonRpcRequest request)? _incomingRequestValidator;
  bool Function(String method)? _isRequestMethodSupported;
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
        _maxReplayedEvents = options.maxReplayedEvents;

  /// Starts the transport. This is required by the Transport interface but is a no-op
  /// for the Streamable HTTP transport as connections are managed per-request.
  @override
  Future<void> start() async {
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

  /// Handles an incoming HTTP request, whether GET or POST
  Future<void> handleRequest(HttpRequest req, [dynamic parsedBody]) async {
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

    if (!await _validateProtocolVersionHeader(req, req.response)) {
      return;
    }

    if (req.method == "POST") {
      await _handlePostRequest(req, parsedBody);
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
    HttpResponse res,
  ) async {
    if (!_strictProtocolVersionHeaderValidation) {
      return true;
    }

    final versionHeader = req.headers.value('mcp-protocol-version');
    if (versionHeader == null || versionHeader.trim().isEmpty) {
      return true;
    }

    final requestedVersion = versionHeader.trim();
    if (supportedProtocolVersionsWithDraft.contains(requestedVersion)) {
      return true;
    }

    await _writeJsonRpcErrorResponse(
      res,
      httpStatus: HttpStatus.badRequest,
      errorCode: ErrorCode.unsupportedProtocolVersion,
      message: 'Unsupported protocol version',
      data: {
        'requested': requestedVersion,
        'supported': supportedProtocolVersionsWithDraft,
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

  String? _requiredNameHeaderValue(JsonRpcMessage message) {
    final method = _messageMethod(message);
    final params = _messageParams(message);
    if (params == null) {
      return null;
    }

    final value = switch (method) {
      Method.toolsCall => params['name'],
      Method.resourcesRead => params['uri'],
      Method.promptsGet => params['name'],
      Method.tasksCancel ||
      Method.tasksGet ||
      Method.tasksUpdate =>
        params['taskId'],
      _ => null,
    };
    return value is String ? value : null;
  }

  String? _decodeMcpParamHeaderValue(String value) {
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
    final integer = _safeHeaderInteger(value);
    if (integer != null) {
      return integer.toString();
    }

    return switch (value) {
      null => null,
      String() => value,
      bool() => value.toString(),
      _ => null,
    };
  }

  int? _safeHeaderInteger(Object? value) {
    if (value is int) {
      if (value < _minSafeHeaderInteger || value > _maxSafeHeaderInteger) {
        return null;
      }
      return value;
    }

    if (value is double &&
        value.isFinite &&
        value.truncateToDouble() == value &&
        value >= _minSafeHeaderInteger &&
        value <= _maxSafeHeaderInteger) {
      return value.toInt();
    }

    return null;
  }

  bool _headerValueMatchesPrimitive(Object? bodyValue, String headerValue) {
    final integer = _safeHeaderInteger(bodyValue);
    if (integer != null) {
      final headerInteger = _safeHeaderInteger(num.tryParse(headerValue));
      return headerInteger != null && headerInteger == integer;
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
    final headers = <String, _McpParamHeader>{};
    req.headers.forEach((name, values) {
      const prefix = 'mcp-param-';
      final lowerName = name.toLowerCase();
      if (!lowerName.startsWith(prefix)) {
        return;
      }

      final headerSuffix = name.substring(prefix.length);
      if (headerSuffix.isEmpty ||
          !headerSuffix.codeUnits.every(
            (unit) => unit >= 0x21 && unit <= 0x7E && unit != 0x3A,
          )) {
        headers[lowerName] = _McpParamHeader.invalidName(
          name: name,
          suffix: headerSuffix,
        );
        return;
      }

      final headerValue = req.headers.value(name);
      final decodedValue =
          headerValue == null ? null : _decodeMcpParamHeaderValue(headerValue);
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

    final params = _messageParams(message);
    final arguments = params?['arguments'];
    if (arguments is! Map) {
      if (headers.isEmpty) {
        return true;
      }
      await _writeHeaderMismatchResponse(
        res,
        message,
        '${headers.values.first.name} header has no matching body arguments',
      );
      return false;
    }

    final argumentMap = arguments.cast<String, dynamic>();
    final consumedHeaders = <String>{};
    final toolName = _toolName(message);
    final headerMappings =
        toolName == null ? null : _toolParameterHeaderMappings[toolName];

    if (headerMappings != null) {
      for (final entry in headerMappings.entries) {
        final argumentName = entry.key;
        final headerSuffix = entry.value;
        final header = headers[headerSuffix.toLowerCase()];
        final argument = _toolParameterHeaderArgument(argumentMap, entry.key);
        final hasArgument = argument.exists;
        final bodyArgument = argument.value;
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

        consumedHeaders.add(header.suffix.toLowerCase());
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
    }

    final argumentNamesByLowercase = <String, String>{};
    for (final argumentName in argumentMap.keys) {
      argumentNamesByLowercase.putIfAbsent(
        argumentName.toLowerCase(),
        () => argumentName,
      );
    }

    for (final header in headers.values) {
      if (consumedHeaders.contains(header.suffix.toLowerCase())) {
        continue;
      }

      final argumentName = argumentMap.containsKey(header.suffix)
          ? header.suffix
          : argumentNamesByLowercase[header.suffix.toLowerCase()];
      if (argumentName == null) {
        await _writeHeaderMismatchResponse(
          res,
          message,
          '${header.name} header has no matching body argument',
        );
        return false;
      }

      final bodyArgument = argumentMap[argumentName];
      if (!_headerValueMatchesPrimitive(bodyArgument, header.value!)) {
        await _writeHeaderMismatchResponse(
          res,
          message,
          "${header.name} header value does not match body argument '$argumentName'",
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

    final metadataVersion = _metadataProtocolVersion(message);
    if (metadataVersion == null) {
      await _writeHeaderMismatchResponse(
        req.response,
        message,
        'MCP-Protocol-Version header has no matching request _meta protocol version',
      );
      return false;
    }
    if (protocolHeader != metadataVersion) {
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
    if (methodHeader == null || methodHeader.isEmpty) {
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

    final requiredName = _requiredNameHeaderValue(message);
    if (requiredName != null) {
      final nameHeader = req.headers.value('mcp-name');
      if (nameHeader == null || nameHeader.isEmpty) {
        await _writeHeaderMismatchResponse(
          req.response,
          message,
          'Mcp-Name header is required',
        );
        return false;
      }
      if (nameHeader != requiredName) {
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
    _ownedStreamIds.add(streamId);
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
      req.response
        ..statusCode = HttpStatus.notAcceptable
        ..write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message: 'Not Acceptable: Client must accept text/event-stream',
              ),
            ).toJson(),
          ),
        );
      await _safeClose(req.response);
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
    final headers = {
      HttpHeaders.contentTypeHeader: "text/event-stream; charset=utf-8",
      HttpHeaders.cacheControlHeader: "no-cache, no-transform",
      HttpHeaders.connectionHeader: "keep-alive",
    };

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
      final streamId = await _eventStore!.replayEventsAfter(
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

      final headers = {
        HttpHeaders.contentTypeHeader: "text/event-stream; charset=utf-8",
        HttpHeaders.cacheControlHeader: "no-cache, no-transform",
        HttpHeaders.connectionHeader: "keep-alive",
      };

      if (sessionId != null) {
        headers["mcp-session-id"] = sessionId!;
      }

      res.statusCode = HttpStatus.ok;
      headers.forEach((key, value) {
        res.headers.set(key, value);
      });
      await res.flush();

      for (final event in replayedEvents) {
        if (!await _writeSSEEvent(res, event.message, event.eventId)) {
          onerror?.call(StateError("Failed to replay events"));
          await _safeClose(res);
          return;
        }
      }

      if (!await _primeSseStream(streamId, res)) {
        await _safeClose(res);
        return;
      }

      if (_isStandaloneSseStreamId(streamId)) {
        _addStandaloneSseResponse(streamId, res);
      } else {
        _streamMapping[streamId] = res;
      }
      res.done.then((_) {
        if (_isStandaloneSseStreamId(streamId)) {
          _removeStandaloneSseResponse(streamId, res);
        } else if (identical(_streamMapping[streamId], res)) {
          _streamMapping.remove(streamId);
        }
      });
    } catch (error) {
      onerror?.call(error is Error ? error : StateError(error.toString()));
      final errorStr = error.toString().toLowerCase();
      final isNotFound =
          errorStr.contains('not found') || errorStr.contains('unknown');
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
    try {
      await res.close().timeout(const Duration(milliseconds: 100));
    } catch (e) {
      // Ignore close errors - client may have already disconnected
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
      var eventData = "event: message\n";
      // Include event ID if provided - this is important for resumability
      if (eventId != null) {
        _validateSseEventId(eventId);
        eventData += "id: $eventId\n";
      }
      eventData += "data: ${jsonEncode(message.toJson())}\n\n";

      res.add(utf8.encode(eventData));
      await res.flush();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Socket> _detachSseSocket(
    HttpRequest req,
    Map<String, String> headers,
  ) async {
    final socket = await req.response.detachSocket(writeHeaders: false);
    final responseHeaders = {
      ...headers,
      HttpHeaders.connectionHeader: 'close',
    };
    final responseHead = StringBuffer('HTTP/1.1 200 OK\r\n');
    responseHeaders.forEach((key, value) {
      responseHead.write('$key: $value\r\n');
    });
    responseHead.write('\r\n');
    socket.add(utf8.encode(responseHead.toString()));
    await socket.flush();
    return socket;
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
      _validateSseEventId(eventId);
      res.add(utf8.encode('id: $eventId\ndata:\n\n'));
      await res.flush();
      return true;
    } catch (e) {
      return false;
    }
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
        await res.flush();
        return true;
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
    res.statusCode = HttpStatus.methodNotAllowed;
    res.headers.set(HttpHeaders.allowHeader, "GET, POST, DELETE");
    res.write(
      jsonEncode(
        JsonRpcError(
          id: null,
          error: JsonRpcErrorData(
            code: ErrorCode.connectionClosed.value,
            message: 'Method not allowed.',
          ),
        ).toJson(),
      ),
    );
    await _safeClose(res);
  }

  Future<void> _handleStatelessUnsupportedRequest(HttpResponse res) async {
    res.statusCode = HttpStatus.methodNotAllowed;
    res.headers.set(HttpHeaders.allowHeader, "POST");
    res.write(
      jsonEncode(
        JsonRpcError(
          id: null,
          error: JsonRpcErrorData(
            code: ErrorCode.connectionClosed.value,
            message: 'Method not allowed for stateless MCP requests.',
          ),
        ).toJson(),
      ),
    );
    await _safeClose(res);
  }

  /// Handles POST requests containing JSON-RPC messages
  Future<void> _handlePostRequest(HttpRequest req, [dynamic parsedBody]) async {
    try {
      // Validate the Accept header
      final acceptedMediaTypes = _parseAcceptedMediaTypes(req);
      // The client MUST include an Accept header, listing both application/json and text/event-stream as supported content types.
      if (!_acceptsMediaType(acceptedMediaTypes, 'application/json') ||
          !_acceptsMediaType(acceptedMediaTypes, 'text/event-stream')) {
        req.response.statusCode = HttpStatus.notAcceptable;
        req.response.write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message:
                    'Not Acceptable: Client must accept both application/json and text/event-stream',
              ),
            ).toJson(),
          ),
        );
        await _safeClose(req.response);
        return;
      }

      final contentType = req.headers.contentType?.value ?? '';
      if (!contentType.contains("application/json")) {
        req.response.statusCode = HttpStatus.unsupportedMediaType;
        req.response.write(
          jsonEncode(
            JsonRpcError(
              id: null,
              error: JsonRpcErrorData(
                code: ErrorCode.connectionClosed.value,
                message:
                    'Unsupported Media Type: Content-Type must be application/json',
              ),
            ).toJson(),
          ),
        );
        await _safeClose(req.response);
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
          messages.add(JsonRpcMessage.fromJson(messageJson));
        } catch (e) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.badRequest,
            errorCode: ErrorCode.parseError,
            message: 'Parse error',
            data: e.toString(),
          );
          onerror?.call(e is Error ? e : StateError(e.toString()));
          return;
        }
      }

      if (!await _validateStatelessHttpHeaders(req, messages)) {
        return;
      }

      // Check if this is an initialization request
      // https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle/
      final isInitializationRequest = messages.any(_isInitializeRequest);
      final isStatelessRequest = messages.any(_isStatelessJsonRpcRequest);
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
              message: 'Session not found',
            );
            return;
          }

          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(
            jsonEncode(
              JsonRpcError(
                id: null,
                error: JsonRpcErrorData(
                  code: ErrorCode.invalidRequest.value,
                  message: 'Invalid Request: Server already initialized',
                ),
              ).toJson(),
            ),
          );
          await _safeClose(req.response);
          return;
        }
        if (messages.length > 1) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(
            jsonEncode(
              JsonRpcError(
                id: null,
                error: JsonRpcErrorData(
                  code: ErrorCode.invalidRequest.value,
                  message:
                      'Invalid Request: Only one initialization request is allowed',
                ),
              ).toJson(),
            ),
          );
          await _safeClose(req.response);
          return;
        }

        final generatedSessionId = _sessionIdGenerator?.call();
        if (generatedSessionId != null &&
            !_isValidSessionId(generatedSessionId)) {
          await _writeJsonRpcErrorResponse(
            req.response,
            httpStatus: HttpStatus.internalServerError,
            errorCode: ErrorCode.internalError,
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
            message: 'Session not found',
          );
          return;
        }

        sessionId = generatedSessionId;
        _initialized = true;

        // If we have a session ID and an onsessioninitialized handler, call it immediately
        // This is needed in cases where the server needs to keep track of multiple sessions
        if (sessionId != null && _onsessioninitialized != null) {
          _onsessioninitialized!(sessionId!);
        }
      }

      // If an Mcp-Session-Id is returned by the server during initialization,
      // clients using the Streamable HTTP transport MUST include it
      // in the Mcp-Session-Id header on all of their subsequent HTTP requests.
      if (!isInitializationRequest &&
          !isStatelessRequest &&
          !await _validateSession(req, req.response)) {
        return;
      }

      // Check if it contains requests
      final hasRequests = messages.any(_isJsonRpcRequest);

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
        Socket? responseSocket;
        if (!_enableJsonResponse) {
          final headers = {
            HttpHeaders.contentTypeHeader: "text/event-stream; charset=utf-8",
            HttpHeaders.cacheControlHeader: "no-cache",
            HttpHeaders.connectionHeader: "keep-alive",
          };

          // After initialization, always include the session ID if we have one
          if (sessionId != null) {
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

        // Store the response for this request to send messages back through this connection
        // We need to track by request ID to maintain the connection
        for (final message in messages) {
          if (_isJsonRpcRequest(message)) {
            final reqId = (message as JsonRpcRequest).id;
            _ownedStreamIds.add(streamId);
            if (responseSocket == null) {
              _streamMapping[streamId] = req.response;
            } else {
              _responseStreamSockets[streamId] = responseSocket;
            }
            _requestToStreamMapping[reqId] = streamId;
            if (_isStatelessJsonRpcRequest(message)) {
              _statelessRequestIds.add(reqId);
            }
          }
        }

        final ssePrimed = _enableJsonResponse ||
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
          for (final message in messages) {
            if (_isJsonRpcRequest(message)) {
              final reqId = (message as JsonRpcRequest).id;
              _requestToStreamMapping.remove(reqId);
              _requestResponseMap.remove(reqId);
              _statelessRequestIds.remove(reqId);
            }
          }
          await _safeClose(req.response);
          return;
        }

        var responseDoneHandled = false;
        void handleResponseDone() {
          if (responseDoneHandled) {
            return;
          }
          responseDoneHandled = true;
          if (_enableJsonResponse) {
            _streamMapping.remove(streamId);
          } else {
            _handleResponseStreamClosed(streamId);
          }
        }

        // Set up close handler for client disconnects
        if (responseSocket == null) {
          req.response.done.then(
            (_) => handleResponseDone(),
            onError: (Object _, StackTrace __) => handleResponseDone(),
          );
        } else {
          responseSocket.listen(
            null,
            onDone: handleResponseDone,
            onError: (Object _, StackTrace __) => handleResponseDone(),
            cancelOnError: true,
          );
        }

        // Handle each message
        for (final message in messages) {
          try {
            onmessage?.call(message);
          } catch (e) {
            // Don't let handler errors affect the response - message was received successfully
            onerror?.call(e is Error ? e : StateError(e.toString()));
          }
        }
        // The server SHOULD NOT close the SSE stream before sending all JSON-RPC responses
        // This will be handled by the send() method when responses are ready
      }
    } catch (error) {
      await _writeJsonRpcErrorResponse(
        req.response,
        httpStatus: HttpStatus.badRequest,
        errorCode: ErrorCode.parseError,
        message: 'Parse error',
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
  Future<bool> _validateSession(HttpRequest req, HttpResponse res) async {
    if (!_initialized) {
      // If the server has not been initialized yet, reject all requests
      res.statusCode = HttpStatus.badRequest;
      res.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message: 'Bad Request: Server not initialized',
            ),
          ).toJson(),
        ),
      );
      await _safeClose(res);
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
      res.statusCode = HttpStatus.badRequest;
      res.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message: 'Bad Request: Mcp-Session-Id header is required',
            ),
          ).toJson(),
        ),
      );
      await _safeClose(res);
      return false;
    } else if (_terminated || requestSessionId != sessionId) {
      // Reject terminated or invalid session IDs with 404 Not Found.
      res.statusCode = HttpStatus.notFound;
      res.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message: 'Session not found',
            ),
          ).toJson(),
        ),
      );
      await _safeClose(res);
      return false;
    }

    return true;
  }

  @override
  Future<void> close() async {
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
    _responseStreamSockets.clear();
    _streamMapping.clear();
    _standaloneSseStreamIds.clear();
    _standaloneSseResponses.clear();
    _ownedStreamIds.clear();

    // Clear any pending responses
    _requestResponseMap.clear();
    _requestToStreamMapping.clear(); // Also clear this map
    _statelessRequestIds.clear();
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {dynamic relatedRequestId}) {
    return sendWithRequestId(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) async {
    dynamic requestId = relatedRequestId;
    if (_isJsonRpcResponse(message) || _isJsonRpcError(message)) {
      // If the message is a response, use the request ID from the message
      requestId = _getMessageId(message);
    }

    if (message is JsonRpcRequest &&
        requestId != null &&
        _statelessRequestIds.contains(requestId)) {
      throw StateError(
        "Cannot send JSON-RPC requests on stateless MCP response streams; "
        "return an InputRequiredResult for client input instead.",
      );
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
          eventId = await _eventStore!.storeEvent(target.key, message);
        }

        final sent = await _writeSSEEvent(target.value, message, eventId);
        if (sent) {
          return;
        }

        _removeStandaloneSseResponse(target.key, target.value);
      }
    }

    // Get the response for this request
    final streamId = _requestToStreamMapping[requestId];
    if (streamId == null) {
      throw StateError("No connection established for request ID: $requestId");
    }

    final response = _streamMapping[streamId];
    final responseSocket = _responseStreamSockets[streamId];
    final isStatelessRequestStream =
        requestId != null && _statelessRequestIds.contains(requestId);

    if (!_enableJsonResponse) {
      if (response == null && responseSocket == null) {
        if (isStatelessRequestStream) {
          _handleResponseStreamClosed(streamId);
          return;
        }
      }

      // For SSE responses, generate event ID if event store is provided
      String? eventId;

      if (_eventStore != null && !isStatelessRequestStream) {
        eventId = await _eventStore!.storeEvent(streamId, message);
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

    if (_isJsonRpcResponse(message)) {
      if (!_requestToStreamMapping.containsKey(requestId)) {
        return;
      }

      _requestResponseMap[requestId] = message;
      final relatedIds = _requestToStreamMapping.entries
          .where((entry) => entry.value == streamId)
          .map((entry) => entry.key)
          .toList();

      // Check if we have responses for all requests using this connection
      final allResponsesReady = relatedIds.every(
        (id) => _requestResponseMap.containsKey(id),
      );

      if (allResponsesReady) {
        if (response == null && responseSocket == null) {
          throw StateError(
            "No connection established for request ID: $requestId",
          );
        }

        if (_enableJsonResponse) {
          // All responses ready, send as JSON
          final headers = {
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          };

          if (sessionId != null) {
            headers['mcp-session-id'] = sessionId!;
          }

          final responses =
              relatedIds.map((id) => _requestResponseMap[id]!).toList();

          headers.forEach((key, value) {
            response!.headers.set(key, value);
          });

          if (responses.length == 1) {
            response!.write(jsonEncode(responses[0].toJson()));
          } else {
            response!.write(
              jsonEncode(responses.map((r) => r.toJson()).toList()),
            );
          }
          await _safeClose(response);
        } else if (responseSocket != null) {
          await _safeCloseSocket(responseSocket);
        } else {
          // End the SSE stream
          await _safeClose(response!);
        }

        // Clean up
        _responseStreamSockets.remove(streamId);
        for (final id in relatedIds) {
          _requestResponseMap.remove(id);
          _requestToStreamMapping.remove(id);
          _statelessRequestIds.remove(id);
        }
      }
    }
  }

  void _handleResponseStreamClosed(StreamId streamId) {
    _responseStreamSockets.remove(streamId)?.destroy();
    final relatedIds = _requestToStreamMapping.entries
        .where((entry) => entry.value == streamId)
        .map((entry) => entry.key)
        .toList();

    _streamMapping.remove(streamId);

    final statelessIds = relatedIds
        .where((requestId) => _statelessRequestIds.contains(requestId))
        .toList();
    if (statelessIds.isEmpty) {
      return;
    }

    for (final requestId in statelessIds) {
      if (_requestResponseMap.containsKey(requestId)) {
        continue;
      }

      try {
        onmessage?.call(
          JsonRpcCancelledNotification(
            cancelParams: CancelledNotification(
              requestId: requestId,
              reason: 'SSE response stream closed by client',
            ),
          ),
        );
      } catch (error) {
        onerror?.call(
          error is Error ? error : StateError(error.toString()),
        );
      }
    }

    for (final requestId in statelessIds) {
      _requestResponseMap.remove(requestId);
      _requestToStreamMapping.remove(requestId);
      _statelessRequestIds.remove(requestId);
    }
  }

  /// Checks if a message is an initialize request
  bool _isInitializeRequest(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      return message.method == Method.initialize;
    }
    return false;
  }

  /// Checks if a message uses the stateless 2026 protocol metadata.
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
