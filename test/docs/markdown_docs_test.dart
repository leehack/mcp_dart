import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final repoFiles = _repoFiles(repoRoot).toSet();
  final repoRelativeFiles = repoFiles
      .map((file) => p.split(p.relative(file, from: repoRoot)).join('/'))
      .toSet();
  final repoRelativeFileSuffixes = _pathSuffixes(repoRelativeFiles).toSet();
  final markdownFiles = _markdownFiles(repoRoot).toList()..sort();

  group('Markdown docs', () {
    test('local links resolve to checked-in files or directories', () {
      final brokenLinks = <String>[];

      for (final file in markdownFiles) {
        final content = File(file).readAsStringSync();
        for (final match in _markdownLinkPattern.allMatches(content)) {
          final rawTarget = match.namedGroup('target')!;
          final target = _stripFragment(rawTarget);
          if (!_isLocalLink(target)) {
            continue;
          }

          final resolved = p.normalize(p.join(p.dirname(file), target));
          if (!File(resolved).existsSync() &&
              !Directory(resolved).existsSync()) {
            brokenLinks.add(
              '${p.relative(file, from: repoRoot)} -> $rawTarget',
            );
          }
        }
      }

      expect(brokenLinks, isEmpty);
    });

    test('documented dart run file targets exist', () {
      final missingTargets = <String>[];

      for (final file in markdownFiles) {
        final content = File(file).readAsStringSync();
        for (final match in _dartRunFilePattern.allMatches(content)) {
          final target = match.namedGroup('target')!;
          if (!_dartRunTargetExists(
            repoRoot,
            file,
            target,
            repoFiles,
            repoRelativeFiles,
            repoRelativeFileSuffixes,
          )) {
            missingTargets.add(
              '${p.relative(file, from: repoRoot)} -> dart run $target',
            );
          }
        }
      }

      expect(missingTargets, isEmpty);
    });
  });
}

Iterable<String> _pathSuffixes(Set<String> paths) sync* {
  for (final path in paths) {
    final parts = path.split('/');
    for (var index = 0; index < parts.length; index++) {
      yield parts.sublist(index).join('/');
    }
  }
}

final _markdownLinkPattern = RegExp(
  r'(?<!!)\[[^\]]+\]\((?<target>[^)\s]+)(?:\s+"[^"]*")?\)',
);

final _dartRunFilePattern = RegExp(
  r'dart run (?<target>(?:example|packages|test|bin)/[^\s`]+\.dart)',
);

Iterable<String> _markdownFiles(String repoRoot) sync* {
  final roots = [
    'README.md',
    'CHANGELOG.md',
    'doc',
    'example',
    p.join('packages', 'templates'),
    p.join('packages', 'mcp_dart_cli', 'README.md'),
    p.join('packages', 'mcp_dart_cli', 'CHANGELOG.md'),
    p.join('packages', 'mcp_dart_cli', 'CONTRIBUTING.md'),
    p.join('packages', 'mcp_dart_cli', 'example'),
  ];

  for (final root in roots) {
    final path = p.join(repoRoot, root);
    final file = File(path);
    if (file.existsSync() && path.endsWith('.md')) {
      yield path;
      continue;
    }

    final directory = Directory(path);
    if (!directory.existsSync()) {
      continue;
    }

    yield* _filesUnder(directory)
        .where((file) => file.path.endsWith('.md'))
        .map((file) => file.path);
  }
}

Iterable<String> _repoFiles(String repoRoot) sync* {
  yield* _filesUnder(Directory(repoRoot)).map((file) => p.normalize(file.path));
}

Iterable<File> _filesUnder(Directory directory) sync* {
  for (final entity in directory.listSync()) {
    if (entity is Directory) {
      if (_shouldSkipDirectory(entity)) {
        continue;
      }
      yield* _filesUnder(entity);
    } else if (entity is File) {
      yield entity;
    }
  }
}

bool _shouldSkipDirectory(Directory directory) {
  final name = p.basename(directory.path);
  return name.startsWith('.') ||
      const {
        'build',
        'coverage',
      }.contains(name);
}

String _stripFragment(String target) {
  final hashIndex = target.indexOf('#');
  if (hashIndex == -1) {
    return target;
  }
  return target.substring(0, hashIndex);
}

bool _isLocalLink(String target) {
  if (target.isEmpty || target.startsWith('#')) {
    return false;
  }
  final lower = target.toLowerCase();
  return !lower.startsWith('http://') &&
      !lower.startsWith('https://') &&
      !lower.startsWith('mailto:');
}

bool _dartRunTargetExists(
  String repoRoot,
  String markdownFile,
  String target,
  Set<String> repoFiles,
  Set<String> repoRelativeFiles,
  Set<String> repoRelativeFileSuffixes,
) {
  final relativeToMarkdown =
      p.normalize(p.join(p.dirname(markdownFile), target));
  if (repoFiles.contains(relativeToMarkdown)) {
    return true;
  }

  final relativeToRepoRoot = p.normalize(p.join(repoRoot, target));
  if (repoFiles.contains(relativeToRepoRoot)) {
    return true;
  }

  return repoRelativeFiles.contains(target) ||
      repoRelativeFileSuffixes.contains(target);
}
