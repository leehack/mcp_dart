import 'package:json_schema/json_schema.dart' as standards;

import 'json_schema.dart';

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
  final guard = _SchemaGuard(schemaVersion)..inspect(schemaValue);
  final normalizedSchema = _normalizeDialectIdentifiers(
    schemaValue,
    schemaVersion,
  );
  _LocalResourceReferences.rewrite(
    normalizedSchema,
    rewriteDynamicReferences:
        schemaVersion == standards.SchemaVersion.draft2020_12,
  );

  final standards.JsonSchema compiledSchema;
  try {
    compiledSchema = standards.JsonSchema.create(
      normalizedSchema,
      schemaVersion: schemaVersion,
    );
  } on Object catch (error) {
    final unresolvedReference = guard.unresolvedReference(error);
    if (unresolvedReference != null) {
      throw JsonSchemaDefinitionException._(
        'External ${unresolvedReference.keyword} is unresolved: '
        '${unresolvedReference.value}',
      );
    }
    throw JsonSchemaDefinitionException._(
      'Invalid JSON Schema schema: $error',
    );
  }

  return (dynamic data) {
    final result = compiledSchema.validate(data);
    if (result.isValid) {
      if (schemaVersion == standards.SchemaVersion.draft2020_12) {
        _validateUnevaluatedItemLocations(normalizedSchema, data, const []);
      }
      return;
    }

    final error = result.errors.first;
    throw JsonSchemaValidationException(
      error.message,
      _jsonPointerSegments(error.instancePath),
    );
  };
}

/// Adds standards-compliant JSON Schema validation to [JsonSchema].
extension JsonSchemaValidation on JsonSchema {
  /// Validates [data] against this JSON Schema.
  ///
  /// Schemas without `$schema` use JSON Schema 2020-12. The canonical 2020-12
  /// dialect URI, with or without its empty fragment, is supported. Declared
  /// Draft 7 schemas use Draft 7 semantics for compatibility with
  /// legacy MCP schemas. Other dialects are rejected explicitly instead of
  /// being interpreted using the wrong semantics.
  ///
  /// Local fragments and absolute or relative resource identifiers that
  /// resolve inside this schema document are evaluated synchronously,
  /// including `$dynamicRef`. Unresolved references outside the supplied
  /// document are rejected; validation never performs network I/O.
  void validate(dynamic data) {
    compileJsonSchemaValidator(this)(data);
  }
}

void _validateUnevaluatedItemLocations(
  Object? schema,
  Object? data,
  List<String> path,
) {
  if (schema is! Map || data is! List) {
    return;
  }

  final prefixItems = schema['prefixItems'];
  if (prefixItems is List) {
    final prefixLength =
        prefixItems.length < data.length ? prefixItems.length : data.length;
    for (var index = 0; index < prefixLength; index++) {
      _validateUnevaluatedItemLocations(
        prefixItems[index],
        data[index],
        [...path, '$index'],
      );
    }
  }

  final hasOtherItemEvaluator = _otherItemEvaluatorKeywords.any(
    schema.containsKey,
  );
  if (schema['unevaluatedItems'] == false && !hasOtherItemEvaluator) {
    final evaluatedCount = prefixItems is List ? prefixItems.length : 0;
    if (data.length > evaluatedCount) {
      throw JsonSchemaValidationException(
        'Array item was not evaluated and unevaluatedItems is false',
        [...path, '$evaluatedCount'],
      );
    }
  }

  final items = schema['items'];
  if (items is Map || items is bool) {
    final start = prefixItems is List ? prefixItems.length : 0;
    for (var index = start; index < data.length; index++) {
      _validateUnevaluatedItemLocations(
        items,
        data[index],
        [...path, '$index'],
      );
    }
  }
}

const _otherItemEvaluatorKeywords = {
  r'$dynamicRef',
  r'$ref',
  'allOf',
  'anyOf',
  'contains',
  'else',
  'if',
  'items',
  'oneOf',
  'then',
};

