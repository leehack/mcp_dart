/// Maximum allowed length for a URI template string.
const int maxTemplateLength = 1000000;

/// Maximum allowed length for a variable name or value.
const int maxVariableLength = 1000000;

/// Maximum allowed number of template expressions in a template.
const int maxTemplateExpressions = 10000;

/// Type definition for variables used in template expansion.
typedef TemplateVariables
    = Map<String, dynamic /* String | List<String> | Map<String, String> */ >;

/// Base class for different parts parsed from a URI template string.
sealed class _UriTemplatePart {
  const _UriTemplatePart();
}

/// Represents a literal string part of the template.
class _LiteralPart extends _UriTemplatePart {
  final String value;
  const _LiteralPart(this.value);
}

/// Represents an expression part of the template.
class _ExpressionPart extends _UriTemplatePart {
  /// The operator character (e.g., '?', '+', '#') or empty string for simple substitution.
  final String operator;

  /// The list of variable specifications within the expression.
  final List<_VarSpec> varSpecs;

  /// The list of variable names within the expression.
  List<String> get names => varSpecs.map((vs) => vs.name).toList();

  /// Whether the exploded modifier (*) was used.
  bool get exploded => varSpecs.any((vs) => vs.explode);

  /// The first variable name in the list.
  String get name => names.isNotEmpty ? names.first : '';

  const _ExpressionPart(this.operator, this.varSpecs);
}

/// Parses and expands RFC 6570 URI Templates.
///
/// Example:
/// ```dart
/// final template = UriTemplateExpander('/search{?q,lang}');
/// final result = template.expand({'q': 'dart', 'lang': 'en'});
/// print(result); // Output: /search?q=dart&lang=en
/// ```
class UriTemplateExpander {
  /// The original template string.
  final String template;

  /// The internal list of parsed parts (literals and expressions).
  final List<_UriTemplatePart> _parts;

  /// Returns true if the given string contains any URI template expressions (`{...}`).
  static bool isTemplate(String str) {
    return RegExp(r'\{[^}\s]+\}').hasMatch(str);
  }

  /// Validates the length of a string against a maximum.
  static void _validateLength(String str, int max, String context) {
    if (str.length > max) {
      throw ArgumentError(
        '$context exceeds maximum length of $max characters (got ${str.length})',
      );
    }
  }

  /// Parses the [template] string into literal and expression parts.
  ///
  /// Throws [ArgumentError] if the template is invalid.
  factory UriTemplateExpander(String template) {
    _validateLength(template, maxTemplateLength, "Template");
    final parts = _parse(template);
    return UriTemplateExpander._internal(template, parts);
  }

  UriTemplateExpander._internal(this.template, this._parts);

  @override
  String toString() => template;

  static List<_UriTemplatePart> _parse(String template) {
    final parts = <_UriTemplatePart>[];
    StringBuffer currentText = StringBuffer();
    int i = 0;
    int expressionCount = 0;

    while (i < template.length) {
      if (template[i] == '{') {
        if (currentText.isNotEmpty) {
          parts.add(_LiteralPart(currentText.toString()));
          currentText = StringBuffer();
        }
        final end = template.indexOf('}', i);
        if (end == -1) {
          throw ArgumentError(
            "Unclosed template expression starting at index $i",
          );
        }

        expressionCount++;
        if (expressionCount > maxTemplateExpressions) {
          throw ArgumentError(
            'Template contains too many expressions (max $maxTemplateExpressions)',
          );
        }

        final expr = template.substring(i + 1, end);
        if (expr.trim().isEmpty) {
          throw ArgumentError("Empty template expression found at index $i");
        }

        final operator = _getOperator(expr);
        final varSpecs = _parseVarSpecs(expr.substring(operator.length));

        for (final spec in varSpecs) {
          _validateLength(spec.name, maxVariableLength, "Variable name '${spec.name}'");
        }

        parts.add(_ExpressionPart(operator, varSpecs));
        i = end + 1;
      } else {
        currentText.write(template[i]);
        i++;
      }
    }

    if (currentText.isNotEmpty) {
      parts.add(_LiteralPart(currentText.toString()));
    }

    return parts;
  }

