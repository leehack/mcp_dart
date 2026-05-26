import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _SseEvent {
  final String? id;
  final String data;

  const _SseEvent({this.id, required this.data});

  Map<String, dynamic> get json => jsonDecode(data) as Map<String, dynamic>;
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

void main() {
  test('OAuthBearerChallenge builds insufficient-scope challenge', () {
    final challenge = OAuthBearerChallenge.insufficientScope(
      resourceMetadata: Uri.parse(
        'https://mcp.example.com/.well-known/oauth-protected-resource/mcp',
      ),
      scope: 'tools:read',
      errorDescription: 'Need tools:read',
    ).toHeaderValue();

    expect(challenge, startsWith('Bearer '));
    expect(
      challenge,
      contains(
        'resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp"',
      ),
    );
    expect(challenge, contains('scope="tools:read"'));
    expect(challenge, contains('error="insufficient_scope"'));
    expect(challenge, contains('error_description="Need tools:read"'));
  });

  group('StreamableMcpServer', () {
    late StreamableMcpServer server;
    final port = 8081;
    final host = 'localhost';
    final baseUrl = 'http://$host:$port/mcp';

    Future<http.Response> postPingWithSession(String sessionId) {
      return http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(const JsonRpcRequest(id: 2, method: 'ping').toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'mcp-session-id': sessionId,
        },
      );
    }

    Future<http.Response> postInitializeWithHeaders({
      Map<String, String> headers = const {},
    }) {
      final mergedHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        ...headers,
      };
      return http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'Client', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
        headers: mergedHeaders,
      );
    }

    Future<http.Response> postInitialize({String? sessionId}) {
      return postInitializeWithHeaders(
        headers: {
          if (sessionId != null) 'mcp-session-id': sessionId,
        },
      );
    }

    Future<http.Response> getSseWithSession(String sessionId) async {
      final client = http.Client();
      addTearDown(client.close);
      final req = http.Request('GET', Uri.parse(baseUrl));
      req.headers['Accept'] = 'text/event-stream';
      req.headers['mcp-session-id'] = sessionId;
      final streamedRes = await client.send(req);
      return http.Response.fromStream(streamedRes);
    }

    Future<http.Response> deleteSession(String sessionId) async {
      final client = http.Client();
      addTearDown(client.close);
      final req = http.Request('DELETE', Uri.parse(baseUrl));
      req.headers['mcp-session-id'] = sessionId;
      final streamedRes = await client.send(req);
      return http.Response.fromStream(streamedRes);
    }

    setUp(() async {
      server = StreamableMcpServer(
        serverFactory: (sessionId) {
          return McpServer(
            const Implementation(name: 'TestServer', version: '1.0.0'),
          );
        },
        host: host,
        port: port,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('handle OPTIONS request (CORS)', () async {
      // http.read throws if status is not 200, and by default it sends GET.
      // We want to test OPTIONS method.

      final client = http.Client();
      try {
        final req = http.Request('OPTIONS', Uri.parse(baseUrl));
        final streamedRes = await client.send(req);
        final res = await http.Response.fromStream(streamedRes);

        expect(res.statusCode, HttpStatus.ok);
        expect(res.headers['access-control-allow-origin'], '*');
        expect(res.headers['access-control-allow-methods'], contains('POST'));
      } finally {
        client.close();
      }
    });

    test('initialize session flow', () async {
      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final client = HttpClient();
      try {
        // 1. Send initialization request
        final req = await client.postUrl(Uri.parse(baseUrl));
        req.headers.contentType = ContentType.json;
        req.headers.add('Accept', 'application/json, text/event-stream');
        req.write(jsonEncode(initRequest.toJson()));
        final res = await req.close();

        expect(res.statusCode, HttpStatus.ok);
        final sessionId = res.headers.value('mcp-session-id');
        expect(sessionId, isNotNull);
        await res.drain();
      } finally {
        client.close(force: true);
      }
    });

    test('initialize session accepts multiple Accept header values', () async {
      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse(baseUrl));
        req.headers.contentType = ContentType.json;
        req.headers.add(
          HttpHeaders.acceptHeader,
          'application/json, text/event-stream',
        );
        req.headers.add(HttpHeaders.acceptHeader, 'text/event-stream');
        req.write(jsonEncode(initRequest.toJson()));

        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(res.headers.value('mcp-session-id'), isNotNull);
        await res.drain();
      } finally {
        client.close(force: true);
      }
    });

    test('rejects POST without session ID for non-init request', () async {
      final req = const JsonRpcRequest(id: 1, method: 'ping');

      final res = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(req.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        },
      );

      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('rejects unsupported MCP-Protocol-Version header by default',
        () async {
      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final res = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(initRequest.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'MCP-Protocol-Version': '1900-01-01',
        },
      );

      expect(res.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], ErrorCode.invalidRequest.value);
    });

    test(
      'allows unsupported MCP-Protocol-Version when strict validation is disabled',
      () async {
        await server.stop();

        server = StreamableMcpServer(
          serverFactory: (sid) => McpServer(
            const Implementation(
              name: 'CompatServer',
              version: '1.0',
            ),
          ),
          host: host,
          port: port,
          strictProtocolVersionHeaderValidation: false,
        );
        await server.start();

        final initRequest = JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: const InitializeRequestParams(
            protocolVersion: latestProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ).toJson(),
        );

        final res = await http.post(
          Uri.parse(baseUrl),
          body: jsonEncode(initRequest.toJson()),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'MCP-Protocol-Version': '1900-01-01',
          },
        );

        expect(res.statusCode, HttpStatus.ok);
        expect(res.headers['mcp-session-id'], isNotNull);
      },
    );

    test('rejects batch JSON-RPC payloads with 400', () async {
      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final initRes = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(initRequest.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        },
      );
      expect(initRes.statusCode, HttpStatus.ok);

      final sessionId = initRes.headers['mcp-session-id'];
      expect(sessionId, isNotNull);

      final batchRes = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode([
          const JsonRpcRequest(id: 2, method: 'ping').toJson(),
          const JsonRpcNotification(method: 'notifications/initialized')
              .toJson(),
        ]),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'mcp-session-id': sessionId!,
        },
      );

      expect(batchRes.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(batchRes.body) as Map<String, dynamic>;
      expect(body['error']['code'], ErrorCode.invalidRequest.value);
    });

    test('accepts batch JSON-RPC payloads when rejection is disabled',
        () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) => McpServer(
          const Implementation(
            name: 'CompatServer',
            version: '1.0',
          ),
        ),
        host: host,
        port: port,
        rejectBatchJsonRpcPayloads: false,
      );
      await server.start();

      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final initRes = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(initRequest.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        },
      );
      expect(initRes.statusCode, HttpStatus.ok);

      final sessionId = initRes.headers['mcp-session-id'];
      expect(sessionId, isNotNull);

      final batchRes = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode([
          const JsonRpcNotification(method: 'test/notify-1').toJson(),
          const JsonRpcNotification(method: 'test/notify-2').toJson(),
        ]),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'mcp-session-id': sessionId!,
        },
      );

      expect(batchRes.statusCode, HttpStatus.accepted);
    });

    test('rejects empty batch payloads even when batch rejection is disabled',
        () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) => McpServer(
          const Implementation(
            name: 'CompatServer',
            version: '1.0',
          ),
        ),
        host: host,
        port: port,
        rejectBatchJsonRpcPayloads: false,
      );
      await server.start();

      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final initRes = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(initRequest.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        },
      );
      expect(initRes.statusCode, HttpStatus.ok);

      final sessionId = initRes.headers['mcp-session-id'];
      expect(sessionId, isNotNull);

      final batchRes = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode([]),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'mcp-session-id': sessionId!,
        },
      );

      expect(batchRes.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(batchRes.body) as Map<String, dynamic>;
      expect(body['error']['code'], ErrorCode.invalidRequest.value);
    });

    test('rejects GET without session ID', () async {
      final res = await http.get(Uri.parse(baseUrl));
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('returns 404 for unknown session IDs', () async {
      final postRes = await postPingWithSession('unknown-session-id');
      expect(postRes.statusCode, HttpStatus.notFound);
      expect(postRes.body, contains('Session not found'));

      final malformedPostRes = await http.post(
        Uri.parse(baseUrl),
        body: 'not json',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'mcp-session-id': 'unknown-session-id',
        },
      );
      expect(malformedPostRes.statusCode, HttpStatus.notFound);
      expect(malformedPostRes.body, contains('Session not found'));

      final initRes = await postInitialize(sessionId: 'unknown-session-id');
      expect(initRes.statusCode, HttpStatus.notFound);
      expect(initRes.body, contains('Session not found'));

      final getRes = await getSseWithSession('unknown-session-id');
      expect(getRes.statusCode, HttpStatus.notFound);
      expect(getRes.body, contains('Session not found'));

      final deleteRes = await deleteSession('unknown-session-id');
      expect(deleteRes.statusCode, HttpStatus.notFound);
      expect(deleteRes.body, contains('Session not found'));
    });

    test('returns 404 for requests after session termination', () async {
      final initRes = await postInitialize();
      expect(initRes.statusCode, HttpStatus.ok);
      final sessionId = initRes.headers['mcp-session-id'];
      expect(sessionId, isNotNull);

      final deleteRes = await deleteSession(sessionId!);
      expect(deleteRes.statusCode, HttpStatus.ok);

      final postRes = await postPingWithSession(sessionId);
      expect(postRes.statusCode, HttpStatus.notFound);
      expect(postRes.body, contains('Session not found'));

      final initAfterDelete = await postInitialize(sessionId: sessionId);
      expect(initAfterDelete.statusCode, HttpStatus.notFound);
      expect(initAfterDelete.body, contains('Session not found'));

      final getRes = await getSseWithSession(sessionId);
      expect(getRes.statusCode, HttpStatus.notFound);
      expect(getRes.body, contains('Session not found'));

      final deleteAfterDelete = await deleteSession(sessionId);
      expect(deleteAfterDelete.statusCode, HttpStatus.notFound);
      expect(deleteAfterDelete.body, contains('Session not found'));
    });

    test('E2E GET Last-Event-ID replay is stream-scoped over HTTP', () async {
      await server.stop();

      final servers = <String, McpServer>{};
      server = StreamableMcpServer(
        serverFactory: (sessionId) {
          final mcpServer = McpServer(
            const Implementation(name: 'ReplayE2EServer', version: '1.0'),
          );
          servers[sessionId] = mcpServer;
          return mcpServer;
        },
        host: host,
        port: port,
        eventStore: InMemoryEventStore(),
      );
      await server.start();

      Future<HttpClientResponse> openGetSse(
        String sessionId, {
        String? lastEventId,
      }) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final req = await client.getUrl(Uri.parse(baseUrl));
        req.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId);
        if (lastEventId != null) {
          req.headers.set('Last-Event-ID', lastEventId);
        }
        return req.close();
      }

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

      final initRes = await postInitialize();
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

      final streamFuture = openGetSse(sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sendServerNotification(mcpServer!, {'seq': 1});
      await sendServerNotification(mcpServer, {'seq': 2});
      final stream = await streamFuture.timeout(const Duration(seconds: 3));
      expect(stream.statusCode, HttpStatus.ok);
      expect(stream.headers.contentType?.mimeType, 'text/event-stream');

      final lines = StreamIterator(
        stream.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(lines.cancel);

      final first = await _readSseEvent(lines);
      final second = await _readSseEvent(lines);
      expect(first.id, isNotNull);
      expect(second.id, isNotNull);
      expect(first.json['params'], containsPair('seq', 1));
      expect(second.json['params'], containsPair('seq', 2));

      final replay = await openGetSse(sessionId, lastEventId: first.id);
      expect(replay.statusCode, HttpStatus.ok);
      expect(replay.headers.contentType?.mimeType, 'text/event-stream');
      final replayLines = StreamIterator(
        replay.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(replayLines.cancel);

      final replayed = await _readSseEvent(replayLines);
      expect(replayed.id, second.id);
      expect(replayed.json['params'], containsPair('seq', 2));

      await sendServerNotification(mcpServer, {'seq': 3});
      final replayThird = await _readSseEvent(replayLines);
      expect(replayThird.json['params'], containsPair('seq', 3));

      final deleteRes = await deleteSession(sessionId);
      expect(deleteRes.statusCode, HttpStatus.ok);
      expect(
        await lines.moveNext().timeout(const Duration(seconds: 3)),
        isFalse,
      );
      expect(
        await replayLines.moveNext().timeout(const Duration(seconds: 3)),
        isFalse,
      );
    });

    test('authentication', () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) =>
            McpServer(const Implementation(name: 'AuthServer', version: '1.0')),
        host: host,
        port: port,
        authenticator: (req) =>
            req.headers.value('Authorization') == 'Bearer secret',
      );
      await server.start();

      // 1. Fail without auth
      final resFail = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(
          const JsonRpcRequest(
            id: 1,
            method: 'initialize',
          ).toJson(),
        ),
      );
      expect(resFail.statusCode, HttpStatus.forbidden);

      // 2. Pass with auth
      final resPass = await http.post(
        Uri.parse(baseUrl),
        body: jsonEncode(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'test', version: '1.0'),
            ).toJson(),
          ).toJson(),
        ),
        headers: {
          'Authorization': 'Bearer secret',
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        },
      );
      expect(resPass.statusCode, HttpStatus.ok);
    });

    test('authentication remains forbidden without OAuth metadata', () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) => McpServer(
          const Implementation(name: 'LegacyAuthServer', version: '1.0'),
        ),
        host: host,
        port: port,
        authenticator: (req) => false,
      );
      await server.start();

      final res = await postInitialize();

      expect(res.statusCode, HttpStatus.forbidden);
      expect(res.headers, isNot(contains(HttpHeaders.wwwAuthenticateHeader)));
    });

    test('serves OAuth protected-resource metadata endpoints', () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) => McpServer(
          const Implementation(name: 'OAuthMetadataServer', version: '1.0'),
        ),
        host: host,
        port: port,
        oauthProtectedResource: OAuthProtectedResourceOptions(
          metadata: OAuthProtectedResourceMetadata(
            resource: Uri.parse(baseUrl),
            authorizationServers: [Uri.parse('https://auth.example.com')],
            scopesSupported: const ['tools:read'],
          ),
          scope: 'tools:read',
        ),
      );
      await server.start();

      final endpointMetadata = await http.get(
        Uri.parse(
          'http://$host:$port/.well-known/oauth-protected-resource/mcp',
        ),
      );
      final rootMetadata = await http.get(
        Uri.parse('http://$host:$port/.well-known/oauth-protected-resource'),
      );

      for (final response in [endpointMetadata, rootMetadata]) {
        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers[HttpHeaders.contentTypeHeader],
          contains('json'),
        );
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['resource'], baseUrl);
        expect(body['authorization_servers'], ['https://auth.example.com']);
        expect(body['bearer_methods_supported'], ['header']);
        expect(body['scopes_supported'], ['tools:read']);
      }
    });

    test('failed OAuth protected-resource auth returns bearer challenge',
        () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) => McpServer(
          const Implementation(name: 'OAuthChallengeServer', version: '1.0'),
        ),
        host: host,
        port: port,
        authenticator: (req) =>
            req.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer secret',
        oauthProtectedResource: OAuthProtectedResourceOptions(
          metadata: OAuthProtectedResourceMetadata(
            resource: Uri.parse(baseUrl),
            authorizationServers: [Uri.parse('https://auth.example.com')],
            scopesSupported: const ['tools:read'],
          ),
          scope: 'tools:read',
        ),
      );
      await server.start();

      final denied = await postInitialize();

      expect(denied.statusCode, HttpStatus.unauthorized);
      expect(denied.body, 'Unauthorized');
      final challenge = denied.headers[HttpHeaders.wwwAuthenticateHeader];
      expect(challenge, isNotNull);
      expect(challenge, startsWith('Bearer '));
      expect(
        challenge,
        contains(
          'resource_metadata="http://localhost:$port/.well-known/oauth-protected-resource/mcp"',
        ),
      );
      expect(challenge, contains('scope="tools:read"'));

      final allowed = await postInitializeWithHeaders(
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer secret',
        },
      );
      expect(allowed.statusCode, HttpStatus.ok);
    });

    test('OAuth challenge can use configured public metadata URL', () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) => McpServer(
          const Implementation(name: 'PublicOAuthServer', version: '1.0'),
        ),
        host: host,
        port: port,
        authenticator: (req) => false,
        oauthProtectedResource: OAuthProtectedResourceOptions(
          metadata: OAuthProtectedResourceMetadata(
            resource: Uri.parse('https://mcp.example.com/mcp'),
            authorizationServers: [Uri.parse('https://auth.example.com')],
            scopesSupported: const ['tools:read'],
          ),
          metadataUri: Uri.parse(
            'https://mcp.example.com/.well-known/oauth-protected-resource/mcp',
          ),
          scope: 'tools:read',
        ),
      );
      await server.start();

      final denied = await postInitialize();

      expect(denied.statusCode, HttpStatus.unauthorized);
      final challenge = denied.headers[HttpHeaders.wwwAuthenticateHeader];
      expect(
        challenge,
        contains(
          'resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp"',
        ),
      );
      expect(
        challenge,
        isNot(contains('http://localhost:$port')),
      );
    });

    test('dns rebinding protection blocks disallowed host header', () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) =>
            McpServer(const Implementation(name: 'DnsServer', version: '1.0')),
        host: host,
        port: port,
        enableDnsRebindingProtection: true,
        allowedHosts: {'localhost'},
      );
      await server.start();

      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse(baseUrl));
        req.headers.contentType = ContentType.json;
        req.headers.set(HttpHeaders.hostHeader, 'evil.example');
        req.headers.set('Accept', 'application/json, text/event-stream');
        req.write(jsonEncode(initRequest.toJson()));

        final res = await req.close();
        expect(res.statusCode, HttpStatus.forbidden);
        await res.drain();
      } finally {
        client.close(force: true);
      }
    });

    test('dns rebinding protection is enabled by default', () async {
      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse(baseUrl));
        req.headers.contentType = ContentType.json;
        req.headers.set(HttpHeaders.hostHeader, 'evil.example');
        req.headers.set('Accept', 'application/json, text/event-stream');
        req.write(jsonEncode(initRequest.toJson()));

        final res = await req.close();
        expect(res.statusCode, HttpStatus.forbidden);
        await res.drain();
      } finally {
        client.close(force: true);
      }
    });

    test('dns rebinding protection allows configured origin', () async {
      await server.stop();

      server = StreamableMcpServer(
        serverFactory: (sid) =>
            McpServer(const Implementation(name: 'DnsServer', version: '1.0')),
        host: host,
        port: port,
        enableDnsRebindingProtection: true,
        allowedHosts: {'localhost'},
        allowedOrigins: {'http://localhost:$port'},
      );
      await server.start();

      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse(baseUrl));
        req.headers.contentType = ContentType.json;
        req.headers.set('Origin', 'http://localhost:$port');
        req.headers.set('Accept', 'application/json, text/event-stream');
        req.write(jsonEncode(initRequest.toJson()));

        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        await res.drain();
      } finally {
        client.close(force: true);
      }
    });

    test('rejects PUT request with 405 Method Not Allowed', () async {
      final client = http.Client();
      try {
        final req = http.Request('PUT', Uri.parse(baseUrl));
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode({'data': 'test'});
        final streamedRes = await client.send(req);
        final res = await http.Response.fromStream(streamedRes);

        expect(res.statusCode, HttpStatus.methodNotAllowed);
      } finally {
        client.close();
      }
    });

    test('rejects PATCH request with 405 Method Not Allowed', () async {
      final client = http.Client();
      try {
        final req = http.Request('PATCH', Uri.parse(baseUrl));
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode({'data': 'test'});
        final streamedRes = await client.send(req);
        final res = await http.Response.fromStream(streamedRes);

        expect(res.statusCode, HttpStatus.methodNotAllowed);
      } finally {
        client.close();
      }
    });

    test('DELETE request requires valid session ID', () async {
      final client = http.Client();
      try {
        final req = http.Request('DELETE', Uri.parse(baseUrl));
        final streamedRes = await client.send(req);
        final res = await http.Response.fromStream(streamedRes);

        // Should fail without session ID
        expect(res.statusCode, HttpStatus.badRequest);
      } finally {
        client.close();
      }
    });

    test('DELETE request with valid session closes session', () async {
      // First, initialize a session
      final initRequest = JsonRpcRequest(
        id: 1,
        method: 'initialize',
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'Client', version: '1.0'),
        ).toJson(),
      );

      final httpClient = HttpClient();
      String? sessionId;

      try {
        // Initialize session
        final initReq = await httpClient.postUrl(Uri.parse(baseUrl));
        initReq.headers.contentType = ContentType.json;
        initReq.headers.add('Accept', 'application/json, text/event-stream');
        initReq.write(jsonEncode(initRequest.toJson()));
        final initRes = await initReq.close();
        sessionId = initRes.headers.value('mcp-session-id');
        await initRes.drain();

        expect(sessionId, isNotNull);

        // Now send DELETE with the session ID
        final deleteReq = await httpClient.deleteUrl(Uri.parse(baseUrl));
        deleteReq.headers.add('mcp-session-id', sessionId!);
        final deleteRes = await deleteReq.close();

        expect(deleteRes.statusCode, HttpStatus.ok);
        await deleteRes.drain();
      } finally {
        httpClient.close(force: true);
      }
    });

    test('rejects requests to invalid paths', () async {
      final invalidUrl = 'http://$host:$port/invalid';
      final res = await http.get(Uri.parse(invalidUrl));

      expect(res.statusCode, HttpStatus.notFound);
    });

    test('server can be stopped and restarted', () async {
      await server.stop();
      await server.start();

      // Should be able to handle OPTIONS request after restart
      final client = http.Client();
      try {
        final req = http.Request('OPTIONS', Uri.parse(baseUrl));
        final streamedRes = await client.send(req);
        final res = await http.Response.fromStream(streamedRes);

        expect(res.statusCode, HttpStatus.ok);
      } finally {
        client.close();
      }
    });

    test('server port is exposed correctly', () async {
      expect(server.port, equals(port));
    });
  });
}
