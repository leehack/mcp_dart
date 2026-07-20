import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final anonymous = args.contains('--anonymous');
  final Map<String, dynamic>? resultMeta =
      anonymous
          ? null
          : <String, dynamic>{
            'io.modelcontextprotocol/serverInfo': <String, dynamic>{
              'name': 'stateless-inventory-fixture',
              'version': '1.0.0',
            },
          };
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) continue;
    final message = decoded.cast<String, dynamic>();
    final id = message['id'];
    final method = message['method'];

    switch (method) {
      case 'server/discover':
        await _writeResult(id, <String, dynamic>{
          'resultType': 'complete',
          'ttlMs': 0,
          'cacheScope': 'private',
          'supportedVersions': <String>['2026-07-28'],
          'capabilities': <String, dynamic>{
            'tools': <String, dynamic>{},
            'logging': <String, dynamic>{},
          },
          if (resultMeta != null) '_meta': resultMeta,
        });
        break;
      case 'tools/list':
        await _writeResult(id, <String, dynamic>{
          'resultType': 'complete',
          'ttlMs': 0,
          'cacheScope': 'private',
          'tools': <Map<String, dynamic>>[],
          if (resultMeta != null) '_meta': resultMeta,
        });
        break;
      case 'ping':
      case 'logging/setLevel':
      case 'tools/call':
      case 'resources/read':
      case 'prompts/get':
      case 'completion/complete':
        await _writeError(id, 'Unexpected active probe: $method');
        break;
      default:
        if (id != null) {
          await _writeError(id, 'Method not found: $method');
        }
    }
  }
}

Future<void> _writeResult(Object? id, Map<String, dynamic> result) async {
  stdout.writeln(
    jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    }),
  );
  await stdout.flush();
}

Future<void> _writeError(Object? id, String message) async {
  stdout.writeln(
    jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, dynamic>{
        'code': -32601,
        'message': message,
      },
    }),
  );
  await stdout.flush();
}
