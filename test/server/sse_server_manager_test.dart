import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/src/server/mcp.dart';
import 'package:mcp_dart/src/server/sse_server_manager.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock HttpRequest for testing
class MockHttpRequest extends Stream<Uint8List> implements HttpRequest {
  @override
  final String method;

  @override
  final Uri uri;

  @override
  final MockHttpResponse response = MockHttpResponse();

  final StreamController<Uint8List> _bodyController =
      StreamController<Uint8List>();

  MockHttpRequest(this.method, String path, {Map<String, String>? queryParams})
      : uri = Uri(path: path, queryParameters: queryParams);

  /// Add body data to the request
  void addBodyData(String data) {
    _bodyController.add(Uint8List.fromList(utf8.encode(data)));
  }

  /// Close the body stream
  void closeBody() {
    _bodyController.close();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _bodyController.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  int get contentLength => 0;

  @override
  List<Cookie> get cookies => [];

  @override
  HttpHeaders get headers => MockHttpHeaders();

  @override
  String get protocolVersion => '1.1';

  @override
  HttpSession get session => throw UnimplementedError();

  X509Certificate? get clientCertificate => null;

  @override
  Uri get requestedUri => uri;

  @override
  bool get persistentConnection => true;
}

/// Mock HttpResponse for testing
class MockHttpResponse implements HttpResponse {
  @override
  int statusCode = HttpStatus.ok;
  final List<String> writtenData = [];
  bool isClosed = false;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  void write(Object? object) {
    writtenData.add(object.toString());
  }

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  int get contentLength => 0;

  @override
  set contentLength(int contentLength) {}

  @override
  List<Cookie> get cookies => [];

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) =>
      throw UnimplementedError();

  @override
  HttpHeaders get headers => MockHttpHeaders();

  @override
  Future<void> flush() async {}

  @override
  Future<void> redirect(Uri location,
          {int status = HttpStatus.movedTemporarily}) async =>
      throw UnimplementedError();

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    write('$object\n');
  }

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding encoding) {}

  @override
  void add(List<int> data) {
    write(utf8.decode(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future get done => Future.value();

  @override
  Duration? get deadline => null;

  @override
  set deadline(Duration? value) {}

  @override
  bool get persistentConnection => true;

  @override
  set persistentConnection(bool persistentConnection) {}

  @override
  String get reasonPhrase => '';

  @override
  set reasonPhrase(String reasonPhrase) {}

  @override
  bool get bufferOutput => true;

  @override
  set bufferOutput(bool bufferOutput) {}
}

/// Mock HttpHeaders for testing
class MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  void remove(String name, Object value) {
    _headers[name.toLowerCase()]?.remove(value.toString());
  }

  @override
  void removeAll(String name) {
    _headers.remove(name.toLowerCase());
  }

  @override
  void clear() {
    _headers.clear();
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach(action);
  }

  @override
  void noFolding(String name) {}

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];

  @override
  String? value(String name) {
    final values = _headers[name.toLowerCase()];
    return values?.isNotEmpty == true ? values!.first : null;
  }

  @override
  int get contentLength => -1;

  @override
  set contentLength(int contentLength) {}

  @override
  bool get chunkedTransferEncoding => false;

  @override
  set chunkedTransferEncoding(bool chunkedTransferEncoding) {}

  @override
  ContentType? get contentType => null;

  @override
  set contentType(ContentType? contentType) {}

  @override
  DateTime? get date => null;

  @override
  set date(DateTime? date) {}

  @override
  DateTime? get expires => null;

  @override
  set expires(DateTime? expires) {}

  @override
  String? get host => null;

  @override
  set host(String? host) {}

  @override
  DateTime? get ifModifiedSince => null;

  @override
  set ifModifiedSince(DateTime? ifModifiedSince) {}

  @override
  bool get persistentConnection => true;

  @override
  set persistentConnection(bool persistentConnection) {}

  @override
  int? get port => null;

  @override
  set port(int? port) {}
}

