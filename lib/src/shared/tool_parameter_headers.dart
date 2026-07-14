const _singleSchemaKeywords = {
  'additionalItems',
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

const _schemaArrayKeywords = {
  'allOf',
  'anyOf',
  'oneOf',
  'prefixItems',
};

const _schemaMapKeywords = {
  r'$defs',
  'definitions',
  'dependentSchemas',
  'patternProperties',
};

/// Returns why an `x-mcp-header` annotation is not statically reachable.
///
/// MCP parameter-header annotations are reachable only through an unbroken
/// chain of JSON Schema `properties` entries from the schema root.
String? toolParameterHeaderReachabilityRejectionReason(
  Map<String, dynamic> schema,
) {
  return _findUnreachableToolParameterHeader(
    schema,
    path: '#',
    propertyChainReachable: true,
    annotationAllowed: false,
  );
}

String? _findUnreachableToolParameterHeader(
  Map<String, dynamic> schema, {
  required String path,
  required bool propertyChainReachable,
  required bool annotationAllowed,
}) {
  if (schema.containsKey('x-mcp-header') && !annotationAllowed) {
    return 'x-mcp-header at "$path" is not statically reachable through '
        'properties';
  }

  final properties = schema['properties'];
  if (properties is Map) {
    for (final entry in properties.entries) {
      final propertySchema = entry.value;
      if (propertySchema is! Map) {
        continue;
      }
      final reason = _findUnreachableToolParameterHeader(
        Map<String, dynamic>.from(propertySchema),
        path: '$path/properties/${_escapePointer(entry.key)}',
        propertyChainReachable: propertyChainReachable,
        annotationAllowed: propertyChainReachable,
      );
      if (reason != null) {
        return reason;
      }
    }
  }

  for (final keyword in _singleSchemaKeywords) {
    final childSchema = schema[keyword];
    if (childSchema is! Map) {
      continue;
    }
    final reason = _findUnreachableToolParameterHeader(
      Map<String, dynamic>.from(childSchema),
      path: '$path/$keyword',
      propertyChainReachable: false,
      annotationAllowed: false,
    );
    if (reason != null) {
      return reason;
    }
  }

  for (final keyword in _schemaArrayKeywords) {
    final childSchemas = schema[keyword];
    if (childSchemas is! List) {
      continue;
    }
    for (var index = 0; index < childSchemas.length; index++) {
      final childSchema = childSchemas[index];
      if (childSchema is! Map) {
        continue;
      }
      final reason = _findUnreachableToolParameterHeader(
        Map<String, dynamic>.from(childSchema),
        path: '$path/$keyword/$index',
        propertyChainReachable: false,
        annotationAllowed: false,
      );
      if (reason != null) {
        return reason;
      }
    }
  }

  for (final keyword in _schemaMapKeywords) {
    final childSchemas = schema[keyword];
    if (childSchemas is! Map) {
      continue;
    }
    for (final entry in childSchemas.entries) {
      final childSchema = entry.value;
      if (childSchema is! Map) {
        continue;
      }
      final reason = _findUnreachableToolParameterHeader(
        Map<String, dynamic>.from(childSchema),
        path: '$path/$keyword/${_escapePointer(entry.key)}',
        propertyChainReachable: false,
        annotationAllowed: false,
      );
      if (reason != null) {
        return reason;
      }
    }
  }

  final dependencies = schema['dependencies'];
  if (dependencies is Map) {
    for (final entry in dependencies.entries) {
      final childSchema = entry.value;
      if (childSchema is! Map) {
        continue;
      }
      final reason = _findUnreachableToolParameterHeader(
        Map<String, dynamic>.from(childSchema),
        path: '$path/dependencies/${_escapePointer(entry.key)}',
        propertyChainReachable: false,
        annotationAllowed: false,
      );
      if (reason != null) {
        return reason;
      }
    }
  }

  return null;
}

/// Removes `x-mcp-header` annotations from every schema location.
///
/// Literal JSON values stored in keywords such as `default`, `const`, and
/// `examples` are preserved.
Map<String, dynamic> stripToolParameterHeaderAnnotations(
  Map<String, dynamic> schema,
) {
  final stripped = Map<String, dynamic>.from(schema)..remove('x-mcp-header');

  final properties = stripped['properties'];
  if (properties is Map) {
    stripped['properties'] = _stripNamedSchemaMap(properties);
  }

  for (final keyword in _singleSchemaKeywords) {
    final childSchema = stripped[keyword];
    if (childSchema is Map) {
      stripped[keyword] = stripToolParameterHeaderAnnotations(
        Map<String, dynamic>.from(childSchema),
      );
    }
  }

  for (final keyword in _schemaArrayKeywords) {
    final childSchemas = stripped[keyword];
    if (childSchemas is List) {
      stripped[keyword] = [
        for (final childSchema in childSchemas)
          if (childSchema is Map)
            stripToolParameterHeaderAnnotations(
              Map<String, dynamic>.from(childSchema),
            )
          else
            childSchema,
      ];
    }
  }

  for (final keyword in _schemaMapKeywords) {
    final childSchemas = stripped[keyword];
    if (childSchemas is Map) {
      stripped[keyword] = _stripNamedSchemaMap(childSchemas);
    }
  }

  final dependencies = stripped['dependencies'];
  if (dependencies is Map) {
    stripped['dependencies'] = _stripNamedSchemaMap(dependencies);
  }

  return stripped;
}

Map<String, dynamic> _stripNamedSchemaMap(Map<dynamic, dynamic> schemas) {
  return <String, dynamic>{
    for (final entry in schemas.entries)
      if (entry.key is String)
        entry.key as String: entry.value is Map
            ? stripToolParameterHeaderAnnotations(
                Map<String, dynamic>.from(entry.value as Map),
              )
            : entry.value,
  };
}

String _escapePointer(Object? segment) {
  return segment.toString().replaceAll('~', '~0').replaceAll('/', '~1');
}
