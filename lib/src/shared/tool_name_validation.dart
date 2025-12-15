import 'logging.dart';

final _logger = Logger("mcp_dart.shared.tool_name_validation");

/// Regular expression for valid tool names according to SEP-986 specification
final _toolNameRegex = RegExp(r'^[A-Za-z0-9._-]{1,128}$');

class ToolNameValidationResult {
  final bool isValid;
  final List<String> warnings;

  const ToolNameValidationResult({
    required this.isValid,
    required this.warnings,
  });
}

/// Validates a tool name according to the SEP specification
///
/// Tool names SHOULD be between 1 and 128 characters in length (inclusive).
/// Tool names are case-sensitive.
/// Allowed characters: uppercase and lowercase ASCII letters (A-Z, a-z), digits
/// (0-9), underscore (_), dash (-), and dot (.).
/// Tool names SHOULD NOT contain spaces, commas, or other special characters.
ToolNameValidationResult validateToolName(String name) {
  final warnings = <String>[];

  // Check length
  if (name.isEmpty) {
    return const ToolNameValidationResult(
      isValid: false,
      warnings: ['Tool name cannot be empty'],
    );
  }

  if (name.length > 128) {
    return ToolNameValidationResult(
      isValid: false,
      warnings: [
        'Tool name exceeds maximum length of 128 characters (current: ${name.length})',
      ],
    );
  }

  // Check for specific problematic patterns
  if (name.contains(' ')) {
    warnings.add('Tool name contains spaces, which may cause parsing issues');
  }

  if (name.contains(',')) {
    warnings.add('Tool name contains commas, which may cause parsing issues');
  }

  // Check for potentially confusing patterns
  if (name.startsWith('-') || name.endsWith('-')) {
    warnings.add(
      'Tool name starts or ends with a dash, which may cause parsing issues in some contexts',
    );
  }

  if (name.startsWith('.') || name.endsWith('.')) {
    warnings.add(
      'Tool name starts or ends with a dot, which may cause parsing issues in some contexts',
    );
  }

  // Check for invalid characters
  if (!_toolNameRegex.hasMatch(name)) {
    final invalidChars = name
        .split('')
        .where((char) => !RegExp(r'[A-Za-z0-9._-]').hasMatch(char))
        .toSet()
        .toList(); // Remove duplicates

    warnings.addAll([
      'Tool name contains invalid characters: ${invalidChars.map((c) => '"$c"').join(', ')}',
      'Allowed characters are: A-Z, a-z, 0-9, underscore (_), dash (-), and dot (.)',
    ]);

    return ToolNameValidationResult(
      isValid: false,
      warnings: warnings,
    );
  }

  return ToolNameValidationResult(
    isValid: true,
    warnings: warnings,
  );
}

/// Issues warnings for non-conforming tool names
void issueToolNameWarning(String name, List<String> warnings) {
  if (warnings.isNotEmpty) {
    _logger.warn('Tool name validation warning for "$name":');
    for (final warning in warnings) {
      _logger.warn('  - $warning');
    }
    _logger.warn(
      'Tool registration will proceed, but this may cause compatibility issues.',
    );
    _logger.warn(
      'Consider updating the tool name to conform to the MCP tool naming standard.',
    );
    _logger.warn(
      'See SEP: Specify Format for Tool Names (https://github.com/modelcontextprotocol/modelcontextprotocol/issues/986) for more details.',
    );
  }
}

/// Validates a tool name and issues warnings for non-conforming names
/// @returns true if the name is valid, false otherwise
bool validateAndWarnToolName(String name) {
  final result = validateToolName(name);

  // Always issue warnings for any validation issues (both invalid names and warnings)
  issueToolNameWarning(name, result.warnings);

  return result.isValid;
}