class _LocalResourceReferences {
  final standards.SchemaVersion _schemaVersion;
  final Map<String, String> _resourcePointers = {};
  final Map<String, Map<String, dynamic>> _resources = {};
  final Map<String, _DynamicAnchor> _dynamicAnchors = {};

  _LocalResourceReferences(this._schemaVersion);

  static void rewrite(
    Object schema, {
    required bool rewriteDynamicReferences,
  }) {
    if (schema is! Map<String, dynamic>) {
      return;
    }
    final references = _LocalResourceReferences(
      rewriteDynamicReferences
          ? standards.SchemaVersion.draft2020_12
          : standards.SchemaVersion.draft7,
    );
    references
      .._collectResources(schema, '', null)
      .._rewriteAbsolutePathReferences(schema, null);
    if (rewriteDynamicReferences) {
      references._rewriteDynamicScopeReferences(
        schema,
        null,
        const [],
        <String>{},
      );
    }
  }

  void _collectResources(
    Map<String, dynamic> schema,
    String pointer,
    Uri? inheritedBase,
  ) {
    final base = _schemaBase(schema, inheritedBase);
    if (schema[r'$id'] is String && base != null) {
      final resourceKey = _withoutFragment(base);
      _resourcePointers[resourceKey] = pointer;
      _resources[resourceKey] = schema;
    }
    final dynamicAnchor = schema[r'$dynamicAnchor'];
    if (base != null && dynamicAnchor is String) {
      final resourceBase = _withoutFragment(base);
      _dynamicAnchors['$resourceBase#$dynamicAnchor'] =
          _DynamicAnchor(schema, pointer, resourceBase);
    }
    _visitSubschemas(
      schema,
      pointer,
      (subschema, childPointer) =>
          _collectResources(subschema, childPointer, base),
    );
  }

  void _rewriteDynamicScopeReferences(
    Map<String, dynamic> schema,
    Uri? inheritedBase,
    List<Uri> callerScope,
    Set<String> activeReferences,
  ) {
    final base = _schemaBase(schema, inheritedBase);
    final reference = schema[r'$ref'];
    if (base != null && reference is String) {
      final target = _resolveReference(base, reference);
      if (target != null) {
        final edge = '${_withoutFragment(base)}::$reference';
        if (activeReferences.add(edge)) {
          final nextScope = target.resourceBase == _withoutFragment(base)
              ? callerScope
              : [...callerScope, base];
          _rewriteDynamicScopeReferences(
            target.schema,
            Uri.parse(target.resourceBase),
            nextScope,
            activeReferences,
          );
          activeReferences.remove(edge);
        }
      }
    }

    final dynamicReference = schema[r'$dynamicRef'];
    if (base == null || dynamicReference is! String) {
      return;
    }
    final resolved = base.resolve(dynamicReference);
    final anchorName = resolved.fragment;
    if (anchorName.isEmpty || anchorName.startsWith('/')) {
      return;
    }
    final staticAnchor =
        _dynamicAnchors['${_withoutFragment(resolved)}#$anchorName'];
    if (staticAnchor == null) {
      return;
    }

    _DynamicAnchor? scopedAnchor;
    for (final caller in callerScope.reversed) {
      scopedAnchor = _dynamicAnchors['${_withoutFragment(caller)}#$anchorName'];
      if (scopedAnchor != null) {
        break;
      }
    }
    if (scopedAnchor != null && scopedAnchor != staticAnchor) {
      final resourcePointer =
          _resourcePointers[scopedAnchor.resourceBase] ?? '';
      final relativePointer =
          scopedAnchor.pointer.substring(resourcePointer.length);
      schema
        ..remove(r'$dynamicRef')
        ..[r'$ref'] = '${scopedAnchor.resourceBase}#$relativePointer';
    }
  }

