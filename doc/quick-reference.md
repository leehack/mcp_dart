# Quick Reference

Fast lookup guide for common MCP Dart SDK operations.

## Installation

```yaml
# pubspec.yaml
dependencies:
  mcp_dart: ^1.0.0
```

```bash
dart pub get  # or: flutter pub get
```

## Import

```dart
import 'package:mcp_dart/mcp_dart.dart';
```

## Server Basics

### Create Server

```dart
final server = McpServer(
  Implementation(
    name: 'server-name',
    version: '1.0.0',
  ),
  options: ServerOptions(
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
  ),
);
```

### Create Streamable Server

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(
    Implementation(name: 'server', version: '1.0.0'),
  ),
  host: '0.0.0.0',
  port: 3000,
  path: '/mcp',
);
await server.start();
```

### Register Tool

```dart
server.tool(
  'tool-name',
  description: 'What it does',
  toolInputSchema: ToolInputSchema(
    properties: {
      'param': {'type': 'string'},
    },
    required: ['param'],
  ),
  callback: ({args, extra}) async {
    return CallToolResult.fromContent(
      content: [TextContent(text: 'result')],
    );
  },
);
```

### Register Resource

```dart
server.resource(
  'Resource Name',
  'resource://example',
  (uri, extra) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: 'content',
          mimeType: 'text/plain',
        ),
      ],
    );
  },
);
```

### Register Resource Template

```dart
server.resourceTemplate(
  'User Profile',
  'users://{userId}/profile',
  (uri, extra) async {
    final userId = uri.pathSegments.first;
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: jsonEncode(await getUser(userId)),
          mimeType: 'application/json',
        ),
      ],
    );
  },
);
```

### Register Prompt

```dart
server.prompt(
  'prompt-name',
  description: 'Prompt description',
  argsSchema: {
    'arg1': PromptArgumentDefinition(
      type: String,
      description: 'Argument description',
      required: true,
    ),
  },
  callback: (args, extra) async {
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Prompt with ${args["arg1"]}'),
        ),
      ],
    );
  },
);
```

### Register Tasks

```dart
server.tasks(
  listCallback: (extra) async => ListTasksResult(tasks: []),
  cancelCallback: (taskId, extra) async { /* cancel */ },
  getCallback: (taskId, extra) async { /* get */ },
  resultCallback: (taskId, extra) async { /* result */ },
);
```

### Connect Transport

```dart
// Stdio
final transport = StdioServerTransport();
await server.connect(transport);

// HTTP
final transport = StreamableHTTPServerTransport(
  request: httpRequest,
  response: httpResponse,
);
await server.connect(transport);
```

## Client Basics

### Create Client

```dart
final client = Client(
  Implementation(
    name: 'client-name',
    version: '1.0.0',
  ),
);
```

### Connect to Server

```dart
// Stdio - Dart server
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'dart',
    args: ['run', 'server.dart'],
  ),
);
await client.connect(transport);

// Stdio - Node.js server
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'node',
    args: ['server.js'],
  ),
);
await client.connect(transport);

// HTTP
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
);
await client.connect(transport);
```

### List Tools

```dart
final result = await client.listTools();
for (final tool in result.tools) {
  print('${tool.name}: ${tool.description}');
}
```

### Call Tool

```dart
final result = await client.callTool(
  CallToolRequestParams(
    name: 'tool-name',
    arguments: {'param': 'value'},
  ),
);

print(result.content.first.text);
```

### List Resources

```dart
final result = await client.listResources();
for (final resource in result.resources) {
  print('${resource.name}: ${resource.uri}');
}
```

### Read Resource

```dart
final result = await client.readResource(ReadResourceRequest(
  uri: 'resource://example',
));

print(result.contents.first.text);
```

### List Prompts

```dart
final result = await client.listPrompts(ListPromptsRequest());
for (final prompt in result.prompts) {
  print('${prompt.name}: ${prompt.description}');
}
```

### Get Prompt

```dart
final result = await client.getPrompt(GetPromptRequest(
  name: 'prompt-name',
  arguments: {'arg1': 'value'},
));

