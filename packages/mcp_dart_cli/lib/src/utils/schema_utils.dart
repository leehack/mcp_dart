import 'package:mcp_dart/mcp_dart.dart';

/// Generates dummy arguments for a given [JsonSchema].
///
/// This is used to test tool execution without providing real user input.
Map<String, dynamic> generateDummyArguments(JsonSchema? schema) {
  if (schema is! JsonObject) return {};

  final properties = schema.properties;
  if (properties == null) return {};

  final required = schema.required ?? [];
  final dummyArgs = <String, dynamic>{};

  for (final key in required) {
    final propertySchema = properties[key];
    if (propertySchema != null) {
      dummyArgs[key] = _generateValueForSchema(propertySchema, key);
    }
  }

  return dummyArgs;
}

dynamic _generateValueForSchema(JsonSchema schema, String fieldName) {
  if (schema is JsonString) {
    if (schema.enumValues != null && schema.enumValues!.isNotEmpty) {
      return schema.enumValues!.first;
    }
    return "test_$fieldName";
  }
  if (schema is JsonInteger) return 1;
  if (schema is JsonNumber) return 1.5;
  if (schema is JsonBoolean) return true;
  if (schema is JsonArray) return [];
  if (schema is JsonObject) return {};
  return "test";
}
