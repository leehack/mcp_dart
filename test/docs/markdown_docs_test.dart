import 'dart:convert';
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

    test('same-repository GitHub links map to checked-in paths', () {
      final brokenLinks = <String>[];

      for (final file in markdownFiles) {
        final content = File(file).readAsStringSync();
        for (final match in _markdownLinkPattern.allMatches(content)) {
          final rawTarget = match.namedGroup('target')!;
          final resolved = _resolveSameRepositoryGitHubTarget(
            repoRoot,
            rawTarget,
          );
          if (resolved == null) {
            continue;
          }
          final targetExists = resolved.expectsFile
              ? File(resolved.path).existsSync()
              : Directory(resolved.path).existsSync();
          if (!targetExists) {
            brokenLinks.add(
              '${p.relative(file, from: repoRoot)} -> $rawTarget',
            );
          }
        }
      }

      expect(brokenLinks, isEmpty);
    });

    test('local and same-repository heading anchors resolve', () {
      final brokenAnchors = <String>[];
      final anchorsByFile = <String, Set<String>>{};

      for (final file in markdownFiles) {
        final content = File(file).readAsStringSync();
        for (final match in _markdownLinkPattern.allMatches(content)) {
          final rawTarget = match.namedGroup('target')!;
          final fragment = Uri.tryParse(rawTarget)?.fragment ?? '';
          if (fragment.isEmpty) {
            continue;
          }

          final targetFile = _resolveAnchorTarget(repoRoot, file, rawTarget);
          if (targetFile == null || !File(targetFile).existsSync()) {
            continue;
          }

          final anchors = anchorsByFile.putIfAbsent(
            targetFile,
            () => _markdownAnchors(File(targetFile).readAsStringSync()),
          );
          final decodedFragment = Uri.decodeComponent(fragment);
          if (!anchors.contains(decodedFragment)) {
            brokenAnchors.add(
              '${p.relative(file, from: repoRoot)} -> $rawTarget',
            );
          }
        }
      }

      expect(brokenAnchors, isEmpty);
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

    test('fenced code blocks are balanced', () {
      final unbalancedFiles = <String>[];

      for (final file in markdownFiles) {
        if (!_hasBalancedCodeFences(File(file).readAsStringSync())) {
          unbalancedFiles.add(p.relative(file, from: repoRoot));
        }
      }

      expect(unbalancedFiles, isEmpty);
    });

    test('the rendered server template analyzes and passes its tests',
        () async {
      final templateRoot = Directory(
        p.join(
          repoRoot,
          'packages',
          'templates',
          'simple',
          '__brick__',
        ),
      );
      final rendered = await Directory.systemTemp.createTemp(
        'mcp_dart_template_',
      );
      addTearDown(() => rendered.delete(recursive: true));
      _renderTemplate(templateRoot, rendered);

      final pubspec = File(p.join(rendered.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        '${pubspec.readAsStringSync()}\n'
        'dependency_overrides:\n'
        '  mcp_dart:\n'
        '    path: ${jsonEncode(repoRoot)}\n',
      );

      for (final command in const <List<String>>[
        <String>['pub', 'get'],
        <String>['analyze'],
        <String>['test'],
      ]) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          command,
          workingDirectory: rendered.path,
        );
        expect(
          result.exitCode,
          0,
          reason: 'dart ${command.join(' ')} failed:\n'
              '${result.stdout}\n${result.stderr}',
        );
      }
    });
  });
}

void _renderTemplate(Directory source, Directory target) {
  for (final file in _filesUnder(source)) {
    final relative = p.relative(file.path, from: source.path);
    final output = File(p.join(target.path, relative));
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      file
          .readAsStringSync()
          .replaceAll('{{name.snakeCase()}}', 'generated_server')
          .replaceAll('{{name}}', 'generated_server'),
    );
  }
}

bool _hasBalancedCodeFences(String content) {
  String? openingCharacter;
  var openingLength = 0;
  final fencePattern = RegExp(r'^\s*(`{3,}|~{3,})', multiLine: true);

  for (final match in fencePattern.allMatches(content)) {
    final fence = match.group(1)!;
    final character = fence[0];
    if (openingCharacter == null) {
      openingCharacter = character;
      openingLength = fence.length;
    } else if (character == openingCharacter && fence.length >= openingLength) {
      openingCharacter = null;
      openingLength = 0;
    }
  }

  return openingCharacter == null;
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
  r'dart run (?<target>(?:example|packages|test|bin|tool)/[^\s`]+\.dart)',
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
    p.join('packages', 'mcp_dart_cli', 'doc'),
    p.join('packages', 'mcp_dart_cli', 'example'),
    'llms.txt',
  ];

  for (final root in roots) {
    final path = p.join(repoRoot, root);
    final file = File(path);
    if (file.existsSync() &&
        (path.endsWith('.md') || p.basename(path) == 'llms.txt')) {
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

({String path, bool expectsFile})? _resolveSameRepositoryGitHubTarget(
  String repoRoot,
  String rawTarget,
) {
  final uri = Uri.tryParse(rawTarget);
  if (uri == null || uri.host != 'github.com') {
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.length < 5 ||
      segments[0] != 'leehack' ||
      segments[1] != 'mcp_dart' ||
      (segments[2] != 'blob' && segments[2] != 'tree')) {
    return null;
  }

  return (
    path: p.normalize(p.join(repoRoot, p.joinAll(segments.sublist(4)))),
    expectsFile: segments[2] == 'blob',
  );
}

String? _resolveAnchorTarget(
  String repoRoot,
  String markdownFile,
  String rawTarget,
) {
  final sameRepoTarget =
      _resolveSameRepositoryGitHubTarget(repoRoot, rawTarget);
  if (sameRepoTarget != null) {
    return sameRepoTarget.path;
  }

  final target = _stripFragment(rawTarget);
  if (target.isEmpty) {
    return markdownFile;
  }
  if (!_isLocalLink(target)) {
    return null;
  }
  return p.normalize(p.join(p.dirname(markdownFile), target));
}

Set<String> _markdownAnchors(String content) {
  final anchors = <String>{};
  final occurrences = <String, int>{};
  final headingPattern = RegExp(r'^#{1,6}\s+(.+?)\s*#*$', multiLine: true);

  for (final match in headingPattern.allMatches(content)) {
    final heading = match.group(1)!;
    final base = _githubHeadingSlug(heading);
    if (base.isEmpty) {
      continue;
    }
    final occurrence =
        occurrences.update(base, (value) => value + 1, ifAbsent: () => 0);
    anchors.add(occurrence == 0 ? base : '$base-$occurrence');
  }

  return anchors;
}

String _githubHeadingSlug(String heading) {
  return heading
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'[`*_~]'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
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
