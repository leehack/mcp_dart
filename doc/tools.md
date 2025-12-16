# Tools Documentation

Complete guide to implementing MCP tools.

## What are Tools?

Tools are functions that AI can call to perform actions. They are the primary way for clients to interact with server capabilities.

## Basic Tool Registration

```dart
server.registerTool(
  'tool-name',
  description: 'What the tool does',
  inputSchema: ToolInputSchema(
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
  inputSchema: ToolInputSchema(
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

## Tool Annotations

Provide behavioral hints to clients:

### Read-Only Tools

```dart
server.registerTool(
  'get-user-stats',
  description: 'Get user statistics',
  annotations: ToolAnnotations(readOnly: true), // No side effects
  inputSchema: ToolInputSchema(properties: {...}),
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
    readOnly: false,
    destructive: true, // Warn users!
  ),
  inputSchema: ToolInputSchema(
    properties: {
      'confirmation': JsonSchema.string(constValue: 'DELETE'),
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
  annotations: ToolAnnotations(idempotent: true), // Safe to retry
  inputSchema: ToolInputSchema(properties: {...}),
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
  annotations: ToolAnnotations(openWorld: true), // Results vary over time
  inputSchema: ToolInputSchema(properties: {...}),
  callback: (args, extra) async {
    final results = await webSearch(args['query']);
    return CallToolResult(
      content: [TextContent(text: jsonEncode(results))],
    );
  },
);
```

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
  inputSchema: ToolInputSchema(properties: {...}),
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

### Throw MCP Errors

```dart
server.registerTool(
  'admin-action',
  inputSchema: ToolInputSchema(properties: {...}),
  callback: (args, extra) async {
    if (!await isAdmin(args['userId'])) {
      throw McpError(
        ErrorCode.unauthorized,
        'Admin privileges required',
      );
    }

    // Perform admin action...
    return CallToolResult(content: []);
  },
);
```

### Validation Errors

```dart
server.tool(
  name: 'custom-validation',
  inputSchema: {...},
  callback: (args) async {
    // Custom business logic validation
    if (!isValid(args)) {
      throw McpError(
        ErrorCode.invalidParams,
        'Validation failed: ${getErrors(args)}',
      );
    }

    return CallToolResult(...);
  },
);
```

## Long-Running Operations

### Progress Notifications

```dart
server.registerTool(
  'process-large-file',
  inputSchema: ToolInputSchema(properties: {...}),
  callback: (args, extra) async {
    final progressToken = extra.progressToken;
    final file = args['file'] as String;

    if (progressToken != null) {
      // Initial progress
      await server.sendProgress(
        progressToken: progressToken,
        progress: 0,
        total: 100,
      );

      // Processing...
      for (var i = 0; i <= 100; i += 10) {
        await processChunk(file, i);

        // Update progress
        await server.sendProgress(
          progressToken: progressToken,
          progress: i,
          total: 100,
        );
      }
    } else {
      // Process without progress
      await processFile(file);
    }

    return CallToolResult(
      content: [TextContent(text: 'Processing complete')],
    );
  },
);
```

### Cancellation Support

```dart
server.registerTool(
  'cancelable-task',
  inputSchema: ToolInputSchema(properties: {...}),
  callback: (args, extra) async {
    final progressToken = extra.progressToken;

    for (var i = 0; i < 1000; i++) {
      // Check for cancellation
      if (progressToken != null && await isCancelled(progressToken)) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Task cancelled')],
        );
      }

      await processItem(i);

      // Send progress
      if (progressToken != null) {
        await server.sendProgress(
          progressToken: progressToken,
          progress: i,
          total: 1000,
        );
      }
    }

    return CallToolResult(content: []);
  },
);
```

## Real-World Examples

### API Integration

```dart
server.registerTool(
  'get-weather',
  description: 'Get current weather for a city',
  inputSchema: ToolInputSchema(
    properties: {
      'city': JsonSchema.string(description: 'City name'),
      'units': JsonSchema.string(
        enumValues: ['metric', 'imperial'],
        defaultValue: 'metric',
      ),
    },
    required: ['city'],
  ),
  callback: (args, extra) async {
    final city = args['city'] as String;
    final units = args['units'] as String? ?? 'metric';

    final weather = await weatherApi.getCurrent(
      city: city,
      units: units,
    );

    return CallToolResult(
      content: [
        TextContent(
          text: 'Weather in $city:\n'
                'Temperature: ${weather.temp}°\n'
                'Conditions: ${weather.description}',
        ),
      ],
    );
  },
);
```

### Database Query

```dart
server.registerTool(
  'query-users',
  description: 'Query user database',
  inputSchema: ToolInputSchema(
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
  annotations: ToolAnnotations(readOnly: true),
  inputSchema: ToolInputSchema(
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
        ErrorCode.invalidParams,
        'Access denied: $path',
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      throw McpError(
        ErrorCode.invalidParams,
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
inputSchema: ToolInputSchema(
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
inputSchema: ToolInputSchema(
  properties: {
    'query': JsonSchema.string(),
  },
)
```

### 3. Type Safety

```dart
// ✅ Good - type checking
callback: (args) async {
  final count = args['count'] as int;
  if (count < 1 || count > 100) {
    throw McpError(ErrorCode.invalidParams, 'Count out of range');
  }
  ...
}

// ❌ Bad - no type checking
callback: (args) async {
  final count = args['count'];  // Could be anything!
  ...
}
```

### 4. Error Handling

```dart
// ✅ Good - comprehensive error handling
callback: (args) async {
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
callback: (args) async {
  final result = await riskyOperation(args);  // May throw!
  return CallToolResult(
    content: [TextContent(text: result)],
  );
}
```

### 5. Security

```dart
// ✅ Good - validate inputs, check permissions
callback: (args) async {
  final path = args['path'] as String;

  // Validate path
  if (!isPathAllowed(path)) {
    throw McpError(ErrorCode.unauthorized, 'Access denied');
  }

  // Check permissions
  if (!hasPermission(args['userId'], path)) {
    throw McpError(ErrorCode.unauthorized, 'Insufficient permissions');
  }

  // Sanitize input
  final safePath = sanitizePath(path);

  return CallToolResult(...);
}

// ❌ Bad - no validation or security checks
callback: (args) async {
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
      inputSchema: ToolInputSchema(
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
