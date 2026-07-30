import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var host = '127.0.0.1';
  var port = 8766;
  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--host':
        if (index + 1 >= args.length) {
          throw const FormatException('--host requires a value');
        }
        host = args[++index];
      case '--port':
        if (index + 1 >= args.length) {
          throw const FormatException('--port requires a value');
        }
        port = int.parse(args[++index]);
    }
  }

  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'Legacy SSE browser fixture listening on http://$host:${server.port}',
  );
  await _LegacySseFixture(server).serve();
}

class _LegacySseFixture {
  final HttpServer _server;

  HttpResponse? _sseResponse;
  String? _sessionId;
  Map<String, dynamic>? _lastRequest;
  var _connectionCount = 0;
  var _postCount = 0;
  var _redirectTargetCount = 0;
  final _redirectTargetAuthorizations = <String?>[];

  _LegacySseFixture(this._server);

  Future<void> serve() async {
    await for (final request in _server) {
      unawaited(_handleSafely(request));
    }
  }

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handle(request);
    } on Object catch (error, stackTrace) {
      stderr.writeln('Legacy SSE browser fixture request failed: $error');
      stderr.writeln(stackTrace);
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Legacy SSE fixture failure');
        await request.response.close();
      } on Object {
        // The browser may have already cancelled the streaming response.
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _addCorsHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    switch ((request.method, request.uri.path)) {
      case ('GET', '/sse'):
        await _openSse(request);
      case ('GET', '/sse-redirect'):
        await _redirect(request);
      case ('GET', '/sse-post-redirect'):
        await _openSse(request, messagePath: '/messages-redirect');
      case ('POST', '/messages'):
        await _handlePost(request);
      case ('POST', '/messages-redirect'):
        await request.drain<void>();
        await _redirect(request);
      case ('GET', '/redirect-target') || ('POST', '/redirect-target'):
        _redirectTargetCount++;
        _redirectTargetAuthorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..write('Redirect target must not be reached');
        await request.response.close();
      case ('GET', '/status'):
        await _writeStatus(request.response);
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _openSse(
    HttpRequest request, {
    String messagePath = '/messages',
  }) async {
    final response = request.response;
    final sessionId = 'browser-session-${++_connectionCount}';
    _sseResponse = response;
    _sessionId = sessionId;
    response
      ..statusCode = HttpStatus.ok
      ..bufferOutput = false;
    response.headers
      ..contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.write(
      'event: endpoint\n'
      'data: http://127.0.0.1:${_server.port}$messagePath'
      '?sessionId=$sessionId\n\n',
    );
    await response.flush();
  }

  Future<void> _redirect(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.temporaryRedirect
      ..headers.set(HttpHeaders.locationHeader, '/redirect-target');
    await request.response.close();
  }

  Future<void> _handlePost(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    final sseResponse = _sseResponse;
    if (sessionId == null || sessionId != _sessionId || sseResponse == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('SSE session not found');
      await request.response.close();
      return;
    }

    final decoded = jsonDecode(await utf8.decoder.bind(request).join());
    if (decoded is! Map<String, dynamic>) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Expected one JSON-RPC object');
      await request.response.close();
      return;
    }

    _postCount++;
    _lastRequest = decoded;
    sseResponse.write(
      'event: message\n'
      'data: ${jsonEncode({
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': {
              'receivedMethod': decoded['method'],
              'receivedParams': decoded['params'],
            },
          })}\n\n',
    );
    await sseResponse.flush();

    request.response
      ..statusCode = HttpStatus.accepted
      ..headers.contentType = ContentType.text
      ..write('Accepted');
    await request.response.close();
  }

  Future<void> _writeStatus(HttpResponse response) async {
    response.headers.contentType = ContentType.json;
    response.write(
      jsonEncode({
        'connections': _connectionCount,
        'posts': _postCount,
        'lastRequest': _lastRequest,
        'redirectTargetCount': _redirectTargetCount,
        'redirectTargetAuthorizations': _redirectTargetAuthorizations,
      }),
    );
    await response.close();
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Accept, Authorization, Content-Type, Last-Event-ID, '
            'MCP-Protocol-Version',
      )
      ..set('Access-Control-Max-Age', '600');
  }
}
