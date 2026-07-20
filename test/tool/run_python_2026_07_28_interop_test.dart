import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../../tool/testing/mcp_2026_07_28_discovery_wire_probe.dart';

void main() {
  test('published Python gap flag requires the Python client direction',
      () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'tool/testing/run_python_2026_07_28_interop.dart',
        '--direction=dart-to-python',
        '--expect-published-python-client-gap',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains(
        '--expect-published-python-client-gap requires the python-to-dart direction',
      ),
    );
    expect(result.stdout, isNot(contains('[dart-server]')));
  });

  group('Dart MCP 2026-07-28 discovery wire probe', () {
    test('builds an anonymous discovery request', () {
      final request = buildAnonymousMcp20260728DiscoveryRequest();
      final params = request['params']! as Map<String, Object?>;
      final meta = params['_meta']! as Map<String, Object?>;

      expect(request['method'], Method.serverDiscover);
      expect(meta[McpMetaKey.protocolVersion], previewProtocolVersion);
      expect(meta[McpMetaKey.clientCapabilities], isEmpty);
      expect(meta.containsKey(McpMetaKey.clientInfo), isFalse);
    });

    test('accepts canonical server identity metadata in JSON', () {
      expect(
        () => validateDartMcp20260728DiscoveryWireResponse(
          jsonEncode(_validDiscoveryResponse()),
        ),
        returnsNormally,
      );
    });

    test('accepts canonical server identity metadata in SSE', () {
      final response = jsonEncode(_validDiscoveryResponse());

      expect(
        () => validateDartMcp20260728DiscoveryWireResponse(
          'event: message\ndata: $response\n\n',
        ),
        returnsNormally,
      );
    });

    test('rejects obsolete body serverInfo', () {
      final response = _validDiscoveryResponse();
      final result = response['result']! as Map<String, Object?>;
      result['serverInfo'] = const {'name': 'legacy', 'version': '1.0.0'};

      expect(
        () => validateDartMcp20260728DiscoveryWireResponse(
          jsonEncode(response),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('obsolete body serverInfo'),
          ),
        ),
      );
    });

    test('rejects missing canonical server identity metadata', () {
      final response = _validDiscoveryResponse();
      final result = response['result']! as Map<String, Object?>;
      result['_meta'] = <String, Object?>{};

      expect(
        () => validateDartMcp20260728DiscoveryWireResponse(
          jsonEncode(response),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('omitted or malformed result metadata serverInfo'),
          ),
        ),
      );
    });

    test('rejects anonymous discovery errors', () {
      final response = _validDiscoveryResponse()
        ..remove('result')
        ..['error'] = const {'code': -32602, 'message': 'clientInfo required'};

      expect(
        () => validateDartMcp20260728DiscoveryWireResponse(
          jsonEncode(response),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('rejected anonymous server/discover'),
          ),
        ),
      );
    });
  });
}

Map<String, Object?> _validDiscoveryResponse() {
  return {
    'jsonrpc': '2.0',
    'id': 'dart-discovery-wire-probe',
    'result': {
      'supportedVersions': [previewProtocolVersion],
      '_meta': {
        McpMetaKey.serverInfo: {
          'name': 'dart-test-server',
          'version': '1.0.0',
        },
      },
    },
  };
}
