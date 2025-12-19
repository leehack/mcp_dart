/// MCP prompts for the server.
library;

import 'base_prompt.dart';
import 'hello_prompt.dart';

export 'base_prompt.dart';
export 'hello_prompt.dart';

/// Creates all available prompts.
List<BasePrompt> createAllPrompts() => [
      HelloPrompt(),
    ];
