import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('stdio transport concurrent sends', () {
    late Client client;
    late StdioClientTransport transport;
    StreamSubscription<String>? stderrSub;

    final String serverFilePath =
        '${Directory.current.path}/example/server_stdio.dart';

    setUp(() async {
      client = Client(
        const Implementation(name: "test-concurrent-client", version: "1.0.0"),
      );
      transport = StdioClientTransport(
        StdioServerParameters(
          command: Platform.resolvedExecutable,
          args: [serverFilePath],
          stderrMode: ProcessStartMode.normal,
        ),
      );

      stderrSub = transport.stderr
          ?.transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {});

      await client.connect(transport);
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDown(() async {
      try {
        await transport.close();
      } catch (_) {}
      await stderrSub?.cancel();
    });

    test('concurrent callTool requests all succeed', () async {
      final calls = List.generate(10, (i) {
        return client.callTool(
          CallToolRequest(
            name: 'calculate',
            arguments: {'operation': 'add', 'a': i, 'b': 100},
          ),
        );
      });

      final results = await Future.wait(calls);

      for (var i = 0; i < results.length; i++) {
        final text = (results[i].content.first as TextContent).text;
        expect(text, 'Result: ${i + 100}', reason: 'Call $i returned wrong result');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('concurrent calls complete faster than sequential', () async {
      final sequentialStart = DateTime.now();
      for (var i = 0; i < 5; i++) {
        await client.callTool(
          CallToolRequest(
            name: 'calculate',
            arguments: {'operation': 'multiply', 'a': i, 'b': 2},
          ),
        );
      }
      final sequentialTime = DateTime.now().difference(sequentialStart);

      final concurrentStart = DateTime.now();
      await Future.wait(List.generate(5, (i) {
        return client.callTool(
          CallToolRequest(
            name: 'calculate',
            arguments: {'operation': 'multiply', 'a': i, 'b': 3},
          ),
        );
      }));
      final concurrentTime = DateTime.now().difference(concurrentStart);

      expect(
        concurrentTime.inMilliseconds <= sequentialTime.inMilliseconds,
        isTrue,
        reason: 'Concurrent ($concurrentTime) should not be slower than sequential ($sequentialTime)',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
