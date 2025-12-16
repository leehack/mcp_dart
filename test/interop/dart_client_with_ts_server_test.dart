import 'dart:io' as io;
import 'dart:async';
import 'package:test/test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

void main() {
  // Locate the TS server (compiled JS version)
  // Default: test/interop/ts/dist/server.js relative to project root
  final defaultTsPath =
      p.join(io.Directory.current.path, 'test/interop/ts/dist/server.js');
  final tsServerScript =
      io.Platform.environment['TS_INTEROP_SERVER_CMD'] ?? defaultTsPath;

  // Check if we should skip
  final skipTests = !io.File(tsServerScript).existsSync();

  group('TS Interop', () {
    if (skipTests) {
      print(
        'Skipping TS Interop tests: TS server not found at $tsServerScript',
      );
      return;
    }

    group('Stdio', () {
      late StdioClientTransport transport;
      late Client client;

      setUp(() async {
        // 1. Create the StdioClientTransport with server parameters
        transport = StdioClientTransport(
          StdioServerParameters(
            command: 'node',
            args: [tsServerScript, '--transport', 'stdio'],
            stderrMode: io.ProcessStartMode.normal, // Ensure stdio is piped
          ),
        );

        // 2. Create the Client instance, which will use this transport
        client = Client(
          const Implementation(name: 'dart-test', version: '1.0'),
          options: const ClientOptions(
            capabilities: ClientCapabilities(),
          ),
        );

        // 3. Connect the Client to the transport (this internally calls transport.start())
        await client.connect(transport);
      });

      tearDown(() async {
        // This closes the client and its underlying transport, which also kills the spawned process.
        await client.close();
      });

      test('tools', () async {
        final result = await client.listTools();
        expect(result.tools.map((t) => t.name), containsAll(['echo', 'add']));

        final echo = await client.callTool(
          const CallToolRequest(
            name: 'echo',
            arguments: {'message': 'hello'},
          ),
        );
        expect((echo.content.first as TextContent).text, equals('hello'));

        final add = await client.callTool(
          const CallToolRequest(name: 'add', arguments: {'a': 10, 'b': 20}),
        );
        expect((add.content.first as TextContent).text, equals('30'));
      });

      test('resources', () async {
        final result = await client.readResource(
          ReadResourceRequestParams(
            uri: Uri.parse('resource://test').toString(),
          ),
        );
        expect(
          (result.contents.first as TextResourceContents).text,
          equals('This is a test resource'),
        );
      });

      test('prompts', () async {
        final result = await client.getPrompt(
          const GetPromptRequestParams(name: 'test_prompt', arguments: {}),
        );
        expect(result.messages.first.content, isA<TextContent>());
        expect(
          (result.messages.first.content as TextContent).text,
          equals('Test Prompt'),
        );
      });
    });

    group('HTTP', () {
      late StreamableHttpClientTransport transport;
      late Client client;
      late io.Process serverProcess;
      final port = 3001;

      setUp(() async {
        // 1. Manually spawn the external HTTP server
        serverProcess = await io.Process.start(
          'node',
          [tsServerScript, '--transport', 'http', '--port', '$port'],
          mode: io.ProcessStartMode.inheritStdio,
        );

        // Give node server a moment to start
        await Future.delayed(const Duration(seconds: 2));

        // 2. Create the StreamableHttpClientTransport
        transport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$port/mcp'),
        );

        // 3. Create the Client instance
        client = Client(
          const Implementation(name: 'dart-test', version: '1.0'),
          options: const ClientOptions(
            capabilities: ClientCapabilities(),
          ),
        );

        // 4. Connect the Client to the transport
        await client.connect(transport);
      });

      tearDown(() async {
        // This closes the client and its underlying transport
        await client.close();
        // Kill the manually spawned server
        serverProcess.kill();
      });

      test('tools', () async {
        final result = await client.listTools();
        expect(result.tools.map((t) => t.name), containsAll(['echo', 'add']));

        final echo = await client.callTool(
          const CallToolRequest(
            name: 'echo',
            arguments: {'message': 'hello'},
          ),
        );
        expect((echo.content.first as TextContent).text, equals('hello'));
      });
    });
  });
}
