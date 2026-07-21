import 'dart:math' as math;

import 'json_schema_definition_validator.dart';
import 'json_schema_dialect.dart';
import 'json_schema_formats.dart';
import 'json_schema_meta_schemas.dart';
import 'json_schema_number.dart';

const _maxEvaluationDepth = 1120;

/// A failure produced by the package-internal JSON Schema engine.
final class JsonSchemaEngineException implements Exception {
  final String message;
  final List<String> path;

  const JsonSchemaEngineException(this.message, [this.path = const []]);

  @override
  String toString() => '$message (at /${path.join('/')})';
}

/// Compiles JSON Schema documents without network access or runtime packages.
abstract final class JsonSchemaEngine {
  static CompiledJsonSchema compile(
    Object? schema, {
    required JsonSchemaDialect dialect,
  }) {
    return _Compiler(schema, dialect).compile();
  }
}

/// A reusable, synchronous JSON Schema validator.
final class CompiledJsonSchema {
  final _Compiler _compiler;
  final _Node _root;

  const CompiledJsonSchema._(this._compiler, this._root);

  void validate(Object? instance) {
    final result = _compiler.evaluate(
      _root,
      instance,
      const [],
      const [],
      _EvaluationContext(),
    );
    final failure = result.failure;
    if (failure != null) {
      throw JsonSchemaEngineException(failure.message, failure.path);
    }
  }
}

final class _Compiler {
  static final Uri _documentUri = Uri.parse('mcp-schema:///document');

  final Object? source;
  final JsonSchemaDialect dialect;
  final Map<String, _Node> _references = {};
  final Map<String, _Resource> _resources = {};
  final List<_Node> _nodes = [];
  final Map<JsonSchemaDialect, _Node> _metaSchemas = {};
  final Map<String, _Node> _delegatedMetaSchemaFragments = {};
  bool _metaSchemaBundleRegistered = false;
  late final _Node root;

  _Compiler(this.source, this.dialect);

  CompiledJsonSchema compile() {
    if (!_isSchema(source)) {
      throw const JsonSchemaEngineException(
        'A JSON Schema must be an object or boolean',
      );
    }
    final initialResource = _Resource(_documentUri);
    _resources[_documentUri.toString()] = initialResource;
    root = _visit(source, _documentUri, initialResource, [
      _PointerAlias(initialResource, ''),
    ]);
    initialResource.root ??= root;
    _references.putIfAbsent(_key(initialResource.uri, ''), () => root);
    _checkReferences();
    _computeDynamicDependencies();
    return CompiledJsonSchema._(this, root);
  }

  _Node _visit(
    Object? raw,
    Uri inheritedBase,
    _Resource inheritedResource,
    List<_PointerAlias> inheritedAliases,
  ) {
    final map = _schemaMap(raw);
    var base = inheritedBase;
    var resource = inheritedResource;
    final aliases = [...inheritedAliases];
    Uri? declaredId;

    final id = map?[r'$id'];
    final draft7ReferenceObject =
        dialect == JsonSchemaDialect.draft7 && map?[r'$ref'] is String;
    if (id is String && !draft7ReferenceObject) {
      try {
        declaredId = inheritedBase.resolve(id);
        base = _withoutFragment(declaredId);
      } on FormatException {
        throw JsonSchemaEngineException('Invalid \$id URI: $id');
      }
      if (declaredId.fragment.isEmpty) {
        if (base == inheritedResource.uri) {
          if (inheritedResource.root != null) {
            throw JsonSchemaEngineException(
              'Duplicate schema resource identifier: $base',
            );
          }
        } else {
          if (_resources.containsKey(base.toString())) {
            throw JsonSchemaEngineException(
              'Duplicate schema resource identifier: $base',
            );
          }
          resource = _Resource(base);
          _resources[base.toString()] = resource;
          aliases.add(_PointerAlias(resource, ''));
        }
      }
    }

    final node = _Node(_nodes.length, raw, map, base, resource);
    _nodes.add(node);
    resource.root ??= node;
    for (final alias in aliases) {
      _references[_key(alias.resource.uri, alias.pointer)] = node;
    }
    if (declaredId != null) {
      _references[_key(base, _decodeUriFragment(declaredId.fragment))] = node;
    }

    if (dialect == JsonSchemaDialect.draft202012) {
      final anchor = map?[r'$anchor'];
      if (anchor is String) {
        _registerAnchor(resource, anchor);
        _references[_key(resource.uri, anchor)] = node;
      }
      final dynamicAnchor = map?[r'$dynamicAnchor'];
      if (dynamicAnchor is String) {
        _registerAnchor(resource, dynamicAnchor);
        _references[_key(resource.uri, dynamicAnchor)] = node;
        resource.dynamicAnchors[dynamicAnchor] = node;
      }
    }

    if (map == null) return node;

    final pattern = map['pattern'];
    if (pattern is String) {
      node.pattern = RegExp(pattern, unicode: true);
    }

    void single(String keyword) {
      final child = map[keyword];
      if (_isSchema(child)) {
        node.single[keyword] = _visitChild(
          child,
          base,
          resource,
          _childAliases(aliases, [keyword]),
        );
      }
    }

    void list(String keyword) {
      final values = map[keyword];
      if (values is! List) return;
      final children = <_Node>[];
      for (var index = 0; index < values.length; index++) {
        final child = values[index];
        if (_isSchema(child)) {
          children.add(
            _visitChild(
              child,
              base,
              resource,
              _childAliases(aliases, [keyword, '$index']),
            ),
          );
        }
      }
      node.lists[keyword] = children;
    }

    void dictionary(String keyword, {bool schemasOnly = true}) {
      final values = map[keyword];
      if (values is! Map) return;
      final children = <String, _Node>{};
      for (final entry in values.entries) {
        if (entry.key is! String) continue;
        final child = entry.value;
        if (_isSchema(child) && (!schemasOnly || child is! List)) {
          children[entry.key as String] = _visitChild(
            child,
            base,
            resource,
            _childAliases(aliases, [keyword, entry.key as String]),
          );
        }
      }
      node.maps[keyword] = children;
    }

    for (final keyword in const [
      'additionalProperties',
      'contains',
      'else',
      'if',
      'not',
      'propertyNames',
      'then',
    ]) {
      single(keyword);
    }
    if (dialect == JsonSchemaDialect.draft202012) {
      for (final keyword in const [
        'unevaluatedItems',
        'unevaluatedProperties',
      ]) {
        single(keyword);
      }
    } else {
      single('additionalItems');
    }
    final items = map['items'];
    if (items is List) {
      list('items');
    } else {
      single('items');
    }
    for (final keyword in const ['allOf', 'anyOf', 'oneOf']) {
      list(keyword);
    }
    if (dialect == JsonSchemaDialect.draft202012) list('prefixItems');
    for (final keyword in const ['patternProperties', 'properties']) {
      dictionary(keyword);
    }
    if (dialect == JsonSchemaDialect.draft202012) {
      dictionary(r'$defs');
      dictionary('dependentSchemas');
    } else {
      dictionary('definitions');
    }
    final patternProperties = node.maps['patternProperties'];
    if (patternProperties != null) {
      for (final entry in patternProperties.entries) {
        node.patternProperties.add(
          MapEntry(RegExp(entry.key, unicode: true), entry.value),
        );
      }
    }
    if (dialect == JsonSchemaDialect.draft7) {
      dictionary('dependencies', schemasOnly: false);
    }
    return node;
  }