  _ResolvedReference? _resolveReference(Uri base, String reference) {
    final resolved = base.resolve(reference);
    final resourceBase = _withoutFragment(resolved);
    final resource = _resources[resourceBase];
    if (resource == null) {
      return null;
    }
    final fragment = resolved.fragment;
    if (fragment.isEmpty) {
      return _ResolvedReference(resource, resourceBase);
    }
    if (!fragment.startsWith('/')) {
      final anchor = _dynamicAnchors['$resourceBase#$fragment'];
      return anchor == null
          ? null
          : _ResolvedReference(anchor.schema, resourceBase);
    }

    Object? target = resource;
    for (final rawToken in fragment.substring(1).split('/')) {
      final token = rawToken.replaceAll('~1', '/').replaceAll('~0', '~');
      if (target is Map && target.containsKey(token)) {
        target = target[token];
      } else if (target is List) {
        final index = int.tryParse(token);
        if (index == null || index < 0 || index >= target.length) {
          return null;
        }
        target = target[index];
      } else {
        return null;
      }
    }
    return target is Map<String, dynamic>
        ? _ResolvedReference(target, resourceBase)
        : null;
  }

  void _rewriteAbsolutePathReferences(
    Map<String, dynamic> schema,
    Uri? inheritedBase,
  ) {
    final base = _schemaBase(schema, inheritedBase);
    final reference = schema[r'$ref'];
    if (base != null && reference is String && reference.startsWith('/')) {
      final resolved = base.resolve(reference);
      final resourcePointer = _resourcePointers[_withoutFragment(resolved)];
      final fragment = resolved.fragment;
      if (resourcePointer != null &&
          (fragment.isEmpty || fragment.startsWith('/'))) {
        schema[r'$ref'] = '#$resourcePointer$fragment';
      }
    }
    _visitSubschemas(
      schema,
      '',
      (subschema, _) => _rewriteAbsolutePathReferences(subschema, base),
    );
  }

  Uri? _schemaBase(Map<String, dynamic> schema, Uri? inheritedBase) {
    final identifier = schema[r'$id'];
    if (identifier is! String) {
      return inheritedBase;
    }
    final parsed = Uri.tryParse(identifier);
    if (parsed == null) {
      return inheritedBase;
    }
    return inheritedBase?.resolveUri(parsed) ?? parsed;
  }

  String _withoutFragment(Uri uri) {
    final value = uri.toString();
    final fragmentIndex = value.indexOf('#');
    return fragmentIndex == -1 ? value : value.substring(0, fragmentIndex);
  }

  void _visitSubschemas(
    Map<String, dynamic> schema,
    String pointer,
    void Function(Map<String, dynamic> schema, String pointer) visit,
  ) {
    for (final keyword in _singleSubschemaKeywordsFor(_schemaVersion)) {
      final value = schema[keyword];
      if (keyword == 'items' && value is List) {
        for (var index = 0; index < value.length; index++) {
          final subschema = value[index];
          if (subschema is Map<String, dynamic>) {
            visit(subschema, '$pointer/items/$index');
          }
        }
      } else if (value is Map<String, dynamic>) {
        visit(value, '$pointer/${_escapePointerToken(keyword)}');
      }
    }
    for (final keyword in _subschemaMapKeywordsFor(_schemaVersion)) {
      final value = schema[keyword];
      if (value is Map) {
        for (final entry in value.entries) {
          final subschema = entry.value;
          if (subschema is Map<String, dynamic>) {
            visit(
              subschema,
              '$pointer/${_escapePointerToken(keyword)}'
              '/${_escapePointerToken(entry.key.toString())}',
            );
          }
        }
      }
    }
    for (final keyword in _subschemaListKeywordsFor(_schemaVersion)) {
      final value = schema[keyword];
      if (value is List) {
        for (var index = 0; index < value.length; index++) {
          final subschema = value[index];
          if (subschema is Map<String, dynamic>) {
            visit(
              subschema,
              '$pointer/${_escapePointerToken(keyword)}/$index',
            );
          }
        }
      }
    }
  }

  String _escapePointerToken(String value) {
    return value.replaceAll('~', '~0').replaceAll('/', '~1');
  }
}

