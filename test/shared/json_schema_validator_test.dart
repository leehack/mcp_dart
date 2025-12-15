import 'package:mcp_dart/src/shared/json_schema_validator.dart';
import 'package:test/test.dart';

void main() {
  const validator = BasicJsonSchemaValidator();

  group('BasicJsonSchemaValidator - Advanced Keywords', () {
    group('allOf', () {
      final schema = {
        'allOf': [
          {'type': 'string'},
          {'minLength': 3},
          {'maxLength': 5},
        ],
      };

      test('valid data', () {
        expect(validator.validate(schema, 'test'), isTrue);
      });

      test('invalid type', () {
        expect(
          () => validator.validate(schema, 123),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('invalid minLength', () {
        expect(
          () => validator.validate(schema, 'hi'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('invalid maxLength', () {
        expect(
          () => validator.validate(schema, 'testing'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('anyOf', () {
      final schema = {
        'anyOf': [
          {'type': 'string'},
          {'type': 'number', 'minimum': 10},
        ],
      };

      test('valid string', () {
        expect(validator.validate(schema, 'hello'), isTrue);
      });

      test('valid number', () {
        expect(validator.validate(schema, 15), isTrue);
      });

      test('invalid number (too small)', () {
        expect(
          () => validator.validate(schema, 5),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('invalid type (boolean)', () {
        expect(
          () => validator.validate(schema, true),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('oneOf', () {
      final schema = {
        'oneOf': [
          {'type': 'number', 'multipleOf': 5},
          {'type': 'number', 'multipleOf': 3},
        ],
      };

      test('valid multiple of 5 only', () {
        expect(validator.validate(schema, 10), isTrue);
      });

      test('valid multiple of 3 only', () {
        expect(validator.validate(schema, 9), isTrue);
      });

      test('invalid multiple of both (15)', () {
        expect(
          () => validator.validate(schema, 15),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('invalid multiple of neither', () {
        expect(
          () => validator.validate(schema, 7),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('not', () {
      final schema = {
        'not': {'type': 'string'},
      };

      test('valid non-string', () {
        expect(validator.validate(schema, 123), isTrue);
      });

      test('invalid string', () {
        expect(
          () => validator.validate(schema, 'hello'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('additionalProperties', () {
      test('disallow additional properties', () {
        final schema = {
          'type': 'object',
          'properties': {
            'foo': {'type': 'string'},
          },
          'additionalProperties': false,
        };

        expect(validator.validate(schema, {'foo': 'bar'}), isTrue);
        expect(
          () => validator.validate(schema, {'foo': 'bar', 'baz': 123}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validate additional properties schema', () {
        final schema = {
          'type': 'object',
          'properties': {
            'foo': {'type': 'string'},
          },
          'additionalProperties': {'type': 'number'},
        };

        expect(validator.validate(schema, {'foo': 'bar'}), isTrue);
        expect(
          validator.validate(schema, {'foo': 'bar', 'baz': 123}),
          isTrue,
        );
        expect(
          () => validator.validate(schema, {'foo': 'bar', 'baz': 'string'}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });
  });
}
