import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/server/sse.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer testServer;
  late int serverPort;
  late String serverUrlBase;
  // Use a Map to handle multiple clients/transports during tests if needed
  final Map<String, SseServerTransport> activeTransports = {};
  // Keep track of the MCP Server instance (if needed for integration)
  // late Server mcpServer; // Assuming Server class exists

  // --- Test Server Setup ---
  Future<void> testServerHandler(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;
    // print("Test Server received: $method $path"); // Debugging

    if (method == 'GET' && path == '/sse_test') {
      try {
        final transport = SseServerTransport(
          response: request.response,
          messageEndpointPath: '/messages_test',
        );
        final sessionId = transport.sessionId;
        activeTransports[sessionId] = transport;
        // print("Test Server: SSE Transport created for session $sessionId");

        transport.onclose = () {
          // print("Test Server: SSE Transport closed for session $sessionId");
          activeTransports.remove(sessionId);
        };
        transport.onerror = (e) => print(
              "Test Server: Transport error for session $sessionId: $e",
            );

        // Start the transport AFTER setting handlers
        await transport.start();
      } catch (e) {
        print("Test Server: Error creating/starting SSE transport: $e");
        if (!request.response.headers.persistentConnection) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      }
    } else if (method == 'POST' && path == '/messages_test') {
      final sessionId = request.uri.queryParameters['sessionId'];
      if (sessionId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write("Missing sessionId");
        await request.response.close();
        return;
      }
      final transport = activeTransports[sessionId];
      if (transport != null) {
        // print("Test Server: Routing POST to transport for session $sessionId");
        await transport.handlePostMessage(request);
      } else {
        // print("Test Server: No transport found for POST session $sessionId");
        request.response.statusCode = HttpStatus.notFound;
        request.response.write("Session not found");
        await request.response.close();
      }
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  // Start the server once before all tests
  setUpAll(() async {
    try {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;
      serverUrlBase = 'http://localhost:$serverPort';
      print("Test server listening on $serverUrlBase");
      testServer.listen(testServerHandler); // No await here
    } catch (e) {
      print("FATAL: Failed to start test server: $e");
      exit(1);
    }
  });

  // Stop the server once after all tests
  tearDownAll(() async {
    print("Stopping test server...");
    // Close any remaining transports
    await Future.wait(activeTransports.values.map((t) => t.close()));
    activeTransports.clear();
    await testServer.close(force: true);
    print("Test server stopped.");
  });

  // --- Test Cases ---

  test(
    'SseServerTransport - start() sends headers and endpoint event',
    () async {
      final sseUrl = '$serverUrlBase/sse_test';
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(sseUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final response = await request.close();

      expect(
        response.statusCode,
        equals(HttpStatus.ok),
      ); // Initial response is OK

      final completer = Completer<List<String>>();
      final outputLines = <String>[];
      late StreamSubscription sub;

      sub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          outputLines.add(line);
          // Check for the endpoint event data
          if (line.startsWith('data: /messages_test?sessionId=')) {
            if (!completer.isCompleted) completer.complete(outputLines);
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(outputLines);
          client.close();
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
          client.close();
        },
      );

      // Wait for the endpoint event or timeout
      final List<String> receivedLines = await completer.future;

      // Verify content
      expect(receivedLines, contains(startsWith('event: endpoint')));
      expect(
        receivedLines,
        contains(startsWith('data: /messages_test?sessionId=')),
      );

      // Verify server state (simplistic check for one transport)
      expect(activeTransports.length, equals(1));
      expect(activeTransports.values.first, isA<SseServerTransport>());

      await sub.cancel();
      client.close();
    },
  );

  test('SseServerTransport - send() formats message correctly', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final client = HttpClient();
    final completer =
        Completer<String>(); // Completes with received data containing message
    late StreamSubscription responseSub;
    late SseServerTransport serverTransport;
    String receivedData = '';

    // 1. Establish SSE connection
    final request = await client.getUrl(Uri.parse(sseUrl));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close();

    responseSub = response.transform(utf8.decoder).listen(
          (dataChunk) {
            receivedData += dataChunk;
            // Check if we received the specific message event
            if (receivedData.contains(
              'event: message\ndata: {"jsonrpc":"2.0","id":1,"method":"ping"}\n\n',
            )) {
              if (!completer.isCompleted) completer.complete(receivedData);
            }
          },
          onDone: () => print("SSE Client (Send Test) closed by server."),
          onError: (e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
        );

    // Wait for server to create the transport
    await Future.delayed(
      const Duration(milliseconds: 100),
    ); // Allow server handler time
    expect(activeTransports.length, 1, reason: "Transport should be active");
    serverTransport = activeTransports.values.first;

    // 2. Send message from server
    final pingMsg = const JsonRpcPingRequest(id: 1);
    await serverTransport.send(pingMsg);

    // 3. Wait for client to receive or timeout
    await expectLater(completer.future, completes);

    // Optional: Verify exact received data if needed
    // expect(await completer.future, contains('event: message\ndata: {"jsonrpc":"2.0","id":1,"method":"ping"}\n\n'));

    await responseSub.cancel();
    client.close();
  });

  test('SseServerTransport - handlePostMessage() success', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final postUrlBase = '$serverUrlBase/messages_test';
    final client = HttpClient();
    final messageCompleter =
        Completer<JsonRpcMessage>(); // Captures msg on server
    late SseServerTransport serverTransport;

    // 1. Establish SSE connection (and keep it alive)
    final sseRequest = await client.getUrl(Uri.parse(sseUrl));
    sseRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final sseResponse = await sseRequest.close();
    final sseSub = sseResponse.listen(
      (_) {},
      onDone: () => print("SSE Client (POST Test) closed."),
    ); // Keep alive

    // Wait for server to create transport
    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);
    serverTransport = activeTransports.values.first;

    // 2. Set up server's onmessage listener
    serverTransport.onmessage = (msg) {
      if (!messageCompleter.isCompleted) messageCompleter.complete(msg);
    };

    // 3. Send POST request
    final postMsgJson = const JsonRpcPingRequest(id: 99).toJson();
    final postBody = utf8.encode(jsonEncode(postMsgJson));
    final postUrl = '$postUrlBase?sessionId=${serverTransport.sessionId}';

    late HttpClientResponse postResponse;
    try {
      final postRequest = await client.postUrl(Uri.parse(postUrl));
      postRequest.headers.contentType = ContentType.json;
      postRequest.headers.contentLength = postBody.length;
      postRequest.add(postBody);
      postResponse = await postRequest.close();

      // Verify POST response status
      expect(postResponse.statusCode, HttpStatus.accepted);
      await postResponse.drain(); // Consume response body

      // 4. Wait for server's onmessage
      final receivedMsg = await messageCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      // Verify received message structure/content
      expect(receivedMsg, isA<JsonRpcPingRequest>());
      expect(receivedMsg.toJson()['id'], 99);
    } finally {
      await sseSub.cancel();
      client.close(); // Close client after test
    }
  });

  test('SseServerTransport - handlePostMessage() wrong session ID', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final postUrlBase = '$serverUrlBase/messages_test';
    final client = HttpClient();
    late SseServerTransport serverTransport;

    // 1. Establish SSE connection
    final sseRequest = await client.getUrl(Uri.parse(sseUrl));
    sseRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final sseResponse = await sseRequest.close();
    final sseSub = sseResponse.listen((_) {}); // Keep alive

    // Wait for server to create transport
    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);
    serverTransport = activeTransports.values.first;

    // 2. Set up server's onmessage listener (should not be called)
    serverTransport.onmessage = (msg) {
      fail("onmessage should not be called for wrong session ID");
    };

    // 3. Send POST request with WRONG session ID
    final postMsgJson = const JsonRpcPingRequest(id: 101).toJson();
    final postBody = utf8.encode(jsonEncode(postMsgJson));
    final postUrl = '$postUrlBase?sessionId=INVALID_SESSION_ID'; // Wrong ID

    late HttpClientResponse postResponse;
    try {
      final postRequest = await client.postUrl(Uri.parse(postUrl));
      postRequest.headers.contentType = ContentType.json;
      postRequest.headers.contentLength = postBody.length;
      postRequest.add(postBody);
      postResponse = await postRequest.close();

      // Verify POST response status (should be error)
      expect(postResponse.statusCode, HttpStatus.notFound); // Check for 404
      await postResponse.drain();
    } finally {
      await sseSub.cancel();
      client.close();
    }
  });

  test('SseServerTransport - handlePostMessage() invalid JSON', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final postUrlBase = '$serverUrlBase/messages_test';
    final client = HttpClient();
    final errorCompleter = Completer<Error>(); // Capture server error
    late SseServerTransport serverTransport;

    // 1. Establish SSE connection
    final sseRequest = await client.getUrl(Uri.parse(sseUrl));
    sseRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final sseResponse = await sseRequest.close();
    final sseSub = sseResponse.listen((_) {}); // Keep alive

    // Wait for server to create transport
    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);
    serverTransport = activeTransports.values.first;

    // 2. Set up server's onerror listener
    serverTransport.onerror = (err) {
      if (!errorCompleter.isCompleted) errorCompleter.complete(err);
    };
    serverTransport.onmessage =
        (msg) => fail("onmessage called with invalid JSON");

    // 3. Send POST request with invalid JSON
    final postBody = utf8.encode("this is not valid json");
    final postUrl = '$postUrlBase?sessionId=${serverTransport.sessionId}';

    late HttpClientResponse postResponse;
    try {
      final postRequest = await client.postUrl(Uri.parse(postUrl));
      postRequest.headers.contentType = ContentType.json; // Claim JSON
      postRequest.headers.contentLength = postBody.length;
      postRequest.add(postBody);
      postResponse = await postRequest.close();

      // Verify POST response status (should be error)
      expect(
        postResponse.statusCode,
        HttpStatus.internalServerError,
      ); // Or 400, depending on error handling
      await postResponse.drain();

      // 4. Verify server's onerror was called
      final serverError = await errorCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(
        serverError,
        isA<Error>(),
      ); // Or check for specific FormatException etc.
    } finally {
      await sseSub.cancel();
      client.close();
    }
  });

  test('SseServerTransport - sessionId is a valid UUID', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final client = HttpClient();

    final request = await client.getUrl(Uri.parse(sseUrl));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close();
    final sseSub = response.listen((_) {});

    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);

    final transport = activeTransports.values.first;
    final sessionId = transport.sessionId;

    // Verify sessionId format (UUID-like)
    expect(sessionId, isNotEmpty);
    expect(sessionId.length, greaterThanOrEqualTo(32));

    await sseSub.cancel();
    client.close();
  });

  test('SseServerTransport - close() cleans up resources', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final client = HttpClient();
    final closeCompleter = Completer<void>();

    final request = await client.getUrl(Uri.parse(sseUrl));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close();

    late StreamSubscription sseSub;
    sseSub = response.listen(
      (_) {},
      onDone: () {
        if (!closeCompleter.isCompleted) closeCompleter.complete();
      },
    );

    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);

    final transport = activeTransports.values.first;

    // Close the transport
    await transport.close();

    // Wait for client to receive close
    await closeCompleter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        // Transport closed, client may or may not receive done
      },
    );

    await sseSub.cancel();
    client.close();
  });

  test('SseServerTransport - onclose callback is invoked', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final client = HttpClient();
    final oncloseCompleter = Completer<void>();

    final request = await client.getUrl(Uri.parse(sseUrl));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close();
    final sseSub = response.listen((_) {});

    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);

    final transport = activeTransports.values.first;
    final originalOnclose = transport.onclose;

    transport.onclose = () {
      if (!oncloseCompleter.isCompleted) oncloseCompleter.complete();
      originalOnclose?.call();
    };

    await transport.close();

    await oncloseCompleter.future.timeout(
      const Duration(seconds: 2),
    );

    await sseSub.cancel();
    client.close();
  });

  test('SseServerTransport - multiple close calls are safe', () async {
    final sseUrl = '$serverUrlBase/sse_test';
    final client = HttpClient();

    final request = await client.getUrl(Uri.parse(sseUrl));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close();
    final sseSub = response.listen((_) {});

    await Future.delayed(const Duration(milliseconds: 100));
    expect(activeTransports.length, 1);

    final transport = activeTransports.values.first;

    // Multiple close calls should not throw
    await transport.close();
    await transport.close();
    await transport.close();

    await sseSub.cancel();
    client.close();
  });
} // End of main test group
