/// A builder for creating JSON Schemas in a type-safe way.
sealed class JsonSchema {
  const JsonSchema();

  /// Creates a [JsonSchema] from a JSON map.
  factory JsonSchema.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('allOf')) {
      return JsonAllOf.fromJson(json);
    }
    if (json.containsKey('anyOf')) {
      return JsonAnyOf.fromJson(json);
    }
    if (json.containsKey('oneOf')) {
      return JsonOneOf.fromJson(json);
    }
    if (json.containsKey('not')) {
      return JsonNot.fromJson(json);
    }

    final type = json['type'];
    if (type is String) {
      switch (type) {
        case 'string':
          return JsonString.fromJson(json);
        case 'number':
          return JsonNumber.fromJson(json);
        case 'integer':
          return JsonInteger.fromJson(json);
        case 'boolean':
          return JsonBoolean.fromJson(json);
        case 'null':
          return JsonNull.fromJson(json);
        case 'array':
          return JsonArray.fromJson(json);
        case 'object':
          return JsonObject.fromJson(json);
      }
    }

    // Fallback for schemas without an explicit type, or unknown types.
    // This handles empty schemas {} which validate everything (JsonAny).
    return JsonAny.fromJson(json);
  }

  /// Converts the schema to a JSON map.
  Map<String, dynamic> toJson();

  /// Creates a string schema.
  static JsonString string({
    int? minLength,
    int? maxLength,
    String? pattern,
    String? format,
    List<String>? enumValues,
  }) {
    return JsonString(
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
      format: format,
      enumValues: enumValues,
    );
  }

  /// Creates a number schema.
  static JsonNumber number({
    num? minimum,
    num? maximum,
    num? exclusiveMinimum,
    num? exclusiveMaximum,
    num? multipleOf,
  }) {
    return JsonNumber(
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      multipleOf: multipleOf,
    );
  }

  /// Creates an integer schema.
  static JsonInteger integer({
    int? minimum,
    int? maximum,
    int? exclusiveMinimum,
    int? exclusiveMaximum,
    int? multipleOf,
  }) {
    return JsonInteger(
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      multipleOf: multipleOf,
    );
  }

  /// Creates a boolean schema.
  static JsonBoolean boolean() {
    return const JsonBoolean();
  }

  /// Creates a null schema.
  static JsonNull nullValue() {
    return const JsonNull();
  }

  /// Creates an array schema.
  static JsonArray array({
    JsonSchema? items,
    int? minItems,
    int? maxItems,
    bool? uniqueItems,
  }) {
    return JsonArray(
      items: items,
      minItems: minItems,
      maxItems: maxItems,
      uniqueItems: uniqueItems,
    );
  }

  /// Creates an object schema.
  static JsonObject object({
    Map<String, JsonSchema>? properties,
    List<String>? required,
    bool? additionalProperties,
    Map<String, List<String>>? dependentRequired,
  }) {
    return JsonObject(
      properties: properties,
      required: required,
      additionalProperties: additionalProperties,
      dependentRequired: dependentRequired,
    );
  }

  /// Creates an allOf schema.
  static JsonAllOf allOf(List<JsonSchema> schemas) {
    return JsonAllOf(schemas);
  }

  /// Creates an anyOf schema.
  static JsonAnyOf anyOf(List<JsonSchema> schemas) {
    return JsonAnyOf(schemas);
  }

  /// Creates a oneOf schema.
  static JsonOneOf oneOf(List<JsonSchema> schemas) {
    return JsonOneOf(schemas);
  }

  /// Creates a not schema.
  static JsonNot not(JsonSchema schema) {
    return JsonNot(schema);
  }
}

/// A schema for string values.
class JsonString extends JsonSchema {
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final String? format;
  final List<String>? enumValues;

  const JsonString({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.format,
    this.enumValues,
  });

  factory JsonString.fromJson(Map<String, dynamic> json) {
    return JsonString(
      minLength: json['minLength'] as int?,
      maxLength: json['maxLength'] as int?,
      pattern: json['pattern'] as String?,
      format: json['format'] as String?,
      enumValues: (json['enum'] as List?)?.cast<String>(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'string',
      if (minLength != null) 'minLength': minLength,
      if (maxLength != null) 'maxLength': maxLength,
      if (pattern != null) 'pattern': pattern,
      if (format != null) 'format': format,
      if (enumValues != null) 'enum': enumValues,
    };
  }
}

/// A schema for number values.
class JsonNumber extends JsonSchema {
  final num? minimum;
  final num? maximum;
  final num? exclusiveMinimum;
  final num? exclusiveMaximum;
  final num? multipleOf;

  const JsonNumber({
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
  });

  factory JsonNumber.fromJson(Map<String, dynamic> json) {
    return JsonNumber(
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
      exclusiveMinimum: json['exclusiveMinimum'] as num?,
      exclusiveMaximum: json['exclusiveMaximum'] as num?,
      multipleOf: json['multipleOf'] as num?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'number',
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
      if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
      if (multipleOf != null) 'multipleOf': multipleOf,
    };
  }
}

/// A schema for integer values.
class JsonInteger extends JsonSchema {
  final int? minimum;
  final int? maximum;
  final int? exclusiveMinimum;
  final int? exclusiveMaximum;
  final int? multipleOf;

