import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Completions Capability Integration Tests', () {
    test('Server declares completions capability', () {
      final mcpServer = McpServer(
        const Implementation(name: "test-server", version: "1.0.0"),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            completions: ServerCapabilitiesCompletions(),
          ),
        ),
      );

      final caps = mcpServer.server.getCapabilities();
      expect(caps.completions, isNotNull);
      expect(caps.completions, isA<ServerCapabilitiesCompletions>());
    });

    test('legacy listChanged flag is retained in memory only', () {
      final mcpServer = McpServer(
        const Implementation(name: "test-server", version: "1.0.0"),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            completions: ServerCapabilitiesCompletions(listChanged: true),
          ),
        ),
      );

      final caps = mcpServer.server.getCapabilities();
      expect(caps.completions, isNotNull);
      expect(caps.completions?.listChanged, equals(true));
      expect(caps.toJson()['completions'], isEmpty);
    });

    test('Server without completions capability returns null', () {
      final mcpServer = McpServer(
        const Implementation(name: "test-server", version: "1.0.0"),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );

      final caps = mcpServer.server.getCapabilities();
      expect(caps.completions, isNull);
    });

    test('Server with completions capability can be verified', () {
      // Create a server with completions capability
      final mcpServer = McpServer(
        const Implementation(name: "test-server", version: "1.0.0"),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            completions: ServerCapabilitiesCompletions(),
          ),
        ),
      );

      // Verify server capabilities include completions
      // This would normally happen during the connect/initialize handshake
      final caps = mcpServer.server.getCapabilities();
      expect(caps.completions, isNotNull);
    });

    test('Server with multiple capabilities including completions', () {
      final mcpServer = McpServer(
        const Implementation(name: "test-server", version: "1.0.0"),
        options: const ServerOptions(
          capabilities: ServerCapabilities(
            completions: ServerCapabilitiesCompletions(listChanged: true),
            tools: ServerCapabilitiesTools(listChanged: true),
            resources: ServerCapabilitiesResources(
              subscribe: true,
              listChanged: true,
            ),
            prompts: ServerCapabilitiesPrompts(listChanged: true),
          ),
        ),
      );

      final caps = mcpServer.server.getCapabilities();
      expect(caps.completions, isNotNull);
      expect(caps.toJson()['completions'], isEmpty);
      expect(caps.tools, isNotNull);
      expect(caps.resources, isNotNull);
      expect(caps.prompts, isNotNull);
    });

    test('Completions capability survives serialization round-trip', () {
      final originalCaps = const ServerCapabilities(
        completions: ServerCapabilitiesCompletions(listChanged: true),
        experimental: {'test': {}},
      );

      final json = originalCaps.toJson();
      final deserializedCaps = ServerCapabilities.fromJson(json);

      expect(deserializedCaps.completions, isNotNull);
      expect(json['completions'], isEmpty);
      expect(deserializedCaps.experimental?['test'], isEmpty);
    });

    test('legacy completions listChanged payload still parses', () {
      final caps = ServerCapabilities.fromJson(
        const {
          'completions': {'listChanged': true},
        },
      );

      expect(caps.completions?.listChanged, isTrue);
      expect(caps.toJson()['completions'], isEmpty);
    });
  });
}
