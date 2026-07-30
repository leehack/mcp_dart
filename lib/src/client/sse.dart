import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/src/shared/legacy_sse_deprecation.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger('mcp_dart.client.sse');
bool _legacySseWarningEmitted = false;
const int _maximumErrorResponseBodyBytes = 64 * 1024;
const String _truncatedResponseBodySuffix = '\n[response body truncated]';

enum _SseClientState { idle, starting, running, closing, closed }

/// Options for the deprecated [SseClientTransport].
///
/// [headers] supplies additional static headers for the initial SSE `GET` and
/// every JSON-RPC `POST`. This can carry a fixed `Authorization` header for a
/// legacy deployment. Transport-controlled `Accept`, `Content-Type`, and
/// `MCP-Protocol-Version` values take precedence. New OAuth integrations use
/// [StreamableHttpClientTransport] instead.
///
/// When [httpClient] is supplied, the caller retains ownership and must close
/// it after the transport is no longer used. Closing the transport completes
/// each request's abort trigger; a supplied client may ignore that trigger if
/// it does not support [http.AbortableRequest].
@Deprecated(legacySseDeprecationMessage)
class SseClientTransportOptions {
  /// Additional static headers for both legs of the legacy transport.
  ///
  /// Transport-controlled protocol headers take precedence.
  final Map<String, String> headers;

  /// Optional HTTP client used for the SSE stream and JSON-RPC POSTs.
  final http.Client? httpClient;

  /// Creates options for a legacy SSE client transport.
  const SseClientTransportOptions({
    this.headers = const {},
    this.httpClient,
  });
}

/// Error raised by the deprecated legacy HTTP+SSE client transport.
@Deprecated(legacySseDeprecationMessage)
class SseClientError extends Error {
  /// HTTP status code associated with the error, when applicable.
  final int? code;

  /// Human-readable description of the transport failure.
  final String message;

  /// Response body associated with a failed HTTP request, when available.
  ///
  /// Large bodies are truncated to a bounded diagnostic.
  final String? responseBody;

  /// Creates a legacy SSE client transport error.
  SseClientError(this.code, this.message, {this.responseBody});

  @override
  String toString() {
    final status = code == null ? '' : ' (HTTP $code)';
    final body =
        responseBody == null || responseBody!.isEmpty ? '' : ': $responseBody';
    return 'SSE client error$status: $message$body';
  }
}

/// Deprecated client transport for the MCP HTTP+SSE transport.
///
/// This transport opens [url] with an SSE `GET`, requires the first dispatched
/// event to be an `endpoint` event, and sends every client JSON-RPC message as
/// a separate HTTP `POST` to that advertised endpoint. Server JSON-RPC
/// messages are received as SSE `message` events.
///
/// Both the opening `GET` and every message `POST` reject redirects. The
/// advertised endpoint must use HTTP or HTTPS and have the same origin as
/// [url]. Together, these checks prevent configured credentials and MCP
/// messages from being redirected to an untrusted origin.
///
/// HTTP+SSE has no dependable MCP session-resumption contract. An unexpected
/// end to the SSE stream closes this transport; it does not replay messages or
/// silently create a replacement session.
///
/// Use [StreamableHttpClientTransport] for new integrations. Select
/// `McpProtocol.legacy` explicitly when connecting this transport to an
/// initialization-era server.
@Deprecated(legacySseDeprecationMessage)
class SseClientTransport implements Transport, ProtocolVersionAwareTransport {
  final Uri _url;
  final Map<String, String> _headers;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  _SseClientState _state = _SseClientState.idle;
  Completer<void>? _abortController;
  Completer<void>? _endpointReady;
  Object? _startToken;
  Future<void>? _attemptCleanupFuture;
  Future<void>? _closeFuture;
  // Cancelled by failed-start cleanup or transport closure.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _sseSubscription;
  _SseEventParser? _parser;
  Uri? _messageEndpoint;
  String? _sessionId;
  String? _protocolVersion;
  Error? _streamFailure;
  bool _streamEnded = false;
  bool _closeNotified = false;

