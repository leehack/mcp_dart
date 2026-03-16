/// shelf HTTP Adapter Implementation
///
/// Wraps shelf Request and Response to work with the HttpAdapter interface.
/// Handles the impedance mismatch between shelf's immutable Response model
/// and the mutable dart:io HttpResponse model.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType;

import 'package:shelf/shelf.dart';

import 'http_adapter.dart';

/// Adapter for shelf Request
///
/// Wraps a shelf Request to provide the HttpAdapter interface.
/// The response adapter accumulates writes and creates the final
/// shelf Response when the response is closed or flushed.
class ShelfHttpAdapter implements HttpAdapter {
  final Request _request;
  final Completer<Response> _responseCompleter;
  late final ShelfHttpResponseAdapter _responseAdapter;

  ShelfHttpAdapter(this._request, this._responseCompleter) {
    _responseAdapter = ShelfHttpResponseAdapter(_responseCompleter);
  }

  @override
  String get method => _request.method;

  @override
  String? getHeader(String name) {
    // shelf headers are case-insensitive
    return _request.headers[name.toLowerCase()];
  }

  @override
  ContentType? get contentType {
    final contentTypeHeader = getHeader('content-type');
    if (contentTypeHeader == null) return null;

    try {
      return ContentType.parse(contentTypeHeader);
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<List<int>> get bodyStream => _request.read();

  @override
  HttpResponseAdapter get response => _responseAdapter;

  /// Get the shelf Response once it's been created
  ///
  /// This Future completes when the response adapter creates the final Response.
  Future<Response> get shelfResponse => _responseCompleter.future;
}

/// Adapter for shelf Response
///
/// This is more complex than the dart:io adapter because shelf uses
/// an immutable Response model. We accumulate all writes and headers,
/// then create the final Response when flush() or close() is called.
///
/// For JSON responses, we buffer the writes and create a Response with String body.
/// For SSE responses, we create a Response with a streaming body.
class ShelfHttpResponseAdapter implements HttpResponseAdapter {
  final Completer<Response> _responseCompleter;
  final StreamController<List<int>> _bodyController = StreamController<List<int>>();
  final List<String> _bufferedWrites = []; // Buffer for JSON responses
  final Map<String, String> _headers = {};
  final Completer<void> _doneCompleter = Completer<void>();

  int _statusCode = 200;
  bool _responseSent = false;
  bool _closed = false;
  bool _isStreaming = false; // Track if this is a streaming response

  ShelfHttpResponseAdapter(this._responseCompleter);

  @override
  set bufferOutput(bool value) {
    // shelf doesn't have buffering control - this is a no-op
    // shelf handles streaming automatically
  }

  @override
  set statusCode(int code) {
    if (_responseSent) {
      throw StateError('Cannot set status code after response has been sent');
    }
    _statusCode = code;
  }

  @override
  void setHeader(String name, String value) {
    if (_responseSent) {
      throw StateError('Cannot set headers after response has been sent');
    }
    // shelf headers are case-insensitive, but we'll store as provided
    _headers[name] = value;
  }

  @override
  void write(String data) {
    if (_closed) {
      throw StateError('Cannot write to closed response');
    }

    // Determine if this is a streaming response based on content-type
    final contentType = _headers['content-type'] ?? _headers['Content-Type'] ?? '';
    _isStreaming = contentType.contains('text/event-stream');

    if (_isStreaming) {
      // SSE streaming: write to stream immediately
      _bodyController.add(utf8.encode(data));

      // Send response with streaming body on first write
      if (!_responseSent) {
        _sendStreamingResponse();
      }
    } else {
      if (_responseSent) {
        throw StateError('Cannot write after response has been sent');
      }
      // JSON response: buffer the writes
      _bufferedWrites.add(data);
    }
  }

  @override
  Future<void> flush() async {
    if (_closed) {
      return;
    }

    // Determine if streaming based on content-type
    final contentType = _headers['content-type'] ?? _headers['Content-Type'] ?? '';
    _isStreaming = contentType.contains('text/event-stream');

    // Ensure response is sent if we have any pending data
    if (!_responseSent) {
      if (_isStreaming) {
        _sendStreamingResponse();
      } else if (_bufferedWrites.isNotEmpty) {
        // For JSON responses, flush() finalizes and sends buffered content
        _sendBufferedResponse();
      }
    }

    // For streaming responses, flush just ensures headers are sent
    // The actual data flushing is handled by the underlying stream
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;

    // Send response if not already sent
    if (!_responseSent) {
      if (_isStreaming) {
        _sendStreamingResponse();
      } else {
        // JSON response: send buffered content
        _sendBufferedResponse();
      }
    }

    // Close the body stream to prevent resource leaks.
    // For streaming (SSE) responses, await the close to ensure all data is flushed.
    // For non-streaming (JSON) responses, the controller was never listened to,
    // so we close it without awaiting (an unlistened StreamController.close()
    // returns a Future that never completes in Dart).
    if (!_bodyController.isClosed) {
      if (_isStreaming) {
        await _bodyController.close();
      } else {
        unawaited(_bodyController.close());
      }
    }

    // Complete the done Future
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  @override
  Future<void> get done => _doneCompleter.future;

  /// Send a streaming response (for SSE)
  ///
  /// Creates a Response with a streaming body from the StreamController.
  void _sendStreamingResponse() {
    if (_responseSent) {
      return;
    }

    _responseSent = true;

    // Create the response with streaming body
    final response = Response(_statusCode, body: _bodyController.stream, headers: _headers);

    // Complete the response completer
    if (!_responseCompleter.isCompleted) {
      _responseCompleter.complete(response);
    }
  }

  /// Send a buffered response (for JSON)
  ///
  /// Creates a Response with all buffered writes as the body.
  void _sendBufferedResponse() {
    if (_responseSent) {
      return;
    }

    _responseSent = true;

    // Combine all buffered writes
    final body = _bufferedWrites.join('');

    // Create the response with string body
    final response = Response(_statusCode, body: body, headers: _headers);

    // Complete the response completer
    if (!_responseCompleter.isCompleted) {
      _responseCompleter.complete(response);
    }
  }
}
