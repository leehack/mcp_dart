# Tools Documentation

Complete guide to implementing MCP tools.

## What are Tools?

Tools are functions that AI can call to perform actions. They are the primary way for clients to interact with server capabilities.

## Basic Tool Registration

```dart
server.registerTool(
  'tool-name',
  description: 'What the tool does',
  inputSchema: JsonSchema.object(
    properties: {
      'param': JsonSchema.string(),
    },
  ),
  callback: (args, extra) async {
    // Process request
    return CallToolResult(
      content: [TextContent(text: 'result')],
    );
  },
);
```

## JSON Schema Validation

mcp_dart implements a pragmatic JSON Schema subset for MCP tool input/output and elicitation schemas; it is not a complete JSON Schema 2020-12 validator.

MCP 2025-11-25 requires both `inputSchema` and `outputSchema` on a `Tool` to be
object-root JSON Schema values. Use `JsonSchema.object(...)` or
`JsonObject.fromJson(...)` at the root and put primitive values under named
properties. Primitive root schemas such as `JsonSchema.string()` are rejected at
the MCP wire boundary for tools and form elicitation.

### Basic Types

```dart
// String
'param': JsonSchema.string(
  description: 'A text parameter',
)

// Number
'count': JsonSchema.number(
  description: 'A numeric value',
)

// Integer
'age': JsonSchema.integer(
  minimum: 0,
  maximum: 150,
)

// Boolean
'enabled': JsonSchema.boolean(
  description: 'Enable feature',
)

// Array
'tags': JsonSchema.array(
  items: JsonSchema.string(),
  minItems: 1,
  maxItems: 10,
)

// Object
'config': JsonSchema.object(
  properties: {
    'key': JsonSchema.string(),
    'value': JsonSchema.number(),
  },
)
```

### Advanced Validation

```dart
server.registerTool(
  'create-user',
  inputSchema: JsonSchema.object(
    properties: {
      'username': JsonSchema.string(
        minLength: 3,
        maxLength: 20,
        pattern: r'^[a-zA-Z0-9_]+$',
      ),
      'email': JsonSchema.string(format: 'email'),
      'age': JsonSchema.integer(minimum: 13),
      'role': JsonSchema.string(
        enumValues: ['user', 'admin', 'moderator'],
      ),
      'preferences': JsonSchema.object(
        properties: {
          'notifications': JsonSchema.boolean(),
          'theme': JsonSchema.string(
            enumValues: ['light', 'dark'],
            defaultValue: 'light',
          ),
        },
      ),
    },
    required: ['username', 'email'],
  ),
  callback: (args, extra) async {
    final username = args['username'] as String;
    final email = args['email'] as String;
    final age = args['age'] as int?;
    final role = args['role'] as String? ?? 'user';

    // Create user...
    return CallToolResult(
      content: [TextContent(text: 'User created: $username')],
    );
  },
);
```

### Enum Wire Format

String enum schemas serialize as standard JSON Schema:

```json
{
  "type": "string",
  "enum": ["user", "admin", "moderator"]
}
```

`JsonEnum` uses the same standard output. When enum values include display titles, it emits JSON Schema `oneOf` entries with `const` and `title`; when a titled enum is used as array items, it emits `anyOf` entries. Mixed primitive enums without titles emit an `enum` array without a `type`. Legacy serialized input using `type: 'enum'` / `values` or `enumNames` is still accepted by parsers.

### Const Values

Use `JsonSchema.constValue(...)` when a property must equal exactly one JSON value:

```dart
'confirmation': JsonSchema.constValue('DELETE')
```

This emits standard JSON Schema `const` and validates only the constant value.

### Nullable and Type Unions

`JsonSchema.fromJson(...)` also accepts simple JSON Schema `type` arrays, such as nullable string schemas:

```json
{
  "type": ["string", "null"]
}
```

These are parsed as a union of the listed primitive schema types and validate only values matching one of those types.

## Tool Annotations

Provide behavioral hints to clients:

### Read-Only Tools

```dart
server.registerTool(
  'get-user-stats',
  description: 'Get user statistics',
  annotations: ToolAnnotations(readOnlyHint: true), // No side effects
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    final stats = await database.getUserStats();
    return CallToolResult(
      content: [TextContent(text: jsonEncode(stats))],
    );
  },
);
```

### Destructive Tools

