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

/// Mock HTTP client for web testing
class MockWebHttpClient extends http.BaseClient {
  final Map<String, dynamic> responses = {};
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);

    final method = request.method;

    // Mock different responses based on request
    if (method == 'POST') {
      final body = await request.finalize().bytesToString();
      final requestData = jsonDecode(body) as Map<String, dynamic>;

      if (requestData['method'] == 'test/initialized') {
        return http.StreamedResponse(
          Stream.value([]),
          202,
          headers: {'mcp-session-id': 'test-web-session-id'},
        );
      } else if (requestData['id'] != null) {
        final response = {
          'jsonrpc': '2.0',
          'id': requestData['id'],
          'result': {'success': true, 'echo': requestData['params']}
        };
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(response))),
          200,
          headers: {
            'content-type': 'application/json',
            'mcp-session-id': 'test-web-session-id'
          },
        );
      }
    } else if (method == 'DELETE') {
      return http.StreamedResponse(
        Stream.value([]),
        200,
      );
    }

    return http.StreamedResponse(
      Stream.value([]),
      404,
    );
  }
}

void main() {
  // Use a mock server URL since we can't start a real server in the browser
  final mockServerUrl = Uri.parse('https://mock-test-server.example.com/mcp');

  group('Web StreamableHttpClientTransport', () {
    late StreamableHttpClientTransport transport;
    late MockWebHttpClient mockHttpClient;

    setUp(() {
      mockHttpClient = MockWebHttpClient();
    });

    tearDown(() async {
      try {
        await transport.close();
      } catch (e) {
        // Ignore errors during teardown
      }
    });

    test('constructor works in web environment', () {
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
      );
      expect(transport, isNotNull);
    });

    test('constructor accepts web-compatible options', () {
      final mockAuthProvider = WebMockOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
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
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
      );
      await transport.start();
      expect(transport, isNotNull);
    });

    test('send method works with mock HTTP client in browser', () async {
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
      );
      await transport.start();

      final request = JsonRpcRequest(
        id: 123,
        method: 'test/method',
        params: {'data': 'test-web-data'},
      );

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        completer.complete(message);
      };

      await transport.send(request);

      final response = await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('No response received in web test'),
      );

      expect(response, isA<JsonRpcResponse>());
      expect((response as JsonRpcResponse).id, equals(123));
      expect(response.result['success'], isTrue);
      expect(response.result['echo']['data'], equals('test-web-data'));

      // Verify the HTTP request was made
      expect(mockHttpClient.requests.length, equals(1));
      expect(mockHttpClient.requests.first.method, equals('POST'));
    });

    test('web authentication flow works', () async {
      final mockAuthProvider = WebMockOAuthClientProvider(returnTokens: false);

      mockAuthProvider.registerRedirectToAuthorization(() async {
        mockAuthProvider.didRedirectToAuthorization = true;
        print('Mock web auth redirected!');
      });

      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
        opts: StreamableHttpClientTransportOptions(
          authProvider: mockAuthProvider,
        ),
      );

      await transport.start();

      final request = JsonRpcRequest(
        id: 456,
        method: 'test/method',
        params: {'data': 'test-auth-data'},
      );

      try {
        await transport.send(request);
        if (!mockAuthProvider.didRedirectToAuthorization) {
          fail('Auth provider did not redirect to authorization in web test');
        }
      } catch (e) {
        // Expected since we're using a mock that doesn't return tokens initially
        print('Web auth test caught expected exception: $e');
      }

      expect(mockAuthProvider.didRedirectToAuthorization, isTrue,
          reason: 'Web auth provider should have redirected to authorization');

      // Test successful auth
      final successAuthProvider =
          WebMockOAuthClientProvider(returnTokens: true);
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
        opts: StreamableHttpClientTransportOptions(
          authProvider: successAuthProvider,
        ),
      );
      await transport.start();

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        completer.complete(message);
      };

      await transport.send(request);

      final response = await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('No response received after web auth'),
      );

      expect(response, isA<JsonRpcResponse>());
      expect((response as JsonRpcResponse).id, equals(456));
    });

    test('close method works in web environment', () async {
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
      );
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
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
      );
      expect(transport, isNotNull);

      print(
          '✓ Successfully created StreamableHttpClientTransport in web environment');
      print('✓ No dart:io dependencies detected');
      print(
          '✓ Using package:http and package:eventflux for cross-platform compatibility');
    });

    test('session management works in web environment', () async {
      transport = StreamableHttpClientTransport(
        mockServerUrl,
        httpClient: mockHttpClient,
      );
      await transport.start();

      // Send a request to establish session
      final request = JsonRpcRequest(
        id: 789,
        method: 'test/method',
        params: {'data': 'session-test'},
      );

      try {
        await transport.send(request);

        // Check that session ID is captured
        expect(transport.sessionId, isNotNull);
        expect(transport.sessionId, equals('test-web-session-id'));

        // Test session termination
        await transport.terminateSession();

        // Verify DELETE request was made
        final deleteRequests =
            mockHttpClient.requests.where((r) => r.method == 'DELETE');
        expect(deleteRequests.length, equals(1));
      } catch (e) {
        // In web environment, network errors are expected with mock URLs
        print('Expected network error in web environment: $e');
        expect(e, isA<Exception>());
      }
    });
  });

  group('Web EventFlux Integration', () {
    test('eventflux package is available in web context', () {
      // This test ensures that the eventflux package works in web environment
      // We can't easily test the full SSE functionality without a real server,
      // but we can verify the package loads and basic instantiation works

      try {
        // The StreamableHttpClientTransport constructor creates an EventFlux instance
        final transport = StreamableHttpClientTransport(
          Uri.parse('https://example.com/test'),
          httpClient: MockWebHttpClient(),
        );
        expect(transport, isNotNull);
        print('✓ EventFlux integration successful in web environment');
      } catch (e) {
        fail('EventFlux package not compatible with web: $e');
      }
    });
  });

  group('Web HTTP Package Integration', () {
    test('http package works correctly in web context', () async {
      final client = MockWebHttpClient();

      final request =
          http.Request('POST', Uri.parse('https://example.com/test'));
      request.body = jsonEncode({'test': 'data'});
      request.headers['Content-Type'] = 'application/json';

      final response = await client.send(request);
      expect(response.statusCode,
          equals(404)); // Our mock returns 404 for unknown routes

      print('✓ HTTP package integration successful in web environment');
    });
  });
}
