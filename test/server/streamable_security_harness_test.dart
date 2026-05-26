import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Streamable HTTP security harness', () {
    test('safe local development scenario checks origin before auth', () async {
      final harness = await _SecurityHarness.start(
        allowedHosts: {'localhost', '127.0.0.1'},
        allowedOrigins: {'http://localhost:{port}'},
        bearerToken: 'local-secret',
      );
      addTearDown(harness.stop);

      final badOrigin = await harness.postInitialize(
        hostHeader: 'localhost:${harness.port}',
        origin: 'http://evil.example',
        bearerToken: 'local-secret',
      );

      expect(badOrigin.statusCode, HttpStatus.forbidden);
      expect(badOrigin.body, contains('DNS rebinding protection'));
      expect(harness.authenticatorCalls, 0);

      final missingAuth = await harness.postInitialize(
        hostHeader: 'localhost:${harness.port}',
        origin: 'http://localhost:${harness.port}',
      );

      expect(missingAuth.statusCode, HttpStatus.forbidden);
      expect(missingAuth.body, 'Forbidden');
      expect(harness.authenticatorCalls, 1);

      final allowed = await harness.postInitialize(
        hostHeader: 'localhost:${harness.port}',
        origin: 'http://localhost:${harness.port}',
        bearerToken: 'local-secret',
      );

      expect(allowed.statusCode, HttpStatus.ok);
      expect(allowed.header('mcp-session-id'), isNotNull);
      expect(harness.authenticatorCalls, 2);
    });

    test('production scenario requires public host and trusted origin',
        () async {
      final harness = await _SecurityHarness.start(
        allowedHosts: {'mcp.example.com'},
        allowedOrigins: {'https://app.example.com'},
        bearerToken: 'prod-secret',
      );
      addTearDown(harness.stop);

      final loopbackHost = await harness.postInitialize(
        hostHeader: 'localhost:${harness.port}',
        origin: 'https://app.example.com',
        bearerToken: 'prod-secret',
      );

      expect(loopbackHost.statusCode, HttpStatus.forbidden);
      expect(loopbackHost.body, contains('DNS rebinding protection'));
      expect(harness.authenticatorCalls, 0);

      final badOrigin = await harness.postInitialize(
        hostHeader: 'mcp.example.com',
        origin: 'https://evil.example',
        bearerToken: 'prod-secret',
      );

      expect(badOrigin.statusCode, HttpStatus.forbidden);
      expect(badOrigin.body, contains('DNS rebinding protection'));
      expect(harness.authenticatorCalls, 0);

      final allowed = await harness.postInitialize(
        hostHeader: 'mcp.example.com',
        origin: 'https://app.example.com',
        bearerToken: 'prod-secret',
      );

      expect(allowed.statusCode, HttpStatus.ok);
      expect(allowed.header('mcp-session-id'), isNotNull);
      expect(harness.authenticatorCalls, 1);
    });

    test('compatibility toggles do not disable Host and Origin checks',
        () async {
      final harness = await _SecurityHarness.start(
        allowedHosts: {'mcp.example.com'},
        allowedOrigins: {'https://app.example.com'},
        strictProtocolVersionHeaderValidation: false,
        rejectBatchJsonRpcPayloads: false,
      );
      addTearDown(harness.stop);

      final badHostBatch = await harness.postJson(
        <Map<String, dynamic>>[
          const JsonRpcNotification(method: 'notifications/initialized')
              .toJson(),
        ],
        hostHeader: 'evil.example',
        origin: 'https://app.example.com',
        protocolVersionHeader: '1900-01-01',
      );

      expect(badHostBatch.statusCode, HttpStatus.forbidden);
      expect(badHostBatch.body, contains('DNS rebinding protection'));

      final allowedLegacyVersion = await harness.postInitialize(
        hostHeader: 'mcp.example.com',
        origin: 'https://app.example.com',
        protocolVersionHeader: '1900-01-01',
      );

      expect(allowedLegacyVersion.statusCode, HttpStatus.ok);
      expect(allowedLegacyVersion.header('mcp-session-id'), isNotNull);
    });
  });
}

class _SecurityHarness {
  final StreamableMcpServer _server;
  final int port;
  int authenticatorCalls = 0;

  _SecurityHarness._({
    required StreamableMcpServer server,
    required this.port,
  }) : _server = server;

  Uri get uri => Uri.parse('http://localhost:$port/mcp');

  static Future<_SecurityHarness> start({
    required Set<String> allowedHosts,
    required Set<String> allowedOrigins,
    String? bearerToken,
    bool strictProtocolVersionHeaderValidation = true,
    bool rejectBatchJsonRpcPayloads = true,
  }) async {
    const maxAttempts = 5;
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      final port = await _reservePort();
      late _SecurityHarness harness;
      final server = StreamableMcpServer(
        serverFactory: (sessionId) => McpServer(
          const Implementation(name: 'SecurityHarnessServer', version: '1.0.0'),
        ),
        host: 'localhost',
        port: port,
        enableDnsRebindingProtection: true,
        allowedHosts: _resolvePortPlaceholders(allowedHosts, port),
        allowedOrigins: _resolvePortPlaceholders(allowedOrigins, port),
        strictProtocolVersionHeaderValidation:
            strictProtocolVersionHeaderValidation,
        rejectBatchJsonRpcPayloads: rejectBatchJsonRpcPayloads,
        authenticator: bearerToken == null
            ? null
            : (request) {
                harness.authenticatorCalls += 1;
                return request.headers.value(HttpHeaders.authorizationHeader) ==
                    'Bearer $bearerToken';
              },
      );
      harness = _SecurityHarness._(
        server: server,
        port: port,
      );
      try {
        await server.start();
        return harness;
      } on SocketException {
        await server.stop();
        if (attempt == maxAttempts - 1) {
          rethrow;
        }
      }
    }

    throw StateError('unreachable');
  }

  Future<void> stop() async {
    await _server.stop();
  }

  Future<_HttpResult> postInitialize({
    required String hostHeader,
    required String origin,
    String? bearerToken,
    String? protocolVersionHeader,
  }) {
    return postJson(
      JsonRpcRequest(
        id: 1,
        method: Method.initialize,
        params: const InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(
            name: 'SecurityHarnessClient',
            version: '1.0.0',
          ),
        ).toJson(),
      ).toJson(),
      hostHeader: hostHeader,
      origin: origin,
      bearerToken: bearerToken,
      protocolVersionHeader: protocolVersionHeader,
    );
  }

  Future<_HttpResult> postJson(
    Object body, {
    required String hostHeader,
    required String origin,
    String? bearerToken,
    String? protocolVersionHeader,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set(HttpHeaders.hostHeader, hostHeader)
        ..set('Origin', origin);
      if (bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      if (protocolVersionHeader != null) {
        request.headers.set('MCP-Protocol-Version', protocolVersionHeader);
      }
      request.write(jsonEncode(body));

      final response = await request.close();
      final headers = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values;
      });
      final responseBody = await utf8.decodeStream(response);
      return _HttpResult(
        statusCode: response.statusCode,
        headers: headers,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _HttpResult {
  final int statusCode;
  final Map<String, List<String>> headers;
  final String body;

  const _HttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Set<String> _resolvePortPlaceholders(Set<String> values, int port) {
  return values.map((value) => value.replaceAll('{port}', '$port')).toSet();
}
