/// Base class for MCP prompts with modular registration.
///
/// Each prompt implementation should extend this class and provide:
/// - [name]: Unique prompt identifier
/// - [description]: Human-readable description of what the prompt generates
/// - [title]: Optional human-readable title
/// - [argsSchema]: Optional schema defining prompt arguments
/// - [getPrompt]: Implementation to generate prompt content
library;

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

/// Base class for all MCP prompts.
abstract class BasePrompt {
  /// Unique name for this prompt.
  String get name;

  /// Human-readable description of what this prompt generates.
  String get description;

  /// Optional human-readable title for this prompt.
  String? get title => null;

  /// Optional schema defining the arguments this prompt accepts.
  ///
  /// Keys are argument names, values are [PromptArgumentDefinition]s.
  Map<String, PromptArgumentDefinition>? get argsSchema => null;

  /// Generate the prompt content.
  ///
  /// [args] contains the argument values provided by the client.
  /// Returns a [GetPromptResult] with the prompt messages.
  FutureOr<GetPromptResult> getPrompt(
      Map<String, dynamic>? args, RequestHandlerExtra? extra);
}

/// Extension to register prompts with an MCP server.
extension PromptRegistration on McpServer {
  /// Register a [BasePrompt] with this server.
  void registerBasePrompt(BasePrompt prompt) {
    registerPrompt(
      prompt.name,
      title: prompt.title,
      description: prompt.description,
      argsSchema: prompt.argsSchema,
      callback: (args, extra) => prompt.getPrompt(args, extra),
    );
  }
}
