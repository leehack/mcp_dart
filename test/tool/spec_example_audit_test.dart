import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('spec_example_audit', () {
    late Directory examplesDir;

    setUp(() {
      examplesDir = Directory.systemTemp.createTempSync(
        'mcp_spec_example_audit_test_',
      );
    });

    tearDown(() {
      if (examplesDir.existsSync()) {
        examplesDir.deleteSync(recursive: true);
      }
    });

    test('accepts representative upstream example shapes', () async {
      _writeExample(
        examplesDir,
        'Tool',
        'tool-with-array-output-schema.json',
        {
          'name': 'get_tags',
          'description': 'Returns tags',
          'inputSchema': {
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          'outputSchema': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      );
      _writeExample(
        examplesDir,
        'CallToolResultResponse',
        'call-tool-result-response.json',
        {
          'jsonrpc': '2.0',
          'id': 'call-tool-example',
          'result': {
            'resultType': 'complete',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          },
        },
      );
      _writeExample(
        examplesDir,
        'MissingRequiredClientCapabilityError',
        'missing-elicitation-capability.json',
        {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {
            'code': -32021,
            'message':
                'Server requires the elicitation capability for this request',
            'data': {
              'requiredCapabilities': {
                'elicitation': <String, dynamic>{},
              },
            },
          },
        },
      );
      _writeExample(
        examplesDir,
        'HeaderMismatchError',
        'header-mismatch.json',
        {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {
            'code': -32020,
            'message':
                "Header mismatch: Mcp-Name header value 'foo' does not match body value 'bar'",
          },
        },
      );
      _writeExample(
        examplesDir,
        'ListRootsRequest',
        'list-roots-request.json',
        {
          'id': 'list-roots-example',
          'method': 'roots/list',
        },
      );
      _writeExample(
        examplesDir,
        'InputRequests',
        'elicitation-and-sampling-input-requests.json',
        {
          'github_login': {
            'method': 'elicitation/create',
            'params': {
              'mode': 'form',
              'message': 'Please provide your GitHub username',
              'requestedSchema': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                },
                'required': ['name'],
              },
            },
          },
          'capital_of_france': {
            'method': 'sampling/createMessage',
            'params': {
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    'type': 'text',
                    'text': 'What is the capital of France?',
                  },
                },
              ],
              'maxTokens': 100,
            },
          },
        },
      );
      _writeExample(
        examplesDir,
        'SubscriptionsListenResult',
        'listen-closed.json',
        {
          'resultType': 'complete',
          '_meta': {
            'io.modelcontextprotocol/subscriptionId': 'listen-1',
          },
        },
      );

      final result = await _runAudit(examplesDir);

      expect(result.exitCode, 0, reason: _processOutput(result));
      expect(result.stdout, contains('examples=7 parsed=7 missing=0'));
    });

    test('fails when an upstream example group has no parser mapping',
        () async {
      _writeExample(
        examplesDir,
        'FutureSpecThing',
        'future.json',
        {'example': true},
      );

      final result = await _runAudit(examplesDir);

      expect(result.exitCode, 1);
      expect(result.stdout, contains('missing parser groups:'));
      expect(result.stdout, contains('FutureSpecThing: 1'));
    });

    test('fails when a known example no longer matches the typed parser',
        () async {
      _writeExample(
        examplesDir,
        'CallToolResult',
        'missing-content.json',
        {'resultType': 'complete'},
      );

      final result = await _runAudit(examplesDir);

      expect(result.exitCode, 1);
      expect(result.stdout, contains('failures:'));
      expect(result.stdout, contains('CallToolResult/missing-content.json'));
      expect(result.stdout, contains('CallToolResult.content is required'));
    });
  });
}

Future<ProcessResult> _runAudit(Directory examplesDir) {
  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/spec_example_audit.dart', examplesDir.path],
    workingDirectory: Directory.current.path,
  );
}

void _writeExample(
  Directory root,
  String group,
  String name,
  Map<String, dynamic> json,
) {
  final directory = Directory(p.join(root.path, group))..createSync();
  File(p.join(directory.path, name)).writeAsStringSync(jsonEncode(json));
}

String _processOutput(ProcessResult result) {
  return 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}';
}
