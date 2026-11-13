import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../example/parallel_search.dart' as example;

void main() {
  tearDown(() => exitCode = 0);

  for (final scenario in ['search', 'fetch', 'tool-error', 'missing-tool']) {
    final command = scenario == 'fetch' ? 'fetch' : 'search';
    test('$scenario through the anonymous HTTP client', () async {
      final methods = <String>[];
      final output = <String>[];
      final mock = MockClient((request) async {
        expect(request.url, Uri.parse('https://search.parallel.ai/mcp'));
        expect(
          request.headers['user-agent'],
          'mcp_dart-parallel-search-example/1.0.0',
        );
        expect(request.headers.containsKey('authorization'), isFalse);
        if (request.method == 'GET') {
          return http.Response('', 405);
        }
        final message = jsonDecode(request.body) as Map<String, dynamic>;
        final method = message['method'] as String;
        methods.add(method);
        Object? result;
        switch (method) {
          case 'server/discover':
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': message['id'],
                'error': {'code': -32601, 'message': 'Method not found'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          case 'initialize':
            result = {
              'protocolVersion': '2025-11-25',
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'fixture', 'version': '1.0.0'},
            };
          case 'notifications/initialized':
            return http.Response('', 202);
          case 'tools/list':
            result = {
              'tools': [
                {
                  'name': scenario == 'missing-tool'
                      ? 'other_tool'
                      : command == 'search'
                          ? 'web_search'
                          : 'web_fetch',
                  'inputSchema': {'type': 'object'},
                },
              ],
            };
          case 'tools/call':
            expect(message['params'], {
              'name': command == 'search' ? 'web_search' : 'web_fetch',
              'arguments': command == 'search'
                  ? {
                      'objective': 'Dart MCP clients',
                      'search_queries': ['Dart MCP clients'],
                    }
                  : {
                      'urls': ['https://dart.dev/overview'],
                    },
            });
            result = {
              'isError': scenario == 'tool-error',
              'content': [
                {
                  'type': 'text',
                  'text': 'https://dart.dev: Dart documentation',
                },
              ],
            };
          default:
            fail('Unexpected method $method');
        }
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': message['id'], 'result': result}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await runZoned(
        () => http.runWithClient(
          () => example.main([
            command,
            command == 'search'
                ? 'Dart MCP clients'
                : 'https://dart.dev/overview',
          ]),
          () => mock,
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => output.add(line),
        ),
      );
      expect(exitCode, scenario == 'search' || scenario == 'fetch' ? 0 : 1);
      if (scenario == 'missing-tool') {
        expect(methods, contains('tools/list'));
        expect(methods, isNot(contains('tools/call')));
      } else {
        expect(methods, containsAllInOrder(['tools/list', 'tools/call']));
        expect(output, contains('https://dart.dev: Dart documentation'));
      }
    });
  }

  for (final args in <List<String>>[
    [],
    ['unknown', 'query'],
    ['search', ' '],
    ['fetch', 'file:///tmp/page'],
    ['fetch', 'https:///'],
  ]) {
    test('invalid arguments $args fail before connecting', () async {
      await http.runWithClient(
        () => example.main(args),
        () => MockClient((request) async => fail('Unexpected network request')),
      );
      expect(exitCode, 64);
    });
  }

  test('HTTP failures exit nonzero', () async {
    await http.runWithClient(
      () => example.main(['search', 'Dart MCP clients']),
      () => MockClient((request) async => http.Response('Unavailable', 503)),
    );
    expect(exitCode, 1);
  });
}
