import 'package:test/test.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

void main() {
  group('JsonSchemaValidationException', () {
    test('toString includes message and path', () {
      final exception = JsonSchemaValidationException('test error', ['a', 'b']);
      expect(exception.toString(), contains('test error'));
      expect(exception.toString(), contains('a/b'));
    });

    test('handles empty path', () {
      final exception = JsonSchemaValidationException('error', []);
      expect(exception.toString(), contains('error'));
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
