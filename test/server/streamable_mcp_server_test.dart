import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('StreamableMcpServer', () {
    late StreamableMcpServer server;
    final port = 8081;
    final host = 'localhost';
    final baseUrl = 'http://$host:$port/mcp';

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

    test('rejects GET without session ID', () async {
      final res = await http.get(Uri.parse(baseUrl));
      expect(res.statusCode, HttpStatus.badRequest);
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
  });
}
