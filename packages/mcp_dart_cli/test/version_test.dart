import 'dart:io';

import 'package:mcp_dart_cli/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('version matches pubspec.yaml', () {
    final pubspecFile = File('pubspec.yaml');
    expect(pubspecFile.existsSync(), isTrue);

    final pubspecContent = pubspecFile.readAsStringSync();
    final yaml = loadYaml(pubspecContent) as YamlMap;
    final pubspecVersion = yaml['version'] as String;

    expect(
      packageVersion,
      pubspecVersion,
      reason:
          'lib/src/version.dart does not match pubspec.yaml. '
          'Update both values before publishing.',
    );
  });

  test('build metadata does not affect prerelease classification', () {
    expect(isPrereleaseVersion('1.2.3+build-1'), isFalse);
    expect(isPrereleaseVersion('1.2.3-dev.1+build-1'), isTrue);
    expect(
      _stableCaretConstraintAllows('^2.3.0', '2.4.0+build-1'),
      isTrue,
    );
    expect(
      _stableCaretConstraintAllows('^2.3.0', '2.4.0-dev.1'),
      isFalse,
    );
  });

  test('stable caret compatibility follows semantic version bounds', () {
    const cases = [
      (constraint: '^2.3.0', version: '2.3.0', allows: true),
      (constraint: '^2.3.0', version: '2.2.9', allows: false),
      (constraint: '^2.3.0', version: '3.0.0', allows: false),
      (constraint: '^0.3.0', version: '0.3.9', allows: true),
      (constraint: '^0.3.0', version: '0.4.0', allows: false),
      (constraint: '^0.0.3', version: '0.0.3', allows: true),
      (constraint: '^0.0.3', version: '0.0.4', allows: false),
    ];

    for (final testCase in cases) {
      expect(
        _stableCaretConstraintAllows(
          testCase.constraint,
          testCase.version,
        ),
        testCase.allows,
        reason: '${testCase.constraint} with ${testCase.version}',
      );
    }
  });

  test(
    'CLI dependency and generated SDK constraint stay aligned',
    () {
      final cliPubspec =
          loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      final dependencies = cliPubspec['dependencies'] as YamlMap;
      final sdkConstraint = dependencies['mcp_dart'] as String;

      expect(generatedSdkConstraint, sdkConstraint);
      expect(isPrereleaseVersion(packageVersion), isFalse);
      expect(defaultTemplateUrl, contains('mcp_dart_cli-v$packageVersion'));
      expect(defaultTemplateUrl, isNot(contains('/main/')));
    },
  );

  test('CLI dependency accepts the root package in a repository checkout', () {
    final rootPubspecFile = File('../../pubspec.yaml');
    if (!rootPubspecFile.existsSync()) {
      markTestSkipped('Root package is unavailable outside the repository.');
      return;
    }

    final cliPubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final dependencies = cliPubspec['dependencies'] as YamlMap;
    final rootPubspec = loadYaml(rootPubspecFile.readAsStringSync()) as YamlMap;
    final rootVersion = rootPubspec['version'] as String;
    final templatePubspec =
        loadYaml(
              File(
                '../templates/simple/__brick__/pubspec.yaml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final templateDependencies = templatePubspec['dependencies'] as YamlMap;
    final sdkConstraint = dependencies['mcp_dart'] as String;
    final templateSdkConstraint = templateDependencies['mcp_dart'] as String;

    expect(templateSdkConstraint, sdkConstraint);
    expect(
      _stableCaretConstraintAllows(sdkConstraint, rootVersion),
      isTrue,
      reason:
          'The published CLI dependency must accept the stable SDK version '
          'checked out beside it.',
    );
  });
}

bool _stableCaretConstraintAllows(String constraint, String version) {
  final lower = _parseStableVersion(
    constraint.startsWith('^') ? constraint.substring(1) : '',
  );
  final candidate = _parseStableVersion(version);
  if (lower == null || candidate == null) {
    return false;
  }

  final upper = switch (lower) {
    [final major, _, _] when major > 0 => [major + 1, 0, 0],
    [0, final minor, _] when minor > 0 => [0, minor + 1, 0],
    [0, 0, final patch] => [0, 0, patch + 1],
    _ => throw StateError('Unreachable semantic version.'),
  };

  return _compareVersions(candidate, lower) >= 0 &&
      _compareVersions(candidate, upper) < 0;
}

List<int>? _parseStableVersion(String version) {
  final match = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  ).firstMatch(version);
  if (match == null) {
    return null;
  }
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

int _compareVersions(List<int> left, List<int> right) {
  for (var index = 0; index < left.length; index++) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}
