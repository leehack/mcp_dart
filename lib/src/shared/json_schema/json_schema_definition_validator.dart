import 'json_schema_dialect.dart';
import 'json_schema_formats.dart';
import 'json_schema_number.dart';

const _jsonSchema2020Dialect = 'https://json-schema.org/draft/2020-12/schema';
const _jsonSchemaDraft7Dialect = 'http://json-schema.org/draft-07/schema#';
const _jsonSchemaDraft7DialectWithoutFragment =
    'http://json-schema.org/draft-07/schema';
const _jsonSchemaDraft7HttpsDialect =
    'https://json-schema.org/draft-07/schema#';
const _jsonSchemaDraft7HttpsDialectWithoutFragment =
    'https://json-schema.org/draft-07/schema';
const _maxSchemaDepth = 64;
const _maxSubschemas = 1024;

const _supportedDialects = {
  _jsonSchema2020Dialect,
  '$_jsonSchema2020Dialect#',
  _jsonSchemaDraft7Dialect,
  _jsonSchemaDraft7DialectWithoutFragment,
  _jsonSchemaDraft7HttpsDialect,
  _jsonSchemaDraft7HttpsDialectWithoutFragment,
};

const _jsonTypes = {
  'array',
  'boolean',
  'integer',
  'null',
  'number',
  'object',
  'string',
};

const _commonStringKeywords = {
  r'$comment',
  'contentEncoding',
  'contentMediaType',
  'description',
  'format',
  'title',
};

const _commonBooleanKeywords = {'readOnly', 'uniqueItems', 'writeOnly'};

const _numericKeywords = {
  'exclusiveMaximum',
  'exclusiveMinimum',
  'maximum',
  'minimum',
};

const _commonCountKeywords = {
  'maxItems',
  'maxLength',
  'maxProperties',
  'minItems',
  'minLength',
  'minProperties',
};

const _commonSingleSubschemaKeywords = {
  'additionalProperties',
  'contains',
  'else',
  'if',
  'not',
  'propertyNames',
  'then',
};

const _commonSubschemaMapKeywords = {'patternProperties', 'properties'};

const _commonSubschemaListKeywords = {'allOf', 'anyOf', 'oneOf'};

final _anchorPattern = RegExp(r'^[A-Za-z_][-A-Za-z0-9._]*$');

/// Checks that [schema] is a well-formed schema for [dialect].
///
/// This validates the JSON Schema vocabulary shapes used by the SDK before a
/// schema is compiled. Unknown keywords remain annotations, as required by
/// JSON Schema. Invalid definitions throw [FormatException].
void validateJsonSchemaDefinition(
  Object? schema,
  JsonSchemaDialect dialect,
) {
  _JsonSchemaDefinitionValidator(dialect).validate(schema);
}

/// Validates [value] as data against the selected canonical meta-schema.
///
/// Meta-schema `format` keywords are annotations, so URI and regular-expression
/// syntax is deliberately not asserted in this mode.
void validateJsonMetaSchemaInstance(
  Object? value,
  JsonSchemaDialect dialect,
) {
  _JsonSchemaDefinitionValidator(
    dialect,
    validatingMetaSchemaInstance: true,
  ).validate(value);
}

final class _JsonSchemaDefinitionValidator {
  final JsonSchemaDialect _dialect;
  final bool _validatingMetaSchemaInstance;
  int _subschemaCount = 0;

  _JsonSchemaDefinitionValidator(
    this._dialect, {
    bool validatingMetaSchemaInstance = false,
  }) : _validatingMetaSchemaInstance = validatingMetaSchemaInstance;

  bool get _metaFormatsAreAnnotations =>
      _validatingMetaSchemaInstance &&
      _dialect == JsonSchemaDialect.draft202012;

  void validate(Object? schema) {
    _validateSchema(schema, '#', 0);
  }