  _Node _visitChild(
    Object? raw,
    Uri inheritedBase,
    _Resource inheritedResource,
    List<_PointerAlias> aliases,
  ) {
    _Node? existing;
    for (final alias in aliases) {
      final candidate = _references[_key(alias.resource.uri, alias.pointer)];
      if (candidate == null) continue;
      if (!identical(candidate.schema, raw)) {
        throw JsonSchemaEngineException(
          'Conflicting schema document location: ${alias.pointer}',
        );
      }
      existing = candidate;
      break;
    }
    if (existing == null) {
      return _visit(raw, inheritedBase, inheritedResource, aliases);
    }
    for (final alias in aliases) {
      final key = _key(alias.resource.uri, alias.pointer);
      final candidate = _references[key];
      if (candidate != null && !identical(candidate, existing)) {
        throw JsonSchemaEngineException(
          'Conflicting schema document location: ${alias.pointer}',
        );
      }
      _references[key] = existing;
    }
    return existing;
  }

  List<_PointerAlias> _childAliases(
    List<_PointerAlias> parents,
    List<String> segments,
  ) {
    return [
      for (final parent in parents)
        _PointerAlias(
          parent.resource,
          '${parent.pointer}/${segments.map(_pointerEscape).join('/')}',
        ),
    ];
  }

  void _registerAnchor(_Resource resource, String anchor) {
    if (!resource.anchorNames.add(anchor)) {
      throw JsonSchemaEngineException(
        'Duplicate plain-name fragment in ${resource.uri}: $anchor',
      );
    }
  }

  void _checkReferences() {
    while (true) {
      final previousNodeCount = _nodes.length;
      final previousReferenceCount = _references.length;
      (_Node, String, String)? unresolved;
      for (var index = 0; index < _nodes.length; index++) {
        final node = _nodes[index];
        final map = node.map;
        if (map == null) continue;
        final keywords = dialect == JsonSchemaDialect.draft7
            ? const [r'$ref']
            : const [r'$ref', r'$dynamicRef'];
        for (final keyword in keywords) {
          final value = map[keyword];
          if (value is String && _resolve(node, value) == null) {
            unresolved ??= (node, keyword, value);
          }
        }
      }
      if (unresolved == null) return;
      if (_nodes.length == previousNodeCount &&
          _references.length == previousReferenceCount) {
        final (node, keyword, reference) = unresolved;
        throw JsonSchemaEngineException(
          _unresolvedReferenceMessage(node, keyword, reference),
        );
      }
    }
  }

  String _unresolvedReferenceMessage(
    _Node from,
    String keyword,
    String reference,
  ) {
    try {
      final base = _withoutFragment(from.base.resolve(reference));
      final isLocal = _resources.containsKey(base.toString()) ||
          _metaSchemaDialect(base) != null;
      return '${isLocal ? 'Local' : 'External'} $keyword is unresolved: '
          '$reference';
    } on FormatException {
      return '$keyword is unresolved: $reference';
    }
  }

