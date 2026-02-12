import 'package:mcp_dart/src/client/module.dart' as client_module;
import 'package:mcp_dart/src/server/module.dart' as server_module;
import 'package:mcp_dart/src/shared/module.dart' as shared_module;
import 'package:test/test.dart';

void main() {
  group('Module exports', () {
    test('client module symbols are available', () {
      client_module.Client? client;
      client_module.StdioClientTransport? stdioTransport;

      expect(client, isNull);
      expect(stdioTransport, isNull);
    });

    test('server module symbols are available', () {
      server_module.McpServer? server;
      server_module.StreamableMcpServer? streamableServer;

      expect(server, isNull);
      expect(streamableServer, isNull);
    });

    test('shared module symbols are available', () {
      shared_module.Protocol? protocol;
      shared_module.Transport? transport;

      expect(protocol, isNull);
      expect(transport, isNull);
    });
  });
}
