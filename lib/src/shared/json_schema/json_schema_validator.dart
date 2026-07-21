import 'json_schema.dart';
import 'json_schema_definition_validator.dart';
import 'json_schema_dialect.dart';
import 'json_schema_engine.dart';

const _jsonSchema2020Dialect = 'https://json-schema.org/draft/2020-12/schema';
const _jsonSchemaDraft7Dialect = 'http://json-schema.org/draft-07/schema#';
const _jsonSchemaDraft7DialectWithoutFragment =
    'http://json-schema.org/draft-07/schema';
const _jsonSchemaDraft7HttpsDialect =
    'https://json-schema.org/draft-07/schema#';
const _jsonSchemaDraft7HttpsDialectWithoutFragment =
    'https://json-schema.org/draft-07/schema';

/// Exception thrown when a JSON Schema is invalid or instance validation fails.
class JsonSchemaValidationException implements Exception {
  /// Human-readable validation failure.
  final String message;

  /// JSON Pointer segments locating the failing instance value.
  final List<String> path;

  /// Creates a validation exception with an optional instance [path].
  JsonSchemaValidationException(this.message, [this.path = const []]);

  @override
  String toString() =>
      'JsonSchemaValidationException: $message (at ${path.join('/')})';
}

/// Package-internal classification for invalid schema definitions.
///
/// The public name permits use across the SDK's internal libraries and is
/// hidden from the package barrel.
final class JsonSchemaDefinitionException
    extends JsonSchemaValidationException {
  JsonSchemaDefinitionException._(super.message);
}

/// Compiles [schema] and returns a reusable instance validator.
///
/// This SDK-internal helper is hidden from the package barrels. Compilation
/// performs all schema-definition checks before the returned function validates
/// an instance, which lets callers reject invalid contracts before invoking
/// side-effecting application code.
void Function(dynamic) compileJsonSchemaValidator(JsonSchema schema) {
  final schemaValue = schema.toJsonValue();
  final schemaVersion = _schemaVersionFor(schemaValue);
  try {
    validateJsonSchemaDefinition(schemaValue, schemaVersion);
  } on FormatException catch (error) {
    throw JsonSchemaDefinitionException._(
      'Invalid JSON Schema schema: ${error.message}',
    );
  }

  final CompiledJsonSchema compiledSchema;
  try {
    compiledSchema = JsonSchemaEngine.compile(
      schemaValue,
      dialect: schemaVersion,
    );
  } on JsonSchemaEngineException catch (error) {
    if (error.message.startsWith('External ') &&
        error.message.contains(' is unresolved:')) {
      throw JsonSchemaDefinitionException._(error.message);
    }
    throw JsonSchemaDefinitionException._(
      'Invalid JSON Schema schema: ${error.message}',
    );
  }

  return (dynamic data) {
    try {
      compiledSchema.validate(data);
    } on JsonSchemaEngineException catch (error) {
      throw JsonSchemaValidationException(error.message, error.path);
    }
  };
}

/// Adds standards-compliant JSON Schema validation to [JsonSchema].
extension JsonSchemaValidation on JsonSchema {
  /// Validates [data] against this JSON Schema.
  ///
  /// Schemas without `$schema` use JSON Schema 2020-12. The canonical 2020-12
  /// dialect URI, with or without its empty fragment, is supported. Declared
  /// Draft 7 schemas use Draft 7 semantics for compatibility with legacy MCP
  /// schemas. Other dialects are rejected explicitly instead of being
  /// interpreted using the wrong semantics.
  ///
  /// Local fragments and absolute or relative resource identifiers that
  /// resolve inside this schema document are evaluated synchronously,
  /// including `$dynamicRef`. Unresolved references outside the supplied
  /// document are rejected; validation never performs network I/O.
  void validate(dynamic data) {
    compileJsonSchemaValidator(this)(data);
  }
}

JsonSchemaDialect _schemaVersionFor(Object schema) {
  if (schema is! Map || !schema.containsKey(r'$schema')) {
    return JsonSchemaDialect.draft202012;
  }
  return switch (schema[r'$schema']) {
    _jsonSchema2020Dialect ||
    '$_jsonSchema2020Dialect#' =>
      JsonSchemaDialect.draft202012,
    _jsonSchemaDraft7Dialect ||
    _jsonSchemaDraft7DialectWithoutFragment ||
    _jsonSchemaDraft7HttpsDialect ||
    _jsonSchemaDraft7HttpsDialectWithoutFragment =>
      JsonSchemaDialect.draft7,
    final value => throw JsonSchemaDefinitionException._(
        'Unsupported JSON Schema dialect: $value',
      ),
  };
}
