/// MCP protocol components for the server.
library;

import 'package:mcp_dart/mcp_dart.dart';

import 'prompts/prompts.dart';
import 'resources/resources.dart';
import 'tools/tools.dart';

export 'prompts/prompts.dart';
export 'resources/resources.dart';
export 'tools/tools.dart';

/// Creates a fully configured MCP server instance.
McpServer createMcpServer() {
  final server = McpServer(
    Implementation(name: '{{name}}', version: '1.0.0'),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
      ),
    ),
  );

  // Register all tools
  for (final tool in createAllTools()) {
    server.registerBaseTool(tool);
  }

  // Register all resources
  for (final resource in createAllResources()) {
    server.registerBaseResource(resource);
  }

  // Register all prompts
  for (final prompt in createAllPrompts()) {
    server.registerBasePrompt(prompt);
  }

  return server;
}
