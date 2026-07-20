import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import 'bounded_response_body.dart';

const _defaultTimeout = Duration(seconds: 20);
const _defaultMaxBodyBytes = 1024 * 1024;
const _requestId = 'dart-discovery-wire-probe';

Map<String, Object?> buildAnonymousMcp20260728DiscoveryRequest() {
  return {
    'jsonrpc': '2.0',
    'id': _requestId,
    'method': Method.serverDiscover,
    'params': {
      '_meta': {
        McpMetaKey.protocolVersion: previewProtocolVersion,
        McpMetaKey.clientCapabilities: <String, Object?>{},
      },
    },
  };
}

Future<void> assertDartMcp20260728DiscoveryWire(
  String url, {
  Duration timeout = _defaultTimeout,
  int maxBodyBytes = _defaultMaxBodyBytes,
}) async {
  final httpClient = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await httpClient.postUrl(Uri.parse(url)).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    request.headers.set('MCP-Protocol-Version', previewProtocolVersion);
    request.headers.set('Mcp-Method', Method.serverDiscover);
    request.add(
      utf8.encode(jsonEncode(buildAnonymousMcp20260728DiscoveryRequest())),
    );

    final response = await request.close().timeout(timeout);
    final body = await readBoundedUtf8ResponseBody(
      response,
      timeout: timeout,
      maxBytes: maxBodyBytes,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Dart server/discover wire probe returned HTTP '
        '${response.statusCode}: ${_bodyPreview(body)}',
      );
    }

    validateDartMcp20260728DiscoveryWireResponse(body);
  } finally {
    httpClient.close(force: true);
  }
}

void validateDartMcp20260728DiscoveryWireResponse(String body) {
  final envelope = _decodeJsonOrSse(body);
  if (envelope is! Map ||
      envelope['jsonrpc'] != '2.0' ||
      envelope['id'] != _requestId) {
    throw StateError(
      'Dart server/discover wire probe returned an invalid JSON-RPC '
      'envelope: ${_bodyPreview(body)}',
    );
  }
  if (envelope.containsKey('error')) {
    throw StateError(
      'Dart server rejected anonymous server/discover: ${envelope['error']}',
    );
  }

  final result = envelope['result'];
  if (result is! Map) {
    throw StateError(
      'Dart server/discover wire probe returned no result object: '
      '${_bodyPreview(body)}',
    );
  }
  final supportedVersions = result['supportedVersions'];
  if (supportedVersions is! List ||
      !supportedVersions.contains(previewProtocolVersion)) {
    throw StateError(
      'Dart server/discover did not advertise $previewProtocolVersion: '
      '$result',
    );
  }
  if (result.containsKey('serverInfo')) {
    throw StateError(
      'Dart server/discover emitted obsolete body serverInfo: $result',
    );
  }

  final meta = result['_meta'];
  final serverInfo = meta is Map ? meta[McpMetaKey.serverInfo] : null;
  if (serverInfo is! Map ||
      serverInfo['name'] != 'dart-test-server' ||
      serverInfo['version'] != '1.0.0') {
    throw StateError(
      'Dart server/discover omitted or malformed result metadata '
      'serverInfo: $result',
    );
  }
}

Object? _decodeJsonOrSse(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring('data:'.length).trimLeft();
      if (data.isEmpty) continue;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map && decoded['id'] == _requestId) {
          return decoded;
        }
      } on FormatException {
        continue;
      }
    }
    throw FormatException(
      'Dart server/discover wire probe returned neither JSON nor a matching '
      'JSON SSE event.',
      _bodyPreview(body),
    );
  }
}

String _bodyPreview(String body) {
  const maxCharacters = 1000;
  if (body.length <= maxCharacters) return body;
  return '${body.substring(0, maxCharacters)}...';
}
