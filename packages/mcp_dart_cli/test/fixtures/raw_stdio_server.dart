import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final notifyAfterList = args.contains('--notify-after-list');
  final notifyAfterCall = args.contains('--notify-after-call');
  final invalidOutputSchema = args.contains('--invalid-output-schema');

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) continue;
    final message = decoded.cast<String, dynamic>();
    final id = message['id'];
    final method = message['method'];

    switch (method) {
      case 'initialize':
        await _writeResponse(id, <String, dynamic>{
          'protocolVersion': '2025-11-25',
          'capabilities': <String, dynamic>{
            'tools': <String, dynamic>{},
          },
          'serverInfo': <String, dynamic>{
            'name': 'raw-stdio-fixture',
            'version': '1.0.0',
          },
        });
        break;
      case 'notifications/initialized':
        break;
      case 'ping':
        await _writeResponse(id, const <String, dynamic>{});
        break;
      case 'tools/list':
        await _writeResponse(id, <String, dynamic>{
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': invalidOutputSchema ? 'bad_structured' : 'echo',
              'description': 'Raw fixture tool.',
              'inputSchema': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'message': <String, dynamic>{'type': 'string'},
                },
              },
              if (invalidOutputSchema)
                'outputSchema': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'result': <String, dynamic>{'type': 'string'},
                  },
                  'required': <String>['result'],
                },
            },
          ],
        });
        if (notifyAfterList) await _writeLoggingNotification();
        break;
      case 'tools/call':
        await _writeResponse(id, <String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'text',
              'text': invalidOutputSchema ? 'bad' : 'ok',
            },
          ],
          if (invalidOutputSchema)
            'structuredContent': <String, dynamic>{'result': 1},
        });
        if (notifyAfterCall) await _writeLoggingNotification();
        break;
      default:
        if (id != null) {
          await _writeErrorResponse(
            id,
            -32601,
            'Method not found',
          );
        }
    }
  }
}

Future<void> _writeResponse(Object? id, Map<String, dynamic> result) async {
  stdout.writeln(
    jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    }),
  );
  await stdout.flush();
}

Future<void> _writeErrorResponse(
  Object? id,
  int code,
  String message,
) async {
  stdout.writeln(
    jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, dynamic>{
        'code': code,
        'message': message,
      },
    }),
  );
  await stdout.flush();
}

Future<void> _writeLoggingNotification() async {
  stdout.writeln(
    jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/message',
      'params': <String, dynamic>{
        'level': 'info',
        'logger': 'raw-fixture',
        'data': 'notification noise',
      },
    }),
  );
  await stdout.flush();
}
