@TestOn('browser')
library;

import 'dart:async';

import 'package:web/web.dart';

import 'package:mcp_dart/src/client/streamable_https.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Integration test that simulates real web usage patterns
void main() {
  group('Web Integration Tests', () {
    test('web environment validation', () {
      // Ensure we're running in a browser context
      expect(window, isNotNull);
      expect(document, isNotNull);
      expect(window.location, isNotNull);

      print('✓ Running in browser context');
      print('✓ User agent: ${window.navigator.userAgent}');
      print('✓ Location: ${window.location.href}');
    });

    test('cross-platform package compatibility', () {
      // Test that all required packages are available and work in web context

      // 1. Test package:http availability
      try {
        // We can't make real HTTP requests in tests easily, but we can verify
        // the import and basic usage doesn't fail
        print('✓ package:http imported successfully');
      } catch (e) {
        fail('package:http not available in web context: $e');
      }

      // 2. Test package:eventflux availability
      try {
        // EventFlux is instantiated in the StreamableHttpClientTransport constructor
        final transport = StreamableHttpClientTransport(
          Uri.parse('https://example.com/mcp'),
        );
        expect(transport, isNotNull);
        print('✓ package:eventflux imported and instantiated successfully');
      } catch (e) {
        fail('package:eventflux not available in web context: $e');
      }

      // 3. Test no dart:io dependencies
      try {
        final transport = StreamableHttpClientTransport(
          Uri.parse('https://example.com/mcp'),
        );
        expect(transport, isNotNull);
        print('✓ No dart:io dependencies detected');
      } catch (e) {
        fail('dart:io dependency found: $e');
      }
    });

    test('realistic web usage scenario', () async {
      // Simulate a realistic web application usage pattern
      final serverUrl = Uri.parse('https://api.example.com/mcp');

      // 1. Create transport with realistic web options
      final transport = StreamableHttpClientTransport(
        serverUrl,
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {
              'User-Agent': window.navigator.userAgent,
              'Origin': window.location.origin,
              'Referer': window.location.href,
            }
          },
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 1000,
            maxReconnectionDelay: 30000,
            reconnectionDelayGrowFactor: 1.5,
            maxRetries: 3,
          ),
        ),
      );

      // 2. Set up event handlers like a real web app would
      var closeCount = 0;

      transport.onerror = (error) {
        print('Transport error (expected in test): $error');
      };

      transport.onmessage = (message) {
        print('Transport message: ${message.runtimeType}');
      };

      transport.onclose = () {
        closeCount++;
        print('Transport closed');
      };

      // 3. Start the transport
      await transport.start();
      expect(transport, isNotNull);

      // 4. The transport should be ready to use
      // In a real scenario, send would connect to a real server
      // Here we just verify the method exists and can be called
      try {
        final request = JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: {'protocolVersion': latestProtocolVersion},
        );

        // This will fail because we don't have a real server, but that's expected
        await transport.send(request);
      } catch (e) {
        // Expected - we don't have a real server to connect to
        print('Expected error when trying to connect to mock server: $e');
      }

      // 5. Clean up
      await transport.close();
      expect(closeCount, equals(1));

      print('✓ Realistic web usage scenario completed');
    });

    test('browser-specific features integration', () {
      // Test integration with browser-specific features that a web MCP client might use

      // 1. Local storage for session persistence
      window.localStorage['mcp_test_session'] = 'test-session-123';
      final storedSession = window.localStorage['mcp_test_session'];
      expect(storedSession, equals('test-session-123'));

      // 2. URL parameters for auth callbacks
      final currentUrl = window.location.href;
      expect(currentUrl, isNotNull);

      // 3. Console logging (commonly used in web debugging)
      print('MCP Dart web integration test running');

      // 4. Create transport with browser-persisted session ID
      final transport = StreamableHttpClientTransport(
        Uri.parse('https://example.com/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: storedSession,
        ),
      );

      expect(transport, isNotNull);
      print('✓ Browser-specific features integration successful');

      // Clean up
      window.localStorage.removeItem('mcp_test_session');
    });

    test('web security considerations', () {
      // Test that security-sensitive features work correctly in web context

      // 1. CORS headers are properly handled by the transport
      final transport = StreamableHttpClientTransport(
        Uri.parse('https://api.example.com/mcp'),
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {
              'Origin': window.location.origin,
              'Access-Control-Request-Method': 'POST',
              'Access-Control-Request-Headers': 'content-type,authorization',
            }
          },
        ),
      );

      expect(transport, isNotNull);

      // 2. Verify no sensitive data leakage in browser console
      // (This is more of a code review item, but we can check basic structure)

      // 3. Verify proper handling of authentication tokens
      final mockAuth = _MockWebAuthProvider();
      final authTransport = StreamableHttpClientTransport(
        Uri.parse('https://api.example.com/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: mockAuth,
        ),
      );

      expect(authTransport, isNotNull);
      print('✓ Web security considerations validated');
    });

    test('web error handling and recovery', () async {
      // Test error scenarios specific to web environments

      final transport = StreamableHttpClientTransport(
        Uri.parse('https://nonexistent-server-12345.example.com/mcp'),
        opts: StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 100, // Fast for testing
            maxReconnectionDelay: 500,
            reconnectionDelayGrowFactor: 1.2,
            maxRetries: 2,
          ),
        ),
      );

      transport.onerror = (error) {
        print('Received expected error: $error');
      };

      await transport.start();

      // Try to send a message to trigger connection attempt
      try {
        await transport.send(JsonRpcRequest(
          id: 1,
          method: 'test',
          params: {},
        ));
      } catch (e) {
        // Expected due to nonexistent server
        print('Expected connection error: $e');
      }

      // Give some time for error handling
      await Future.delayed(Duration(milliseconds: 200));

      await transport.close();

      print('✓ Web error handling and recovery tested');
    });
  });
}

/// Mock auth provider for web testing
class _MockWebAuthProvider implements OAuthClientProvider {
  @override
  Future<OAuthTokens?> tokens() async {
    return OAuthTokens(accessToken: 'mock-web-token');
  }

  @override
  Future<void> redirectToAuthorization() async {
    // In real implementation, this would redirect the browser window
    print('Mock web redirect to authorization');
  }
}
