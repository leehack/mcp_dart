import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('published TypeScript gap flag requires the TS client direction',
      () async {
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
        '--expect-published-ts-client-gap requires the ts-to-dart direction',
      ),
    );
  });
}
