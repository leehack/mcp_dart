import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _RecordingHttpClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;
  int closeCount = 0;

  _RecordingHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() {
    closeCount++;
  }
}

http.StreamedResponse _response(
  Stream<List<int>> stream, {
  int statusCode = 200,
  String? contentType = 'text/event-stream; charset=utf-8',
}) =>
    http.StreamedResponse(
      stream,
      statusCode,
      headers: {
        if (contentType != null) 'content-type': contentType,
      },
    );

Stream<List<int>> _body(String value) =>
    Stream<List<int>>.value(utf8.encode(value));

Future<String> _requestBody(http.BaseRequest request) =>
    request.finalize().transform(utf8.decoder).join();

Future<void> _nextEventLoop() => Future<void>.delayed(Duration.zero);

void main() {
  group('SseClientTransport', () {
    test('emits a configurable runtime deprecation warning once', () async {
      final warnings = <String>[];
      setMcpLogHandler((loggerName, level, message) {
        if (loggerName == 'mcp_dart.client.sse' && level == LogLevel.warn) {
          warnings.add(message);
        }
      });
      addTearDown(resetMcpLogHandler);

      final first = SseClientTransport(Uri.parse('http://example.com/sse'));
      final second = SseClientTransport(Uri.parse('http://example.com/sse'));
      await first.close();
      await second.close();

      expect(warnings, hasLength(1));
      expect(warnings.single, contains('SEP-2596'));
      expect(warnings.single, contains('2026-08-18'));
      expect(warnings.single, contains('Streamable HTTP'));
    });

    test(
      'opens SSE, resolves endpoint, receives messages, and POSTs JSON-RPC',
      () async {
        final sse = StreamController<List<int>>();
        addTearDown(sse.close);
        final requests = <http.BaseRequest>[];
        final postBodies = <String>[];
        final httpClient = _RecordingHttpClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return _response(sse.stream);
          }
          postBodies.add(await _requestBody(request));
          return _response(
            _body('Accepted'),
            statusCode: 202,
            contentType: 'text/plain',
          );
        });
        final errors = <Error>[];
        final messages = <JsonRpcMessage>[];
        final transport = SseClientTransport(
          Uri.parse('http://example.com/api/sse'),
          opts: SseClientTransportOptions(
            headers: const {
              'Authorization': 'Bearer legacy-token',
              'Accept': 'application/json',
              'Content-Type': 'text/plain',
            },
            httpClient: httpClient,
          ),
        )
          ..onerror = errors.add
          ..onmessage = messages.add;
        addTearDown(transport.close);

        final started = transport.start();
        sse.add(
          utf8.encode(
            ': keepalive\r\n'
            '\r\n'
            'event: endpoint\r\n'
            'data: ../messages?sessionId=session-7\r\n'
            '\r\n',
          ),
        );
        await started;

        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.url, Uri.parse('http://example.com/api/sse'));
        expect(requests.single.headers['accept'], 'text/event-stream');
        expect(
          requests.single.headers['authorization'],
          'Bearer legacy-token',
        );
        expect(transport.sessionId, 'session-7');

        transport.protocolVersion = latestInitializationProtocolVersion;
        await transport.send(const JsonRpcPingRequest(id: 7));

        expect(requests, hasLength(2));
        final post = requests.last;
        expect(post.method, 'POST');
        expect(
          post.url,
          Uri.parse('http://example.com/messages?sessionId=session-7'),
        );
        expect(post.headers['content-type'], 'application/json');
        expect(post.headers['authorization'], 'Bearer legacy-token');
        expect(
          post.headers['mcp-protocol-version'],
          latestInitializationProtocolVersion,
        );
        expect(
          jsonDecode(postBodies.single),
          const {
            'jsonrpc': '2.0',
            'id': 7,
            'method': 'ping',
          },
        );

        sse.add(
          utf8.encode(
            'event: message\r\n'
            'data: not-json\r\n'
            '\r\n'
            'event: message\r\n'
            'data: {"jsonrpc":"2.0",\r\n',
          ),
        );
        sse.add(
          utf8.encode(
            'data: "id":7,"result":{}}\r\n'
            '\r\n'
            'event: message\r\n'
            'data: {"jsonrpc":"2.0","id":"server-1",'
            '"method":"custom/request","params":{"value":1}}\r\n'
            '\r\n',
          ),
        );
        await _nextEventLoop();

        expect(errors, hasLength(1));
        expect(errors.single, isA<SseClientError>());
        expect(messages, hasLength(2));
        expect(messages.first, isA<JsonRpcResponse>());
        expect((messages.first as JsonRpcResponse).id, 7);
        expect(messages.last, isA<JsonRpcRequest>());
        expect((messages.last as JsonRpcRequest).id, 'server-1');
        expect((messages.last as JsonRpcRequest).method, 'custom/request');
      },
    );

    test('accepts an absolute same-origin endpoint and session_id', () async {
      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      Uri? postUrl;
      final httpClient = _RecordingHttpClient((request) async {
        if (request.method == 'GET') {
          return _response(sse.stream);
        }
        postUrl = request.url;
        await request.finalize().drain<void>();
        return _response(
          const Stream.empty(),
          statusCode: 204,
          contentType: null,
        );
      });
      final transport = SseClientTransport(
        Uri.parse('https://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );
      addTearDown(transport.close);

      final started = transport.start();
      sse.add(
        utf8.encode(
          'event: endpoint\n'
          'data: https://example.com/messages?session_id=python-style\n\n',
        ),
      );
      await started;
      await transport.send(const JsonRpcPingRequest(id: 'ping-1'));

      expect(transport.sessionId, 'python-style');
      expect(
        postUrl,
        Uri.parse(
          'https://example.com/messages?session_id=python-style',
        ),
      );
    });

    test('rejects a non-endpoint first event without making a POST', () async {
      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      var postCount = 0;
      final httpClient = _RecordingHttpClient((request) async {
        if (request.method == 'POST') {
          postCount++;
        }
        return _response(sse.stream);
      });
      final errors = <Error>[];
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      )..onerror = errors.add;
      addTearDown(transport.close);

      final started = transport.start();
      sse.add(
        utf8.encode(
          'event: message\n'
          'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
        ),
      );

      await expectLater(started, throwsA(isA<SseClientError>()));
      expect(postCount, 0);
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('first SSE event'));
      await expectLater(
        transport.send(const JsonRpcPingRequest(id: 1)),
        throwsStateError,
      );
    });

    test('rejects unsafe endpoints before forwarding credentials', () async {
      for (final endpoint in [
        'https://attacker.example/messages',
        'ftp://trusted.example/messages',
        'https://trusted.example/messages#fragment',
        'https://user@trusted.example/messages',
      ]) {
        final sse = StreamController<List<int>>();
        final requests = <http.BaseRequest>[];
        final httpClient = _RecordingHttpClient((request) async {
          requests.add(request);
          return _response(sse.stream);
        });
        final transport = SseClientTransport(
          Uri.parse('https://trusted.example/sse'),
          opts: SseClientTransportOptions(
            headers: const {'Authorization': 'Bearer secret'},
            httpClient: httpClient,
          ),
        );

        final started = transport.start();
        sse.add(
          utf8.encode(
            'event: endpoint\n'
            'data: $endpoint\n\n',
          ),
        );

        await expectLater(
          started,
          throwsA(isA<SseClientError>()),
          reason: endpoint,
        );
        expect(requests, hasLength(1), reason: endpoint);
        expect(requests.single.url.host, 'trusted.example', reason: endpoint);
        await transport.close();
        await sse.close();
      }
    });

    test('rejects non-200 and non-SSE connection responses', () async {
      for (final testCase in [
        (
          response: _response(
            _body('Forbidden'),
            statusCode: 403,
            contentType: 'text/plain',
          ),
          expected: 'HTTP 403',
        ),
        (
          response: _response(
            _body('{}'),
            contentType: 'application/json',
          ),
          expected: 'text/event-stream',
        ),
      ]) {
        final errors = <Error>[];
        final httpClient = _RecordingHttpClient(
          (_) async => testCase.response,
        );
        final transport = SseClientTransport(
          Uri.parse('http://example.com/sse'),
          opts: SseClientTransportOptions(httpClient: httpClient),
        )..onerror = errors.add;

        await expectLater(
          transport.start(),
          throwsA(
            isA<SseClientError>().having(
              (error) => error.toString(),
              'message',
              contains(testCase.expected),
            ),
          ),
        );
        expect(errors, hasLength(1));
        await transport.close();
      }
    });

    test('surfaces and reports non-success POST responses', () async {
      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      final httpClient = _RecordingHttpClient((request) async {
        if (request.method == 'GET') {
          return _response(sse.stream);
        }
        await request.finalize().drain<void>();
        return _response(
          _body('session expired'),
          statusCode: 401,
          contentType: 'text/plain',
        );
      });
      final errors = <Error>[];
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      )..onerror = errors.add;
      addTearDown(transport.close);

      final started = transport.start();
      sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
      await started;

      await expectLater(
        transport.send(const JsonRpcPingRequest(id: 1)),
        throwsA(
          isA<SseClientError>()
              .having((error) => error.code, 'code', 401)
              .having(
                (error) => error.responseBody,
                'response body',
                'session expired',
              ),
        ),
      );
      expect(errors, hasLength(1));
    });

    test('enforces lifecycle and closes exactly once', () async {
      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      final httpClient = _RecordingHttpClient(
        (_) async => _response(sse.stream),
      );
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );
      var closes = 0;
      transport.onclose = () => closes++;

      await expectLater(
        transport.send(const JsonRpcPingRequest(id: 1)),
        throwsStateError,
      );
      final started = transport.start();
      final startExpectation =
          expectLater(started, throwsA(isA<SseClientError>()));
      await expectLater(transport.start(), throwsStateError);
      await transport.close();
      await transport.close();
      await startExpectation;
      await expectLater(
        transport.send(const JsonRpcPingRequest(id: 1)),
        throwsStateError,
      );

      expect(closes, 1);
      expect(httpClient.closeCount, 0);
    });

    test('unexpected SSE termination reports an error and closes once',
        () async {
      final sse = StreamController<List<int>>();
      final httpClient = _RecordingHttpClient(
        (_) async => _response(sse.stream),
      );
      final errors = <Error>[];
      final closed = Completer<void>();
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      )
        ..onerror = errors.add
        ..onclose = closed.complete;

      final started = transport.start();
      sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
      await started;
      await sse.close();
      await closed.future;
      await transport.close();

      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('closed unexpectedly'));
      await expectLater(
        transport.send(const JsonRpcPingRequest(id: 1)),
        throwsStateError,
      );
    });

    test(
      'drives a real legacy McpClient and SseServerManager tool flow',
      () async {
        final mcpServer = McpServer(
          const Implementation(name: 'legacy-test-server', version: '1.0.0'),
          options: const McpServerOptions(
            protocol: McpProtocol.legacy,
            capabilities: ServerCapabilities(),
          ),
        );
        mcpServer.registerTool(
          'add',
          description: 'Add two integers',
          inputSchema: JsonSchema.object(
            properties: {
              'a': JsonSchema.integer(),
              'b': JsonSchema.integer(),
            },
            required: ['a', 'b'],
          ),
          callback: (arguments, extra) async => CallToolResult.fromContent(
            [
              TextContent(
                text: '${arguments['a'] + arguments['b']}',
              ),
            ],
          ),
        );
        final manager = SseServerManager(mcpServer);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final serverSubscription = server.listen((request) {
          unawaited(manager.handleRequest(request));
        });
        final client = McpClient(
          const Implementation(name: 'legacy-test-client', version: '1.0.0'),
          options: const McpClientOptions(protocol: McpProtocol.legacy),
        );
        addTearDown(() async {
          await client.close();
          await mcpServer.close();
          await serverSubscription.cancel();
          await server.close(force: true);
        });
        final transport = SseClientTransport(
          Uri.parse('http://127.0.0.1:${server.port}/sse'),
        );

        await client.connect(transport);
        final tools = await client.listTools();
        final result = await client.callTool(
          const CallToolRequest(
            name: 'add',
            arguments: {'a': 5, 'b': 10},
          ),
        );

        expect(
          client.getProtocolVersion(),
          latestInitializationProtocolVersion,
        );
        expect(tools.tools.map((tool) => tool.name), contains('add'));
        expect(result.content, hasLength(1));
        expect((result.content.single as TextContent).text, '15');
        expect(transport.sessionId, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  group('SseClientTransport URL validation', () {
    test('requires a credential-free absolute HTTP(S) URL', () {
      for (final url in [
        Uri.parse('/sse'),
        Uri.parse('file:///tmp/sse'),
        Uri.parse('https://user:secret@example.com/sse'),
        Uri.parse('https://example.com/sse#fragment'),
      ]) {
        expect(
          () => SseClientTransport(url),
          throwsArgumentError,
          reason: '$url should be rejected',
        );
      }
    });
  });
}
