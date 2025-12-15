import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('stdio transport integration test', () {
    late Client client;
    late StdioClientTransport transport;
    final stderrOutput = <String>[];
    StreamSubscription<String>? stderrSub;

    // Path to the example stdio server file
    final String serverFilePath =
        '${Directory.current.path}/example/server_stdio.dart';

    setUp(() async {
      // Verify the server file exists
      final serverFile = File(serverFilePath);
      expect(
        await serverFile.exists(),
        isTrue,
        reason: 'Example server file not found',
      );

      // Create the client and transport
      client = Client(
        const Implementation(name: "test-stdio-client", version: "1.0.0"),
      );
      transport = StdioClientTransport(
        StdioServerParameters(
          command: 'dart',
          args: [serverFilePath],
          stderrMode: ProcessStartMode.normal, // Pipe stderr for debugging
        ),
      );

      // Set up error handlers
      client.onerror = (error) => fail('Client error: $error');

      transport.onerror = (error) {
        // Don't fail here as some non-critical errors might occur
        stderrOutput.add('Transport error: $error');
      };

      // Capture stderr output from the server process
      stderrSub = transport.stderr
          ?.transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrOutput.add(line);
      });
    });

    tearDown(() async {
      // Clean up resources
      try {
        await transport.close();
      } catch (e) {
        // Ignore errors during cleanup
      }

      await stderrSub?.cancel();
    });

    test(
      'client and server communicate successfully using stdio transport',
      () async {
        // Connect client to the transport and establish communication
        await client.connect(transport);

        // Make sure connection is established
        await Future.delayed(const Duration(milliseconds: 500));

        // Get available tools
        final tools = await client.listTools();
        expect(
          tools.tools.isNotEmpty,
          isTrue,
          reason: 'Server should return at least one tool',
        );
        expect(
          tools.tools.any((tool) => tool.name == 'calculate'),
          isTrue,
          reason: 'Server should have a "calculate" tool',
        );

        // Test all calculator operations
        final operations = [
          {
            'operation': 'add',
            'a': 5,
            'b': 3,
            'expected': 'Result: 8',
            'description': 'Addition',
          },
          {
            'operation': 'subtract',
            'a': 10,
            'b': 4,
            'expected': 'Result: 6',
            'description': 'Subtraction',
          },
          {
            'operation': 'multiply',
            'a': 6,
            'b': 7,
            'expected': 'Result: 42',
            'description': 'Multiplication',
          },
          {
            'operation': 'divide',
            'a': 20,
            'b': 5,
            'expected': r'Result: 4(\.0)?$',
            'description': 'Division',
            'isRegex': true,
          }
        ];

        for (final op in operations) {
          final params = CallToolRequest(
            name: 'calculate',
            arguments: {
              'operation': op['operation'],
              'a': op['a'],
              'b': op['b'],
            },
          );

          final result = await client.callTool(params);
          expect(
            result.content.first is TextContent,
            isTrue,
            reason: 'Result should contain TextContent',
          );

          final textContent = result.content.first as TextContent;

          if (op['isRegex'] == true) {
            expect(
              textContent.text,
              matches(op['expected'] as String),
              reason: '${op['description']} result incorrect',
            );
          } else {
            expect(
              textContent.text,
              op['expected'],
              reason: '${op['description']} result incorrect',
            );
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
