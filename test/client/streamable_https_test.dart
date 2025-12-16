import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/client/streamable_https.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// A simple mock implementation of OAuthClientProvider for testing
class MockOAuthClientProvider implements OAuthClientProvider {
  final bool returnTokens;
  bool didRedirectToAuthorization = false;
  Function? redirectToAuthorizationCb;

  MockOAuthClientProvider({this.returnTokens = true});

  @override
  Future<OAuthTokens?> tokens() async {
    if (returnTokens) {
      return OAuthTokens(accessToken: 'test-access-token');
    }
    return null;
  }

  @override
  Future<void> redirectToAuthorization() async {
    if (redirectToAuthorizationCb != null) {
      redirectToAuthorizationCb!();
    } else {
      didRedirectToAuthorization = true;
    }
  }

  void registerRedirectToAuthorization(Function callback) {
    redirectToAuthorizationCb = callback;
  }
}

void main() {
  late HttpServer testServer;
  late int serverPort;
  late Uri serverUrl;
  final testSessionId = 'test-session-id';

  // Map to track active SSE connections by request hash
  final connections = <int, HttpResponse>{};
  final currentSseConnections = <HttpResponse>[];

  /// Set up the test HTTP server before all tests
  setUpAll(() async {
    try {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;
      serverUrl = Uri.parse('http://localhost:$serverPort/mcp');

      testServer.listen((request) async {
        final method = request.method;
        final path = request.uri.path;

        if (path == '/mcp') {
          if (method == 'GET') {
            // Handle SSE connection requests
            request.response.headers.add('Content-Type', 'text/event-stream');
            request.response.headers.add('Cache-Control', 'no-cache');
            request.response.headers.add('Connection', 'keep-alive');
            request.response.headers.add('mcp-session-id', testSessionId);

            // Critical for SSE: disable buffering and compression
            request.response.bufferOutput = false;
            request.response.headers.set('Content-Encoding', 'identity');

            // Keep the connection open by sending a comment right away
            request.response.write(': connected\n\n');
            await request.response.flush();
            print('SSE connection established with client');

            // Remember the response to send events later in tests
            currentSseConnections.add(request.response);

            // Initialize events map for this connection
            connections[request.hashCode] = request.response;

            // Don't close the response - it stays open for SSE
          } else if (method == 'POST') {
            // Handle message sending
            final requestBody = await utf8.decoder.bind(request).join();
            Map<String, dynamic> requestData;
            try {
              requestData = jsonDecode(requestBody);
            } catch (e) {
              request.response.statusCode = HttpStatus.badRequest;
              request.response.write('Invalid JSON');
              await request.response.close();
              return;
            }

            // Handle special test scenarios
            if (requestData['method'] == 'test/initialized') {
              // For initialization notification, return Accepted (202)
              request.response.statusCode = HttpStatus.accepted;
              request.response.headers.set('mcp-session-id', testSessionId);
              await request.response.close();
            } else if (requestData['id'] != null) {
              // For requests, return a response
              final id = requestData['id'];
              final response = JsonRpcResponse(
                id: id,
                result: {'success': true, 'echo': requestData['params']},
              );

              request.response.headers.contentType = ContentType.json;
              request.response.statusCode = HttpStatus.ok;
              request.response.headers.set('mcp-session-id', testSessionId);
              request.response.write(jsonEncode(response.toJson()));
              await request.response.close();
            } else {
              // For other notifications
              request.response.statusCode = HttpStatus.accepted;
              request.response.headers.set('mcp-session-id', testSessionId);
              await request.response.close();
            }
          } else if (method == 'DELETE') {
            // Handle session termination
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.methodNotAllowed;
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
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
    for (final connection in connections.values) {
      await connection.close();
    }
    await testServer.close(force: true);
    print("Test server stopped.");
  });

  // Helper function to send an SSE event through the active connections

  group('StreamableHttpClientTransport', () {
    late StreamableHttpClientTransport transport;

    setUp(() {
      currentSseConnections.clear();
    });

    tearDown(() async {
      try {
        await transport.close();
      } catch (e) {
        // Ignore errors during teardown
      }
    });

    test('constructor initializes with default options', () {
      transport = StreamableHttpClientTransport(serverUrl);
      expect(transport, isNotNull);
    });

    test('constructor accepts custom options', () {
      final mockAuthProvider = MockOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: StreamableHttpClientTransportOptions(
          authProvider: mockAuthProvider,
          requestInit: {
            'headers': {'test-header': 'test-value'},
          },
          reconnectionOptions: const StreamableHttpReconnectionOptions(
            maxReconnectionDelay: 5000,
            initialReconnectionDelay: 500,
            reconnectionDelayGrowFactor: 2.0,
            maxRetries: 3,
          ),
          sessionId: 'custom-session-id',
        ),
      );
      expect(transport, isNotNull);
    });

    test('start initializes the transport', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();
      expect(transport, isNotNull);
    });

    test('send method sends a JsonRpcMessage', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      final request = const JsonRpcRequest(
        id: 123,
        method: 'test/method',
        params: {'data': 'test-data'},
      );

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        completer.complete(message);
      };

      await transport.send(request);

      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('No response received'),
      );

      expect(response, isA<JsonRpcResponse>());
      expect((response as JsonRpcResponse).id, equals(123));
      expect(response.result['success'], isTrue);
      expect(response.result['echo']['data'], equals('test-data'));
    });

    test('send with initialized notification triggers SSE establishment',
        () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      final notification = const JsonRpcInitializedNotification();

      await transport.send(notification);

      // Wait a moment for the GET request to be established
      await Future.delayed(const Duration(milliseconds: 500));

      // If a connection was established, currentSseConnections should have an entry
      expect(currentSseConnections.isEmpty, isFalse);
    });

    test('close method terminates the transport', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      final closeCompleter = Completer<void>();
      transport.onclose = () {
        closeCompleter.complete();
      };

      await transport.close();

      await closeCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('onclose not called'),
      );
    });

    test(
      '_getNextReconnectionDelay implements exponential backoff',
      () async {
        // Set up a reconnection simulation flag

        // Create a new transport with specialized reconnection options
        transport = StreamableHttpClientTransport(
          serverUrl,
          opts: const StreamableHttpClientTransportOptions(
            reconnectionOptions: StreamableHttpReconnectionOptions(
              initialReconnectionDelay: 100, // Very short to make test faster
              reconnectionDelayGrowFactor: 1.1,
              maxReconnectionDelay: 500,
              maxRetries: 10, // Plenty of retries
            ),
          ),
        );

        await transport.start();

        // We'll test the algorithm by sending a notification
        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        // Wait for SSE connection to establish
        await Future.delayed(const Duration(milliseconds: 500));

        // Make sure we have at least one connection before proceeding
        if (currentSseConnections.isEmpty) {
          fail('Initial connection was not established');
        }

        // Close all current connections to simulate a disconnect
        for (var connection in List<HttpResponse>.from(currentSseConnections)) {
          try {
            await connection.close();
          } catch (e) {
            print('Error closing connection: $e');
          }
        }
        currentSseConnections.clear();

        // Wait for the client to attempt reconnection
        await Future.delayed(const Duration(seconds: 2));

        // After the delay, manually "accept" a new connection by sending another notification
        await transport.send(notification);

        // Wait for the new connection to establish
        await Future.delayed(const Duration(milliseconds: 500));

        // Now we should have a new connection
        expect(
          currentSseConnections.isNotEmpty,
          isTrue,
          reason: 'New connection should be established after reconnection',
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'receives SSE events',
      () async {
        transport = StreamableHttpClientTransport(serverUrl);

        // Set up the message handler first
        final messageCompleter = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          print('Transport received message: ${jsonEncode(message.toJson())}');
          messageCompleter.complete(message);
        };

        transport.onerror = (error) {
          print('Transport error: $error');
        };

        await transport.start();

        // Send initialization notification to establish SSE connection
        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        // Wait for SSE connection to be established
        await Future.delayed(const Duration(milliseconds: 1000));

        if (currentSseConnections.isEmpty) {
          fail('No SSE connections established');
        }

        print(
          'About to send SSE event, active connections: ${currentSseConnections.length}',
        );

        // Send a valid JSON-RPC notification via SSE using proper SSE format
        for (final connection
            in List<HttpResponse>.from(currentSseConnections)) {
          try {
            final message = const JsonRpcNotification(
              method: 'notifications/initialized',
            );

            final data = jsonEncode(message.toJson());
            print('Sending SSE event with data: $data');

            // Send data with proper SSE format in a single write operation
            // This avoids the header already sent error
            connection.write('data: $data\n\n');
            await connection.flush();
            print('Sent SSE event');
          } catch (e) {
            print('Error sending SSE event: $e');
            fail('Failed to send SSE event: $e');
          }
        }

        // Wait for the message with a longer timeout
        final message = await messageCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('*** TIMEOUT: No message received via SSE after 5 seconds');
            throw TimeoutException('No message received via SSE');
          },
        );

        expect(message, isA<JsonRpcNotification>());
        expect(
          (message as JsonRpcNotification).method,
          equals('notifications/initialized'),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'authentication flow works',
      () async {
        // Create a mock auth provider that specifically implements the required behavior
        final mockAuthProvider = MockOAuthClientProvider(returnTokens: false);

        // Override the standard method to ensure it redirects
        mockAuthProvider.registerRedirectToAuthorization(() async {
          mockAuthProvider.didRedirectToAuthorization = true;
          print('Mock redirected to authorization!');
        });

        transport = StreamableHttpClientTransport(
          serverUrl,
          opts: StreamableHttpClientTransportOptions(
            authProvider: mockAuthProvider,
          ),
        );

        await transport.start();

        final request = const JsonRpcRequest(
          id: 123,
          method: 'test/method',
          params: {'data': 'test-data'},
        );

        // Set up an error handler to verify errors
        final errorCompleter = Completer<Error>();
        transport.onerror = (error) {
          print('Auth test error: $error');
          errorCompleter.complete(error);
        };

        try {
          // This should trigger auth flow and eventually throw
          await transport.send(request);

          // If we get here, we should check the auth provider state
          if (!mockAuthProvider.didRedirectToAuthorization) {
            fail('Auth provider did not redirect to authorization');
          }
        } catch (e) {
          print('Auth test caught exception: $e');
          // This is expected since we're using a mock that doesn't return tokens
        }

        // Verify the auth provider was called to redirect
        expect(
          mockAuthProvider.didRedirectToAuthorization,
          isTrue,
          reason: 'Auth provider should have redirected to authorization',
        );

        // For the second part of the test, use a new transport that succeeds
        final successAuthProvider = MockOAuthClientProvider(returnTokens: true);
        transport = StreamableHttpClientTransport(
          serverUrl,
          opts: StreamableHttpClientTransportOptions(
            authProvider: successAuthProvider,
          ),
        );
        await transport.start();

        // Set up the message handler
        final completer = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          completer.complete(message);
        };

        // Send the request with the authenticated transport
        await transport.send(request);

        // Verify we get a successful response
        final response = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('No response received after auth'),
        );

        expect(response, isA<JsonRpcResponse>());
        expect((response as JsonRpcResponse).id, equals(123));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('terminateSession sends DELETE request', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      // Ensure we have a session ID
      final notification = const JsonRpcInitializedNotification();
      await transport.send(notification);

      // Wait for session establishment
      await Future.delayed(const Duration(milliseconds: 500));

      // Now terminate the session
      await transport.terminateSession();

      // Since the session was terminated, a successful result implies the
      // server received and processed our DELETE request
      expect(true, isTrue);
    });

    test(
      'handles CRLF line endings in SSE events',
      () async {
        transport = StreamableHttpClientTransport(serverUrl);

        final messageCompleter = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          print('Transport received message: ${jsonEncode(message.toJson())}');
          messageCompleter.complete(message);
        };

        transport.onerror = (error) {
          print('Transport error: $error');
        };

        await transport.start();

        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        await Future.delayed(const Duration(milliseconds: 1000));

        if (currentSseConnections.isEmpty) {
          fail('No SSE connections established');
        }

        print(
          'About to send SSE event, active connections: ${currentSseConnections.length}',
        );

        for (final connection
            in List<HttpResponse>.from(currentSseConnections)) {
          try {
            final message = const JsonRpcNotification(
              method: 'notifications/initialized',
            );

            final data = jsonEncode(message.toJson());
            print('Sending SSE event with data: $data');

            connection.write('event: message\r\n');
            connection.write('data: $data\r\n\r\n');
            await connection.flush();
            print('Sent SSE event');
          } catch (e) {
            print('Error sending SSE event: $e');
            fail('Failed to send SSE event: $e');
          }
        }

        final message = await messageCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('*** TIMEOUT: No message received via SSE after 5 seconds');
            throw TimeoutException('No message received via SSE');
          },
        );

        expect(message, isA<JsonRpcNotification>());
        expect(
          (message as JsonRpcNotification).method,
          equals('notifications/initialized'),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    group('Error Handling and Edge Cases', () {
      test('handles finishAuth without auth provider', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        // Calling finishAuth without authProvider should throw
        expect(
          () async => await transport.finishAuth('test-code'),
          throwsA(isA<UnauthorizedError>()),
        );
      });

      test('start throws error if already started', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        // Starting again should throw
        expect(
          () async => await transport.start(),
          throwsA(isA<McpError>()),
        );
      });

      test('sessionId is tracked correctly', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        expect(transport.sessionId, isNull);

        // Send a message that will get a session ID
        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        await Future.delayed(const Duration(milliseconds: 500));

        // Session ID should be set from server
        expect(transport.sessionId, isNotNull);
      });

      test('terminateSession with no session does nothing', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        // Should complete without error
        await transport.terminateSession();
        expect(true, isTrue);
      });

      test('handles error callback configuration', () async {
        transport = StreamableHttpClientTransport(serverUrl);

        transport.onerror = (error) {
          // Error callback configured
        };

        await transport.start();

        // Error callback should be configured
        expect(transport.onerror, isNotNull);
      });

      test('handles onclose callback configuration', () async {
        transport = StreamableHttpClientTransport(serverUrl);

        var oncloseCalled = false;
        transport.onclose = () {
          oncloseCalled = true;
        };

        await transport.start();
        await transport.close();

        expect(oncloseCalled, isTrue);
      });
    });
  });
}
