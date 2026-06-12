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

    test('preserves mixed typed enum schemas conjunctively', () {
      final json = {
        'type': 'string',
        'enum': ['a', null],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonAny>());
      expect(schema.toJson(), json);
    });

    test('parses legacy enum schema', () {
      final json = {
        'type': 'enum',
        'values': ['simple', 'complex'],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonEnum>());
      final s = schema as JsonEnum;
      expect(s.values, ['simple', 'complex']);
    });

    test('parses enum-only schema', () {
      final json = {
        'enum': [1, 'a', null],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonEnum>());
      final s = schema as JsonEnum;
      expect(s.values, [1, 'a', null]);
      expect(s.toJson(), json);
    });

    test('parses const schema', () {
      final json = {'const': 'DELETE'};
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonConst>());
      final s = schema as JsonConst;
      expect(s.value, 'DELETE');
      expect(s.toJson(), json);
    });

    test('parses type array union schema', () {
      final json = {
        'type': ['string', 'null'],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonUnion>());
      final s = schema as JsonUnion;
      expect(s.schemas[0], isA<JsonString>());
      expect(s.schemas[1], isA<JsonNull>());
      expect(s.toJson(), json);
    });

    test('parses titled enum const schemas', () {
      final json = {
        'oneOf': [
          {'const': 1, 'title': 'One'},
          {'const': true, 'title': 'Enabled'},
        ],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonEnum>());
      expect(schema.toJson(), json);
    });

    test('parses titled string enum const schemas from MCP elicitation', () {
      final json = {
        'type': 'string',
        'oneOf': [
          {
            'const': 'red',
            'title': 'Red',
            'description': 'Primary red option',
          },
          {'const': 'blue', 'title': 'Blue', 'default': 'blue'},
        ],
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonEnum>());
      final s = schema as JsonEnum;
      expect(s.normalizedValues, ['red', 'blue']);
      expect(s.toJson(), json);
    });

    test('parses titled array enum items from MCP elicitation', () {
      final json = {
        'type': 'array',
        'items': {
          'anyOf': [
            {'const': 'red', 'title': 'Red'},
            {'const': 'blue', 'title': 'Blue'},
          ],
        },
      };
      final schema = JsonSchema.fromJson(json);
      expect(schema, isA<JsonArray>());
      final array = schema as JsonArray;
      expect(array.items, isA<JsonEnum>());
      expect((array.items! as JsonEnum).normalizedValues, ['red', 'blue']);
      expect(array.toJson(), json);
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

    test('round trips boolean schema values', () {
      expect(JsonSchema.fromJsonValue(true).toJsonValue(), true);
      expect(JsonSchema.fromJsonValue(false).toJsonValue(), false);
    });

    test('parses object properties with boolean subschemas', () {
      final json = {
        'type': 'object',
        'properties': {
          'allowed': true,
          'denied': false,
          'named': {'type': 'string'},
        },
      };

      final schema = JsonSchema.fromJson(json);

      expect(schema, isA<JsonObject>());
      final object = schema as JsonObject;
      expect(object.properties!['allowed'], isA<JsonAny>());
      expect(object.properties!['denied'], isA<JsonNot>());
      expect(object.properties!['named'], isA<JsonString>());
      expect(object.toJson(), json);
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

    test('parses array items with boolean subschemas', () {
      for (final json in [
        {'type': 'array', 'items': true},
        {'type': 'array', 'items': false},
      ]) {
        final schema = JsonSchema.fromJson(json);

        expect(schema, isA<JsonArray>());
        expect(schema.toJson(), json);
      }
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

    test('parses composition keywords with boolean subschemas', () {
      final schemas = [
        {
          'allOf': [
            true,
            {'type': 'string'},
          ],
        },
        {
          'anyOf': [
            false,
            {'type': 'integer'},
          ],
        },
        {
          'oneOf': [true, false],
        },
        {'not': false},
        {'not': true},
      ];

      for (final json in schemas) {
        expect(JsonSchema.fromJson(json).toJson(), json);
      }
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

    test('nested boolean subschemas round trip', () {
      final schemas = [
        {
          'type': 'object',
          'properties': {
            'allowed': true,
            'denied': false,
          },
        },
        {'type': 'array', 'items': false},
        {
          'allOf': [
            true,
            {'type': 'string'},
          ],
        },
        {'not': true},
      ];

      for (final json in schemas) {
        expect(JsonSchema.fromJson(json).toJson(), json);
      }
    });

    test('const round trip', () {
      final original = JsonSchema.constValue('DELETE');
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });

    test('type array union round trip', () {
      final original = JsonSchema.union([
        JsonSchema.string(),
        JsonSchema.nullValue(),
      ]);
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });

    test('union with boolean subschema branches round trip', () {
      final original = JsonSchema.union([
        JsonSchema.fromJsonValue(true),
        JsonSchema.fromJsonValue(false),
      ]);
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);

      expect(json, {
        'anyOf': [true, false],
      });
      expect(parsed.toJson(), json);
    });

    test('type array union with sibling constraints preserves wire shape', () {
      final json = {
        'title': 'Optional mode',
        'description':
            'Official JSON Schema allows assertions beside type arrays',
        'type': ['string', 'null'],
        'enum': ['auto', null],
        'default': 'auto',
      };

      final parsed = JsonSchema.fromJson(json);

      expect(parsed.toJson(), json);
    });

    test('explicit null defaults preserve parsed wire shape', () {
      final schemas = [
        {
          'type': 'string',
          'default': null,
        },
        {
          'const': 'DELETE',
          'default': null,
        },
        {
          'type': ['string', 'null'],
          'enum': ['auto', null],
          'default': null,
        },
        {
          'oneOf': [
            {'const': 'short', 'title': 'Short'},
            {'const': 'longer', 'title': 'Longer'},
          ],
          'default': null,
        },
      ];

      for (final json in schemas) {
        expect(JsonSchema.fromJson(json).toJson(), json);
      }
    });

    test('composition schema with sibling assertions preserves wire shape', () {
      final json = {
        'type': 'string',
        'oneOf': [
          {'const': 'short', 'title': 'Short'},
          {'const': 'longer', 'title': 'Longer'},
        ],
        'minLength': 5,
      };

      final parsed = JsonSchema.fromJson(json);

      expect(parsed.toJson(), json);
    });

    test('const schema with sibling assertions preserves wire shape', () {
      final json = {
        'type': 'string',
        'const': 'DELETE',
        'minLength': 6,
      };

      final parsed = JsonSchema.fromJson(json);

      expect(parsed.toJson(), json);
    });

    test('titled non-string enum round trip', () {
      const original = JsonEnum([
        {'value': 1, 'title': 'One'},
        {'value': true, 'title': 'Enabled'},
      ]);
      final json = original.toJson();
      final parsed = JsonSchema.fromJson(json);
      expect(parsed.toJson(), json);
    });
  });
}
