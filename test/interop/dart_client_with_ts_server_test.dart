@Tags(['interop'])
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<int> _findAvailablePort() async {
  final socket = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForTcpServer({
  required io.Process process,
  required String host,
  required int port,
  String label = 'interop server',
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastConnectionError;

  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await io.Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 250),
      );
      socket.destroy();
      return;
    } on Object catch (error) {
      lastConnectionError = error;
    }

    final exitCode = await Future.any<int?>([
      process.exitCode.then<int?>((code) => code),
      Future<int?>.delayed(const Duration(milliseconds: 50), () => null),
    ]);
    if (exitCode != null) {
      throw StateError(
        '$label exited with code $exitCode before '
        '$host:$port accepted connections.',
      );
    }
  }

  throw TimeoutException(
    'Timed out waiting for $label at $host:$port. '
    'Last connection error: $lastConnectionError',
    timeout,
  );
}

Future<void> _terminateProcess(io.Process process) async {
  final exitFuture = process.exitCode;
  process.kill();
  await exitFuture.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      if (!io.Platform.isWindows) {
        process.kill(io.ProcessSignal.sigkill);
      }
      return -1;
    },
  );
}

void main() {
  // Locate the TS server (compiled JS version)
  // Default: test/interop/ts/dist/server.js relative to project root
  final defaultTsPath =
      p.join(io.Directory.current.path, 'test/interop/ts/dist/server.js');
  final tsServerScript =
      io.Platform.environment['TS_INTEROP_SERVER_CMD'] ?? defaultTsPath;
  final defaultTsLegacySseClientPath = p.join(
    io.Directory.current.path,
    'test/interop/ts/dist/legacy_sse_client.js',
  );
  final tsLegacySseClientScript =
      io.Platform.environment['TS_LEGACY_SSE_CLIENT_CMD'] ??
          defaultTsLegacySseClientPath;

  final tsServerAvailable = io.File(tsServerScript).existsSync();
  final tsLegacySseClientAvailable =
      io.File(tsLegacySseClientScript).existsSync();
  final isCi = io.Platform.environment['CI'] == 'true';

  group('TS Interop', () {
    if (!tsServerAvailable) {
      final reason = 'TS Interop tests require the compiled server fixture at '
          '$tsServerScript';
      if (isCi) {
        test('TS fixture is available in CI', () {
          fail(reason);
        });
      } else {
        print('Skipping TS Interop tests: $reason');
      }
      return;
    }

    group('Stdio', () {
      late StdioClientTransport transport;
      late McpClient client;

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
        client = McpClient(
          const Implementation(name: 'dart-test', version: '1.0'),
          options: const McpClientOptions(
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
          ReadResourceRequest(
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
          const GetPromptRequest(name: 'test_prompt', arguments: {}),
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
      late McpClient client;
      late io.Process serverProcess;
      final port = 3001;

      setUp(() async {
        // 1. Manually spawn the external HTTP server
        serverProcess = await io.Process.start(
          'node',
          [tsServerScript, '--transport', 'http', '--port', '$port'],
          mode: io.ProcessStartMode.inheritStdio,
        );

        await _waitForTcpServer(
          process: serverProcess,
          host: '127.0.0.1',
          port: port,
        );

        // 2. Create the StreamableHttpClientTransport
        transport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$port/mcp'),
        );

        // 3. Create the Client instance
        client = McpClient(
          const Implementation(name: 'dart-test', version: '1.0'),
          options: const McpClientOptions(
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

      test('recovers from stale preconfigured session id during initialize',
          () async {
        final stalePort = await _findAvailablePort();
        final staleServerProcess = await io.Process.start(
          'node',
          [tsServerScript, '--transport', 'http', '--port', '$stalePort'],
          mode: io.ProcessStartMode.normal,
        );

        staleServerProcess.stdout
            .transform(io.systemEncoding.decoder)
            .listen((data) => print('[TS Server] $data'));
        staleServerProcess.stderr
            .transform(io.systemEncoding.decoder)
            .listen((data) => print('[TS Server Error] $data'));

        await _waitForTcpServer(
          process: staleServerProcess,
          host: '127.0.0.1',
          port: stalePort,
        );

        final staleTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$stalePort/mcp'),
          opts: const StreamableHttpClientTransportOptions(
            sessionId: 'stale-session-id',
          ),
        );
        final staleClient = McpClient(
          const Implementation(name: 'dart-stale-session-test', version: '1.0'),
          options: const McpClientOptions(
            capabilities: ClientCapabilities(),
          ),
        );

        try {
          await staleClient.connect(staleTransport);

          expect(staleTransport.sessionId, isNot(equals('stale-session-id')));
          expect(staleTransport.sessionId, isNotNull);

          final result = await staleClient.listTools();
          expect(result.tools.map((t) => t.name), containsAll(['echo', 'add']));
        } finally {
          await staleClient.close();
          staleServerProcess.kill();
        }
      });
    });

    group('Legacy SSE', () {
      group('Dart client to TypeScript server', () {
        SseClientTransport? transport;
        McpClient? client;
        io.Process? serverProcess;

        setUp(() async {
          final port = await _findAvailablePort();
          final startedServer = await io.Process.start(
            'node',
            [tsServerScript, '--transport', 'sse', '--port', '$port'],
            mode: io.ProcessStartMode.normal,
          );
          serverProcess = startedServer;
          startedServer.stdout
              .transform(io.systemEncoding.decoder)
              .listen((data) => print('[TS SSE Server] $data'));
          startedServer.stderr
              .transform(io.systemEncoding.decoder)
              .listen((data) => print('[TS SSE Server Error] $data'));

          await _waitForTcpServer(
            process: startedServer,
            host: '127.0.0.1',
            port: port,
            label: 'TypeScript legacy SSE server',
          );
          final startedTransport = SseClientTransport(
            Uri.parse('http://127.0.0.1:$port/sse'),
          );
          transport = startedTransport;
          final startedClient = McpClient(
            const Implementation(name: 'dart-sse-test', version: '1.0'),
            options: const McpClientOptions(
              protocol: McpProtocol.legacy,
              capabilities: ClientCapabilities(),
            ),
          );
          client = startedClient;
          await startedClient.connect(startedTransport);
        });

        tearDown(() async {
          try {
            await client?.close();
          } finally {
            final process = serverProcess;
            if (process != null) {
              await _terminateProcess(process);
            }
          }
        });

        test('initializes and calls tools through the official TS SSE server',
            () async {
          final connectedClient = client!;
          final connectedTransport = transport!;
          expect(
            connectedClient.getProtocolVersion(),
            latestInitializationProtocolVersion,
          );
          expect(connectedTransport.sessionId, isNotEmpty);

          final tools = await connectedClient.listTools();
          expect(
            tools.tools.map((tool) => tool.name),
            containsAll(['echo', 'add']),
          );

          final result = await connectedClient.callTool(
            const CallToolRequest(
              name: 'add',
              arguments: {'a': 10, 'b': 20},
            ),
          );
          expect((result.content.single as TextContent).text, '30');
        });
      });

      test('official TS client initializes and calls the Dart SSE server',
          () async {
        if (!tsLegacySseClientAvailable) {
          final reason = 'Reverse legacy SSE interop requires the compiled '
              'TypeScript client fixture at $tsLegacySseClientScript';
          if (isCi) {
            fail(reason);
          }
          markTestSkipped(reason);
          return;
        }

        final port = await _findAvailablePort();
        final serverProcess = await io.Process.start(
          io.Platform.resolvedExecutable,
          ['run', 'example/server_sse.dart'],
          mode: io.ProcessStartMode.normal,
          environment: {
            ...io.Platform.environment,
            'PORT': '$port',
            'MCP_ALLOWED_ORIGIN': 'http://localhost:$port',
          },
        );
        serverProcess.stdout
            .transform(io.systemEncoding.decoder)
            .listen((data) => print('[Dart SSE Server] $data'));
        serverProcess.stderr
            .transform(io.systemEncoding.decoder)
            .listen((data) => print('[Dart SSE Server Error] $data'));
        io.Process? clientProcess;

        try {
          await _waitForTcpServer(
            process: serverProcess,
            host: '127.0.0.1',
            port: port,
            label: 'Dart legacy SSE server',
          );
          final startedClient = await io.Process.start(
            'node',
            [
              tsLegacySseClientScript,
              '--url',
              'http://127.0.0.1:$port/sse',
            ],
          );
          clientProcess = startedClient;
          final clientStdout =
              startedClient.stdout.transform(io.systemEncoding.decoder).join();
          final clientStderr =
              startedClient.stderr.transform(io.systemEncoding.decoder).join();
          final exitCode = await startedClient.exitCode.timeout(
            const Duration(seconds: 15),
            onTimeout: () async {
              await _terminateProcess(startedClient);
              return -1;
            },
          );
          final output = '${await clientStdout}\n${await clientStderr}';

          expect(exitCode, 0, reason: output);
          expect(
            output,
            contains(
              'TypeScript legacy SSE client interop passed: Result: 42',
            ),
          );
        } finally {
          if (clientProcess != null) {
            await _terminateProcess(clientProcess);
          }
          await _terminateProcess(serverProcess);
        }
      });
    });
  });
}
