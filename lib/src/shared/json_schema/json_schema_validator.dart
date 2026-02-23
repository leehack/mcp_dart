import 'json_schema.dart';

/// Exception thrown when JSON schema validation fails.
class JsonSchemaValidationException implements Exception {
  final String message;
  final List<String> path;

  JsonSchemaValidationException(this.message, [this.path = const []]);

  @override
  String toString() =>
      "JsonSchemaValidationException: $message (at ${path.join('/')})";
}

/// Extension on [JsonSchema] to provide validation capability.
extension JsonSchemaValidation on JsonSchema {
  /// Validates [data] against this schema.
  ///
  /// See [JsonSchemaValidator] for more details.
  void validate(dynamic data) {
    _validate(this, data, []);
  }

  void _validate(JsonSchema schema, dynamic data, List<String> path) {
    // 1. Validate common keywords if they exist on specific types
    // Since JsonSchema is sealed, we switch on type.

    switch (schema) {
      case final JsonString s:
        _validateString(s, data, path);
      case final JsonNumber n:
        _validateNumber(n, data, path);
      case final JsonInteger i:
        _validateInteger(i, data, path);
      case JsonBoolean _:
        _validateBoolean(data, path);
      case JsonNull _:
        _validateNull(data, path);
      case final JsonArray a:
        _validateArray(a, data, path);
      case final JsonObject o:
        _validateObject(o, data, path);
      case final JsonEnum e:
        _validateEnum(e, data, path);
      case final JsonAllOf all:
        _validateAllOf(all, data, path);
      case final JsonAnyOf any:
        _validateAnyOf(any, data, path);
      case final JsonOneOf one:
        _validateOneOf(one, data, path);
      case final JsonNot not:
        _validateNot(not, data, path);
      case JsonAny _:
        // JsonAny validates everything, but might check for specific properties if any
        // The implementation has 'properties' map, but it's unstructured.
        break;
    }
  }

  void _validateString(JsonString schema, dynamic data, List<String> path) {
    if (data is! String) {
      throw JsonSchemaValidationException(
        'Expected string, got ${data.runtimeType}',
        path,
      );
    }

    if (schema.minLength != null) {
      if (data.length < schema.minLength!) {
        throw JsonSchemaValidationException(
          'Length must be >= ${schema.minLength}',
          path,
        );
      }
    }

    if (schema.maxLength != null) {
      if (data.length > schema.maxLength!) {
        throw JsonSchemaValidationException(
          'Length must be <= ${schema.maxLength}',
          path,
        );
      }
    }

    if (schema.pattern != null) {
      final pattern = RegExp(schema.pattern!);
      if (!pattern.hasMatch(data)) {
        throw JsonSchemaValidationException(
          'Value does not match pattern: ${schema.pattern}',
          path,
        );
      }
    }

    if (schema.enumValues != null) {
      if (!schema.enumValues!.contains(data)) {
        throw JsonSchemaValidationException(
          'Value must be one of ${schema.enumValues}',
          path,
        );
      }
    }
  }

  void _validateNumber(JsonNumber schema, dynamic data, List<String> path) {
    if (data is! num) {
      throw JsonSchemaValidationException(
        'Expected number, got ${data.runtimeType}',
        path,
      );
    }

    if (schema.minimum != null && data < schema.minimum!) {
      throw JsonSchemaValidationException(
        'Value must be >= ${schema.minimum}',
        path,
      );
    }

    if (schema.maximum != null && data > schema.maximum!) {
      throw JsonSchemaValidationException(
        'Value must be <= ${schema.maximum}',
        path,
      );
    }

    if (schema.exclusiveMinimum != null && data <= schema.exclusiveMinimum!) {
      throw JsonSchemaValidationException(
        'Value must be > ${schema.exclusiveMinimum}',
        path,
      );
    }

    if (schema.exclusiveMaximum != null && data >= schema.exclusiveMaximum!) {
      throw JsonSchemaValidationException(
        'Value must be < ${schema.exclusiveMaximum}',
        path,
      );
    }

    if (schema.multipleOf != null) {
      if ((data % schema.multipleOf!).abs() > 1e-10) {
        throw JsonSchemaValidationException(
          'Value must be multiple of ${schema.multipleOf}',
          path,
        );
      }
    }
  }

  void _validateInteger(JsonInteger schema, dynamic data, List<String> path) {
    if (data is! int) {
      throw JsonSchemaValidationException(
        'Expected integer, got ${data.runtimeType}',
        path,
      );
    }

    if (schema.minimum != null && data < schema.minimum!) {
      throw JsonSchemaValidationException(
        'Value must be >= ${schema.minimum}',
        path,
      );
    }

    if (schema.maximum != null && data > schema.maximum!) {
      throw JsonSchemaValidationException(
        'Value must be <= ${schema.maximum}',
        path,
      );
    }

    if (schema.exclusiveMinimum != null && data <= schema.exclusiveMinimum!) {
      throw JsonSchemaValidationException(
        'Value must be > ${schema.exclusiveMinimum}',
        path,
      );
    }

    if (schema.exclusiveMaximum != null && data >= schema.exclusiveMaximum!) {
      throw JsonSchemaValidationException(
        'Value must be < ${schema.exclusiveMaximum}',
        path,
      );
    }

    if (schema.multipleOf != null) {
      if ((data % schema.multipleOf!).abs() > 0) {
        throw JsonSchemaValidationException(
          'Value must be multiple of ${schema.multipleOf}',
          path,
        );
      }
    }
  }

