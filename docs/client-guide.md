# Client Guide

Complete guide to building MCP clients with the Dart SDK.

## Table of Contents

- [Creating a Client](#creating-a-client)
- [Client Capabilities](#client-capabilities)
- [Calling Tools](#calling-tools)
- [Reading Resources](#reading-resources)
- [Using Prompts](#using-prompts)
- [Sampling Requests](#sampling-requests)
- [Completions](#completions)
- [Managing Roots](#managing-roots)
- [Logging](#logging)
- [Advanced Topics](#advanced-topics)

## Creating a Client

### Basic Client Setup

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final client = Client(
    Implementation(
      name: 'my-client',
      version: '1.0.0',
    ),
  );

  // Connect to a server
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: 'node',
      args: ['server.js'],
    ),
  );
  await client.connect(transport);

  // Use the server's capabilities

  // Clean up
  await client.close();
}
```

### Client Configuration Options

```dart
final client = Client(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
);

// Optional: Handle elicitation requests (user input from server)
// Set up handlers after client creation if needed
```

## Client Capabilities

Declare what your client supports:

```dart
final client = Client(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
);
// Capabilities are negotiated during connection
```

## Calling Tools

### List Available Tools

```dart
// Get all tools
final response = await client.listTools();

for (final tool in response.tools) {
  print('Tool: ${tool.name}');
  print('  Description: ${tool.description}');
  print('  Schema: ${tool.inputSchema}');
}
```

### Call a Tool

```dart
// Simple tool call
final result = await client.callTool(
  CallToolRequestParams(
    name: 'greet',
    arguments: {'name': 'Alice'},
  ),
);

// Access results
for (final content in result.content) {
  if (content is TextContent) {
    print(content.text);
  } else if (content is ImageContent) {
    print('Image: ${content.mimeType}');
  }
}
```

### Handle Tool Errors

```dart
try {
  final result = await client.callTool(
    CallToolRequestParams(
      name: 'divide',
      arguments: {'a': 10, 'b': 0},
    ),
  );

  if (result.isError == true) {
    print('Tool returned error: ${result.content.first.text}');
  } else {
    print('Result: ${result.content.first.text}');
  }
} catch (e) {
  if (e is McpError) {
    print('MCP Error: ${e.message} (code: ${e.code})');
  } else {
    print('Unexpected error: $e');
  }
}
```

### Tool Progress Tracking

```dart
// Request progress notifications
final result = await client.callTool(
  CallToolRequestParams(
    name: 'process-large-file',
    arguments: {'file': 'large.dat'},
  ),
  // Progress token for tracking
  _meta: {
    'progressToken': 'progress-123',
  },
);

// Listen for progress (set up before calling tool)
client.onProgress = (notification) {
  if (notification.progressToken == 'progress-123') {
    print('Progress: ${notification.progress}/${notification.total}');
  }
};
```

### Cancel Tool Execution

```dart
final progressToken = 'cancel-me-123';

// Start long-running tool
final future = client.callTool(CallToolRequestParams(
  name: 'long-operation',
  arguments: {},
  _meta: {'progressToken': progressToken},
));

// Cancel after 5 seconds
await Future.delayed(Duration(seconds: 5));
await client.cancelRequest(progressToken);

// The tool call will be cancelled
try {
  await future;
} catch (e) {
  print('Tool was cancelled: $e');
}
```

## Reading Resources

### List Available Resources

```dart
// Get all resources
final response = await client.listResources();

for (final resource in response.resources) {
  print('Resource: ${resource.name}');
  print('  URI: ${resource.uri}');
  print('  Description: ${resource.description}');
  print('  MIME: ${resource.mimeType}');
}
```

### Read a Resource

```dart
// Read specific resource
final result = await client.readResource(
  ReadResourceRequestParams(
    uri: 'file:///docs/readme.md',
  ),
);

for (final content in result.contents) {
  if (content is TextResourceContents) {
    print('Text content:');
    print(content.text);
  } else if (content is BlobResourceContents) {
    print('Binary content: ${content.blob.length} bytes');
    final bytes = base64Decode(content.blob);
    // Use bytes...
  }
}
```

### Subscribe to Resource Updates

```dart
// Subscribe to changes
await client.subscribeResource(
  SubscribeRequestParams(
    uri: 'file:///data/metrics.json',
  ),
);

// Listen for updates
client.onResourceUpdated = (notification) {
  print('Resource updated: ${notification.uri}');

  // Re-read the resource
  client.readResource(
    ReadResourceRequestParams(
      uri: notification.uri,
    ),
  ).then((result) {
    print('New content: ${result.contents.first.text}');
  });
};

// Unsubscribe when done
await client.unsubscribeResource(
  UnsubscribeRequestParams(
    uri: 'file:///data/metrics.json',
  ),
);
```

### Resource Templates

```dart
// List resources to discover templates
final response = await client.listResources();

for (final resource in response.resources) {
  if (resource.uri.contains('{')) {
    print('Template: ${resource.uri}');
    print('  Example: ${_expandTemplate(resource.uri)}');
  }
}

// Read from template
final result = await client.readResource(
  ReadResourceRequestParams(
    uri: 'users://alice/profile',  // Expands template
  ),
);
```

## Using Prompts

### List Available Prompts

```dart
// Get all prompts
final response = await client.listPrompts();

for (final prompt in response.prompts) {
  print('Prompt: ${prompt.name}');
  print('  Description: ${prompt.description}');

  if (prompt.arguments != null) {
    print('  Arguments:');
    for (final arg in prompt.arguments!) {
      print('    - ${arg.name}: ${arg.description} '
            '(required: ${arg.required})');
    }
  }
}
```

### Get a Prompt

```dart
// Get prompt without arguments
final result = await client.getPrompt(
  GetPromptRequestParams(
    name: 'code-review',
  ),
);

print('Description: ${result.description}');
for (final message in result.messages) {
  print('${message.role}: ${message.content.text}');
}
```

### Get Prompt with Arguments

```dart
// Get prompt with arguments
final result = await client.getPrompt(
  GetPromptRequestParams(
    name: 'translate',
    arguments: {
      'target_language': 'Spanish',
      'formality': 'formal',
    },
  ),
);

// Use the prompt messages with an LLM
for (final message in result.messages) {
  print('${message.role}: ${message.content.text}');
}
```

### Handle Embedded Resources in Prompts

```dart
final result = await client.getPrompt(
  GetPromptRequestParams(
    name: 'analyze-file',
    arguments: {'file_uri': 'file:///data.json'},
  ),
);

for (final message in result.messages) {
  final content = message.content;

  if (content is TextContent) {
    print('Text: ${content.text}');
  } else if (content is EmbeddedResource) {
    // Resolve the embedded resource
    final resourceUri = content.resource.uri;
    final resourceData = await client.readResource(
      ReadResourceRequestParams(uri: resourceUri),
    );
    print('Embedded: ${resourceData.contents.first.text}');
  }
}
```

## Sampling Requests

Handle LLM sampling requests from the server (server asking client to use an LLM):

```dart
final client = Client(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
  capabilities: ClientCapabilities(
    sampling: {},  // Enable sampling capability
  ),
);

// Server will send sampling requests via notifications
// You need to handle them in your client implementation
```

Example sampling handler (low-level):

```dart
// This is handled automatically if you integrate with an LLM
// For custom handling:

client.onSamplingRequest = (request) async {
  // request.params contains:
  // - messages: Conversation messages
  // - modelPreferences: Cost/speed/intelligence priorities
  // - systemPrompt: Optional system prompt
  // - includeContext: What context to include
  // - temperature, maxTokens, stopSequences, etc.

  // Call your LLM (e.g., Anthropic, OpenAI, Gemini)
  final llmResponse = await callLLM(
    messages: request.params.messages,
    systemPrompt: request.params.systemPrompt,
    maxTokens: request.params.maxTokens,
  );

  return CreateMessageResult(
    role: Role.assistant,
    content: TextContent(text: llmResponse),
    model: 'gpt-4',
    stopReason: StopReason.endTurn,
  );
};
```

## Completions

Get argument completion suggestions:

```dart
// Complete resource template variable
final result = await client.complete(
  CompleteRequestParams(
    ref: CompletionReference(
      type: CompletionReferenceType.resourceRef,
      uri: 'users://{userId}/profile',
    ),
    argument: CompletionArgument(
      name: 'userId',
      value: 'ali',  // Partial value
    ),
  ),
);

print('Suggestions:');
for (final completion in result.completion.values) {
  print('  - ${completion}');
}

if (result.completion.hasMore == true) {
  print('More suggestions available...');
}
```

```dart
// Complete prompt argument
final result = await client.complete(
  CompleteRequestParams(
    ref: CompletionReference(
      type: CompletionReferenceType.promptRef,
      name: 'translate',
    ),
    argument: CompletionArgument(
      name: 'target_language',
      value: 'Spa',  // Partial value
    ),
  ),
);

// Get suggestions for target_language
for (final lang in result.completion.values) {
  print('  - $lang');
}
```

## Managing Roots

Roots are filesystem locations the client exposes to the server:

```dart
final client = Client(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
  capabilities: ClientCapabilities(
    roots: RootsCapability(
      listChanged: true,
    ),
  ),
);

// Implement roots listing
client.onListRoots = () async {
  return ListRootsResult(
    roots: [
      Root(
        uri: 'file:///home/user/projects',
        name: 'Projects',
      ),
      Root(
        uri: 'file:///home/user/documents',
        name: 'Documents',
      ),
    ],
  );
};

// Notify server when roots change
await client.sendRootsListChanged();
```

## Logging

### Set Logging Level

```dart
// Set server's logging level
await client.setLoggingLevel(
  SetLevelRequestParams(
    level: LoggingLevel.debug,
  ),
);
```

### Receive Log Messages

```dart
// Listen for server logs
client.onLogMessage = (notification) {
  final level = notification.level;
  final message = notification.data;
  final logger = notification.logger ?? 'server';

  print('[$level] $logger: $message');
};
```

## Advanced Topics

### Connection Management

```dart
// Connect
await client.connect(transport);

// Check connection
if (client.isConnected) {
  print('Connected to server');
}

// Graceful disconnect
await client.close();
```

### Reconnection Logic

```dart
Future<void> connectWithRetry(Client client, Transport transport) async {
  var retries = 0;
  const maxRetries = 3;

  while (retries < maxRetries) {
    try {
      await client.connect(transport);
      print('Connected successfully');
      return;
    } catch (e) {
      retries++;
      print('Connection failed (attempt $retries/$maxRetries): $e');

      if (retries < maxRetries) {
        await Future.delayed(Duration(seconds: 2 * retries));
      } else {
        rethrow;
      }
    }
  }
}
```

### Capability Negotiation

```dart
// After connection, check server capabilities
final serverCapabilities = client.serverCapabilities;

if (serverCapabilities?.tools != null) {
  print('Server supports tools');
  // List and call tools
}

if (serverCapabilities?.resources != null) {
  print('Server supports resources');
  if (serverCapabilities!.resources!.subscribe == true) {
    print('Server supports resource subscriptions');
  }
}

if (serverCapabilities?.prompts != null) {
  print('Server supports prompts');
}
```

### Batching Requests

```dart
// Make multiple requests efficiently
final results = await Future.wait([
  client.listTools(),
  client.listResources(),
  client.listPrompts(),
]);

final tools = results[0] as ListToolsResult;
final resources = results[1] as ListResourcesResult;
final prompts = results[2] as ListPromptsResult;

print('Server has:');
print('  ${tools.tools.length} tools');
print('  ${resources.resources.length} resources');
print('  ${prompts.prompts.length} prompts');
```

### Error Recovery

```dart
Future<CallToolResult?> callToolSafely(
  Client client,
  String toolName,
  Map<String, dynamic> args,
) async {
  try {
    return await client.callTool(
      CallToolRequestParams(
        name: toolName,
        arguments: args,
      ),
    );
  } on McpError catch (e) {
    switch (e.code) {
      case ErrorCode.methodNotFound:
        print('Tool not found: $toolName');
        break;
      case ErrorCode.invalidParams:
        print('Invalid parameters for $toolName: ${e.message}');
        break;
      case ErrorCode.timeout:
        print('Tool call timed out');
        break;
      default:
        print('MCP error: ${e.message}');
    }
    return null;
  } catch (e) {
    print('Unexpected error: $e');
    return null;
  }
}
```

### Notification Handlers

```dart
// Set up all notification handlers
void setupNotifications(Client client) {
  // Resource updates
  client.onResourceUpdated = (notification) {
    print('Resource updated: ${notification.uri}');
  };

  client.onResourceListChanged = () {
    print('Resource list changed');
    // Re-fetch resource list
  };

  // Tool updates
  client.onToolListChanged = () {
    print('Tool list changed');
    // Re-fetch tool list
  };

  // Prompt updates
  client.onPromptListChanged = () {
    print('Prompt list changed');
    // Re-fetch prompt list
  };

  // Progress
  client.onProgress = (notification) {
    print('Progress: ${notification.progress}/${notification.total}');
  };

  // Logging
  client.onLogMessage = (notification) {
    print('[${notification.level}] ${notification.data}');
  };
}
```

### Timeout Handling

```dart
// Custom timeout per request
try {
  final result = await client
      .callTool(
        CallToolRequestParams(
          name: 'slow-tool',
          arguments: {},
        ),
      )
      .timeout(Duration(seconds: 60));
} on TimeoutException {
  print('Tool call timed out');
}
```

## Best Practices

### 1. Always Close Connections

```dart
Future<void> useClient() async {
  final client = Client(
    Implementation(name: 'client', version: '1.0.0'),
  );

  try {
    await client.connect(transport);
    // Use client...
  } finally {
    await client.close();  // Always clean up
  }
}
```

### 2. Handle All Error Cases

```dart
// ✅ Good - comprehensive error handling
try {
  final result = await client.callTool(request);

  if (result.isError == true) {
    // Handle tool-level error
    handleToolError(result);
  } else {
    processResult(result);
  }
} on McpError catch (e) {
  // Handle protocol error
  handleMcpError(e);
} on TimeoutException {
  // Handle timeout
  handleTimeout();
} catch (e) {
  // Handle unexpected error
  handleUnexpectedError(e);
}

// ❌ Bad - no error handling
final result = await client.callTool(request);
processResult(result);
```

### 3. Check Capabilities Before Use

```dart
// ✅ Good
if (client.serverCapabilities?.resources?.subscribe == true) {
  await client.subscribeResource(SubscribeRequestParams(uri: uri));
} else {
  // Fallback: poll for changes
  pollResourceForChanges(uri);
}

// ❌ Bad - assume capability exists
await client.subscribeResource(SubscribeRequestParams(uri: uri));
```

### 4. Use Progress for Long Operations

```dart
// ✅ Good - track progress
final progressToken = 'progress-${DateTime.now().millisecondsSinceEpoch}';

client.onProgress = (notification) {
  if (notification.progressToken == progressToken) {
    updateUI(notification.progress, notification.total);
  }
};

await client.callTool(
  CallToolRequestParams(
    name: 'long-task',
    arguments: {},
    _meta: {'progressToken': progressToken},
  ),
);

// ❌ Bad - no feedback for user
await client.callTool(
  CallToolRequestParams(
    name: 'long-task',
    arguments: {},
  ),
);
```

### 5. Resource Subscription Management

```dart
// ✅ Good - track subscriptions
final subscriptions = <String>{};

Future<void> subscribe(String uri) async {
  if (!subscriptions.contains(uri)) {
    await client.subscribeResource(SubscribeRequestParams(uri: uri));
    subscriptions.add(uri);
  }
}

Future<void> unsubscribe(String uri) async {
  if (subscriptions.contains(uri)) {
    await client.unsubscribeResource(UnsubscribeRequestParams(uri: uri));
    subscriptions.remove(uri);
  }
}

// Clean up all subscriptions
Future<void> cleanUp() async {
  await Future.wait(
    subscriptions.map((uri) =>
      client.unsubscribeResource(UnsubscribeRequestParams(uri: uri)),
    ),
  );
  subscriptions.clear();
}
```

## Next Steps

- [Transports Guide](transports.md) - Choosing the right transport
- [Examples](examples.md) - Real-world client implementations
