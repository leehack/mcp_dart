import 'validation.dart';

/// A validated JSON value.
///
/// This represents the MCP `2026-07-28` cases where protocol fields
/// may carry any JSON value instead of only an object. Prefer the typed
/// constructors such as [JsonValue.object], [JsonValue.array], or
/// [JsonValue.nullValue] at public API boundaries.
final class JsonValue {
  final Object? _value;

  const JsonValue._(this._value);

  /// A JSON `null` value.
  static const JsonValue nullValue = JsonValue._(null);

  /// Creates a JSON value from decoded JSON data.
  factory JsonValue.fromJson(Object? value) {
    return JsonValue._(readJsonValue(value, 'JsonValue'));
  }

  /// Creates a JSON object value.
  factory JsonValue.object(Map<String, dynamic> value) {
    return JsonValue.fromJson(value);
  }

  /// Creates a JSON array value.
  factory JsonValue.array(List<dynamic> value) {
    return JsonValue.fromJson(value);
  }

  /// Creates a JSON string value.
  factory JsonValue.string(String value) {
    return JsonValue._(value);
  }

  /// Creates a JSON number value.
  factory JsonValue.number(num value) {
    return JsonValue.fromJson(value);
  }

  /// Creates a JSON boolean value.
  factory JsonValue.boolean(bool value) {
    return JsonValue._(value);
  }

  /// Returns this value as a JSON object, or `null` for non-object values.
  Map<String, dynamic>? get asObject {
    final value = _value;
    if (value is! Map) {
      return null;
    }
    return readJsonObject(value, 'JsonValue');
  }

  /// Returns this value as a JSON array, or `null` for non-array values.
  List<dynamic>? get asArray {
    final value = _value;
    if (value is! List) {
      return null;
    }
    return List<dynamic>.unmodifiable(
      value.map((item) => readJsonValue(item, 'JsonValue[]')),
    );
  }

  /// Returns this value as a JSON string, or `null` for non-string values.
  String? get asString {
    final value = _value;
    return value is String ? value : null;
  }

  /// Returns this value as a JSON number, or `null` for non-number values.
  num? get asNumber {
    final value = _value;
    return value is num ? value : null;
  }

  /// Returns this value as a JSON boolean, or `null` for non-boolean values.
  bool? get asBoolean {
    final value = _value;
    return value is bool ? value : null;
  }

  /// Whether this value is JSON `null`.
  bool get isNull => _value == null;

  /// Returns decoded JSON suitable for wire serialization.
  Object? toJson() => readJsonValue(_value, 'JsonValue');
}
