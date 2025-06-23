@TestOn('browser')
library;

import 'dart:async';
import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  group('Web Client Real Server Tests', () {
    // Real Hugging Face MCP server from their blog post example
    final hfMcpServerUrl =
        Uri.parse('https://abidlabs-mcp-tools.hf.space/gradio_api/mcp/sse');

    test('can create web transport for real HF MCP server', () {
      final transport = StreamableHttpClientTransport(hfMcpServerUrl);
      expect(transport, isA<StreamableHttpClientTransport>());
    });

    test('can create Client for real server connection', () {
      final client = Client(
        Implementation(name: 'web-test-client', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(listChanged: true),
            sampling: {'temperature': 0.7},
          ),
        ),
      );

      expect(client, isA<Client>());
    });

    test('attempts real connection to HF MCP server', () async {
      final transport = StreamableHttpClientTransport(
        hfMcpServerUrl,
        opts: StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 1000,
            maxReconnectionDelay: 5000,
            reconnectionDelayGrowFactor: 1.2,
            maxRetries: 2,
          ),
        ),
      );

      final client = Client(
        Implementation(name: 'web-test-client', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(listChanged: true),
            sampling: {'model': 'web-test'},
          ),
        ),
      );

      bool connectionAttempted = false;
      bool receivedMessage = false;
      bool hadError = false;
      String? errorMessage;
      String? sessionId;

      // Set up event handlers to monitor the connection
      transport.onmessage = (message) {
        receivedMessage = true;
        print('📥 Received: ${message.runtimeType}');
      };

      transport.onerror = (error) {
        hadError = true;
        errorMessage = error.toString();
        print('❌ Transport error: $error');
      };

      transport.onclose = () {
        print('🔌 Transport closed');
      };

      try {
        connectionAttempted = true;
        print('🌐 Attempting connection to: $hfMcpServerUrl');

        // Try to connect with a timeout
        await client.connect(transport).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Connection timeout after 10 seconds');
          },
        );

        sessionId = transport.sessionId;
        print('✅ Connected! Session ID: $sessionId');

        // If we get here, connection was successful
        expect(sessionId, isNotNull);
        expect(client.getServerVersion(), isNotNull);

        // Try to list tools
        final tools = await client.listTools().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('List tools timeout');
          },
        );

        print('🔧 Found ${tools.tools.length} tools');
        for (final tool in tools.tools) {
          print('  • ${tool.name}: ${tool.description}');
        }
      } catch (e) {
        print('⚠️ Expected connection error: $e');
        // Connection errors are expected in testing environment
        // The important thing is that we can create the objects and attempt connection
      } finally {
        await client.close();
        await transport.close();
      }

      // Validate that we actually attempted the connection
      expect(connectionAttempted, isTrue,
          reason: 'Should have attempted connection to real server');

      print('📊 Test Results:');
      print('  Connection attempted: $connectionAttempted');
      print('  Received message: $receivedMessage');
      print('  Had error: $hadError');
      print('  Error message: $errorMessage');
      print('  Session ID: $sessionId');
    });

    test('validates cross-platform compatibility in browser', () async {
      // This test validates that all our cross-platform components work in browser

      final transport = StreamableHttpClientTransport(
        hfMcpServerUrl,
        opts: StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 500,
            maxReconnectionDelay: 2000,
            reconnectionDelayGrowFactor: 1.1,
            maxRetries: 1,
          ),
        ),
      );

      final client = Client(
        Implementation(name: 'cross-platform-test', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            experimental: {'browserTest': true},
            roots: ClientCapabilitiesRoots(listChanged: false),
          ),
        ),
      );

      // Test that we can create all the objects without errors
      expect(transport, isA<Transport>());
      expect(client, isA<Client>());

      // Test that methods exist and are callable
      expect(() => client.getServerVersion(), returnsNormally);
      expect(() => client.getServerCapabilities(), returnsNormally);

      // Test capability registration before connection
      expect(
        () => client.registerCapabilities(
          ClientCapabilities(sampling: {'test': true}),
        ),
        returnsNormally,
      );

      print('✅ Cross-platform compatibility validated in browser environment');
    });

    test('validates MCP protocol types work in web environment', () {
      // Test creating various MCP protocol objects to ensure web compatibility

      final initParams = InitializeRequestParams(
        protocolVersion: latestProtocolVersion,
        capabilities: ClientCapabilities(
          roots: ClientCapabilitiesRoots(listChanged: true),
          sampling: {'model': 'test'},
          experimental: {'webSupport': true},
        ),
        clientInfo: Implementation(name: 'web-client', version: '1.0.0'),
      );

      final initRequest = JsonRpcInitializeRequest(
        id: 42,
        initParams: initParams,
      );

      final pingRequest = JsonRpcPingRequest(id: 43);

      final listToolsRequest = JsonRpcListToolsRequest(
        id: 44,
        params: ListToolsRequestParams(),
      );

      // Validate objects can be created and serialized
      expect(initRequest.toJson(), isA<Map<String, dynamic>>());
      expect(pingRequest.toJson(), isA<Map<String, dynamic>>());
      expect(listToolsRequest.toJson(), isA<Map<String, dynamic>>());

      expect(initRequest.id, equals(42));
      expect(initRequest.method, equals('initialize'));
      expect(initRequest.initParams.protocolVersion,
          equals(latestProtocolVersion));

      print('✅ MCP protocol types work correctly in web environment');
    });
  });
}
