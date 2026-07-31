import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('renders from a package checkout without release tooling', () {
    final root = Directory.systemTemp.createTempSync(
      'mcp_release_notes_package_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: mcp_dart
version: 2.4.0
''');
    File('${root.path}/CHANGELOG.md').writeAsStringSync('''
## 2.4.0

- See the [migration guide](https://github.com/leehack/mcp_dart/blob/main/doc/migration.md).

## 2.3.0

- Older notes.
''');
    expect(Directory('${root.path}/tool').existsSync(), isFalse);

    final output = File('${root.path}/rendered/release-notes.md');
    final result = Process.runSync(Platform.resolvedExecutable, [
      File('tool/release/prepare_release_notes.dart').absolute.path,
      '--package',
      'mcp_dart',
      '--root',
      root.path,
      '--ref',
      'v2.4.0',
      '--output',
      output.path,
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      output.readAsStringSync(),
      '- See the [migration guide]'
      '(https://github.com/leehack/mcp_dart/blob/v2.4.0/doc/migration.md).\n',
    );
  });
}