for (final message in result.messages) {
  print('${message.role}: ${message.content.text}');
}
```

### Close Connection

```dart
await client.close();
```

## Tool Patterns

### Simple Tool

```dart
server.tool(
  name: 'echo',
  inputSchema: {
    'type': 'object',
    'properties': {'message': {'type': 'string'}},
  },
  callback: (args) async => CallToolResult(
    content: [TextContent(text: args['message'] as String)],
  ),
);
```

### Tool with Validation

```dart
server.tool(
  name: 'divide',
  inputSchema: {
    'type': 'object',
    'properties': {
      'a': {'type': 'number'},
      'b': {'type': 'number'},
    },
  },
  callback: (args) async {
    final a = args['a'] as num;
    final b = args['b'] as num;

    if (b == 0) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Division by zero')],
      );
    }

    return CallToolResult(
      content: [TextContent(text: '${a / b}')],
    );
  },
);
```

### Tool with Progress

```dart
server.tool(
  name: 'long-task',
  inputSchema: {...},
  callback: (args) async {
    final token = args['\$meta']?['progressToken'];

    for (var i = 0; i <= 100; i += 10) {
      await processStep(i);

      if (token != null) {
        await server.sendProgress(
          progressToken: token,
          progress: i,
          total: 100,
        );
      }
    }

    return CallToolResult(
      content: [TextContent(text: 'Complete')],
    );
  },
);
```

### Tool Annotations

```dart
// Read-only
server.tool(
  name: 'get-data',
  readOnlyHint: true,
  ...
);

// Destructive
server.tool(
  name: 'delete-all',
  destructiveHint: true,
  ...
);

// Idempotent
server.tool(
  name: 'update',
  idempotentHint: true,
  ...
);

// Open world
server.tool(
  name: 'search-web',
  openWorldHint: true,
  ...
);
```

## Content Types

### Text

```dart
TextContent(text: 'Hello, world!')
```

### Image

```dart
ImageContent(
  data: base64Encode(bytes),
  mimeType: 'image/png',
)
```

### Embedded Resource

```dart
EmbeddedResource(
  resource: ResourceReference(
    uri: 'file:///path',
    type: 'resource',
  ),
)
```

### Multiple Content

```dart
CallToolResult(
  content: [
    TextContent(text: 'Summary'),
    ImageContent(data: chart, mimeType: 'image/png'),
    TextContent(text: 'Details'),
  ],
)
```

## Error Handling

### Tool Error Result

```dart
return CallToolResult(
  isError: true,
  content: [TextContent(text: 'Error message')],
);
```

### Throw MCP Error

```dart
throw McpError(
  ErrorCode.invalidParams,
  'Invalid parameters',
);
```

### Error Codes

```dart
ErrorCode.parseError       // -32700
ErrorCode.invalidRequest   // -32600
ErrorCode.methodNotFound   // -32601
ErrorCode.invalidParams    // -32602
ErrorCode.internalError    // -32603
```

### Try-Catch

```dart
try {
  final result = await client.callTool(request);
} on McpError catch (e) {
  print('MCP Error: ${e.message} (${e.code})');
} on TimeoutException {
  print('Request timed out');
} catch (e) {
  print('Unexpected error: $e');
}
```

## JSON Schema Patterns

### String

```dart
'name': {
  'type': 'string',
  'minLength': 1,
  'maxLength': 100,
  'pattern': r'^[a-zA-Z]+$',
}
```

### Number

```dart
'age': {
  'type': 'number',
  'minimum': 0,
  'maximum': 150,
}
```

### Integer

```dart
'count': {
  'type': 'integer',
  'minimum': 1,
}
```

### Boolean

```dart
'enabled': {
  'type': 'boolean',
}
```

### Enum

```dart
'status': {
  'type': 'string',
  'enum': ['active', 'inactive', 'pending'],
}
```

### Array

```dart
'tags': {
  'type': 'array',
  'items': {'type': 'string'},
  'minItems': 1,
  'maxItems': 10,
}
```

### Object

```dart
'config': {
  'type': 'object',
  'properties': {
    'key': {'type': 'string'},
    'value': {'type': 'number'},
  },
  'required': ['key'],
}
```

## Notifications

### Send Progress

```dart
await server.sendProgress(
  progressToken: 'token-123',
  progress: 50,
  total: 100,
);
```

### Send Log Message

```dart
await server.sendLogMessage(
  level: LoggingLevel.info,
  message: 'Processing started',
);
```

### Resource Updated

```dart
await server.sendResourceUpdated('resource://uri');
```

### List Changed

```dart
await server.sendToolListChanged();
await server.sendResourceListChanged();
await server.sendPromptListChanged();
```

## Capabilities

### Server Capabilities

```dart
final server = McpServer(
  Implementation(name: 'server', version: '1.0.0'),
  // Capabilities auto-detected from registrations
  options: ServerOptions(
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
  ),
);
```

### Client Capabilities

```dart
final client = Client(
  Implementation(name: 'client', version: '1.0.0'),
  capabilities: ClientCapabilities(
    sampling: {},
    roots: RootsCapability(listChanged: true),
    elicitation: ElicitationCapability(
      inputSchemas: [
        ElicitationInputSchemaType.stringSchema,
        ElicitationInputSchemaType.booleanSchema,
      ],
    ),
  ),
);
```

## Logging

### Set Level

```dart
await client.setLoggingLevel(SetLevelRequest(
  level: LoggingLevel.debug,
));
```

### Log Levels

```dart
LoggingLevel.debug
LoggingLevel.info
LoggingLevel.notice
LoggingLevel.warning
LoggingLevel.error
LoggingLevel.critical
LoggingLevel.alert
LoggingLevel.emergency
```

### Receive Logs

```dart
client.onLogMessage = (notification) {
  print('[${notification.level}] ${notification.data}');
};
```

## Resource Subscriptions

### Subscribe

```dart
await client.subscribeResource(SubscribeRequest(
  uri: 'resource://uri',
));
```

### Handle Updates

```dart
client.onResourceUpdated = (notification) {
  print('Updated: ${notification.uri}');
  // Re-read resource
};
```

### Unsubscribe

```dart
await client.unsubscribeResource(UnsubscribeRequest(
  uri: 'resource://uri',
));
```

## Completions

### Complete Resource Argument

```dart
final result = await client.complete(CompleteRequest(
  ref: CompletionReference(
    type: CompletionReferenceType.resourceRef,
    uri: 'users://{userId}/profile',
  ),
  argument: CompletionArgument(
    name: 'userId',
    value: 'al',  // Partial
  ),
));

