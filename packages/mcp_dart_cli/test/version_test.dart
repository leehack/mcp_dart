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
      reason: 'lib/src/version.dart does not match pubspec.yaml. '
          'Run "dart tool/update_version.dart" to update.',
    );
  });
}
