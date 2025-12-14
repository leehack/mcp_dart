/// A simple JSON Schema validator interface.
abstract class JsonSchemaValidator {
  /// Validates [data] against the [schema].
  ///
  /// Returns `true` if valid, `false` otherwise.
  /// Throws [JsonSchemaValidationException] if validation fails and [throwOnError] is true.
  bool validate(Map<String, dynamic> schema, dynamic data);
}

/// Exception thrown when JSON schema validation fails.
class JsonSchemaValidationException implements Exception {
  final String message;
  final List<String> path;

  JsonSchemaValidationException(this.message, [this.path = const []]);

  @override
  String toString() =>
      "JsonSchemaValidationException: $message (at ${path.join('/')})";
}

/// A basic implementation of [JsonSchemaValidator] that supports common JSON Schema keywords.
class BasicJsonSchemaValidator implements JsonSchemaValidator {
  const BasicJsonSchemaValidator();

  @override
  bool validate(Map<String, dynamic> schema, dynamic data) {
    try {
      _validate(schema, data, []);
      return true;
    } catch (e) {
      if (e is JsonSchemaValidationException) {
        rethrow;
      }
      throw JsonSchemaValidationException(e.toString());
    }
  }

  void _validate(Map<String, dynamic> schema, dynamic data, List<String> path) {
    final type = schema['type'];
    if (type != null) {
      _validateType(type, data, path);
    }

    if (schema.containsKey('enum')) {
      final enumValues = schema['enum'] as List;
      if (!enumValues.any((e) => _deepEquals(e, data))) {
        throw JsonSchemaValidationException(
          'Value must be one of $enumValues',
          path,
        );
      }
    }

    if (schema.containsKey('const')) {
      if (!_deepEquals(data, schema['const'])) {
        throw JsonSchemaValidationException(
          'Value must be ${schema['const']}',
          path,
        );
      }
    }

    // Numeric validation
    if (data is num) {
      if (schema.containsKey('multipleOf')) {
        final multipleOf = schema['multipleOf'] as num;
        if ((data % multipleOf).abs() > 1e-10) {
          throw JsonSchemaValidationException(
            'Value must be multiple of $multipleOf',
            path,
          );
        }
      }
      if (schema.containsKey('maximum')) {
        if (data > (schema['maximum'] as num)) {
          throw JsonSchemaValidationException(
            'Value must be <= ${schema['maximum']}',
            path,
          );
        }
      }
      if (schema.containsKey('exclusiveMaximum')) {
        if (data >= (schema['exclusiveMaximum'] as num)) {
          throw JsonSchemaValidationException(
            'Value must be < ${schema['exclusiveMaximum']}',
            path,
          );
        }
      }
      if (schema.containsKey('minimum')) {
        if (data < (schema['minimum'] as num)) {
          throw JsonSchemaValidationException(
            'Value must be >= ${schema['minimum']}',
            path,
          );
        }
      }
      if (schema.containsKey('exclusiveMinimum')) {
        if (data <= (schema['exclusiveMinimum'] as num)) {
          throw JsonSchemaValidationException(
            'Value must be > ${schema['exclusiveMinimum']}',
            path,
          );
        }
      }
    }

    // String validation
    if (data is String) {
      if (schema.containsKey('maxLength')) {
        if (data.length > (schema['maxLength'] as int)) {
          throw JsonSchemaValidationException(
            'Length must be <= ${schema['maxLength']}',
            path,
          );
        }
      }
      if (schema.containsKey('minLength')) {
        if (data.length < (schema['minLength'] as int)) {
          throw JsonSchemaValidationException(
            'Length must be >= ${schema['minLength']}',
            path,
          );
        }
      }
      if (schema.containsKey('pattern')) {
        final pattern = RegExp(schema['pattern'] as String);
        if (!pattern.hasMatch(data)) {
          throw JsonSchemaValidationException(
            'Value does not match pattern: ${schema['pattern']}',
            path,
          );
        }
      }
    }

    // Array validation
    if (data is List) {
      if (schema.containsKey('maxItems')) {
        if (data.length > (schema['maxItems'] as int)) {
          throw JsonSchemaValidationException(
            'Array length must be <= ${schema['maxItems']}',
            path,
          );
        }
      }
      if (schema.containsKey('minItems')) {
        if (data.length < (schema['minItems'] as int)) {
          throw JsonSchemaValidationException(
            'Array length must be >= ${schema['minItems']}',
            path,
          );
        }
      }
      if (schema.containsKey('uniqueItems') &&
          (schema['uniqueItems'] as bool)) {
        if (!_hasUniqueItems(data)) {
          throw JsonSchemaValidationException(
            'Array must have unique items',
            path,
          );
        }
      }

      if (schema.containsKey('items')) {
        final itemsSchema = schema['items'] as Map<String, dynamic>;
        for (var i = 0; i < data.length; i++) {
          _validate(itemsSchema, data[i], [...path, '$i']);
        }
      }
    }

    // Object validation
    if (data is Map) {
      if (schema.containsKey('maxProperties')) {
        if (data.length > (schema['maxProperties'] as int)) {
          throw JsonSchemaValidationException(
            'Object property count must be <= ${schema['maxProperties']}',
            path,
          );
        }
      }
      if (schema.containsKey('minProperties')) {
        if (data.length < (schema['minProperties'] as int)) {
          throw JsonSchemaValidationException(
            'Object property count must be >= ${schema['minProperties']}',
            path,
          );
        }
      }
      if (schema.containsKey('dependentRequired')) {
        final dependentRequired =
            schema['dependentRequired'] as Map<String, dynamic>;
        for (final key in dependentRequired.keys) {
          if (data.containsKey(key)) {
            final required = (dependentRequired[key] as List).cast<String>();
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

      if (schema.containsKey('properties')) {
        final properties = schema['properties'] as Map<String, dynamic>;
        for (final key in properties.keys) {
          if (data.containsKey(key)) {
            _validate(properties[key], data[key], [...path, key]);
          }
        }
      }

      if (schema.containsKey('required')) {
        final required = (schema['required'] as List).cast<String>();
        for (final key in required) {
          if (!data.containsKey(key)) {
            throw JsonSchemaValidationException(
              'Missing required property: $key',
              path,
            );
          }
        }
      }
    }
  }

  void _validateType(dynamic type, dynamic data, List<String> path) {
    // type can be a string or a list of strings
    if (type is List) {
      bool isValid = false;
      for (final t in type) {
        try {
          _validateType(t, data, path);
          isValid = true;
          break;
        } catch (_) {}
      }
      if (!isValid) {
        throw JsonSchemaValidationException(
          'Value does not match any of types: $type',
          path,
        );
      }
      return;
    }

    switch (type) {
      case 'string':
        if (data is! String) {
          throw JsonSchemaValidationException(
            'Expected string, got ${data.runtimeType}',
            path,
          );
        }
        break;
      case 'number':
        if (data is! num) {
          throw JsonSchemaValidationException(
            'Expected number, got ${data.runtimeType}',
            path,
          );
        }
        break;
      case 'integer':
        if (data is! int) {
          throw JsonSchemaValidationException(
            'Expected integer, got ${data.runtimeType}',
            path,
          );
        }
        break;
      case 'boolean':
        if (data is! bool) {
          throw JsonSchemaValidationException(
            'Expected boolean, got ${data.runtimeType}',
            path,
          );
        }
        break;
      case 'object':
        if (data is! Map) {
          throw JsonSchemaValidationException(
            'Expected object, got ${data.runtimeType}',
            path,
          );
        }
        break;
      case 'array':
        if (data is! List) {
          throw JsonSchemaValidationException(
            'Expected array, got ${data.runtimeType}',
            path,
          );
        }
        break;
      case 'null':
        if (data != null) {
          throw JsonSchemaValidationException(
            'Expected null, got ${data.runtimeType}',
            path,
          );
        }
        break;
      default:
        // Ignore unknown types or let them pass? strict validation would fail.
        break;
    }
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