for (final value in result.completion.values) {
  print(value);  // alice, alex, alan, ...
}
```

### Complete Prompt Argument

```dart
final result = await client.complete(CompleteRequest(
  ref: CompletionReference(
    type: CompletionReferenceType.promptRef,
    name: 'translate',
  ),
  argument: CompletionArgument(
    name: 'language',
    value: 'Spa',
  ),
));
```

## Common Imports

```dart
// Core SDK
import 'package:mcp_dart/mcp_dart.dart';

// For HTTP servers (VM only)
import 'dart:io';

// For async operations
import 'dart:async';

// For JSON encoding
import 'dart:convert';

// For base64 encoding
import 'dart:convert' show base64Encode, base64Decode;
```

## Testing

### Stream Transport for Tests

```dart
test('example', () async {
  final s2c = StreamController<String>();
  final c2s = StreamController<String>();

  final server = McpServer(...);
  await server.connect(IOStreamTransport(
    inputStream: c2s.stream,
    outputSink: s2c.sink,
  ));

  final client = Client(...);
  await client.connect(IOStreamTransport(
    inputStream: s2c.stream,
    outputSink: c2s.sink,
  ));

  // Test operations
  final result = await client.callTool(...);
  expect(result.content.first.text, 'expected');

  // Cleanup
  await client.close();
  await server.close();
});
```

## Platform Checks

```dart
import 'dart:io' show Platform;

if (Platform.isWeb) {
  // Web-specific code
} else {
  // VM-specific code
}
```

## Best Practices Checklist

- ✅ Always close clients: `await client.close()`
- ✅ Validate tool inputs with JSON schema
- ✅ Handle all error cases (McpError, TimeoutException)
- ✅ Use type-safe argument access: `args['key'] as Type`
- ✅ Provide clear descriptions for tools/resources/prompts
- ✅ Use appropriate tool hints (readOnly, destructive, etc.)
- ✅ Send progress for long-running operations
- ✅ Check server capabilities before using features
- ✅ Sanitize and validate user inputs for security
- ✅ Use meaningful error messages

## Next Steps

- **Main README**: See [../README.md](../README.md) for overview and platform support
- **Getting Started**: See [getting-started.md](getting-started.md)
- **Examples**: See [examples.md](examples.md)
