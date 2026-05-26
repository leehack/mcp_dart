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
  final tsOAuthClientPath =
      p.join(Directory.current.path, 'test/interop/ts/dist/oauth_client.js');
  final dartServerPath =
      p.join(Directory.current.path, 'test/interop/test_dart_server.dart');

  // Check if we should skip
  final skipTests = !File(tsClientPath).existsSync() ||
      !File(tsLifecycleClientPath).existsSync() ||
      !File(tsReplayClientPath).existsSync() ||
      !File(tsOAuthClientPath).existsSync() ||
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
      'official TS Streamable HTTP client completes OAuth PKCE flow',
      () async {
        final server = await _ProtectedMcpServer.start();
        try {
          final result = await Process.run(
            'node',
            [
              tsOAuthClientPath,
              '--url',
              server.mcpUrl,
            ],
            runInShell: true,
          );

          if (result.exitCode != 0) {
            print('TS OAuth client stdout: ${result.stdout}');
            print('TS OAuth client stderr: ${result.stderr}');
          }

          expect(
            result.exitCode,
            equals(0),
            reason: 'Official TS Streamable HTTP OAuth interop failed',
          );
          expect(server.unauthenticatedMcpRequests, greaterThanOrEqualTo(1));
          expect(server.authenticatedMcpRequests, greaterThanOrEqualTo(1));
          expect(server.resourceMetadataRequests, greaterThanOrEqualTo(1));
          expect(server.authorizationMetadataRequests, greaterThanOrEqualTo(1));
          expect(server.lastTokenForm, isNotNull);
          expect(
            server.lastTokenForm,
            containsPair('grant_type', 'authorization_code'),
          );
          expect(server.lastTokenForm, containsPair('code', 'valid-code'));
          expect(
            server.lastTokenForm,
            containsPair('client_id', 'ts-oauth-client'),
          );
          expect(
            server.lastTokenForm,
            containsPair(
              'redirect_uri',
              'http://127.0.0.1:9876/oauth/callback',
            ),
          );
          expect(server.lastTokenForm!['code_verifier'], isNotEmpty);
          expect(server.lastTokenForm, containsPair('resource', server.mcpUrl));
        } finally {
          await server.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'official TS Streamable HTTP client completes OAuth with StreamableMcpServer helper',
      () async {
        final port = await _findAvailablePort();
        final mcpUrl = 'http://127.0.0.1:$port/mcp';
        final authorizationServer =
            await _OAuthAuthorizationServer.start(expectedResource: mcpUrl);
        var unauthenticatedRequests = 0;
        var authenticatedRequests = 0;

        final streamableServer = StreamableMcpServer(
          serverFactory: (_) => createServer(),
          host: '127.0.0.1',
          port: port,
          authenticator: (request) {
            final authorized = request.headers.value(
                  HttpHeaders.authorizationHeader,
                ) ==
                'Bearer ts-access-token';
            if (authorized) {
              authenticatedRequests += 1;
            } else {
              unauthenticatedRequests += 1;
            }
            return authorized;
          },
          oauthProtectedResource: OAuthProtectedResourceOptions(
            metadata: OAuthProtectedResourceMetadata(
              resource: Uri.parse(mcpUrl),
              authorizationServers: [Uri.parse(authorizationServer.baseUrl)],
              scopesSupported: const ['tools:read'],
            ),
            scope: 'tools:read',
          ),
        );

        await streamableServer.start();
        try {
          final result = await Process.run(
            'node',
            [
              tsOAuthClientPath,
              '--url',
              mcpUrl,
            ],
            runInShell: true,
          );

          if (result.exitCode != 0) {
            print('TS OAuth helper stdout: ${result.stdout}');
            print('TS OAuth helper stderr: ${result.stderr}');
          }

          expect(
            result.exitCode,
            equals(0),
            reason: 'Official TS OAuth interop failed against helper',
          );
          expect(unauthenticatedRequests, greaterThanOrEqualTo(1));
          expect(authenticatedRequests, greaterThanOrEqualTo(1));
          expect(
            authorizationServer.authorizationMetadataRequests,
            greaterThanOrEqualTo(1),
          );
          expect(authorizationServer.lastTokenForm, isNotNull);
          expect(
            authorizationServer.lastTokenForm,
            containsPair('grant_type', 'authorization_code'),
          );
          expect(
            authorizationServer.lastTokenForm,
            containsPair('code', 'valid-code'),
          );
          expect(
            authorizationServer.lastTokenForm,
            containsPair('client_id', 'ts-oauth-client'),
          );
          expect(
            authorizationServer.lastTokenForm,
            containsPair(
              'redirect_uri',
              'http://127.0.0.1:9876/oauth/callback',
            ),
          );
          expect(
            authorizationServer.lastTokenForm!['code_verifier'],
            isNotEmpty,
          );
          expect(
            authorizationServer.lastTokenForm,
            containsPair('resource', mcpUrl),
          );
        } finally {
          await streamableServer.stop();
          await authorizationServer.stop();
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

class _ProtectedMcpServer {
  final HttpServer _httpServer;
  final Map<String, StreamableHTTPServerTransport> _transports = {};
  final Map<String, McpServer> _servers = {};
  Map<String, String>? lastTokenForm;
  int unauthenticatedMcpRequests = 0;
  int authenticatedMcpRequests = 0;
  int resourceMetadataRequests = 0;
  int authorizationMetadataRequests = 0;

  _ProtectedMcpServer._(this._httpServer);

  int get port => _httpServer.port;
  String get baseUrl => 'http://127.0.0.1:$port';
  String get mcpUrl => '$baseUrl/mcp';
  String get protectedResourceMetadataUrl =>
      '$baseUrl/.well-known/oauth-protected-resource/mcp';

  static Future<_ProtectedMcpServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _ProtectedMcpServer._(httpServer);
    httpServer.listen(server._handleRequest);
    return server;
  }

  Future<void> stop() async {
    await _httpServer.close(force: true);
    for (final transport in _transports.values) {
      await transport.close();
    }
    for (final server in _servers.values) {
      await server.close();
    }
    _transports.clear();
    _servers.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/.well-known/oauth-protected-resource' ||
          request.uri.path == '/.well-known/oauth-protected-resource/mcp') {
        await _handleProtectedResourceMetadata(request);
        return;
      }
      if (request.uri.path == '/.well-known/oauth-authorization-server') {
        await _handleAuthorizationServerMetadata(request);
        return;
      }
      if (request.uri.path == '/token') {
        await _handleTokenRequest(request);
        return;
      }
      if (request.uri.path == '/mcp') {
        await _handleMcpRequest(request);
        return;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
    } catch (error, stack) {
      print('Protected OAuth interop server error: $error\n$stack');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal Server Error');
        await request.response.close();
      } catch (_) {
        // The transport may already have started or closed the response.
      }
    }
  }

  Future<void> _handleProtectedResourceMetadata(HttpRequest request) async {
    resourceMetadataRequests += 1;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'resource': mcpUrl,
          'authorization_servers': [baseUrl],
          'bearer_methods_supported': ['header'],
          'scopes_supported': ['tools:read'],
        }),
      );
    await request.response.close();
  }

  Future<void> _handleAuthorizationServerMetadata(HttpRequest request) async {
    authorizationMetadataRequests += 1;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'issuer': baseUrl,
          'authorization_endpoint': '$baseUrl/authorize',
          'token_endpoint': '$baseUrl/token',
          'response_types_supported': ['code'],
          'grant_types_supported': ['authorization_code', 'refresh_token'],
          'code_challenge_methods_supported': ['S256'],
          'token_endpoint_auth_methods_supported': ['none'],
          'scopes_supported': ['tools:read'],
        }),
      );
    await request.response.close();
  }

  Future<void> _handleTokenRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final body = await utf8.decodeStream(request);
    lastTokenForm = Uri.splitQueryString(body);
    if (lastTokenForm!['code'] != 'valid-code' ||
        lastTokenForm!['resource'] != mcpUrl ||
        lastTokenForm!['code_verifier'] == null ||
        lastTokenForm!['code_verifier']!.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': 'invalid_request',
            'error_description': 'Invalid OAuth token request',
          }),
        );
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'access_token': 'ts-access-token',
          'refresh_token': 'ts-refresh-token',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'scope': 'tools:read',
        }),
      );
    await request.response.close();
  }

  Future<void> _handleMcpRequest(HttpRequest request) async {
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization != 'Bearer ts-access-token') {
      unauthenticatedMcpRequests += 1;
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer resource_metadata="$protectedResourceMetadataUrl", scope="tools:read"',
        )
        ..write('Unauthorized');
      await request.response.close();
      return;
    }

    authenticatedMcpRequests += 1;
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId != null) {
      final transport = _transports[sessionId];
      if (transport == null) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Session not found');
        await request.response.close();
        return;
      }
      await transport.handleRequest(request);
      return;
    }

    final mcpServer = createServer();
    late StreamableHTTPServerTransport transport;
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: generateUUID,
        onsessioninitialized: (createdSessionId) {
          _transports[createdSessionId] = transport;
          _servers[createdSessionId] = mcpServer;
        },
      ),
    );
    await mcpServer.connect(transport);
    await transport.handleRequest(request);

    final createdSessionId = transport.sessionId;
    if (createdSessionId == null) {
      await transport.close();
      await mcpServer.close();
    }
  }
}

