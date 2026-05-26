const _jsonSchemaAnnotationKeys = {'title', 'description', 'default'};

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
    return _fromJson(json);
  }

  static JsonSchema _fromJson(Map<String, dynamic> json) {
    if (JsonEnum._canParse(json)) {
      return JsonEnum.fromJson(json);
    }

    final conjunctiveSchema = _splitConjunctiveSchema(json);
    if (conjunctiveSchema != null) {
      return conjunctiveSchema;
    }

    if (json.containsKey('const')) {
      return JsonConst.fromJson(json);
    }
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
    if (type is List) {
      if (!_isValidJsonTypeArray(type)) {
        return JsonAny.fromJson(json);
      }
      return JsonUnion.fromJson(json);
    }
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

  static JsonSchema? _splitConjunctiveSchema(Map<String, dynamic> json) {
    final primaryKeys = _primaryKeysForConjunctiveSplit(json);
    if (primaryKeys == null) {
      return null;
    }

    final siblingKeys = json.keys
        .where(
          (key) =>
              !primaryKeys.contains(key) &&
              !_jsonSchemaAnnotationKeys.contains(key),
        )
        .toSet();
    if (siblingKeys.isEmpty) {
      return null;
    }

    // JSON Schema keywords are conjunctive: a schema such as
    // `{type: ['string', 'null'], enum: ['auto', null]}` means both the
    // type-array assertion and the enum assertion apply. Preserve the official
    // wire shape instead of rewriting it into allOf or a typed convenience
    // schema; JsonAny preserves the keywords and the validator enforces the
    // supported assertions.
    return JsonAny.fromJson(json);
  }

  static Set<String>? _primaryKeysForConjunctiveSplit(
    Map<String, dynamic> json,
  ) {
    if (json.containsKey('const')) {
      return {'const'};
    }

    if (json['type'] is List) {
      return {'type'};
    }

    final type = json['type'];
    if (type is String && json['enum'] is List) {
      final enumValues = json['enum'] as List;
      if (type != 'string' || !enumValues.every((value) => value is String)) {
        return {'type'};
      }
    }

    for (final keyword in const ['allOf', 'anyOf', 'oneOf', 'not']) {
      if (json.containsKey(keyword)) {
        return {keyword};
      }
    }

    if (json['type'] == null) {
      final enumKeys = <String>{};
      if (json['enum'] is List) {
        enumKeys.add('enum');
      }
      if (json['values'] is List) {
        enumKeys.add('values');
      }
      if (enumKeys.isNotEmpty) {
        if (json['enumNames'] is List) {
          enumKeys.add('enumNames');
        }
        return enumKeys;
      }
    }

    return null;
  }

  static bool _isValidJsonTypeArray(List<dynamic> types) {
    if (types.isEmpty) {
      return false;
    }
    final seen = <String>{};
    for (final type in types) {
      if (type is! String ||
          !_knownJsonTypes.contains(type) ||
          !seen.add(type)) {
        return false;
      }
    }
    return true;
  }

  static const Set<String> _knownJsonTypes = {
    'string',
    'number',
    'integer',
    'boolean',
    'null',
    'array',
    'object',
  };

  static bool _hasOnlyAnnotationAnd(
    Map<String, dynamic> json,
    Set<String> keys,
  ) {
    return json.keys.every(
      (key) => keys.contains(key) || _jsonSchemaAnnotationKeys.contains(key),
    );
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

  /// Creates a const schema that accepts exactly [value].
  static JsonConst constValue(
    dynamic value, {
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonConst(
      value,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }

  /// Creates a union schema that accepts any one of [schemas].
  static JsonUnion union(
    List<JsonSchema> schemas, {
    String? title,
    String? description,
    dynamic defaultValue,
  }) {
    return JsonUnion(
      schemas,
      title: title,
      description: description,
      defaultValue: defaultValue,
    );
  }
}

/// A schema for string values.
class JsonString extends JsonSchema {
  final bool _hasDefault;
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
  }) : _hasDefault = defaultValue != null;

  const JsonString._({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.format,
    this.enumValues,
    this.enumNames,
    super.title,
    super.description,
    this.defaultValue,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final String? defaultValue;

  factory JsonString.fromJson(Map<String, dynamic> json) {
    return JsonString._(
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
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
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
  final bool _hasDefault;
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
  }) : _hasDefault = defaultValue != null;

  const JsonNumber._({
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final num? defaultValue;

  factory JsonNumber.fromJson(Map<String, dynamic> json) {
    return JsonNumber._(
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
      exclusiveMinimum: json['exclusiveMinimum'] as num?,
      exclusiveMaximum: json['exclusiveMaximum'] as num?,
      multipleOf: json['multipleOf'] as num?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as num?,
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
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
  final bool _hasDefault;
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
  }) : _hasDefault = defaultValue != null;

  const JsonInteger._({
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final int? defaultValue;

  factory JsonInteger.fromJson(Map<String, dynamic> json) {
    return JsonInteger._(
      minimum: json['minimum'] as int?,
      maximum: json['maximum'] as int?,
      exclusiveMinimum: json['exclusiveMinimum'] as int?,
      exclusiveMaximum: json['exclusiveMaximum'] as int?,
      multipleOf: json['multipleOf'] as int?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as int?,
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
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
  final bool _hasDefault;

  const JsonBoolean({
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonBoolean._({
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final bool? defaultValue;

  factory JsonBoolean.fromJson(Map<String, dynamic> json) {
    return JsonBoolean._(
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as bool?,
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'type': 'boolean',
    };
  }
}

/// A schema for null values.
class JsonNull extends JsonSchema {
  final bool _hasDefault;

  const JsonNull({
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonNull._({
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonNull.fromJson(Map<String, dynamic> json) {
    return JsonNull._(
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'type': 'null',
    };
  }
}

/// A schema for array values.
class JsonArray extends JsonSchema {
  final bool _hasDefault;
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
  }) : _hasDefault = defaultValue != null;

  const JsonArray._({
    this.items,
    this.minItems,
    this.maxItems,
    this.uniqueItems,
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final List<dynamic>? defaultValue;

  factory JsonArray.fromJson(Map<String, dynamic> json) {
    return JsonArray._(
      items: json['items'] != null
          ? JsonSchema.fromJson(json['items'] as Map<String, dynamic>)
          : null,
      minItems: json['minItems'] as int?,
      maxItems: json['maxItems'] as int?,
      uniqueItems: json['uniqueItems'] as bool?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as List<dynamic>?,
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final itemSchema = items;
    final serializedItems = itemSchema == null
        ? null
        : switch (itemSchema) {
            final JsonEnum enumItems => enumItems._toJson(
                titledStringConstListKeyword: 'anyOf',
              ),
            final JsonSchema schema => schema.toJson(),
          };

    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'type': 'array',
      if (serializedItems != null) 'items': serializedItems,
      if (minItems != null) 'minItems': minItems,
      if (maxItems != null) 'maxItems': maxItems,
      if (uniqueItems != null) 'uniqueItems': uniqueItems,
    };
  }
}

/// A schema for object values.
class JsonObject extends JsonSchema {
  final bool _hasDefault;
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
  }) : _hasDefault = defaultValue != null;

  const JsonObject._({
    this.properties,
    this.required,
    this.additionalProperties,
    this.dependentRequired,
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final Map<String, dynamic>? defaultValue;

  factory JsonObject.fromJson(Map<String, dynamic> json) {
    final additionalProps = json['additionalProperties'];
    Object? parsedAdditionalProps;
    if (additionalProps is bool) {
      parsedAdditionalProps = additionalProps;
    } else if (additionalProps is Map) {
      parsedAdditionalProps = JsonSchema.fromJson(
        Map<String, dynamic>.from(additionalProps),
      );
    }

    return JsonObject._(
      properties: (json['properties'] as Map<String, dynamic>?)?.map(
        (key, value) =>
            MapEntry(key, JsonSchema.fromJson(value as Map<String, dynamic>)),
      ),
      required: (json['required'] as List?)?.cast<String>(),
      additionalProperties: parsedAdditionalProps,
      dependentRequired: (json['dependentRequired'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, (value as List).cast<String>())),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'] as Map<String, dynamic>?,
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
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
  final bool _hasDefault;

  const JsonAny([
    this.properties = const {},
    String? title,
    String? description,
    this.defaultValue,
  ])  : _hasDefault = defaultValue != null,
        super(title: title, description: description);

  const JsonAny._(
    this.properties,
    String? title,
    String? description,
    this.defaultValue, {
    required bool hasDefault,
  })  : _hasDefault = hasDefault,
        super(title: title, description: description);

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

    return JsonAny._(
      Map.unmodifiable(properties),
      title,
      description,
      defaultValue,
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      ...properties,
    };
  }
}

/// A schema that accepts exactly one JSON value.
class JsonConst extends JsonSchema {
  final bool _hasDefault;
  final dynamic value;

  const JsonConst(
    this.value, {
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonConst._(
    this.value, {
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonConst.fromJson(Map<String, dynamic> json) {
    return JsonConst._(
      json['const'],
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'const': value,
    };
  }
}

/// A schema that validates against any one of the given schemas.
class JsonUnion extends JsonSchema {
  final bool _hasDefault;
  final List<JsonSchema> schemas;

  const JsonUnion(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonUnion._(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonUnion.fromJson(Map<String, dynamic> json) {
    final types = json['type'] as List;
    final commonKeys = {'type', 'title', 'description', 'default'};
    final schemaProperties = Map<String, dynamic>.from(json)
      ..removeWhere((key, value) => commonKeys.contains(key));

    return JsonUnion._(
      types.whereType<String>().map((type) {
        return JsonSchema.fromJson({
          ...schemaProperties,
          'type': type,
        });
      }).toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final typeNames = _typeNamesForTypeOnlySchemas();

    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      if (typeNames != null)
        'type': typeNames
      else
        'anyOf': schemas.map((schema) => schema.toJson()).toList(),
    };
  }

  List<String>? _typeNamesForTypeOnlySchemas() {
    final typeNames = <String>[];
    for (final schema in schemas) {
      final typeName = _typeNameForTypeOnlySchema(schema);
      if (typeName == null) {
        return null;
      }
      typeNames.add(typeName);
    }
    return typeNames;
  }

  String? _typeNameForTypeOnlySchema(JsonSchema schema) {
    if (schema.title != null ||
        schema.description != null ||
        schema.defaultValue != null) {
      return null;
    }

    return switch (schema) {
      JsonString(
        minLength: null,
        maxLength: null,
        pattern: null,
        format: null,
        enumValues: null,
        enumNames: null,
      ) =>
        'string',
      JsonNumber(
        minimum: null,
        maximum: null,
        exclusiveMinimum: null,
        exclusiveMaximum: null,
        multipleOf: null,
      ) =>
        'number',
      JsonInteger(
        minimum: null,
        maximum: null,
        exclusiveMinimum: null,
        exclusiveMaximum: null,
        multipleOf: null,
      ) =>
        'integer',
      JsonBoolean _ => 'boolean',
      JsonNull _ => 'null',
      JsonArray(
        items: null,
        minItems: null,
        maxItems: null,
        uniqueItems: null,
      ) =>
        'array',
      JsonObject(
        properties: null,
        required: null,
        additionalProperties: null,
        dependentRequired: null,
      ) =>
        'object',
      _ => null,
    };
  }
}

/// A schema that validates against all of the given schemas.
class JsonAllOf extends JsonSchema {
  final bool _hasDefault;
  final List<JsonSchema> schemas;

  const JsonAllOf(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonAllOf._(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonAllOf.fromJson(Map<String, dynamic> json) {
    return JsonAllOf._(
      (json['allOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'allOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against any of the given schemas.
class JsonAnyOf extends JsonSchema {
  final bool _hasDefault;
  final List<JsonSchema> schemas;

  const JsonAnyOf(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonAnyOf._(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonAnyOf.fromJson(Map<String, dynamic> json) {
    return JsonAnyOf._(
      (json['anyOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'anyOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against exactly one of the given schemas.
class JsonOneOf extends JsonSchema {
  final bool _hasDefault;
  final List<JsonSchema> schemas;

  const JsonOneOf(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonOneOf._(
    this.schemas, {
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonOneOf.fromJson(Map<String, dynamic> json) {
    return JsonOneOf._(
      (json['oneOf'] as List)
          .map((e) => JsonSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'oneOf': schemas.map((s) => s.toJson()).toList(),
    };
  }
}

/// A schema that validates against none of the given schemas.
class JsonNot extends JsonSchema {
  final bool _hasDefault;
  final JsonSchema schema;

  const JsonNot(
    this.schema, {
    this.defaultValue,
    super.title,
    super.description,
  }) : _hasDefault = defaultValue != null;

  const JsonNot._(
    this.schema, {
    this.defaultValue,
    super.title,
    super.description,
    required bool hasDefault,
  }) : _hasDefault = hasDefault;

  @override
  final dynamic defaultValue;

  factory JsonNot.fromJson(Map<String, dynamic> json) {
    return JsonNot._(
      JsonSchema.fromJson(json['not'] as Map<String, dynamic>),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
      'not': schema.toJson(),
    };
  }
}

/// A schema for enum values.
class JsonEnum extends JsonSchema {
  final bool _hasDefault;
  final List<dynamic> values;
  final String? _constListKeyword;
  final String? _constListType;
  final String? _enumValuesKeyword;
  final dynamic _enumTypeKeyword;

  const JsonEnum(
    this.values, {
    this.defaultValue,
    super.title,
    super.description,
  })  : _hasDefault = defaultValue != null,
        _constListKeyword = null,
        _constListType = null,
        _enumValuesKeyword = null,
        _enumTypeKeyword = null;

  const JsonEnum._(
    this.values, {
    this.defaultValue,
    super.title,
    super.description,
    String? constListKeyword,
    String? constListType,
    String? enumValuesKeyword,
    dynamic enumTypeKeyword,
    required bool hasDefault,
  })  : _hasDefault = hasDefault,
        _constListKeyword = constListKeyword,
        _constListType = constListType,
        _enumValuesKeyword = enumValuesKeyword,
        _enumTypeKeyword = enumTypeKeyword;

  @override
  final dynamic defaultValue;

  /// The canonical values accepted by this enum schema.
  List<dynamic> get normalizedValues =>
      values.map((value) => _normalizeEntry(value).value).toList();

  static bool _canParse(Map<String, dynamic> json) {
    final type = json['type'];
    if (type == 'enum') {
      return true;
    }
    if (type == null && (json['enum'] is List || json['values'] is List)) {
      return JsonSchema._hasOnlyAnnotationAnd(
        json,
        {'enum', 'values', 'enumNames'},
      );
    }

    final constListKey = _constSchemaListKey(json);
    if ((type == null || type == 'string') && constListKey != null) {
      if (!JsonSchema._hasOnlyAnnotationAnd(json, {'type', constListKey})) {
        return false;
      }
      if (type == 'string' &&
          !_constSchemaListValuesAreStrings(json[constListKey])) {
        return false;
      }
      if (constListKey == 'oneOf' &&
          !_constSchemaListValuesAreUnique(json[constListKey])) {
        return false;
      }
      return true;
    }
    return false;
  }

  factory JsonEnum.fromJson(Map<String, dynamic> json) {
    final constListKey = _constSchemaListKey(json);
    final enumValuesKeyword = json['values'] is List
        ? 'values'
        : json['enum'] is List
            ? 'enum'
            : null;

    return JsonEnum._(
      _parseValues(json),
      title: json['title'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      hasDefault: json.containsKey('default'),
      constListKeyword: constListKey,
      constListType: constListKey != null ? json['type'] as String? : null,
      enumValuesKeyword: enumValuesKeyword,
      enumTypeKeyword: enumValuesKeyword != null && json.containsKey('type')
          ? json['type']
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => _toJson();

  Map<String, dynamic> _toJson({
    String titledStringConstListKeyword = 'oneOf',
  }) {
    final normalizedEntries =
        values.map((value) => _normalizeEntry(value)).toList(growable: false);
    final hasTitles = normalizedEntries.any((entry) => entry.title != null);
    final allStrings = normalizedEntries.every(
      (entry) => entry.value is String,
    );

    final annotations = {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (_hasDefault) 'default': defaultValue,
    };

    final constListKeyword = _constListKeyword;
    if (constListKeyword != null) {
      return {
        ...annotations,
        if (_constListType != null) 'type': _constListType,
        constListKeyword: normalizedEntries
            .map(
              (entry) => {
                'const': entry.value,
                if (entry.title != null) 'title': entry.title,
                if (entry.description != null) 'description': entry.description,
                if (entry.hasDefault) 'default': entry.defaultValue,
              },
            )
            .toList(),
      };
    }

    if (hasTitles) {
      return {
        ...annotations,
        if (allStrings) 'type': 'string',
        titledStringConstListKeyword: normalizedEntries
            .map(
              (entry) => {
                'const': entry.value,
                if (entry.title != null) 'title': entry.title,
                if (entry.description != null) 'description': entry.description,
                if (entry.hasDefault) 'default': entry.defaultValue,
              },
            )
            .toList(),
      };
    }

    final enumValuesKeyword = _enumValuesKeyword;
    if (enumValuesKeyword != null) {
      return {
        ...annotations,
        if (_enumTypeKeyword != null) 'type': _enumTypeKeyword,
        enumValuesKeyword:
            normalizedEntries.map((entry) => entry.value).toList(),
      };
    }

    return {
      ...annotations,
      if (allStrings) 'type': 'string',
      if (allStrings)
        'enum': normalizedEntries.map((entry) => entry.value as String).toList()
      else
        'enum': normalizedEntries.map((entry) => entry.value).toList(),
    };
  }

  static List<dynamic> _parseValues(Map<String, dynamic> json) {
    final legacyValues = json['values'];
    if (legacyValues is List) {
      return List<dynamic>.from(legacyValues);
    }

    final enumValues = json['enum'];
    if (enumValues is List) {
      final enumNames = json['enumNames'];
      if (enumNames is List && enumNames.length == enumValues.length) {
        return List<dynamic>.generate(enumValues.length, (index) {
          final value = enumValues[index];
          final title = enumNames[index];
          if (title is String && title != '$value') {
            return {'value': value, 'title': title};
          }
          return value;
        });
      }

      return List<dynamic>.from(enumValues);
    }

    final constValues = json['oneOf'] ?? json['anyOf'];
    if (constValues is List) {
      return constValues.map((entry) {
        if (entry is Map && entry.containsKey('const')) {
          final value = entry['const'];
          final title = entry['title'];
          final description = entry['description'];
          if (title is String ||
              description is String ||
              entry.containsKey('default')) {
            return {
              'value': value,
              if (title is String) 'title': title,
              if (description is String) 'description': description,
              if (entry.containsKey('default')) 'default': entry['default'],
            };
          }
          return value;
        }

        return entry;
      }).toList();
    }

    return const [];
  }

  static String? _constSchemaListKey(Map<String, dynamic> json) {
    final hasOneOf = _isConstSchemaList(json['oneOf']);
    final hasAnyOf = _isConstSchemaList(json['anyOf']);
    if (hasOneOf == hasAnyOf) {
      return null;
    }
    return hasOneOf ? 'oneOf' : 'anyOf';
  }

  static bool _isConstSchemaList(dynamic schemaList) {
    return schemaList is List &&
        schemaList.isNotEmpty &&
        schemaList.every(
          (entry) =>
              entry is Map &&
              entry.containsKey('const') &&
              entry.keys.every(
                (key) =>
                    key is String &&
                    (key == 'const' || _jsonSchemaAnnotationKeys.contains(key)),
              ),
        );
  }

  static bool _constSchemaListValuesAreStrings(dynamic schemaList) {
    return schemaList is List &&
        schemaList.every((entry) => entry is Map && entry['const'] is String);
  }

  static bool _constSchemaListValuesAreUnique(dynamic schemaList) {
    if (schemaList is! List) {
      return false;
    }
    for (var i = 0; i < schemaList.length; i++) {
      final left = schemaList[i];
      if (left is! Map) {
        return false;
      }
      for (var j = i + 1; j < schemaList.length; j++) {
        final right = schemaList[j];
        if (right is! Map) {
          return false;
        }
        if (_jsonValuesEqual(left['const'], right['const'])) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _jsonValuesEqual(dynamic left, dynamic right) {
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var i = 0; i < left.length; i++) {
        if (!_jsonValuesEqual(left[i], right[i])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final key in left.keys) {
        if (!right.containsKey(key) ||
            !_jsonValuesEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  static ({
    dynamic value,
    String? title,
    String? description,
    bool hasDefault,
    dynamic defaultValue,
  }) _normalizeEntry(dynamic entry) {
    if (entry is Map && entry.containsKey('value')) {
      final title = entry['title'];
      final description = entry['description'];
      return (
        value: entry['value'],
        title: title is String ? title : null,
        description: description is String ? description : null,
        hasDefault: entry.containsKey('default'),
        defaultValue: entry['default'],
      );
    }

    return (
      value: entry,
      title: null,
      description: null,
      hasDefault: false,
      defaultValue: null,
    );
  }
}
