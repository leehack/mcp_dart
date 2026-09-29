@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Rules from https://dart.dev/tools/pub/package-skills and
// https://agentskills.io/specification. `dart run skills@ get` silently skips
// a skill whose directory lacks the package-name prefix; the hyphenated form
// keeps names spec-valid for the underscored package name.
const String _skillPrefix = 'mcp-dart-';
const int _maxSkillLines = 500;
const int _maxNameLength = 64;
const int _maxDescriptionLength = 1024;
final RegExp _namePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _frontmatter = RegExp(r'^---\n([\s\S]*?)\n---\n');
final RegExp _dartBlock = RegExp(r'```dart\n([\s\S]*?)```');
final RegExp _frontmatterEntry = RegExp(r'^([A-Za-z][\w-]*):\s*(.*)$');
// A block starting with this marker is one file of an example package named
// `my_server`, so its package imports resolve like a consumer project.
final RegExp _fileMarker = RegExp(r'^// file: (\S+)\n');
const String _exampleProjectPubspec = '''
name: my_server
publish_to: none
environment:
  sdk: ^3.4.0
dependencies:
  mcp_dart:
    path: '{{root}}'
dev_dependencies:
  lints: ">=4.0.0 <7.0.0"
  test: ^1.24.0
''';

void main() {
  final List<Directory> skills = Directory('skills')
      .listSync()
      .whereType<Directory>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('ships at least one skill', () {
    expect(skills, isNotEmpty);
  });

  for (final Directory skill in skills) {
    final String directoryName = p.basename(skill.path);

    group(directoryName, () {
      late String markdown;

      setUpAll(() {
        markdown = _readSkill(skill);
      });

      test('uses the package-name prefix and a spec-valid name', () {
        expect(directoryName, startsWith(_skillPrefix));
        expect(directoryName, matches(_namePattern));
        expect(directoryName.length, lessThanOrEqualTo(_maxNameLength));
      });

      test('has frontmatter matching the directory', () {
        final RegExpMatch? match = _frontmatter.firstMatch(markdown);
        expect(match, isNotNull, reason: 'missing YAML frontmatter');
        final Map<String, String> metadata =
            _parseFrontmatter(match!.group(1)!);
        expect(metadata['name'], directoryName);
        final String? description = metadata['description'];
        expect(description, isNotNull);
        expect(description!, isNotEmpty);
        expect(description.length, lessThanOrEqualTo(_maxDescriptionLength));
      });

      test('stays within the line budget', () {
        expect(
          '\n'.allMatches(markdown).length,
          lessThanOrEqualTo(_maxSkillLines),
        );
      });
    });
  }

  test(
    'Dart examples analyze against the public API',
    () async {
      final Directory snippets = Directory(
        p.join('.dart_tool', 'package_skill_snippets'),
      );
      if (snippets.existsSync()) {
        snippets.deleteSync(recursive: true);
      }
      snippets.createSync(recursive: true);
      addTearDown(() => snippets.deleteSync(recursive: true));

      int count = 0;
      for (final Directory skill in skills) {
        final String markdown = _readSkill(skill);
        final String prefix = p.basename(skill.path).replaceAll('-', '_');
        final Directory project = Directory(p.join(snippets.path, prefix));
        int index = 0;
        for (final RegExpMatch block in _dartBlock.allMatches(markdown)) {
          final String code = block.group(1)!;
          final RegExpMatch? file = _fileMarker.firstMatch(code);
          (file == null
              ? File(p.join(snippets.path, '${prefix}_${index++}.dart'))
              : File(p.join(project.path, file.group(1)!)))
            ..createSync(recursive: true)
            ..writeAsStringSync(code);
          count++;
        }
        if (project.existsSync()) {
          await _preparePackage(project);
        }
      }
      expect(count, greaterThan(0));

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['analyze', snippets.path],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _preparePackage(Directory project) async {
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
    _exampleProjectPubspec.replaceFirst(
      '{{root}}',
      // Pub expects POSIX-style separators even on Windows.
      Directory.current.absolute.path.replaceAll(r'\', '/'),
    ),
  );
  File(
    p.join(project.path, 'analysis_options.yaml'),
  ).writeAsStringSync('include: package:lints/recommended.yaml\n');
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    ['pub', 'get', '--offline'],
    workingDirectory: project.path,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

// Windows checkouts may convert line endings to CRLF.
String _readSkill(Directory skill) => File(
      p.join(skill.path, 'SKILL.md'),
    ).readAsStringSync().replaceAll('\r\n', '\n');

/// Reads top-level `key: value` and folded `key: >-` scalars, which is all
/// the skill frontmatter uses, without adding a YAML dependency.
Map<String, String> _parseFrontmatter(String source) {
  final Map<String, String> values = <String, String>{};
  final List<String> lines = source.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final RegExpMatch? entry = _frontmatterEntry.firstMatch(lines[i]);
    if (entry == null) {
      continue;
    }
    String value = entry.group(2)!.trim();
    if (value == '>-' || value == '>') {
      final List<String> folded = <String>[];
      while (i + 1 < lines.length && lines[i + 1].startsWith(' ')) {
        folded.add(lines[++i].trim());
      }
      value = folded.join(' ');
    }
    values[entry.group(1)!] = value;
  }
  return values;
}
