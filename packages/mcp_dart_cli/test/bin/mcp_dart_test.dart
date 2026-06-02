import 'package:test/test.dart';

import '../../bin/mcp_dart.dart' as cli;

void main() {
  group('shouldCheckForUpdate', () {
    test('skips update command', () {
      expect(cli.shouldCheckForUpdate(['update']), isFalse);
    });

    test('skips serve because stdout is MCP protocol traffic', () {
      expect(cli.shouldCheckForUpdate(['serve']), isFalse);
    });

    test('skips conformance JSON mode to keep stdout machine-readable', () {
      expect(cli.shouldCheckForUpdate(['conformance', '--json']), isFalse);
    });

    test('skips any JSON mode to keep stdout machine-readable', () {
      expect(cli.shouldCheckForUpdate(['list-tools', '--json']), isFalse);
      expect(
          cli.shouldCheckForUpdate(['call-tool', 'echo', '--json']), isFalse);
    });

    test('skips inspect-client because stdout is MCP protocol traffic', () {
      expect(
        cli.shouldCheckForUpdate(['inspect-client', '--report', 'report.json']),
        isFalse,
      );
    });

    test('skips trace because stdout is MCP protocol traffic', () {
      expect(
        cli.shouldCheckForUpdate(['trace', '--report', 'trace.json']),
        isFalse,
      );
    });

    test('checks updates for normal conformance output', () {
      expect(cli.shouldCheckForUpdate(['conformance']), isTrue);
    });

    test('skips skills print to keep output reusable', () {
      expect(cli.shouldCheckForUpdate(['skills', 'print']), isFalse);
    });
  });
}
