import 'dart:io';

import 'package:test/test.dart';

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
}
