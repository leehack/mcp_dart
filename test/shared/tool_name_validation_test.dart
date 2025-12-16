import 'package:mcp_dart/src/shared/tool_name_validation.dart';
import 'package:test/test.dart';

void main() {
  group('validateToolName', () {
    group('valid names', () {
      test('accepts simple alphanumeric names', () {
        final result = validateToolName('myTool');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts names with underscores', () {
        final result = validateToolName('my_tool_name');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts names with dashes', () {
        final result = validateToolName('my-tool-name');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts names with dots', () {
        final result = validateToolName('my.tool.name');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts names with mixed valid characters', () {
        final result = validateToolName('my_tool-name.v1');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts single character names', () {
        final result = validateToolName('a');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts 128 character names', () {
        final name = 'a' * 128;
        final result = validateToolName(name);
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });

      test('accepts uppercase names', () {
        final result = validateToolName('MY_TOOL');
        expect(result.isValid, isTrue);
        expect(result.warnings, isEmpty);
      });
    });

    group('invalid names', () {
      test('rejects empty names', () {
        final result = validateToolName('');
        expect(result.isValid, isFalse);
        expect(result.warnings, contains('Tool name cannot be empty'));
      });

      test('rejects names exceeding 128 characters', () {
        final name = 'a' * 129;
        final result = validateToolName(name);
        expect(result.isValid, isFalse);
        expect(
          result.warnings.any((w) => w.contains('exceeds maximum length')),
          isTrue,
        );
      });

      test('rejects names with spaces', () {
        final result = validateToolName('my tool');
        expect(result.isValid, isFalse);
        expect(
          result.warnings.any((w) => w.contains('contains spaces')),
          isTrue,
        );
      });

      test('rejects names with commas', () {
        final result = validateToolName('tool,name');
        expect(result.isValid, isFalse);
        expect(
          result.warnings.any((w) => w.contains('contains commas')),
          isTrue,
        );
      });

      test('rejects names with special characters', () {
        final result = validateToolName('tool@name#test');
        expect(result.isValid, isFalse);
        expect(
          result.warnings.any((w) => w.contains('invalid characters')),
          isTrue,
        );
      });

      test('rejects names with unicode characters', () {
        final result = validateToolName('tööl_näme');
        expect(result.isValid, isFalse);
        expect(
          result.warnings.any((w) => w.contains('invalid characters')),
          isTrue,
        );
      });
    });

    group('warnings for valid but problematic names', () {
      test('warns when name starts with dash', () {
        final result = validateToolName('-mytool');
        expect(result.isValid, isTrue);
        expect(
          result.warnings.any((w) => w.contains('starts or ends with a dash')),
          isTrue,
        );
      });

      test('warns when name ends with dash', () {
        final result = validateToolName('mytool-');
        expect(result.isValid, isTrue);
        expect(
          result.warnings.any((w) => w.contains('starts or ends with a dash')),
          isTrue,
        );
      });

      test('warns when name starts with dot', () {
        final result = validateToolName('.mytool');
        expect(result.isValid, isTrue);
        expect(
          result.warnings.any((w) => w.contains('starts or ends with a dot')),
          isTrue,
        );
      });

      test('warns when name ends with dot', () {
        final result = validateToolName('mytool.');
        expect(result.isValid, isTrue);
        expect(
          result.warnings.any((w) => w.contains('starts or ends with a dot')),
          isTrue,
        );
      });
    });
  });

  group('ToolNameValidationResult', () {
    test('constructs with isValid and warnings', () {
      const result = ToolNameValidationResult(
        isValid: true,
        warnings: ['warning1', 'warning2'],
      );
      expect(result.isValid, isTrue);
      expect(result.warnings, hasLength(2));
    });

    test('can be constructed with empty warnings', () {
      const result = ToolNameValidationResult(isValid: true, warnings: []);
      expect(result.warnings, isEmpty);
    });
  });

  group('validateAndWarnToolName', () {
    test('returns true for valid names', () {
      final result = validateAndWarnToolName('validTool');
      expect(result, isTrue);
    });

    test('returns false for invalid names', () {
      final result = validateAndWarnToolName('');
      expect(result, isFalse);
    });

    test('returns true for valid names with warnings', () {
      final result = validateAndWarnToolName('-startsWithDash');
      expect(result, isTrue);
    });
  });

  group('issueToolNameWarning', () {
    test('handles empty warnings list', () {
      // Should not throw
      issueToolNameWarning('validTool', []);
    });

    test('handles non-empty warnings list', () {
      // Should not throw - warnings are logged
      issueToolNameWarning('problematic-tool-', ['Warning message']);
    });
  });
}
