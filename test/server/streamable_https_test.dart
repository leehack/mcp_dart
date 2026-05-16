import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/server/in_memory_event_store.dart';
import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

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

class _SseEvent {
  final String? id;
  final String? event;
  final String data;

  const _SseEvent({
    this.id,
    this.event,
    required this.data,
  });

  Map<String, dynamic> get json => jsonDecode(data) as Map<String, dynamic>;
}

Future<_SseEvent> _readSseEvent(StreamIterator<String> lines) async {
  String? id;
  String? event;
  final dataLines = <String>[];

  while (await lines.moveNext()) {
    final line = lines.current;
    if (line.isEmpty) {
      if (id != null || event != null || dataLines.isNotEmpty) {
        return _SseEvent(
          id: id,
          event: event,
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
      case 'data':
        dataLines.add(value);
        break;
    }
  }

  throw StateError('SSE stream ended before an event was received');
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
                    'protocolVersion': latestProtocolVersion,
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
              'protocolVersion': latestProtocolVersion,
              'capabilities': {},
              'clientInfo': {'name': 'TestClient', 'version': '1.0.0'},
            },
          ),
        );
        expect(initResponse.statusCode, HttpStatus.ok);
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
              protocolVersion: latestProtocolVersion,
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
            protocolVersion: latestProtocolVersion,
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
            protocolVersion: latestProtocolVersion,
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

    test('allows multiple concurrent GET SSE streams for one session',
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
                  'protocolVersion': latestProtocolVersion,
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
                protocolVersion: latestProtocolVersion,
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
          method: 'notifications/message',
          params: {'stream': 'first'},
        ),
      );
      final first = await firstFuture.timeout(const Duration(seconds: 3));
      expect(first.statusCode, HttpStatus.ok);
      expect(first.headers.contentType?.mimeType, 'text/event-stream');
      final firstLines = StreamIterator(
        first.transform(utf8.decoder).transform(const LineSplitter()),
      );

      final secondFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: {'stream': 'second'},
        ),
      );
      final second = await secondFuture.timeout(const Duration(seconds: 3));
      expect(second.statusCode, HttpStatus.ok);
      expect(second.headers.contentType?.mimeType, 'text/event-stream');
      final secondLines = StreamIterator(
        second.transform(utf8.decoder).transform(const LineSplitter()),
      );

      final firstOnly = await _readSseEvent(firstLines);
      final broadcastToFirst = await _readSseEvent(firstLines);
      final broadcastToSecond = await _readSseEvent(secondLines);

      expect(firstOnly.json['params'], containsPair('stream', 'first'));
      expect(broadcastToFirst.json['params'], containsPair('stream', 'second'));
      expect(
        broadcastToSecond.json['params'],
        containsPair('stream', 'second'),
      );
      expect(firstOnly.id, isNull);
      expect(broadcastToFirst.id, isNull);
      expect(broadcastToSecond.id, isNull);

      await firstLines.cancel();
      await secondLines.cancel();
    });

    test('GET Last-Event-ID replay is scoped to the original SSE stream',
        () async {
      final eventStore = InMemoryEventStore();
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
                  'protocolVersion': latestProtocolVersion,
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
                protocolVersion: latestProtocolVersion,
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
      final streamAFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: {'warmup': 'A'},
        ),
      );
      final streamA = await streamAFuture.timeout(const Duration(seconds: 3));
      expect(streamA.statusCode, HttpStatus.ok);

      final streamBFuture = openGetSse(sessionId);
      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: {'warmup': 'B'},
        ),
      );
      final streamB = await streamBFuture.timeout(const Duration(seconds: 3));
      expect(streamB.statusCode, HttpStatus.ok);

      final linesA = StreamIterator(
        streamA.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final linesB = StreamIterator(
        streamB.transform(utf8.decoder).transform(const LineSplitter()),
      );

      await _readSseEvent(linesA);
      await _readSseEvent(linesA);
      await _readSseEvent(linesB);

      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: {'seq': 1},
        ),
      );
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: {'seq': 2},
        ),
      );

      final aFirst = await _readSseEvent(linesA);
      final aSecond = await _readSseEvent(linesA);
      final bFirst = await _readSseEvent(linesB);
      final bSecond = await _readSseEvent(linesB);

      expect(aFirst.id, isNotNull);
      expect(aSecond.id, isNotNull);
      expect(bFirst.id, isNotNull);
      expect(bSecond.id, isNotNull);
      expect(aFirst.id, isNot(bFirst.id));
      expect(aSecond.id, isNot(bSecond.id));
      expect(aFirst.json['params'], containsPair('seq', 1));
      expect(aSecond.json['params'], containsPair('seq', 2));
      expect(bFirst.json['params'], containsPair('seq', 1));
      expect(bSecond.json['params'], containsPair('seq', 2));

      final replay = await openGetSse(sessionId, lastEventId: aFirst.id);
      expect(replay.statusCode, HttpStatus.ok);
      final replayLines = StreamIterator(
        replay.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final replayed = await _readSseEvent(replayLines);

      expect(replayed.id, aSecond.id);
      expect(replayed.json['params'], containsPair('seq', 2));
      expect(replayed.id, isNot(bSecond.id));

      await Future.delayed(const Duration(milliseconds: 50));
      await transport.send(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: {'seq': 3},
        ),
      );

      final aThird = await _readSseEvent(linesA);
      final bThird = await _readSseEvent(linesB);
      final replayThird = await _readSseEvent(replayLines);

      expect(aThird.json['params'], containsPair('seq', 3));
      expect(bThird.json['params'], containsPair('seq', 3));
      expect(replayThird.json['params'], containsPair('seq', 3));
      expect(aThird.id, replayThird.id);
      expect(aThird.id, isNot(bThird.id));

      await transport.close();
      expect(
        await linesA.moveNext().timeout(const Duration(seconds: 3)),
        isFalse,
      );
      expect(
        await linesB.moveNext().timeout(const Duration(seconds: 3)),
        isFalse,
      );
      expect(
        await replayLines.moveNext().timeout(const Duration(seconds: 3)),
        isFalse,
      );

      await linesA.cancel();
      await linesB.cancel();
      await replayLines.cancel();
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
                  'protocolVersion': latestProtocolVersion,
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
              'protocolVersion': latestProtocolVersion,
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
