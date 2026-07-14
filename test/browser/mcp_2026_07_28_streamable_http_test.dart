@TestOn('browser')
library;

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('browser client negotiates and calls a 2026 server', () async {
    final client = McpClient(
      const Implementation(
        name: 'mcp-dart-browser-2026-07-28-client',
        version: '0.0.0',
      ),
      options: const McpClientOptions(protocol: McpProtocol.stable),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:8765/mcp'),
    );

    try {
      await client.connect(transport).timeout(const Duration(seconds: 20));
      expect(client.getProtocolVersion(), previewProtocolVersion);

      final tools =
          await client.listTools().timeout(const Duration(seconds: 10));
      expect(tools.tools.map((tool) => tool.name), contains('echo'));

      const message = 'from Dart browser 2026-07-28 RC';
      final result = await client
          .callTool(
            const CallToolRequest(
              name: 'echo',
              arguments: {'message': message},
            ),
          )
          .timeout(const Duration(seconds: 10));
      expect(result.content, isNotEmpty);
      expect(result.content.first, isA<TextContent>());
      expect((result.content.first as TextContent).text, message);
    } finally {
      await client.close();
    }
  });
}
