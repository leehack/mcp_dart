abstract class JsonSchema {
  const JsonSchema();

  Map<String, dynamic> toJson();
}

class StringSchema extends JsonSchema {
  final List<String>? enumValues;

  const StringSchema({this.enumValues});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'string',
        if (enumValues != null) 'enum': enumValues,
      };
}

class NumberSchema extends JsonSchema {
  const NumberSchema();

  @override
  Map<String, dynamic> toJson() => {'type': 'number'};
}

class BooleanSchema extends JsonSchema {
  const BooleanSchema();

  @override
  Map<String, dynamic> toJson() => {'type': 'boolean'};
}

class ObjectSchema extends JsonSchema {
  final Map<String, JsonSchema> properties;
  final List<String>? additionalProperties;

  const ObjectSchema(this.properties, {this.additionalProperties});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'object',
        'properties': properties.map((k, v) => MapEntry(k, v.toJson())),
        if (additionalProperties != null)
          'additionalProperties': additionalProperties,
      };
}

class ArraySchema extends JsonSchema {
  final JsonSchema items;

  const ArraySchema(this.items);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'array',
        'items': items.toJson(),
      };
}

class Schema {
  static StringSchema string({List<String>? enumValues}) =>
      StringSchema(enumValues: enumValues);
  static NumberSchema number() => const NumberSchema();
  static BooleanSchema boolean() => const BooleanSchema();
  static ObjectSchema object(
    Map<String, JsonSchema> properties, {
    List<String>? additionalProperties,
  }) =>
      ObjectSchema(properties, additionalProperties: additionalProperties);
  static ArraySchema array(JsonSchema items) => ArraySchema(items);
}