class _OAuthAuthorizationServer {
  final HttpServer _httpServer;
  final String expectedResource;
  Map<String, String>? lastTokenForm;
  int authorizationMetadataRequests = 0;

  _OAuthAuthorizationServer._(this._httpServer, this.expectedResource);

  String get baseUrl => 'http://127.0.0.1:${_httpServer.port}';

  static Future<_OAuthAuthorizationServer> start({
    required String expectedResource,
  }) async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _OAuthAuthorizationServer._(httpServer, expectedResource);
    httpServer.listen(server._handleRequest);
    return server;
  }

  Future<void> stop() async {
    await _httpServer.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/.well-known/oauth-authorization-server') {
      await _handleAuthorizationServerMetadata(request);
      return;
    }
    if (request.uri.path == '/token') {
      await _handleTokenRequest(request);
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not Found');
    await request.response.close();
  }

  Future<void> _handleAuthorizationServerMetadata(HttpRequest request) async {
    authorizationMetadataRequests += 1;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'issuer': baseUrl,
          'authorization_endpoint': '$baseUrl/authorize',
          'token_endpoint': '$baseUrl/token',
          'response_types_supported': ['code'],
          'grant_types_supported': ['authorization_code', 'refresh_token'],
          'code_challenge_methods_supported': ['S256'],
          'token_endpoint_auth_methods_supported': ['none'],
          'scopes_supported': ['tools:read'],
        }),
      );
    await request.response.close();
  }

  Future<void> _handleTokenRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final body = await utf8.decodeStream(request);
    lastTokenForm = Uri.splitQueryString(body);
    if (lastTokenForm!['code'] != 'valid-code' ||
        lastTokenForm!['resource'] != expectedResource ||
        lastTokenForm!['code_verifier'] == null ||
        lastTokenForm!['code_verifier']!.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': 'invalid_request',
            'error_description': 'Invalid OAuth token request',
          }),
        );
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'access_token': 'ts-access-token',
          'refresh_token': 'ts-refresh-token',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'scope': 'tools:read',
        }),
      );
    await request.response.close();
  }
}
