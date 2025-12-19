import 'package:mcp_dart/mcp_dart.dart';

import 'base_prompt.dart';

/// A simple hello prompt.
class HelloPrompt extends BasePrompt {
  @override
  String get name => 'hello-world';

  @override
  String get description => 'A simple hello world prompt';

  @override
  Map<String, PromptArgumentDefinition>? get argsSchema => {
        'name': PromptArgumentDefinition(
          description: 'The name to say hello to',
          required: false,
        ),
      };

  @override
  GetPromptResult getPrompt(
      Map<String, dynamic>? args, RequestHandlerExtra? extra) {
    final name = args?['name'] as String? ?? 'World';
    return GetPromptResult(
      description: 'A friendly greeting',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Hello, $name!'),
        ),
      ],
    );
  }
}
