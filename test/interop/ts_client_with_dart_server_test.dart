import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'test_dart_server.dart';

void main() {
  final tsClientPath =
      p.join(Directory.current.path, 'test/interop/ts/src/client.ts');
  final dartServerPath =
      p.join(Directory.current.path, 'test/interop/test_dart_server.dart');

  // Check if we should skip
  final skipTests =
      !File(tsClientPath).existsSync() || !File(dartServerPath).existsSync();

  group('TS Client with Dart Server', () {
    if (skipTests) {
      print('Skipping TS Client Interop tests: scripts not found');
      return;
    }

    test('Stdio Transport', () async {
      final result = await Process.run(
        'npx',
        [
          'tsx',
          tsClientPath,
          '--transport',
          'stdio',
          '--server-command',
          'dart',
          '--server-args',
          dartServerPath,
        ],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        print('Stdio Test Failed');
        print('Stdout: ${result.stdout}');
        print('Stderr: ${result.stderr}');
      }

      expect(
        result.exitCode,
        equals(0),
        reason: 'TS Client failed in Stdio mode',
      );
    });

    test(
      'Streamable HTTP Transport',
      () async {
        // Manual server setup to avoid modifying SDK
        final httpServer = await HttpServer.bind('127.0.0.1', 0);
        final port = httpServer.port;
        final sessionId = generateUUID();

        // We manually inject the session to bypass the "initialization" request logic
        // or we can just rely on the transport state.
        // Actually, StreamableHTTPServerTransport expects an initialization request to CREATE a session.
        // But we want to pre-seed it for the test so we can give the ID to the client?
        //
        // Issue: The TS client in the test is passed a sessionId.
        // The `StreamableHttpClientTransport` sets headers.
        // `StreamableHTTPServerTransport` validates headers against its internal `sessionId`.
        //
        // If we use the public API of `StreamableHTTPServerTransport`:
        // `transport.handleRequest` processes requests.
        // Initialization request (POST with method: initialize) triggers `_sessionIdGenerator` and sets `sessionId`.
        //
        // If we want to PRE-DETERMINE the session ID so we can pass it to the client command line props:
        // We can mock the generator!

        final specificTransport = StreamableHTTPServerTransport(
          options: StreamableHTTPServerTransportOptions(
            sessionIdGenerator: () => sessionId, // Force this ID
            onsessioninitialized: (sid) {
              print('Session initialized: $sid');
            },
          ),
        ); // Wire up the server
        // We need a server instance per session in a real app, but here we just have one.
        final mcpServer = createServer();

        // We need to connect the server to the transport.
        // Usually done inside the simpler `StreamableMcpServer` wrapper.
        // Here we do it manually.
        // BUT `mcpServer.connect(transport)` expects the transport to be ready.
        // Also `StreamableHTTPServerTransport` is designed to be one-to-one with a session if it has state.
        // In the SDK, `StreamableMcpServer` creates a NEW transport for each new session.
        //
        // For this test, we can just use one transport and assume one session.
        // But `mcpServer.connect` is async.

        // Wait! `mcpServer.connect(transport)` just sets up the message handling.
        // We should call it.
        mcpServer.connect(specificTransport);

        httpServer.listen((request) async {
          if (request.uri.path == '/mcp') {
            // We need to handle CORS manually here as `StreamableMcpServer` did it
            request.response.headers.add('Access-Control-Allow-Origin', '*');
            request.response.headers.add(
              'Access-Control-Allow-Methods',
              'GET, POST, DELETE, OPTIONS',
            );
            request.response.headers.add(
              'Access-Control-Allow-Headers',
              'Origin, X-Requested-With, Content-Type, Accept, mcp-session-id, Last-Event-ID, Authorization',
            );

            if (request.method == 'OPTIONS') {
              request.response.close();
              return;
            }

            await specificTransport.handleRequest(request);
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.close();
          }
        });

        print(
          'Server started on port $port with (expected) session $sessionId',
        );

        try {
          // Start TS Client
          try {
            print("Starting TS Client with Session ID $sessionId...");
            final clientProcess = await Process.start(
              'npx',
              [
                'tsx',
                tsClientPath,
                '--transport',
                'http',
                '--url',
                'http://127.0.0.1:$port/mcp?sessionId=$sessionId', // Pass session ID
              ],
              runInShell: true,
            );

            clientProcess.stdout
                .transform(utf8.decoder)
                .listen((data) => print('[Client Output] $data'));
            clientProcess.stderr
                .transform(utf8.decoder)
                .listen((data) => print('[Client Error] $data'));

            final exitCode = await clientProcess.exitCode;

            if (exitCode != 0) {
              print('HTTP Test Failed with exit code $exitCode');
            }

            expect(
              exitCode,
              equals(0),
              reason: 'TS Client failed in HTTP mode',
            );
          } catch (e) {
            print('Error running client process: $e');
            rethrow;
          }
        } finally {
          await httpServer.close(force: true);
          await specificTransport.close();
          await mcpServer.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });
}
