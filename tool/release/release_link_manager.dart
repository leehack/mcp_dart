import 'dart:io';

enum ReleasePackage {
  sdk('mcp_dart', 'v'),
  cli('mcp_dart_cli', 'mcp_dart_cli-v');

  const ReleasePackage(this.packageName, this.tagPrefix);

  final String packageName;
  final String tagPrefix;

  static ReleasePackage parse(String value) {
    for (final package in values) {
      if (package.packageName == value) {
        return package;
      }
    }
    throw FormatException('Unknown package: $value');
  }
}

class ReleaseLinkIssue {
  const ReleaseLinkIssue({
    required this.path,
    required this.line,
    required this.actualRef,
    required this.expectedRef,
  });

  final String path;
  final int line;
  final String actualRef;
  final String expectedRef;

  @override
  String toString() =>
      '$path:$line uses repository ref $actualRef; expected $expectedRef.';
}

class ReleaseLinkUpdate {
  const ReleaseLinkUpdate({
    required this.changedFiles,
    required this.issues,
  });

  final List<String> changedFiles;
  final List<ReleaseLinkIssue> issues;

  bool get isValid => issues.isEmpty;
}

/// Keeps release-facing same-repository links aligned with a branch or tag.
class ReleaseLinkManager {
  ReleaseLinkManager({
    required this.packageRoot,
    required this.package,
  });

  static const _repositoryUrl = 'https://github.com/leehack/mcp_dart/';
  static final _repositoryLinkPattern = RegExp(
    '${RegExp.escape(_repositoryUrl)}(blob|tree)/([^/\\s)#?]+)',
  );
  static final _versionPattern = RegExp(
    r'^version:[ \t]*([^ \t\r\n]+)[ \t]*$',
    multiLine: true,
  );

  final Directory packageRoot;
  final ReleasePackage package;

  String get version {
    final pubspec = File(_path('pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw FileSystemException('Missing package pubspec.', pubspec.path);
    }
    final match = _versionPattern.firstMatch(pubspec.readAsStringSync());
    if (match == null) {
      throw FormatException('Missing package version in ${pubspec.path}.');
    }
    return match.group(1)!;
  }

  String get releaseTag => '${package.tagPrefix}$version';

  ReleaseLinkUpdate check(String expectedRef) {
    _validateExpectedRef(expectedRef);
    return ReleaseLinkUpdate(
      changedFiles: const [],
      issues: List.unmodifiable(_issues(expectedRef)),
    );
  }

  ReleaseLinkUpdate update(String expectedRef) {
    _validateExpectedRef(expectedRef);
    final changedFiles = <String>[];
    for (final file in _releaseFacingFiles()) {
      final source = file.readAsStringSync();
      final updated = source.replaceAllMapped(_repositoryLinkPattern, (match) {
        return '$_repositoryUrl${match.group(1)}/$expectedRef';
      });
      if (updated == source) {
        continue;
      }
      file.writeAsStringSync(updated);
      changedFiles.add(_relativePath(file));
    }
    return ReleaseLinkUpdate(
      changedFiles: List.unmodifiable(changedFiles),
      issues: List.unmodifiable(_issues(expectedRef)),
    );
  }

  void _validateExpectedRef(String expectedRef) {
    if (expectedRef != 'main' && expectedRef != releaseTag) {
      throw ArgumentError.value(
        expectedRef,
        'expectedRef',
        'must be main or the package release tag $releaseTag',
      );
    }
  }

  List<ReleaseLinkIssue> _issues(String expectedRef) {
    final issues = <ReleaseLinkIssue>[];
    for (final file in _releaseFacingFiles()) {
      final source = file.readAsStringSync();
      for (final match in _repositoryLinkPattern.allMatches(source)) {
        final actualRef = match.group(2)!;
        if (actualRef == expectedRef) {
          continue;
        }
        issues.add(
          ReleaseLinkIssue(
            path: _relativePath(file),
            line: '\n'.allMatches(source.substring(0, match.start)).length + 1,
            actualRef: actualRef,
            expectedRef: expectedRef,
          ),
        );
      }
    }
    return issues;
  }

  List<File> _releaseFacingFiles() {
    final relativeFiles = package == ReleasePackage.sdk
        ? <String>['README.md', 'llms.txt', 'pubspec.yaml']
        : <String>['README.md', 'CONTRIBUTING.md', 'pubspec.yaml'];
    final files = <File>[];
    for (final relativePath in relativeFiles) {
      final file = File(_path(relativePath));
      if (!file.existsSync()) {
        throw FileSystemException(
          'Missing release-facing file.',
          file.path,
        );
      }
      files.add(file);
    }
    for (final relativeDirectory in const ['doc', 'example']) {
      final directory = Directory(_path(relativeDirectory));
      if (!directory.existsSync()) {
        continue;
      }
      files.addAll(
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.md')),
      );
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  String _path(String relativePath) =>
      '${packageRoot.absolute.path}${Platform.pathSeparator}$relativePath';

  String _relativePath(File file) {
    final root = packageRoot.absolute.path;
    return file.absolute.path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
  }
}
