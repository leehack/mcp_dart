/// A builder for creating JSON Schemas in a type-safe way.
sealed class JsonSchema {
  final String? title;
  final String? description;

  /// The default value for this schema.
  ///
  /// The type of this value depends on the schema type (e.g., [String] for [JsonString],
  /// [int] for [JsonInteger], etc.).
  dynamic get defaultValue;

  const JsonSchema({this.title, this.description});

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
        case 'enum':
          return JsonEnum.fromJson(json);
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
    List<String>? enumNames,
    String? title,
    String? description,
    String? defaultValue,
  }) {
    return JsonString(
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
      format: format,
      enumValues: enumValues,
      enumNames: enumNames,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates a number schema.
  static JsonNumber number({
    num? minimum,
    num? maximum,
    num? exclusiveMinimum,
    num? exclusiveMaximum,
    num? multipleOf,
    String? title,
    String? description,
    num? defaultValue,
  }) {
    return JsonNumber(
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      multipleOf: multipleOf,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates an integer schema.
  static JsonInteger integer({
    int? minimum,
    int? maximum,
    int? exclusiveMinimum,
    int? exclusiveMaximum,
    int? multipleOf,
    String? title,
    String? description,
    int? defaultValue,
  }) {
    return JsonInteger(
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      multipleOf: multipleOf,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates a boolean schema.
  static JsonBoolean boolean({
    String? title,
    String? description,
    bool? defaultValue,
  }) {
    return JsonBoolean(
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates a null schema.
  static JsonNull nullValue({
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonNull(
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates an array schema.
  static JsonArray array({
    JsonSchema? items,
    int? minItems,
    int? maxItems,
    bool? uniqueItems,
    String? title,
    String? description,
    List<dynamic>? defaultValue,
  }) {
    return JsonArray(
      items: items,
      minItems: minItems,
      maxItems: maxItems,
      uniqueItems: uniqueItems,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates an object schema.
  static JsonObject object({
    Map<String, JsonSchema>? properties,
    List<String>? required,
    Object? additionalProperties,
    Map<String, List<String>>? dependentRequired,
    String? title,
    String? description,
    Map<String, dynamic>? defaultValue,
  }) {
    return JsonObject(
      properties: properties,
      required: required,
      additionalProperties: additionalProperties,
      dependentRequired: dependentRequired,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates an allOf schema.
  static JsonAllOf allOf(
    List<JsonSchema> schemas, {
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonAllOf(
      schemas,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates an anyOf schema.
  static JsonAnyOf anyOf(
    List<JsonSchema> schemas, {
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonAnyOf(
      schemas,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates a oneOf schema.
  static JsonOneOf oneOf(
    List<JsonSchema> schemas, {
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonOneOf(
      schemas,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates a not schema.
  static JsonNot not(
    JsonSchema schema, {
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonNot(
      schema,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }
}

/// A schema for string values.
class JsonString extends JsonSchema {
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final String? format;
  final List<String>? enumValues;

  /// (Legacy) Display names for enum values.
  /// Non-standard according to JSON schema 2020-12.
  final List<String>? enumNames;

  const JsonString({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.format,
    this.enumValues,
    this.enumNames,
    super.title,
    super.description,
    this.defaultValue,
  });

  @override
  final String? defaultValue;

  factory JsonString.fromJson(Map<String, dynamic> json) {
    return JsonString(
      minLength: json['minLength'] as int?,
      maxLength: json['maxLength'] as int?,
      pattern: json['pattern'] as String?,
      format: json['format'] as String?,
      enumValues: (json['enum'] as List?)?.cast<String>() ??
          (json['values'] as List?)?.cast<String>(),
      enumNames: (json['enumNames'] as List?)?.cast<String>(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'string',
      if (minLength != null) 'minLength': minLength,
      if (maxLength != null) 'maxLength': maxLength,
      if (pattern != null) 'pattern': pattern,
      if (format != null) 'format': format,
      if (enumValues != null) 'enum': enumValues,
      if (enumNames != null) 'enumNames': enumNames,
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
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final num? defaultValue;

  factory JsonNumber.fromJson(Map<String, dynamic> json) {
    return JsonNumber(
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
      exclusiveMinimum: json['exclusiveMinimum'] as num?,
      exclusiveMaximum: json['exclusiveMaximum'] as num?,
      multipleOf: json['multipleOf'] as num?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as num?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
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
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final int? defaultValue;

  factory JsonInteger.fromJson(Map<String, dynamic> json) {
    return JsonInteger(
      minimum: json['minimum'] as int?,
      maximum: json['maximum'] as int?,
      exclusiveMinimum: json['exclusiveMinimum'] as int?,
      exclusiveMaximum: json['exclusiveMaximum'] as int?,
      multipleOf: json['multipleOf'] as int?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as int?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
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
  const JsonBoolean({
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final bool? defaultValue;

  factory JsonBoolean.fromJson(Map<String, dynamic> json) {
    return JsonBoolean(
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'boolean',
    };
  }
}

/// A schema for null values.
class JsonNull extends JsonSchema {
  const JsonNull({
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final dynamic defaultValue;

  factory JsonNull.fromJson(Map<String, dynamic> json) {
    return JsonNull(
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'null',
    };
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
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final List<dynamic>? defaultValue;

  factory JsonArray.fromJson(Map<String, dynamic> json) {
    return JsonArray(
      items: json['items'] != null
          ? JsonSchema.fromJson(json['items'] as Map<String, dynamic>)
          : null,
      minItems: json['minItems'] as int?,
      maxItems: json['maxItems'] as int?,
      uniqueItems: json['uniqueItems'] as bool?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as List<dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
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

  /// Can be a [bool] (true/false) or a [JsonSchema] constraining extra properties.
  final Object? additionalProperties;
  final Map<String, List<String>>? dependentRequired;

  const JsonObject({
    this.properties,
    this.required,
    this.additionalProperties,
    this.dependentRequired,
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final Map<String, dynamic>? defaultValue;

  factory JsonObject.fromJson(Map<String, dynamic> json) {
    final additionalProps = json['additionalProperties'];
    Object? parsedAdditionalProps;
    if (additionalProps is bool) {
      parsedAdditionalProps = additionalProps;
    } else if (additionalProps is Map<String, dynamic>) {
      parsedAdditionalProps = JsonSchema.fromJson(additionalProps);
    }

    return JsonObject(
      properties: (json['properties'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(
          key,
          JsonSchema.fromJson(value as Map<String, dynamic>),
        ),
      ),
      required: (json['required'] as List?)?.cast<String>(),
      additionalProperties: parsedAdditionalProps,
      dependentRequired:
          (json['dependentRequired'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(
          key,
          (value as List).cast<String>(),
        ),
      ),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'object',
      if (properties != null)
        'properties': properties!.map((k, v) => MapEntry(k, v.toJson())),
      if (required != null && required!.isNotEmpty) 'required': required,
      if (additionalProperties != null)
        'additionalProperties': additionalProperties is JsonSchema
            ? (additionalProperties as JsonSchema).toJson()
            : additionalProperties,
      if (dependentRequired != null) 'dependentRequired': dependentRequired,
    };
  }
}

/// A schema that accepts any value, potentially with additional constraints not captured by other types.
class JsonAny extends JsonSchema {
  final Map<String, dynamic> properties;

  const JsonAny([
    this.properties = const {},
    String? title,
    String? description,
    this.defaultValue,
  ]) : super(
          title: title,
          description: description,
        );

  @override
  final dynamic defaultValue;

  factory JsonAny.fromJson(Map<String, dynamic> json) {
    String? title;
    String? description;
    dynamic defaultValue;
    final properties = <String, dynamic>{};

    for (final entry in json.entries) {
      switch (entry.key) {
        case 'title':
          title = entry.value as String?;
        case 'description':
          description = entry.value as String?;
        case 'default':
          defaultValue = entry.value;
        default:
          properties[entry.key] = entry.value;
      }
    }

    return JsonAny(
      Map.unmodifiable(properties),
      title,
      description,
      defaultValue,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      ...properties,
    };
  }
}

/// A schema that validates against all of the given schemas.
class JsonAllOf extends JsonSchema {
  final List<JsonSchema> schemas;

  const JsonAllOf(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final dynamic defaultValue;

  factory JsonAllOf.fromJson(Map<String, dynamic> json) {
    return JsonAllOf(
      (json['allOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'allOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against any of the given schemas.
class JsonAnyOf extends JsonSchema {
  final List<JsonSchema> schemas;

  const JsonAnyOf(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final dynamic defaultValue;

  factory JsonAnyOf.fromJson(Map<String, dynamic> json) {
    return JsonAnyOf(
      (json['anyOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'anyOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against exactly one of the given schemas.
class JsonOneOf extends JsonSchema {
  final List<JsonSchema> schemas;

  const JsonOneOf(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final dynamic defaultValue;

  factory JsonOneOf.fromJson(Map<String, dynamic> json) {
    return JsonOneOf(
      (json['oneOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'oneOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against none of the given schemas.
class JsonNot extends JsonSchema {
  final JsonSchema schema;

  const JsonNot(
    this.schema, {
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final dynamic defaultValue;

  factory JsonNot.fromJson(Map<String, dynamic> json) {
    return JsonNot(
      JsonSchema.fromJson(json['not'] as Map<String, dynamic>),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'not': schema.toJson(),
    };
  }
}

/// A schema for enum values.
class JsonEnum extends JsonSchema {
  final List<dynamic> values;

  const JsonEnum(
    this.values, {
    this.defaultValue,
    super.title,
    super.description,
  });

  @override
  final dynamic defaultValue;

  factory JsonEnum.fromJson(Map<String, dynamic> json) {
    return JsonEnum(
      json['values'] as List<dynamic>? ?? json['enum'] as List<dynamic>? ?? [],
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'enum',
      'values': values,
    };
  }
}
