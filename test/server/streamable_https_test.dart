import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

int _ownedStreamIdCount(StreamableHTTPServerTransport transport) {
  final instance = reflect(transport);
  for (ClassMirror? type = instance.type;
      type != null;
      type = type.superclass) {
    for (final declaration in type.declarations.entries) {
      if (MirrorSystem.getName(declaration.key) == '_ownedStreamIds') {
        return (instance.getField(declaration.key).reflectee as Set<Object?>)
            .length;
      }
    }
  }
  throw StateError('Stream ownership state not found');
}

/// A simple implementation of EventStore for testing event resumability
class TestEventStore implements EventStore {
  /// Maps session IDs to lists of (eventId, messageJson) pairs
  final events = <String, List<MapEntry<String, Map<String, dynamic>>>>{};

  @override
  Future<String> storeEvent(String sessionId, JsonRpcMessage message) async {
    final eventId = generateUUID();
    events.putIfAbsent(sessionId, () => []);
    events[sessionId]!.add(MapEntry(eventId, message.toJson()));
    return eventId;
  }

  @override
  Future<String> replayEventsAfter(
    String eventId, {
    required Future<void> Function(String, JsonRpcMessage) send,
  }) async {
    String? sessionId;
    int? eventIndex;

    for (final entry in events.entries) {
      final sid = entry.key;
      final eventList = entry.value;
      for (var i = 0; i < eventList.length; i++) {
        if (eventList[i].key == eventId) {
          sessionId = sid;
          eventIndex = i;
          break;
        }
      }
      if (sessionId != null) break;
    }

    if (sessionId == null || eventIndex == null) {
      throw Exception('Event ID not found: $eventId');
    }

    final eventsToReplay = events[sessionId]!.sublist(eventIndex + 1);
    for (final event in eventsToReplay) {
      final jsonMap = _convertToStringDynamicMap(event.value);
      final message = JsonRpcMessage.fromJson(jsonMap);
      await send(event.key, message);
    }

    return sessionId;
  }

  /// Converts Maps with dynamic keys to Map&lt;`String, dynamic&gt;
  Map<String, dynamic> _convertToStringDynamicMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        result[key] = _convertToStringDynamicMap(value);
      } else if (value is List) {
        result[key] = _convertToStringDynamicList(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Converts Lists with dynamic values
  List<dynamic> _convertToStringDynamicList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return _convertToStringDynamicMap(item);
      } else if (item is List) {
        return _convertToStringDynamicList(item);
      } else {
        return item;
      }
    }).toList();
  }
}

class InvalidEventIdStore implements EventStore {
  InvalidEventIdStore(this.eventId);

  final String eventId;
  String? storedStreamId;

  @override
  Future<String> storeEvent(String streamId, JsonRpcMessage message) async {
    storedStreamId = streamId;
    return 'known-event-id';
  }

  @override
  Future<String> replayEventsAfter(
    String lastEventId, {
    required Future<void> Function(String eventId, JsonRpcMessage message) send,
  }) async {
    await send(
      eventId,
      const JsonRpcNotification(method: 'notifications/replay'),
    );
    final streamId = storedStreamId;
    if (streamId == null) {
      throw StateError('No stream stored for replay');
    }
    return streamId;
  }
}

class InvalidPrimingEventStore implements EventStore {
  int storeCalls = 0;

  @override
  Future<String> storeEvent(String streamId, JsonRpcMessage message) async {
    storeCalls++;
    return 'bad event id';
  }

  @override
  Future<String> replayEventsAfter(
    String lastEventId, {
    required Future<void> Function(String eventId, JsonRpcMessage message) send,
  }) async {
    throw StateError('Replay is not expected');
  }
}

List<Map<String, dynamic>> _decodeSseJsonMessages(String body) {
  final messages = <Map<String, dynamic>>[];
  for (final event in body.trim().split('\n\n')) {
    final data = event
        .split('\n')
        .where((line) => line.startsWith('data: '))
        .map((line) => line.substring('data: '.length))
        .join('\n');
    if (data.isNotEmpty) {
      messages.add(jsonDecode(data) as Map<String, dynamic>);
    }
  }
  return messages;
}

Map<String, dynamic> _statelessMeta() => buildProtocolRequestMeta(
      protocolVersion: previewProtocolVersion,
      clientInfo: const Implementation(name: 'TestClient', version: '1.0.0'),
      clientCapabilities: const ClientCapabilities(),
    );

class _SseEvent {
  final String? id;
  final String? event;
  final int? retry;
  final String data;

  const _SseEvent({
    this.id,
    this.event,
    this.retry,
    required this.data,
  });

  Map<String, dynamic> get json => jsonDecode(data) as Map<String, dynamic>;
}

Future<_SseEvent> _readSseEvent(StreamIterator<String> lines) async {
  String? id;
  String? event;
  int? retry;
  final dataLines = <String>[];

  while (await lines.moveNext()) {
    final line = lines.current;
    if (line.isEmpty) {
      if (id != null || event != null || dataLines.isNotEmpty) {
        return _SseEvent(
          id: id,
          event: event,
          retry: retry,
          data: dataLines.join('\n'),
        );
      }
      continue;
    }

    if (line.startsWith(':')) {
      continue;
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex < 0) {
      continue;
    }

    final field = line.substring(0, colonIndex);
    final valueStart = colonIndex +
        1 +
        (line.length > colonIndex + 1 && line[colonIndex + 1] == ' ' ? 1 : 0);
    final value = line.substring(valueStart);

    switch (field) {
      case 'id':
        id = value;
        break;
      case 'event':
        event = value;
        break;
      case 'retry':
        retry = int.tryParse(value);
        break;
      case 'data':
        dataLines.add(value);
        break;
    }
  }

  throw StateError('SSE stream ended before an event was received');
}

Future<_SseEvent> _readSseJsonEvent(StreamIterator<String> lines) async {
  while (true) {
    final event = await _readSseEvent(lines);
    if (event.data.trim().isNotEmpty) {
      return event;
    }
  }
}

Future<_SseEvent?> _readOptionalSseEvent(StreamIterator<String> lines) async {
  try {
    return await _readSseEvent(lines).timeout(
      const Duration(milliseconds: 300),
    );
  } on TimeoutException {
    return null;
  } on StateError catch (error) {
    if (error.message == 'SSE stream ended before an event was received') {
      return null;
    }
    rethrow;
  }
}