  /// Callback invoked once when the transport closes.
  @override
  void Function()? onclose;

  /// Callback invoked when a transport or incoming-message error occurs.
  @override
  void Function(Error error)? onerror;

  /// Callback invoked for each valid JSON-RPC SSE `message` event.
  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Creates a deprecated HTTP+SSE client transport for [url].
  ///
  /// The URL must be an absolute HTTP(S) URL without credentials or a
  /// fragment. The transport owns its HTTP client unless one is supplied in
  /// [opts].
  SseClientTransport(
    Uri url, {
    SseClientTransportOptions? opts,
  })  : _url = _validateConnectionUrl(url),
        _headers = Map<String, String>.unmodifiable(
          opts?.headers ?? const {},
        ),
        _httpClient = opts?.httpClient ?? http.Client(),
        _ownsHttpClient = opts?.httpClient == null {
    if (!_legacySseWarningEmitted) {
      _legacySseWarningEmitted = true;
      _logger.warn(legacySseDeprecationMessage);
    }
  }

  /// The legacy session identifier advertised in the POST endpoint query.
  ///
  /// Both `sessionId` and `session_id` are recognized for interoperability.
  @override
  String? get sessionId => _sessionId;

  /// The negotiated MCP protocol version added to subsequent POST requests.
  @override
  String? get protocolVersion => _protocolVersion;

  @override
  set protocolVersion(String? value) {
    _protocolVersion = value;
  }

  /// Opens the SSE stream and waits for its first valid `endpoint` event.
  ///
  /// Throws [StateError] when the lifecycle does not permit another start and
  /// [SseClientError] when connection, HTTP, or SSE framing validation fails.
  @override
  Future<void> start() async {
    if (_state == _SseClientState.starting ||
        _state == _SseClientState.running) {
      throw StateError(
        'SseClientTransport is already started. '
        'McpClient.connect() starts its transport automatically.',
      );
    }
    if (_state == _SseClientState.closing || _state == _SseClientState.closed) {
      throw StateError('SseClientTransport is closed.');
    }

    _state = _SseClientState.starting;
    _streamFailure = null;
    _streamEnded = false;
    _messageEndpoint = null;
    _sessionId = null;
    final startToken = Object();
    final abortController = Completer<void>();
    final endpointReady = Completer<void>();
    final endpointFuture = endpointReady.future;
    // A caller can close immediately after invoking start(), before the HTTP
    // client has returned response headers and this method reaches its await.
    // Attach an error listener now so that close does not create a transient
    // unhandled asynchronous error.
    unawaited(
      endpointFuture.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
    _startToken = startToken;
    _attemptCleanupFuture = null;
    _abortController = abortController;
    _endpointReady = endpointReady;

    try {
      final request = http.AbortableRequest(
        'GET',
        _url,
        abortTrigger: abortController.future,
      )..followRedirects = false;
      request.headers.addAll(_headers);
      request.headers['Accept'] = 'text/event-stream';
      final version = _protocolVersion;
      if (version != null) {
        request.headers['MCP-Protocol-Version'] = version;
      }

      final response = await _httpClient.send(request);
      if (!_isActiveStart(startToken)) {
        await _cancelResponseStream(response.stream);
        throw SseClientError(
          null,
          'SSE connection was closed before it started',
        );
      }
      if (response.statusCode != 200) {
        final body = await _readBoundedResponseBody(response.stream);
        throw SseClientError(
          response.statusCode,
          'SSE connection request failed',
          responseBody: body,
        );
      }

      final mediaType = _mediaType(response.headers['content-type']);
      if (mediaType != 'text/event-stream') {
        await _cancelResponseStream(response.stream);
        throw SseClientError(
          response.statusCode,
          'Expected Content-Type text/event-stream, received '
          '${response.headers['content-type'] ?? 'no Content-Type'}',
        );
      }

      final parser = _SseEventParser(_handleSseEvent);
      _parser = parser;
      _sseSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            parser.addLine,
            onError: _handleSseStreamError,
            onDone: _handleSseStreamDone,
            cancelOnError: false,
          );

      await endpointFuture;
      if (!_isActiveStart(startToken)) {
        throw SseClientError(
          null,
          'SSE connection was closed before it finished starting',
        );
      }
      if (_streamEnded) {
        throw _streamFailure ??
            SseClientError(
              null,
              'SSE stream closed immediately after advertising its endpoint',
            );
      }
      _state = _SseClientState.running;
      _startToken = null;
    } catch (error, stackTrace) {
      final reportedError = _asError(error);
      if (_isActiveStart(startToken)) {
        Object? cleanupError;
        try {
          await _resetAfterFailedStart(startToken);
        } catch (error) {
          cleanupError = error;
        }
        if (cleanupError == null && _state == _SseClientState.idle) {
          _reportError(reportedError);
        } else if (cleanupError != null && _isActiveStart(startToken)) {
          _reportError(reportedError);
          _logger.warn(
            'Failed to clean up an unsuccessful SSE connection: '
            '$cleanupError',
          );
          // A failed cancellation leaves the old response stream observable.
          // Fail closed so it cannot interfere with a later start attempt.
          unawaited(_beginClose());
        }
      }
      Error.throwWithStackTrace(reportedError, stackTrace);
    }
  }