class _DynamicAnchor {
  final Map<String, dynamic> schema;
  final String pointer;
  final String resourceBase;

  const _DynamicAnchor(this.schema, this.pointer, this.resourceBase);
}

class _ResolvedReference {
  final Map<String, dynamic> schema;
  final String resourceBase;

  const _ResolvedReference(this.schema, this.resourceBase);
}

standards.SchemaVersion _schemaVersionFor(Object schema) {
  if (schema is! Map || !schema.containsKey(r'$schema')) {
    return standards.SchemaVersion.draft2020_12;
  }
  return switch (schema[r'$schema']) {
    _jsonSchema2020Dialect ||
    '$_jsonSchema2020Dialect#' =>
      standards.SchemaVersion.draft2020_12,
    _jsonSchemaDraft7Dialect ||
    _jsonSchemaDraft7DialectWithoutFragment ||
    _jsonSchemaDraft7HttpsDialect ||
    _jsonSchemaDraft7HttpsDialectWithoutFragment =>
      standards.SchemaVersion.draft7,
    _ => standards.SchemaVersion.draft2020_12,
  };
}

Object _normalizeDialectIdentifiers(
  Object schema,
  standards.SchemaVersion schemaVersion,
) {
  if (schema is bool) {
    return schema;
  }
  if (schema is! Map) {
    return schema;
  }

  final normalized = Map<String, dynamic>.from(schema);
  if (schemaVersion == standards.SchemaVersion.draft7) {
    // The standards engine indexes schema-shaped values under unknown
    // keywords for reference lookup. Remove keywords introduced after Draft 7
    // from the private validation copy so they remain true no-op annotations
    // instead of being compiled or asserted under legacy semantics.
    for (final keyword in _keywordsIntroducedAfterDraft7) {
      normalized.remove(keyword);
    }
  }
  if (normalized[r'$schema'] == '$_jsonSchema2020Dialect#') {
    normalized[r'$schema'] = _jsonSchema2020Dialect;
  } else if (normalized[r'$schema'] == _jsonSchemaDraft7HttpsDialect ||
      normalized[r'$schema'] == _jsonSchemaDraft7HttpsDialectWithoutFragment ||
      normalized[r'$schema'] == _jsonSchemaDraft7DialectWithoutFragment) {
    normalized[r'$schema'] = _jsonSchemaDraft7Dialect;
  }

  // In both supported dialects the content vocabulary is annotation-only.
  // The underlying engine also offers opt-in content assertions, so omit these
  // annotations from the private validation copy while preserving the public
  // wire schema unchanged.
  normalized
    ..remove('contentEncoding')
    ..remove('contentMediaType')
    ..remove('contentSchema');

  for (final keyword in _nonNegativeIntegerKeywords) {
    final value = normalized[keyword];
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      normalized[keyword] = value.toInt();
    }
  }

  final dynamicReference = normalized[r'$dynamicRef'];
  if (schemaVersion == standards.SchemaVersion.draft2020_12 &&
      dynamicReference is String) {
    final uri = Uri.tryParse(dynamicReference);
    if (uri != null && (uri.fragment.isEmpty || uri.fragment.startsWith('/'))) {
      // A $dynamicRef whose fragment is not a plain-name anchor has the same
      // behavior as $ref in JSON Schema 2020-12.
      normalized
        ..remove(r'$dynamicRef')
        ..[r'$ref'] = dynamicReference;
    }
  }

  if (schemaVersion == standards.SchemaVersion.draft2020_12 &&
      normalized.containsKey('items') &&
      normalized['unevaluatedItems'] == false) {
    // `items` evaluates every array position not covered by prefixItems, so a
    // sibling `unevaluatedItems: false` cannot add another failure.
    normalized.remove('unevaluatedItems');
  } else if (schemaVersion == standards.SchemaVersion.draft2020_12 &&
      normalized['unevaluatedItems'] == false) {
    final evaluatedPrefixLength = _staticEvaluatedPrefixLength(
      normalized,
      ignoreOwnUnevaluatedItems: true,
    );
    if (evaluatedPrefixLength != null) {
      // When only prefixItems (including prefixItems in unconditional allOf
      // branches) contribute evaluated-item annotations, unevaluatedItems
      // false is equivalent to padding the direct prefix and using items
      // false. This private rewrite also keeps nested array evaluation
      // contexts independent in the standards engine.
      final directPrefix = switch (normalized['prefixItems']) {
        final List value => List<dynamic>.from(value),
        _ => <dynamic>[],
      };
      while (directPrefix.length < evaluatedPrefixLength) {
        directPrefix.add(true);
      }
      normalized
        ..remove('unevaluatedItems')
        ..['items'] = false;
      if (directPrefix.isNotEmpty) {
        normalized['prefixItems'] = directPrefix;
      }
    }
  }

  for (final keyword in _singleSubschemaKeywordsFor(schemaVersion)) {
    final value = normalized[keyword];
    if (keyword == 'items' && value is List) {
      normalized[keyword] = value
          .map(
            (subschema) => subschema is Map || subschema is bool
                ? _normalizeDialectIdentifiers(
                    subschema as Object,
                    schemaVersion,
                  )
                : subschema,
          )
          .toList(growable: false);
    } else if (value is Map || value is bool) {
      normalized[keyword] = _normalizeDialectIdentifiers(
        value as Object,
        schemaVersion,
      );
    }
  }
  for (final keyword in _subschemaMapKeywordsFor(schemaVersion)) {
    final value = normalized[keyword];
    if (value is Map) {
      normalized[keyword] = value.map(
        (key, subschema) => MapEntry(
          key,
          subschema is Map || subschema is bool
              ? _normalizeDialectIdentifiers(
                  subschema as Object,
                  schemaVersion,
                )
              : subschema,
        ),
      );
    }
  }
  for (final keyword in _subschemaListKeywordsFor(schemaVersion)) {
    final value = normalized[keyword];
    if (value is List) {
      normalized[keyword] = value
          .map(
            (subschema) => subschema is Map || subschema is bool
                ? _normalizeDialectIdentifiers(
                    subschema as Object,
                    schemaVersion,
                  )
                : subschema,
          )
          .toList(growable: false);
    }
  }
  return normalized;
}