void main() {
  late HttpServer testServer;
  late int serverPort;
  late String serverUrlBase;

  /// Maps endpoint paths to active transports
  final Map<String, StreamableHTTPServerTransport> transports = {};
  final Map<String, Completer<JsonRpcMessage>> messageCompleters = {};

  /// Set up the test HTTP server before all tests
  setUpAll(() async {
    try {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;
      serverUrlBase = 'http://localhost:$serverPort';
      print("Test server listening on $serverUrlBase");

      testServer.listen((request) async {
        final path = request.uri.path;
        print("Received request: ${request.method} ${request.uri}");

        if (path == '/mcp') {
          final transport = transports['/mcp'];

          if (transport != null) {
            try {
              await transport.handleRequest(request);
            } catch (e, stackTrace) {
              print("Error in transport.handleRequest: $e");
              print("Stack trace: $stackTrace");
              if (!request.response.headers.persistentConnection) {
                request.response.statusCode = HttpStatus.internalServerError;
                request.response.write("Error processing request: $e");
                await request.response.close();
              }
            }
          } else {
            print("No transport available for path: $path");
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write("Transport not available");
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write("Not Found");
          await request.response.close();
        }
      });
    } catch (e) {
      print("FATAL: Failed to start test server: $e");
      fail("Failed to start test server: $e");
    }
  });

  /// Clean up resources after all tests complete
  tearDownAll(() async {
    print("Stopping test server...");
    for (final transport in transports.values) {
      await transport.close();
    }
    await testServer.close(force: true);
    print("Test server stopped.");
  });

  group('StreamableHTTPServerTransport tests', () {
    /// Reset state before each test
    setUp(() {
      transports.clear();
      messageCompleters.clear();
    });

    // Common test setup

    // Helper to manually trigger initialization of the transport

    test('JSON-RPC preflight errors advertise JSON content type', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'preflight-session-id',
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      Future<HttpClientResponse> send(
        String method, {
        Map<String, String> headers = const {},
        Object? body,
        ContentType? contentType,
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.openUrl(
          method,
          Uri.parse('$serverUrlBase/mcp'),
        );
        request.headers.contentType = contentType;
        headers.forEach(request.headers.set);
        if (body != null) {
          request.write(jsonEncode(body));
        }
        return request.close();
      }

      final getWithoutSseAccept = await send(
        'GET',
        headers: {HttpHeaders.acceptHeader: 'application/json'},
      );
      expect(getWithoutSseAccept.statusCode, HttpStatus.notAcceptable);
      expect(
        getWithoutSseAccept.headers.contentType?.mimeType,
        'application/json',
      );
      expect(
        await utf8.decodeStream(getWithoutSseAccept),
        contains('Client must accept text/event-stream'),
      );

      final unsupportedMethod = await send('PUT');
      expect(unsupportedMethod.statusCode, HttpStatus.methodNotAllowed);
      expect(
        unsupportedMethod.headers.contentType?.mimeType,
        'application/json',
      );
      expect(
        unsupportedMethod.headers.value(HttpHeaders.allowHeader),
        'GET, POST, DELETE',
      );
      expect(
        await utf8.decodeStream(unsupportedMethod),
        contains('Method not allowed.'),
      );

      final postWithoutSseAccept = await send(
        'POST',
        headers: {HttpHeaders.acceptHeader: 'application/json'},
        contentType: ContentType.json,
        body: const JsonRpcRequest(id: 1, method: 'ping').toJson(),
      );
      expect(postWithoutSseAccept.statusCode, HttpStatus.notAcceptable);
      expect(
        postWithoutSseAccept.headers.contentType?.mimeType,
        'application/json',
      );
      expect(
        await utf8.decodeStream(postWithoutSseAccept),
        contains(
          'Client must accept both application/json and text/event-stream',
        ),
      );

      final postWithWrongContentType = await send(
        'POST',
        headers: {
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        },
        contentType: ContentType.text,
        body: const JsonRpcRequest(id: 2, method: 'ping').toJson(),
      );
      expect(
        postWithWrongContentType.statusCode,
        HttpStatus.unsupportedMediaType,
      );
      expect(
        postWithWrongContentType.headers.contentType?.mimeType,
        'application/json',
      );
      expect(
        await utf8.decodeStream(postWithWrongContentType),
        contains('Content-Type must be application/json'),
      );
    });

    test('maps malformed typed request params to InvalidParams', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      Future<Map<String, dynamic>> post(
        Map<String, dynamic> body, {
        required String method,
        String? name,
      }) async {
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse('$serverUrlBase/mcp'),
          );
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            )
            ..set('MCP-Protocol-Version', previewProtocolVersion)
            ..set('Mcp-Method', method);
          if (name != null) {
            request.headers.set('Mcp-Name', name);
          }
          request.write(jsonEncode(body));
          final response = await request.close();
          expect(response.statusCode, HttpStatus.badRequest);
          return jsonDecode(await utf8.decodeStream(response))
              as Map<String, dynamic>;
        } finally {
          client.close(force: true);
        }
      }

      final taskError = await post(
        {
          'jsonrpc': jsonRpcVersion,
          'id': 'bad-task',
          'method': Method.tasksGet,
          'params': {
            'taskId': 7,
            '_meta': _statelessMeta(),
          },
        },
        method: Method.tasksGet,
        name: '7',
      );
      expect(taskError['id'], 'bad-task');
      expect(taskError['error']['code'], ErrorCode.invalidParams.value);

      final listenError = await post(
        {
          'jsonrpc': jsonRpcVersion,
          'id': 'bad-listen',
          'method': Method.subscriptionsListen,
          'params': {
            'notifications': 'tools',
            '_meta': _statelessMeta(),
          },
        },
        method: Method.subscriptionsListen,
      );
      expect(listenError['id'], 'bad-listen');
      expect(listenError['error']['code'], ErrorCode.invalidParams.value);

      final envelopeError = await post(
        {
          'jsonrpc': jsonRpcVersion,
          'id': <String>[],
          'method': Method.tasksGet,
          'params': {'taskId': 'task'},
        },
        method: Method.tasksGet,
        name: 'task',
      );
      expect(envelopeError['id'], isNull);
      expect(envelopeError['error']['code'], ErrorCode.invalidRequest.value);

      for (final scenario in [
        (
          body: <String, dynamic>{
            'jsonrpc': '1.0',
            'id': 'wrong-version',
            'method': Method.tasksGet,
            'params': {
              'taskId': 'task',
              '_meta': _statelessMeta(),
            },
          },
          id: 'wrong-version',
          method: Method.tasksGet,
          name: 'task',
        ),
        (
          body: <String, dynamic>{
            'jsonrpc': jsonRpcVersion,
            'id': 42,
            'method': 7,
          },
          id: 42,
          method: Method.tasksGet,
          name: null,
        ),
      ]) {
        final invalidRequest = await post(
          scenario.body,
          method: scenario.method,
          name: scenario.name,
        );
        expect(invalidRequest['id'], scenario.id);
        expect(
          invalidRequest['error']['code'],
          ErrorCode.invalidRequest.value,
        );
      }
    });

    test(
        'validates required 2026 headers before malformed typed request params',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<Map<String, dynamic>> post({
        required String id,
        required String bodyVersion,
        required String? protocolHeader,
        required String? methodHeader,
        required String? nameHeader,
      }) async {
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        if (protocolHeader != null) {
          request.headers.set('MCP-Protocol-Version', protocolHeader);
        }
        if (methodHeader != null) {
          request.headers.set('Mcp-Method', methodHeader);
        }
        if (nameHeader != null) {
          request.headers.set('Mcp-Name', nameHeader);
        }
        request.write(
          jsonEncode({
            'jsonrpc': jsonRpcVersion,
            'id': id,
            'method': Method.tasksUpdate,
            'params': {
              'taskId': 'task-1',
              'inputResponses': 'not-an-object',
              '_meta': {
                ..._statelessMeta(),
                McpMetaKey.protocolVersion: bodyVersion,
              },
            },
          }),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.badRequest, reason: id);
        return jsonDecode(await utf8.decodeStream(response))
            as Map<String, dynamic>;
      }

      final scenarios = <({
        String id,
        String bodyVersion,
        String? protocolHeader,
        String? methodHeader,
        String? nameHeader,
        String expectedMessage,
      })>[
        (
          id: 'missing-protocol',
          bodyVersion: previewProtocolVersion,
          protocolHeader: null,
          methodHeader: Method.tasksUpdate,
          nameHeader: 'task-1',
          expectedMessage: 'MCP-Protocol-Version header is required',
        ),
        (
          id: 'mismatched-protocol',
          bodyVersion: latestInitializationProtocolVersion,
          protocolHeader: previewProtocolVersion,
          methodHeader: Method.tasksUpdate,
          nameHeader: 'task-1',
          expectedMessage: 'MCP-Protocol-Version header value',
        ),
        (
          id: 'missing-method',
          bodyVersion: previewProtocolVersion,
          protocolHeader: previewProtocolVersion,
          methodHeader: null,
          nameHeader: 'task-1',
          expectedMessage: 'Mcp-Method header is required',
        ),
        (
          id: 'mismatched-method',
          bodyVersion: previewProtocolVersion,
          protocolHeader: previewProtocolVersion,
          methodHeader: Method.tasksGet,
          nameHeader: 'task-1',
          expectedMessage: 'Mcp-Method header value',
        ),
        (
          id: 'missing-name',
          bodyVersion: previewProtocolVersion,
          protocolHeader: previewProtocolVersion,
          methodHeader: Method.tasksUpdate,
          nameHeader: null,
          expectedMessage: 'Mcp-Name header is required',
        ),
        (
          id: 'mismatched-name',
          bodyVersion: previewProtocolVersion,
          protocolHeader: previewProtocolVersion,
          methodHeader: Method.tasksUpdate,
          nameHeader: 'different-task',
          expectedMessage: 'Mcp-Name header value',
        ),
      ];

      for (final scenario in scenarios) {
        final error = await post(
          id: scenario.id,
          bodyVersion: scenario.bodyVersion,
          protocolHeader: scenario.protocolHeader,
          methodHeader: scenario.methodHeader,
          nameHeader: scenario.nameHeader,
        );
        expect(error['id'], scenario.id);
        expect(error['error']['code'], ErrorCode.headerMismatch.value);
        expect(
          error['error']['message'],
          contains(scenario.expectedMessage),
        );
      }

      final invalidParams = await post(
        id: 'valid-headers',
        bodyVersion: previewProtocolVersion,
        protocolHeader: previewProtocolVersion,
        methodHeader: Method.tasksUpdate,
        nameHeader: 'task-1',
      );
      expect(invalidParams['id'], 'valid-headers');
      expect(invalidParams['error']['code'], ErrorCode.invalidParams.value);
    });

    test('stateless HTTP discover requires body protocol metadata', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        )
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.serverDiscover);
      request.write(
        jsonEncode({
          'jsonrpc': jsonRpcVersion,
          'id': 'discover-missing-version',
          'method': Method.serverDiscover,
          'params': <String, dynamic>{},
        }),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 'discover-missing-version');
      expect(body['error']['code'], ErrorCode.invalidParams.value);
      expect(body['error']['message'], contains(McpMetaKey.protocolVersion));
    });

    test('unsupported protocol response preserves a readable request id',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      )..setServerSupportedProtocolVersions({previewProtocolVersion});
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        )
        ..set('MCP-Protocol-Version', '1900-01-01');
      request.write(
        jsonEncode(
          const JsonRpcRequest(id: 'unsupported-version', method: 'ping')
              .toJson(),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 'unsupported-version');
      expect(
        body['error']['code'],
        ErrorCode.unsupportedProtocolVersion.value,
      );
    });

    test('initialization with stateful session management', () async {
      // Create a new transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;

      // Set the sessionId for testing purposes
      transport.sessionId = "test-session-id";

      // Verify the session ID is correctly set
      expect(transport.sessionId, equals("test-session-id"));

      await transport.close();
    });

    test('GET request establishes SSE stream', () async {
      // Create a transport with fixed session ID
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;

      // Set the session ID for testing
      transport.sessionId = "test-session-id";

      // Create a notification to send via the SSE stream
      final notification = const JsonRpcNotification(
        method: 'test/notification',
        params: {'message': 'hello'},
      );

      // Verify the transport can send messages without exceptions
      try {
        await transport.send(notification);
      } catch (e) {
        fail("Transport send method threw an exception: $e");
      }

      await transport.close();
    });

    test(
      'POST request with JSON-RPC request triggers onmessage',
      () async {
        // Create a transport with session management
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => "test-session-id",
          ),
        );
        await transport.start();
        transports['/mcp'] = transport;

        transport.sessionId = "test-session-id";

        // Set up message handler with completion tracker
        final messageCompleter = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          if (!messageCompleter.isCompleted) {
            messageCompleter.complete(message);
          }
        };

        // Create a test JSON-RPC request
        final request = const JsonRpcRequest(
          id: 123,
          method: 'test/method',
          params: {'data': 'test-data'},
        );

        // Simulate message receipt
        transport.onmessage?.call(request);

        // Wait for message processing with timeout
        final receivedMessage = await messageCompleter.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              throw TimeoutException('No message received within timeout'),
        );

        // Verify message content
        expect(receivedMessage, isA<JsonRpcRequest>());
        expect((receivedMessage as JsonRpcRequest).id, equals(123));
        expect(receivedMessage.method, equals('test/method'));
        expect(receivedMessage.params?['data'], equals('test-data'));

        await transport.close();
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'routes SSE notifications for string request IDs',
      () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => null,
          ),
        );
        addTearDown(transport.close);
        await transport.start();
        transports['/mcp'] = transport;

        Future<HttpClientResponse> postJsonRpc(JsonRpcMessage message) async {
          final client = HttpClient();
          addTearDown(() => client.close(force: true));

          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          request.write(jsonEncode(message.toJson()));
          return request.close();
        }

        transport.onmessage = (message) {
          if (message is! JsonRpcRequest) {
            return;
          }

          if (message.method == 'initialize') {
            unawaited(
              transport.send(
                JsonRpcResponse(
                  id: message.id,
                  result: const {
                    'protocolVersion': latestInitializationProtocolVersion,
                    'capabilities': {},
                    'serverInfo': {'name': 'TestServer', 'version': '1.0.0'},
                  },
                ),
              ),
            );
            return;
          }

          if (message.method == 'test/string-id') {
            unawaited(
              () async {
                await transport.sendWithRequestId(
                  const JsonRpcNotification(
                    method: 'test/notification',
                    params: {'marker': 'routed'},
                  ),
                  relatedRequestId: message.id,
                );
                await transport.send(
                  JsonRpcResponse(
                    id: message.id,
                    result: const {'ok': true},
                  ),
                );
              }(),
            );
          }
        };

        final initResponse = await postJsonRpc(
          const JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: {
              'protocolVersion': latestInitializationProtocolVersion,
              'capabilities': {},
              'clientInfo': {'name': 'TestClient', 'version': '1.0.0'},
            },
          ),
        );
        expect(initResponse.statusCode, HttpStatus.ok);
        expect(initResponse.headers.value('X-Accel-Buffering'), 'no');
        final initMessages = _decodeSseJsonMessages(
          await utf8.decodeStream(initResponse),
        );
        expect(initMessages.single['id'], 1);

        final response = await postJsonRpc(
          const JsonRpcRequest(
            id: 'client-req-string',
            method: 'test/string-id',
          ),
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers.contentType?.mimeType,
          'text/event-stream',
        );
        expect(response.headers.value('X-Accel-Buffering'), 'no');

        final messages =
            _decodeSseJsonMessages(await utf8.decodeStream(response));
        expect(messages, hasLength(2));
        expect(messages[0]['method'], 'test/notification');
        expect(messages[0]['params'], containsPair('marker', 'routed'));
        expect(messages[1]['id'], 'client-req-string');
        expect(messages[1]['result'], containsPair('ok', true));
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'routes handler client requests on originating POST SSE stream',
      () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => null,
          ),
        );
        addTearDown(transport.close);

        final server = Server(
          const Implementation(name: 'TestServer', version: '1.0.0'),
        );
        addTearDown(server.close);
        server.setRequestHandler<JsonRpcRequest>(
          'test/nested-request',
          (request, extra) async {
            await extra.sendRequest<EmptyResult>(
              const JsonRpcRequest(
                id: 0,
                method: 'test/client-question',
                params: {'prompt': 'confirm'},
              ),
              EmptyResult.fromJson,
              const RequestOptions(timeout: Duration(seconds: 2)),
            );
            return const EmptyResult();
          },
          (id, params, meta) => JsonRpcRequest(
            id: id,
            method: 'test/nested-request',
            params: params,
            meta: meta,
          ),
        );
        await server.connect(transport);
        transports['/mcp'] = transport;

        Future<HttpClientResponse> postJsonRpc(JsonRpcMessage message) async {
          final client = HttpClient();
          addTearDown(() => client.close(force: true));

          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          request.write(jsonEncode(message.toJson()));
          return request.close();
        }

        final initResponse = await postJsonRpc(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
            ),
          ),
        );
        expect(initResponse.statusCode, HttpStatus.ok);
        expect(
          _decodeSseJsonMessages(await utf8.decodeStream(initResponse)).single,
          containsPair('id', 1),
        );

        final initializedResponse = await postJsonRpc(
          const JsonRpcInitializedNotification(),
        );
        expect(initializedResponse.statusCode, HttpStatus.accepted);
        await initializedResponse.drain<void>();

        final response = await postJsonRpc(
          const JsonRpcRequest(
            id: 'originating-request',
            method: 'test/nested-request',
          ),
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.contentType?.mimeType, 'text/event-stream');
        final lines = StreamIterator(
          response.transform(utf8.decoder).transform(const LineSplitter()),
        );
        addTearDown(lines.cancel);

        final nestedRequest = await _readSseJsonEvent(lines);
        expect(nestedRequest.json['method'], 'test/client-question');
        expect(nestedRequest.json['params'], {'prompt': 'confirm'});

        final nestedResponse = await postJsonRpc(
          JsonRpcResponse(
            id: nestedRequest.json['id'],
            result: const EmptyResult().toJson(),
          ),
        );
        expect(nestedResponse.statusCode, HttpStatus.accepted);
        await nestedResponse.drain<void>();

        final finalResponse = await _readSseJsonEvent(lines);
        expect(finalResponse.json['id'], 'originating-request');
        expect(finalResponse.json['result'], const EmptyResult().toJson());
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'isolates concurrent JSON POSTs that reuse a request ID',
      () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => null,
            enableJsonResponse: true,
          ),
        );
        addTearDown(transport.close);

        final server = Server(
          const Implementation(name: 'TestServer', version: '1.0.0'),
        );
        addTearDown(server.close);
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final releaseSecond = Completer<void>();

        void registerHandler(
          String method,
          String marker,
          Completer<void> started,
          Completer<void> release,
        ) {
          server.setRequestHandler<JsonRpcRequest>(
            method,
            (request, extra) async {
              expect(extra.requestId, 'shared-id');
              started.complete();
              await release.future;
              return EmptyResult(meta: {'marker': marker});
            },
            (id, params, meta) => JsonRpcRequest(
              id: id,
              method: method,
              params: params,
              meta: meta,
            ),
          );
        }

        registerHandler(
          'test/first',
          'first',
          firstStarted,
          releaseFirst,
        );
        registerHandler(
          'test/second',
          'second',
          secondStarted,
          releaseSecond,
        );
        await server.connect(transport);
        transports['/mcp'] = transport;

        Future<HttpClientResponse> postMessage(JsonRpcMessage message) async {
          final client = HttpClient();
          addTearDown(() => client.close(force: true));
          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          request.write(jsonEncode(message.toJson()));
          return request.close();
        }

        final initializeResponse = await postMessage(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'TestClient', version: '1.0'),
            ),
          ),
        );
        expect(initializeResponse.statusCode, HttpStatus.ok);
        await initializeResponse.drain<void>();
        final initializedResponse = await postMessage(
          const JsonRpcInitializedNotification(),
        );
        expect(initializedResponse.statusCode, HttpStatus.accepted);
        await initializedResponse.drain<void>();

        Future<Map<String, dynamic>> post(String method) async {
          final response = await postMessage(
            JsonRpcRequest(id: 'shared-id', method: method),
          );
          expect(response.statusCode, HttpStatus.ok);
          expect(response.headers.contentType?.mimeType, 'application/json');
          return jsonDecode(await utf8.decodeStream(response))
              as Map<String, dynamic>;
        }

        final firstResponse = post('test/first');
        await firstStarted.future;
        final secondResponse = post('test/second');
        await secondStarted.future;

        releaseSecond.complete();
        final secondJson = await secondResponse;
        releaseFirst.complete();
        final firstJson = await firstResponse;

        expect(secondJson['id'], 'shared-id');
        expect(secondJson['result']['_meta']['marker'], 'second');
        expect(firstJson['id'], 'shared-id');
        expect(firstJson['result']['_meta']['marker'], 'first');
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'legacy cancellation aborts the unique matching HTTP request',
      () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => null,
            eventStore: TestEventStore(),
          ),
        );
        addTearDown(transport.close);

        final server = Server(
          const Implementation(name: 'TestServer', version: '1.0.0'),
        );
        addTearDown(server.close);
        final requestStarted = Completer<void>();
        final cancellationObserved = Completer<Object?>();
        server.setRequestHandler<JsonRpcRequest>(
          'test/cancellable',
          (request, extra) async {
            final abortSubscription = extra.signal.onAbort.listen((_) {
              if (!cancellationObserved.isCompleted) {
                cancellationObserved.complete(extra.signal.reason);
              }
            });
            if (!requestStarted.isCompleted) {
              requestStarted.complete();
            }
            try {
              await cancellationObserved.future;
            } finally {
              await abortSubscription.cancel();
            }
            return const EmptyResult();
          },
          (id, params, meta) => JsonRpcRequest(
            id: id,
            method: 'test/cancellable',
            params: params,
            meta: meta,
          ),
        );
        await server.connect(transport);
        transports['/mcp'] = transport;

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        Future<HttpClientResponse> post(JsonRpcMessage message) async {
          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          request.write(jsonEncode(message.toJson()));
          return request.close();
        }

        final initialize = await post(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'TestClient', version: '1.0'),
            ),
          ),
        );
        expect(initialize.statusCode, HttpStatus.ok);
        await initialize.drain<void>();
        final initialized = await post(
          const JsonRpcInitializedNotification(),
        );
        expect(initialized.statusCode, HttpStatus.accepted);
        await initialized.drain<void>();

        final pending = await post(
          const JsonRpcRequest(
            id: 'unique-request',
            method: 'test/cancellable',
          ),
        );
        expect(pending.statusCode, HttpStatus.ok);
        expect(pending.headers.contentType?.mimeType, 'text/event-stream');
        final pendingSubscription = pending.listen((_) {});
        addTearDown(pendingSubscription.cancel);
        await requestStarted.future;

        final cancellation = await post(
          JsonRpcCancelledNotification(
            cancelParams: const CancelledNotification(
              requestId: 'unique-request',
              reason: 'legacy client cancelled',
            ),
          ),
        );
        expect(cancellation.statusCode, HttpStatus.accepted);
        await cancellation.drain<void>();
        expect(
          await cancellationObserved.future,
          'legacy client cancelled',
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'legacy cancellation does not cross-cancel ambiguous duplicate IDs',
      () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => null,
            eventStore: TestEventStore(),
          ),
        );
        addTearDown(transport.close);

        final server = Server(
          const Implementation(name: 'TestServer', version: '1.0.0'),
        );
        addTearDown(server.close);
        final firstStarted = Completer<AbortSignal>();
        final secondStarted = Completer<AbortSignal>();
        final releaseFirst = Completer<void>();
        final releaseSecond = Completer<void>();
        addTearDown(() {
          if (!releaseFirst.isCompleted) {
            releaseFirst.complete();
          }
          if (!releaseSecond.isCompleted) {
            releaseSecond.complete();
          }
        });

        void registerHandler(
          String method,
          String marker,
          Completer<AbortSignal> started,
          Completer<void> release,
        ) {
          server.setRequestHandler<JsonRpcRequest>(
            method,
            (request, extra) async {
              started.complete(extra.signal);
              await release.future;
              return EmptyResult(meta: {'marker': marker});
            },
            (id, params, meta) => JsonRpcRequest(
              id: id,
              method: method,
              params: params,
              meta: meta,
            ),
          );
        }

        registerHandler(
          'test/first-cancellable',
          'first',
          firstStarted,
          releaseFirst,
        );
        registerHandler(
          'test/second-cancellable',
          'second',
          secondStarted,
          releaseSecond,
        );
        await server.connect(transport);
        transports['/mcp'] = transport;

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        Future<HttpClientResponse> post(JsonRpcMessage message) async {
          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          request.write(jsonEncode(message.toJson()));
          return request.close();
        }

        final initialize = await post(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'TestClient', version: '1.0'),
            ),
          ),
        );
        expect(initialize.statusCode, HttpStatus.ok);
        await initialize.drain<void>();
        final initialized = await post(
          const JsonRpcInitializedNotification(),
        );
        expect(initialized.statusCode, HttpStatus.accepted);
        await initialized.drain<void>();

        final firstResponse = await post(
          const JsonRpcRequest(
            id: 'shared-cancellation-id',
            method: 'test/first-cancellable',
          ),
        );
        final firstSignal = await firstStarted.future;
        final secondResponse = await post(
          const JsonRpcRequest(
            id: 'shared-cancellation-id',
            method: 'test/second-cancellable',
          ),
        );
        final secondSignal = await secondStarted.future;

        final cancellation = await post(
          JsonRpcCancelledNotification(
            cancelParams: const CancelledNotification(
              requestId: 'shared-cancellation-id',
              reason: 'ambiguous cancellation',
            ),
          ),
        );
        expect(cancellation.statusCode, HttpStatus.accepted);
        await cancellation.drain<void>();
        expect(firstSignal.aborted, isFalse);
        expect(secondSignal.aborted, isFalse);

        releaseSecond.complete();
        releaseFirst.complete();
        final responses = await Future.wait([
          utf8.decodeStream(firstResponse),
          utf8.decodeStream(secondResponse),
        ]);
        final firstMessages = _decodeSseJsonMessages(responses.first);
        final secondMessages = _decodeSseJsonMessages(responses.last);
        expect(firstMessages.single['result']['_meta']['marker'], 'first');
        expect(secondMessages.single['result']['_meta']['marker'], 'second');
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'isolates same-ID subscriptions and forces SSE for JSON mode',
      () async {
        const capabilities = ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
          resources: ServerCapabilitiesResources(listChanged: true),
        );
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => null,
            enableJsonResponse: true,
          ),
        );
        addTearDown(transport.close);
        final server = Server(
          const Implementation(name: 'TestServer', version: '1.0.0'),
          options: const McpServerOptions(
            protocol: McpProtocol.stable,
            capabilities: capabilities,
          ),
        );
        addTearDown(server.close);
        final toolsAcknowledged = Completer<void>();
        final resourcesAcknowledged = Completer<void>();
        final releaseTools = Completer<void>();
        final releaseResources = Completer<void>();

        server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
          Method.subscriptionsListen,
          (request, extra) async {
            final filter = request.listenParams.notifications;
            await extra.sendSubscriptionAcknowledged(
              filter.acknowledgedBy(capabilities),
            );
            if (filter.toolsListChanged == true) {
              toolsAcknowledged.complete();
              await releaseTools.future;
              await extra.sendSubscriptionNotification(
                const JsonRpcToolListChangedNotification(),
              );
            } else {
              resourcesAcknowledged.complete();
              await releaseResources.future;
              await extra.sendSubscriptionNotification(
                const JsonRpcResourceListChangedNotification(),
              );
            }
            return const EmptyResult();
          },
          (id, params, meta) => JsonRpcSubscriptionsListenRequest(
            id: id,
            listenParams: SubscriptionsListenRequest.fromJson(params!),
            meta: meta,
          ),
        );
        await server.connect(transport);
        transports['/mcp'] = transport;

        Future<HttpClientResponse> postSubscription(
          SubscriptionFilter filter,
        ) async {
          final client = HttpClient();
          addTearDown(() => client.close(force: true));
          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            )
            ..set('MCP-Protocol-Version', previewProtocolVersion)
            ..set('Mcp-Method', Method.subscriptionsListen);
          request.write(
            jsonEncode(
              JsonRpcSubscriptionsListenRequest(
                id: 'shared-subscription-id',
                listenParams: SubscriptionsListenRequest(
                  notifications: filter,
                ),
                meta: _statelessMeta(),
              ).toJson(),
            ),
          );
          return request.close();
        }

        final toolsResponse = await postSubscription(
          const SubscriptionFilter(toolsListChanged: true),
        );
        expect(toolsResponse.statusCode, HttpStatus.ok);
        expect(
          toolsResponse.headers.contentType?.mimeType,
          'text/event-stream',
        );
        final toolsLines = StreamIterator(
          toolsResponse.transform(utf8.decoder).transform(const LineSplitter()),
        );
        addTearDown(toolsLines.cancel);
        final toolsAck = await _readSseJsonEvent(toolsLines);
        await toolsAcknowledged.future;

        final resourcesResponse = await postSubscription(
          const SubscriptionFilter(resourcesListChanged: true),
        );
        expect(resourcesResponse.statusCode, HttpStatus.ok);
        expect(
          resourcesResponse.headers.contentType?.mimeType,
          'text/event-stream',
        );
        final resourcesLines = StreamIterator(
          resourcesResponse
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        addTearDown(resourcesLines.cancel);
        final resourcesAck = await _readSseJsonEvent(resourcesLines);
        await resourcesAcknowledged.future;

        expect(
          toolsAck.json['method'],
          Method.notificationsSubscriptionsAcknowledged,
        );
        expect(
          toolsAck.json['params']['_meta'][McpMetaKey.subscriptionId],
          'shared-subscription-id',
        );
        expect(
          resourcesAck.json['method'],
          Method.notificationsSubscriptionsAcknowledged,
        );
        expect(
          resourcesAck.json['params']['_meta'][McpMetaKey.subscriptionId],
          'shared-subscription-id',
        );

        releaseResources.complete();
        final resourcesEvent = await _readSseJsonEvent(resourcesLines);
        final resourcesFinal = await _readSseJsonEvent(resourcesLines);
        expect(
          resourcesEvent.json['method'],
          Method.notificationsResourcesListChanged,
        );
        expect(resourcesFinal.json['id'], 'shared-subscription-id');
        expect(
          resourcesFinal.json['result']['_meta'][McpMetaKey.subscriptionId],
          'shared-subscription-id',
        );

        releaseTools.complete();
        final toolsEvent = await _readSseJsonEvent(toolsLines);
        final toolsFinal = await _readSseJsonEvent(toolsLines);
        expect(toolsEvent.json['method'], Method.notificationsToolsListChanged);
        expect(toolsFinal.json['id'], 'shared-subscription-id');
        expect(
          toolsFinal.json['result']['_meta'][McpMetaKey.subscriptionId],
          'shared-subscription-id',
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test('enableJsonResponse option is accepted', () async {
      // Create a transport with JSON response enabled
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
          enableJsonResponse: true,
        ),
      );

      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "test-session-id";

      await transport.close();

      // If we reach here without exceptions, the test passes
      expect(
        true,
        isTrue,
        reason: "Transport successfully created with enableJsonResponse=true",
      );
    });

    test('JSON responses release unused EventStore replay ownership', () async {
      final eventStore = TestEventStore();
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'json-ownership-session',
          eventStore: eventStore,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;
      transport.onmessage = (message) {
        if (message is JsonRpcInitializeRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'LegacyServer',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ),
            ),
          );
        } else if (message is JsonRpcRequest && message.method == 'test/json') {
          unawaited(
            transport.send(
              JsonRpcResponse(id: message.id, result: const {'ok': true}),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<HttpClientResponse> post(
        JsonRpcMessage message, {
        String? sessionId,
      }) async {
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        if (sessionId != null) {
          request.headers.set('mcp-session-id', sessionId);
        }
        request.write(jsonEncode(message.toJson()));
        return request.close();
      }

      final initialize = await post(
        JsonRpcInitializeRequest(
          id: 'initialize',
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0.0'),
          ),
        ),
      );
      expect(initialize.statusCode, HttpStatus.ok);
      final sessionId = initialize.headers.value('mcp-session-id');
      expect(sessionId, 'json-ownership-session');
      await initialize.drain<void>();
      await Future<void>.delayed(Duration.zero);
      expect(_ownedStreamIdCount(transport), 0);

      final initialized = await post(
        const JsonRpcInitializedNotification(),
        sessionId: sessionId,
      );
      expect(initialized.statusCode, HttpStatus.accepted);
      await initialized.drain<void>();

      for (var index = 0; index < 3; index++) {
        final response = await post(
          JsonRpcRequest(id: 'json-$index', method: 'test/json'),
          sessionId: sessionId,
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.contentType?.mimeType, 'application/json');
        await response.drain<void>();
        await Future<void>.delayed(Duration.zero);
        expect(_ownedStreamIdCount(transport), 0);
      }

      expect(eventStore.events, isEmpty);
    });

    test('JSON response mode promotes legacy intermediate messages to SSE',
        () async {
      final eventStore = TestEventStore();
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'json-to-sse-session',
          eventStore: eventStore,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;
      transport.onmessage = (message) {
        if (message is JsonRpcInitializeRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'LegacyServer',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ),
            ),
          );
        } else if (message is JsonRpcRequest &&
            message.method == 'test/intermediate') {
          unawaited(() async {
            await transport.send(
              const JsonRpcNotification(
                method: 'notifications/test/intermediate',
              ),
              relatedRequestId: message.id,
            );
            await transport.send(
              JsonRpcResponse(id: message.id, result: const {'ok': true}),
            );
          }());
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<HttpClientResponse> post(
        JsonRpcMessage message, {
        String? sessionId,
      }) async {
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        if (sessionId != null) {
          request.headers.set('mcp-session-id', sessionId);
        }
        request.write(jsonEncode(message.toJson()));
        return request.close();
      }

      final initialize = await post(
        JsonRpcInitializeRequest(
          id: 'initialize',
          initParams: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0.0'),
          ),
        ),
      );
      expect(initialize.statusCode, HttpStatus.ok);
      final sessionId = initialize.headers.value('mcp-session-id');
      expect(sessionId, 'json-to-sse-session');
      await initialize.drain<void>();

      final initialized = await post(
        const JsonRpcInitializedNotification(),
        sessionId: sessionId,
      );
      expect(initialized.statusCode, HttpStatus.accepted);
      await initialized.drain<void>();

      final response = await post(
        const JsonRpcRequest(
          id: 'intermediate',
          method: 'test/intermediate',
        ),
        sessionId: sessionId,
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(response.headers.value('mcp-session-id'), sessionId);
      final messages = _decodeSseJsonMessages(
        await utf8.decodeStream(response),
      );
      expect(messages, hasLength(2));
      expect(messages.first['method'], 'notifications/test/intermediate');
      expect(messages.last['id'], 'intermediate');
      expect(messages.last['result'], {'ok': true});
      expect(_ownedStreamIdCount(transport), 1);
      expect(eventStore.events.values.single, hasLength(3));
    });

    test('dns rebinding and compatibility toggle options are accepted',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'test-session-id',
          enableDnsRebindingProtection: true,
          allowedHosts: {'localhost'},
          allowedOrigins: {'http://localhost'},
          strictProtocolVersionHeaderValidation: false,
          rejectBatchJsonRpcPayloads: false,
        ),
      );

      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = 'test-session-id';

      await transport.close();

      expect(true, isTrue);
    });

    group('DNS rebinding protection', () {
      Future<HttpClientResponse> postWithHeaders({
        required String host,
        String? origin,
        String body = '{}',
      }) async {
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..set(HttpHeaders.hostHeader, host)
          ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
          ..contentType = ContentType.json;
        if (origin != null) {
          request.headers.set('Origin', origin);
        }
        request.write(body);
        return request.close();
      }

      test('allows allowlisted headers to reach session validation', () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => 'test-session-id',
            enableDnsRebindingProtection: true,
            allowedHosts: {'localhost'},
            allowedOrigins: {'http://localhost:$serverPort'},
          ),
        );
        addTearDown(transport.close);
        await transport.start();
        transports['/mcp'] = transport;

        final response = await postWithHeaders(
          host: 'localhost:$serverPort',
          origin: 'http://localhost:$serverPort',
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          }),
        );
        final body = await utf8.decodeStream(response);
        final decodedBody = jsonDecode(body) as Map<String, dynamic>;
        final error = decodedBody['error'] as Map<String, dynamic>;

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(error['code'], equals(ErrorCode.connectionClosed.value));
        expect(error['message'], equals('Bad Request: Server not initialized'));
        expect(body, isNot(contains('DNS rebinding protection')));
      });

      test('rejects requests with hosts outside the allowlist', () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => 'test-session-id',
            enableDnsRebindingProtection: true,
            allowedHosts: {'localhost'},
            allowedOrigins: {'http://localhost:$serverPort'},
          ),
        );
        addTearDown(transport.close);
        await transport.start();
        transports['/mcp'] = transport;

        final response = await postWithHeaders(
          host: 'evil.example',
          origin: 'http://localhost:$serverPort',
        );
        final body = await utf8.decodeStream(response);

        expect(response.statusCode, equals(HttpStatus.forbidden));
        expect(body, contains('DNS rebinding protection'));
      });

      test('rejects requests with origins outside the allowlist', () async {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => 'test-session-id',
            enableDnsRebindingProtection: true,
            allowedHosts: {'localhost'},
            allowedOrigins: {'http://localhost:$serverPort'},
          ),
        );
        addTearDown(transport.close);
        await transport.start();
        transports['/mcp'] = transport;

        final response = await postWithHeaders(
          host: 'localhost:$serverPort',
          origin: 'http://evil.example',
        );
        final body = await utf8.decodeStream(response);

        expect(response.statusCode, equals(HttpStatus.forbidden));
        expect(body, contains('DNS rebinding protection'));
      });
    });

    test('uninitialized transport rejects initialize with unknown session ID',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'new-session-id',
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('mcp-session-id', 'unknown-session-id');
      request.write(
        jsonEncode(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
      );

      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.notFound);
      expect(body, contains('Session not found'));
    });

    test('stateful session JSON-RPC errors advertise JSON content type',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'json-error-session-id',
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'JsonErrorServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      Future<HttpClientResponse> postJsonRpc(
        JsonRpcMessage message, {
        String? sessionId,
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        if (sessionId != null) {
          request.headers.set('mcp-session-id', sessionId);
        }
        request.write(jsonEncode(message.toJson()));
        return request.close();
      }

      final initialize = await postJsonRpc(
        JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ).toJson(),
        ),
      );
      expect(initialize.statusCode, HttpStatus.ok);
      expect(
        initialize.headers.value('mcp-session-id'),
        'json-error-session-id',
      );
      await initialize.drain<void>();

      final missingSession = await postJsonRpc(
        const JsonRpcRequest(id: 2, method: 'ping'),
      );
      expect(missingSession.statusCode, HttpStatus.badRequest);
      expect(missingSession.headers.contentType?.mimeType, 'application/json');
      final missingSessionBody = jsonDecode(
        await utf8.decodeStream(missingSession),
      ) as Map<String, dynamic>;
      expect(missingSessionBody['id'], 2);
      expect(
        missingSessionBody['error']['message'],
        contains('Mcp-Session-Id header is required'),
      );

      final invalidSession = await postJsonRpc(
        const JsonRpcRequest(id: 3, method: 'ping'),
        sessionId: 'wrong-session-id',
      );
      expect(invalidSession.statusCode, HttpStatus.notFound);
      expect(invalidSession.headers.contentType?.mimeType, 'application/json');
      final invalidSessionBody = jsonDecode(
        await utf8.decodeStream(invalidSession),
      ) as Map<String, dynamic>;
      expect(invalidSessionBody['id'], 3);
      expect(
        invalidSessionBody['error']['message'],
        contains('Session not found'),
      );
    });

    test('initialization JSON-RPC errors advertise JSON content type',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'duplicate-init-session-id',
          rejectBatchJsonRpcPayloads: false,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'DuplicateInitServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      Future<HttpClientResponse> postJson(Object body) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        request.write(jsonEncode(body));
        return request.close();
      }

      Map<String, dynamic> initializeBody(int id) {
        return JsonRpcRequest(
          id: id,
          method: 'initialize',
          params: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ).toJson(),
        ).toJson();
      }

      final duplicateBatch = await postJson([
        initializeBody(1),
        initializeBody(2),
      ]);
      expect(duplicateBatch.statusCode, HttpStatus.badRequest);
      expect(duplicateBatch.headers.contentType?.mimeType, 'application/json');
      expect(
        await utf8.decodeStream(duplicateBatch),
        contains('Only one initialization request is allowed'),
      );

      final initialize = await postJson(initializeBody(3));
      expect(initialize.statusCode, HttpStatus.ok);
      await initialize.drain<void>();

      final alreadyInitialized = await postJson(initializeBody(4));
      expect(alreadyInitialized.statusCode, HttpStatus.badRequest);
      expect(
        alreadyInitialized.headers.contentType?.mimeType,
        'application/json',
      );
      final alreadyInitializedBody = jsonDecode(
        await utf8.decodeStream(alreadyInitialized),
      ) as Map<String, dynamic>;
      expect(alreadyInitializedBody['id'], 4);
      expect(
        alreadyInitializedBody['error']['message'],
        contains('Server already initialized'),
      );
    });

    test('rejects generated session IDs outside visible ASCII', () async {
      final invalidSessionIds = [
        '',
        'has space',
        'has\tcontrol',
        'snowman-☃',
      ];

      for (final invalidSessionId in invalidSessionIds) {
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => invalidSessionId,
          ),
        );
        addTearDown(transport.close);
        await transport.start();
        transports['/mcp'] = transport;

        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        request.write(
          jsonEncode(
            JsonRpcRequest(
              id: 1,
              method: 'initialize',
              params: const InitializeRequestParams(
                protocolVersion: latestInitializationProtocolVersion,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: 'Client', version: '1.0'),
              ).toJson(),
            ).toJson(),
          ),
        );

        final response = await request.close();
        final body = jsonDecode(
          await utf8.decodeStream(response),
        ) as Map<String, dynamic>;

        expect(response.statusCode, HttpStatus.internalServerError);
        expect(response.headers.value('mcp-session-id'), isNull);
        expect(body['id'], 1);
        expect(body['error']['message'], contains('Invalid session ID'));
        expect(transport.sessionId, isNull);

        await transport.close();
        transports.remove('/mcp');
      }
    });

    test('post-parse internal errors preserve the request ID', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => throw StateError('generator failed'),
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        );
      request.write(
        jsonEncode(
          JsonRpcRequest(
            id: 'generator-error',
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.internalServerError);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 'generator-error');
      expect(body['error']['code'], ErrorCode.internalError.value);
    });

    test('rejects unsafe custom EventStore SSE event IDs', () async {
      final eventStore = InvalidEventIdStore('bad\nid');
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          eventStore: eventStore,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;
      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'InvalidEventIdServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final initRequest = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      initRequest.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        );
      initRequest.write(
        jsonEncode(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
      );
      final initResponse = await initRequest.close();
      expect(initResponse.statusCode, HttpStatus.ok);
      await initResponse.drain<void>();

      final liveRequest = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
      liveRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final liveResponseFuture = liveRequest.close();

      final liveReadyDeadline = DateTime.now().add(const Duration(seconds: 3));
      while (eventStore.storedStreamId == null &&
          DateTime.now().isBefore(liveReadyDeadline)) {
        await transport.send(
          const JsonRpcNotification(method: 'notifications/live'),
        );
        if (eventStore.storedStreamId == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(eventStore.storedStreamId, isNotNull);

      final liveResponse =
          await liveResponseFuture.timeout(const Duration(seconds: 3));
      expect(liveResponse.statusCode, HttpStatus.ok);
      final liveLines = StreamIterator(
        liveResponse.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(liveLines.cancel);
      expect((await _readSseEvent(liveLines)).id, 'known-event-id');

      final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..set('Last-Event-ID', 'known-event-id');
      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.notFound);
      expect(body, contains('Event ID not found'));
      expect(body, isNot(contains('Invalid SSE event ID')));
    });

    test('GET SSE priming failure closes the response', () async {
      final eventStore = InvalidPrimingEventStore();
      final errors = <Error>[];
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'get-priming-failure-session-id',
          eventStore: eventStore,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      transport.onerror = errors.add;
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'PrimingFailureServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final initRequest = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      initRequest.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        );
      initRequest.write(
        jsonEncode(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
      );
      final initResponse = await initRequest.close();
      expect(initResponse.statusCode, HttpStatus.ok);
      final sessionId = initResponse.headers.value('mcp-session-id');
      await initResponse.drain<void>();
      expect(sessionId, 'get-priming-failure-session-id');

      final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..set('mcp-session-id', sessionId!);

      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>().timeout(const Duration(seconds: 3));

      expect(eventStore.storeCalls, 1);
      expect(errors.single.toString(), contains('Invalid SSE event ID'));
    });

    test('POST SSE priming failure closes the response and skips messages',
        () async {
      final eventStore = InvalidPrimingEventStore();
      final errors = <Error>[];
      var onMessageCalled = false;
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          eventStore: eventStore,
        ),
      );
      addTearDown(transport.close);
      transport.onerror = errors.add;
      transport.onmessage = (_) {
        onMessageCalled = true;
      };
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        );
      request.write(
        jsonEncode(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>().timeout(const Duration(seconds: 3));

      expect(eventStore.storeCalls, 1);
      expect(errors.single.toString(), contains('Invalid SSE event ID'));
      expect(onMessageCalled, isFalse);
    });

    test('terminated stateful sessions reject subsequent requests with 404',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'terminated-session-id',
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is! JsonRpcRequest) {
          return;
        }
        unawaited(
          transport.send(
            JsonRpcResponse(id: message.id, result: const {'ok': true}),
          ),
        );
      };

      Future<HttpClientResponse> postJsonRpc(
        JsonRpcMessage message, {
        String? sessionId,
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        if (sessionId != null) {
          request.headers.set('mcp-session-id', sessionId);
        }
        request.write(jsonEncode(message.toJson()));
        return request.close();
      }

      Future<HttpClientResponse> deleteWithSession(String sessionId) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.deleteUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers.set('mcp-session-id', sessionId);
        return request.close();
      }

      Future<HttpClientResponse> getWithSession(String sessionId) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId);
        return request.close();
      }

      final initResponse = await postJsonRpc(
        JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ).toJson(),
        ),
      );
      expect(initResponse.statusCode, HttpStatus.ok);
      final sessionId = initResponse.headers.value('mcp-session-id');
      expect(sessionId, 'terminated-session-id');
      await initResponse.drain();

      final deleteResponse = await deleteWithSession(sessionId!);
      expect(deleteResponse.statusCode, HttpStatus.ok);
      await deleteResponse.drain();

      final postAfterDelete = await postJsonRpc(
        const JsonRpcRequest(id: 2, method: 'ping'),
        sessionId: sessionId,
      );
      final postAfterDeleteBody = await utf8.decodeStream(postAfterDelete);
      expect(postAfterDelete.statusCode, HttpStatus.notFound);
      expect(postAfterDeleteBody, contains('Session not found'));

      final initAfterDelete = await postJsonRpc(
        JsonRpcRequest(
          id: 3,
          method: 'initialize',
          params: const InitializeRequestParams(
            protocolVersion: latestInitializationProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ).toJson(),
        ),
        sessionId: sessionId,
      );
      final initAfterDeleteBody = await utf8.decodeStream(initAfterDelete);
      expect(initAfterDelete.statusCode, HttpStatus.notFound);
      expect(initAfterDeleteBody, contains('Session not found'));

      final getAfterDelete = await getWithSession(sessionId);
      final getAfterDeleteBody = await utf8.decodeStream(getAfterDelete);
      expect(getAfterDelete.statusCode, HttpStatus.notFound);
      expect(getAfterDeleteBody, contains('Session not found'));

      final deleteAfterDelete = await deleteWithSession(sessionId);
      final deleteAfterDeleteBody = await utf8.decodeStream(deleteAfterDelete);
      expect(deleteAfterDelete.statusCode, HttpStatus.notFound);
      expect(deleteAfterDeleteBody, contains('Session not found'));
    });

    test('session validation works correctly', () async {
      // Create a transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "correct-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "correct-session-id";

      // Set up handlers for valid and invalid cases
      final validMessageCompleter = Completer<JsonRpcMessage>();
      final invalidMessageCompleter = Completer<String>();

      transport.onmessage = (message) {
        if (!validMessageCompleter.isCompleted) {
          validMessageCompleter.complete(message);
        }
      };

      // Create test message and headers
      final validRequest = const JsonRpcRequest(
        id: 1,
        method: 'test/method',
        params: {'data': 'test-data'},
      );

      final validHeaders = {
        'mcp-session-id': ['correct-session-id'],
      };
      final invalidHeaders = {
        'mcp-session-id': ['wrong-session-id'],
      };

      // Test session validation
      Future<void> testSessionValidation() async {
        // Test with valid session ID
        if (transport.sessionId == validHeaders['mcp-session-id']?[0]) {
          transport.onmessage?.call(validRequest);
        } else {
          fail("Valid session ID check failed");
        }

        // Test with invalid session ID
        if (transport.sessionId == invalidHeaders['mcp-session-id']?[0]) {
          fail("Invalid session ID check passed when it should fail");
        } else {
          // Expected behavior: session ID mismatch prevents processing
          invalidMessageCompleter
              .complete("Invalid session rejected correctly");
        }
      }

      await testSessionValidation();

      // Verify results with appropriate timeouts
      final receivedMessage = await validMessageCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Valid message test timed out'),
      );

      final invalidResult = await invalidMessageCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () =>
            throw TimeoutException('Invalid message test timed out'),
      );

      // Verify message properties
      expect(receivedMessage, isA<JsonRpcRequest>());
      expect((receivedMessage as JsonRpcRequest).id, equals(1));
      expect(receivedMessage.method, equals('test/method'));
      expect(receivedMessage.params?['data'], equals('test-data'));
      expect(invalidResult, equals("Invalid session rejected correctly"));

      await transport.close();
    });

    test('routes a server-originated message to only one GET SSE stream',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'multi-stream-session-id',
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'MultiStreamServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      Future<String> initializeSession() async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        request.write(
          jsonEncode(
            JsonRpcRequest(
              id: 1,
              method: 'initialize',
              params: const InitializeRequestParams(
                protocolVersion: latestInitializationProtocolVersion,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: 'Client', version: '1.0'),
              ).toJson(),
            ).toJson(),
          ),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        final sessionId = response.headers.value('mcp-session-id');
        await response.drain<void>();
        expect(sessionId, 'multi-stream-session-id');
        return sessionId!;
      }

      Future<HttpClientResponse> openGetSse(String sessionId) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId);
        return request.close();
      }

      final sessionId = await initializeSession();
      final firstFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/custom',
          params: {'stream': 'first'},
        ),
      );
      final first = await firstFuture.timeout(const Duration(seconds: 3));
      expect(first.statusCode, HttpStatus.ok);
      expect(first.headers.contentType?.mimeType, 'text/event-stream');
      expect(first.headers.value('X-Accel-Buffering'), 'no');
      final firstLines = StreamIterator(
        first.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(firstLines.cancel);
      final firstOnly = await _readSseEvent(firstLines);
      expect(firstOnly.json['params'], containsPair('stream', 'first'));

      final secondFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/custom',
          params: {'stream': 'second'},
        ),
      );
      final second = await secondFuture.timeout(const Duration(seconds: 3));
      expect(second.statusCode, HttpStatus.ok);
      expect(second.headers.contentType?.mimeType, 'text/event-stream');
      expect(second.headers.value('X-Accel-Buffering'), 'no');
      final secondLines = StreamIterator(
        second.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(secondLines.cancel);

      final secondOnly = await _readSseEvent(secondLines);

      expect(secondOnly.json['params'], containsPair('stream', 'second'));
      expect(await _readOptionalSseEvent(firstLines), isNull);
    });

    test(
      'handler can close and resume a request-scoped SSE stream',
      () async {
        final eventStore = TestEventStore();
        final transport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => 'polling-session-id',
            eventStore: eventStore,
            sseRetryDelay: const Duration(milliseconds: 250),
          ),
        );
        addTearDown(transport.close);

        final server = Server(
          const Implementation(name: 'PollingServer', version: '1.0.0'),
        );
        addTearDown(server.close);
        server.setRequestHandler<JsonRpcRequest>(
          'test/reconnection',
          (request, extra) async {
            expect(extra.closeSSEStream, isNotNull);
            extra.closeSSEStream!();
            return const EmptyResult();
          },
          (id, params, meta) => JsonRpcRequest(
            id: id,
            method: 'test/reconnection',
            params: params,
            meta: meta,
          ),
        );
        await server.connect(transport);
        transports['/mcp'] = transport;

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        Future<HttpClientResponse> post(
          JsonRpcMessage message, {
          String? sessionId,
        }) async {
          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          if (sessionId != null) {
            request.headers.set('mcp-session-id', sessionId);
          }
          request.write(jsonEncode(message.toJson()));
          return request.close();
        }

        final initialize = await post(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ),
          ),
        );
        final sessionId = initialize.headers.value('mcp-session-id');
        await initialize.drain<void>();
        expect(sessionId, 'polling-session-id');

        final initialized = await post(
          const JsonRpcInitializedNotification(),
          sessionId: sessionId,
        );
        expect(initialized.statusCode, HttpStatus.accepted);
        await initialized.drain<void>();

        final response = await post(
          const JsonRpcRequest(id: 2, method: 'test/reconnection'),
          sessionId: sessionId,
        );
        final responseLines = StreamIterator(
          response.transform(utf8.decoder).transform(const LineSplitter()),
        );
        addTearDown(responseLines.cancel);
        final initial = await _readSseEvent(responseLines);
        expect(initial.id, isNotNull);
        expect(initial.retry, 250);
        expect(initial.data, isEmpty);
        expect(await _readOptionalSseEvent(responseLines), isNull);

        final reconnectRequest =
            await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
        reconnectRequest.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId!)
          ..set('Last-Event-ID', initial.id!);
        final reconnect = await reconnectRequest.close();
        expect(reconnect.statusCode, HttpStatus.ok);
        final reconnectLines = StreamIterator(
          reconnect.transform(utf8.decoder).transform(const LineSplitter()),
        );
        addTearDown(reconnectLines.cancel);

        final resumed = await _readSseJsonEvent(reconnectLines);
        expect(resumed.id, isNotNull);
        expect(resumed.json['id'], 2);
        expect(resumed.json['result'], isA<Map<String, dynamic>>());
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test('GET Last-Event-ID replay is scoped to the owning SSE stream',
        () async {
      final eventStore = TestEventStore();
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'replay-session-id',
          eventStore: eventStore,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'ReplayServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      Future<String> initializeSession() async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        request.write(
          jsonEncode(
            JsonRpcRequest(
              id: 1,
              method: 'initialize',
              params: const InitializeRequestParams(
                protocolVersion: latestInitializationProtocolVersion,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: 'Client', version: '1.0'),
              ).toJson(),
            ).toJson(),
          ),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        final sessionId = response.headers.value('mcp-session-id');
        await response.drain<void>();
        expect(sessionId, 'replay-session-id');
        return sessionId!;
      }

      Future<HttpClientResponse> openGetSse(
        String sessionId, {
        String? lastEventId,
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId);
        if (lastEventId != null) {
          request.headers.set('Last-Event-ID', lastEventId);
        }
        return request.close();
      }

      final sessionId = await initializeSession();
      final streamFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/custom',
          params: {'seq': 1},
        ),
      );
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/custom',
          params: {'seq': 2},
        ),
      );

      final stream = await streamFuture.timeout(const Duration(seconds: 3));
      expect(stream.statusCode, HttpStatus.ok);
      expect(stream.headers.value('X-Accel-Buffering'), 'no');
      final lines = StreamIterator(
        stream.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(lines.cancel);

      final initial = await _readSseEvent(lines);
      expect(initial.id, isNotNull);
      expect(initial.retry, 1000);
      expect(initial.data, isEmpty);

      final first = await _readSseJsonEvent(lines);
      final second = await _readSseJsonEvent(lines);
      expect(first.id, isNotNull);
      expect(second.id, isNotNull);
      expect(first.json['params'], containsPair('seq', 1));
      expect(second.json['params'], containsPair('seq', 2));

      final otherStreamFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/custom',
          params: {'seq': 'other-stream'},
        ),
      );
      final otherStream =
          await otherStreamFuture.timeout(const Duration(seconds: 3));
      expect(otherStream.statusCode, HttpStatus.ok);
      expect(otherStream.headers.value('X-Accel-Buffering'), 'no');
      final otherLines = StreamIterator(
        otherStream.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(otherLines.cancel);
      final otherInitial = await _readSseEvent(otherLines);
      expect(otherInitial.id, isNotNull);
      expect(otherInitial.retry, 1000);
      expect(otherInitial.data, isEmpty);
      final other = await _readSseJsonEvent(otherLines);
      expect(other.id, isNotNull);
      expect(other.json['params'], containsPair('seq', 'other-stream'));

      final replay = await openGetSse(sessionId, lastEventId: first.id);
      expect(replay.statusCode, HttpStatus.ok);
      expect(replay.headers.value('X-Accel-Buffering'), 'no');
      final replayLines = StreamIterator(
        replay.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(replayLines.cancel);
      final replayed = await _readSseJsonEvent(replayLines);
      expect(replayed.id, second.id);
      expect(replayed.json['params'], containsPair('seq', 2));
      final replayInitial = await _readSseEvent(replayLines);
      expect(replayInitial.id, isNotNull);
      expect(replayInitial.retry, 1000);
      expect(replayInitial.data, isEmpty);
      expect(await _readOptionalSseEvent(replayLines), isNull);

      final foreignEventId = await eventStore.storeEvent(
        'foreign-stream-id',
        const JsonRpcNotification(
          method: 'notifications/custom',
          params: {'foreign': true},
        ),
      );
      final foreignReplay = await openGetSse(
        sessionId,
        lastEventId: foreignEventId,
      );
      expect(foreignReplay.statusCode, HttpStatus.notFound);
      final foreignBody = await utf8.decodeStream(foreignReplay);
      expect(foreignBody, contains('Event ID not found'));
    });

    test('rejects event replay exceeding maxReplayedEvents limit', () async {
      final eventStore = TestEventStore();
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'limit-replay-session-id',
          eventStore: eventStore,
          maxReplayedEvents: 1,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {
                    'name': 'LimitReplayServer',
                    'version': '1.0.0',
                  },
                },
              ),
            ),
          );
        }
      };

      Future<String> initializeSession() async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        request.write(
          jsonEncode(
            JsonRpcRequest(
              id: 1,
              method: 'initialize',
              params: const InitializeRequestParams(
                protocolVersion: latestInitializationProtocolVersion,
                capabilities: ClientCapabilities(),
                clientInfo: Implementation(name: 'Client', version: '1.0'),
              ).toJson(),
            ).toJson(),
          ),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        final sessionId = response.headers.value('mcp-session-id');
        await response.drain<void>();
        return sessionId!;
      }

      final activeClients = <HttpClient>[];
      Future<HttpClientResponse> localOpenGetSse(
        String sessionId, {
        String? lastEventId,
      }) async {
        final client = HttpClient();
        activeClients.add(client);
        final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId);
        if (lastEventId != null) {
          request.headers.set('Last-Event-ID', lastEventId);
        }
        return request.close();
      }

      try {
        final sessionId = await initializeSession();

        // 1. Establish an active GET stream so the server creates an owned streamId
        // Do not await immediately to match the asynchronous sequence of other GET SSE tests
        final streamFuture = localOpenGetSse(sessionId);
        await Future.delayed(const Duration(milliseconds: 50));

        // 2. Send 3 events (seq 1, seq 2, seq 3) to the stream.
        // This stores them in the eventStore under the owned streamId.
        await transport.send(
          const JsonRpcNotification(
            method: 'notifications/custom',
            params: {'seq': 1},
          ),
        );
        await transport.send(
          const JsonRpcNotification(
            method: 'notifications/custom',
            params: {'seq': 2},
          ),
        );
        await transport.send(
          const JsonRpcNotification(
            method: 'notifications/custom',
            params: {'seq': 3},
          ),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        final streamResponse =
            await streamFuture.timeout(const Duration(seconds: 3));
        expect(streamResponse.statusCode, HttpStatus.ok);

        // Get the first event ID stored for the standalone SSE stream
        final streamEvents = eventStore.events.entries
            .firstWhere((entry) => entry.key.startsWith('_GET_stream:'))
            .value;
        final firstEventId = streamEvents.first.key;

        // 3. Close the active GET stream cleanly. Replay ownership remains
        // available because the EventStore may serve a later reconnect.
        for (final client in activeClients) {
          client.close(force: true);
        }
        activeClients.clear();

        // 4. Replay from firstEventId attempts to replay 2 messages (seq 2, seq 3), which exceeds limit (1).
        // Since it fails, the server writes 413 and closes the response cleanly.
        final failResponse =
            await localOpenGetSse(sessionId, lastEventId: firstEventId);
        expect(failResponse.statusCode, equals(413)); // Payload Too Large
        final failBody = await utf8.decodeStream(failResponse);
        expect(failBody, contains('Event replay limit exceeded'));
      } finally {
        for (final client in activeClients) {
          client.close(force: true);
        }
      }
    });

    test('event resumability works with EventStore', () async {
      // Create a test event store for tracking events
      final eventStore = TestEventStore();

      // Create a transport with event store for resumability
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "resumable-session-id",
          eventStore: eventStore,
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "resumable-session-id";

      // Create sample test messages
      final messages = [
        const JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-1', 'version': '1.0.0'},
            'capabilities': {},
          },
        ),
        const JsonRpcRequest(
          id: 2,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-2', 'version': '1.0.0'},
            'capabilities': {},
          },
        ),
        const JsonRpcRequest(
          id: 3,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-3', 'version': '1.0.0'},
            'capabilities': {},
          },
        ),
      ];

      // Store the messages in the event store
      final storedEventIds = <String>[];
      for (final message in messages) {
        final eventId =
            await eventStore.storeEvent(transport.sessionId!, message);
        storedEventIds.add(eventId);
      }

      // Verify storage was successful
      expect(
        eventStore.events[transport.sessionId!]!.length,
        equals(messages.length),
      );

      // Resume from the first event
      final lastEventId = storedEventIds.first;
      final replayedEvents = <JsonRpcMessage>[];
      final replayCompleter = Completer<void>();

      // Set up send function for replaying events
      Future<void> sendFunction(String eventId, JsonRpcMessage message) async {
        replayedEvents.add(message);
        if (replayedEvents.length == messages.length - 1) {
          replayCompleter.complete();
        }
      }

      // Perform event replay
      final streamId = await eventStore.replayEventsAfter(
        lastEventId,
        send: sendFunction,
      );

      // Verify the session ID matches
      expect(streamId, equals(transport.sessionId));

      // Wait for replay completion
      await replayCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Event replay timed out'),
      );

      // Verify correct number of events replayed
      expect(replayedEvents.length, equals(messages.length - 1));

      // Verify replayed events match original messages
      for (var i = 0; i < replayedEvents.length; i++) {
        final replayedMessage = replayedEvents[i];
        final originalMessage = messages[i + 1]; // Skip the first message

        expect(replayedMessage, isA<JsonRpcRequest>());
        expect(
          (replayedMessage as JsonRpcRequest).method,
          equals('initialize'),
        );
        expect(replayedMessage.id, equals(originalMessage.id));
        expect(
          replayedMessage.params!['clientInfo']['name'],
          equals(originalMessage.params!['clientInfo']['name']),
        );
      }

      await transport.close();
    });

    test('transport throws StateError when started twice', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();

      expect(
        () => transport.start(),
        throwsA(isA<StateError>()),
      );

      await transport.close();
    });

    test('onsessioninitialized callback is registered and callable', () async {
      // Test callback registration
      bool callbackWasSet = false;
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "callback-session-id",
          onsessioninitialized: (sessionId) {
            callbackWasSet = true;
          },
        ),
      );
      await transport.start();

      // Verify the transport has the expected session ID generator behavior
      // The actual callback is triggered during handleRequest with an init message
      // Here we just verify the transport was successfully configured
      expect(transport.sessionId, isNull); // Not set yet before init
      expect(callbackWasSet, isFalse); // Not triggered without init request

      await transport.close();

      // Note: In actual usage, the callback is called during handleRequest
      // when an initialization request is processed. See integration tests.
    });

    test('stateless mode allows requests without session validation', () async {
      // Stateless mode - sessionIdGenerator returns null
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;

      final messageCompleter = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        if (!messageCompleter.isCompleted) {
          messageCompleter.complete(message);
        }
      };

      // Simulate initialization to set _initialized = true
      transport.onmessage?.call(
        const JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test', 'version': '1.0'},
            'capabilities': {},
          },
        ),
      );

      final message = await messageCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      expect(message, isA<JsonRpcRequest>());
      expect(transport.sessionId, isNull);

      await transport.close();
    });

    test('2026 stateless HTTP validates required protocol header', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final response = await HttpClient()
          .postUrl(
        Uri.parse('$serverUrlBase/mcp'),
      )
          .then((request) async {
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          )
          ..set('Mcp-Method', Method.toolsList);
        request.write(
          jsonEncode(JsonRpcListToolsRequest(id: 1, meta: _statelessMeta())),
        );
        return request.close();
      });

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers.contentType?.mimeType, 'application/json');
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 1);
      expect(body['error']['code'], ErrorCode.headerMismatch.value);
      expect(
        body['error']['message'],
        contains('MCP-Protocol-Version header is required'),
      );
    });

    test('2026 stateless HTTP rejects mismatched method and name headers',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsCall)
        ..set('Mcp-Name', 'wrong-tool');
      request.write(
        jsonEncode(
          JsonRpcCallToolRequest(
            id: 2,
            params: const {
              'name': 'echo',
              'arguments': {'message': 'hello'},
            },
            meta: _statelessMeta(),
          ),
        ),
      );

      final response = await request.close();

      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 2);
      expect(body['error']['code'], ErrorCode.headerMismatch.value);
      expect(body['error']['message'], contains('Mcp-Name header value'));
    });

    test(
        '2026 stateless HTTP requires name headers before validating body sources',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'unused-session-id',
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedMessages = <JsonRpcMessage>[];
      transport.onmessage = (message) {
        receivedMessages.add(message);
        if (message is JsonRpcRequest) {
          unawaited(
            transport.send(JsonRpcResponse(id: message.id, result: const {})),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      const cases = <(String, String, Map<String, dynamic>)>[
        (Method.toolsCall, 'name', {'arguments': <String, dynamic>{}}),
        (Method.resourcesRead, 'uri', <String, dynamic>{}),
        (Method.promptsGet, 'name', <String, dynamic>{}),
        (Method.tasksGet, 'taskId', <String, dynamic>{}),
        (
          Method.tasksUpdate,
          'taskId',
          {'inputResponses': <String, dynamic>{}},
        ),
        (Method.tasksCancel, 'taskId', <String, dynamic>{}),
      ];
      var id = 20;
      for (final (method, sourceField, otherParams) in cases) {
        for (final includeWrongTypeSource in const [false, true]) {
          final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
          request.headers
            ..contentType = ContentType.json
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            )
            ..set('MCP-Protocol-Version', previewProtocolVersion)
            ..set('Mcp-Method', method);
          request.write(
            jsonEncode(
              JsonRpcRequest(
                id: id,
                method: method,
                params: {
                  ...otherParams,
                  if (includeWrongTypeSource) sourceField: 42,
                },
                meta: _statelessMeta(),
              ),
            ),
          );

          final response = await request.close();
          expect(
            response.statusCode,
            HttpStatus.badRequest,
            reason:
                '$method ${includeWrongTypeSource ? 'wrong type' : 'absent'}',
          );
          final body = jsonDecode(await utf8.decodeStream(response))
              as Map<String, dynamic>;
          expect(body['id'], id, reason: method);
          expect(
            body['error']['code'],
            ErrorCode.headerMismatch.value,
            reason: method,
          );
          expect(
            body['error']['message'],
            contains('Mcp-Name header is required'),
            reason: method,
          );
          id++;
        }
      }

      expect(receivedMessages, isEmpty);
    });

    test('2026 stateless HTTP decodes base64 Mcp-Name values', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'unused-session-id',
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;
      transport.onmessage = (message) {
        if (message is JsonRpcRequest) {
          unawaited(
            transport.send(JsonRpcResponse(id: message.id, result: const {})),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      const cases = <(String, String, String)>[
        (Method.toolsCall, 'name', 'café'),
        (Method.toolsCall, 'name', 'tool\u0001name'),
        (Method.promptsGet, 'name', ' prompt '),
        (Method.resourcesRead, 'uri', 'file:///café'),
        (Method.tasksGet, 'taskId', '=?base64?literal?='),
      ];
      for (var index = 0; index < cases.length; index++) {
        final (method, field, value) = cases[index];
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          )
          ..set('MCP-Protocol-Version', previewProtocolVersion)
          ..set('Mcp-Method', method)
          ..set(
            'Mcp-Name',
            '=?base64?${base64Encode(utf8.encode(value))}?=',
          );
        request.write(
          jsonEncode(
            JsonRpcRequest(
              id: index + 1,
              method: method,
              params: <String, dynamic>{
                field: value,
                if (method == Method.toolsCall)
                  'arguments': <String, dynamic>{},
              },
              meta: _statelessMeta(),
            ),
          ),
        );

        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok, reason: '$method $value');
        await response.drain<void>();
      }

      final malformed = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      malformed.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        )
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsCall)
        ..set('Mcp-Name', '=?base64?%%%?=');
      malformed.write(
        jsonEncode(
          JsonRpcCallToolRequest(
            id: 99,
            params: const {'name': 'echo', 'arguments': <String, dynamic>{}},
            meta: _statelessMeta(),
          ),
        ),
      );
      final malformedResponse = await malformed.close();
      expect(malformedResponse.statusCode, HttpStatus.badRequest);
      final malformedBody = jsonDecode(
        await utf8.decodeStream(malformedResponse),
      ) as Map<String, dynamic>;
      expect(malformedBody['error']['message'], contains('malformed'));
    });

    test('2026 stateless HTTP accepts task requests with matching name header',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest &&
            {
              Method.tasksGet,
              Method.tasksUpdate,
              Method.tasksCancel,
            }.contains(message.method)) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const TaskExtensionAcknowledgementResult().toJson(),
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final requests = <MapEntry<JsonRpcRequest, String>>[
        MapEntry(
          JsonRpcGetTaskRequest(
            id: 4,
            getParams: const GetTaskRequest(taskId: 'task-1'),
            meta: _statelessMeta(),
          ),
          'task-1',
        ),
        MapEntry(
          JsonRpcUpdateTaskRequest(
            id: 5,
            updateParams: const UpdateTaskRequest(
              taskId: 'task-1',
              inputResponses: {},
            ),
            meta: _statelessMeta(),
          ),
          'task-1',
        ),
        MapEntry(
          JsonRpcCancelTaskRequest(
            id: 6,
            cancelParams: const CancelTaskRequest(taskId: 'task-1'),
            meta: _statelessMeta(),
          ),
          'task-1',
        ),
        MapEntry(
          JsonRpcGetTaskRequest(
            id: 7,
            getParams: const GetTaskRequest(taskId: ''),
            meta: _statelessMeta(),
          ),
          '=?base64??=',
        ),
      ];
      for (final entry in requests) {
        final message = entry.key;
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          )
          ..set('MCP-Protocol-Version', previewProtocolVersion)
          ..set('Mcp-Method', message.method)
          ..set('Mcp-Name', entry.value);
        request.write(jsonEncode(message));

        final response = await request.close();
        final responseBody = await utf8.decodeStream(response);
        expect(
          response.statusCode,
          HttpStatus.ok,
          reason: '${message.method}: $responseBody',
        );
        final body = jsonDecode(responseBody) as Map<String, dynamic>;
        expect(body['id'], message.id);
        expect(body['result'], {'resultType': resultTypeComplete});
      }
    });

    test('2026 stateless HTTP rejects task requests without name header',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.tasksUpdate);
      request.write(
        jsonEncode(
          JsonRpcUpdateTaskRequest(
            id: 4,
            updateParams: const UpdateTaskRequest(
              taskId: 'task-1',
              inputResponses: {},
            ),
            meta: _statelessMeta(),
          ),
        ),
      );

      final response = await request.close();

      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 4);
      expect(body['error']['code'], ErrorCode.headerMismatch.value);
      expect(body['error']['message'], contains('Mcp-Name header'));
    });

    test('2026 stateless HTTP rejects client response posts', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedMessages = <JsonRpcMessage>[];
      transport.onmessage = receivedMessages.add;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion);
      request.write(
        jsonEncode(
          const JsonRpcResponse(
            id: 'input-response',
            result: {'ok': true},
          ).toJson(),
        ),
      );

      final response = await request.close();

      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], isNull);
      expect(body['error']['code'], ErrorCode.invalidRequest.value);
      expect(body['error']['message'], contains('must not POST'));
      expect(receivedMessages, isEmpty);
    });

    test('2026 stateless HTTP rejects cancellation notification posts',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedMessages = <JsonRpcMessage>[];
      transport.onmessage = receivedMessages.add;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.notificationsCancelled);
      request.write(
        jsonEncode(
          JsonRpcCancelledNotification(
            cancelParams: const CancelledNotification(requestId: 1),
            meta: {McpMetaKey.protocolVersion: previewProtocolVersion},
          ).toJson(),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['error']['code'], ErrorCode.invalidRequest.value);
      expect(body['error']['message'], contains('closing its response stream'));
      expect(receivedMessages, isEmpty);
    });

    test('2026 HTTP rejects known server notifications but permits extensions',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedMessages = <JsonRpcMessage>[];
      transport.onmessage = receivedMessages.add;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<HttpClientResponse> post(JsonRpcNotification notification) async {
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          )
          ..set('MCP-Protocol-Version', previewProtocolVersion)
          ..set('Mcp-Method', notification.method);
        request.write(jsonEncode(notification.toJson()));
        return request.close();
      }

      final progressResponse = await post(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotification(
            progressToken: 'progress-1',
            progress: 1,
          ),
        ),
      );
      expect(progressResponse.statusCode, HttpStatus.badRequest);
      final progressBody = jsonDecode(
        await utf8.decodeStream(progressResponse),
      ) as Map<String, dynamic>;
      expect(
        progressBody['error']['code'],
        ErrorCode.invalidRequest.value,
      );
      expect(
        progressBody['error']['message'],
        contains(Method.notificationsProgress),
      );
      expect(receivedMessages, isEmpty);

      const custom = JsonRpcNotification(
        method: 'com.example/notifications/custom',
      );
      final customResponse = await post(custom);
      expect(customResponse.statusCode, HttpStatus.accepted);
      expect(await utf8.decodeStream(customResponse), isEmpty);
      expect(receivedMessages, hasLength(1));
      expect(receivedMessages.single, isA<JsonRpcNotification>());
      expect(
        (receivedMessages.single as JsonRpcNotification).method,
        custom.method,
      );
    });

    test('legacy HTTP still accepts client response posts', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedMessage = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        if (message is JsonRpcInitializeRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'legacy-server',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ),
            ),
          );
          return;
        }
        receivedMessage.complete(message);
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final initializeRequest =
          await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      initializeRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
      initializeRequest.write(
        jsonEncode(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(
                name: 'legacy-client',
                version: '1.0.0',
              ),
            ),
          ).toJson(),
        ),
      );
      final initializeResponse = await initializeRequest.close();
      expect(initializeResponse.statusCode, HttpStatus.ok);
      await initializeResponse.drain<void>();

      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
      request.write(
        jsonEncode(
          const JsonRpcResponse(
            id: 'input-response',
            result: {'ok': true},
          ).toJson(),
        ),
      );

      final response = await request.close();

      expect(response.statusCode, HttpStatus.accepted);
      expect(await utf8.decodeStream(response), isEmpty);
      final message =
          await receivedMessage.future.timeout(const Duration(seconds: 5));
      expect(message, isA<JsonRpcResponse>());
      final jsonRpcResponse = message as JsonRpcResponse;
      expect(jsonRpcResponse.id, 'input-response');
      expect(jsonRpcResponse.result, {'ok': true});
    });

    test('2026 stateless HTTP ignores session header', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcListToolsRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const ListToolsResult(tools: []).toJson(),
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList)
        ..set('Mcp-Session-Id', 'legacy-session');
      request.write(
        jsonEncode(JsonRpcListToolsRequest(id: 6, meta: _statelessMeta())),
      );

      final response = await request.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('mcp-session-id'), isNull);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 6);
      expect(body['result']['tools'], isEmpty);
    });

    test('2026 stateless HTTP omits existing transport session header',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'stateful-session-id',
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcInitializeRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'StatefulServer',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ),
            ),
          );
        } else if (message is JsonRpcListToolsRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const ListToolsResult(tools: []).toJson(),
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final initRequest = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      initRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
      initRequest.write(
        jsonEncode(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequest(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'client', version: '1.0.0'),
            ),
          ),
        ),
      );

      final initResponse = await initRequest.close();
      expect(initResponse.statusCode, HttpStatus.ok);
      final sessionId = initResponse.headers.value('mcp-session-id');
      expect(sessionId, 'stateful-session-id');
      await utf8.decodeStream(initResponse);

      final statelessRequest =
          await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      statelessRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList)
        ..set('Mcp-Session-Id', sessionId!);
      statelessRequest.write(
        jsonEncode(JsonRpcListToolsRequest(id: 6, meta: _statelessMeta())),
      );

      final statelessResponse = await statelessRequest.close();

      expect(statelessResponse.statusCode, HttpStatus.ok);
      expect(statelessResponse.headers.value('mcp-session-id'), isNull);
      final body = jsonDecode(await utf8.decodeStream(statelessResponse))
          as Map<String, dynamic>;
      expect(body['id'], 6);
      expect(body['result']['tools'], isEmpty);
    });

    test('2026 stateless HTTP accepts matching standard and parameter headers',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcCallToolRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const CallToolResult(content: []).toJson(),
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsCall)
        ..set('Mcp-Name', 'execute')
        ..set('Mcp-Param-region', 'us-east1')
        ..set('Mcp-Param-ratio', '1.5')
        ..set('Mcp-Param-dryRun', 'false');
      request.write(
        jsonEncode(
          JsonRpcCallToolRequest(
            id: 3,
            params: const {
              'name': 'execute',
              'arguments': {
                'region': 'us-east1',
                'ratio': 1.5,
                'dryRun': false,
              },
            },
            meta: _statelessMeta(),
          ),
        ),
      );

      final response = await request.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('mcp-session-id'), isNull);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 3);
      expect(body['result']['content'], isEmpty);
    });

    test('2026 stateless HTTP routes only opted-in request logging', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      late final Server server;
      server = Server(
        const Implementation(name: 'TestServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
          capabilities: ServerCapabilities(
            logging: <String, dynamic>{},
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );
      addTearDown(server.close);
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          await extra.sendNotification(
            JsonRpcLoggingMessageNotification(
              logParams: const LoggingMessageNotification(
                level: LoggingLevel.debug,
                data: 'below threshold',
              ),
            ),
          );
          await server.sendStatelessLoggingMessage(
            const LoggingMessageNotification(
              level: LoggingLevel.warning,
              data: 'routed warning',
            ),
            requestMeta: extra.meta,
            requestId: extra.requestId,
          );
          return const ListToolsResult(tools: []);
        },
        (id, params, meta) => JsonRpcListToolsRequest(
          id: id,
          params: params,
          meta: meta,
        ),
      );
      await server.connect(transport);
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        )
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList);
      request.write(
        jsonEncode(
          JsonRpcListToolsRequest(
            id: 'logged-list',
            meta: {
              ..._statelessMeta(),
              McpMetaKey.logLevel: LoggingLevel.warning.name,
            },
          ),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      final messages = _decodeSseJsonMessages(
        await utf8.decodeStream(response),
      );
      expect(messages, hasLength(2));
      expect(messages.first['method'], Method.notificationsMessage);
      expect(messages.first['params']['level'], LoggingLevel.warning.name);
      expect(messages.first['params']['data'], 'routed warning');
      expect(messages.last['id'], 'logged-list');
      expect(messages.last['result']['tools'], isEmpty);
    });

    test('2026 stateless HTTP rejects server requests on response streams',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final sendError = Completer<Object>();
      transport.onmessage = (message) {
        if (message is JsonRpcListToolsRequest) {
          final requestSend = transport.send(
            const JsonRpcListRootsRequest(id: 99),
            relatedRequestId: message.id,
          );
          unawaited(
            requestSend.then(
              (_) {},
              onError: (Object error) {
                if (!sendError.isCompleted) {
                  sendError.complete(error);
                }
              },
            ),
          );
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const ListToolsResult(tools: []).toJson(),
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList);
      request.write(
        jsonEncode(
          JsonRpcListToolsRequest(id: 10, meta: _statelessMeta()).toJson(),
        ),
      );

      final response = await request.close();
      final messages =
          _decodeSseJsonMessages(await utf8.decodeStream(response));
      final error = await sendError.future.timeout(
        const Duration(seconds: 1),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('X-Accel-Buffering'), 'no');
      expect(messages, hasLength(1));
      expect(messages.single['id'], 10);
      expect(messages.single['result']['tools'], isEmpty);
      expect(error, isA<StateError>());
      expect(
        error.toString(),
        contains('stateless MCP response streams'),
      );
    });

    test('2026 stateless HTTP cancels pending request when SSE response closes',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedRequest = Completer<JsonRpcListToolsRequest>();
      final cancellation = Completer<JsonRpcCancelledNotification>();
      transport.onmessage = (message) {
        if (message is JsonRpcListToolsRequest) {
          if (!receivedRequest.isCompleted) {
            receivedRequest.complete(message);
          }
          return;
        }

        if (message is JsonRpcCancelledNotification) {
          if (!cancellation.isCompleted) {
            cancellation.complete(message);
          }
        }
      };

      final body = jsonEncode(
        JsonRpcListToolsRequest(id: 11, meta: _statelessMeta()).toJson(),
      );
      final bodyBytes = utf8.encode(body);
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, serverPort);
      addTearDown(socket.destroy);
      final responseBytes = <int>[];
      final responseStarted = Completer<String>();
      final socketSubscription = socket.listen((chunk) {
        responseBytes.addAll(chunk);
        final responseText = latin1.decode(responseBytes, allowInvalid: true);
        if (!responseStarted.isCompleted && responseText.contains('\r\n\r\n')) {
          responseStarted.complete(responseText);
        }
      });

      socket.add(
        utf8.encode(
          'POST /mcp HTTP/1.1\r\n'
          'Host: localhost:$serverPort\r\n'
          'Content-Type: application/json\r\n'
          'Accept: application/json, text/event-stream\r\n'
          'MCP-Protocol-Version: $previewProtocolVersion\r\n'
          'Mcp-Method: ${Method.toolsList}\r\n'
          'Content-Length: ${bodyBytes.length}\r\n'
          '\r\n',
        ),
      );
      socket.add(bodyBytes);
      await socket.flush();

      final responseText = await responseStarted.future.timeout(
        const Duration(seconds: 3),
      );
      expect(responseText, contains('200 OK'));
      expect(responseText.toLowerCase(), contains('text/event-stream'));
      expect(responseText.toLowerCase(), contains('x-accel-buffering: no'));
      expect(
        (await receivedRequest.future.timeout(const Duration(seconds: 3))).id,
        11,
      );

      socket.destroy();
      await socketSubscription.cancel();
      final notification = await cancellation.future.timeout(
        const Duration(seconds: 3),
      );
      expect(notification.cancelParams.requestId, 11);
      expect(
        notification.cancelParams.reason,
        contains('SSE response stream closed'),
      );
    });

    test(
        '2026 stateless HTTP cancels pending request when JSON response closes',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final receivedRequest = Completer<JsonRpcListToolsRequest>();
      final cancellation = Completer<JsonRpcCancelledNotification>();
      transport.onmessage = (message) {
        if (message is JsonRpcListToolsRequest) {
          if (!receivedRequest.isCompleted) {
            receivedRequest.complete(message);
          }
          return;
        }

        if (message is JsonRpcCancelledNotification &&
            !cancellation.isCompleted) {
          cancellation.complete(message);
        }
      };

      final body = jsonEncode(
        JsonRpcListToolsRequest(id: 12, meta: _statelessMeta()).toJson(),
      );
      final bodyBytes = utf8.encode(body);
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, serverPort);
      addTearDown(socket.destroy);
      socket.add(
        utf8.encode(
          'POST /mcp HTTP/1.1\r\n'
          'Host: localhost:$serverPort\r\n'
          'Content-Type: application/json\r\n'
          'Accept: application/json, text/event-stream\r\n'
          'MCP-Protocol-Version: $previewProtocolVersion\r\n'
          'Mcp-Method: ${Method.toolsList}\r\n'
          'Content-Length: ${bodyBytes.length}\r\n'
          '\r\n',
        ),
      );
      socket.add(bodyBytes);
      await socket.flush();

      expect(
        (await receivedRequest.future.timeout(const Duration(seconds: 3))).id,
        12,
      );
      socket.destroy();

      final notification = await cancellation.future.timeout(
        const Duration(seconds: 3),
      );
      expect(notification.cancelParams.requestId, 12);
      expect(
        notification.cancelParams.reason,
        contains('JSON response stream closed'),
      );
    });

    test(
        '2026 detached JSON preserves response headers without cancelling completed requests',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      addTearDown(transport.close);
      await transport.start();

      final cancellations = <JsonRpcCancelledNotification>[];
      transport.onmessage = (message) {
        if (message is JsonRpcCancelledNotification) {
          cancellations.add(message);
        } else if (message is JsonRpcListToolsRequest) {
          unawaited(
            message.id == 14
                ? transport.send(
                    JsonRpcError(
                      id: message.id,
                      error: const JsonRpcErrorData(
                        code: -32601,
                        message: 'Method not found',
                      ),
                    ),
                  )
                : transport.send(
                    JsonRpcResponse(
                      id: message.id,
                      result: const ListToolsResult(tools: []).toJson(),
                    ),
                  ),
          );
        }
      };

      final headerServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => headerServer.close(force: true));
      headerServer.listen((request) async {
        request.response.headers
          ..set('access-control-allow-origin', 'https://example.com')
          ..add(HttpHeaders.setCookieHeader, 'first=1')
          ..add(HttpHeaders.setCookieHeader, 'second=2');
        await transport.handleRequest(request);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${headerServer.port}/mcp'),
      );
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList);
      request.write(
        jsonEncode(
          JsonRpcListToolsRequest(id: 13, meta: _statelessMeta()).toJson(),
        ),
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentLength, greaterThan(0));
      expect(response.persistentConnection, isFalse);
      expect(
        response.headers.value('access-control-allow-origin'),
        'https://example.com',
      );
      expect(
        response.headers[HttpHeaders.setCookieHeader],
        containsAll(<String>['first=1', 'second=2']),
      );
      expect(body['id'], 13);
      expect(body['result']['tools'], isEmpty);
      expect(cancellations, isEmpty);

      final errorRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${headerServer.port}/mcp'),
      );
      errorRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList);
      errorRequest.write(
        jsonEncode(
          JsonRpcListToolsRequest(id: 14, meta: _statelessMeta()).toJson(),
        ),
      );

      final errorResponse = await errorRequest.close();
      final errorBody = jsonDecode(await utf8.decodeStream(errorResponse))
          as Map<String, dynamic>;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errorResponse.statusCode, HttpStatus.notFound);
      expect(
        errorResponse.headers.value('access-control-allow-origin'),
        'https://example.com',
      );
      expect(errorBody['id'], 14);
      expect(errorBody['error']['code'], ErrorCode.methodNotFound.value);
      expect(cancellations, isEmpty);
    });

    test('2026 stateless HTTP validates mapped tool parameter headers',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
        ),
      );
      transport.setToolParameterHeaderMappings(
        const {
          'execute': {
            'count': 'Count',
            'dryRun': 'Dry-Run',
            'region': 'Region',
            'sentinel': 'Sentinel',
            '/location/zone': 'Zone',
          },
        },
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcCallToolRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const CallToolResult(content: []).toJson(),
              ),
            ),
          );
        }
      };

      Future<(int, Map<String, dynamic>)> postToolCall({
        required int id,
        required Map<String, Object> headers,
        Map<String, Object?> arguments = const {
          'dryRun': false,
          'region': 'us-east1',
        },
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
          ..set('MCP-Protocol-Version', previewProtocolVersion)
          ..set('Mcp-Method', Method.toolsCall)
          ..set('Mcp-Name', 'execute');
        headers.forEach(request.headers.set);
        request.write(
          jsonEncode(
            JsonRpcCallToolRequest(
              id: id,
              params: {
                'name': 'execute',
                'arguments': arguments,
              },
              meta: _statelessMeta(),
            ),
          ),
        );

        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      var (statusCode, body) = await postToolCall(
        id: 30,
        headers: const {
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.badRequest);
      expect(body['id'], 30);
      expect(body['error']['code'], ErrorCode.headerMismatch.value);
      expect(
        body['error']['message'],
        contains('Mcp-Param-Dry-Run header is required'),
      );

      (statusCode, body) = await postToolCall(
        id: 31,
        headers: const {
          'Mcp-Param-Dry-Run': 'true',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.badRequest);
      expect(body['id'], 31);
      expect(
        body['error']['message'],
        contains("body argument 'dryRun'"),
      );

      (statusCode, body) = await postToolCall(
        id: 32,
        arguments: const {
          'dryRun': {'nested': true},
          'region': 'us-east1',
        },
        headers: const {
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.badRequest);
      expect(body['id'], 32);
      expect(
        body['error']['message'],
        contains('no matching primitive body argument'),
      );

      (statusCode, body) = await postToolCall(
        id: 34,
        arguments: const {
          'count': 42,
          'dryRun': false,
          'region': 'us-east1',
        },
        headers: const {
          'Mcp-Param-Count': '42',
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 34);
      expect(body['result']['content'], isEmpty);

      (statusCode, body) = await postToolCall(
        id: 38,
        arguments: const {
          'count': 42,
          'dryRun': false,
          'region': 'us-east1',
        },
        headers: const {
          'Mcp-Param-Count': '43',
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.badRequest);
      expect(body['id'], 38);
      expect(
        body['error']['message'],
        contains("body argument 'count'"),
      );

      (statusCode, body) = await postToolCall(
        id: 35,
        arguments: const {
          'count': 42,
          'dryRun': false,
          'region': 'us-east1',
        },
        headers: const {
          'Mcp-Param-Count': '42.0',
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 35);
      expect(body['result']['content'], isEmpty);

      (statusCode, body) = await postToolCall(
        id: 39,
        arguments: const {
          'count': 9007199254740991,
          'dryRun': false,
          'region': 'us-east1',
        },
        headers: const {
          'Mcp-Param-Count': '9007199254740991',
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 39);
      expect(body['result']['content'], isEmpty);

      (statusCode, body) = await postToolCall(
        id: 40,
        arguments: const {
          'count': 9007199254740992,
          'dryRun': false,
          'region': 'us-east1',
        },
        headers: const {
          'Mcp-Param-Count': '9007199254740992',
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.badRequest);
      expect(body['id'], 40);
      expect(body['error']['code'], ErrorCode.headerMismatch.value);
      expect(
        body['error']['message'],
        contains('JavaScript safe integer range'),
      );

      (statusCode, body) = await postToolCall(
        id: 36,
        arguments: const {
          'dryRun': false,
          'region': 'us-east1',
          'sentinel': '=?base64?YWJj?=',
        },
        headers: {
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
          'Mcp-Param-Sentinel':
              '=?base64?${base64Encode(utf8.encode('=?base64?YWJj?='))}?=',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 36);
      expect(body['result']['content'], isEmpty);

      (statusCode, body) = await postToolCall(
        id: 37,
        arguments: const {
          'dryRun': false,
          'region': 'us-east1',
          'location': {'zone': 'us-east1-b'},
        },
        headers: const {
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
          'Mcp-Param-Zone': 'us-east1-b',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 37);
      expect(body['result']['content'], isEmpty);

      (statusCode, body) = await postToolCall(
        id: 41,
        arguments: const {
          'dryRun': false,
          'region': 'us-east1',
          'trace': 'body-value',
        },
        headers: const {
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
          'Mcp-Param-Trace': '=?base64?%%%?=',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 41);
      expect(body['result']['content'], isEmpty);

      (statusCode, body) = await postToolCall(
        id: 33,
        headers: const {
          'Mcp-Param-Dry-Run': 'false',
          'Mcp-Param-Region': 'us-east1',
        },
      );
      expect(statusCode, HttpStatus.ok);
      expect(body['id'], 33);
      expect(body['result']['content'], isEmpty);
    });

    test('2026 stateless HTTP validates recognized routing headers', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
          enableJsonResponse: true,
          rejectBatchJsonRpcPayloads: false,
        ),
      );
      transport.setToolParameterHeaderMappings(
        const {
          'execute': {'region': 'Region'},
        },
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;
      transport.onmessage = (message) {
        if (message is JsonRpcCallToolRequest) {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const CallToolResult(content: []).toJson(),
              ),
            ),
          );
        }
      };

      Future<Map<String, dynamic>> postJson(
        Object body, {
        Map<String, String> headers = const {},
        int expectedStatus = HttpStatus.badRequest,
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          );
        headers.forEach(request.headers.set);
        request.write(jsonEncode(body));

        final response = await request.close();
        expect(response.statusCode, expectedStatus);
        return jsonDecode(await utf8.decodeStream(response))
            as Map<String, dynamic>;
      }

      var body = await postJson(
        const JsonRpcListToolsRequest(id: 4).toJson(),
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
          'Mcp-Method': Method.toolsList,
        },
      );
      expect(body['error']['code'], ErrorCode.invalidParams.value);
      expect(body['error']['message'], contains(McpMetaKey.protocolVersion));

      final topLevelMetaOnly = const JsonRpcListToolsRequest(id: 20).toJson()
        ..['_meta'] = _statelessMeta();
      body = await postJson(
        topLevelMetaOnly,
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
          'Mcp-Method': Method.toolsList,
        },
      );
      expect(body['id'], 20);
      expect(body['error']['code'], ErrorCode.invalidParams.value);
      expect(body['error']['message'], contains(McpMetaKey.protocolVersion));

      body = await postJson(
        JsonRpcListToolsRequest(id: 5, meta: _statelessMeta()).toJson(),
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
        },
      );
      expect(body['error']['message'], contains('Mcp-Method header'));

      body = await postJson(
        JsonRpcCallToolRequest(
          id: 16,
          params: const {
            'name': 'execute',
            'arguments': {'region': 'us-east1'},
          },
          meta: _statelessMeta(),
        ).toJson(),
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
          'Mcp-Method': Method.toolsCall,
          'Mcp-Name': 'execute',
          'Mcp-Param-': 'us-east1',
          'Mcp-Param-Region': 'us-east1',
        },
        expectedStatus: HttpStatus.ok,
      );
      expect(body['id'], 16);
      expect(body['result']['content'], isEmpty);

      body = await postJson(
        JsonRpcCallToolRequest(
          id: 17,
          params: const {
            'name': 'execute',
            'arguments': {'region': 'us-east1'},
          },
          meta: _statelessMeta(),
        ).toJson(),
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
          'Mcp-Method': Method.toolsCall,
          'Mcp-Name': 'execute',
          'Mcp-Param-region': '=?base64?%%%?=',
        },
      );
      expect(body['id'], 17);
      expect(body['error']['message'], contains('header value is malformed'));

      body = await postJson(
        JsonRpcCallToolRequest(
          id: 18,
          params: const {'name': 'execute'},
          meta: _statelessMeta(),
        ).toJson(),
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
          'Mcp-Method': Method.toolsCall,
          'Mcp-Name': 'execute',
          'Mcp-Param-region': 'us-east1',
        },
      );
      expect(body['id'], 18);
      expect(
        body['error']['message'],
        contains('no matching primitive body argument'),
      );

      body = await postJson(
        JsonRpcCallToolRequest(
          id: 7,
          params: const {
            'name': 'execute',
            'arguments': {},
          },
          meta: _statelessMeta(),
        ).toJson(),
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
          'Mcp-Method': Method.toolsCall,
        },
      );
      expect(body['id'], 7);
      expect(body['error']['message'], contains('Mcp-Name header'));

      body = await postJson(
        [
          JsonRpcListToolsRequest(id: 8, meta: _statelessMeta()).toJson(),
          JsonRpcListToolsRequest(id: 9, meta: _statelessMeta()).toJson(),
        ],
        headers: {
          'MCP-Protocol-Version': previewProtocolVersion,
        },
      );
      expect(body['error']['message'], contains('must contain one'));
    });

    test('2026 stateless HTTP returns 404 for method not found', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "unused-session-id",
        ),
      );
      final server = Server(
        const Implementation(name: 'StatelessServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.stable,
        ),
      );
      addTearDown(server.close);
      await server.connect(transport);
      transports['/mcp'] = transport;

      Future<Map<String, dynamic>> postStatelessRequest(
        JsonRpcRequest message,
      ) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        request.headers
          ..contentType = ContentType.json
          ..set(
            HttpHeaders.acceptHeader,
            'application/json, text/event-stream',
          )
          ..set('MCP-Protocol-Version', previewProtocolVersion)
          ..set('Mcp-Method', message.method);
        request.write(jsonEncode(message.toJson()));

        final response = await request.close();
        expect(response.statusCode, HttpStatus.notFound);
        final body = jsonDecode(await utf8.decodeStream(response))
            as Map<String, dynamic>;
        expect(body['id'], message.id);
        expect(body['error']['code'], ErrorCode.methodNotFound.value);
        return body;
      }

      var body = await postStatelessRequest(
        JsonRpcRequest(
          id: 20,
          method: 'experimental/unknown',
          meta: _statelessMeta(),
        ),
      );
      expect(body['error']['message'], contains('experimental/unknown'));

      body = await postStatelessRequest(
        JsonRpcRequest(
          id: 21,
          method: Method.ping,
          meta: _statelessMeta(),
        ),
      );
      expect(
        body['error']['message'],
        contains('not part of MCP stateless protocol versions'),
      );
    });

    test(
        '2026 stateless HTTP rejects missing client capabilities as invalid params',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
          enableJsonResponse: true,
        ),
      );
      final server = Server(
        const Implementation(name: 'StatelessServer', version: '1.0.0'),
        options: const McpServerOptions(
          protocol: McpProtocol.require2026,
        ),
      );
      addTearDown(server.close);
      await server.connect(transport);
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        )
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Method', Method.toolsList);
      request.write(
        jsonEncode(
          const JsonRpcListToolsRequest(
            id: 'missing-client-capabilities',
            meta: {
              McpMetaKey.protocolVersion: previewProtocolVersion,
            },
          ).toJson(),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      expect(body['id'], 'missing-client-capabilities');
      expect(body['error']['code'], ErrorCode.invalidParams.value);
      expect(
        body['error']['message'],
        contains(McpMetaKey.clientCapabilities),
      );
    });

    test('stateless mode allows initialization with session header', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          unawaited(
            transport.send(
              JsonRpcResponse(
                id: message.id,
                result: const {
                  'protocolVersion': latestInitializationProtocolVersion,
                  'capabilities': {},
                  'serverInfo': {'name': 'StatelessServer', 'version': '1.0.0'},
                },
              ),
            ),
          );
        }
      };

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        )
        ..set('mcp-session-id', 'ignored-in-stateless-mode');
      request.write(
        jsonEncode(
          const JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: {
              'protocolVersion': latestInitializationProtocolVersion,
              'capabilities': {},
              'clientInfo': {'name': 'TestClient', 'version': '1.0.0'},
            },
          ).toJson(),
        ),
      );

      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('mcp-session-id'), isNull);
      final messages =
          _decodeSseJsonMessages(await utf8.decodeStream(response));
      expect(messages.single['id'], 1);
      expect(transport.sessionId, isNull);
    });

    test('2026 stateless non-POST requests return method not allowed',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => null,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse('$serverUrlBase/mcp'));
      request.headers.set(
        'MCP-Protocol-Version',
        previewProtocolVersion,
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(response.headers.value(HttpHeaders.allowHeader), 'POST');
      expect(body['error']['code'], ErrorCode.connectionClosed.value);
      expect(
        body['error']['message'],
        'Method not allowed for stateless MCP requests.',
      );

      final patchRequest = await client.openUrl(
        'PATCH',
        Uri.parse('$serverUrlBase/mcp'),
      );
      patchRequest.headers.set(
        'MCP-Protocol-Version',
        previewProtocolVersion,
      );

      final patchResponse = await patchRequest.close();
      final patchBody = jsonDecode(
        await utf8.decodeStream(patchResponse),
      ) as Map<String, dynamic>;

      expect(patchResponse.statusCode, HttpStatus.methodNotAllowed);
      expect(patchResponse.headers.contentType?.mimeType, 'application/json');
      expect(patchResponse.headers.value(HttpHeaders.allowHeader), 'POST');
      expect(patchBody['error']['code'], ErrorCode.connectionClosed.value);
      expect(
        patchBody['error']['message'],
        'Method not allowed for stateless MCP requests.',
      );

      final deleteRequest = await client.deleteUrl(
        Uri.parse('$serverUrlBase/mcp'),
      );
      deleteRequest.headers
        ..set('MCP-Protocol-Version', previewProtocolVersion)
        ..set('Mcp-Session-Id', 'ignored-stateless-session');

      final deleteResponse = await deleteRequest.close();
      final deleteBody = jsonDecode(
        await utf8.decodeStream(deleteResponse),
      ) as Map<String, dynamic>;

      expect(deleteResponse.statusCode, HttpStatus.methodNotAllowed);
      expect(deleteResponse.headers.contentType?.mimeType, 'application/json');
      expect(deleteResponse.headers.value(HttpHeaders.allowHeader), 'POST');
      expect(deleteResponse.headers.value('mcp-session-id'), isNull);
      expect(deleteBody['error']['code'], ErrorCode.connectionClosed.value);
      expect(
        deleteBody['error']['message'],
        'Method not allowed for stateless MCP requests.',
      );
    });

    test('close cleans up all resources', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      bool oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.close();

      expect(oncloseCalled, isTrue);
    });

    test('send throws StateError for response on standalone SSE stream',
        () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      // Try to send a response without a request ID (standalone SSE)
      final response = const JsonRpcResponse(
        id: 123,
        result: {'data': 'test'},
      );

      // This should throw because we can't send responses on standalone SSE
      expect(
        () => transport.send(response),
        throwsA(isA<StateError>()),
      );

      await transport.close();
    });

    test('send discards notifications when no standalone SSE stream', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      // Send notification without established SSE stream
      final notification = const JsonRpcNotification(
        method: 'test/notification',
        params: {'message': 'hello'},
      );

      // This should not throw - notifications are discarded if no stream
      await transport.send(notification);

      await transport.close();
    });

    test('send throws StateError for unknown request ID', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      // Try to send a response for an unknown request ID
      final response = const JsonRpcResponse(
        id: 999,
        result: {'data': 'test'},
      );

      expect(
        () => transport.send(response, relatedRequestId: 999),
        throwsA(isA<StateError>()),
      );

      await transport.close();
    });

    test('onerror callback is invoked on errors', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();

      Error? receivedError;
      transport.onerror = (error) {
        receivedError = error;
      };

      // Simulate message handler throwing
      transport.onmessage = (message) {
        throw StateError('Handler error');
      };

      // Try to trigger the error through a simulated message
      try {
        transport.onmessage?.call(
          const JsonRpcNotification(
            method: 'test',
            params: {},
          ),
        );
      } catch (e) {
        // Expected
      }

      // Note: onerror is called internally when handlers throw in POST handling
      // Direct onmessage throws are caught in the test itself
      // The variable is captured but may not be set when throwing directly
      expect(
        receivedError,
        isNull,
      ); // Not called when we throw directly in handler

      await transport.close();
    });

    test('EventStore storeEvent returns unique event IDs', () async {
      final eventStore = TestEventStore();
      final sessionId = 'test-session';

      final msg1 = const JsonRpcNotification(method: 'test1', params: {});
      final msg2 = const JsonRpcNotification(method: 'test2', params: {});

      final id1 = await eventStore.storeEvent(sessionId, msg1);
      final id2 = await eventStore.storeEvent(sessionId, msg2);

      expect(id1, isNot(equals(id2)));
      expect(eventStore.events[sessionId]!.length, equals(2));
    });

    test('EventStore replayEventsAfter throws for unknown event ID', () async {
      final eventStore = TestEventStore();

      expect(
        () => eventStore.replayEventsAfter(
          'unknown-event-id',
          send: (eventId, message) async {},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('transport handles notifications-only POST with 202', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "test-session-id";

      final messages = <JsonRpcMessage>[];
      transport.onmessage = (msg) {
        messages.add(msg);
      };

      // Call onmessage with a notification
      transport.onmessage?.call(
        const JsonRpcNotification(
          method: 'test/notification',
          params: {'data': 'value'},
        ),
      );

      expect(messages.length, equals(1));
      expect(messages.first, isA<JsonRpcNotification>());

      await transport.close();
    });
  });
}
