import 'package:test/test.dart';

import '../../bin/mcp_dart.dart' as cli;

void main() {
  group('shouldCheckForUpdate', () {
    test('skips update command', () {
      expect(cli.shouldCheckForUpdate(['update']), isFalse);
    });

    test('skips conformance JSON mode to keep stdout machine-readable', () {
      expect(cli.shouldCheckForUpdate(['conformance', '--json']), isFalse);
    });

    test('checks updates for normal conformance output', () {
      expect(cli.shouldCheckForUpdate(['conformance']), isTrue);
    });
  });
}
