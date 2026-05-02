import 'dart:io';

import 'package:mcp_dart_cli/src/utils/pubspec_utils.dart';
import 'package:test/test.dart';

void main() {
  group('readPackageNameFromPubspec', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    Future<String?> readName(String content) {
      final pubspecFile = File('${tempDir.path}/pubspec.yaml')
        ..writeAsStringSync(content);
      return readPackageNameFromPubspec(pubspecFile);
    }

    test('reads unquoted package name', () async {
      expect(await readName('name: my_server\n'), equals('my_server'));
    });

    test('reads double quoted package name without quotes', () async {
      expect(await readName('name: "my_server"\n'), equals('my_server'));
    });

    test('reads single quoted package name without quotes', () async {
      expect(await readName("name: 'my_server'\n"), equals('my_server'));
    });

    test('returns null when name is missing', () async {
      expect(await readName('version: 1.0.0\n'), isNull);
    });
  });
}