  static String _getOperator(String expr) {
    const operators = ['+', '#', '.', '/', ';', '?', '&'];
    for (final op in operators) {
      if (expr.startsWith(op)) {
        return op;
      }
    }
    return '';
  }

  static List<_VarSpec> _parseVarSpecs(String specsString) {
    return specsString.split(',').map((spec) {
      spec = spec.trim();
      bool explode = false;
      int? prefix;

      if (spec.endsWith('*')) {
        explode = true;
        spec = spec.substring(0, spec.length - 1);
      } else {
        final prefixMatch = RegExp(r':(\d+)$').firstMatch(spec);
        if (prefixMatch != null) {
          prefix = int.tryParse(prefixMatch.group(1)!);
          spec = spec.substring(0, prefixMatch.start);
        }
      }

      if (spec.isEmpty ||
          !RegExp(r'^[a-zA-Z0-9_]|(%[0-9A-Fa-f]{2})').hasMatch(spec[0])) {
        if (spec.isNotEmpty) {
          // Allow empty string from splitting trailing comma
        }
      }

      _validateLength(spec, maxVariableLength, "Variable name '$spec'");

      return _VarSpec(spec, explode, prefix);
    }).toList();
  }

  String _encodeValue(String value, String operator) {
    _validateLength(value, maxVariableLength, "Variable value");

    final unreserved = RegExp(r'^[a-zA-Z0-9\-\._~]*$');
    final reserved = RegExp(r"[:/?#[\]@!$&'()*+,;=]");

    StringBuffer result = StringBuffer();
    for (int i = 0; i < value.length; i++) {
      String char = value[i];
      bool shouldEncode = true;

      if (unreserved.hasMatch(char)) {
        shouldEncode = false;
      } else if (reserved.hasMatch(char)) {
        if (operator == '+' || operator == '#') {
          shouldEncode = false;
        }
      }

      if (shouldEncode) {
        result.write(
          Uri.encodeComponent(char)
              .replaceAll('!', '%21')
              .replaceAll("'", '%27')
              .replaceAll('(', '%28')
              .replaceAll(')', '%29')
              .replaceAll('*', '%2A'),
        );
      } else {
        result.write(char);
      }
    }
    return result.toString();
  }

  String _expandPart(_ExpressionPart part, TemplateVariables variables) {
    // Use the variable specs stored in the part during parsing
    final varSpecs = part.varSpecs;

    final result = StringBuffer();
    String separator = switch (part.operator) {
      '+' => ',',
      '#' => ',',
      '.' => '.',
      '/' => '/',
      ';' => ';',
      '?' => '&',
      '&' => '&',
      _ => ',',
    };
    String prefix = switch (part.operator) {
      '+' => '',
      '#' => '#',
      _ => part.operator,
    };
    bool firstValue = true;
    bool useName =
        part.operator == ';' || part.operator == '?' || part.operator == '&';

    for (final spec in varSpecs) {
      final value = variables[spec.name];

      if (value == null) continue;

      String? prefixValue(String valStr) {
        if (spec.prefix == null) return valStr;
        if (spec.prefix! >= valStr.length) return valStr;
        return valStr.substring(0, spec.prefix);
      }

      List<String?>? processList(List listValue) {
        if (listValue.isEmpty) return null;
        final processed = listValue
            .where((item) => item != null)
            .map((item) => prefixValue(item.toString()))
            .where((s) => s != null)
            .map((s) => _encodeValue(s!, part.operator))
            .toList();
        return processed.isEmpty ? null : processed;
      }

      Map<String, String?>? processMap(Map mapValue) {
        if (mapValue.isEmpty) return null;
        final processed = <String, String?>{};
        mapValue.forEach((key, val) {
          if (val != null) {
            final keyStr = _encodeValue(key.toString(), part.operator);
            final valStr = prefixValue(val.toString());
            if (valStr != null) {
              processed[keyStr] = _encodeValue(valStr, part.operator);
            }
          }
        });
        return processed.isEmpty ? null : processed;
      }

      if (value is List) {
        final processedList = processList(value);
        if (processedList == null) continue;

        if (spec.explode) {
          for (final itemStr in processedList) {
            if (!firstValue) result.write(separator);
            if (useName) result.write('${spec.name}=');
            result.write(itemStr);
            firstValue = false;
          }
        } else {
          if (!firstValue) result.write(separator);
          if (useName) result.write('${spec.name}=');
          result.write(processedList.join(','));
          firstValue = false;
        }
      } else if (value is Map) {
        final processedMap = processMap(value);
        if (processedMap == null) continue;

        if (spec.explode) {
          processedMap.forEach((key, val) {
            if (!firstValue) result.write(separator);
            result.write(key);
            result.write('=');
            result.write(val);
            firstValue = false;
          });
        } else {
          if (!firstValue) result.write(separator);
          if (useName) result.write('${spec.name}=');
          final kvList = <String>[];
          processedMap.forEach((key, val) {
            kvList.add(key);
            kvList.add(val!);
          });
          result.write(kvList.join(','));
          firstValue = false;
        }
      } else {
        final valueStr = prefixValue(value.toString());
        if (valueStr == null) continue;

        final encodedValue = _encodeValue(valueStr, part.operator);

        if (!firstValue) result.write(separator);

        if (useName) {
          result.write(spec.name);
          if (encodedValue.isNotEmpty || part.operator == ';') {
            result.write('=');
          }
        }
        result.write(encodedValue);
        firstValue = false;
      }
    }

    if (result.isEmpty) {
      return "";
    }

    return prefix + result.toString();
  }