  void _validateBoolean(dynamic data, List<String> path) {
    if (data is! bool) {
      throw JsonSchemaValidationException(
        'Expected boolean, got ${data.runtimeType}',
        path,
      );
    }
  }

  void _validateNull(dynamic data, List<String> path) {
    if (data != null) {
      throw JsonSchemaValidationException(
        'Expected null, got ${data.runtimeType}',
        path,
      );
    }
  }

  void _validateArray(JsonArray schema, dynamic data, List<String> path) {
    if (data is! List) {
      throw JsonSchemaValidationException(
        'Expected array, got ${data.runtimeType}',
        path,
      );
    }

    if (schema.minItems != null && data.length < schema.minItems!) {
      throw JsonSchemaValidationException(
        'Array length must be >= ${schema.minItems}',
        path,
      );
    }

    if (schema.maxItems != null && data.length > schema.maxItems!) {
      throw JsonSchemaValidationException(
        'Array length must be <= ${schema.maxItems}',
        path,
      );
    }

    if (schema.uniqueItems == true) {
      if (!_hasUniqueItems(data)) {
        throw JsonSchemaValidationException(
          'Array must have unique items',
          path,
        );
      }
    }

    if (schema.items != null) {
      for (var i = 0; i < data.length; i++) {
        _validate(schema.items!, data[i], [...path, '$i']);
      }
    }
  }

  void _validateObject(JsonObject schema, dynamic data, List<String> path) {
    if (data is! Map) {
      throw JsonSchemaValidationException(
        'Expected object, got ${data.runtimeType}',
        path,
      );
    }

    if (schema.required != null) {
      for (final key in schema.required!) {
        if (!data.containsKey(key)) {
          throw JsonSchemaValidationException(
            'Missing required property: $key',
            path,
          );
        }
      }
    }

    if (schema.dependentRequired != null) {
      for (final key in schema.dependentRequired!.keys) {
        if (data.containsKey(key)) {
          final required = schema.dependentRequired![key]!;
          for (final reqKey in required) {
            if (!data.containsKey(reqKey)) {
              throw JsonSchemaValidationException(
                'Dependency failed: $key requires $reqKey',
                path,
              );
            }
          }
        }
      }
    }

    // Properties validation
    if (schema.properties != null) {
      for (final key in schema.properties!.keys) {
        if (data.containsKey(key)) {
          _validate(schema.properties![key]!, data[key], [...path, key]);
        }
      }
    }

    // Additional properties
    final definedKeys = schema.properties?.keys.toSet() ?? {};
    final dataKeys = data.keys.cast<String>().toSet();
    final extraKeys = dataKeys.difference(definedKeys);

    // additionalProperties can be bool or JsonSchema
    if (schema.additionalProperties == false && extraKeys.isNotEmpty) {
      throw JsonSchemaValidationException(
        'Additional properties not allowed: ${extraKeys.join(', ')}',
        path,
      );
    }
    // When additionalProperties is a JsonSchema, validate each extra key against it
    if (schema.additionalProperties is JsonSchema && extraKeys.isNotEmpty) {
      final apSchema = schema.additionalProperties as JsonSchema;
      for (final key in extraKeys) {
        _validate(apSchema, data[key], [...path, key]);
      }
    }
  }

  void _validateEnum(JsonEnum schema, dynamic data, List<String> path) {
    if (!schema.values.any((e) => _deepEquals(e, data))) {
      throw JsonSchemaValidationException(
        'Value must be one of ${schema.values}',
        path,
      );
    }
  }

  void _validateAllOf(JsonAllOf schema, dynamic data, List<String> path) {
    for (final subSchema in schema.schemas) {
      _validate(subSchema, data, path);
    }
  }

  void _validateAnyOf(JsonAnyOf schema, dynamic data, List<String> path) {
    bool isValid = false;
    for (final subSchema in schema.schemas) {
      try {
        _validate(subSchema, data, path);
        isValid = true;
        break;
      } catch (_) {}
    }
    if (!isValid) {
      throw JsonSchemaValidationException(
        'Value does not match anyOf schemas',
        path,
      );
    }
  }

  void _validateOneOf(JsonOneOf schema, dynamic data, List<String> path) {
    int validCount = 0;
    for (final subSchema in schema.schemas) {
      try {
        _validate(subSchema, data, path);
        validCount++;
      } catch (_) {}
    }
    if (validCount != 1) {
      throw JsonSchemaValidationException(
        'Value matches $validCount schemas, expected exactly 1 for oneOf',
        path,
      );
    }
  }

  void _validateNot(JsonNot schema, dynamic data, List<String> path) {
    try {
      _validate(schema.schema, data, path);
    } catch (_) {
      return;
    }
    throw JsonSchemaValidationException(
      'Value matches not schema',
      path,
    );
  }

  bool _hasUniqueItems(List data) {
    for (var i = 0; i < data.length; i++) {
      for (var j = i + 1; j < data.length; j++) {
        if (_deepEquals(data[i], data[j])) {
          return false;
        }
      }
    }
    return true;
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == b) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    return false;
  }
}
