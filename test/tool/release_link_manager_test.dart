import 'dart:io';

import 'package:test/test.dart';

import '../../tool/release/release_link_manager.dart';

void main() {
  test('SDK release links rewrite from main to the immutable tag', () {
    final root = Directory.systemTemp.createTempSync('mcp_release_links_sdk_');
    addTearDown(() => root.deleteSync(recursive: true));
    _writeSdkPolicyFiles(root);
    _write(root, 'pubspec.yaml', '''
name: mcp_dart
version: 2.4.0-dev.1
documentation: https://github.com/leehack/mcp_dart/tree/main/doc
''');
    _write(root, 'README.md', '''
[Guide](https://github.com/leehack/mcp_dart/blob/main/doc/guide.md#start)
[Release](https://github.com/leehack/mcp_dart/releases/tag/v2.3.0)
[External](https://example.com/blob/main/doc/guide.md)
''');
    _write(
      root,
      'CHANGELOG.md',
      '[Migration](https://github.com/leehack/mcp_dart/blob/main/doc/migration.md)\n',
    );
    _write(
      root,
      'llms.txt',
      'https://github.com/leehack/mcp_dart/tree/main/example\n',
    );
    _write(
      root,
      'SECURITY.md',
      '[Policy](https://github.com/leehack/mcp_dart/blob/main/SECURITY.md)\n',
    );
    _write(
      root,
      'doc/guide.md',
      '[Example](https://github.com/leehack/mcp_dart/blob/main/example/a.dart)\n',
    );
    _write(
      root,
      'example/README.md',
      '[Docs](https://github.com/leehack/mcp_dart/tree/main/doc)\n',
    );

    final manager = ReleaseLinkManager(
      packageRoot: root,
      package: ReleasePackage.sdk,
    );
    expect(manager.check('main').issues, isEmpty);

    final first = manager.update('v2.4.0-dev.1');
    expect(first.issues, isEmpty);
    expect(
      first.changedFiles,
      containsAll([
        'CHANGELOG.md',
        'README.md',
        'SECURITY.md',
        'doc/guide.md',
        'example/README.md',
        'llms.txt',
        'pubspec.yaml',
      ]),
    );
    expect(
      File('${root.path}/README.md').readAsStringSync(),
      allOf(
        contains('/blob/v2.4.0-dev.1/doc/guide.md#start'),
        contains('/releases/tag/v2.3.0'),
        contains('https://example.com/blob/main/doc/guide.md'),
      ),
    );
    expect(
      File('${root.path}/CHANGELOG.md').readAsStringSync(),
      contains('/blob/v2.4.0-dev.1/doc/migration.md'),
    );
    expect(manager.update('v2.4.0-dev.1').changedFiles, isEmpty);
  });

  test('check reports stale source links with their file and line', () {
    final root =
        Directory.systemTemp.createTempSync('mcp_release_links_stale_');
    addTearDown(() => root.deleteSync(recursive: true));
    _writeSdkPolicyFiles(root);
    _write(root, 'pubspec.yaml', 'name: mcp_dart\nversion: 2.4.0\n');
    _write(root, 'README.md', '''
First line
[Old](https://github.com/leehack/mcp_dart/blob/v2.3.0/doc/guide.md)
''');
    _write(root, 'CHANGELOG.md', 'No links here.\n');
    _write(root, 'llms.txt', 'No links here.\n');

    final result = ReleaseLinkManager(
      packageRoot: root,
      package: ReleasePackage.sdk,
    ).check('main');

    expect(result.isValid, isFalse);
    expect(result.issues, hasLength(1));
    expect(result.issues.single.path, 'README.md');
    expect(result.issues.single.line, 2);
    expect(result.issues.single.actualRef, 'v2.3.0');
    expect(result.issues.single.expectedRef, 'main');
  });

  test('CLI releases require their package-specific tag', () {
    final root = Directory.systemTemp.createTempSync('mcp_release_links_cli_');
    addTearDown(() => root.deleteSync(recursive: true));
    _write(root, 'pubspec.yaml', '''
name: mcp_dart_cli
version: 0.3.0
homepage: https://github.com/leehack/mcp_dart/tree/main/packages/mcp_dart_cli
''');
    _write(
      root,
      'README.md',
      '[CLI](https://github.com/leehack/mcp_dart/blob/main/packages/mcp_dart_cli/README.md)\n',
    );
    _write(
      root,
      'CHANGELOG.md',
      '[CLI guide](https://github.com/leehack/mcp_dart/blob/main/packages/mcp_dart_cli/README.md)\n',
    );
    _write(root, 'CONTRIBUTING.md', 'No repository links.\n');

    final manager = ReleaseLinkManager(
      packageRoot: root,
      package: ReleasePackage.cli,
    );
    expect(
      () => manager.update('v0.3.0'),
      throwsA(isA<ArgumentError>()),
    );

    final result = manager.update('mcp_dart_cli-v0.3.0');
    expect(result.issues, isEmpty);
    expect(
      File('${root.path}/README.md').readAsStringSync(),
      contains('/blob/mcp_dart_cli-v0.3.0/packages/mcp_dart_cli/README.md'),
    );
    expect(
      File('${root.path}/pubspec.yaml').readAsStringSync(),
      contains('/tree/mcp_dart_cli-v0.3.0/packages/mcp_dart_cli'),
    );
    expect(
      File('${root.path}/CHANGELOG.md').readAsStringSync(),
      contains(
        '/blob/mcp_dart_cli-v0.3.0/packages/mcp_dart_cli/README.md',
      ),
    );
  });

  test('rewriteText pins only same-repository source links', () {
    final root = Directory.systemTemp.createTempSync('mcp_release_links_text_');
    addTearDown(() => root.deleteSync(recursive: true));
    _write(root, 'pubspec.yaml', 'name: mcp_dart\nversion: 2.4.0\n');
    final manager = ReleaseLinkManager(
      packageRoot: root,
      package: ReleasePackage.sdk,
    );
    const source = '''
[Blob](https://github.com/leehack/mcp_dart/blob/main/doc/guide.md?plain=1#start)
[Tree](https://github.com/leehack/mcp_dart/tree/main/example)
[Pinned](https://github.com/leehack/mcp_dart/blob/v2.4.0/README.md)
[Release](https://github.com/leehack/mcp_dart/releases/tag/v2.3.0)
[External](https://example.com/leehack/mcp_dart/blob/main/README.md)
''';

    final rewritten = manager.rewriteText(source, 'v2.4.0');

    expect(
      rewritten,
      contains('/blob/v2.4.0/doc/guide.md?plain=1#start'),
    );
    expect(rewritten, contains('/tree/v2.4.0/example'));
    expect(rewritten, contains('/blob/v2.4.0/README.md'));
    expect(rewritten, contains('/releases/tag/v2.3.0'));
    expect(
      rewritten,
      contains('https://example.com/leehack/mcp_dart/blob/main/README.md'),
    );
    expect(manager.rewriteText(rewritten, 'v2.4.0'), rewritten);
  });
}

void _writeSdkPolicyFiles(Directory root) {
  for (final path in const [
    'CONTRIBUTING.md',
    'DEPENDENCY_POLICY.md',
    'ROADMAP.md',
    'SECURITY.md',
    'VERSIONING.md',
  ]) {
    _write(root, path, 'No links here.\n');
  }
}

void _write(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