  void _validateSchema(Object? schema, String path, int depth) {
    if (!_validatingMetaSchemaInstance && depth > _maxSchemaDepth) {
      _fail(path, 'schema exceeds the maximum depth of $_maxSchemaDepth');
    }
    if (++_subschemaCount > _maxSubschemas && !_validatingMetaSchemaInstance) {
      _fail(path, 'schema exceeds the maximum of $_maxSubschemas subschemas');
    }

    if (schema is bool) {
      return;
    }
    if (schema is! Map<Object?, Object?>) {
      _fail(path, 'schema must be an object or boolean');
    }
    final map = _expectObject(schema, path, 'schema');

    _validateDialect(map, path);
    _validateIdentifier(map, path);
    _validateReference(map, r'$ref', path);
    _validateType(map, path);
    _validateEnum(map, path);

    for (final keyword in _commonStringKeywords) {
      _validateStringKeyword(map, keyword, path);
    }
    for (final keyword in _commonBooleanKeywords) {
      _validateBooleanKeyword(map, keyword, path);
    }
    for (final keyword in _numericKeywords) {
      _validateFiniteNumberKeyword(map, keyword, path);
    }
    for (final keyword in _commonCountKeywords) {
      _validateCountKeyword(map, keyword, path);
    }

    _validateMultipleOf(map, path);
    _validatePattern(map, path);
    _validateStringArrayKeyword(map, 'required', path);
    _validateExamples(map, path);

    for (final keyword in _commonSingleSubschemaKeywords) {
      _validateSingleSubschema(map, keyword, path, depth);
    }
    for (final keyword in _commonSubschemaMapKeywords) {
      _validateSubschemaMap(map, keyword, path, depth);
    }
    for (final keyword in _commonSubschemaListKeywords) {
      _validateSubschemaList(map, keyword, path, depth, requireNonEmpty: true);
    }

    switch (_dialect) {
      case JsonSchemaDialect.draft202012:
        _validateDraft202012Keywords(map, path, depth);
      case JsonSchemaDialect.draft7:
        _validateDraft7Keywords(map, path, depth);
    }
  }

  void _validateDraft202012Keywords(
    Map<Object?, Object?> map,
    String path,
    int depth,
  ) {
    _validateReference(map, r'$dynamicRef', path);
    _validateAnchor(map, r'$anchor', path);
    _validateAnchor(map, r'$dynamicAnchor', path);
    _validateVocabulary(map, path);
    _validateBooleanKeyword(map, 'deprecated', path);
    _validateCountKeyword(map, 'maxContains', path);
    _validateCountKeyword(map, 'minContains', path);
    _validateStringArrayMap(map, 'dependentRequired', path);

    _validateSingleSubschema(map, 'contentSchema', path, depth);
    _validateSingleSubschema(map, 'items', path, depth);
    _validateSingleSubschema(map, 'unevaluatedItems', path, depth);
    _validateSingleSubschema(map, 'unevaluatedProperties', path, depth);
    _validateSubschemaMap(map, r'$defs', path, depth);
    _validateSubschemaMap(map, 'dependentSchemas', path, depth);
    _validateSubschemaList(
      map,
      'prefixItems',
      path,
      depth,
      requireNonEmpty: true,
    );
  }

  void _validateDraft7Keywords(
    Map<Object?, Object?> map,
    String path,
    int depth,
  ) {
    _validateSingleSubschema(map, 'additionalItems', path, depth);
    _validateDraft7Items(map, path, depth);
    _validateSubschemaMap(map, 'definitions', path, depth);
    _validateDependencies(map, path, depth);
  }

  void _validateDialect(Map<Object?, Object?> map, String path) {
    if (!map.containsKey(r'$schema')) {
      return;
    }
    final value = map[r'$schema'];
    final keywordPath = _childPath(path, r'$schema');
    if (value is! String) {
      _fail(keywordPath, r'$schema must be a string');
    }
    if (!_validatingMetaSchemaInstance && !_supportedDialects.contains(value)) {
      _fail(keywordPath, 'unsupported JSON Schema dialect: $value');
    }
    if (_validatingMetaSchemaInstance &&
        _dialect == JsonSchemaDialect.draft7 &&
        !jsonSchemaFormatIsValid('uri', value)) {
      _fail(keywordPath, r'$schema must be a valid URI');
    }
  }