  void _computeDynamicDependencies() {
    if (dialect != JsonSchemaDialect.draft202012) return;
    final predecessors = <_Node, Set<_Node>>{};

    void addEdge(_Node from, _Node? to) {
      if (to != null && !identical(from, to)) {
        predecessors.putIfAbsent(to, () => {}).add(from);
      }
    }

    for (final node in _nodes) {
      for (final keyword in const [
        'additionalProperties',
        'contains',
        'items',
        'not',
        'propertyNames',
        'unevaluatedItems',
        'unevaluatedProperties',
      ]) {
        addEdge(node, node.single[keyword]);
      }
      final condition = node.single['if'];
      if (condition != null) {
        addEdge(node, condition);
        addEdge(node, node.single['then']);
        addEdge(node, node.single['else']);
      }
      for (final keyword in const [
        'allOf',
        'anyOf',
        'oneOf',
        'prefixItems',
      ]) {
        for (final child in node.lists[keyword] ?? const <_Node>[]) {
          addEdge(node, child);
        }
      }
      for (final keyword in const [
        'dependentSchemas',
        'patternProperties',
        'properties',
      ]) {
        for (final child in node.maps[keyword]?.values ?? const <_Node>[]) {
          addEdge(node, child);
        }
      }

      final reference = node.map?[r'$ref'];
      if (reference is String) addEdge(node, _resolve(node, reference));

      final dynamicReference = node.map?[r'$dynamicRef'];
      if (dynamicReference is String) {
        final target = _resolve(node, dynamicReference);
        addEdge(node, target);
        final fragment = _decodeUriFragment(
          node.base.resolve(dynamicReference).fragment,
        );
        if (fragment.isNotEmpty &&
            !fragment.startsWith('/') &&
            target?.map?[r'$dynamicAnchor'] == fragment) {
          node.dynamicAnchorDependencies.add(fragment);
        }
      }
    }

    final queue = [
      for (final node in _nodes)
        if (node.dynamicAnchorDependencies.isNotEmpty) node,
    ];
    for (var index = 0; index < queue.length; index++) {
      final child = queue[index];
      for (final parent in predecessors[child] ?? const <_Node>{}) {
        final previousLength = parent.dynamicAnchorDependencies.length;
        parent.dynamicAnchorDependencies.addAll(
          child.dynamicAnchorDependencies,
        );
        if (parent.dynamicAnchorDependencies.length != previousLength) {
          queue.add(parent);
        }
      }
    }
  }

  _Node? _resolve(_Node from, String reference) {
    try {
      final uri = from.base.resolve(reference);
      final base = _withoutFragment(uri);
      final metaDialect = _metaSchemaDialect(base);
      if (uri.fragment.isEmpty && metaDialect != null) {
        if (metaDialect != dialect) {
          return _delegatedMetaSchemaFragments.putIfAbsent(
            uri.toString(),
            () => _createDelegatedMetaSchemaNode(uri, metaDialect),
          );
        }
        if (metaDialect == JsonSchemaDialect.draft7) {
          _registerMetaSchemaBundle();
          return _references[_key(base, '')];
        }
        return _metaSchemas.putIfAbsent(
          metaDialect,
          () => _createMetaSchemaNode(uri, metaDialect),
        );
      }
      final fragment = _decodeUriFragment(uri.fragment);
      if (metaDialect != null) {
        if (metaDialect == dialect) {
          _registerMetaSchemaBundle();
        } else {
          return _delegatedMetaSchemaFragments.putIfAbsent(
            uri.toString(),
            () => _createDelegatedMetaSchemaNode(uri, metaDialect),
          );
        }
      }
      return _references[_key(base, fragment)] ??
          _resolvePointerTarget(base, fragment);
    } on FormatException {
      return null;
    }
  }

  _Node? _resolvePointerTarget(Uri base, String fragment) {
    if (!fragment.startsWith('/')) return null;
    final resource = _resources[base.toString()];
    Object? target = resource?.root?.schema;
    if (resource == null || target == null) return null;
    for (final rawToken in fragment.substring(1).split('/')) {
      if (!_isValidPointerToken(rawToken)) return null;
      final token = rawToken.replaceAll('~1', '/').replaceAll('~0', '~');
      if (target is Map && target.containsKey(token)) {
        target = target[token];
      } else if (target is List) {
        final index = _parsePointerArrayIndex(token);
        if (index == null || index >= target.length) return null;
        target = target[index];
      } else {
        return null;
      }
    }
    if (!_isSchema(target)) return null;
    try {
      validateJsonSchemaDefinition(target, dialect);
    } on FormatException catch (error) {
      throw JsonSchemaEngineException(error.message);
    }
    return _visit(
      target,
      resource.uri,
      resource,
      [_PointerAlias(resource, fragment)],
    );
  }

