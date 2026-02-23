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
        final schema = JsonSchema.integer(exclusiveMinimum: 5);
        schema.validate(6);
        expect(
          () => schema.validate(5),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates exclusiveMaximum', () {
        final schema = JsonSchema.integer(exclusiveMaximum: 10);
        schema.validate(9);
        expect(
          () => schema.validate(10),
          throwsA(isA<JsonSchemaValidationException>()),
        );
      });

      test('validates multipleOf', () {
        final schema = JsonSchema.integer(multipleOf: 3);
        schema.validate(9);
        expect(
          () => schema.validate(10),
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
          'additionalProperties': <String, dynamic>{},
        };
        final schema = JsonSchema.fromJson(json) as JsonObject;

        // Any extra properties should be accepted
        schema.validate({"foo": "bar", "baz": 123, "nested": {"a": true}});
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