```dart
server.registerTool(
  'delete-all-data',
  description: 'Permanently delete all data',
  annotations: ToolAnnotations(
    readOnlyHint: false,
    destructiveHint: true, // Warn users!
  ),
  inputSchema: JsonSchema.object(
    properties: {
      'confirmation': JsonSchema.constValue('DELETE'),
    },
    required: ['confirmation'],
  ),
  callback: (args, extra) async {
    await database.deleteAll();
    return CallToolResult(
      content: [TextContent(text: 'All data deleted')],
    );
  },
);
```

### Idempotent Tools

```dart
server.registerTool(
  'update-cache',
  description: 'Update cache entry',
  annotations: ToolAnnotations(idempotentHint: true), // Safe to retry
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    await cache.set(args['key'], args['value']);
    return CallToolResult(
      content: [TextContent(text: 'Cache updated')],
    );
  },
);
```

### Open World Tools

```dart
server.registerTool(
  'search-web',
  description: 'Search the internet',
  annotations: ToolAnnotations(openWorldHint: true), // Results vary over time
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    final results = await webSearch(args['query']);
    return CallToolResult(
      content: [TextContent(text: jsonEncode(results))],
    );
  },
);
```

Stable MCP tool annotations are `title`, `readOnlyHint`, `destructiveHint`,
`idempotentHint`, and `openWorldHint`. Legacy `priority` and `audience` payloads
still parse into deprecated Dart fields for compatibility, but they are not
emitted by `ToolAnnotations.toJson()`.

## Content Types

### Text Content

```dart
return CallToolResult(
  content: [
    TextContent(text: 'Simple text response'),
  ],
);
```

### Image Content

```dart
return CallToolResult(
  content: [
    ImageContent(
      data: base64Encode(imageBytes),
      mimeType: 'image/png',
      theme: 'dark', // optional: 'light' | 'dark'
    ),
  ],
);
```

### Resource Link Content

```dart
return CallToolResult(
  content: [
    TextContent(text: 'Open the generated report:'),
    ResourceLink(
      uri: 'file:///reports/summary.md',
      name: 'summary-report',
      mimeType: 'text/markdown',
      icons: [
        McpIcon(
          src: 'https://example.com/icons/report.png',
          mimeType: 'image/png',
          theme: IconTheme.light,
        ),
      ],
    ),
  ],
);
```

### Multiple Content Types

```dart
return CallToolResult(
  content: [
    TextContent(text: 'Analysis Results:'),
    ImageContent(
      data: base64Encode(chart),
      mimeType: 'image/png',
    ),
    TextContent(text: 'See attached chart for details.'),
  ],
);
```

### Embedded Resources

```dart
return CallToolResult(
  content: [
    TextContent(text: 'Generated report:'),
    EmbeddedResource(
      resource: ResourceReference(
        uri: 'file:///reports/analysis.pdf',
        type: 'resource',
      ),
    ),
  ],
);
```

## Error Handling

### Return Error Results

```dart
server.registerTool(
  'divide',
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    final a = args['a'] as num;
    final b = args['b'] as num;

    if (b == 0) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Error: Division by zero')],
      );
    }

    return CallToolResult(
      content: [TextContent(text: '${a / b}')],
    );
  },
);
```

### Tool-domain Permission Errors

For deliverable tool-domain failures such as permission denials, return a tool
result with `isError: true` instead of using JSON-RPC structural error codes.
Reserve `McpError`/`ErrorCode` for protocol-level failures or invalid arguments.

```dart
server.registerTool(
  'admin-action',
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    if (!await isAdmin(args['userId'])) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Admin privileges required')],
      );
    }

    // Perform admin action...
    return CallToolResult(content: []);
  },
);
```

### Validation Errors

```dart
server.registerTool(
  'custom-validation',
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    // Custom business logic validation
    if (!isValid(args)) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Validation failed: ${getErrors(args)}',
      );
    }

    return CallToolResult(...);
  },
);
```




## Progress Notifications

Long-running tools can report progress back to the client. This provides feedback to the user about the operation's status.

### Sending Progress

The `callback` function receives an `extra` parameter (of type `RequestHandlerExtra`) which exposes the `sendProgress` method.

```dart
server.registerTool(
  'long-running-task',
  description: 'A task that takes some time',
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    final totalSteps = 10;

    for (var i = 1; i <= totalSteps; i++) {
      await performStep(i);

      // Send progress notification
      // This automatically checks if the client requested progress (via progressToken)
      await extra.sendProgress(
        i.toDouble(),
        total: totalSteps.toDouble(),
        message: 'Processing step $i',
      );
    }

    return CallToolResult(
      content: [TextContent(text: 'Task completed')],
    );
  },
);
```

### Cancellation Support

Tools should also check for cancellation, especially if they are long-running.
When `extra.signal.aborted` is set, stop work promptly and clean up local state.
The protocol may suppress any response after cancellation, so do not rely on a
thrown error being delivered to the client.

