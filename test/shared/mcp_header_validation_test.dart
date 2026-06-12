import 'package:mcp_dart/src/shared/mcp_header_validation.dart';
import 'package:test/test.dart';

void main() {
  group('isValidMcpHeaderNameSuffix', () {
    test('accepts RFC 9110 field-name token characters', () {
      expect(
        isValidMcpHeaderNameSuffix("AZaz09!#\$%&'*+-.^_`|~"),
        isTrue,
      );
    });

    test('rejects empty and separator characters', () {
      expect(isValidMcpHeaderNameSuffix(''), isFalse);

      for (final separator in [
        '"',
        '(',
        ')',
        ',',
        '/',
        ':',
        ';',
        '<',
        '=',
        '>',
        '?',
        '@',
        '[',
        r'\',
        ']',
        '{',
        '}',
      ]) {
        expect(
          isValidMcpHeaderNameSuffix('Bad${separator}Header'),
          isFalse,
          reason: 'separator $separator must be rejected',
        );
      }
    });

    test('rejects whitespace, control characters, and non-ASCII characters',
        () {
      for (final value in ['Bad Header', 'Bad\tHeader', 'Bad\nHeader', 'Bäd']) {
        expect(isValidMcpHeaderNameSuffix(value), isFalse);
      }
    });
  });
}