  void _validateIdentifier(Map<Object?, Object?> map, String path) {
    if (!map.containsKey(r'$id')) {
      return;
    }
    final value = map[r'$id'];
    final keywordPath = _childPath(path, r'$id');
    if (value is! String) {
      _fail(keywordPath, r'$id must be a URI-reference string');
    }
    if (!_metaFormatsAreAnnotations) {
      _validateUriReference(value, keywordPath, r'$id');
    }
    if (_dialect == JsonSchemaDialect.draft202012) {
      final fragmentIndex = value.indexOf('#');
      if (fragmentIndex >= 0 && fragmentIndex + 1 < value.length) {
        _fail(keywordPath, r'$id must not contain a non-empty fragment');
      }
    }
  }

  void _validateReference(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final value = map[keyword];
    final keywordPath = _childPath(path, keyword);
    if (value is! String) {
      _fail(keywordPath, '$keyword must be a URI-reference string');
    }
    if (!_metaFormatsAreAnnotations) {
      _validateUriReference(value, keywordPath, keyword);
    }
  }

  void _validateAnchor(Map<Object?, Object?> map, String keyword, String path) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final value = map[keyword];
    final keywordPath = _childPath(path, keyword);
    if (value is! String || !_anchorPattern.hasMatch(value)) {
      _fail(keywordPath, '$keyword must be a valid plain-name fragment');
    }
  }

  void _validateVocabulary(Map<Object?, Object?> map, String path) {
    if (!map.containsKey(r'$vocabulary')) {
      return;
    }
    final keywordPath = _childPath(path, r'$vocabulary');
    final vocabulary = _expectObject(
      map[r'$vocabulary'],
      keywordPath,
      r'$vocabulary',
    );
    for (final entry in vocabulary.entries) {
      final uri = entry.key as String;
      final entryPath = _childPath(keywordPath, uri);
      if (!_metaFormatsAreAnnotations) {
        _validateUriReference(uri, entryPath, r'$vocabulary key');
        final parsed = Uri.parse(uri);
        if (!parsed.hasScheme) {
          _fail(entryPath, r'$vocabulary keys must be absolute URIs');
        }
      }
      if (entry.value is! bool) {
        _fail(entryPath, r'$vocabulary values must be booleans');
      }
    }
  }

  void _validateType(Map<Object?, Object?> map, String path) {
    if (!map.containsKey('type')) {
      return;
    }
    final value = map['type'];
    final keywordPath = _childPath(path, 'type');
    if (value is String) {
      if (!_jsonTypes.contains(value)) {
        _fail(keywordPath, "unknown JSON Schema type '$value'");
      }
      return;
    }
    if (value is! List<Object?> || value.isEmpty) {
      _fail(
        keywordPath,
        'type must be a JSON Schema type string or a non-empty array',
      );
    }
    final seen = <String>{};
    for (var index = 0; index < value.length; index++) {
      final type = value[index];
      final itemPath = _childPath(keywordPath, '$index');
      if (type is! String || !_jsonTypes.contains(type)) {
        _fail(itemPath, 'type array entries must be JSON Schema type strings');
      }
      if (!seen.add(type)) {
        _fail(keywordPath, 'type array entries must be unique');
      }
    }
  }

  void _validateEnum(Map<Object?, Object?> map, String path) {
    if (!map.containsKey('enum')) {
      return;
    }
    final value = map['enum'];
    final keywordPath = _childPath(path, 'enum');
    if (value is! List<Object?>) {
      _fail(keywordPath, 'enum must be an array');
    }
    // The 2020-12 validation meta-schema constrains `enum` only to `array`.
    // Keep that canonical meta-schema behavior separate from the stricter
    // schema-definition checks below, which preserve the SDK's compile-time
    // rejection of empty and duplicate enums.
    if (_validatingMetaSchemaInstance &&
        _dialect == JsonSchemaDialect.draft202012) {
      return;
    }
    if (value.isEmpty) {
      _fail(keywordPath, 'enum must be a non-empty array');
    }
    final seen = <int, List<Object?>>{};
    for (final item in value) {
      final bucket = seen.putIfAbsent(_jsonHash(item), () => []);
      if (bucket.any((candidate) => _jsonEquals(candidate, item))) {
        _fail(keywordPath, 'enum values must be unique');
      }
      bucket.add(item);
    }
  }

  void _validateStringKeyword(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (map.containsKey(keyword) && map[keyword] is! String) {
      _fail(_childPath(path, keyword), '$keyword must be a string');
    }
  }

  void _validateBooleanKeyword(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (map.containsKey(keyword) && map[keyword] is! bool) {
      _fail(_childPath(path, keyword), '$keyword must be a boolean');
    }
  }

  void _validateFiniteNumberKeyword(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final value = map[keyword];
    if (value is! num || !value.isFinite) {
      _fail(_childPath(path, keyword), '$keyword must be a finite JSON number');
    }
  }

  void _validateMultipleOf(Map<Object?, Object?> map, String path) {
    if (!map.containsKey('multipleOf')) {
      return;
    }
    final value = map['multipleOf'];
    if (value is! num || !value.isFinite || value <= 0) {
      _fail(
        _childPath(path, 'multipleOf'),
        'multipleOf must be a finite number greater than zero',
      );
    }
  }

  void _validateCountKeyword(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final value = map[keyword];
    if (value is! num || !_isNonNegativeInteger(value)) {
      _fail(
        _childPath(path, keyword),
        '$keyword must be a non-negative integer',
      );
    }
  }

  void _validatePattern(Map<Object?, Object?> map, String path) {
    if (!map.containsKey('pattern')) {
      return;
    }
    final value = map['pattern'];
    final keywordPath = _childPath(path, 'pattern');
    if (value is! String) {
      _fail(keywordPath, 'pattern must be a string');
    }
    if (!_metaFormatsAreAnnotations) {
      _compilePattern(value, keywordPath);
    }
  }

  void _validateExamples(Map<Object?, Object?> map, String path) {
    if (map.containsKey('examples') && map['examples'] is! List<Object?>) {
      _fail(_childPath(path, 'examples'), 'examples must be an array');
    }
  }

  void _validateStringArrayKeyword(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    _validateStringArray(map[keyword], _childPath(path, keyword), keyword);
  }

  void _validateStringArrayMap(
    Map<Object?, Object?> map,
    String keyword,
    String path,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final keywordPath = _childPath(path, keyword);
    final values = _expectObject(map[keyword], keywordPath, keyword);
    for (final entry in values.entries) {
      final name = entry.key as String;
      _validateStringArray(
        entry.value,
        _childPath(keywordPath, name),
        '$keyword entry',
      );
    }
  }

  void _validateStringArray(Object? value, String path, String keyword) {
    if (value is! List<Object?>) {
      _fail(path, '$keyword must be an array of unique strings');
    }
    final seen = <String>{};
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! String) {
        _fail(_childPath(path, '$index'), '$keyword entries must be strings');
      }
      if (!seen.add(item)) {
        _fail(path, '$keyword entries must be unique');
      }
    }
  }

  void _validateSingleSubschema(
    Map<Object?, Object?> map,
    String keyword,
    String path,
    int depth,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    _validateSchema(map[keyword], _childPath(path, keyword), depth + 1);
  }

  void _validateSubschemaMap(
    Map<Object?, Object?> map,
    String keyword,
    String path,
    int depth,
  ) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final keywordPath = _childPath(path, keyword);
    final schemas = _expectObject(map[keyword], keywordPath, keyword);
    for (final entry in schemas.entries) {
      final name = entry.key as String;
      final entryPath = _childPath(keywordPath, name);
      if (keyword == 'patternProperties' && !_metaFormatsAreAnnotations) {
        _compilePattern(name, entryPath);
      }
      _validateSchema(entry.value, entryPath, depth + 1);
    }
  }

  void _validateSubschemaList(
    Map<Object?, Object?> map,
    String keyword,
    String path,
    int depth, {
    bool requireNonEmpty = false,
  }) {
    if (!map.containsKey(keyword)) {
      return;
    }
    final keywordPath = _childPath(path, keyword);
    final schemas = map[keyword];
    if (schemas is! List<Object?> || (requireNonEmpty && schemas.isEmpty)) {
      final qualification = requireNonEmpty ? 'a non-empty' : 'an';
      _fail(keywordPath, '$keyword must be $qualification array of schemas');
    }
    for (var index = 0; index < schemas.length; index++) {
      _validateSchema(
        schemas[index],
        _childPath(keywordPath, '$index'),
        depth + 1,
      );
    }
  }

  void _validateDraft7Items(Map<Object?, Object?> map, String path, int depth) {
    if (!map.containsKey('items')) {
      return;
    }
    final value = map['items'];
    if (value is List<Object?>) {
      _validateSubschemaList(map, 'items', path, depth, requireNonEmpty: true);
      return;
    }
    _validateSchema(value, _childPath(path, 'items'), depth + 1);
  }

  void _validateDependencies(
    Map<Object?, Object?> map,
    String path,
    int depth,
  ) {
    if (!map.containsKey('dependencies')) {
      return;
    }
    final keywordPath = _childPath(path, 'dependencies');
    final dependencies = _expectObject(
      map['dependencies'],
      keywordPath,
      'dependencies',
    );
    for (final entry in dependencies.entries) {
      final name = entry.key as String;
      final entryPath = _childPath(keywordPath, name);
      if (entry.value is List<Object?>) {
        _validateStringArray(entry.value, entryPath, 'property dependency');
      } else {
        _validateSchema(entry.value, entryPath, depth + 1);
      }
    }
  }

  Map<Object?, Object?> _expectObject(
    Object? value,
    String path,
    String keyword,
  ) {
    if (value is! Map<Object?, Object?>) {
      _fail(path, '$keyword must be an object');
    }
    for (final key in value.keys) {
      if (key is! String) {
        _fail(path, '$keyword object keys must be strings');
      }
    }
    return value;
  }

  void _compilePattern(String pattern, String path) {
    try {
      RegExp(pattern, unicode: true);
    } on FormatException catch (error) {
      _fail(path, 'invalid regular expression: ${error.message}');
    }
  }

  void _validateUriReference(String value, String path, String keyword) {
    if (!jsonSchemaUriReferenceIsValid(value)) {
      _fail(path, '$keyword must be a valid URI-reference');
    }
  }

  Never _fail(String path, String message) {
    throw FormatException('Invalid JSON Schema at $path: $message');
  }
}

bool _isNonNegativeInteger(num value) {
  if (!value.isFinite || value < 0) {
    return false;
  }
  return value is int || value == value.truncateToDouble();
}

bool _jsonEquals(Object? left, Object? right) {
  if (left is num && right is num) {
    return jsonNumbersEqual(left, right);
  }
  if (left == right) {
    return true;
  }
  if (left is List<Object?> &&
      right is List<Object?> &&
      left.length == right.length) {
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is Map<Object?, Object?> &&
      right is Map<Object?, Object?> &&
      left.length == right.length) {
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_jsonEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

int _jsonHash(Object? value) {
  if (value is num) {
    return jsonNumberHash(value);
  }
  if (value is List<Object?>) {
    return Object.hashAll(value.map(_jsonHash));
  }
  if (value is Map<Object?, Object?>) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, _jsonHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}

String _childPath(String path, String segment) {
  final escaped = segment.replaceAll('~', '~0').replaceAll('/', '~1');
  return '$path/$escaped';
}
