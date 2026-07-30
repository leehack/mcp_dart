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
          ..protocolVersion = latestInitializationProtocolVersion
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
        expect(requests.single.followRedirects, isFalse);
        expect(requests.single.url, Uri.parse('http://example.com/api/sse'));
        expect(requests.single.headers['accept'], 'text/event-stream');
        expect(
          requests.single.headers['authorization'],
          'Bearer legacy-token',
        );
        expect(
          requests.single.headers['mcp-protocol-version'],
          latestInitializationProtocolVersion,
        );
        expect(transport.sessionId, 'session-7');

        await transport.send(const JsonRpcPingRequest(id: 7));

        expect(requests, hasLength(2));
        final post = requests.last;
        expect(post.method, 'POST');
        expect(post.followRedirects, isFalse);
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

    test('disables redirects for opening GET and message POST', () async {
      final openingRequests = <http.BaseRequest>[];
      final openingClient = _RecordingHttpClient((request) async {
        openingRequests.add(request);
        return _response(
          _body('redirected'),
          statusCode: HttpStatus.temporaryRedirect,
          contentType: 'text/plain',
        );
      });
      final openingTransport = SseClientTransport(
        Uri.parse('https://trusted.example/sse'),
        opts: SseClientTransportOptions(
          headers: const {'Authorization': 'Bearer opening-secret'},
          httpClient: openingClient,
        ),
      );
      await expectLater(
        openingTransport.start(),
        throwsA(
          isA<SseClientError>().having(
            (error) => error.code,
            'code',
            HttpStatus.temporaryRedirect,
          ),
        ),
      );
      await openingTransport.close();
      expect(openingRequests, hasLength(1));
      expect(openingRequests.single.method, 'GET');
      expect(openingRequests.single.followRedirects, isFalse);

      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      final messageRequests = <http.BaseRequest>[];
      final messageClient = _RecordingHttpClient((request) async {
        messageRequests.add(request);
        if (request.method == 'GET') {
          return _response(sse.stream);
        }
        await request.finalize().drain<void>();
        return _response(
          _body('redirected'),
          statusCode: HttpStatus.temporaryRedirect,
          contentType: 'text/plain',
        );
      });
      final messageTransport = SseClientTransport(
        Uri.parse('https://trusted.example/sse'),
        opts: SseClientTransportOptions(
          headers: const {'Authorization': 'Bearer message-secret'},
          httpClient: messageClient,
        ),
      );
      final started = messageTransport.start();
      sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
      await started;
      await expectLater(
        messageTransport.send(const JsonRpcPingRequest(id: 1)),
        throwsA(
          isA<SseClientError>().having(
            (error) => error.code,
            'code',
            HttpStatus.temporaryRedirect,
          ),
        ),
      );
      await messageTransport.close();

      expect(messageRequests, hasLength(2));
      expect(messageRequests.last.method, 'POST');
      expect(messageRequests.last.followRedirects, isFalse);
    });

    test('keeps the first endpoint when later endpoint events arrive',
        () async {
      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      final postUrls = <Uri>[];
      final errors = <Error>[];
      final httpClient = _RecordingHttpClient((request) async {
        if (request.method == 'GET') {
          return _response(sse.stream);
        }
        postUrls.add(request.url);
        await request.finalize().drain<void>();
        return _response(
          const Stream.empty(),
          statusCode: HttpStatus.noContent,
          contentType: null,
        );
      });
      final transport = SseClientTransport(
        Uri.parse('https://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      )..onerror = errors.add;
      addTearDown(transport.close);

      final started = transport.start();
      sse.add(
        utf8.encode(
          'event: endpoint\n'
          'data: /messages/first?sessionId=first\n\n',
        ),
      );
      await started;
      sse.add(
        utf8.encode(
          'event: endpoint\n'
          'data: /messages/second?sessionId=second\n\n',
        ),
      );
      await _nextEventLoop();
      await transport.send(const JsonRpcPingRequest(id: 1));

      expect(transport.sessionId, 'first');
      expect(
        postUrls,
        [Uri.parse('https://example.com/messages/first?sessionId=first')],
      );
      expect(errors, isEmpty);
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

    test('cancels a non-SSE response without waiting for its body', () async {
      final responseCancelled = Completer<void>();
      final responseBody = StreamController<List<int>>(
        onCancel: responseCancelled.complete,
      );
      addTearDown(responseBody.close);
      final httpClient = _RecordingHttpClient(
        (_) async => _response(
          responseBody.stream,
          contentType: 'application/json',
        ),
      );
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.start().timeout(const Duration(seconds: 1)),
        throwsA(
          isA<SseClientError>().having(
            (error) => error.toString(),
            'message',
            contains('text/event-stream'),
          ),
        ),
      );
      await responseCancelled.future.timeout(const Duration(seconds: 1));
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

    test('bounds failure bodies and cancels unused success bodies', () async {
      final sse = StreamController<List<int>>();
      final successBodyCancelled = Completer<void>();
      final successBody = StreamController<List<int>>(
        onCancel: successBodyCancelled.complete,
      );
      addTearDown(() async {
        await successBody.close();
        await sse.close();
      });
      var postCount = 0;
      final httpClient = _RecordingHttpClient((request) async {
        if (request.method == 'GET') {
          return _response(sse.stream);
        }
        await request.finalize().drain<void>();
        postCount++;
        if (postCount == 1) {
          return _response(
            _body('x' * (70 * 1024)),
            statusCode: HttpStatus.internalServerError,
            contentType: 'text/plain',
          );
        }
        return _response(
          successBody.stream,
          statusCode: HttpStatus.accepted,
          contentType: 'text/plain',
        );
      });
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );
      addTearDown(transport.close);

      final started = transport.start();
      sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
      await started;

      SseClientError? boundedError;
      try {
        await transport.send(const JsonRpcPingRequest(id: 1));
      } on SseClientError catch (error) {
        boundedError = error;
      }
      expect(boundedError, isNotNull);
      expect(boundedError!.responseBody, hasLength(64 * 1024 + 26));
      expect(
        boundedError.responseBody,
        endsWith('\n[response body truncated]'),
      );

      await transport.send(const JsonRpcPingRequest(id: 2)).timeout(
            const Duration(seconds: 1),
          );
      await successBodyCancelled.future.timeout(const Duration(seconds: 1));
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

    test('preserves POST errors when onerror throws', () async {
      final sse = StreamController<List<int>>();
      addTearDown(sse.close);
      final httpClient = _RecordingHttpClient((request) async {
        if (request.method == 'GET') {
          return _response(sse.stream);
        }
        await request.finalize().drain<void>();
        return _response(
          _body('rejected'),
          statusCode: HttpStatus.badRequest,
          contentType: 'text/plain',
        );
      });
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      )..onerror = (_) => throw StateError('onerror failed');
      addTearDown(transport.close);

      final started = transport.start();
      sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
      await started;

      await expectLater(
        transport.send(const JsonRpcPingRequest(id: 1)),
        throwsA(
          isA<SseClientError>()
              .having(
                (error) => error.code,
                'code',
                HttpStatus.badRequest,
              )
              .having(
                (error) => error.responseBody,
                'response body',
                'rejected',
              ),
        ),
      );
    });

    test(
      'shares remote close cleanup and contains throwing close callbacks',
      () async {
        final cancelStarted = Completer<void>();
        final allowCancellation = Completer<void>();
        final sse = StreamController<List<int>>(
          onCancel: () {
            cancelStarted.complete();
            return allowCancellation.future;
          },
        );
        addTearDown(() async {
          if (!allowCancellation.isCompleted) {
            allowCancellation.complete();
          }
          await sse.close();
        });
        final httpClient = _RecordingHttpClient(
          (_) async => _response(sse.stream),
        );
        final errorSeen = Completer<void>();
        var closeCalls = 0;
        final transport = SseClientTransport(
          Uri.parse('http://example.com/sse'),
          opts: SseClientTransportOptions(httpClient: httpClient),
        )
          ..onerror = (_) {
            errorSeen.complete();
            throw StateError('onerror failed');
          }
          ..onclose = () {
            closeCalls++;
            throw StateError('onclose failed');
          };

        final started = transport.start();
        sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
        await started;

        sse.addError(StateError('remote stream failed'), StackTrace.current);
        await errorSeen.future.timeout(const Duration(seconds: 1));
        await cancelStarted.future.timeout(const Duration(seconds: 1));

        final firstClose = transport.close();
        final secondClose = transport.close();
        expect(identical(firstClose, secondClose), isTrue);
        var closeSettled = false;
        unawaited(firstClose.then((_) => closeSettled = true));
        await _nextEventLoop();
        expect(closeSettled, isFalse);

        allowCancellation.complete();
        await firstClose;
        await secondClose;

        expect(closeSettled, isTrue);
        expect(closeCalls, 1);
        await expectLater(
          transport.send(const JsonRpcPingRequest(id: 1)),
          throwsStateError,
        );
      },
    );

    test('finalizes close when stream cancellation fails', () async {
      final sse = StreamController<List<int>>(
        onCancel: () async {
          throw StateError('stream cancellation failed');
        },
      );
      addTearDown(sse.close);
      final httpClient = _RecordingHttpClient(
        (_) async => _response(sse.stream),
      );
      var closeCalls = 0;
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      )..onclose = () => closeCalls++;

      final started = transport.start();
      sse.add(
        utf8.encode(
          'event: endpoint\n'
          'data: /messages?sessionId=cleanup-test\n\n',
        ),
      );
      await started;
      expect(transport.sessionId, 'cleanup-test');

      await expectLater(transport.close(), throwsStateError);

      expect(closeCalls, 1);
      expect(transport.sessionId, isNull);
      await expectLater(transport.start(), throwsStateError);
    });

    test('late opening response cannot resurrect a closed transport', () async {
      final responseReady = Completer<http.StreamedResponse>();
      final responseCancelled = Completer<void>();
      final responseBody = StreamController<List<int>>(
        onCancel: responseCancelled.complete,
      );
      addTearDown(responseBody.close);
      final httpClient = _RecordingHttpClient((_) => responseReady.future);
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );

      final started = transport.start();
      await transport.close();
      responseReady.complete(_response(responseBody.stream));

      await expectLater(started, throwsA(isA<SseClientError>()));
      await responseCancelled.future.timeout(const Duration(seconds: 1));
      await expectLater(transport.start(), throwsStateError);
    });

    test('close wins an endpoint-completion race', () async {
      final listening = Completer<void>();
      final sse = StreamController<List<int>>(
        sync: true,
        onListen: listening.complete,
      );
      addTearDown(sse.close);
      final httpClient = _RecordingHttpClient(
        (_) async => _response(sse.stream),
      );
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );

      final started = transport.start();
      await listening.future;
      sse.add(utf8.encode('event: endpoint\ndata: /messages\n\n'));
      final closing = transport.close();

      await expectLater(started, throwsA(isA<SseClientError>()));
      await closing;
      await expectLater(transport.start(), throwsStateError);
    });

    test('close wins a failed-start cleanup race', () async {
      final listening = Completer<void>();
      final cancelStarted = Completer<void>();
      final allowCancellation = Completer<void>();
      final sse = StreamController<List<int>>(
        sync: true,
        onListen: listening.complete,
        onCancel: () {
          cancelStarted.complete();
          return allowCancellation.future;
        },
      );
      addTearDown(() async {
        if (!allowCancellation.isCompleted) {
          allowCancellation.complete();
        }
        await sse.close();
      });
      final httpClient = _RecordingHttpClient(
        (_) async => _response(sse.stream),
      );
      final transport = SseClientTransport(
        Uri.parse('http://example.com/sse'),
        opts: SseClientTransportOptions(httpClient: httpClient),
      );

      final started = transport.start();
      await listening.future;
      sse.add(
        utf8.encode(
          'event: message\n'
          'data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
        ),
      );
      await cancelStarted.future.timeout(const Duration(seconds: 1));

      final closing = transport.close();
      var closeSettled = false;
      unawaited(closing.then((_) => closeSettled = true));
      await _nextEventLoop();
      expect(closeSettled, isFalse);

      allowCancellation.complete();
      await expectLater(started, throwsA(isA<SseClientError>()));
      await closing;

      expect(closeSettled, isTrue);
      await expectLater(transport.start(), throwsStateError);
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