```dart
server.registerTool(
  'cancelable-task',
  inputSchema: JsonSchema.object(properties: {...}),
  callback: (args, extra) async {
    // Check if cancelled at the start
    if (extra.signal.aborted) {
      await cleanupPartialWork();
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Task cancelled')],
      );
    }

    for (var i = 0; i < 1000; i++) {
      // Check for cancellation during loop
      if (extra.signal.aborted) {
        await cleanupPartialWork();
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Task cancelled')],
        );
      }

      await processItem(i);

      // Report progress
      await extra.sendProgress(i.toDouble(), total: 1000);
    }

    return CallToolResult(content: [TextContent(text: 'Done')]);
  },
);
```

## Task-Augmented Tools

MCP 2025-11-25 requires task-augmented requests to be negotiated explicitly.
For tools, the server must advertise `tasks.requests.tools.call`; a top-level
`tasks` capability is not enough. `registerToolTask()` advertises that
subcapability automatically when it is called before `connect()`.

```dart
final server = McpServer(
  const Implementation(name: 'task-server', version: '1.0.0'),
);

server.experimental.registerToolTask(
  'slow-tool',
  description: 'Runs asynchronously and returns a task first',
  inputSchema: const ToolInputSchema(),
  // Defaults to ToolExecution(taskSupport: 'required'). Use 'optional' if the
  // same tool can also return an immediate CallToolResult.
  execution: const ToolExecution(taskSupport: 'required'),
  handler: SlowToolTaskHandler(),
);

await server.connect(transport);
```

If a task-based tool must be registered after `connect()`, pre-advertise the
capability in `McpServerOptions` before connecting:

```dart
final server = McpServer(
  const Implementation(name: 'task-server', version: '1.0.0'),
  options: const McpServerOptions(
    capabilities: ServerCapabilities(
      tasks: ServerCapabilitiesTasks(
        requests: ServerCapabilitiesTasksRequests(
          tools: ServerCapabilitiesTasksTools(
            call: ServerCapabilitiesTasksToolsCall(),
          ),
        ),
      ),
    ),
  ),
);
```

Clients that call task-augmented tools can use `TaskClient.callToolStream()`.
When the `task` argument is supplied, `TaskClient` first verifies that the server
advertised `tasks.requests.tools.call`, then lists tools to confirm the target
tool advertises `execution.taskSupport` as `optional` or `required`.

```dart
final taskClient = TaskClient(client);

await for (final message in taskClient.callToolStream(
  'slow-tool',
  {'input': 'value'},
  task: {'ttl': 60000, 'pollInterval': 1000},
)) {
  // Handle TaskCreatedMessage, TaskStatusMessage, TaskResultMessage,
  // or TaskErrorMessage.
}
```

## Real-World Examples

### API Integration

```dart
const nwsApiBase = 'https://api.weather.gov';

server.registerTool(
  'get-alerts',
  description: 'Get weather alerts for a US state',
  inputSchema: JsonSchema.object(
    properties: {
      'state': JsonSchema.string(
        description: 'Two-letter state code, for example CA or NY',
      ),
    },
    required: ['state'],
  ),
  callback: (args, extra) async {
    final state = (args['state'] as String?)?.toUpperCase();
    if (state == null || state.length != 2) {
      return const CallToolResult(
        content: [TextContent(text: 'Invalid state code provided.')],
        isError: true,
      );
    }

    final alertsData = await makeNWSRequest('$nwsApiBase/alerts?area=$state');
    if (alertsData == null) {
      return CallToolResult.fromContent(
        [const TextContent(text: 'Failed to retrieve alerts data.')],
      );
    }

    final features = alertsData['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) {
      return CallToolResult.fromContent(
        [TextContent(text: 'No active alerts for $state.')],
      );
    }

    return CallToolResult.fromContent(
      [TextContent(text: 'Active alerts for $state: ${features.length}')],
    );
  },
);
```

See [`example/weather.dart`](../example/weather.dart) for the complete National Weather Service example, including request headers, forecast lookup, and alert formatting.

### Database Query

```dart
server.registerTool(
  'query-users',
  description: 'Query user database',
  inputSchema: JsonSchema.object(
    properties: {
      'filters': JsonSchema.object(
        properties: {
          'age_min': JsonSchema.integer(),
          'age_max': JsonSchema.integer(),
          'role': JsonSchema.string(),
        },
      ),
      'limit': JsonSchema.integer(
        minimum: 1,
        maximum: 100,
        defaultValue: 10,
      ),
    },
  ),
  callback: (args, extra) async {
    final filters = args['filters'] as Map<String, dynamic>?;
    final limit = args['limit'] as int? ?? 10;

    final users = await database.query(
      filters: filters,
      limit: limit,
    );

    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode({
            'count': users.length,
            'users': users,
          }),
        ),
      ],
    );
  },
);
```

