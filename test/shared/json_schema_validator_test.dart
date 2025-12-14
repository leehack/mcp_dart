import 'package:test/test.dart';
import 'package:mcp_dart/src/shared/json_schema_validator.dart';

void main() {
  group('BasicJsonSchemaValidator', () {
    const validator = BasicJsonSchemaValidator();

    test('validates types', () {
      expect(validator.validate({'type': 'string'}, 'hello'), isTrue);
      expect(validator.validate({'type': 'number'}, 123), isTrue);
      expect(validator.validate({'type': 'number'}, 12.3), isTrue);
      expect(validator.validate({'type': 'integer'}, 123), isTrue);
      expect(validator.validate({'type': 'boolean'}, true), isTrue);
      expect(validator.validate({'type': 'null'}, null), isTrue);

      expect(
        () => validator.validate({'type': 'string'}, 123),
        throwsA(isA<JsonSchemaValidationException>()),
      );
      expect(
        () => validator.validate({'type': 'integer'}, 12.3),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates numeric constraints', () {
      // multipleOf
      expect(
        validator.validate({'type': 'number', 'multipleOf': 0.5}, 1.0),
        isTrue,
      );
      expect(
        validator.validate({'type': 'number', 'multipleOf': 0.5}, 0.5),
        isTrue,
      );
      expect(
        () => validator.validate({'type': 'number', 'multipleOf': 0.5}, 0.6),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      // maximum / exclusiveMaximum
      expect(validator.validate({'type': 'number', 'maximum': 10}, 10), isTrue);
      expect(validator.validate({'type': 'number', 'maximum': 10}, 9), isTrue);
      expect(
        () => validator.validate({'type': 'number', 'maximum': 10}, 11),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      expect(
        validator.validate({'type': 'number', 'exclusiveMaximum': 10}, 9),
        isTrue,
      );
      expect(
        () =>
            validator.validate({'type': 'number', 'exclusiveMaximum': 10}, 10),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      // minimum / exclusiveMinimum
      expect(validator.validate({'type': 'number', 'minimum': 5}, 5), isTrue);
      expect(validator.validate({'type': 'number', 'minimum': 5}, 6), isTrue);
      expect(
        () => validator.validate({'type': 'number', 'minimum': 5}, 4),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      expect(
        validator.validate({'type': 'number', 'exclusiveMinimum': 5}, 6),
        isTrue,
      );
      expect(
        () => validator.validate({'type': 'number', 'exclusiveMinimum': 5}, 5),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates string constraints', () {
      // length
      expect(
        validator.validate({'type': 'string', 'maxLength': 3}, 'abc'),
        isTrue,
      );
      expect(
        () => validator.validate({'type': 'string', 'maxLength': 3}, 'abcd'),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      expect(
        validator.validate({'type': 'string', 'minLength': 2}, 'ab'),
        isTrue,
      );
      expect(
        () => validator.validate({'type': 'string', 'minLength': 2}, 'a'),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      // pattern
      expect(
        validator.validate({'type': 'string', 'pattern': '^a.*z\$'}, 'az'),
        isTrue,
      );
      expect(
        validator.validate({'type': 'string', 'pattern': '^a.*z\$'}, 'abcz'),
        isTrue,
      );
      expect(
        () =>
            validator.validate({'type': 'string', 'pattern': '^a.*z\$'}, 'ab'),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates array constraints', () {
      // maxItems / minItems
      expect(
        validator.validate({'type': 'array', 'maxItems': 2}, [1, 2]),
        isTrue,
      );
      expect(
        () => validator.validate({'type': 'array', 'maxItems': 2}, [1, 2, 3]),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      expect(validator.validate({'type': 'array', 'minItems': 1}, [1]), isTrue);
      expect(
        () => validator.validate({'type': 'array', 'minItems': 1}, []),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      // uniqueItems
      expect(
        validator.validate({'type': 'array', 'uniqueItems': true}, [1, 2, 3]),
        isTrue,
      );
      expect(
        validator.validate({
          'type': 'array',
          'uniqueItems': true,
        }, [
          {'a': 1},
          {'a': 2},
        ]),
        isTrue,
      );
      expect(
        () =>
            validator.validate({'type': 'array', 'uniqueItems': true}, [1, 1]),
        throwsA(isA<JsonSchemaValidationException>()),
      );
      expect(
        () => validator.validate({
          'type': 'array',
          'uniqueItems': true,
        }, [
          {'a': 1},
          {'a': 1},
        ]),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates object constraints', () {
      // maxProperties / minProperties
      expect(
        validator.validate({'type': 'object', 'maxProperties': 1}, {'a': 1}),
        isTrue,
      );
      expect(
        () => validator.validate(
          {'type': 'object', 'maxProperties': 1},
          {'a': 1, 'b': 2},
        ),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      expect(
        validator.validate({'type': 'object', 'minProperties': 1}, {'a': 1}),
        isTrue,
      );
      expect(
        () => validator.validate({'type': 'object', 'minProperties': 1}, {}),
        throwsA(isA<JsonSchemaValidationException>()),
      );

      // dependentRequired
      final schema = {
        'type': 'object',
        'dependentRequired': {
          'credit_card': ['billing_address'],
        },
      };
      expect(
        validator
            .validate(schema, {'credit_card': 123, 'billing_address': 456}),
        isTrue,
      );
      expect(validator.validate(schema, {'other': 123}), isTrue);
      expect(
        () => validator.validate(schema, {'credit_card': 123}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates required fields', () {
      final schema = {
        'type': 'object',
        'required': ['foo'],
        'properties': {
          'foo': {'type': 'string'},
        },
      };
      expect(validator.validate(schema, {'foo': 'bar'}), isTrue);
      expect(
        () => validator.validate(schema, {'bar': 'baz'}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates nested properties', () {
      final schema = {
        'type': 'object',
        'properties': {
          'foo': {
            'type': 'object',
            'required': ['bar'],
            'properties': {
              'bar': {'type': 'string'},
            },
          },
        },
      };
      expect(
        validator.validate(schema, {
          'foo': {'bar': 'baz'},
        }),
        isTrue,
      );
      expect(
        () => validator.validate(schema, {'foo': {}}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates array items', () {
      final schema = {
        'type': 'array',
        'items': {'type': 'string'},
      };
      expect(validator.validate(schema, ['a', 'b']), isTrue);
      expect(
        () => validator.validate(schema, ['a', 1]),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates enum', () {
      final schema = {
        'enum': [
          'a',
          'b',
          {'x': 1},
        ],
      };
      expect(validator.validate(schema, 'a'), isTrue);
      expect(validator.validate(schema, {'x': 1}), isTrue); // Deep equal check
      expect(
        () => validator.validate(schema, 'c'),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates const', () {
      final schema = {
        'const': {'a': 1},
      };
      expect(validator.validate(schema, {'a': 1}), isTrue); // Deep equal check
      expect(
        () => validator.validate(schema, {'a': 2}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });
  });
}