  /// Expands the template using the provided [variables].
  ///
  /// Variables not found in the map are skipped.
  /// Values in the [variables] map can be [String], [List<String>], or [Map<String, String>].
  /// Null values within lists/maps or assigned directly to variables are ignored.
  String expand(TemplateVariables variables) {
    final output = StringBuffer();
    for (final part in _parts) {
      if (part is _LiteralPart) {
        output.write(part.value);
      } else if (part is _ExpressionPart) {
        output.write(_expandPart(part, variables));
      }
    }
    return output.toString();
  }

  /// Attempts to match a given [uri] against the template structure.
  ///
  /// Returns a map of extracted variables, or null if the URI doesn't match
  /// the basic template structure.
  TemplateVariables? match(String uri) {
    const String valuePattern = r'([^/]+?)';

    StringBuffer pattern = StringBuffer('^');
    final List<String> varNames = [];

    for (final part in _parts) {
      if (part is _LiteralPart) {
        pattern.write(RegExp.escape(part.value));
      } else if (part is _ExpressionPart) {
        bool firstInExpr = true;
        for (final name in part.names) {
          if (!firstInExpr) {
            pattern.write(',');
          }
          switch (part.operator) {
            case '+':
            case '#':
              pattern.write(valuePattern);
              break;
            case '.':
              pattern.write(r'\.');
              pattern.write(valuePattern);
              break;
            case '/':
              pattern.write(r'/');
              pattern.write(valuePattern);
              break;
            case ';':
              pattern.write(';');
              pattern.write(name);
              pattern.write('=');
              pattern.write(valuePattern);
              break;
            case '?':
              pattern.write(r'\?');
              pattern.write(name);
              pattern.write('=');
              pattern.write(valuePattern);
              break;
            case '&':
              pattern.write('&');
              pattern.write(name);
              pattern.write('=');
              pattern.write(valuePattern);
              break;
            default:
              pattern.write(valuePattern);
              break;
          }
          varNames.add(name);
          firstInExpr = false;
        }
      }
    }
    pattern.write(r'$');

    RegExp regex;
    try {
      regex = RegExp(pattern.toString());
    } catch (e) {
      return null;
    }

    final match = regex.firstMatch(uri);

    if (match == null) return null;

    final result = <String, dynamic>{};
    if (match.groupCount == varNames.length) {
      for (int i = 0; i < varNames.length; i++) {
        final value = match.group(i + 1);
        if (value != null) {
          try {
            result[varNames[i]] = Uri.decodeComponent(value);
          } catch (_) {
            result[varNames[i]] = value;
          }
        }
      }
    } else {
      return null;
    }

    return result.isEmpty ? null : result;
  }
}

/// Represents a variable specification within an expression.
class _VarSpec {
  final String name;
  final bool explode;
  final int? prefix;

  _VarSpec(this.name, this.explode, this.prefix);
}