  _Result evaluate(
    _Node node,
    Object? instance,
    List<String> path,
    List<_Resource> incomingScope,
    _EvaluationContext context,
  ) {
    final collapsed = _collapseReferences(node, incomingScope);
    node = collapsed.$1;
    final scope = collapsed.$2;
    final key = _EvaluationKey(node.id, instance, path, scope);
    final cached = context.completed[key];
    if (cached != null) return cached;
    if (context.active.contains(key)) {
      context.cycleEpoch++;
      return _Result.valid();
    }
    if (context.depth >= _maxEvaluationDepth) {
      return _Result.invalid(
        'Instance validation exceeds the maximum depth of '
        '$_maxEvaluationDepth',
        path,
      );
    }
    context.active.add(key);
    context.depth++;
    final initialCycleEpoch = context.cycleEpoch;
    try {
      final result = _evaluate(node, instance, path, scope, context);
      if (context.cycleEpoch == initialCycleEpoch) {
        context.completed[key] = result;
      }
      return result;
    } finally {
      context.depth--;
      context.active.remove(key);
    }
  }

  (_Node, List<_Resource>) _collapseReferences(
    _Node node,
    List<_Resource> incomingScope,
  ) {
    var scope = _scopeFor(node, incomingScope);
    final visited = <int>{};
    while (visited.add(node.id)) {
      final map = node.map;
      if (map == null) break;
      _Node? target;
      final reference = map[r'$ref'];
      if (reference is String &&
          (dialect == JsonSchemaDialect.draft7 || map.length == 1)) {
        target = _resolve(node, reference);
      } else if (dialect == JsonSchemaDialect.draft202012 && map.length == 1) {
        final dynamicReference = map[r'$dynamicRef'];
        if (dynamicReference is String) {
          target = _resolve(node, dynamicReference);
          final fragment = _decodeUriFragment(
            node.base.resolve(dynamicReference).fragment,
          );
          if (target?.map?[r'$dynamicAnchor'] == fragment) {
            for (final resource in scope) {
              final candidate = resource.dynamicAnchors[fragment];
              if (candidate != null) {
                target = candidate;
                break;
              }
            }
          }
        }
      }
      if (target == null || visited.contains(target.id)) break;
      node = target;
      scope = _scopeFor(node, scope);
    }
    return (node, scope);
  }

  List<_Resource> _scopeFor(_Node node, List<_Resource> incomingScope) {
    final dependencies = node.dynamicAnchorDependencies;
    if (dependencies.isEmpty) return const [];
    final unresolved = {...dependencies};
    final scope = <_Resource>[];
    for (final resource in incomingScope) {
      final resolved = unresolved
          .where(resource.dynamicAnchors.containsKey)
          .toList(growable: false);
      if (resolved.isEmpty) continue;
      scope.add(resource);
      unresolved.removeAll(resolved);
      if (unresolved.isEmpty) return scope;
    }
    if (unresolved.any(node.resource.dynamicAnchors.containsKey)) {
      scope.add(node.resource);
    }
    return scope;
  }

  _Result _evaluate(
    _Node node,
    Object? instance,
    List<String> path,
    List<_Resource> scope,
    _EvaluationContext context,
  ) {
    final metaDialect = node.metaDialect;
    if (metaDialect != null) {
      try {
        validateJsonMetaSchemaInstance(instance, metaDialect);
        return _Result.valid();
      } on FormatException catch (error) {
        return _Result.invalid(error.message, path);
      }
    }
    final delegatedSchema = node.delegatedSchema;
    if (delegatedSchema != null) {
      try {
        delegatedSchema.validate(instance);
        return _Result.valid();
      } on JsonSchemaEngineException catch (error) {
        return _Result.invalid(error.message, [...path, ...error.path]);
      }
    }
    if (node.schema is bool) {
      return node.schema == true
          ? _Result.valid()
          : _Result.invalid('Boolean schema is false', path);
    }
    final schema = node.map!;
    final result = _Result.valid();

    final reference = schema[r'$ref'];
    if (reference is String) {
      final target = _resolve(node, reference)!;
      final referenced = evaluate(target, instance, path, scope, context);
      if (!referenced.isValid) return referenced;
      result.merge(referenced);
      if (dialect == JsonSchemaDialect.draft7) return result;
    }
    if (dialect == JsonSchemaDialect.draft202012) {
      final dynamicReference = schema[r'$dynamicRef'];
      if (dynamicReference is String) {
        var target = _resolve(node, dynamicReference)!;
        final fragment = _decodeUriFragment(
          node.base.resolve(dynamicReference).fragment,
        );
        if (target.map?[r'$dynamicAnchor'] == fragment) {
          for (final resource in scope) {
            final candidate = resource.dynamicAnchors[fragment];
            if (candidate != null) {
              target = candidate;
              break;
            }
          }
        }
        final referenced = evaluate(target, instance, path, scope, context);
        if (!referenced.isValid) return referenced;
        result.merge(referenced);
      }
    }

    final type = schema['type'];
    if (type is String && !_matchesType(type, instance) ||
        type is List &&
            !type.whereType<String>().any(
                  (name) => _matchesType(name, instance),
                )) {
      return _Result.invalid('Value does not match schema type $type', path);
    }
    if (schema.containsKey('const') && !_jsonEqual(schema['const'], instance)) {
      return _Result.invalid('Value does not match const', path);
    }
    final enumValues = schema['enum'];
    if (enumValues is List &&
        !enumValues.any((value) => _jsonEqual(value, instance))) {
      return _Result.invalid('Value is not one of the allowed values', path);
    }

    final composition = _evaluateComposition(
      node,
      schema,
      instance,
      path,
      scope,
      context,
    );
    if (!composition.isValid) return composition;
    result.merge(composition);

    if (instance is num) {
      final failure = _validateNumber(schema, instance, path);
      if (failure != null) return failure;
    }
    if (instance is String) {
      final failure = _validateString(node, schema, instance, path);
      if (failure != null) return failure;
    }
    if (instance is List) {
      final array = _evaluateArray(
        node,
        schema,
        instance,
        path,
        scope,
        context,
        result.items,
      );
      if (!array.isValid) return array;
      result.merge(array);
    }
    if (instance is Map) {
      final object = _evaluateObject(
        node,
        schema,
        instance,
        path,
        scope,
        context,
        result.properties,
      );
      if (!object.isValid) return object;
      result.merge(object);
    }
    return result;
  }