  const JsonInteger({
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
  });

  factory JsonInteger.fromJson(Map<String, dynamic> json) {
    return JsonInteger(
      minimum: json['minimum'] as int?,
      maximum: json['maximum'] as int?,
      exclusiveMinimum: json['exclusiveMinimum'] as int?,
      exclusiveMaximum: json['exclusiveMaximum'] as int?,
      multipleOf: json['multipleOf'] as int?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'integer',
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
      if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
      if (multipleOf != null) 'multipleOf': multipleOf,
    };
  }
}

/// A schema for boolean values.
class JsonBoolean extends JsonSchema {
  const JsonBoolean();

  factory JsonBoolean.fromJson(Map<String, dynamic> json) {
    return const JsonBoolean();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'boolean'};
  }
}

/// A schema for null values.
class JsonNull extends JsonSchema {
  const JsonNull();

  factory JsonNull.fromJson(Map<String, dynamic> json) {
    return const JsonNull();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'null'};
  }
}

/// A schema for array values.
class JsonArray extends JsonSchema {
  final JsonSchema? items;
  final int? minItems;
  final int? maxItems;
  final bool? uniqueItems;

  const JsonArray({
    this.items,
    this.minItems,
    this.maxItems,
    this.uniqueItems,
  });

  factory JsonArray.fromJson(Map<String, dynamic> json) {
    return JsonArray(
      items: json['items'] != null
          ? JsonSchema.fromJson(json['items'] as Map<String, dynamic>)
          : null,
      minItems: json['minItems'] as int?,
      maxItems: json['maxItems'] as int?,
      uniqueItems: json['uniqueItems'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'array',
      if (items != null) 'items': items!.toJson(),
      if (minItems != null) 'minItems': minItems,
      if (maxItems != null) 'maxItems': maxItems,
      if (uniqueItems != null) 'uniqueItems': uniqueItems,
    };
  }
}

/// A schema for object values.
class JsonObject extends JsonSchema {
  final Map<String, JsonSchema>? properties;
  final List<String>? required;
  final bool? additionalProperties;
  final Map<String, List<String>>? dependentRequired;

  const JsonObject({
    this.properties,
    this.required,
    this.additionalProperties,
    this.dependentRequired,
  });

  factory JsonObject.fromJson(Map<String, dynamic> json) {
    return JsonObject(
      properties: (json['properties'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(
          key,
          JsonSchema.fromJson(value as Map<String, dynamic>),
        ),
      ),
      required: (json['required'] as List?)?.cast<String>(),
      additionalProperties: json['additionalProperties'] as bool?,
      dependentRequired:
          (json['dependentRequired'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(
          key,
          (value as List).cast<String>(),
        ),
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'object',
      if (properties != null)
        'properties': properties!.map((k, v) => MapEntry(k, v.toJson())),
      if (required != null) 'required': required,
      if (additionalProperties != null)
        'additionalProperties': additionalProperties,
      if (dependentRequired != null) 'dependentRequired': dependentRequired,
    };
  }
}

/// A schema that accepts any value, potentially with additional constraints not captured by other types.
class JsonAny extends JsonSchema {
  final Map<String, dynamic> properties;

  const JsonAny([this.properties = const {}]);

  factory JsonAny.fromJson(Map<String, dynamic> json) {
    return JsonAny(Map.unmodifiable(json));
  }

  @override
  Map<String, dynamic> toJson() {
    return Map.from(properties);
  }
}

/// A schema that validates against all of the given schemas.
class JsonAllOf extends JsonSchema {
  final List<JsonSchema> schemas;

  const JsonAllOf(this.schemas);

  factory JsonAllOf.fromJson(Map<String, dynamic> json) {
    return JsonAllOf(
      (json['allOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'allOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against any of the given schemas.
class JsonAnyOf extends JsonSchema {
  final List<JsonSchema> schemas;

  const JsonAnyOf(this.schemas);

  factory JsonAnyOf.fromJson(Map<String, dynamic> json) {
    return JsonAnyOf(
      (json['anyOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'anyOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against exactly one of the given schemas.
class JsonOneOf extends JsonSchema {
  final List<JsonSchema> schemas;

  const JsonOneOf(this.schemas);

  factory JsonOneOf.fromJson(Map<String, dynamic> json) {
    return JsonOneOf(
      (json['oneOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'oneOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against none of the given schemas.
class JsonNot extends JsonSchema {
  final JsonSchema schema;

  const JsonNot(this.schema);

  factory JsonNot.fromJson(Map<String, dynamic> json) {
    return JsonNot(
      JsonSchema.fromJson(json['not'] as Map<String, dynamic>),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'not': schema.toJson(),
    };
  }
}
