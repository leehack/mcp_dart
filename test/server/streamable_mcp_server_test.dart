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