  JsonSchemaDialect? _metaSchemaDialect(Uri uri) {
    final value = uri.toString();
    if (value == 'https://json-schema.org/draft/2020-12/schema') {
      return JsonSchemaDialect.draft202012;
    }
    if (value == 'http://json-schema.org/draft-07/schema' ||
        value == 'https://json-schema.org/draft-07/schema') {
      return JsonSchemaDialect.draft7;
    }
    return null;
  }

  _Node _createMetaSchemaNode(Uri uri, JsonSchemaDialect metaDialect) {
    final resource = _Resource(_withoutFragment(uri));
    final node = _Node(
      -1,
      true,
      null,
      resource.uri,
      resource,
      metaDialect: metaDialect,
    );
    resource.root = node;
    return node;
  }

  _Node _createDelegatedMetaSchemaNode(
    Uri uri,
    JsonSchemaDialect metaDialect,
  ) {
    final delegatedSchema = JsonSchemaEngine.compile(
      {r'$ref': uri.toString()},
      dialect: metaDialect,
    );
    final resource = _Resource(_withoutFragment(uri));
    final node = _Node(
      _nodes.length,
      true,
      null,
      uri,
      resource,
      delegatedSchema: delegatedSchema,
    );
    _nodes.add(node);
    resource.root = node;
    return node;
  }

  void _registerMetaSchemaBundle() {
    if (_metaSchemaBundleRegistered) return;
    _metaSchemaBundleRegistered = true;

    final bases = dialect == JsonSchemaDialect.draft7
        ? [
            Uri.parse('http://json-schema.org/draft-07/schema'),
            Uri.parse('https://json-schema.org/draft-07/schema'),
          ]
        : [Uri.parse('https://json-schema.org/draft/2020-12/schema')];
    final resources = [for (final base in bases) _Resource(base)];
    for (final resource in resources) {
      _resources[resource.uri.toString()] = resource;
    }
    final bundledRoot = _visit(
      canonicalJsonSchemaDocument(dialect),
      bases.first,
      resources.first,
      [for (final resource in resources) _PointerAlias(resource, '')],
    );
    for (final resource in resources) {
      resource.root ??= bundledRoot;
    }
  }

  _Result _evaluateComposition(
    _Node node,
    Map<String, Object?> schema,
    Object? instance,
    List<String> path,
    List<_Resource> scope,
    _EvaluationContext context,
  ) {
    final result = _Result.valid();
    for (final child in node.lists['allOf'] ?? const []) {
      final branch = evaluate(child, instance, path, scope, context);
      if (!branch.isValid) return branch;
      result.merge(branch);
    }

    final anyOf = node.lists['anyOf'];
    if (anyOf != null) {
      var matched = false;
      for (final child in anyOf) {
        final branch = evaluate(child, instance, path, scope, context);
        if (branch.isValid) {
          matched = true;
          result.merge(branch);
        }
      }
      if (!matched) {
        return _Result.invalid('Value does not match anyOf', path);
      }
    }

    final oneOf = node.lists['oneOf'];
    if (oneOf != null) {
      _Result? match;
      for (final child in oneOf) {
        final branch = evaluate(child, instance, path, scope, context);
        if (!branch.isValid) continue;
        if (match != null) {
          return _Result.invalid(
            'Value must match exactly one oneOf schema',
            path,
          );
        }
        match = branch;
      }
      if (match == null) {
        return _Result.invalid(
          'Value must match exactly one oneOf schema',
          path,
        );
      }
      result.merge(match);
    }

    final not = node.single['not'];
    if (not != null && evaluate(not, instance, path, scope, context).isValid) {
      return _Result.invalid('Value matches the disallowed schema', path);
    }

    final condition = node.single['if'];
    if (condition != null) {
      final conditionResult = evaluate(
        condition,
        instance,
        path,
        scope,
        context,
      );
      final matched = conditionResult.isValid;
      if (matched) result.merge(conditionResult);
      final selected = node.single[matched ? 'then' : 'else'];
      if (selected != null) {
        final branch = evaluate(selected, instance, path, scope, context);
        if (!branch.isValid) return branch;
        result.merge(branch);
      }
    }
    return result;
  }

