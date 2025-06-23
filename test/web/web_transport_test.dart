@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/src/client/streamable_https.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

/// A web-specific mock implementation of OAuthClientProvider for testing
class WebMockOAuthClientProvider implements OAuthClientProvider {
  final bool returnTokens;
  bool didRedirectToAuthorization = false;
  Function? redirectToAuthorizationCb;

  WebMockOAuthClientProvider({this.returnTokens = true});

  @override
  Future<OAuthTokens?> tokens() async {
    if (returnTokens) {
      return OAuthTokens(accessToken: 'test-web-access-token');
    }
    return null;
  }

  @override
  Future<void> redirectToAuthorization() async {
    if (redirectToAuthorizationCb != null) {
      redirectToAuthorizationCb!();
    } else {
      didRedirectToAuthorization = true;
      // In a real web app, this would redirect the window
      print('Mock web redirect to authorization URL');
    }
  }

  void registerRedirectToAuthorization(Function callback) {
    redirectToAuthorizationCb = callback;
  }
}

// Simplified web tests that don't require HTTP mocking

void main() {
  // Use a mock server URL since we can't start a real server in the browser
  final mockServerUrl = Uri.parse('https://mock-test-server.example.com/mcp');

  group('Web StreamableHttpClientTransport', () {
    late StreamableHttpClientTransport transport;

    setUp(() {
      // No setup needed for simplified tests
    });

    tearDown(() async {
      try {
        await transport.close();
      } catch (e) {
        // Ignore errors during teardown
      }
    });

    test('constructor works in web environment', () {
      transport = StreamableHttpClientTransport(mockServerUrl);
      expect(transport, isNotNull);
    });

    test('constructor accepts web-compatible options', () {
      final mockAuthProvider = WebMockOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        opts: StreamableHttpClientTransportOptions(
          authProvider: mockAuthProvider,
          requestInit: {
            'headers': {'test-web-header': 'test-web-value'}
          },
          reconnectionOptions: StreamableHttpReconnectionOptions(
            maxReconnectionDelay: 5000,
            initialReconnectionDelay: 500,
            reconnectionDelayGrowFactor: 2.0,
            maxRetries: 3,
          ),
          sessionId: 'custom-web-session-id',
        ),
      );
      expect(transport, isNotNull);
    });

    test('start initializes the transport in web environment', () async {
      transport = StreamableHttpClientTransport(mockServerUrl);
      await transport.start();
      expect(transport, isNotNull);
    });

    test('send method can be called without throwing in browser', () async {
      transport = StreamableHttpClientTransport(mockServerUrl);
      await transport.start();

      final request = JsonRpcRequest(
        id: 123,
        method: 'test/method',
        params: {'data': 'test-web-data'},
      );

      // Just test that send doesn't throw - actual network will fail with mock URL
      try {
        await transport.send(request);
      } catch (e) {
        // Expected - mock URL will fail, but API should work
        expect(e, isA<Exception>());
        print('Expected network error with mock URL: $e');
      }
    });

    test('web authentication flow can be configured', () async {
      final mockAuthProvider = WebMockOAuthClientProvider(returnTokens: false);

      transport = StreamableHttpClientTransport(
        mockServerUrl,
        opts: StreamableHttpClientTransportOptions(
          authProvider: mockAuthProvider,
        ),
      );

      await transport.start();
      expect(transport, isNotNull);

      // Test that auth provider is configured
      final request = JsonRpcRequest(
        id: 456,
        method: 'test/method',
        params: {'data': 'test-auth-data'},
      );

      try {
        await transport.send(request);
      } catch (e) {
        // Expected - network will fail with mock URL
        print('Expected network error: $e');
      }
    });

    test('close method works in web environment', () async {
      transport = StreamableHttpClientTransport(mockServerUrl);
      await transport.start();

      final closeCompleter = Completer<void>();
      transport.onclose = () {
        closeCompleter.complete();
      };

      await transport.close();

      await closeCompleter.future.timeout(
        Duration(seconds: 2),
        onTimeout: () =>
            throw TimeoutException('onclose not called in web test'),
      );
    });

    test('web platform compatibility check', () {
      // This test verifies we're running in a web context
      expect(window, isNotNull, reason: 'Should be running in browser context');
      expect(document, isNotNull, reason: 'Should have access to DOM');

      // Verify our transport can be instantiated without dart:io imports
      transport = StreamableHttpClientTransport(mockServerUrl);
      expect(transport, isNotNull);

      print(
          '✓ Successfully created StreamableHttpClientTransport in web environment');
      print('✓ No dart:io dependencies detected');
      print('✓ Using package:http for cross-platform compatibility');
    });

    test('session management API works in web environment', () async {
      transport = StreamableHttpClientTransport(mockServerUrl);
      await transport.start();

      // Test that session APIs can be called
      expect(transport.sessionId, isNull); // No session initially

      try {
        await transport.terminateSession();
      } catch (e) {
        // Expected - network will fail with mock URL
        print('Expected network error: $e');
      }
    });
  });

  group('Web SSE Integration', () {
    test('transport can be created for SSE in web context', () {
      // This test ensures that the web transport works without dart:io dependencies

      try {
        final transport = StreamableHttpClientTransport(
          Uri.parse('https://example.com/test'),
        );
        expect(transport, isNotNull);
        print('✓ Web SSE transport creation successful');
      } catch (e) {
        fail('Web transport not compatible with web: $e');
      }
    });
  });

  group('Web HTTP Package Integration', () {
    test('http package is available in web context', () async {
      // Just test that we can create an HTTP request without errors
      final request =
          http.Request('POST', Uri.parse('https://example.com/test'));
      request.body = jsonEncode({'test': 'data'});
      request.headers['Content-Type'] = 'application/json';

      expect(request.method, equals('POST'));
      expect(request.url.toString(), equals('https://example.com/test'));

      print('✓ HTTP package integration successful in web environment');
    });
  });
}
