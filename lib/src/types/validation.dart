double? readUnitDouble(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw FormatException('$field must be a number between 0 and 1');
  }
  final result = value.toDouble();
  if (result < 0 || result > 1) {
    throw FormatException('$field must be between 0 and 1');
  }
  return result;
}

void validateUnitDouble(double? value, String field) {
  if (value == null) {
    return;
  }
  if (value < 0 || value > 1) {
    throw ArgumentError.value(value, field, 'must be between 0 and 1');
  }
}

int? readOptionalInteger(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw FormatException('$field must be an integer');
}

String? readOptionalString(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('$field must be a string');
}

int? readOptionalTtlMs(Object? value, String field) {
  final ttlMs = readOptionalInteger(value, field);
  if (ttlMs == null) {
    return null;
  }
  return ttlMs < 0 ? 0 : ttlMs;
}

void validateTtlMs(int? value, String field) {
  if (value == null) {
    return;
  }
  if (value < 0) {
    throw ArgumentError.value(
      value,
      field,
      'must be greater than or equal to 0',
    );
  }
}

String? readOptionalCacheScope(Object? value, String field) {
  final scope = readOptionalString(value, field);
  if (scope == null) {
    return null;
  }
  if (scope == 'public' || scope == 'private') {
    return scope;
  }
  throw FormatException('$field must be either "public" or "private"');
}

void validateCacheScope(String? value, String field) {
  if (value == null) {
    return;
  }
  if (value != 'public' && value != 'private') {
    throw ArgumentError.value(
      value,
      field,
      'must be either "public" or "private"',
    );
  }
}

Object? readJsonValue(Object? value, String field) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw FormatException('$field must be a finite JSON number');
    }
    return value;
  }
  if (value is List) {
    return value.map((item) => readJsonValue(item, '$field[]')).toList();
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw FormatException('$field must be a JSON object with string keys');
    }
    return {
      for (final entry in value.entries)
        entry.key as String: readJsonValue(
          entry.value,
          '$field.${entry.key}',
        ),
    };
  }
  throw FormatException('$field must be a JSON value');
}
