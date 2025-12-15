import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:test/test.dart';

void main() {
  group('JsonSchema', () {
    test('JsonString serializes correctly', () {
      final schema = JsonSchema.string(
        minLength: 5,
        maxLength: 10,
        pattern: '^[a-z]+\$',
        format: 'email',
        enumValues: ['a', 'b'],
      );
      expect(schema.toJson(), {
        'type': 'string',
        'minLength': 5,
        'maxLength': 10,
        'pattern': '^[a-z]+\$',
        'format': 'email',
        'enum': ['a', 'b'],
      });
    });

    test('JsonNumber serializes correctly', () {
      final schema = JsonSchema.number(
        minimum: 1.5,
        maximum: 10.5,
        exclusiveMinimum: 1.0,
        exclusiveMaximum: 11.0,
        multipleOf: 0.5,
      );
      expect(schema.toJson(), {
        'type': 'number',
        'minimum': 1.5,
        'maximum': 10.5,
        'exclusiveMinimum': 1.0,
        'exclusiveMaximum': 11.0,
        'multipleOf': 0.5,
      });
    });

    test('JsonInteger serializes correctly', () {
      final schema = JsonSchema.integer(
        minimum: 1,
        maximum: 10,
      );
      expect(schema.toJson(), {
        'type': 'integer',
        'minimum': 1,
        'maximum': 10,
      });
    });

    test('JsonBoolean serializes correctly', () {
      expect(JsonSchema.boolean().toJson(), {'type': 'boolean'});
    });

    test('JsonNull serializes correctly', () {
      expect(JsonSchema.nullValue().toJson(), {'type': 'null'});
    });

    test('JsonArray serializes correctly', () {
      final schema = JsonSchema.array(
        items: JsonSchema.string(),
        minItems: 1,
        maxItems: 5,
        uniqueItems: true,
      );
      expect(schema.toJson(), {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
        'maxItems': 5,
        'uniqueItems': true,
      });
    });

    test('JsonObject serializes correctly', () {
      final schema = JsonSchema.object(
        properties: {
          'name': JsonSchema.string(),
          'age': JsonSchema.integer(),
        },
        required: ['name'],
        additionalProperties: false,
        dependentRequired: {
          'age': ['name'],
        },
      );
      expect(schema.toJson(), {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name'],
        'additionalProperties': false,
        'dependentRequired': {
          'age': ['name'],
        },
      });
    });

    test('JsonAllOf serializes correctly', () {
      final schema = JsonSchema.allOf([
        JsonSchema.string(),
        JsonSchema.integer(),
      ]);
      expect(schema.toJson(), {
        'allOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      });
    });

    test('JsonAnyOf serializes correctly', () {
      final schema = JsonSchema.anyOf([
        JsonSchema.string(),
        JsonSchema.integer(),
      ]);
      expect(schema.toJson(), {
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      });
    });

    test('JsonOneOf serializes correctly', () {
      final schema = JsonSchema.oneOf([
        JsonSchema.string(),
        JsonSchema.integer(),
      ]);
      expect(schema.toJson(), {
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      });
    });

    test('JsonNot serializes correctly', () {
      final schema = JsonSchema.not(JsonSchema.string());
      expect(schema.toJson(), {
        'not': {'type': 'string'},
      });
    });
  });

  group('JsonSchema Validation Integration', () {
    test('validates string schema', () {
      final schema = JsonSchema.string(minLength: 3);

      schema.validate('abc'); // Should pass
      expect(
        () => schema.validate('ab'),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates object schema', () {
      final schema = JsonSchema.object(
        properties: {
          'name': JsonSchema.string(),
          'age': JsonSchema.integer(minimum: 0),
        },
        required: ['name'],
      );

      schema.validate({'name': 'Alice', 'age': 30}); // Pass
      schema.validate({'name': 'Bob'}); // Pass

      expect(
        () => schema.validate({'age': 30}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
      expect(
        () => schema.validate({'name': 'Alice', 'age': -1}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });
  });
}