int? _staticEvaluatedPrefixLength(
  Map<String, dynamic> schema, {
  bool ignoreOwnUnevaluatedItems = false,
}) {
  if (schema.containsKey(r'$ref') ||
      schema.containsKey(r'$dynamicRef') ||
      schema.containsKey('contains') ||
      schema.containsKey('items') ||
      (!ignoreOwnUnevaluatedItems && schema.containsKey('unevaluatedItems'))) {
    return null;
  }

  var evaluatedPrefixLength = 0;
  final prefixItems = schema['prefixItems'];
  if (prefixItems != null) {
    if (prefixItems is! List) {
      return null;
    }
    evaluatedPrefixLength = prefixItems.length;
  }

  final allOf = schema['allOf'];
  if (allOf != null) {
    if (allOf is! List) {
      return null;
    }
    for (final subschema in allOf) {
      final branchLength = switch (subschema) {
        bool _ => 0,
        final Map value => _staticEvaluatedPrefixLength(
            Map<String, dynamic>.from(value),
          ),
        _ => null,
      };
      if (branchLength == null) {
        return null;
      }
      if (branchLength > evaluatedPrefixLength) {
        evaluatedPrefixLength = branchLength;
      }
    }
  }

  for (final keyword in const ['anyOf', 'oneOf', 'if', 'then', 'else']) {
    if (_valueMayEvaluateItems(schema[keyword])) {
      return null;
    }
  }
  return evaluatedPrefixLength;
}

