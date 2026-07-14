@TestOn('browser')
library;

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('browser client sustains repeated 2026 requests', () async {
    await _exerciseRepeatedRequests(
      protocol: McpProtocol.stable,
      expectedVersion: previewProtocolVersion,
      label: '2026',
    );
  });

  test('browser client sustains repeated legacy requests', () async {
    await _exerciseRepeatedRequests(
      protocol: McpProtocol.legacy,
      expectedVersion: stableProtocolVersion,
      label: 'legacy',
    );
  });

  test('browser cancellation closes one 2026 response stream and recovers',
      () async {
    final client = McpClient(
      const Implementation(
        name: 'mcp-dart-browser-cancellation-client',
        version: '0.0.0',
      ),
      options: const McpClientOptions(protocol: McpProtocol.require2026),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:8765/mcp'),
    );

    try {
      await client.connect(transport).timeout(const Duration(seconds: 20));
      final controller = BasicAbortController();
      final requestStarted = Completer<void>();
      final request = client.callTool(
        const CallToolRequest(
          name: 'test_stream_cancellation',
          arguments: {},
        ),
        options: RequestOptions(
          signal: controller.signal,
          timeoutEnabled: false,
          onprogress: (_) {
            if (!requestStarted.isCompleted) {
              requestStarted.complete();
            }
          },
        ),
      );
      await requestStarted.future.timeout(const Duration(seconds: 10));

      controller.abort('browser request cancelled');
      await expectLater(
        request,
        throwsA(
          predicate<Object?>(
            (error) => error.toString().contains('browser request cancelled'),
          ),
        ),
      );

      var observedCancellations = 0;
      for (var attempt = 0;
          attempt < 10 && observedCancellations == 0;
          attempt++) {
        final status = await client
            .callTool(
              const CallToolRequest(
                name: 'test_stream_cancellation_status',
                arguments: {},
              ),
            )
            .timeout(const Duration(seconds: 10));
        observedCancellations = int.parse(
          (status.content.single as TextContent).text,
        );
      }
      expect(observedCancellations, greaterThan(0));

      final tools =
          await client.listTools().timeout(const Duration(seconds: 10));
      expect(
        tools.tools.map((tool) => tool.name),
        contains('echo'),
      );
    } finally {
      await client.close();
    }
  });
}

Future<void> _exerciseRepeatedRequests({
  required McpProtocol protocol,
  required String expectedVersion,
  required String label,
}) async {
  final client = McpClient(
    Implementation(
      name: 'mcp-dart-browser-$label-client',
      version: '0.0.0',
    ),
    options: McpClientOptions(protocol: protocol),
  );
  final transport = StreamableHttpClientTransport(
    Uri.parse('http://localhost:8765/mcp'),
    opts: const StreamableHttpClientTransportOptions(
      reconnectionOptions: StreamableHttpReconnectionOptions(
        initialReconnectionDelay: 10,
        maxReconnectionDelay: 10,
        reconnectionDelayGrowFactor: 1,
        maxRetries: 2,
      ),
    ),
  );

  try {
    await client.connect(transport).timeout(const Duration(seconds: 20));
    expect(client.getProtocolVersion(), expectedVersion);

    for (var request = 1; request <= 12; request++) {
      final tools =
          await client.listTools().timeout(const Duration(seconds: 10));
      expect(
        tools.tools.map((tool) => tool.name),
        contains('echo'),
        reason: '$label tools/list request $request',
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    for (var request = 1; request <= 12; request++) {
      final message = 'from Dart browser $label request $request';
      final result = await client
          .callTool(
            CallToolRequest(
              name: 'echo',
              arguments: {'message': message},
            ),
          )
          .timeout(const Duration(seconds: 10));
      expect(
        result.content,
        isNotEmpty,
        reason: '$label tool request $request',
      );
      expect(result.content.first, isA<TextContent>());
      expect(
        (result.content.first as TextContent).text,
        message,
        reason: '$label tool request $request',
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    if (protocol == McpProtocol.legacy) {
      for (var request = 1; request <= 8; request++) {
        await expectLater(
          client
              .callTool(
                CallToolRequest(
                  name: 'missing-tool-$request',
                  arguments: const {},
                ),
              )
              .timeout(const Duration(seconds: 10)),
          throwsA(isA<McpError>()),
          reason: 'legacy error response $request',
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final toolsAfterErrors =
          await client.listTools().timeout(const Duration(seconds: 10));
      expect(
        toolsAfterErrors.tools.map((tool) => tool.name),
        contains('echo'),
        reason: 'legacy request after repeated error responses',
      );
    }
  } finally {
    await client.close();
  }
}