  /// Sends one JSON-RPC message to the endpoint advertised by the SSE server.
  ///
  /// Throws [StateError] unless the transport is running and [SseClientError]
  /// when the HTTP exchange fails.
  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
  }) async {
    final endpoint = _messageEndpoint;
    if (_state != _SseClientState.running || endpoint == null) {
      throw StateError('SseClientTransport is not connected.');
    }

    try {
      final abortController = _abortController;
      if (abortController == null || abortController.isCompleted) {
        throw StateError('SseClientTransport is closed.');
      }
      final request = http.AbortableRequest(
        'POST',
        endpoint,
        abortTrigger: abortController.future,
      )..followRedirects = false;
      request.headers.addAll(_headers);
      request.headers['Content-Type'] = 'application/json';
      final version = _protocolVersion;
      if (version != null) {
        request.headers['MCP-Protocol-Version'] = version;
      }
      request.body = jsonEncode(message.toJson());

      final response = await _httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await _readBoundedResponseBody(response.stream);
        throw SseClientError(
          response.statusCode,
          'Error POSTing JSON-RPC message to the SSE endpoint',
          responseBody: body,
        );
      }
      await _cancelResponseStream(response.stream);
    } catch (error, stackTrace) {
      final reportedError = _asError(error);
      if (_state != _SseClientState.closing &&
          _state != _SseClientState.closed) {
        _reportError(reportedError);
      }
      Error.throwWithStackTrace(reportedError, stackTrace);
    }
  }

  /// Closes the SSE stream and triggers abortion of in-flight HTTP requests.
  ///
  /// The default IO and browser clients honor the trigger. A caller-supplied
  /// [http.Client] may ignore it. Response-subscription cleanup failures are
  /// returned to the caller.
  @override
  Future<void> close() {
    final closeFuture = _closeFuture;
    if (closeFuture != null) {
      return closeFuture;
    }
    if (_state == _SseClientState.closed) {
      return Future<void>.value();
    }
    return _beginClose();
  }

  Future<void> _beginClose({Error? error}) {
    final existingClose = _closeFuture;
    if (existingClose != null) {
      return existingClose;
    }
    _state = _SseClientState.closing;
    _startToken = null;
    final closeCompleter = Completer<void>();
    final closeFuture = closeCompleter.future;
    _closeFuture = closeFuture;
    // Remote failures can begin closing without an awaiting caller. Keep
    // resource-cleanup errors observable to explicit close() callers while
    // preventing a transient unhandled asynchronous error.
    unawaited(
      closeFuture.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
    final startCompleter = _endpointReady;
    if (startCompleter != null && !startCompleter.isCompleted) {
      startCompleter.completeError(
        SseClientError(null, 'SSE connection was closed before it started'),
      );
    }
    unawaited(_settleClose(closeCompleter, error));
    return closeFuture;
  }

  Future<void> _settleClose(
    Completer<void> closeCompleter,
    Error? error,
  ) async {
    try {
      await _finishClose(error);
      closeCompleter.complete();
    } catch (closeError, stackTrace) {
      closeCompleter.completeError(closeError, stackTrace);
    }
  }

  Future<void> _finishClose(Error? error) async {
    if (error != null) {
      _reportError(error);
    }
    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      await _cleanupAttemptResources();
    } catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }
    try {
      if (_ownsHttpClient) {
        _httpClient.close();
      }
    } catch (error, stackTrace) {
      closeError ??= error;
      closeStackTrace ??= stackTrace;
    } finally {
      _state = _SseClientState.closed;
      _notifyClose();
    }
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }

  void _handleSseEvent(String event, String data) {
    if (_state != _SseClientState.starting &&
        _state != _SseClientState.running) {
      return;
    }

    if (_messageEndpoint == null && event != 'endpoint') {
      _failConnection(
        SseClientError(
          null,
          'Expected endpoint as the first SSE event, received $event',
        ),
      );
      return;
    }

    if (event == 'endpoint') {
      if (_messageEndpoint != null) {
        return;
      }
      try {
        final endpoint = _validateMessageEndpoint(data);
        _messageEndpoint = endpoint;
        _sessionId = endpoint.queryParameters['sessionId'] ??
            endpoint.queryParameters['session_id'];
        final endpointReady = _endpointReady;
        if (endpointReady != null && !endpointReady.isCompleted) {
          endpointReady.complete();
        }
      } catch (error) {
        _failConnection(_asError(error));
      }
      return;
    }

    if (event != 'message') {
      return;
    }

    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'SSE message event must contain one JSON-RPC object',
        );
      }
      final message = JsonRpcMessage.fromJson(decoded);
      try {
        onmessage?.call(message);
      } catch (error) {
        _reportError(
          StateError('Error in SseClientTransport.onmessage: $error'),
        );
      }
    } catch (error) {
      _reportError(_asError(error));
    }
  }

  void _handleSseStreamError(Object error, StackTrace stackTrace) {
    final streamError = _asError(error);
    _streamFailure = streamError;
    _streamEnded = true;
    if (_state == _SseClientState.starting) {
      final endpointReady = _endpointReady;
      if (endpointReady != null && !endpointReady.isCompleted) {
        endpointReady.completeError(streamError, stackTrace);
      }
      return;
    }
    if (_state == _SseClientState.running) {
      unawaited(_beginClose(error: streamError));
    }
  }

  void _handleSseStreamDone() {
    _parser?.close();
    _streamEnded = true;
    if (_state == _SseClientState.starting) {
      final endpointReady = _endpointReady;
      if (endpointReady != null && !endpointReady.isCompleted) {
        endpointReady.completeError(
          _streamFailure ??
              SseClientError(
                null,
                'SSE stream closed before advertising an endpoint',
              ),
        );
      }
      return;
    }
    if (_state == _SseClientState.running) {
      unawaited(
        _beginClose(
          error: _streamFailure ??
              SseClientError(null, 'SSE stream closed unexpectedly'),
        ),
      );
    }
  }

  void _failConnection(Error error) {
    _streamFailure = error;
    _streamEnded = true;
    if (_state == _SseClientState.starting) {
      final endpointReady = _endpointReady;
      if (endpointReady != null && !endpointReady.isCompleted) {
        endpointReady.completeError(error);
      }
      return;
    }
    if (_state == _SseClientState.running) {
      unawaited(_beginClose(error: error));
    }
  }

  Future<void> _resetAfterFailedStart(Object startToken) async {
    await _cleanupAttemptResources();
    if (!_isActiveStart(startToken)) {
      return;
    }
    _startToken = null;
    _streamFailure = null;
    _streamEnded = false;
    _state = _SseClientState.idle;
  }

  Future<void> _cleanupAttemptResources() {
    return _attemptCleanupFuture ??= _performAttemptCleanup();
  }

  Future<void> _performAttemptCleanup() async {
    final abortController = _abortController;
    if (abortController != null && !abortController.isCompleted) {
      abortController.complete();
    }
    final subscription = _sseSubscription;
    _sseSubscription = null;
    try {
      await subscription?.cancel();
    } finally {
      _parser = null;
      _endpointReady = null;
      _abortController = null;
      _messageEndpoint = null;
      _sessionId = null;
    }
  }

  bool _isActiveStart(Object startToken) =>
      _state == _SseClientState.starting && identical(_startToken, startToken);

  void _reportError(Error error) {
    try {
      onerror?.call(error);
    } catch (callbackError) {
      _logger.warn('Error in onerror handler: $callbackError');
    }
  }

  void _notifyClose() {
    if (_closeNotified) {
      return;
    }
    _closeNotified = true;
    try {
      onclose?.call();
    } catch (error) {
      _logger.warn('Error in onclose handler: $error');
    }
  }

  Uri _validateMessageEndpoint(String data) {
    final endpointText = data.trim();
    if (endpointText.isEmpty) {
      throw const FormatException('SSE endpoint event data must not be empty');
    }
    final endpoint = _url.resolve(endpointText);
    if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
      throw FormatException(
        'SSE message endpoint must use HTTP or HTTPS: $endpoint',
      );
    }
    if (endpoint.userInfo.isNotEmpty || endpoint.hasFragment) {
      throw const FormatException(
        'SSE message endpoint must not contain credentials or a fragment',
      );
    }
    if (!_sameOrigin(_url, endpoint)) {
      throw FormatException(
        'SSE message endpoint origin does not match connection origin: '
        '$endpoint',
      );
    }
    return endpoint;
  }
}

