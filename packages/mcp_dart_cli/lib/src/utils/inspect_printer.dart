import 'dart:convert';

import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

/// Handles formatting and printing of inspection results.
class InspectPrinter {
  final Logger _logger;

  InspectPrinter(this._logger);

  /// Prints tool execution result.
  void printToolResult(CallToolResult result) {
    _logger.info('Result:');
    _logger.info(const JsonEncoder.withIndent('  ').convert(result.content));
  }

  /// Prints resource read result.
  void printResourceResult(ReadResourceResult result) {
    _logger.info('Result:');
    _logger.info(const JsonEncoder.withIndent('  ').convert(result.contents));
  }

  /// Prints prompt retrieval result.
  void printPromptResult(GetPromptResult result) {
    _logger.info('Result:');
    _logger.info(const JsonEncoder.withIndent('  ').convert(result.messages));
  }

  /// Prints all server capabilities (tools, resources, prompts).
  void printCapabilities(
    ListToolsResult tools,
    ListResourcesResult resources,
    ListPromptsResult prompts,
  ) {
    _logger.info('\n--- Capabilities ---\n');

    _printTools(tools);
    _logger.info('');

    _printResources(resources);
    _logger.info('');

    _printPrompts(prompts);
    _logger.info('');
  }

  void _printTools(ListToolsResult tools) {
    if (tools.tools.isEmpty) {
      _logger.info('Tools: (None)');
    } else {
      _logger.info('Tools:');
      for (final tool in tools.tools) {
        _logger.info(
            '  - ${tool.name}: ${tool.description ?? "(no description)"}');
        _printSchemaUsage(tool.inputSchema);
      }
    }
  }

  void _printResources(ListResourcesResult resources) {
    if (resources.resources.isEmpty) {
      _logger.info('Resources: (None)');
    } else {
      _logger.info('Resources:');
      for (final res in resources.resources) {
        final mime = res.mimeType != null ? ' (${res.mimeType})' : '';
        _logger.info('  - ${res.uri}: ${res.name}$mime');
        if (res.description != null) {
          _logger.info('    ${res.description}');
        }
      }
    }
  }

  void _printPrompts(ListPromptsResult prompts) {
    if (prompts.prompts.isEmpty) {
      _logger.info('Prompts: (None)');
    } else {
      _logger.info('Prompts:');
      for (final prompt in prompts.prompts) {
        _logger.info('  - ${prompt.name}: ${prompt.description ?? ""}');
        if (prompt.arguments != null && prompt.arguments!.isNotEmpty) {
          _logger.info('    Arguments:');
          for (final arg in prompt.arguments!) {
            final req = arg.required == true ? ' (required)' : '';
            _logger.info('      ${arg.name}$req: ${arg.description ?? ""}');
          }
        }
      }
    }
  }

  /// Prints the usage information for a tool input schema.
  void _printSchemaUsage(JsonSchema? schema) {
    if (schema is! JsonObject) return;

    final properties = schema.properties;
    final required = schema.required ?? [];

    if (properties != null && properties.isNotEmpty) {
      _logger.info('    Usage:');
      properties.forEach((key, value) {
        final isRequired = required.contains(key);
        String type = _getSchemaType(value);

        final desc = value.description != null ? ' - ${value.description}' : '';

        _logger
            .info('      $key ($type${isRequired ? ', required' : ''})$desc');
      });
    }
  }

  String _getSchemaType(JsonSchema value) {
    if (value is JsonString) return 'string';
    if (value is JsonInteger) return 'integer';
    if (value is JsonNumber) return 'number';
    if (value is JsonBoolean) return 'boolean';
    if (value is JsonArray) return 'array';
    if (value is JsonObject) return 'object';
    return 'unknown';
  }
}
