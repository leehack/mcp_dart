import 'dart:async';
import 'dart:io';

import 'package:fetch_server/safe_fetcher.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('SafeFetcher URL policy', () {
    test('rejects non-HTTP URLs and embedded credentials', () async {
      final fetcher = _fetcher((_) async => http.Response('unused', 200));

      await expectLater(
        fetcher.fetch(Uri.parse('file:///etc/passwd')),
        throwsA(_safeFetchError(contains('Only http and https'))),
      );
      await expectLater(
        fetcher.fetch(Uri.parse('https://user:secret@example.test/')),
        throwsA(_safeFetchError(contains('credentials'))),
      );
    });

    for (final address in <String>[
      '0.0.0.0',
      '10.0.0.1',
      '127.0.0.1',
      '169.254.169.254',
      '172.16.0.1',
      '192.168.0.1',
      '224.0.0.1',
      '::',
      '::1',
      'fe80::1',
      'fec0::1',
      'fd00::1',
      'ff02::1',
      '::ffff:127.0.0.1',
      '64:ff9b::7f00:1',
      '2001::1',
      '2001:2::1',
      '2001:10::1',
      '2001:20::1',
      '2001:db8::1',
      '2002:7f00:1::',
      '3fff::1',
    ]) {
      test('rejects the non-public literal $address', () async {
        var requestSent = false;
        final fetcher = _fetcher((_) async {
          requestSent = true;
          return http.Response('unused', 200);
        });
        final uri = Uri(
          scheme: 'http',
          host: address,
          path: '/',
        );

        await expectLater(
          fetcher.fetch(uri),
          throwsA(_safeFetchError(contains('Blocked non-public'))),
        );
        expect(requestSent, isFalse);
      });
    }

    test('rejects a host if any DNS answer is non-public', () async {
      var requestSent = false;
      final fetcher = SafeFetcher(
        testClient: MockClient((_) async {
          requestSent = true;
          return http.Response('unused', 200);
        }),
        resolver: (_) async => [
          InternetAddress('93.184.216.34'),
          InternetAddress('127.0.0.1'),
        ],
      );

      await expectLater(
        fetcher.fetch(Uri.parse('https://mixed.example.test/')),
        throwsA(_safeFetchError(contains('Blocked non-public'))),
      );
      expect(requestSent, isFalse);
    });
  });

  group('SafeFetcher redirects', () {
    test('revalidates a redirect before sending the next request', () async {
      final requests = <Uri>[];
      final fetcher = SafeFetcher(
        testClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            '',
            302,
            headers: {'location': 'http://internal.example.test/admin'},
          );
        }),
        resolver: (host) async => [
          InternetAddress(
            host == 'internal.example.test' ? '127.0.0.1' : '93.184.216.34',
          ),
        ],
      );

      await expectLater(
        fetcher.fetch(Uri.parse('https://public.example.test/start')),
        throwsA(_safeFetchError(contains('Blocked non-public'))),
      );
      expect(requests, [Uri.parse('https://public.example.test/start')]);
    });

    test('re-resolves the same host for every redirect hop', () async {
      var resolutionCount = 0;
      final requests = <Uri>[];
      final fetcher = SafeFetcher(
        testClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response('', 302, headers: {'location': '/next'});
        }),
        resolver: (_) async {
          resolutionCount++;
          return [
            InternetAddress(
              resolutionCount == 1 ? '93.184.216.34' : '127.0.0.1',
            ),
          ];
        },
      );

      await expectLater(
        fetcher.fetch(Uri.parse('https://public.example.test/start')),
        throwsA(_safeFetchError(contains('Blocked non-public'))),
      );
      expect(resolutionCount, 2);
      expect(requests, hasLength(1));
    });

    test('follows a validated redirect with automatic redirects disabled',
        () async {
      final requests = <http.Request>[];
      final fetcher = SafeFetcher(
        testClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/start') {
            return http.Response(
              '',
              301,
              headers: {'location': 'https://next.example.test/final'},
            );
          }
          return http.Response('safe response', 200);
        }),
        resolver: (_) async => [InternetAddress('93.184.216.34')],
      );

      final response = await fetcher.fetch(
        Uri.parse('https://public.example.test/start'),
      );

      expect(response.body, 'safe response');
      expect(response.uri, Uri.parse('https://next.example.test/final'));
      expect(requests, hasLength(2));
      expect(requests.every((request) => !request.followRedirects), isTrue);
    });
  });

  group('SafeFetcher bounds', () {
    test('rejects a streamed body above the byte limit', () async {
      final fetcher = SafeFetcher(
        testClient: MockClient.streaming((request, requestBody) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4, 5],
            ]),
            200,
          );
        }),
        resolver: (_) async => [InternetAddress('93.184.216.34')],
        maxResponseBytes: 4,
      );

      await expectLater(
        fetcher.fetch(Uri.parse('https://public.example.test/')),
        throwsA(_safeFetchError(contains('4-byte limit'))),
      );
    });

    test('applies one timeout budget to the request', () async {
      final neverCompletes = Completer<http.Response>();
      final fetcher = SafeFetcher(
        testClient: MockClient((_) => neverCompletes.future),
        resolver: (_) async => [InternetAddress('93.184.216.34')],
        requestTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        fetcher.fetch(Uri.parse('https://public.example.test/')),
        throwsA(_safeFetchError(contains('timed out'))),
      );
    });
  });
}

SafeFetcher _fetcher(
  Future<http.Response> Function(http.Request request) handler,
) {
  return SafeFetcher(
    testClient: MockClient(handler),
    resolver: (_) async => [InternetAddress('93.184.216.34')],
  );
}

Matcher _safeFetchError(Matcher message) {
  return isA<SafeFetchException>().having(
    (error) => error.message,
    'message',
    message,
  );
}
