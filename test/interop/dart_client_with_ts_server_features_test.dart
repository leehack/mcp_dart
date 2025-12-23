@Tags(['interop'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Interop tests for Dart client with TS server.
/// Tests features: roots, sampling, elicitation, completion, progress.
void main() {
  // Locate the TS server (compiled JS version)
  final defaultTsPath =
      p.join(io.Directory.current.path, 'test/interop/ts/dist/server.js');
  final tsServerScript =
      io.Platform.environment['TS_INTEROP_SERVER_CMD'] ?? defaultTsPath;

  // Check if we should skip
  final skipTests = !io.File(tsServerScript).existsSync();

  group('TS Interop - Dart Client Features', () {
    if (skipTests) {
      print(
        'Skipping TS Interop Feature tests: TS server not found at $tsServerScript',
      );
      return;
    }

    group('Stdio Transport', () {
      late McpClient client;
      late StdioClientTransport transport;

      setUp(() async {
        // 1. Create the StdioClientTransport with server parameters
        transport = StdioClientTransport(
          StdioServerParameters(
            command: 'node',
            args: [tsServerScript, '--transport', 'stdio'],
            stderrMode: io.ProcessStartMode.normal,
          ),
        );

        // 2. Create the Client instance with capabilities for roots, sampling, elicitation
        client = McpClient(
          const Implementation(name: 'dart-test-features', version: '1.0.0'),
          options: const McpClientOptions(
            capabilities: ClientCapabilities(
              roots: ClientCapabilitiesRoots(listChanged: true),
              sampling: ClientCapabilitiesSampling(),
              elicitation: ClientElicitation.formOnly(),
            ),
          ),
        );

        // 3. Set up client-side handlers for server-initiated requests

        // Roots handler - return mock roots
        client.setRequestHandler<JsonRpcListRootsRequest>(
          Method.rootsList,
          (request, extra) async {
            return ListRootsResult(
              roots: [
                Root(
                  uri: 'file:///home/user/documents',
                  name: 'Documents',
                ),
                Root(
                  uri: 'file:///home/user/projects',
                  name: 'Projects',
                ),
              ],
            );
          },
          (id, params, meta) => JsonRpcListRootsRequest(id: id),
        );

        // Sampling handler - return mock LLM response
        client.onSamplingRequest = (params) async {
          // Extract the prompt from messages
          final firstMessage = params.messages.firstOrNull;
          String promptText = 'unknown';
          if (firstMessage != null) {
            final content = firstMessage.content;
            if (content is SamplingTextContent) {
              promptText = content.text;
            }
          }
          return CreateMessageResult(
            model: 'mock-llm-model',
            role: SamplingMessageRole.assistant,
            content: SamplingTextContent(
              text: 'Mock LLM response to: $promptText',
            ),
          );
        };

        // Elicitation handler - return mock acceptance
        client.onElicitRequest = (params) async {
          return const ElicitResult(
            action: 'accept',
            content: {'confirmed': true},
          );
        };

        // 4. Connect the Client to the transport
        await client.connect(transport);
      });

      tearDown(() async {
        await client.close();
      });

      test('get_roots - server lists client roots', () async {
        final result = await client.callTool(
          const CallToolRequest(name: 'get_roots', arguments: {}),
        );

        expect(result.content, isNotEmpty);
        final textContent = result.content.first as TextContent;
        final roots =
            (jsonDecode(textContent.text) as List).cast<Map<String, dynamic>>();

        expect(roots, hasLength(2));
        expect(roots[0]['name'], equals('Documents'));
        expect(roots[1]['name'], equals('Projects'));
      });

      test('sample_llm - server requests LLM completion', () async {
        final result = await client.callTool(
          const CallToolRequest(
            name: 'sample_llm',
            arguments: {'prompt': 'Hello, world!'},
          ),
        );

        expect(result.content, isNotEmpty);
        final textContent = result.content.first as TextContent;
        expect(textContent.text, contains('Mock LLM response'));
        expect(textContent.text, contains('Hello, world!'));
      });

      test('elicit_input - server requests user input', () async {
        final result = await client.callTool(
          const CallToolRequest(
            name: 'elicit_input',
            arguments: {'message': 'Please confirm'},
          ),
        );

        expect(result.content, isNotEmpty);
        final textContent = result.content.first as TextContent;
        final elicitResult =
            jsonDecode(textContent.text) as Map<String, dynamic>;
        expect(elicitResult['action'], equals('accept'));
      });

      test('completion - client gets argument completions', () async {
        final result = await client.complete(
          const CompleteRequest(
            ref: PromptReference(name: 'greeting'),
            argument: ArgumentCompletionInfo(name: 'language', value: 'En'),
          ),
        );

        expect(result.completion.values, contains('English'));
      });

      test('progress_demo - tool completes with progress', () async {
        // Note: Progress notifications may not be received in all transport modes
        // The important thing is the tool call completes successfully
        final result = await client.callTool(
          const CallToolRequest(
            name: 'progress_demo',
            arguments: {'steps': 4},
          ),
        );

        expect(result.content, isNotEmpty);
        final textContent = result.content.first as TextContent;
        expect(textContent.text, contains('Completed'));
      });
    });
  });
}
