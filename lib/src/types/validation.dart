import 'dart:convert';

import '../shared/uri_template.dart';

final _base64Pattern = RegExp(
  r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
);

String readRequiredString(Object? value, String field) {
  if (value is String) {
    return value;
  }
  throw FormatException('$field must be a string');
}

bool isAbsoluteUriString(String value) {
  return Uri.tryParse(value)?.hasScheme ?? false;
}

String readRequiredAbsoluteUriString(Object? value, String field) {
  final result = readRequiredString(value, field);
  if (!isAbsoluteUriString(result)) {
    throw FormatException('$field must be an absolute URI');
  }
  return result;
}

void validateAbsoluteUriString(String value, String field) {
  if (!isAbsoluteUriString(value)) {
    throw ArgumentError.value(value, field, 'must be an absolute URI');
  }
}

String readRequiredUriTemplateString(Object? value, String field) {
  final result = readRequiredString(value, field);
  try {
    UriTemplateExpander(result);
  } on ArgumentError catch (error) {
    throw FormatException(
      '$field must be a URI template: ${error.message}',
    );
  }
  return result;
}

void validateUriTemplateString(String value, String field) {
  try {
    UriTemplateExpander(value);
  } on ArgumentError catch (error) {
    throw ArgumentError.value(
        value,
        field,
        'must be a URI template: '
        '${error.message}');
  }
}

bool isBase64String(String value) {
  if (!_base64Pattern.hasMatch(value)) {
    return false;
  }
  try {
    base64.decode(value);
    return true;
  } on FormatException {
    return false;
  }
}

String readRequiredBase64String(Object? value, String field) {
  final result = readRequiredString(value, field);
  if (!isBase64String(result)) {
    throw FormatException('$field must be a base64-encoded string');
  }
  return result;
}

void validateBase64String(String value, String field) {
  if (!isBase64String(value)) {
    throw ArgumentError.value(
      value,
      field,
      'must be a base64-encoded string',
    );
  }
}

T readRequiredEnumValue<T extends Enum>(
  Object? value,
  Iterable<T> values,
  String field,
) {
  final name = readRequiredString(value, field);
  for (final enumValue in values) {
    if (enumValue.name == name) {
      return enumValue;
    }
  }
  final allowed = values.map((value) => '"${value.name}"').join(', ');
  throw FormatException('$field must be one of: $allowed');
}

T? readOptionalEnumValue<T extends Enum>(
  Object? value,
  Iterable<T> values,
  String field,
) {
  if (value == null) {
    return null;
  }
  return readRequiredEnumValue(value, values, field);
}

bool isRoleString(String value) {
  return value == 'user' || value == 'assistant';
}

String readRequiredRoleString(Object? value, String field) {
  final result = readRequiredString(value, field);
  if (!isRoleString(result)) {
    throw FormatException('$field must be "user" or "assistant"');
  }
  return result;
}

List<String>? readOptionalAnnotationAudience(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw FormatException('$field must be a list of roles');
  }
  return [
    for (final item in value) readRequiredRoleString(item, '$field items'),
  ];
}

void validateAnnotationAudience(List<String>? value, String field) {
  if (value == null) {
    return;
  }
  for (final item in value) {
    if (!isRoleString(item)) {
      throw ArgumentError.value(
        item,
        field,
        'items must be "user" or "assistant"',
      );
    }
  }
}

void validateAnnotationsObject(Map<String, dynamic>? value, String field) {
  if (value == null) {
    return;
  }
  readOptionalAnnotationAudience(value['audience'], '$field.audience');
  readUnitDouble(value['priority'], '$field.priority');
  readOptionalString(value['lastModified'], '$field.lastModified');
}

Map<String, dynamic>? readOptionalAnnotationsObject(
  Object? value,
  String field,
) {
  final result = readOptionalJsonObject(value, field);
  validateAnnotationsObject(result, field);
  return result;
}

double? readUnitDouble(Object? value, String field) {
  final number = readOptionalFiniteNumber(value, field);
  final result = number?.toDouble();
  if (result == null) {
    return null;
  }
  if (result < 0 || result > 1) {
    throw FormatException('$field must be between 0 and 1');
  }
  return result;
}

void validateUnitDouble(double? value, String field) {
  if (value == null) {
    return;
  }
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, field, 'must be between 0 and 1');
  }
}

num readFiniteNumber(Object? value, String field) {
  if (value is num && value.isFinite) {
    return value;
  }
  throw FormatException('$field must be a finite JSON number');
}

num? readOptionalFiniteNumber(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return readFiniteNumber(value, field);
}

double? readOptionalFiniteDouble(Object? value, String field) {
  return readOptionalFiniteNumber(value, field)?.toDouble();
}

void validateFiniteNumber(num value, String field) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, field, 'must be a finite JSON number');
  }
}

void validateOptionalFiniteNumber(num? value, String field) {
  if (value == null) {
    return;
  }
  validateFiniteNumber(value, field);
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

int readInteger(Object? value, String field) {
  final integer = readOptionalInteger(value, field);
  if (integer == null) {
    throw FormatException('$field is required');
  }
  return integer;
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

bool readRequiredBool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('$field must be a boolean');
}

bool? readOptionalBool(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return readRequiredBool(value, field);
}

List<String>? readOptionalStringList(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw FormatException('$field must be a list of strings');
  }
  return [
    for (final item in value) readRequiredString(item, '$field items'),
  ];
}

int? readOptionalTtlMs(Object? value, String field) {
  final ttlMs = readOptionalInteger(value, field);
  if (ttlMs == null) {
    return null;
  }
  if (ttlMs < 0) {
    throw FormatException('$field must be greater than or equal to 0');
  }
  return ttlMs;
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

Map<String, dynamic> readJsonObject(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be a JSON object');
  }
  return (readJsonValue(value, field) as Map).cast<String, dynamic>();
}

Map<String, dynamic>? readOptionalJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return readJsonObject(value, field);
}