bool _valueMayEvaluateItems(Object? value) {
  if (value is List) {
    return value.any(_valueMayEvaluateItems);
  }
  if (value is! Map) {
    return false;
  }
  if (const {
    r'$dynamicRef',
    r'$ref',
    'contains',
    'items',
    'prefixItems',
    'unevaluatedItems',
  }.any(value.containsKey)) {
    return true;
  }
  return const ['allOf', 'anyOf', 'oneOf', 'if', 'then', 'else']
      .any((keyword) => _valueMayEvaluateItems(value[keyword]));
}

class _SchemaGuard {
  final standards.SchemaVersion _schemaVersion;
  int _subschemas = 0;
  final List<_NonFragmentReference> _nonFragmentReferences = [];

  _SchemaGuard(this._schemaVersion);

  void inspect(Object schema) {
    _inspectSchema(schema, 0);
  }

  void _inspectSchema(Object? schema, int depth) {
    if (depth > _maxSchemaDepth) {
      throw JsonSchemaDefinitionException._(
        'JSON Schema exceeds the maximum depth of $_maxSchemaDepth',
      );
    }
    if (++_subschemas > _maxSubschemas) {
      throw JsonSchemaDefinitionException._(
        'JSON Schema exceeds the maximum of $_maxSubschemas subschemas',
      );
    }

    if (schema is bool) {
      return;
    }
    if (schema is! Map) {
      // The standards validator provides the detailed schema-shape error.
      return;
    }

    _validateDialect(schema[r'$schema']);
    _validateReference(r'$ref', schema[r'$ref']);
    if (_schemaVersion == standards.SchemaVersion.draft2020_12) {
      _validateReference(r'$dynamicRef', schema[r'$dynamicRef']);
    }
    _validateEnum(schema['enum']);

    for (final keyword in _singleSubschemaKeywordsFor(_schemaVersion)) {
      if (schema.containsKey(keyword)) {
        final value = schema[keyword];
        if (keyword == 'items' && value is List) {
          for (final subschema in value) {
            _inspectSchema(subschema, depth + 1);
          }
        } else {
          _inspectSchema(value, depth + 1);
        }
      }
    }

    for (final keyword in _subschemaMapKeywordsFor(_schemaVersion)) {
      final value = schema[keyword];
      if (value is Map) {
        for (final subschema in value.values) {
          _inspectSchema(subschema, depth + 1);
        }
      }
    }

    for (final keyword in _subschemaListKeywordsFor(_schemaVersion)) {
      final value = schema[keyword];
      if (value is List) {
        for (final subschema in value) {
          _inspectSchema(subschema, depth + 1);
        }
      }
    }
  }

  void _validateDialect(Object? dialect) {
    if (dialect == null) {
      return;
    }
    if (dialect is! String || !_supportedDialects.contains(dialect)) {
      throw JsonSchemaDefinitionException._(
        'Unsupported JSON Schema dialect: $dialect',
      );
    }
  }

  void _validateReference(String keyword, Object? reference) {
    if (reference is String &&
        reference.isNotEmpty &&
        !reference.startsWith('#')) {
      _nonFragmentReferences.add(_NonFragmentReference(keyword, reference));
    }
  }

  void _validateEnum(Object? value) {
    if (value == null) {
      return;
    }
    if (value is! List || value.isEmpty) {
      throw JsonSchemaDefinitionException._(
        'Invalid JSON Schema schema: enum must be a non-empty array',
      );
    }
    for (var index = 0; index < value.length; index++) {
      for (var other = index + 1; other < value.length; other++) {
        if (_jsonEquals(value[index], value[other])) {
          throw JsonSchemaDefinitionException._(
            'Invalid JSON Schema schema: enum values must be unique',
          );
        }
      }
    }
  }

  _NonFragmentReference? unresolvedReference(Object error) {
    final message = error.toString();
    final isUnresolved = message.contains('unresolvable request') ||
        message.contains('could not be found') ||
        message.contains('Unable to resolve path');
    if (!isUnresolved) {
      if (message.contains('Null check operator used on a null value')) {
        return _nonFragmentReferences
            .where((reference) => reference.keyword == r'$dynamicRef')
            .firstOrNull;
      }
      return null;
    }
    for (final reference in _nonFragmentReferences) {
      if (message.contains(reference.value)) {
        return reference;
      }
    }
    return _nonFragmentReferences.firstOrNull;
  }
}