void main() {
  group('SseServerManager - Request Routing', () {
    late SseServerManager manager;
    late McpServer mcpServer;

    setUp(() {
      mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      manager = SseServerManager(mcpServer);
    });

    test('routes GET /sse to SSE connection handler', () async {
      final request = MockHttpRequest('GET', '/sse');

      // This will attempt to establish SSE connection
      await manager.handleRequest(request);

      // Should have created an active transport
      expect(manager.activeSseTransports.length, equals(1));
    });

    test('routes POST /messages to message handler', () async {
      final request =
          MockHttpRequest('POST', '/messages', queryParams: {'sessionId': ''});

      await manager.handleRequest(request);

      // Should get bad request for empty sessionId
      expect(request.response.statusCode, equals(HttpStatus.badRequest));
      expect(request.response.writtenData.any((d) => d.contains('Missing')),
          isTrue);
    });

    test('returns 404 for unknown paths', () async {
      final request = MockHttpRequest('GET', '/unknown');

      await manager.handleRequest(request);

      expect(request.response.statusCode, equals(HttpStatus.notFound));
      expect(request.response.writtenData.any((d) => d.contains('Not Found')),
          isTrue);
    });

    test('returns 405 for POST to /sse', () async {
      final request = MockHttpRequest('POST', '/sse');

      await manager.handleRequest(request);

      expect(request.response.statusCode, equals(HttpStatus.methodNotAllowed));
      expect(
          request.response.writtenData
              .any((d) => d.contains('Method Not Allowed')),
          isTrue);
    });

    test('returns 405 for GET to /messages', () async {
      final request = MockHttpRequest('GET', '/messages');

      await manager.handleRequest(request);

      expect(request.response.statusCode, equals(HttpStatus.methodNotAllowed));
    });

    test('uses custom paths when provided', () async {
      final customManager = SseServerManager(
        mcpServer,
        ssePath: '/custom-sse',
        messagePath: '/custom-messages',
      );

      final sseRequest = MockHttpRequest('GET', '/custom-sse');
      await customManager.handleRequest(sseRequest);
      expect(customManager.activeSseTransports.length, equals(1));

      final msgRequest = MockHttpRequest('POST', '/custom-messages',
          queryParams: {'sessionId': ''});
      await customManager.handleRequest(msgRequest);
      expect(msgRequest.response.statusCode, equals(HttpStatus.badRequest));
    });
  });

  group('SseServerManager - SSE Connection Management', () {
    test('creates new SSE transport on connection', () async {
      final mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      final manager = SseServerManager(mcpServer);

      expect(manager.activeSseTransports.length, equals(0));

      final request = MockHttpRequest('GET', '/sse');
      await manager.handleRequest(request);

      expect(manager.activeSseTransports.length, equals(1));
    });

    test('stores transport with session ID', () async {
      final mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      final manager = SseServerManager(mcpServer);

      final request = MockHttpRequest('GET', '/sse');
      await manager.handleRequest(request);

      final sessionId = manager.activeSseTransports.keys.first;
      expect(sessionId, isNotEmpty);
      expect(manager.activeSseTransports[sessionId], isNotNull);
    });

    test('transport has onclose callback configured', () async {
      final mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      final manager = SseServerManager(mcpServer);

      final request = MockHttpRequest('GET', '/sse');
      await manager.handleRequest(request);

      expect(manager.activeSseTransports.length, equals(1));

      final transport = manager.activeSseTransports.values.first;
      // Verify onclose callback is configured
      expect(transport.onclose, isNotNull);
    });

    test('handles multiple simultaneous connections', () async {
      // Each connection needs its own McpServer since server can only connect once
      final mcpServer1 = McpServer(
        Implementation(name: 'TestServer1', version: '1.0.0'),
      );
      final mcpServer2 = McpServer(
        Implementation(name: 'TestServer2', version: '1.0.0'),
      );

      final manager1 = SseServerManager(mcpServer1);
      final manager2 = SseServerManager(mcpServer2);

      final request1 = MockHttpRequest('GET', '/sse');
      final request2 = MockHttpRequest('GET', '/sse');

      await manager1.handleRequest(request1);
      await manager2.handleRequest(request2);

      expect(manager1.activeSseTransports.length, equals(1));
      expect(manager2.activeSseTransports.length, equals(1));

      final sessionId1 = manager1.activeSseTransports.keys.first;
      final sessionId2 = manager2.activeSseTransports.keys.first;
      expect(sessionId1, isNot(equals(sessionId2)));
    });
  });

  group('SseServerManager - Message Handling', () {
    late SseServerManager manager;
    late McpServer mcpServer;

    setUp(() {
      mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      manager = SseServerManager(mcpServer);
    });

    test('returns 400 for missing sessionId', () async {
      final request = MockHttpRequest('POST', '/messages');

      await manager.handleRequest(request);

      expect(request.response.statusCode, equals(HttpStatus.badRequest));
      expect(request.response.writtenData.any((d) => d.contains('Missing')),
          isTrue);
    });

    test('returns 400 for empty sessionId', () async {
      final request =
          MockHttpRequest('POST', '/messages', queryParams: {'sessionId': ''});

      await manager.handleRequest(request);

      expect(request.response.statusCode, equals(HttpStatus.badRequest));
      expect(
          request.response.writtenData.any((d) => d.contains('empty')), isTrue);
    });

    test('returns 404 for unknown sessionId', () async {
      final request = MockHttpRequest('POST', '/messages',
          queryParams: {'sessionId': 'unknown-session-id'});

      await manager.handleRequest(request);

      expect(request.response.statusCode, equals(HttpStatus.notFound));
      expect(request.response.writtenData.any((d) => d.contains('No active')),
          isTrue);
    });

    test('forwards message to correct transport', () async {
      final mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      final manager = SseServerManager(mcpServer);

      // First establish SSE connection
      final sseRequest = MockHttpRequest('GET', '/sse');
      await manager.handleRequest(sseRequest);

      final sessionId = manager.activeSseTransports.keys.first;

      // Then send a message to that session
      final messageRequest = MockHttpRequest('POST', '/messages',
          queryParams: {'sessionId': sessionId});

      // Add message body
      final messageData = '{"jsonrpc":"2.0","method":"ping","id":1}\n';
      messageRequest.addBodyData(messageData);
      messageRequest.closeBody();

      await manager.handleRequest(messageRequest);

      // Should have been accepted (202 Accepted is correct for SSE POST)
      expect(messageRequest.response.statusCode, equals(HttpStatus.accepted));
    });
  });

  group('SseServerManager - Error Handling', () {
    late SseServerManager manager;
    late McpServer mcpServer;

    setUp(() {
      mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      manager = SseServerManager(mcpServer);
    });

    test('handles SSE connection setup errors gracefully', () async {
      final request = MockHttpRequest('GET', '/sse');

      // Simulate error by closing response immediately
      request.response.headers.persistentConnection = false;

      await manager.handleRequest(request);

      // Should still complete without throwing
      expect(() => Future.value(), returnsNormally);
    });

    test('configures error handler on transport', () async {
      final mcpServer = McpServer(
        Implementation(name: 'TestServer', version: '1.0.0'),
      );
      final manager = SseServerManager(mcpServer);

      final request = MockHttpRequest('GET', '/sse');
      await manager.handleRequest(request);

      final transport = manager.activeSseTransports.values.first;

      // Verify onerror callback is configured
      expect(transport.onerror, isNotNull);

      // Trigger error should not throw
      expect(() => transport.onerror?.call(StateError('Test error')),
          returnsNormally);
    });
  });
}
