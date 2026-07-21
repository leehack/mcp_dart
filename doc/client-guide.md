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
  final client = McpClient(
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
final client = McpClient(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
);

// Optional: Handle elicitation requests (user input from server)
// Set up handlers after client creation if needed
```

### Protocol Profile

Clients in the 2.3.0 preview use `McpProtocol.stable` by default, which
prefers MCP `2026-07-28` negotiation. The default client probes with
`server/discover`, sends stateless request metadata for a compatible peer, and
falls back to legacy `initialize` when discovery is unavailable. On body-only
transports such as stdio, a silent discovery probe is bounded to five seconds;
HTTP transports retain their normal request timeout because an HTTP timeout
indicates an outage rather than a legacy peer. Select the legacy profile
explicitly when a deployment must skip discovery and use only MCP `2025-11-25`
and earlier behavior:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(protocol: McpProtocol.legacy),
);
```

Use `McpClientOptions(protocol: McpProtocol.require2026)` when fallback should
be treated as an error.

## Client Capabilities

Declare what your client supports:

```dart
final client = McpClient(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
);
// Capabilities are negotiated during connection
```

### MCP Apps Extension Capability

Advertise support for MCP Apps (`io.modelcontextprotocol/ui`) during initialization:

```dart
final client = McpClient(
  const Implementation(name: 'my-host', version: '1.0.0'),
  options: McpClientOptions(
    capabilities: ClientCapabilities(
      extensions: withMcpUiExtension(),
    ),
  ),
);

await client.connect(transport);

if (getUiCapability(client.getServerCapabilities())
        ?.supportsMimeType(mcpUiResourceMimeType) ??
    false) {
  // Server supports text/html;profile=mcp-app
}
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
  CallToolRequest(
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
  } else if (content is ResourceLink) {
    print('Linked resource: ${content.uri}');
  }
}
```

### Receive Tool Progress

You can provide a callback to receive progress updates from long-running tools.

```dart
final result = await client.callTool(
  CallToolRequest(
    name: 'long-running-tool',
    arguments: {},
  ),
  options: RequestOptions(
    onprogress: (progress) {
      print('Progress: ${progress.progress}/${progress.total}');
      if (progress.message != null) {
        print('Status: ${progress.message}');
      }
    },
  ),
);
```

### Task-Augmented Tool Calls

For MCP `2026-07-28` stateless servers that advertise the
`io.modelcontextprotocol/tasks` extension, task creation is server-directed.
Call `client.callTool()` normally, or call `TaskClient.callToolStream()` without
the legacy `task` argument; the client follows `resultType: "task"` with
`tasks/get`, using `tasks/update` only when the server requests more input,
until the final tool result is available.

For legacy MCP `2025-11-25` task augmentation only, callers can pass task
creation parameters through the `task` argument. That legacy path requires
`tasks.requests.tools.call` plus tool `execution.taskSupport`; do not send the
legacy argument on an MCP 2026-07-28 extension session.

```dart
final taskClient = TaskClient(client);

await for (final event in taskClient.callToolStream(
  'slow-tool',
  {'query': 'large job'},
)) {
  switch (event) {
    case TaskCreatedMessage(:final task):
      print('Created task: ${task.taskId}');
    case TaskStatusMessage(:final task):
      print('Task status: ${task.status}');
    case TaskResultMessage(:final result):
      print('Tool result: ${result.content.length} content blocks');
    case TaskErrorMessage(:final error):
      print('Task error: $error');
  }
}
```

### Handle Tool Errors

```dart
try {
  final result = await client.callTool(
    CallToolRequest(
      name: 'divide',
      arguments: {'a': 10, 'b': 0},
    ),
  );

  final content = result.content.first;
  if (result.isError == true) {
    print(
      'Tool returned error: ${content is TextContent ? content.text : content.toJson()}',
    );
  } else {
    print(
      'Result: ${content is TextContent ? content.text : content.toJson()}',
    );
  }
} catch (e) {
  if (e is McpError) {
    print('MCP Error: ${e.message} (code: ${e.code})');
  } else {
    print('Unexpected error: $e');
  }
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
  print('  Size: ${resource.size ?? "unknown"}');
  print('  Last modified: ${resource.annotations?.lastModified}');
  print('  Icons: ${resource.icons?.length ?? 0}');
}
```

### Read a Resource

```dart
// Read specific resource
final result = await client.readResource(
  ReadResourceRequest(
    uri: 'file:///docs/readme.md',
  ),
);

for (final content in result.contents) {
  if (content is TextResourceContents) {
    print('Text content:');
    print(content.text);
  } else if (content is BlobResourceContents) {
    final bytes = base64Decode(content.blob);
    print('Binary content: ${bytes.length} bytes');
    // Use bytes...
  }
}
```

### Listen for Resource Updates (MCP 2026-07-28)

The default MCP 2026-07-28 stateless profile uses `subscriptions/listen`. The
returned handle exposes the required acknowledgment, filtered notification
stream, graceful completion, and cancellation:

```dart
final subscription = client.listenSubscriptions(
  const SubscriptionsListenRequest(
    notifications: SubscriptionFilter(
      resourceSubscriptions: ['file:///data/metrics.json'],
    ),
  ),
);

final acknowledged = await subscription.acknowledged;
print(acknowledged.notifications.resourceSubscriptions);

// Reconnecting transports emit this only if a replacement stream
// acknowledges a different subset of the original filter.
final acknowledgmentChanges =
    subscription.acknowledgmentChanges.listen((replacement) {
  print('Replacement subscription filter: ${replacement.notifications}');
});

final listener = subscription.notifications.listen((notification) async {
  if (notification is JsonRpcResourceUpdatedNotification) {
    final result = await client.readResource(
      ReadResourceRequest(uri: notification.updatedParams.uri),
    );
    print('Updated content blocks: ${result.contents.length}');
  }
});

// When this caller no longer needs updates:
subscription.cancel();
await listener.cancel();
await acknowledgmentChanges.cancel();
```

### Subscribe to Resource Updates (MCP 2025-11-25)

Legacy stateful peers use `resources/subscribe`, global notifications, and
`resources/unsubscribe`. These methods are removed from the MCP 2026-07-28
profile.

```dart
// Subscribe to changes
await client.subscribeResource(
  SubscribeRequest(
    uri: 'file:///data/metrics.json',
  ),
);

// Listen for updates
client.setNotificationHandler<JsonRpcResourceUpdatedNotification>(
  Method.notificationsResourcesUpdated,
  (notification) async {
    final uri = notification.updatedParams.uri;
    print('Resource updated: $uri');

    // Re-read the resource
    final result = await client.readResource(
      ReadResourceRequest(uri: uri),
    );
    if (result.contents.isNotEmpty && result.contents.first is TextResourceContents) {
      print('New content: ${(result.contents.first as TextResourceContents).text}');
    }
  },
  (params, meta) {
    if (params == null) {
      throw const FormatException(
        'Missing params for resource update notification',
      );
    }

    return JsonRpcResourceUpdatedNotification(
      updatedParams: ResourceUpdatedNotification.fromJson(params),
      meta: meta,
    );
  },
);

// Unsubscribe when done
await client.unsubscribeResource(
  UnsubscribeRequest(
    uri: 'file:///data/metrics.json',
  ),
);
```

### Resource Templates

```dart
// Templates have their own discovery method.
final response = await client.listResourceTemplates();

for (final template in response.resourceTemplates) {
  print('Template: ${template.uriTemplate}');
}

// Expand the advertised template with values from your application.
final result = await client.readResource(
  ReadResourceRequest(
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
  GetPromptRequest(
    name: 'code-review',
  ),
);

print('Description: ${result.description}');
for (final message in result.messages) {
  final content = message.content;
  print(
    '${message.role}: ${content is TextContent ? content.text : content.toJson()}',
  );
}
```

### Get Prompt with Arguments

```dart
// Get prompt with arguments
final result = await client.getPrompt(
  GetPromptRequest(
    name: 'translate',
    arguments: {
      'target_language': 'Spanish',
      'formality': 'formal',
    },
  ),
);

// Use the prompt messages with an LLM
for (final message in result.messages) {
  final content = message.content;
  print(
    '${message.role}: ${content is TextContent ? content.text : content.toJson()}',
  );
}
```

### Handle Embedded Resources in Prompts

```dart
final result = await client.getPrompt(
  GetPromptRequest(
    name: 'analyze-file',
    arguments: {'file_uri': 'file:///data.json'},
  ),
);

for (final message in result.messages) {
  final content = message.content;

  if (content is TextContent) {
    print('Text: ${content.text}');
  } else if (content is EmbeddedResource) {
    final embedded = content.resource;
    print(
      'Embedded: ${embedded is TextResourceContents ? embedded.text : embedded.toJson()}',
    );
  } else if (content is ResourceLink) {
    // Follow resource links directly
    final resourceData = await client.readResource(
      ReadResourceRequest(uri: content.uri),
    );
    final linked = resourceData.contents.first;
    print(
      'Linked: ${linked is TextResourceContents ? linked.text : linked.toJson()}',
    );
  }
}
```

## Sampling Requests

Handle LLM sampling requests from the server (server asking client to use an LLM):

```dart
final client = McpClient(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
  options: McpClientOptions(
    capabilities: ClientCapabilities(
      sampling: ClientCapabilitiesSampling(
        tools: true,
      ), // Enable sampling capability with tool support
    ),
  ),
);

// Server will send sampling requests via requests.
// Handle them with client.onSamplingRequest.
```

Example sampling handler (low-level):

```dart
// This is handled automatically if you integrate with an LLM
// For custom handling:

client.onSamplingRequest = (request) async {
  // request contains:
  // - messages: Conversation messages
  // - modelPreferences: Cost/speed/intelligence priorities
  // - systemPrompt: Optional system prompt
  // - includeContext: What context to include
  // - temperature, maxTokens, stopSequences, etc.

  // Call your LLM (e.g., Anthropic, OpenAI, Gemini)
  final llmResponse = await callLLM(
    messages: request.messages,
    systemPrompt: request.systemPrompt,
    maxTokens: request.maxTokens,
  );

  return CreateMessageResult(
    role: SamplingMessageRole.assistant,
    content: SamplingTextContent(text: llmResponse),
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
  CompleteRequest(
    ref: const ResourceReference(
      uri: 'users://{organization}/{userId}/profile',
    ),
    argument: const ArgumentCompletionInfo(
      name: 'userId',
      value: 'ali',  // Partial value
    ),
    context: const CompletionContext(
      arguments: {'organization': 'engineering'},
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
  CompleteRequest(
    ref: const PromptReference(
      name: 'translate',
      title: 'Translate text',
    ),
    argument: const ArgumentCompletionInfo(
      name: 'target_language',
      value: 'Spa',  // Partial value
    ),
    context: const CompletionContext(
      arguments: {'source_language': 'English'},
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
final client = McpClient(
  Implementation(
    name: 'my-client',
    version: '1.0.0',
  ),
  options: McpClientOptions(
    capabilities: ClientCapabilities(
      roots: ClientCapabilitiesRoots(
        listChanged: true,
      ),
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
        meta: {'workspace': 'primary'},
      ),
      Root(
        uri: 'file:///home/user/documents',
        name: 'Documents',
      ),
    ],
  );
};

// MCP 2025-11-25 only; this notification is removed in MCP 2026-07-28.
await client.sendRootsListChanged();
```

## Logging

MCP 2026-07-28 deprecates protocol logging. The SDK retains these APIs for
compatibility; new implementations should prefer server `stderr` for stdio or
OpenTelemetry for structured observability.

### Deprecated Request Logs (MCP 2026-07-28)

Logging is request-scoped in the MCP 2026-07-28 profile. Set the minimum level
on the operation that should emit logs:

```dart
final tools = await client.listTools(
  options: const RequestOptions(logLevel: LoggingLevel.debug),
);
```

Install the notification handler below before sending the request.

### Set Logging Level (MCP 2025-11-25)

`logging/setLevel` is legacy-only and is rejected by MCP 2026-07-28 stateless
peers.

```dart
// Set server's logging level
await client.setLoggingLevel(
  LoggingLevel.debug,
);
```

### Receive Log Messages

```dart
// Listen for server logs
client.setNotificationHandler<JsonRpcLoggingMessageNotification>(
  Method.notificationsMessage,
  (notification) async {
    final level = notification.logParams.level;
    final message = notification.logParams.data;
    final logger = notification.logParams.logger ?? 'server';

    print('[$level] $logger: $message');
  },
  (params, meta) {
    if (params == null) {
      throw const FormatException(
        'Missing params for logging message notification',
      );
    }

    return JsonRpcLoggingMessageNotification(
      logParams: LoggingMessageNotification.fromJson(params),
      meta: meta,
    );
  },
);
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
Future<McpClient> connectWithRetry(
  McpClient Function() createClient,
  Transport Function() createTransport,
) async {
  var retries = 0;
  const maxRetries = 3;

  while (retries < maxRetries) {
    final client = createClient();
    try {
      await client.connect(createTransport());
      print('Connected successfully');
      return client;
    } catch (e) {
      await client.close();
      retries++;
      print('Connection failed (attempt $retries/$maxRetries): $e');

      if (retries < maxRetries) {
        await Future.delayed(Duration(seconds: 2 * retries));
      } else {
        rethrow;
      }
    }
  }

  throw StateError('Unreachable');
}
```

### Capability Negotiation

```dart
// After connection, check server capabilities
final serverCapabilities = client.getServerCapabilities();

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
  McpClient client,
  String toolName,
  Map<String, dynamic> args,
) async {
  try {
    final result = await client.callTool(
      CallToolRequest(
        name: toolName,
        arguments: args,
      ),
    );
    if (result.isError) {
      print('Tool rejected the call: ${result.toJson()}');
    }
    return result;
  } on McpError catch (e) {
    switch (ErrorCode.fromValue(e.code)) {
      case ErrorCode.methodNotFound:
        print('Method or requested tool mode unavailable: ${e.message}');
        break;
      case ErrorCode.invalidParams:
        print(
          'Malformed request, unavailable tool, or legacy input rejection: '
          '${e.message}',
        );
        break;
      case ErrorCode.requestTimeout:
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


### Timeout Handling

```dart
// Custom timeout per request
try {
  final result = await client.callTool(
    const CallToolRequest(
      name: 'slow-tool',
      arguments: {},
    ),
    options: const RequestOptions(timeout: Duration(seconds: 60)),
  );
} on McpError catch (error)
    when (error.code == ErrorCode.requestTimeout.value) {
  print('Tool call timed out');
}
```

## Best Practices

### 1. Always Close Connections

```dart
Future<void> useClient() async {
  final client = McpClient(
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

### 3. Check Legacy Capabilities Before Use

This `resources.subscribe` check applies only to MCP 2025-11-25. MCP 2026-07-28 uses
the `subscriptions/listen` flow shown earlier in this guide.

```dart
// ✅ Good
if (client.getServerCapabilities()?.resources?.subscribe == true) {
  await client.subscribeResource(SubscribeRequest(uri: uri));
} else {
  // Fallback: poll for changes
  pollResourceForChanges(uri);
}

// ❌ Bad - assume capability exists
await client.subscribeResource(SubscribeRequest(uri: uri));
```

### 4. Legacy Resource Subscription Management

The following tracking pattern is for MCP 2025-11-25
`resources/subscribe`/`resources/unsubscribe` sessions.

```dart
// ✅ Good - track subscriptions
final subscriptions = <String>{};

Future<void> subscribe(String uri) async {
  if (!subscriptions.contains(uri)) {
    await client.subscribeResource(SubscribeRequest(uri: uri));
    subscriptions.add(uri);
  }
}

Future<void> unsubscribe(String uri) async {
  if (subscriptions.contains(uri)) {
    await client.unsubscribeResource(UnsubscribeRequest(uri: uri));
    subscriptions.remove(uri);
  }
}

// Clean up all subscriptions
Future<void> cleanUp() async {
  await Future.wait(
    subscriptions.map((uri) =>
      client.unsubscribeResource(UnsubscribeRequest(uri: uri)),
    ),
  );
  subscriptions.clear();
}
```

## Next Steps

- [Transports Guide](transports.md) - Choosing the right transport
- [Examples](examples.md) - Real-world client implementations
