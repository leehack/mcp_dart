@TestOn('browser')
@Tags(['browser-e2e'])
library;

import 'package:flutter_http_client/services/streamable_mcp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  test(
    'Flutter Web service sustains requests, errors, and reconnects',
    () async {
      final service = StreamableMcpService(
        serverUrl: 'http://localhost:3000/mcp',
      );
      addTearDown(service.dispose);

      expect(await service.connect(), isTrue, reason: service.connectionError);
      expect(service.negotiatedProtocolVersion, previewProtocolVersion);

      for (var request = 1; request <= 12; request++) {
        await service.listTools();
        expect(
          service.availableTools?.map((tool) => tool.name),
          contains('echo'),
          reason: 'MCP 2026-07-28 tools/list request $request',
        );
      }

      for (var request = 1; request <= 12; request++) {
        final message = 'flutter-browser-request-$request';
        final result = await service.callTool('echo', {'message': message});
        expect((result.content.single as TextContent).text, message);
      }

      await expectLater(
        service.callTool('missing-tool-for-browser-recovery', const {}),
        throwsA(isA<McpError>()),
      );
      await service.listTools();
      expect(
        service.availableTools?.map((tool) => tool.name),
        contains('echo'),
        reason: 'the client must remain usable after an expected RPC error',
      );

      expect(await service.reconnect(), isTrue);
      expect(service.negotiatedProtocolVersion, previewProtocolVersion);

      await service.listTools();
      const finalMessage = 'flutter-browser-after-reconnect';
      final finalResult = await service.callTool('echo', {
        'message': finalMessage,
      });
      expect((finalResult.content.single as TextContent).text, finalMessage);

      await service.disconnect();
      expect(service.isConnected, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