bool _jsonEquals(Object? left, Object? right) {
  if (left == right) {
    return true;
  }
  if (left is List && right is List && left.length == right.length) {
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is Map && right is Map && left.length == right.length) {
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_jsonEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

class _NonFragmentReference {
  final String keyword;
  final String value;

  const _NonFragmentReference(this.keyword, this.value);
}

const _jsonSchema2020SingleSubschemaKeywords = {
  'additionalProperties',
  'contains',
  'contentSchema',
  'else',
  'if',
  'items',
  'not',
  'propertyNames',
  'then',
  'unevaluatedItems',
  'unevaluatedProperties',
};

const _jsonSchemaDraft7SingleSubschemaKeywords = {
  'additionalItems',
  'additionalProperties',
  'contains',
  'else',
  'if',
  'items',
  'not',
  'propertyNames',
  'then',
};

const _jsonSchema2020SubschemaMapKeywords = {
  r'$defs',
  'dependentSchemas',
  'patternProperties',
  'properties',
};

const _jsonSchemaDraft7SubschemaMapKeywords = {
  'definitions',
  'dependencies',
  'patternProperties',
  'properties',
};

const _supportedDialects = {
  _jsonSchema2020Dialect,
  '$_jsonSchema2020Dialect#',
  _jsonSchemaDraft7Dialect,
  _jsonSchemaDraft7DialectWithoutFragment,
  _jsonSchemaDraft7HttpsDialect,
  _jsonSchemaDraft7HttpsDialectWithoutFragment,
};

const _nonNegativeIntegerKeywords = {
  'maxContains',
  'maxItems',
  'maxLength',
  'maxProperties',
  'minContains',
  'minItems',
  'minLength',
  'minProperties',
};

const _keywordsIntroducedAfterDraft7 = {
  r'$anchor',
  r'$defs',
  r'$dynamicAnchor',
  r'$dynamicRef',
  r'$recursiveAnchor',
  r'$recursiveRef',
  r'$vocabulary',
  'contentSchema',
  'dependentRequired',
  'dependentSchemas',
  'maxContains',
  'minContains',
  'prefixItems',
  'unevaluatedItems',
  'unevaluatedProperties',
};

const _jsonSchema2020SubschemaListKeywords = {
  'allOf',
  'anyOf',
  'oneOf',
  'prefixItems',
};

const _jsonSchemaDraft7SubschemaListKeywords = {
  'allOf',
  'anyOf',
  'oneOf',
};

Set<String> _singleSubschemaKeywordsFor(
  standards.SchemaVersion schemaVersion,
) =>
    schemaVersion == standards.SchemaVersion.draft7
        ? _jsonSchemaDraft7SingleSubschemaKeywords
        : _jsonSchema2020SingleSubschemaKeywords;

Set<String> _subschemaMapKeywordsFor(
  standards.SchemaVersion schemaVersion,
) =>
    schemaVersion == standards.SchemaVersion.draft7
        ? _jsonSchemaDraft7SubschemaMapKeywords
        : _jsonSchema2020SubschemaMapKeywords;

Set<String> _subschemaListKeywordsFor(
  standards.SchemaVersion schemaVersion,
) =>
    schemaVersion == standards.SchemaVersion.draft7
        ? _jsonSchemaDraft7SubschemaListKeywords
        : _jsonSchema2020SubschemaListKeywords;

List<String> _jsonPointerSegments(String pointer) {
  if (pointer.isEmpty || pointer == '#') {
    return const [];
  }
  final value = pointer.startsWith('#') ? pointer.substring(1) : pointer;
  if (!value.startsWith('/')) {
    return [value];
  }
  return value
      .substring(1)
      .split('/')
      .map((segment) => segment.replaceAll('~1', '/').replaceAll('~0', '~'))
      .toList(growable: false);
}