### File Operations

```dart
server.registerTool(
  'read-file',
  description: 'Read file contents',
  annotations: ToolAnnotations(readOnlyHint: true),
  inputSchema: JsonSchema.object(
    properties: {
      'path': JsonSchema.string(description: 'File path'),
      'encoding': JsonSchema.string(
        enumValues: ['utf8', 'latin1', 'ascii'],
        defaultValue: 'utf8',
      ),
    },
    required: ['path'],
  ),
  callback: (args, extra) async {
    final path = args['path'] as String;
    final encoding = args['encoding'] as String? ?? 'utf8';

    // Validate path (security!)
    if (!isPathAllowed(path)) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Access denied: $path',
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'File not found: $path',
      );
    }

    final content = await file.readAsString();
    return CallToolResult(
      content: [TextContent(text: content)],
    );
  },
);
```

## Best Practices

### 1. Clear Descriptions

```dart
// ✅ Good
server.registerTool(
  'search',
  description: 'Search the knowledge base using keywords. '
               'Returns up to 10 most relevant results ranked '
               'by relevance score.',
  ...
);

// ❌ Bad
server.registerTool(
  'search',
  description: 'Searches',
  ...
);
```

### 2. Comprehensive Schemas

```dart
// ✅ Good - descriptive, with validation
inputSchema: JsonSchema.object(
  properties: {
    'query': JsonSchema.string(
      description: 'Search query (keywords)',
      minLength: 1,
      maxLength: 200,
    ),
  },
  required: ['query'],
)

// ❌ Bad - minimal, no validation
inputSchema: JsonSchema.object(
  properties: {
    'query': JsonSchema.string(),
  },
)
```

### 3. Type Safety

```dart
// ✅ Good - type checking
callback: (args, extra) async {
  final count = args['count'] as int;
  if (count < 1 || count > 100) {
    throw McpError(ErrorCode.invalidParams.value, 'Count out of range');
  }
  ...
}

// ❌ Bad - no type checking
callback: (args, extra) async {
  final count = args['count'];  // Could be anything!
  ...
}
```

### 4. Error Handling

```dart
// ✅ Good - comprehensive error handling
callback: (args, extra) async {
  try {
    final result = await riskyOperation(args);
    return CallToolResult(
      content: [TextContent(text: result)],
    );
  } on NetworkException catch (e) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Network error: ${e.message}')],
    );
  } catch (e) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Unexpected error: $e')],
    );
  }
}

// ❌ Bad - unhandled exceptions
callback: (args, extra) async {
  final result = await riskyOperation(args);  // May throw!
  return CallToolResult(
    content: [TextContent(text: result)],
  );
}
```

### 5. Security

```dart
// ✅ Good - validate inputs, check permissions
callback: (args, extra) async {
  final path = args['path'] as String;

  // Validate path
  if (!isPathAllowed(path)) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Access denied')],
    );
  }

  // Check permissions
  if (!hasPermission(args['userId'], path)) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Insufficient permissions')],
    );
  }

  // Sanitize input
  final safePath = sanitizePath(path);

  return CallToolResult(...);
}

// ❌ Bad - no validation or security checks
callback: (args, extra) async {
  final path = args['path'] as String;
  final file = File(path);  // Direct file access!
  return CallToolResult(...);
}
```

## Testing Tools

```dart
import 'package:test/test.dart';

void main() {
  test('tool execution', () async {
    // Setup
    final server = McpServer(
      Implementation(name: 'test', version: '1.0.0'),
    );

    server.registerTool(
      'add',
      inputSchema: JsonSchema.object(
        properties: {
          'a': JsonSchema.number(),
          'b': JsonSchema.number(),
        },
      ),
      callback: (args, extra) async {
        final sum = (args['a'] as num) + (args['b'] as num);
        return CallToolResult(
          content: [TextContent(text: '$sum')],
        );
      },
    );

    // Create client and connect (see Stream transport)
    final client = await createTestClient(server);

    // Test
    final result = await client.callTool(CallToolRequest(
      name: 'add',
      arguments: {'a': 5, 'b': 3},
    ));

    expect(result.content.first.text, '8');
  });
}
```

## Next Steps

- [Server Guide](server-guide.md) - Complete server guide
- [Examples](examples.md) - More tool examples
