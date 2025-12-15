// Demonstrates proper completions capability usage per MCP 2025-06-18 spec
//
// This example shows:
// 1. Server declaring completions capability explicitly
// 2. Resource template with argument completion
// 3. Prompt with argument completion
// 4. How completion callbacks work
library;

import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // Server declares completions support explicitly per 2025-06-18 spec
  final server = McpServer(
    const Implementation(name: "completions-demo", version: "1.0.0"),
    options: const ServerOptions(
      capabilities: ServerCapabilities(
        completions: ServerCapabilitiesCompletions(),
        resources: ServerCapabilitiesResources(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  // Add a resource template with argument completion
  // Clients can request completion for the {path} argument
  server.registerResourceTemplate(
    "file-reader",
    ResourceTemplateRegistration(
      "file:///{path}",
      listCallback: null,
      completeCallbacks: {
        'path': (value) async {
          // Simulate file path completion
          // In a real scenario, this would scan the file system
          final suggestions = [
            'README.md',
            'CHANGELOG.md',
            'LICENSE',
            'pubspec.yaml',
            'lib/mcp_dart.dart',
            'lib/src/types.dart',
          ];

          // Filter suggestions based on current value
          final filtered = suggestions
              .where((s) => s.toLowerCase().contains(value.toLowerCase()))
              .toList();

          return filtered.isEmpty ? suggestions : filtered;
        },
      },
    ),
    (
      description: "Read files with auto-completion support",
      mimeType: "text/plain"
    ),
    (uri, variables, extra) async {
      final path = variables['path'] ?? 'unknown';
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'text/plain',
            text:
                'Content of file: $path\n\n(This is a demo - actual file reading not implemented)',
          ),
        ],
      );
    },
  );

  // Add a prompt with argument completion
  server.registerPrompt(
    'code-review',
    description: 'Generate code review for a specific file type',
    argsSchema: {
      'language': PromptArgumentDefinition(
        description: 'Programming language to review',
        required: true,
        type: String,
        completable: CompletableField(
          def: CompletableDef(
            complete: (value) async {
              // Provide language completions
              final languages = [
                'dart',
                'javascript',
                'typescript',
                'python',
                'java',
                'go',
                'rust',
                'c',
                'cpp',
              ];

              // Filter based on current input
              final filtered = languages
                  .where((lang) => lang.startsWith(value.toLowerCase()))
                  .toList();

              return filtered.isEmpty ? languages : filtered;
            },
          ),
        ),
      ),
      'style': PromptArgumentDefinition(
        description: 'Review style',
        required: false,
        type: String,
        completable: CompletableField(
          def: CompletableDef(
            complete: (value) async {
              // Provide style completions
              return [
                'concise',
                'detailed',
                'security-focused',
                'performance-focused',
              ];
            },
          ),
        ),
      ),
    },
    callback: (args, extra) async {
      final language = args?['language'] ?? 'unknown';
      final style = args?['style'] ?? 'detailed';

      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text:
                  'Please provide a $style code review for $language code:\n\n'
                  '(This is where the code would be inserted)',
            ),
          ),
        ],
      );
    },
  );

  // Add a simple tool (no completion - just for demonstration)
  server.registerTool(
    'echo',
    description: 'Echo back the input message',
    inputSchema: const ToolInputSchema(
      properties: {
        'message': {'type': 'string', 'description': 'Message to echo'},
      },
      required: ['message'],
    ),
    callback: (args, extra) async {
      final message = args['message'] ?? '';
      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Echo: $message'),
        ],
      );
    },
  );

  // Connect to stdio transport
  await server.connect(StdioServerTransport());
}
