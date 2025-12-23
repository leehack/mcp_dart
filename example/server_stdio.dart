import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final McpServer server = McpServer(
    const Implementation(name: "example_server", version: "1.0.0"),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        resources: ServerCapabilitiesResources(),
        tools: ServerCapabilitiesTools(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  server.registerTool(
    'calculate',
    description: 'Perform basic arithmetic operations',
    inputSchema: JsonSchema.object(
      properties: {
        'operation': JsonSchema.string(
          enumValues: ['add', 'subtract', 'multiply', 'divide'],
        ),
        'a': JsonSchema.number(),
        'b': JsonSchema.number(),
      },
      required: ['operation', 'a', 'b'],
    ),
    callback: (args, extra) async {
      final operation = args['operation'];
      final a = args['a'];
      final b = args['b'];
      return CallToolResult.fromContent(
        [
          TextContent(
            text: switch (operation) {
              'add' => 'Result: ${a + b}',
              'subtract' => 'Result: ${a - b}',
              'multiply' => 'Result: ${a * b}',
              'divide' => 'Result: ${a / b}',
              _ => throw Exception('Invalid operation'),
            },
          ),
        ],
      );
    },
  );

  server.registerResource("Application Logs", 'file:///logs', null,
      (uri, extra) async {
    if (uri.scheme != 'file') {
      throw Exception('Invalid URI scheme: ${uri.scheme}');
    }
    if (uri.path != '/logs') {
      throw Exception('Invalid URI path: ${uri.path}');
    }

    // Uncomment the following lines to read from a file
    // final file = File(uri.path);
    // if (!await file.exists()) {
    //   throw Exception('File not found: ${uri.path}');
    // }
    // final text = await file.readAsString();
    final text = 'Sample log content';
    return ReadResourceResult(
      contents: [
        TextResourceContents(uri: uri.path, mimeType: 'text/plain', text: text),
      ],
    );
  });

  server.registerPrompt(
    'analyze-code',
    description: 'Analyze code for potential improvements',
    argsSchema: {
      'language': const PromptArgumentDefinition(
        type: String,
        description: 'Programming language',
        required: true,
      ),
    },
    callback: (args, extra) async {
      return const GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text:
                  'Please analyze the following Python code for potential improvements:\n\n```python\ndef calculate_sum(numbers):\n    total = 0\n    for num in numbers:\n        total = total + num\n    return total\n\nresult = calculate_sum([1, 2, 3, 4, 5])\nprint(result)\n```',
            ),
          ),
        ],
      );
    },
  );

  server.connect(StdioServerTransport());
}
