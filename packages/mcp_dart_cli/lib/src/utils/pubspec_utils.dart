import 'dart:io';

import 'package:yaml/yaml.dart';

/// Reads the package name from a pubspec file.
Future<String?> readPackageNameFromPubspec(File pubspecFile) async {
  final pubspecContent = await pubspecFile.readAsString();
  final pubspecYaml = loadYaml(pubspecContent);

  if (pubspecYaml is! YamlMap) {
    return null;
  }

  final packageName = pubspecYaml['name'];
  return packageName is String ? packageName : null;
}