  _Result? _validateNumber(
    Map<String, Object?> schema,
    num value,
    List<String> path,
  ) {
    if (!value.isFinite) {
      return _Result.invalid('Value is not a finite JSON number', path);
    }
    final multipleOf = schema['multipleOf'];
    if (multipleOf is num && !jsonNumberIsMultiple(value, multipleOf)) {
      return _Result.invalid('Value is not a multiple of $multipleOf', path);
    }
    final maximum = schema['maximum'];
    if (maximum is num && compareJsonNumbers(value, maximum) > 0) {
      return _Result.invalid('Value exceeds maximum $maximum', path);
    }
    final exclusiveMaximum = schema['exclusiveMaximum'];
    if (exclusiveMaximum is num &&
        compareJsonNumbers(value, exclusiveMaximum) >= 0) {
      return _Result.invalid('Value must be less than $exclusiveMaximum', path);
    }
    final minimum = schema['minimum'];
    if (minimum is num && compareJsonNumbers(value, minimum) < 0) {
      return _Result.invalid('Value is below minimum $minimum', path);
    }
    final exclusiveMinimum = schema['exclusiveMinimum'];
    if (exclusiveMinimum is num &&
        compareJsonNumbers(value, exclusiveMinimum) <= 0) {
      return _Result.invalid(
        'Value must be greater than $exclusiveMinimum',
        path,
      );
    }
    return null;
  }

  _Result? _validateString(
    _Node node,
    Map<String, Object?> schema,
    String value,
    List<String> path,
  ) {
    final length = value.runes.length;
    final minLength = schema['minLength'];
    if (minLength is num && length < minLength) {
      return _Result.invalid('String is shorter than $minLength', path);
    }
    final maxLength = schema['maxLength'];
    if (maxLength is num && length > maxLength) {
      return _Result.invalid('String is longer than $maxLength', path);
    }
    final pattern = node.pattern;
    if (pattern != null && !pattern.hasMatch(value)) {
      return _Result.invalid(
        'String does not match pattern ${schema['pattern']}',
        path,
      );
    }
    final format = schema['format'];
    if (dialect == JsonSchemaDialect.draft7 &&
        format is String &&
        !jsonSchemaDraft7FormatIsValid(format, value)) {
      return _Result.invalid('String does not match format $format', path);
    }
    return null;
  }

  _Result _evaluateArray(
    _Node node,
    Map<String, Object?> schema,
    List instance,
    List<String> path,
    List<_Resource> scope,
    _EvaluationContext context,
    Set<int> alreadyEvaluated,
  ) {
    final result = _Result.valid();
    result.items.addAll(alreadyEvaluated);
    final minItems = schema['minItems'];
    if (minItems is num && instance.length < minItems) {
      return _Result.invalid('Array has fewer than $minItems items', path);
    }
    final maxItems = schema['maxItems'];
    if (maxItems is num && instance.length > maxItems) {
      return _Result.invalid('Array has more than $maxItems items', path);
    }
    if (schema['uniqueItems'] == true) {
      final seen = <int, List<Object?>>{};
      for (var index = 0; index < instance.length; index++) {
        final value = instance[index];
        final bucket = seen.putIfAbsent(_jsonHash(value), () => []);
        if (bucket.any((previous) => _jsonEqual(previous, value))) {
          return _Result.invalid('Array items must be unique', [
            ...path,
            '$index',
          ]);
        }
        bucket.add(value);
      }
    }

    var positionalCount = 0;
    if (dialect == JsonSchemaDialect.draft202012) {
      final prefix = node.lists['prefixItems'] ?? const [];
      positionalCount = prefix.length;
      for (var index = 0;
          index < math.min(prefix.length, instance.length);
          index++) {
        final branch = evaluate(
          prefix[index],
          instance[index],
          [...path, '$index'],
          scope,
          context,
        );
        if (!branch.isValid) return branch;
        result.items.add(index);
      }
      final items = node.single['items'];
      if (items != null) {
        for (var index = positionalCount; index < instance.length; index++) {
          final branch = evaluate(
            items,
            instance[index],
            [...path, '$index'],
            scope,
            context,
          );
          if (!branch.isValid) return branch;
          result.items.add(index);
        }
      }
    } else {
      final tuple = node.lists['items'];
      final items = node.single['items'];
      if (tuple != null) {
        positionalCount = tuple.length;
        for (var index = 0;
            index < math.min(tuple.length, instance.length);
            index++) {
          final branch = evaluate(
            tuple[index],
            instance[index],
            [...path, '$index'],
            scope,
            context,
          );
          if (!branch.isValid) return branch;
          result.items.add(index);
        }
        final additional = node.single['additionalItems'];
        if (additional != null) {
          for (var index = tuple.length; index < instance.length; index++) {
            final branch = evaluate(
              additional,
              instance[index],
              [...path, '$index'],
              scope,
              context,
            );
            if (!branch.isValid) return branch;
            result.items.add(index);
          }
        }
      } else if (items != null) {
        for (var index = 0; index < instance.length; index++) {
          final branch = evaluate(
            items,
            instance[index],
            [...path, '$index'],
            scope,
            context,
          );
          if (!branch.isValid) return branch;
          result.items.add(index);
        }
      }
    }

    final contains = node.single['contains'];
    if (contains != null) {
      final matched = <int>[];
      for (var index = 0; index < instance.length; index++) {
        if (evaluate(
          contains,
          instance[index],
          [...path, '$index'],
          scope,
          context,
        ).isValid) {
          matched.add(index);
        }
      }
      final minContains = dialect == JsonSchemaDialect.draft202012
          ? schema['minContains'] as num? ?? 1
          : 1;
      final maxContains = dialect == JsonSchemaDialect.draft202012
          ? schema['maxContains'] as num?
          : null;
      if (matched.length < minContains ||
          maxContains != null && matched.length > maxContains) {
        return _Result.invalid('Array does not satisfy contains', path);
      }
      if (dialect == JsonSchemaDialect.draft202012) {
        result.items.addAll(matched);
      }
    }

    if (dialect == JsonSchemaDialect.draft202012) {
      final unevaluated = node.single['unevaluatedItems'];
      if (unevaluated != null) {
        for (var index = 0; index < instance.length; index++) {
          if (result.items.contains(index)) continue;
          final branch = evaluate(
            unevaluated,
            instance[index],
            [...path, '$index'],
            scope,
            context,
          );
          if (!branch.isValid) return branch;
          result.items.add(index);
        }
      }
    }
    return result;
  }

