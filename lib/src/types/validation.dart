import 'dart:typed_data';

import '../shared/uri_template.dart';

final _base64Values = _createBase64Values();

Uint8List _createBase64Values() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final values = Uint8List(128)..fillRange(0, 128, 0xff);
  for (var i = 0; i < alphabet.length; i++) {
    values[alphabet.codeUnitAt(i)] = i;
  }
  return values;
}

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
  if (value.length % 4 != 0) {
    return false;
  }
  var dataEnd = value.length;
  if (dataEnd > 0 && value.codeUnitAt(dataEnd - 1) == 0x3d) {
    dataEnd--;
    if (dataEnd > 0 && value.codeUnitAt(dataEnd - 1) == 0x3d) {
      dataEnd--;
    }
  }
  // Check four ASCII characters at a time. Invalid table entries are 0xff;
  // valid sextets are below 64, so OR preserves any invalid entry.
  var i = 0;
  for (; i + 3 < dataEnd; i += 4) {
    final a = value.codeUnitAt(i);
    final b = value.codeUnitAt(i + 1);
    final c = value.codeUnitAt(i + 2);
    final d = value.codeUnitAt(i + 3);
    if ((a | b | c | d) >= _base64Values.length) {
      return false;
    }
    if ((_base64Values[a] |
            _base64Values[b] |
            _base64Values[c] |
            _base64Values[d]) ==
        0xff) {
      return false;
    }
  }
  for (; i < dataEnd; i++) {
    final code = value.codeUnitAt(i);
    if (code >= _base64Values.length || _base64Values[code] == 0xff) {
      return false;
    }
  }
  final padding = value.length - dataEnd;
  if (padding == 0) {
    return true;
  }
  final lastValue = _base64Values[value.codeUnitAt(dataEnd - 1)];
  // Unused low bits must be zero: four bits for '==', two bits for '='.
  return (lastValue & (padding == 2 ? 0x0f : 0x03)) == 0;
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

Map<String, String>? readOptionalStringMap(Object? value, String field) {
  if (value == null) {
    return null;
  }
  final map = readJsonObject(value, field);
  return {
    for (final entry in map.entries)
      entry.key: readRequiredString(entry.value, '$field.${entry.key}'),
  };
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
