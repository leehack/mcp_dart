@Tags(['interop'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'test_dart_server.dart';

class _SseEvent {
  final String? id;
  final String data;

  const _SseEvent({this.id, required this.data});

  Map<String, dynamic> get json => jsonDecode(data) as Map<String, dynamic>;
}

class _SseConnection {
  final HttpClient client;
  final HttpClientResponse response;

  const _SseConnection(this.client, this.response);

  void close() => client.close(force: true);
}

class _PostSseResult {
  final int statusCode;
  final _SseEvent event;

  const _PostSseResult({required this.statusCode, required this.event});
}

Future<int> _findAvailablePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_SseEvent> _readSseEvent(StreamIterator<String> lines) async {
  String? id;
  final dataLines = <String>[];

  while (await lines.moveNext().timeout(const Duration(seconds: 3))) {
    final line = lines.current;
    if (line.isEmpty) {
      if (id != null || dataLines.isNotEmpty) {
        return _SseEvent(id: id, data: dataLines.join('\n'));
      }
      continue;
    }

    if (line.startsWith(':')) {
      continue;
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex < 0) {
      continue;
    }

    final field = line.substring(0, colonIndex);
    final valueStart = colonIndex +
        1 +
        (line.length > colonIndex + 1 && line[colonIndex + 1] == ' ' ? 1 : 0);
    final value = line.substring(valueStart);

    switch (field) {
      case 'id':
        id = value;
        break;
      case 'data':
        dataLines.add(value);
        break;
    }
  }

  throw StateError('SSE stream ended before an event was received');
}

Future<_SseConnection> _openGetSse(
  String baseUrl,
  String sessionId, {
  String? lastEventId,
}) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(baseUrl));
  req.headers
    ..set(HttpHeaders.acceptHeader, 'text/event-stream')
    ..set('mcp-session-id', sessionId);
  if (lastEventId != null) {
    req.headers.set('Last-Event-ID', lastEventId);
  }
  final response = await req.close();
  return _SseConnection(client, response);
}

Future<_PostSseResult> _postJsonForSseEvent(
  String baseUrl,
  String sessionId,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(baseUrl));
    req.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('mcp-session-id', sessionId);
    req.write(jsonEncode(body));

    final response = await req.close();
    final lines = StreamIterator(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      final event = await _readSseEvent(lines);
      return _PostSseResult(statusCode: response.statusCode, event: event);
    } finally {
      await lines.cancel();
    }
  } finally {
    client.close(force: true);
  }
}