  _Result _evaluateObject(
    _Node node,
    Map<String, Object?> schema,
    Map instance,
    List<String> path,
    List<_Resource> scope,
    _EvaluationContext context,
    Set<Object?> alreadyEvaluated,
  ) {
    final object = instance;
    final result = _Result.valid();
    result.properties.addAll(alreadyEvaluated);
    final minProperties = schema['minProperties'];
    if (minProperties is num && object.length < minProperties) {
      return _Result.invalid(
        'Object has fewer than $minProperties properties',
        path,
      );
    }
    final maxProperties = schema['maxProperties'];
    if (maxProperties is num && object.length > maxProperties) {
      return _Result.invalid(
        'Object has more than $maxProperties properties',
        path,
      );
    }
    final required = schema['required'];
    if (required is List) {
      for (final name in required.whereType<String>()) {
        if (!object.containsKey(name)) {
          return _Result.invalid('Required property is missing: $name', path);
        }
      }
    }

    if (dialect == JsonSchemaDialect.draft202012) {
      final dependentRequired = schema['dependentRequired'];
      if (dependentRequired is Map) {
        for (final entry in dependentRequired.entries) {
          if (entry.key is! String || !object.containsKey(entry.key)) continue;
          final dependencies = entry.value;
          if (dependencies is! List) continue;
          for (final name in dependencies.whereType<String>()) {
            if (!object.containsKey(name)) {
              return _Result.invalid(
                'Property $name is required by ${entry.key}',
                path,
              );
            }
          }
        }
      }
    } else {
      final dependencies = schema['dependencies'];
      if (dependencies is Map) {
        for (final entry in dependencies.entries) {
          if (entry.key is! String || !object.containsKey(entry.key)) continue;
          if (entry.value is List) {
            for (final name in (entry.value as List).whereType<String>()) {
              if (!object.containsKey(name)) {
                return _Result.invalid(
                  'Property $name is required by ${entry.key}',
                  path,
                );
              }
            }
          } else {
            final child = node.maps['dependencies']?[entry.key];
            if (child != null) {
              final branch = evaluate(child, instance, path, scope, context);
              if (!branch.isValid) return branch;
              result.merge(branch);
            }
          }
        }
      }
    }

    final properties = node.maps['properties'] ?? const {};
    for (final entry in properties.entries) {
      if (!object.containsKey(entry.key)) continue;
      final branch = evaluate(
        entry.value,
        object[entry.key],
        [...path, entry.key],
        scope,
        context,
      );
      if (!branch.isValid) return branch;
      result.properties.add(entry.key);
    }

    for (final entry in object.entries) {
      if (entry.key is! String) continue;
      final name = entry.key as String;
      for (final pattern in node.patternProperties) {
        if (!pattern.key.hasMatch(name)) continue;
        final branch = evaluate(
          pattern.value,
          entry.value,
          [...path, name],
          scope,
          context,
        );
        if (!branch.isValid) return branch;
        result.properties.add(name);
      }
    }

    final additional = node.single['additionalProperties'];
    if (additional != null) {
      for (final entry in object.entries) {
        final name = entry.key;
        if (name is String &&
            (properties.containsKey(name) ||
                node.patternProperties.any(
                  (pattern) => pattern.key.hasMatch(name),
                ))) {
          continue;
        }
        final branch = evaluate(
          additional,
          entry.value,
          [...path, '$name'],
          scope,
          context,
        );
        if (!branch.isValid) return branch;
        result.properties.add(entry.key);
      }
    }

    final propertyNames = node.single['propertyNames'];
    if (propertyNames != null) {
      for (final name in object.keys) {
        final branch = evaluate(
          propertyNames,
          name,
          [...path, '$name'],
          scope,
          context,
        );
        if (!branch.isValid) return branch;
      }
    }

    if (dialect == JsonSchemaDialect.draft202012) {
      final dependentSchemas = node.maps['dependentSchemas'] ?? const {};
      for (final entry in dependentSchemas.entries) {
        if (!object.containsKey(entry.key)) continue;
        final branch = evaluate(entry.value, instance, path, scope, context);
        if (!branch.isValid) return branch;
        result.merge(branch);
      }
      final unevaluated = node.single['unevaluatedProperties'];
      if (unevaluated != null) {
        for (final entry in object.entries) {
          if (result.properties.contains(entry.key)) continue;
          final branch = evaluate(
            unevaluated,
            entry.value,
            [...path, '${entry.key}'],
            scope,
            context,
          );
          if (!branch.isValid) return branch;
          result.properties.add(entry.key);
        }
      }
    }
    return result;
  }
}

