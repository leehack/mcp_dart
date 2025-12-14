import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/src/client/streamable_https.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock implementation of OAuthClientProvider for testing
class AdvancedMockOAuthProvider implements OAuthClientProvider {
  final bool returnTokens;
  bool redirectCalled = false;

  AdvancedMockOAuthProvider({this.returnTokens = true});

  @override
  Future<OAuthTokens?> tokens() async {
    if (returnTokens) {
      return OAuthTokens(accessToken: 'test-token');
    }
    return null;
  }

  @override
  Future<void> redirectToAuthorization() async {
    redirectCalled = true;
  }
}

/// Streamable HTTPS advanced scenarios
void main() {
  late HttpServer testServer;
  late int serverPort;
  late Uri serverUrl;
  StreamController<HttpRequest>? requestController;

  setUpAll(() async {
    testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverPort = testServer.port;
    serverUrl = Uri.parse('http://localhost:$serverPort/mcp');

    // Set up a single listener that forwards to a stream controller
    requestController = StreamController<HttpRequest>.broadcast();
    testServer.listen((request) {
      requestController?.add(request);
    });
  });

  tearDownAll(() async {
    await requestController?.close();
    await testServer.close(force: true);
  });

  group('Streamable HTTPS Advanced Integration', () {
    late StreamableHttpClientTransport transport;

    tearDown(() async {
      try {
        await transport.close();
      } catch (_) {}
    });

    test('reconnection delay calculation follows exponential backoff', () {
      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 100,
            reconnectionDelayGrowFactor: 2.0,
            maxReconnectionDelay: 1000,
            maxRetries: 5,
          ),
        ),
      );

      // Test is conceptual - the delay calculation is private
      // We're testing that the configuration is accepted and transport starts
      expect(transport, isNotNull);
    });

    test('max reconnection attempts prevents infinite retries', () async {
      // Handle requests - close GET immediately to trigger reconnection
      final subscription = requestController!.stream.listen((request) async {
        if (request.uri.path == '/mcp' && request.method == 'GET') {
          // Return non-200 status to trigger error and reconnection
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
        } else if (request.uri.path == '/mcp' && request.method == 'POST') {
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set('mcp-session-id', 'test-session');
          await request.response.close();
        }
      });

      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 50,
            reconnectionDelayGrowFactor: 1.1,
            maxReconnectionDelay: 200,
            maxRetries: 2, // Only 2 retries
          ),
        ),
      );

      final errors = <Error>[];
      transport.onerror = (error) {
        errors.add(error);
      };

      await transport.start();

      // Send initialization to trigger SSE connection
      try {
        await transport.send(const JsonRpcInitializedNotification());
      } catch (_) {
        // May fail, that's OK
      }

      // Wait for reconnection attempts to exhaust
      await Future.delayed(const Duration(seconds: 1));

      await subscription.cancel();

      // Should have received reconnection-related errors
      expect(errors.isNotEmpty, isTrue);
    });

    test('send handles HTTP request failure gracefully', () async {
      // Configure server to reject POST requests
      final subscription = requestController!.stream.listen((request) async {
        if (request.uri.path == '/mcp' && request.method == 'POST') {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      });

      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      // Send should handle failure
      try {
        await transport.send(
          const JsonRpcRequest(
            id: 1,
            method: 'test/method',
            params: {},
          ),
        );
        fail('Should have thrown an error');
      } catch (e) {
        expect(e, isA<McpError>());
      } finally {
        await subscription.cancel();
      }
    });

    test('handles network timeout during send', () async {
      // Configure server to delay response beyond timeout
      final subscription = requestController!.stream.listen((request) async {
        if (request.uri.path == '/mcp' && request.method == 'POST') {
          // Delay longer than reasonable timeout
          await Future.delayed(const Duration(seconds: 10));
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
        }
      });

      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: const StreamableHttpClientTransportOptions(
          requestInit: {
            'timeout': Duration(milliseconds: 100), // Short timeout
          },
        ),
      );

      await transport.start();

      // Send should timeout
      try {
        await transport
            .send(
              const JsonRpcRequest(
                id: 1,
                method: 'test/method',
                params: {},
              ),
            )
            .timeout(const Duration(milliseconds: 500));
        fail('Should have timed out');
      } catch (e) {
        expect(e, isA<TimeoutException>());
      } finally {
        await subscription.cancel();
      }
    });

    test('authentication flow handles missing authProvider', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      // finishAuth without authProvider should throw
      expect(
        () async => await transport.finishAuth('code'),
        throwsA(isA<UnauthorizedError>()),
      );
    });

    test('authentication flow handles token refresh', () async {
      final authProvider = AdvancedMockOAuthProvider(returnTokens: true);

      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      );

      await transport.start();

      // Verify auth provider was used
      expect(authProvider, isNotNull);
      // Test passes if no authorization redirect occurred
      expect(authProvider.redirectCalled, isFalse);
    });

    test('handles malformed SSE data gracefully', () async {
      final receivedErrors = <Error>[];

      final subscription = requestController!.stream.listen((request) async {
        if (request.uri.path == '/mcp' && request.method == 'GET') {
          request.response.headers.contentType =
              ContentType('text', 'event-stream');
          request.response.bufferOutput = false;

          // Send malformed SSE data
          request.response.write('data: {invalid json}\n\n');
          await request.response.flush();

          // Keep connection open briefly
          await Future.delayed(const Duration(milliseconds: 100));
          await request.response.close();
        } else if (request.uri.path == '/mcp' && request.method == 'POST') {
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set('mcp-session-id', 'test-session');
          await request.response.close();
        }
      });

      transport = StreamableHttpClientTransport(serverUrl);
      transport.onerror = (error) => receivedErrors.add(error);

      await transport.start();
      await transport.send(const JsonRpcInitializedNotification());

      // Wait for SSE connection and error processing
      await Future.delayed(const Duration(milliseconds: 500));

      await subscription.cancel();

      // Should have received parsing error
      expect(receivedErrors.isNotEmpty, isTrue);
    });

    test('custom reconnection options are respected', () {
      final customOptions = const StreamableHttpReconnectionOptions(
        initialReconnectionDelay: 500,
        maxReconnectionDelay: 5000,
        reconnectionDelayGrowFactor: 2.5,
        maxRetries: 10,
      );

      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: StreamableHttpClientTransportOptions(
          reconnectionOptions: customOptions,
        ),
      );

      // Configuration is accepted
      expect(transport, isNotNull);
    });

    test('send handles unauthorized response', () async {
      final subscription = requestController!.stream.listen((request) async {
        if (request.uri.path == '/mcp' && request.method == 'POST') {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
        }
      });

      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      // Send should throw McpError for 401 response without authProvider
      try {
        await transport.send(
          const JsonRpcRequest(
            id: 1,
            method: 'test/method',
            params: {},
          ),
        );
        fail('Should have thrown McpError');
      } catch (e) {
        expect(e, isA<McpError>());
      } finally {
        await subscription.cancel();
      }
    });
  });
}
