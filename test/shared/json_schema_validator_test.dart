import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:test/test.dart';

void main() {
  group('JsonSchemaValidationException', () {
    test('toString includes message and path', () {
      final exception = JsonSchemaValidationException('test error', ['a', 'b']);
      expect(exception.toString(), contains('test error'));
      expect(exception.toString(), contains('a/b'));
      expect(exception, isNot(isA<JsonSchemaDefinitionException>()));
    });

    test('handles empty path', () {
      final exception = JsonSchemaValidationException('error', []);
      expect(exception.toString(), contains('error'));
    });

    test('distinguishes schema configuration errors', () {
      final schema = JsonSchema.fromJson({
        r'$schema': 'https://example.com/unsupported-schema',
        'type': 'object',
      });

      expect(
        () => schema.validate({}),
        throwsA(
          isA<JsonSchemaDefinitionException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Unsupported JSON Schema dialect'),
              contains(r'#/$schema'),
            ),
          ),
        ),
      );
    });

    test('classifies schema compiler failures as definition errors', () {
      final schema = JsonSchema.fromJson({
        'type': 'string',
        'minLength': -1,
      });

      expect(
        () => schema.validate('value'),
        throwsA(
          isA<JsonSchemaDefinitionException>()
              .having(
                (error) => error.message,
                'message',
                contains('Invalid JSON Schema schema: #/minLength:'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('schema: Invalid JSON Schema')),
              ),
        ),
      );
    });

    test('classifies unresolved references as definition errors', () {
      final schema = JsonSchema.fromJson({
        r'$ref': 'https://example.com/missing-schema',
      });

      expect(
        () => schema.validate({}),
        throwsA(
          isA<JsonSchemaDefinitionException>().having(
            (error) => error.message,
            'message',
            contains(r'External $ref is unresolved'),
          ),
        ),
      );
    });

    test('distinguishes unresolved local references from external ones', () {
      void expectLocalReferenceError(
        Map<String, Object?> definition,
        String keyword,
        String reference,
      ) {
        final schema = JsonSchema.fromJson(definition);
        final expectedMessage = 'Local $keyword is unresolved';

        expect(
          () => schema.validate({}),
          throwsA(
            isA<JsonSchemaDefinitionException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains(expectedMessage),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains(reference),
                )
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('External $keyword')),
                )
                .having(
                  (error) => error.message,
                  'message',
                  isNot(startsWith('Invalid JSON Schema schema:')),
                ),
          ),
        );
      }

      for (final reference in const [r'#/$defs/missing', r'#/~2invalid']) {
        expectLocalReferenceError(
          {r'$ref': reference},
          r'$ref',
          reference,
        );
      }

      const absoluteReference = r'https://example.test/root#/$defs/missing';
      expectLocalReferenceError(
        {
          r'$id': 'https://example.test/root',
          r'$ref': absoluteReference,
        },
        r'$ref',
        absoluteReference,
      );

      expectLocalReferenceError(
        {r'$dynamicRef': '#missing'},
        r'$dynamicRef',
        '#missing',
      );
    });
  });

  group('JsonSchemaValidation', () {
    group('string validation', () {
      test('validates simple string schema', () {
        final schema = JsonSchema.string(minLength: 3);
        schema.validate("abc"); // Should pass

        expect(
          () => schema.validate("ab"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates maxLength', () {
        final schema = JsonSchema.string(maxLength: 5);
        schema.validate("abc");
        schema.validate("12345");
        expect(
          () => schema.validate("123456"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates pattern', () {
        final schema = JsonSchema.string(pattern: r'^[a-z]+$');
        schema.validate("abc");
        expect(
          () => schema.validate("ABC"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate("abc123"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates string enum values', () {
        final schema = JsonSchema.string(enumValues: ['red', 'green', 'blue']);
        schema.validate("red");
        schema.validate("green");
        expect(
          () => schema.validate("yellow"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('rejects non-string values', () {
        final schema = JsonSchema.string();
        expect(
          () => schema.validate(123),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('number validation', () {
      test('validates number type', () {
        final schema = JsonSchema.number();
        schema.validate(1.5);
        schema.validate(42);
        expect(
          () => schema.validate("not a number"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates minimum', () {
        final schema = JsonSchema.number(minimum: 10);
        schema.validate(10);
        schema.validate(15);
        expect(
          () => schema.validate(5),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates maximum', () {
        final schema = JsonSchema.number(maximum: 100);
        schema.validate(100);
        schema.validate(50);
        expect(
          () => schema.validate(101),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates exclusiveMinimum', () {
        final schema = JsonSchema.number(exclusiveMinimum: 10);
        schema.validate(11);
        expect(
          () => schema.validate(10),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates exclusiveMaximum', () {
        final schema = JsonSchema.number(exclusiveMaximum: 100);
        schema.validate(99);
        expect(
          () => schema.validate(100),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates multipleOf', () {
        final schema = JsonSchema.number(multipleOf: 5);
        schema.validate(10);
        schema.validate(15);
        expect(
          () => schema.validate(7),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('compares large integers without double precision loss', () {
        final enumSchema = JsonSchema.fromJson({
          'enum': [9007199254740992.0, 9007199254740993],
        });
        enumSchema.validate(9007199254740992.0);
        enumSchema.validate(9007199254740993);
        expect(
          () => JsonSchema.fromJson({
            'enum': [9007199254740992.0],
          }).validate(9007199254740993),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => JsonSchema.fromJson({
            'maximum': 9007199254740992.0,
          }).validate(9007199254740993),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('compares extreme numeric scale gaps exactly', () {
        final finiteDoubleRange = JsonSchema.number(maximum: 5e-324);
        finiteDoubleRange.validate(5e-324);
        expect(
          () => finiteDoubleRange.validate(1e308),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('integer validation', () {
      test('validates integer type', () {
        final schema = JsonSchema.integer();
        schema.validate(42);
        expect(
          () => schema.validate(3.14),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates minimum', () {
        final schema = JsonSchema.integer(minimum: 5);
        schema.validate(5);
        schema.validate(10);
        expect(
          () => schema.validate(4),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates maximum', () {
        final schema = JsonSchema.integer(maximum: 100);
        schema.validate(100);
        expect(
          () => schema.validate(101),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates exclusiveMinimum', () {
        final schema = JsonSchema.fromJson({
          'type': 'integer',
          'exclusiveMinimum': 5.5,
        });
        schema.validate(6);
        expect(
          () => schema.validate(5),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates exclusiveMaximum', () {
        final schema = JsonSchema.fromJson({
          'type': 'integer',
          'exclusiveMaximum': 10.5,
        });
        schema.validate(9);
        schema.validate(10);
        expect(
          () => schema.validate(11),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates multipleOf', () {
        final schema = JsonSchema.fromJson({
          'type': 'integer',
          'multipleOf': 1.5,
        });
        schema.validate(3);
        schema.validate(6);
        expect(
          () => schema.validate(4),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('boolean validation', () {
      test('validates boolean values', () {
        final schema = JsonSchema.boolean();
        schema.validate(true);
        schema.validate(false);
        expect(
          () => schema.validate("true"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate(1),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('null validation', () {
      test('validates null values', () {
        final schema = const JsonNull();
        schema.validate(null);
        expect(
          () => schema.validate("null"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate(0),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('array validation', () {
      test('validates array type', () {
        final schema = JsonSchema.array();
        schema.validate([1, 2, 3]);
        schema.validate([]);
        expect(
          () => schema.validate("not an array"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates minItems', () {
        final schema = JsonSchema.array(minItems: 2);
        schema.validate([1, 2]);
        schema.validate([1, 2, 3]);
        expect(
          () => schema.validate([1]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates maxItems', () {
        final schema = JsonSchema.array(maxItems: 3);
        schema.validate([1, 2, 3]);
        expect(
          () => schema.validate([1, 2, 3, 4]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates uniqueItems', () {
        final schema = JsonSchema.array(uniqueItems: true);
        schema.validate([1, 2, 3]);
        expect(
          () => schema.validate([1, 2, 2]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates items schema', () {
        final schema = JsonSchema.array(items: JsonSchema.integer());
        schema.validate([1, 2, 3]);
        expect(
          () => schema.validate([1, "two", 3]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates array items with boolean subschemas', () {
        final alwaysValid = JsonSchema.fromJson({
          'type': 'array',
          'items': true,
        });
        alwaysValid.validate([1, 'two', null]);

        final alwaysInvalid = JsonSchema.fromJson({
          'type': 'array',
          'items': false,
        });
        alwaysInvalid.validate([]);
        expect(
          () => alwaysInvalid.validate([1]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('uniqueItems works with objects', () {
        final schema = JsonSchema.array(uniqueItems: true);
        schema.validate([
          {"a": 1},
          {"a": 2},
        ]);
        expect(
          () => schema.validate([
            {"a": 1},
            {"a": 1},
          ]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('uniqueItems works with nested arrays', () {
        final schema = JsonSchema.array(uniqueItems: true);
        schema.validate([
          [1, 2],
          [3, 4],
        ]);
        expect(
          () => schema.validate([
            [1, 2],
            [1, 2],
          ]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('object validation', () {
      test('validates object schema', () {
        final schema = JsonSchema.object(
          properties: {
            "name": JsonSchema.string(),
            "age": JsonSchema.integer(),
          },
          required: ["name"],
        );

        schema.validate({"name": "John", "age": 30}); // Pass
        schema.validate({"name": "John"}); // Pass (age optional)

        expect(
          () => schema.validate({"age": 30}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('rejects non-object values', () {
        final schema = JsonSchema.object();
        expect(
          () => schema.validate("not an object"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates dependentRequired', () {
        final schema = JsonSchema.object(
          properties: {
            "creditCard": JsonSchema.string(),
            "billingAddress": JsonSchema.string(),
          },
          dependentRequired: {
            "creditCard": ["billingAddress"],
          },
        );

        schema
            .validate({"creditCard": "1234", "billingAddress": "123 Main St"});
        schema.validate(
          {"billingAddress": "123 Main St"},
        ); // No creditCard, no requirement

        expect(
          () => schema.validate({"creditCard": "1234"}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates additionalProperties false', () {
        final schema = JsonSchema.object(
          properties: {"name": JsonSchema.string()},
          additionalProperties: false,
        );

        schema.validate({"name": "John"});
        expect(
          () => schema.validate({"name": "John", "extra": "field"}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('preserves validation behavior for non-string Dart map keys', () {
        final bounded = JsonSchema.fromJson({'maxProperties': 0});
        final closed = JsonSchema.fromJson({'additionalProperties': false});
        final named = JsonSchema.fromJson({
          'propertyNames': {'type': 'string'},
        });

        for (final schema in [bounded, closed, named]) {
          expect(
            () => schema.validate({1: 'value'}),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        }
      });

      test('validates additionalProperties as schema', () {
        final schema = JsonSchema.object(
          properties: {"name": JsonSchema.string()},
          additionalProperties: JsonSchema.integer(),
        );

        // Extra property matching the schema type is valid
        schema.validate({"name": "John", "age": 30});

        // Extra property not matching the schema type throws
        expect(
          () => schema.validate({"name": "John", "age": "not an integer"}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates additionalProperties as empty schema (any)', () {
        // z.record(z.string(), z.unknown()) produces additionalProperties: {}
        final json = {
          'type': 'object',
          'properties': <String, dynamic>{},
          'additionalProperties': {},
        };
        final schema = JsonSchema.fromJson(json) as JsonObject;

        // Any extra properties should be accepted
        schema.validate({
          "foo": "bar",
          "baz": 123,
          "nested": {"a": true},
        });
      });

      test('validates object properties with boolean subschemas', () {
        final schema = JsonSchema.fromJson({
          'type': 'object',
          'properties': {
            'allowed': true,
            'denied': false,
          },
        });

        schema.validate({'allowed': 'anything'});
        schema.validate({'allowed': null});

        expect(
          () => schema.validate({'denied': 'anything'}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('enum validation', () {
      test('validates enum values', () {
        final schema = const JsonEnum(["red", "green", "blue"]);
        schema.validate("red");
        schema.validate("green");
        expect(
          () => schema.validate("yellow"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('enum with mixed types', () {
        final schema = const JsonEnum([1, "two", true, null]);
        schema.validate(1);
        schema.validate("two");
        schema.validate(true);
        schema.validate(null);
        expect(
          () => schema.validate(2),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates enum-only schema from map', () {
        final schema = JsonSchema.fromJson({
          'enum': [1, 'a', null],
        });

        schema.validate(1);
        schema.validate('a');
        schema.validate(null);

        expect(
          () => schema.validate('b'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test(
        'compiles large enums without quadratic duplicate scanning',
        () {
          final schema = JsonSchema.fromJson({
            'enum': List<int>.generate(10000, (index) => index),
          });

          schema.validate(9999);
          expect(
            () => schema.validate(10000),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test('validates titled enum values against canonical values', () {
        final schema = const JsonEnum([
          'simple',
          {'value': 'complex', 'title': 'Complex Option'},
        ]);

        schema.validate('simple');
        schema.validate('complex');

        expect(
          () => schema.validate('Complex Option'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('round-tripped titled non-string enum stays strict', () {
        const original = JsonEnum([
          {'value': 1, 'title': 'One'},
          {'value': true, 'title': 'Enabled'},
        ]);
        final schema = JsonSchema.fromJson(original.toJson());

        schema.validate(1);
        schema.validate(true);

        expect(
          () => schema.validate('One'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate(false),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates titled anyOf enum items against canonical values', () {
        final schema = JsonSchema.fromJson({
          'type': 'array',
          'items': {
            'anyOf': [
              {'const': 'red', 'title': 'Red'},
              {'const': 'blue', 'title': 'Blue'},
            ],
          },
        });

        schema.validate(['red', 'blue']);

        expect(
          () => schema.validate(['Red']),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('const validation', () {
      test('validates only the constant value', () {
        final schema = JsonSchema.fromJson({'const': 'DELETE'});

        schema.validate('DELETE');

        expect(
          () => schema.validate('delete'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('preserves sibling assertions when parsing const schemas', () {
        final schema = JsonSchema.fromJson({
          'type': 'string',
          'const': 1,
        });

        expect(
          () => schema.validate(1),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate('1'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('union validation', () {
      test('validates type array union schema', () {
        final schema = JsonSchema.fromJson({
          'type': ['string', 'null'],
        });

        schema.validate('value');
        schema.validate(null);

        expect(
          () => schema.validate(1),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('preserves top-level constraints around type array unions', () {
        final schema = JsonSchema.fromJson({
          'type': ['string', 'null'],
          'enum': ['a'],
        });

        schema.validate('a');

        expect(
          () => schema.validate(null),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate('b'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('composition schemas', () {
      test('validates allOf', () {
        final schema = JsonSchema.allOf([
          JsonSchema.object(
            properties: {"name": JsonSchema.string()},
            required: ["name"],
          ),
          JsonSchema.object(
            properties: {"age": JsonSchema.integer()},
            required: ["age"],
          ),
        ]);

        schema.validate({"name": "John", "age": 30});
        expect(
          () => schema.validate({"name": "John"}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates anyOf', () {
        final schema = JsonSchema.anyOf([
          JsonSchema.string(),
          JsonSchema.integer(),
        ]);

        schema.validate("hello");
        schema.validate(42);
        expect(
          () => schema.validate(true),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates oneOf', () {
        final schema = JsonSchema.oneOf([
          JsonSchema.integer(minimum: 0, maximum: 10),
          JsonSchema.integer(minimum: 5, maximum: 15),
        ]);

        schema.validate(3); // Only matches first
        schema.validate(12); // Only matches second

        // Value 7 matches both schemas, should fail
        expect(
          () => schema.validate(7),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        // Value 20 matches neither
        expect(
          () => schema.validate(20),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates not', () {
        final schema = JsonSchema.not(JsonSchema.string());

        schema.validate(42);
        schema.validate(true);
        expect(
          () => schema.validate("string"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates composition keywords with boolean subschemas', () {
        final allOfTrue = JsonSchema.fromJson({
          'allOf': [
            true,
            {'type': 'string'},
          ],
        });
        allOfTrue.validate('value');
        expect(
          () => allOfTrue.validate(1),
          throwsA(isA<JsonSchemaValidationException>()),
        );

        final anyOfFalse = JsonSchema.fromJson({
          'anyOf': [
            false,
            {'type': 'integer'},
          ],
        });
        anyOfFalse.validate(1);
        expect(
          () => anyOfFalse.validate('value'),
          throwsA(isA<JsonSchemaValidationException>()),
        );

        final oneOfTrueFalse = JsonSchema.fromJson({
          'oneOf': [true, false],
        });
        oneOfTrueFalse.validate('value');
        oneOfTrueFalse.validate(null);

        final notFalse = JsonSchema.fromJson({'not': false});
        notFalse.validate('value');

        final notTrue = JsonSchema.fromJson({'not': true});
        expect(
          () => notTrue.validate('value'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('preserves sibling assertions around const composition lists', () {
        final schema = JsonSchema.fromJson({
          'type': 'string',
          'oneOf': [
            {'const': 'a'},
            {'const': 'bb'},
          ],
          'minLength': 2,
        });

        schema.validate('bb');

        expect(
          () => schema.validate('a'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('rejects malformed raw composition keywords', () {
        final schemas = [
          {
            'type': 'string',
            'allOf': ['not a schema'],
            'minLength': 1,
          },
          {
            'type': 'string',
            'anyOf': ['not a schema'],
            'minLength': 1,
          },
          {
            'type': 'string',
            'oneOf': ['not a schema'],
            'minLength': 1,
          },
          {
            'type': 'string',
            'not': 'not a schema',
            'minLength': 1,
          },
        ];

        for (final json in schemas) {
          final schema = JsonSchema.fromJson(json);
          expect(
            () => schema.validate('value'),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        }
      });

      test('rejects malformed raw type arrays at parse time', () {
        final schemas = [
          {
            'type': ['string', 1],
          },
          {
            'type': ['string', 'bogus'],
          },
          {'type': <String>[]},
          {
            'type': ['string', 'string'],
          },
          {
            'type': ['string', 1],
            'enum': ['value'],
          },
        ];

        for (final json in schemas) {
          expect(
            () => JsonSchema.fromJson(json),
            throwsA(isA<FormatException>()),
          );
        }
      });

      test('validates mixed typed enum schemas conjunctively', () {
        final schema = JsonSchema.fromJson({
          'type': 'string',
          'enum': ['a', null],
        });

        schema.validate('a');
        expect(
          () => schema.validate(null),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate('b'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('preserves exact oneOf semantics for duplicate const branches', () {
        final schema = JsonSchema.fromJson({
          'oneOf': [
            {'const': 'duplicate'},
            {'const': 'duplicate'},
          ],
        });

        expect(
          () => schema.validate('duplicate'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });

    group('JsonAny validation', () {
      test('accepts any value', () {
        final schema = const JsonAny();
        schema.validate("string");
        schema.validate(42);
        schema.validate(true);
        schema.validate(null);
        schema.validate({"key": "value"});
        schema.validate([1, 2, 3]);
      });
    });

    group('JSON Schema 2020-12 compliance', () {
      test('uses 2020-12 when the schema does not declare a dialect', () {
        final schema = JsonSchema.fromJson({
          'type': 'array',
          'prefixItems': [
            {'type': 'integer'},
          ],
          'items': false,
        });

        schema.validate([1]);
        expect(
          () => schema.validate(['1']),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate([1, 2]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('accepts the declared 2020-12 dialect URI forms', () {
        for (final dialect in const [
          'https://json-schema.org/draft/2020-12/schema',
          'https://json-schema.org/draft/2020-12/schema#',
        ]) {
          final schema = JsonSchema.fromJson({
            r'$schema': dialect,
            'type': 'string',
          });

          schema.validate('value');
          expect(
            () => schema.validate(1),
            throwsA(isA<JsonSchemaValidationException>()),
            reason: dialect,
          );
        }
      });

      test(r'canonical meta-schema $ref accepts custom dialect identifiers',
          () {
        final schema = JsonSchema.fromJson({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$ref': 'https://json-schema.org/draft/2020-12/schema',
        });

        schema.validate({
          r'$schema': 'https://example.com/custom',
          'type': 'string',
        });
        schema.validate({
          r'$id': 'not a uri',
          r'$ref': 'not a uri',
          r'$dynamicRef': 'not a uri',
          r'$vocabulary': {'relative': true},
          'pattern': '[',
          'patternProperties': {'[': true},
        });
        // The canonical 2020-12 validation meta-schema only requires `enum`
        // to be an array. Ordinary schema compilation remains stricter.
        schema.validate({'enum': []});
        schema.validate({
          'enum': [1, 1],
        });
        expect(
          () => schema.validate({'enum': 'value'}),
          throwsA(isA<JsonSchemaValidationException>()),
        );

        Object deepSchema = true;
        for (var depth = 0; depth < 70; depth++) {
          deepSchema = {
            'allOf': [deepSchema],
          };
        }
        schema.validate(deepSchema);
        schema.validate({
          r'$defs': {
            for (var index = 0; index < 1100; index++) '$index': true,
          },
        });
      });

      test('Draft 7 canonical meta-schema asserts supported formats', () {
        final metaSchema = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          r'$ref': 'http://json-schema.org/draft-07/schema#',
        });

        metaSchema.validate({
          r'$schema': 'https://example.com/custom',
          r'$id': 'relative/path',
          r'$ref': '#/definitions/value',
          'pattern': r'^[a-z]+$',
          'patternProperties': {r'^[a-z]+$': true},
        });

        for (final invalidSchema in [
          {r'$schema': 'not a uri'},
          {r'$id': 'not a uri'},
          {r'$ref': 'not a uri'},
          {'pattern': '['},
          {
            'patternProperties': {'[': true},
          },
        ]) {
          expect(
            () => metaSchema.validate(invalidSchema),
            throwsA(isA<JsonSchemaValidationException>()),
            reason: '$invalidSchema',
          );
        }
      });

      test(r'resolves canonical meta-schema fragment $ref values', () {
        for (final dialect in const [
          'http://json-schema.org/draft-07/schema#',
          'https://json-schema.org/draft-07/schema#',
        ]) {
          final base = dialect.substring(0, dialect.length - 1);
          final schema = JsonSchema.fromJson({
            r'$schema': dialect,
            r'$ref': '$base#/definitions/nonNegativeInteger',
          });
          schema.validate(3);
          expect(
            () => schema.validate(-1),
            throwsA(isA<JsonSchemaValidationException>()),
          );

          final arbitraryPointer = JsonSchema.fromJson({
            r'$schema': dialect,
            r'$ref': '$base#/properties/multipleOf',
          });
          arbitraryPointer.validate(1);
          expect(
            () => arbitraryPointer.validate(0),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        }

        final schema2020 = JsonSchema.fromJson({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$ref': 'https://json-schema.org/draft/2020-12/schema#/'
              r'%24defs/vocab-validation/$defs/nonNegativeInteger',
        });
        schema2020.validate(3);
        expect(
          () => schema2020.validate(-1),
          throwsA(isA<JsonSchemaValidationException>()),
        );

        final nestedPointer = JsonSchema.fromJson({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$ref': 'https://json-schema.org/draft/2020-12/schema#/'
              r'$defs/vocab-validation/properties/type',
        });
        nestedPointer.validate(['object']);
        expect(
          () => nestedPointer.validate([]),
          throwsA(isA<JsonSchemaValidationException>()),
        );

        final draft7Root = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          r'$ref': 'http://json-schema.org/draft-07/schema',
        });
        expect(
          () => draft7Root.validate({'type': 'bogus'}),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.path,
              'path',
              ['type'],
            ),
          ),
        );
      });

      test('uses the target dialect for cross-dialect canonical references',
          () {
        final draft7From2020 = JsonSchema.fromJson({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$ref': 'http://json-schema.org/draft-07/schema#/properties/items',
        });
        draft7From2020.validate([true]);

        final draft2020From7 = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          r'$ref': 'https://json-schema.org/draft/2020-12/schema#/'
              r'$defs/vocab-applicator/properties/items',
        });
        draft2020From7.validate(true);
        expect(
          () => draft2020From7.validate([true]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('uses declared Draft 7 tuple semantics for legacy schemas', () {
        for (final dialect in const [
          'http://json-schema.org/draft-07/schema#',
          'http://json-schema.org/draft-07/schema',
          'https://json-schema.org/draft-07/schema#',
          'https://json-schema.org/draft-07/schema',
        ]) {
          final schema = JsonSchema.fromJson({
            r'$schema': dialect,
            'type': 'array',
            'items': [
              {'type': 'string'},
              {'type': 'integer'},
            ],
            'additionalItems': false,
          });

          schema.validate(['value', 1]);
          expect(
            () => schema.validate([1, 'value']),
            throwsA(isA<JsonSchemaValidationException>()),
            reason: dialect,
          );
          expect(
            () => schema.validate(['value', 1, true]),
            throwsA(isA<JsonSchemaValidationException>()),
            reason: dialect,
          );
        }

        final defaultDialectSchema = JsonSchema.fromJson({
          'type': 'array',
          'items': [
            {'type': 'string'},
          ],
        });
        expect(
          () => defaultDialectSchema.validate(['value']),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.message,
              'message',
              contains('Invalid JSON Schema schema'),
            ),
          ),
        );
      });

      test('Draft 7 treats formats from later dialects as annotations', () {
        for (final format in const ['duration', 'uuid', 'ecmascript-regex']) {
          final schema = JsonSchema.fromJson({
            r'$schema': 'http://json-schema.org/draft-07/schema#',
            'format': format,
          });

          schema.validate(format == 'ecmascript-regex' ? '[' : 'not-valid');
        }
      });

      test('Draft 7 rejects whitespace in IPv6 values on every Dart SDK', () {
        final schema = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          'format': 'ipv6',
        });

        schema.validate('2001:db8::1');
        for (final invalid in const [
          '2001:db8::1 ',
          ' 2001:db8::1',
          '2001:db8::1\n',
          'fe80::1%eth0',
        ]) {
          expect(
            () => schema.validate(invalid),
            throwsA(isA<JsonSchemaValidationException>()),
            reason: invalid,
          );
        }
      });

      test(
        'Draft 7 rejects oversized hostname labels with bounded work',
        () {
          for (final format in const ['hostname', 'idn-hostname']) {
            final schema = JsonSchema.fromJson({
              r'$schema': 'http://json-schema.org/draft-07/schema#',
              'format': format,
            });

            schema.validate(List.filled(63, 'a').join());
            expect(
              () => schema.validate(List.filled(64, 'a').join()),
              throwsA(isA<JsonSchemaValidationException>()),
              reason: format,
            );
          }

          final idnSchema = JsonSchema.fromJson({
            r'$schema': 'http://json-schema.org/draft-07/schema#',
            'format': 'idn-hostname',
          });
          expect(
            () => idnSchema.validate(List.filled(100000, '例').join()),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test('Draft 7 ignores unrecognized 2020-12 keywords independently', () {
        final schemas = <String, Map<String, dynamic>>{
          'prefixItems': {
            'prefixItems': [false],
          },
          'unevaluatedItems': {
            'unevaluatedItems': false,
          },
          r'$dynamicRef': {
            r'$dynamicRef': r'#/$defs/rejected',
            r'$defs': {'rejected': false},
          },
          'invalid schemas under unknown keywords': {
            'prefixItems': [
              {'enum': []},
            ],
            'unevaluatedItems': {'enum': []},
            r'$defs': {
              'invalid': {
                r'$schema': 'https://example.com/unsupported',
                'enum': [],
              },
            },
          },
          'external references under unknown keywords': {
            'prefixItems': [
              {r'$ref': 'https://example.invalid/schema'},
            ],
            'unevaluatedItems': {
              r'$ref': 'https://example.invalid/schema',
            },
            r'$defs': {
              'ignored': {r'$ref': 'https://example.invalid/schema'},
            },
          },
        };

        for (final value in schemas.values) {
          final schema = JsonSchema.fromJson({
            r'$schema': 'http://json-schema.org/draft-07/schema#',
            'type': 'array',
            ...value,
          });
          schema.validate([1, 2]);
        }
      });

      test('Draft 7 treats anchor keywords as annotations', () {
        final unresolvedAnchor = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          r'$anchor': 'value',
          r'$ref': '#value',
        });
        expect(
          () => unresolvedAnchor.validate('value'),
          throwsA(isA<JsonSchemaDefinitionException>()),
        );

        final duplicateAnnotations = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          'definitions': {
            'first': {r'$anchor': 'same'},
            'second': {r'$anchor': 'same'},
          },
        });
        duplicateAnnotations.validate(null);
      });

      test(r'Draft 7 resolves local $ref values through definitions', () {
        final schema = JsonSchema.fromJson({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          'definitions': {
            'positiveInteger': {
              'type': 'integer',
              'minimum': 1,
            },
          },
          r'$ref': r'#/definitions/positiveInteger',
        });

        schema.validate(1);
        expect(
          () => schema.validate(0),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('2020-12 ignores invalid schemas under legacy unknown keywords', () {
        final schema = JsonSchema.fromJson({
          'definitions': {
            'invalid': {'enum': []},
          },
          'additionalItems': {'enum': []},
          'dependencies': {
            'value': {'enum': []},
          },
        });

        schema.validate('value');
      });

      test('2020-12 does not resolve references inside contentSchema', () {
        final schema = JsonSchema.fromJson({
          'contentSchema': {
            r'$ref': 'https://example.invalid/schema',
          },
        });

        schema.validate('encoded content');
      });

      test('rejects unsupported and malformed declared dialects clearly', () {
        for (final dialect in const <Object>[
          'http://json-schema.org/draft-06/schema#',
          'https://example.com/custom-schema',
          202012,
        ]) {
          final schema = JsonSchema.fromJson({
            r'$schema': dialect,
            'type': 'string',
          });

          expect(
            () => schema.validate('value'),
            throwsA(
              isA<JsonSchemaValidationException>().having(
                (error) => error.message,
                'message',
                contains('Unsupported JSON Schema dialect'),
              ),
            ),
          );
        }
      });

      test('normalizes compiler errors from referenced schema locations', () {
        final schema = JsonSchema.fromJson({
          r'$ref': '#/x-target',
          'x-target': {'minLength': -1},
        });

        expect(
          () => schema.validate('value'),
          throwsA(
            isA<JsonSchemaDefinitionException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('Invalid JSON Schema schema: #/minLength:'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('schema: Invalid JSON Schema')),
                ),
          ),
        );
      });

      test('rejects schemas that are invalid under 2020-12', () {
        final schemas = [
          JsonSchema.fromJson({
            'type': 'string',
            'minLength': -1,
          }),
          JsonSchema.fromJson({'enum': []}),
          JsonSchema.fromJson({
            'enum': [
              {'nested': true},
              {'nested': true},
            ],
          }),
        ];

        for (final schema in schemas) {
          expect(
            () => schema.validate('value'),
            throwsA(
              isA<JsonSchemaValidationException>().having(
                (error) => error.message,
                'message',
                contains('Invalid JSON Schema schema'),
              ),
            ),
          );
        }
      });

      test('rejects invalid URI-references in schema identifiers', () {
        for (final keyword in const [r'$id', r'$ref', r'$dynamicRef']) {
          for (final value in const [
            'a b',
            r'a\b',
            '%zz',
            'foo[bar',
            'foo]bar',
            'https://example.com/{x}',
          ]) {
            final schema = JsonSchema.fromJson({keyword: value});
            expect(
              () => schema.validate('value'),
              throwsA(isA<JsonSchemaDefinitionException>()),
              reason: '$keyword=$value',
            );
          }
        }
        JsonSchema.fromJson({r'$id': '//[::1]/schema'}).validate('value');
      });

      test(r'resolves local $ref values through $defs', () {
        final schema = JsonSchema.fromJson({
          r'$defs': {
            'positiveInteger': {
              'type': 'integer',
              'minimum': 1,
            },
          },
          'type': 'object',
          'properties': {
            'count': {r'$ref': r'#/$defs/positiveInteger'},
          },
          'required': ['count'],
        });

        schema.validate({'count': 1});
        expect(
          () => schema.validate({'count': 0}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test(r'resolves escaped JSON Pointer tokens in local $ref values', () {
        final schema = JsonSchema.fromJson({
          r'$defs': {
            'a/b~c': {'const': 'matched'},
          },
          r'$ref': r'#/$defs/a~1b~0c',
        });

        schema.validate('matched');
        expect(
          () => schema.validate('other'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test(r'rejects invalid JSON Pointer syntax in $ref values', () {
        for (final reference in const [
          r'#/$defs/foo~2bar',
          r'#/$defs/foo~',
          r'#/$defs/foo%7E2bar',
        ]) {
          final schema = JsonSchema.fromJson({
            r'$defs': {
              'foo~2bar': true,
              'foo~': true,
            },
            r'$ref': reference,
          });

          expect(
            () => schema.validate('value'),
            throwsA(isA<JsonSchemaDefinitionException>()),
            reason: reference,
          );
        }

        for (final index in const ['01', '00', '+1', '-']) {
          final schema = JsonSchema.fromJson({
            'unknown-keyword': [true, true],
            r'$ref': '#/unknown-keyword/$index',
          });
          expect(
            () => schema.validate('value'),
            throwsA(isA<JsonSchemaDefinitionException>()),
            reason: index,
          );
        }
      });

      test('reuses overlapping lazily compiled pointer targets', () {
        for (final target in [
          <String, Object?>{r'$anchor': 'value', 'type': 'string'},
          <String, Object?>{r'$id': 'value', 'type': 'string'},
        ]) {
          for (final references in const [
            [r'#/unknown/properties/x', r'#/unknown'],
            [r'#/unknown', r'#/unknown/properties/x'],
          ]) {
            final schema = JsonSchema.fromJson({
              r'$id': 'https://example.test/root',
              'unknown': {
                'properties': {'x': target},
              },
              'allOf': [
                for (final reference in references) {r'$ref': reference},
              ],
            });

            schema.validate('value');
            expect(
              () => schema.validate(1),
              throwsA(isA<JsonSchemaValidationException>()),
            );
          }
        }
      });

      test('resolves lazy resource identifiers independently of ref order', () {
        for (final references in const [
          ['child', r'#/unknown'],
          [r'#/unknown', 'child'],
        ]) {
          final schema = JsonSchema.fromJson({
            r'$id': 'https://example.test/root',
            'unknown': {r'$id': 'child', 'type': 'string'},
            'allOf': [
              for (final reference in references) {r'$ref': reference},
            ],
          });

          schema.validate('value');
          expect(
            () => schema.validate(1),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        }
      });

      test(r'decodes percent escapes in $ref fragments exactly once', () {
        final schema = JsonSchema.fromJson({
          r'$defs': {
            'percent%25field': {'const': 'matched'},
          },
          r'$ref': r'#/$defs/percent%2525field',
        });

        schema.validate('matched');
        expect(
          () => schema.validate('other'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test(r'resolves $ref pointers beneath unknown keywords', () {
        for (final schemaJson in [
          {
            'unknown-keyword': {'const': 'matched'},
            r'$ref': '#/unknown-keyword',
          },
          {
            'properties': {
              'foo': {
                'unknown-keyword': {'const': 'matched'},
                r'$ref': '#/properties/foo/unknown-keyword',
              },
            },
          },
        ]) {
          final schema = JsonSchema.fromJson(schemaJson);
          schema.validate(
            schemaJson.containsKey('properties')
                ? {'foo': 'matched'}
                : 'matched',
          );
          expect(
            () => schema.validate(
              schemaJson.containsKey('properties') ? {'foo': 'other'} : 'other',
            ),
            throwsA(isA<JsonSchemaValidationException>()),
          );
        }
      });

      test(r'resolves local $anchor references', () {
        final schema = JsonSchema.fromJson({
          r'$defs': {
            'positiveInteger': {
              r'$anchor': 'positiveInteger',
              'type': 'integer',
              'minimum': 1,
            },
          },
          r'$ref': '#positiveInteger',
        });

        schema.validate(1);
        expect(
          () => schema.validate(0),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('rejects duplicate plain-name fragments within one resource', () {
        for (final definitions in [
          {
            'first': {r'$anchor': 'same'},
            'second': {r'$anchor': 'same'},
          },
          {
            'first': {r'$anchor': 'same'},
            'second': {r'$dynamicAnchor': 'same'},
          },
          {
            'first': {r'$dynamicAnchor': 'same'},
            'second': {r'$dynamicAnchor': 'same'},
          },
          {
            'sameNode': {
              r'$anchor': 'same',
              r'$dynamicAnchor': 'same',
            },
          },
        ]) {
          final schema = JsonSchema.fromJson({r'$defs': definitions});
          expect(
            () => schema.validate(null),
            throwsA(isA<JsonSchemaDefinitionException>()),
          );
        }

        final distinctResources = JsonSchema.fromJson({
          r'$id': 'https://example.test/root',
          r'$defs': {
            'first': {
              r'$id': 'first',
              r'$anchor': 'same',
            },
            'second': {
              r'$id': 'second',
              r'$anchor': 'same',
            },
          },
        });
        distinctResources.validate(null);
      });

      test(r'rejects duplicate resolved $id resource identifiers', () {
        for (final definitions in [
          {
            'first': {r'$id': 'resource'},
            'second': {r'$id': './resource'},
          },
          {
            'nested': {r'$id': 'https://example.test/root'},
          },
        ]) {
          final schema = JsonSchema.fromJson({
            r'$id': 'https://example.test/root',
            r'$defs': definitions,
          });
          expect(
            () => schema.validate(null),
            throwsA(isA<JsonSchemaDefinitionException>()),
          );
        }
      });

      test('resolves absolute references to in-document resources', () {
        final rootResource = JsonSchema.fromJson({
          r'$id': 'https://example.com/root-schema',
          r'$defs': {
            'positiveInteger': {
              'type': 'integer',
              'minimum': 1,
            },
          },
          r'$ref': r'https://example.com/root-schema#/$defs/positiveInteger',
        });
        rootResource.validate(1);
        expect(
          () => rootResource.validate(0),
          throwsA(isA<JsonSchemaValidationException>()),
        );

        final embeddedResource = JsonSchema.fromJson({
          r'$defs': {
            'positiveInteger': {
              r'$id': 'urn:example:positive-integer',
              'type': 'integer',
              'minimum': 1,
            },
          },
          r'$ref': 'urn:example:positive-integer',
        });
        embeddedResource.validate(1);
        expect(
          () => embeddedResource.validate(0),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test(r'applies a nested $id before resolving its sibling $ref', () {
        final schema = JsonSchema.fromJson({
          r'$id': 'https://example.com/schemas/base.json',
          r'$ref': 'nested/value.json',
          r'$defs': {
            'value': {
              r'$id': 'nested/value.json',
              r'$ref': './number.json',
            },
            'number': {
              r'$id': 'nested/number.json',
              'type': 'number',
            },
          },
        });

        schema.validate(1);
        expect(
          () => schema.validate('not a number'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test(r'terminates cycles across schema resources', () {
        final schema = JsonSchema.fromJson({
          r'$id': 'https://example.com/A',
          r'$ref': 'B',
          r'$defs': {
            'B': {
              r'$id': 'B',
              r'$ref': 'https://example.com/A',
            },
          },
        });

        schema.validate('value');
      });

      test(
        'memoizes recursive combinator evaluation',
        () {
          final schema = JsonSchema.fromJson({
            r'$defs': {
              'node': {
                'anyOf': [
                  {
                    'properties': {
                      'next': {r'$ref': r'#/$defs/node'},
                    },
                  },
                  {
                    'properties': {
                      'next': {r'$ref': r'#/$defs/node'},
                    },
                  },
                ],
              },
            },
            r'$ref': r'#/$defs/node',
          });
          Object value = <String, Object?>{};
          for (var depth = 0; depth < 20; depth++) {
            value = <String, Object?>{'next': value};
          }

          schema.validate(value);
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test(
        'bounds deep recursive instance evaluation without reducing baseline',
        () {
          final schemas = [
            JsonSchema.fromJson({
              r'$defs': {
                'node': {
                  'type': 'object',
                  'properties': {
                    'next': {r'$ref': r'#/$defs/node'},
                  },
                },
              },
              r'$ref': r'#/$defs/node',
            }),
            JsonSchema.fromJson({
              r'$id': 'https://example.test/node',
              r'$dynamicAnchor': 'node',
              'type': 'object',
              'properties': {
                'next': {r'$dynamicRef': '#node'},
              },
            }),
          ];

          Object nestedObject(int depth) {
            Object value = <String, Object?>{};
            for (var level = 0; level < depth; level++) {
              value = <String, Object?>{'next': value};
            }
            return value;
          }

          final baselineDepth = nestedObject(1100);
          final boundedDepth = nestedObject(1200);
          for (final schema in schemas) {
            schema.validate(baselineDepth);
            expect(
              () => schema.validate(boundedDepth),
              throwsA(
                isA<JsonSchemaValidationException>().having(
                  (error) => error.message,
                  'message',
                  contains('maximum depth'),
                ),
              ),
            );
          }
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test(
        'memoizes static reference DAGs across resource paths',
        () {
          const levels = 20;
          final definitions = <String, Object?>{};
          for (var level = 0; level < levels; level++) {
            definitions['c$level'] = {
              r'$id': 'c$level',
              'allOf': [
                {r'$ref': 'a$level'},
                {r'$ref': 'b$level'},
              ],
            };
            definitions['a$level'] = {
              r'$id': 'a$level',
              r'$ref': 'c${level + 1}',
            };
            definitions['b$level'] = {
              r'$id': 'b$level',
              r'$ref': 'c${level + 1}',
            };
          }
          definitions['c$levels'] = {r'$id': 'c$levels'};
          final schema = JsonSchema.fromJson({
            r'$id': 'https://example.test/root',
            r'$dynamicAnchor': 'unused',
            r'$defs': {
              ...definitions,
              'unusedDynamic': {r'$dynamicRef': '#unused'},
            },
            r'$ref': 'c0',
          });

          schema.validate(null);
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test(
        'memoizes dynamic reference DAGs across equivalent scopes',
        () {
          const levels = 8;
          final definitions = <String, Object?>{};
          for (var level = 0; level < levels; level++) {
            definitions['c$level'] = {
              r'$id': 'c$level',
              'allOf': [
                {r'$ref': 'a$level'},
                {r'$ref': 'b$level'},
              ],
            };
            definitions['a$level'] = {
              r'$id': 'a$level',
              r'$dynamicAnchor': 'node',
              r'$ref': 'c${level + 1}',
            };
            definitions['b$level'] = {
              r'$id': 'b$level',
              r'$dynamicAnchor': 'node',
              r'$ref': 'c${level + 1}',
            };
          }
          definitions['c$levels'] = {
            r'$id': 'c$levels',
            r'$dynamicRef': 'target#node',
          };
          definitions['target'] = {
            r'$id': 'target',
            r'$dynamicAnchor': 'node',
          };
          final schema = JsonSchema.fromJson({
            r'$id': 'https://example.test/root',
            r'$defs': definitions,
            r'$ref': 'c0',
          });

          schema.validate(null);
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test('evaluates if, then, and else branches', () {
        final schema = JsonSchema.fromJson({
          'type': 'object',
          'properties': {
            'kind': {'type': 'string'},
            'value': true,
          },
          'required': ['kind', 'value'],
          'if': {
            'properties': {
              'kind': {'const': 'text'},
            },
            'required': ['kind'],
          },
          'then': {
            'properties': {
              'value': {'type': 'string', 'minLength': 2},
            },
          },
          'else': {
            'properties': {
              'value': {'type': 'integer'},
            },
          },
        });

        schema.validate({'kind': 'text', 'value': 'ok'});
        schema.validate({'kind': 'count', 'value': 2});
        expect(
          () => schema.validate({'kind': 'text', 'value': 2}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate({'kind': 'count', 'value': '2'}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('evaluates contains with minimum and maximum matches', () {
        final schema = JsonSchema.fromJson({
          'type': 'array',
          'contains': {'type': 'integer'},
          'minContains': 2,
          'maxContains': 2,
        });

        schema.validate([1, 'two', 3]);
        expect(
          () => schema.validate([1, 'two']),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate([1, 2, 3]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('accepts mathematically integral JSON number counts', () {
        final schema = JsonSchema.fromJson({
          'type': 'array',
          'contains': {'type': 'integer'},
          'minContains': 1.0,
          'maxContains': 2.0,
          'minItems': 1.0,
          'maxItems': 3.0,
        });

        schema.validate([1]);
        schema.validate([1, 2]);
        expect(
          () => schema.validate([]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
        expect(
          () => schema.validate([1, 2, 3, 4]),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('treats content keywords as annotations', () {
        final schema = JsonSchema.fromJson({
          'contentEncoding': 'base64',
          'contentMediaType': 'application/json',
          'contentSchema': {
            'type': 'object',
            'required': ['value'],
          },
        });

        schema.validate('not base64');
        schema.validate(1);
        schema.validate(null);
      });

      test(r'treats pointer $dynamicRef values like $ref', () {
        final schema = JsonSchema.fromJson({
          r'$defs': {
            'value': {'type': 'integer'},
          },
          r'$dynamicRef': r'#/$defs/value',
        });

        schema.validate(1);
        expect(
          () => schema.validate('1'),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('tracks evaluated properties across allOf', () {
        final schema = JsonSchema.fromJson({
          'type': 'object',
          'allOf': [
            {
              'properties': {
                'name': {'type': 'string'},
              },
              'required': ['name'],
            },
          ],
          'unevaluatedProperties': false,
        });

        schema.validate({'name': 'Ada'});
        expect(
          () => schema.validate({'name': 'Ada', 'extra': true}),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('tracks evaluated properties across matching anyOf branches', () {
        final schema = JsonSchema.fromJson({
          'type': 'object',
          'anyOf': [
            {
              'properties': {'a': true},
            },
            {
              'properties': {'b': true},
            },
          ],
          'unevaluatedProperties': false,
        });

        schema.validate({'a': 1, 'b': 2});
      });

      test('tracks evaluated prefix items', () {
        final schema = JsonSchema.fromJson({
          'type': 'array',
          'prefixItems': [
            {'type': 'string'},
          ],
          'unevaluatedItems': false,
        });

        schema.validate(['first']);
        expect(
          () => schema.validate(['first', 'extra']),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('tracks evaluated item locations independently when nested', () {
        final schema = JsonSchema.fromJson({
          'prefixItems': [
            {
              'prefixItems': [
                true,
                {'type': 'string'},
              ],
            },
          ],
          'unevaluatedItems': false,
        });

        schema.validate([
          ['foo', 'bar'],
        ]);
        expect(
          () => schema.validate([
            ['foo', 'bar'],
            'bar',
          ]),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.path,
              'path',
              ['1'],
            ),
          ),
        );
      });

      test('combines static prefix evaluations without leaking nested state',
          () {
        final schema = JsonSchema.fromJson({
          'prefixItems': [
            {
              'prefixItems': [
                true,
                {'type': 'string'},
              ],
            },
          ],
          'allOf': [
            {
              'prefixItems': [
                true,
                {'type': 'integer'},
              ],
            },
          ],
          'unevaluatedItems': false,
        });

        schema.validate([
          ['nested', 'value'],
          2,
        ]);
        expect(
          () => schema.validate([
            ['nested', 'value'],
            2,
            'extra',
          ]),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.path,
              'path',
              ['2'],
            ),
          ),
        );
      });

      test('rejects external and relative references', () {
        for (final reference in const [
          'https://example.com/schema.json',
          'http://127.0.0.1/schema.json',
          '../schema.json',
          r'schema.json#/$defs/value',
        ]) {
          final schema = JsonSchema.fromJson({r'$ref': reference});

          expect(
            () => schema.validate('value'),
            throwsA(
              isA<JsonSchemaValidationException>().having(
                (error) => error.message,
                'message',
                allOf(contains(r'External $ref'), contains(reference)),
              ),
            ),
          );
        }
      });

      test(r'rejects external $dynamicRef values', () {
        final schema = JsonSchema.fromJson({
          r'$dynamicRef': 'https://example.com/schema.json#node',
        });

        expect(
          () => schema.validate('value'),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.message,
              'message',
              contains(r'External $dynamicRef'),
            ),
          ),
        );
      });

      test('bounds schema nesting depth', () {
        Map<String, dynamic> schemaJson = {'type': 'string'};
        for (var i = 0; i < 65; i++) {
          schemaJson = {
            'allOf': [schemaJson],
          };
        }
        final schema = JsonSchema.fromJson(schemaJson);

        expect(
          () => schema.validate('value'),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.message,
              'message',
              contains('maximum depth'),
            ),
          ),
        );
      });

      test('bounds the total number of subschemas', () {
        final schema = JsonSchema.fromJson({
          'allOf': List<bool>.filled(1024, true),
        });

        expect(
          () => schema.validate('value'),
          throwsA(
            isA<JsonSchemaValidationException>().having(
              (error) => error.message,
              'message',
              contains('maximum of 1024 subschemas'),
            ),
          ),
        );
      });
    });

    group('complex validation from map (legacy support)', () {
      test('validates complex schema from map', () {
        final mapSchema = {"type": "string", "minLength": 3};
        final schema = JsonSchema.fromJson(mapSchema);
        schema.validate("abc");
        expect(
          () => schema.validate("ab"),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });
    });
  });
}
