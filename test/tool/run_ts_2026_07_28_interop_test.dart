import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/testing/bounded_response_body.dart';

void main() {
  test('retired published TypeScript gap flag fails closed', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'tool/testing/run_ts_2026_07_28_interop.dart',
        '--direction=dart-to-ts',
        '--expect-published-ts-client-gap',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains(
        '--expect-published-ts-client-gap is retired',
      ),
    );
  });

  group('readBoundedUtf8ResponseBody', () {
    test('decodes a response within the configured bounds', () async {
      final body = Stream.value(utf8.encode('{"ok":true}'));

      final decoded = await readBoundedUtf8ResponseBody(
        body,
        timeout: const Duration(seconds: 1),
        maxBytes: 32,
      );

      expect(decoded, '{"ok":true}');
    });

    test('times out and cancels a response body that never closes', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      body.add(utf8.encode('partial'));

      await expectLater(
        readBoundedUtf8ResponseBody(
          body.stream,
          timeout: const Duration(milliseconds: 20),
          maxBytes: 32,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(cancelled, isTrue);
      await body.close();
    });

    test('rejects and cancels a response body over the byte limit', () async {
      final body = Stream.fromIterable([
        utf8.encode('1234'),
        utf8.encode('5'),
      ]);

      await expectLater(
        readBoundedUtf8ResponseBody(
          body,
          timeout: const Duration(seconds: 1),
          maxBytes: 4,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('4-byte limit'),
          ),
        ),
      );
    });
  });
}