void main() {
  // Use compiled JS client for reliability (avoids npx tsx issues in CI)
  final tsClientPath =
      p.join(Directory.current.path, 'test/interop/ts/dist/client.js');
  final tsLifecycleClientPath = p.join(
    Directory.current.path,
    'test/interop/ts/dist/lifecycle_client.js',
  );
  final tsReplayClientPath =
      p.join(Directory.current.path, 'test/interop/ts/dist/replay_client.js');
  final dartServerPath =
      p.join(Directory.current.path, 'test/interop/test_dart_server.dart');

  // Check if we should skip
  final skipTests = !File(tsClientPath).existsSync() ||
      !File(tsLifecycleClientPath).existsSync() ||
      !File(tsReplayClientPath).existsSync() ||
      !File(dartServerPath).existsSync();
  final isCi = Platform.environment['CI'] == 'true';

  group('TS Client with Dart Server', () {
    if (skipTests) {
      final reason =
          'TS client interop tests require compiled fixtures at $tsClientPath and $dartServerPath';
      if (isCi) {
        test('TS fixtures are available in CI', () {
          fail(reason);
        });
      } else {
        print('Skipping TS Client Interop tests: $reason');
      }
      return;
    }

    test('Stdio Transport', () async {
      final result = await Process.run(
        'node',
        [
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

    test('official TS stdio client lists tools immediately after lifecycle',
        () async {
      final result = await Process.run(
        'node',
        [
          tsLifecycleClientPath,
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
        print('TS lifecycle stdio stdout: ${result.stdout}');
        print('TS lifecycle stdio stderr: ${result.stderr}');
      }

      expect(
        result.exitCode,
        equals(0),
        reason: 'Official TS stdio client lifecycle interop failed',
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
              'Origin, X-Requested-With, Content-Type, Accept, mcp-session-id, Last-Event-ID, Authorization, MCP-Protocol-Version',
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
              'node',
              [
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

    test(
      'official TS Streamable HTTP client lists tools immediately after lifecycle',
      () async {
        final port = await _findAvailablePort();
        final baseUrl = 'http://127.0.0.1:$port/mcp';
        final streamableServer = StreamableMcpServer(
          serverFactory: (_) => createServer(),
          host: '127.0.0.1',
          port: port,
        );

        await streamableServer.start();
        try {
          final result = await Process.run(
            'node',
            [
              tsLifecycleClientPath,
              '--transport',
              'http',
              '--url',
              baseUrl,
            ],
            runInShell: true,
          );

          if (result.exitCode != 0) {
            print('TS lifecycle HTTP stdout: ${result.stdout}');
            print('TS lifecycle HTTP stderr: ${result.stderr}');
          }

          expect(
            result.exitCode,
            equals(0),
            reason:
                'Official TS Streamable HTTP client lifecycle interop failed',
          );
        } finally {
          await streamableServer.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'Dart Streamable HTTP server rejects operations before initialized',
      () async {
        final port = await _findAvailablePort();
        final baseUrl = 'http://127.0.0.1:$port/mcp';
        final streamableServer = StreamableMcpServer(
          serverFactory: (_) => createServer(),
          host: '127.0.0.1',
          port: port,
        );

        await streamableServer.start();
        try {
          final initRes = await http.post(
            Uri.parse(baseUrl),
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'initialize',
              'params': {
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object>{},
                'clientInfo': {'name': 'lifecycle-test', 'version': '1.0'},
              },
            }),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
            },
          );
          expect(initRes.statusCode, HttpStatus.ok);
          final sessionId = initRes.headers['mcp-session-id'];
          expect(sessionId, isNotNull);

          final earlyList = await _postJsonForSseEvent(
            baseUrl,
            sessionId!,
            {
              'jsonrpc': '2.0',
              'id': 2,
              'method': 'tools/list',
            },
          );
          expect(earlyList.statusCode, HttpStatus.ok);
          expect(earlyList.event.json['id'], 2);
          expect(earlyList.event.json['error'], isA<Map<String, dynamic>>());
          final earlyError =
              earlyList.event.json['error'] as Map<String, dynamic>;
          expect(earlyError['code'], ErrorCode.invalidRequest.value);
          expect(
            earlyError['message'],
            contains('notifications/initialized'),
          );

          final initializedRes = await http.post(
            Uri.parse(baseUrl),
            body: jsonEncode(
              const JsonRpcNotification(
                method: 'notifications/initialized',
              ).toJson(),
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
              'mcp-session-id': sessionId,
            },
          );
          expect(initializedRes.statusCode, HttpStatus.accepted);

          final initializedList = await _postJsonForSseEvent(
            baseUrl,
            sessionId,
            {
              'jsonrpc': '2.0',
              'id': 3,
              'method': 'tools/list',
            },
          );
          expect(initializedList.statusCode, HttpStatus.ok);
          expect(initializedList.event.json['id'], 3);
          final result =
              initializedList.event.json['result'] as Map<String, dynamic>;
          final tools = result['tools'] as List<dynamic>;
          final toolNames = tools
              .cast<Map<String, dynamic>>()
              .map((tool) => tool['name'])
              .toList();
          expect(toolNames, containsAll(['echo', 'add']));
        } finally {
          await streamableServer.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'official TS client resumes Dart server SSE replay by Last-Event-ID',
      () async {
        final port = await _findAvailablePort();
        final baseUrl = 'http://127.0.0.1:$port/mcp';
        final servers = <String, McpServer>{};

        final streamableServer = StreamableMcpServer(
          serverFactory: (sessionId) {
            final mcpServer = McpServer(
              const Implementation(name: 'DartReplayInterop', version: '1.0'),
            );
            servers[sessionId] = mcpServer;
            return mcpServer;
          },
          host: '127.0.0.1',
          port: port,
          eventStore: InMemoryEventStore(),
        );

        Future<void> sendServerNotification(
          McpServer mcpServer,
          Map<String, Object> params,
        ) async {
          await mcpServer.server.notification(
            JsonRpcNotification(
              method: 'notifications/custom',
              params: params,
            ),
          );
        }

        await streamableServer.start();
        try {
          final initRes = await http.post(
            Uri.parse(baseUrl),
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'initialize',
              'params': {
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object>{},
                'clientInfo': {'name': 'dart-interop-test', 'version': '1.0'},
              },
            }),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
            },
          );
          expect(initRes.statusCode, HttpStatus.ok);
          final sessionId = initRes.headers['mcp-session-id'];
          expect(sessionId, isNotNull);

          final initializedRes = await http.post(
            Uri.parse(baseUrl),
            body: jsonEncode(
              const JsonRpcNotification(
                method: 'notifications/initialized',
              ).toJson(),
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
              'mcp-session-id': sessionId!,
            },
          );
          expect(initializedRes.statusCode, HttpStatus.accepted);

          final mcpServer = servers[sessionId];
          expect(mcpServer, isNotNull);

          final streamFuture = _openGetSse(baseUrl, sessionId);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await sendServerNotification(mcpServer!, {'seq': 1});
          await sendServerNotification(mcpServer, {'seq': 2});
          final stream = await streamFuture.timeout(const Duration(seconds: 3));

          final lines = StreamIterator(
            stream.response
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          );

          final first = await _readSseEvent(lines);
          final second = await _readSseEvent(lines);

          expect(first.json['params'], containsPair('seq', 1));
          expect(second.json['params'], containsPair('seq', 2));
          expect(first.id, isNotNull);
          expect(second.id, isNotNull);

          final result = await Process.run(
            'node',
            [
              tsReplayClientPath,
              '--url',
              baseUrl,
              '--session-id',
              sessionId,
              '--last-event-id',
              first.id!,
              '--expect-seq',
              '2',
              '--expect-token',
              second.id!,
            ],
            runInShell: true,
          );

          if (result.exitCode != 0) {
            print('TS replay client stdout: ${result.stdout}');
            print('TS replay client stderr: ${result.stderr}');
          }
          expect(
            result.exitCode,
            equals(0),
            reason: 'Official TS StreamableHTTPClientTransport replay failed',
          );

          await lines.cancel();
          stream.close();
        } finally {
          await streamableServer.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
