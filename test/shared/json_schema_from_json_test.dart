import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:test/test.dart';

void main() {
  group('JsonSchema.fromJson', () {
    test('parses string schema', () {
      final json = {
        'type': 'string',
        'minLength': 5,
        'maxLength': 10,
        'pattern': '^[a-z]+\$',
        'format': 'email',
        'enum': ['a', 'b'],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonString>());
      final s = schema as JsonString;
      expect(s.minLength, 5);
      expect(s.maxLength, 10);
      expect(s.pattern, '^[a-z]+\$');
      expect(s.format, 'email');
      expect(s.enumValues, ['a', 'b']);
    });

    test('parses number schema', () {
      final json = {
        'type': 'number',
        'minimum': 1.5,
        'maximum': 10.5,
        'exclusiveMinimum': 1.0,
        'exclusiveMaximum': 11.0,
        'multipleOf': 0.5,
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonNumber>());
      final s = schema as JsonNumber;
      expect(s.minimum, 1.5);
      expect(s.maximum, 10.5);
      expect(s.exclusiveMinimum, 1.0);
      expect(s.exclusiveMaximum, 11.0);
      expect(s.multipleOf, 0.5);
    });

    test('parses integer schema', () {
      final json = {
        'type': 'integer',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'multipleOf': 2,
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonInteger>());
      final s = schema as JsonInteger;
      expect(s.minimum, 1);
      expect(s.maximum, 10);
      expect(s.exclusiveMinimum, 0);
      expect(s.exclusiveMaximum, 11);
      expect(s.multipleOf, 2);
    });

    test('parses boolean schema', () {
      final json = {'type': 'boolean'};
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonBoolean>());
    });

    test('parses null schema', () {
      final json = {'type': 'null'};
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonNull>());
    });

    test('parses array schema', () {
      final json = {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
        'maxItems': 5,
        'uniqueItems': true,
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonArray>());
      final s = schema as JsonArray;
      expect(s.items, isA<JsonString>());
      expect(s.minItems, 1);
      expect(s.maxItems, 5);
      expect(s.uniqueItems, true);
    });

    test('parses object schema', () {
      final json = {
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
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonObject>());
      final s = schema as JsonObject;
      expect(s.properties!.length, 2);
      expect(s.properties!['name'], isA<JsonString>());
      expect(s.properties!['age'], isA<JsonInteger>());
      expect(s.required, ['name']);
      expect(s.additionalProperties, false);
      expect(s.dependentRequired, {
        'age': ['name'],
      });
    });

    test('parses object schema with additionalProperties as schema', () {
      final json = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'additionalProperties': {'type': 'string'},
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonObject>());
      final s = schema as JsonObject;
      expect(s.additionalProperties, isA<JsonString>());
    });

    test('parses object schema with untyped additionalProperties map', () {
      // This is what z.record(z.string(), z.unknown()) produces
      final json = {'type': 'object', 'additionalProperties': {}};
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonObject>());
      final s = schema as JsonObject;
      expect(s.additionalProperties, isA<JsonAny>());
    });

    test('parses nested object with additionalProperties as schema', () {
      // Simulates a tool schema with a nested record/map property:
      // e.g. z.object({ config: z.record(z.string(), z.unknown()) })
      final json = {
        'type': 'object',
        'properties': {
          'config': {
            'type': 'object',
            'additionalProperties': <String, dynamic>{},
          },
        },
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonObject>());
      final s = schema as JsonObject;
      final config = s.properties!['config'] as JsonObject;
      expect(config.additionalProperties, isA<JsonAny>());
    });

    test('parses allOf schema', () {
      final json = {
        'allOf': [
          {'type': 'string'},
          {'minLength': 5},
        ],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonAllOf>());
      final s = schema as JsonAllOf;
      expect(s.schemas.length, 2);
      expect(s.schemas[0], isA<JsonString>());

      // Verification that 'minLength' is preserved even without 'type'
      expect(s.schemas[1].toJson(), {'minLength': 5});
    });

    test('parses anyOf schema', () {
      final json = {
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonAnyOf>());
      final s = schema as JsonAnyOf;
      expect(s.schemas.length, 2);
    });

    test('parses oneOf schema', () {
      final json = {
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonOneOf>());
      final s = schema as JsonOneOf;
      expect(s.schemas.length, 2);
    });

    test('parses not schema', () {
      final json = {
        'not': {'type': 'string'},
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonNot>());
      final s = schema as JsonNot;
      expect(s.schema, isA<JsonString>());
    });

    test('parses schema with no type as JsonAny (or equivalent)', () {
      final json = <String, dynamic>{};
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonAny>());
    });
  });

  group('Round Trip', () {
    test('string round trip', () {
      final original = JsonSchema.string(minLength: 5);
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });

    test('object round trip', () {
      final original = JsonSchema.object(
        properties: {'a': JsonSchema.string()},
        required: ['a'],
      );
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });

    test('object with additionalProperties schema round trip', () {
      final original = JsonSchema.object(
        properties: {'name': JsonSchema.string()},
        additionalProperties: JsonSchema.integer(),
      );
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });

    test('object with additionalProperties bool round trip', () {
      final original = JsonSchema.object(
        properties: {'name': JsonSchema.string()},
        additionalProperties: false,
      );
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });
  });
}
