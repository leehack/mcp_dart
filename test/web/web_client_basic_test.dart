@TestOn('browser')
library;

import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  group('Web Client Basic Tests', () {
    test('can create Client instance on web platform', () {
      final client = Client(
        Implementation(name: 'web-test-client', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(listChanged: true),
            sampling: {'test': true},
          ),
        ),
      );

      expect(client, isA<Client>());
    });

    test('can register capabilities before connection', () {
      final client = Client(
        Implementation(name: 'test', version: '1.0.0'),
      );

      expect(
        () => client.registerCapabilities(
          ClientCapabilities(
            experimental: {'webTest': true},
            roots: ClientCapabilitiesRoots(listChanged: false),
          ),
        ),
        returnsNormally,
      );
    });

    test('returns null server info before initialization', () {
      final client = Client(
        Implementation(name: 'test', version: '1.0.0'),
      );

      expect(client.getServerVersion(), isNull);
      expect(client.getServerCapabilities(), isNull);
      expect(client.getInstructions(), isNull);
    });

    test('throws when checking capabilities before initialization', () {
      final client = Client(
        Implementation(name: 'test', version: '1.0.0'),
      );

      expect(
        () => client.assertCapabilityForMethod('tools/list'),
        throwsA(isA<StateError>()),
      );
    });

    test('validates Client configuration options', () {
      final options = ClientOptions(
        capabilities: ClientCapabilities(
          experimental: {'test': true},
          roots: ClientCapabilitiesRoots(listChanged: false),
        ),
      );

      final client = Client(
        Implementation(name: 'test', version: '1.0.0'),
        options: options,
      );

      expect(client, isA<Client>());
    });

    test('can create StreamableHttpClientTransport on web', () {
      // This validates that the cross-platform transport works on web
      final transport = StreamableHttpClientTransport(
        Uri.parse('https://example.com/mcp'),
        opts: StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 1000,
            maxReconnectionDelay: 5000,
            reconnectionDelayGrowFactor: 1.2,
            maxRetries: 2,
          ),
        ),
      );

      expect(transport, isA<StreamableHttpClientTransport>());
      expect(transport.sessionId, isNull); // Not connected yet
    });

    test('Client can be configured with various capabilities', () {
      final capabilities1 = ClientCapabilities(
        roots: ClientCapabilitiesRoots(listChanged: true),
      );

      final capabilities2 = ClientCapabilities(
        sampling: {'model': 'test'},
        experimental: {'feature': true},
      );

      final client1 = Client(
        Implementation(name: 'test1', version: '1.0.0'),
        options: ClientOptions(capabilities: capabilities1),
      );

      final client2 = Client(
        Implementation(name: 'test2', version: '1.0.0'),
        options: ClientOptions(capabilities: capabilities2),
      );

      expect(client1, isA<Client>());
      expect(client2, isA<Client>());
    });

    test('Client methods exist and are callable', () {
      final client = Client(
        Implementation(name: 'test', version: '1.0.0'),
      );

      // These should not throw - just verify methods exist
      expect(() => client.getServerVersion(), returnsNormally);
      expect(() => client.getServerCapabilities(), returnsNormally);
      expect(() => client.getInstructions(), returnsNormally);

      // These will throw StateError since not connected, but that proves they exist
      expect(() => client.assertCapabilityForMethod('test'),
          throwsA(isA<StateError>()));
    });
  });

  group('Web Platform Validation', () {
    test('validates that web-specific imports work', () {
      // This test validates that our web-compatible imports are working
      expect(true, isTrue); // If this test runs, imports worked
    });

    test('can create MCP objects on web platform', () {
      // Test creating various MCP objects to ensure web compatibility
      final implementation =
          Implementation(name: 'web-client', version: '1.0.0');
      final capabilities = ClientCapabilities(
        roots: ClientCapabilitiesRoots(listChanged: true),
        sampling: {'test': true},
      );
      final options = ClientOptions(capabilities: capabilities);

      expect(implementation.name, equals('web-client'));
      expect(capabilities.roots?.listChanged, isTrue);
      expect(options.capabilities?.sampling?['test'], isTrue);
    });
  });
}