Uri _validateConnectionUrl(Uri url) {
  if (!url.isAbsolute || (url.scheme != 'http' && url.scheme != 'https')) {
    throw ArgumentError.value(
      url,
      'url',
      'SSE connection URL must be an absolute HTTP or HTTPS URL',
    );
  }
  if (url.host.isEmpty || url.userInfo.isNotEmpty || url.hasFragment) {
    throw ArgumentError.value(
      url,
      'url',
      'SSE connection URL must have a host and no credentials or fragment',
    );
  }
  return url;
}

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

String? _mediaType(String? contentType) =>
    contentType?.split(';').first.trim().toLowerCase();

Future<String> _readBoundedResponseBody(Stream<List<int>> stream) async {
  final bytes = <int>[];
  var truncated = false;
  await for (final chunk in stream) {
    final remaining = _maximumErrorResponseBodyBytes - bytes.length;
    if (remaining == 0) {
      truncated = true;
      break;
    }
    if (chunk.length <= remaining) {
      bytes.addAll(chunk);
      continue;
    }
    bytes.addAll(chunk.take(remaining));
    truncated = true;
    break;
  }
  final body = utf8.decode(bytes, allowMalformed: true);
  return truncated ? '$body$_truncatedResponseBodySuffix' : body;
}

Future<void> _cancelResponseStream(Stream<List<int>> stream) async {
  try {
    final subscription = stream.listen(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    await subscription.cancel();
  } on Object {
    // The transport is already closing. A response cancellation failure must
    // not replace the close error returned to start().
  }
}

Error _asError(Object error) {
  if (error is Error) {
    return error;
  }
  // ignore: deprecated_member_use_from_same_package
  return SseClientError(null, error.toString());
}

class _SseEventParser {
  final void Function(String event, String data) _onEvent;
  final List<String> _dataLines = [];
  String _event = '';

  _SseEventParser(this._onEvent);

  void addLine(String line) {
    if (line.isEmpty) {
      _dispatch();
      return;
    }
    if (line.startsWith(':')) {
      return;
    }

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _event = value;
        break;
      case 'data':
        _dataLines.add(value);
        break;
    }
  }

  void close() {
    // The SSE algorithm discards an incomplete event when the stream ends.
    // Only a blank line dispatches accumulated data.
    _event = '';
    _dataLines.clear();
  }

  void _dispatch() {
    if (_dataLines.isNotEmpty) {
      _onEvent(_event.isEmpty ? 'message' : _event, _dataLines.join('\n'));
    }
    _event = '';
    _dataLines.clear();
  }
}
