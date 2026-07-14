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

  test(
    'CLI dependency and generated SDK constraint match the root package',
    () {
      final cliPubspec =
          loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      final rootPubspec =
          loadYaml(File('../../pubspec.yaml').readAsStringSync()) as YamlMap;
      final rootVersion = rootPubspec['version'] as String;
      final dependencies = cliPubspec['dependencies'] as YamlMap;
      final templatePubspec =
          loadYaml(
                File(
                  '../templates/simple/__brick__/pubspec.yaml',
                ).readAsStringSync(),
              )
              as YamlMap;
      final templateDependencies = templatePubspec['dependencies'] as YamlMap;

      expect(dependencies['mcp_dart'], '^$rootVersion');
      expect(templateDependencies['mcp_dart'], '^$rootVersion');
      expect(generatedSdkConstraint, '^$rootVersion');
      expect(isPrereleaseVersion(packageVersion), isTrue);
      expect(defaultTemplateUrl, contains('mcp_dart_cli-v$packageVersion'));
      expect(defaultTemplateUrl, isNot(contains('/main/')));
    },
  );
}