final class _Node {
  final int id;
  final Object? schema;
  final Map<String, Object?>? map;
  final Uri base;
  final _Resource resource;
  final JsonSchemaDialect? metaDialect;
  final CompiledJsonSchema? delegatedSchema;
  final Set<String> dynamicAnchorDependencies = {};
  final Map<String, _Node> single = {};
  final Map<String, List<_Node>> lists = {};
  final Map<String, Map<String, _Node>> maps = {};
  RegExp? pattern;
  final List<MapEntry<RegExp, _Node>> patternProperties = [];

  _Node(
    this.id,
    this.schema,
    this.map,
    this.base,
    this.resource, {
    this.metaDialect,
    this.delegatedSchema,
  });
}

final class _EvaluationContext {
  final Set<_EvaluationKey> active = {};
  final Map<_EvaluationKey, _Result> completed = {};
  int cycleEpoch = 0;
  int depth = 0;
}

final class _EvaluationKey {
  final int nodeId;
  final Object? instance;
  final List<String> path;
  final List<_Resource> scope;
  late final int _hashCode = Object.hash(
    nodeId,
    _instanceHash(instance),
    Object.hashAll(path),
    Object.hashAll(scope.map(identityHashCode)),
  );

  _EvaluationKey(this.nodeId, this.instance, this.path, this.scope);

  @override
  int get hashCode => _hashCode;

  @override
  bool operator ==(Object other) {
    return other is _EvaluationKey &&
        nodeId == other.nodeId &&
        _sameInstance(instance, other.instance) &&
        _samePath(path, other.path) &&
        _sameScope(scope, other.scope);
  }
}

final class _Resource {
  final Uri uri;
  _Node? root;
  final Set<String> anchorNames = {};
  final Map<String, _Node> dynamicAnchors = {};

  _Resource(this.uri);
}

final class _PointerAlias {
  final _Resource resource;
  final String pointer;

  const _PointerAlias(this.resource, this.pointer);
}

final class _Failure {
  final String message;
  final List<String> path;

  const _Failure(this.message, this.path);
}

final class _Result {
  _Failure? failure;
  final Set<Object?> properties = {};
  final Set<int> items = {};

  _Result.valid();

  _Result.invalid(String message, List<String> path)
      : failure = _Failure(message, List.unmodifiable(path));

  bool get isValid => failure == null;

  void merge(_Result other) {
    properties.addAll(other.properties);
    items.addAll(other.items);
  }
}

Map<String, Object?>? _schemaMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

bool _isSchema(Object? value) => value is bool || value is Map;

bool _matchesType(String type, Object? value) {
  return switch (type) {
    'array' => value is List,
    'boolean' => value is bool,
    'integer' => value is int ||
        value is double && value.isFinite && value == value.truncateToDouble(),
    'null' => value == null,
    'number' => value is num && value.isFinite,
    'object' => value is Map,
    'string' => value is String,
    _ => false,
  };
}

bool _jsonEqual(Object? left, Object? right) {
  if (left is num && right is num) return jsonNumbersEqual(left, right);
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => index,
        ).every((index) => _jsonEqual(left[index], right[index]));
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonEqual(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) {
  if (value is num && value.isFinite) {
    return jsonNumberHash(value);
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, _jsonHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}

Uri _withoutFragment(Uri uri) {
  final text = uri.toString();
  final marker = text.indexOf('#');
  return Uri.parse(marker < 0 ? text : text.substring(0, marker));
}

String _key(Uri base, String fragment) {
  return '${_withoutFragment(base)}#$fragment';
}

String _decodeUriFragment(String fragment) => Uri.decodeComponent(fragment);

bool _isValidPointerToken(String token) {
  for (var index = 0; index < token.length; index++) {
    if (token.codeUnitAt(index) != 0x7e) continue;
    if (++index >= token.length) return false;
    final escape = token.codeUnitAt(index);
    if (escape != 0x30 && escape != 0x31) return false;
  }
  return true;
}

int? _parsePointerArrayIndex(String token) {
  if (token == '0') return 0;
  if (token.isEmpty ||
      token.codeUnitAt(0) < 0x31 ||
      token.codeUnitAt(0) > 0x39) {
    return null;
  }
  for (var index = 1; index < token.length; index++) {
    final codeUnit = token.codeUnitAt(index);
    if (codeUnit < 0x30 || codeUnit > 0x39) return null;
  }
  return int.tryParse(token);
}

int _instanceHash(Object? value) {
  return value is Map || value is List
      ? identityHashCode(value)
      : value.hashCode;
}

bool _sameInstance(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map || left is List || right is Map || right is List) {
    return false;
  }
  return left == right;
}

bool _samePath(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameScope(List<_Resource> left, List<_Resource> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}

String _pointerEscape(String segment) {
  return segment.replaceAll('~', '~0').replaceAll('/', '~1');
}
