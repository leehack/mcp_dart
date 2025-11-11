# Tools Documentation

Complete guide to implementing MCP tools.

## What are Tools?

Tools are functions that AI can call to perform actions. They are the primary way for clients to interact with server capabilities.

## Basic Tool Registration

```dart
server.tool(
  name: 'tool-name',
  description: 'What the tool does',
  inputSchema: {
    'type': 'object',
    'properties': {
      'param': {'type': 'string'},
    },
  },
  callback: ({args, extra}) async {
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
'param': {
  'type': 'string',
  'description': 'A text parameter',
}

// Number
'count': {
  'type': 'number',
  'description': 'A numeric value',
}

// Integer
'age': {
  'type': 'integer',
  'minimum': 0,
  'maximum': 150,
}

// Boolean
'enabled': {
  'type': 'boolean',
  'description': 'Enable feature',
}

// Array
'tags': {
  'type': 'array',
  'items': {'type': 'string'},
  'minItems': 1,
  'maxItems': 10,
}

// Object
'config': {
  'type': 'object',
  'properties': {
    'key': {'type': 'string'},
    'value': {'type': 'number'},
  },
}
```

### Advanced Validation

```dart
server.tool(
  name: 'create-user',
  inputSchema: {
    'type': 'object',
    'properties': {
      'username': {
        'type': 'string',
        'minLength': 3,
        'maxLength': 20,
        'pattern': r'^[a-zA-Z0-9_]+$',
      },
      'email': {
        'type': 'string',
        'format': 'email',
      },
      'age': {
        'type': 'integer',
        'minimum': 13,
      },
      'role': {
        'type': 'string',
        'enum': ['user', 'admin', 'moderator'],
      },
      'preferences': {
        'type': 'object',
        'properties': {
          'notifications': {'type': 'boolean'},
          'theme': {
            'type': 'string',
            'enum': ['light', 'dark'],
            'default': 'light',
          },
        },
      },
    },
    'required': ['username', 'email'],
  },
  callback: ({args, extra}) async {
    final username = args!['username'] as String;
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
server.tool(
  name: 'get-user-stats',
  description: 'Get user statistics',
  readOnlyHint: true,  // No side effects
  inputSchema: {...},
  callback: (args) async {
    final stats = await database.getUserStats();
    return CallToolResult(
      content: [TextContent(text: jsonEncode(stats))],
    );
  },
);
```

### Destructive Tools

```dart
server.tool(
  name: 'delete-all-data',
  description: 'Permanently delete all data',
  destructiveHint: true,  // Warn users!
  inputSchema: {
    'type': 'object',
    'properties': {
      'confirmation': {
        'type': 'string',
        'const': 'DELETE',
      },
    },
    'required': ['confirmation'],
  },
  callback: (args) async {
    await database.deleteAll();
    return CallToolResult(
      content: [TextContent(text: 'All data deleted')],
    );
  },
);
```

### Idempotent Tools

```dart
server.tool(
  name: 'update-cache',
  description: 'Update cache entry',
  idempotentHint: true,  // Safe to retry
  inputSchema: {...},
  callback: (args) async {
    await cache.set(args['key'], args['value']);
    return CallToolResult(
      content: [TextContent(text: 'Cache updated')],
    );
  },
);
```

### Open World Tools

```dart
server.tool(
  name: 'search-web',
  description: 'Search the internet',
  openWorldHint: true,  // Results vary over time
  inputSchema: {...},
  callback: (args) async {
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
server.tool(
  name: 'divide',
  inputSchema: {...},
  callback: (args) async {
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
server.tool(
  name: 'admin-action',
  inputSchema: {...},
  callback: (args) async {
    if (!await isAdmin(args['userId'])) {
      throw McpError(
        ErrorCode.unauthorized,
        'Admin privileges required',
      );
    }

    // Perform admin action...
    return CallToolResult(...);
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
server.tool(
  name: 'process-large-file',
  inputSchema: {...},
  callback: (args) async {
    final progressToken = args['\$meta']?['progressToken'];
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
server.tool(
  name: 'cancelable-task',
  inputSchema: {...},
  callback: (args) async {
    final progressToken = args['\$meta']?['progressToken'];

    for (var i = 0; i < 1000; i++) {
      // Check for cancellation
      if (await isCancelled(progressToken)) {
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

    return CallToolResult(...);
  },
);
```

## Real-World Examples

### API Integration

```dart
server.tool(
  name: 'get-weather',
  description: 'Get current weather for a city',
  inputSchema: {
    'type': 'object',
    'properties': {
      'city': {
        'type': 'string',
        'description': 'City name',
      },
      'units': {
        'type': 'string',
        'enum': ['metric', 'imperial'],
        'default': 'metric',
      },
    },
    'required': ['city'],
  },
  callback: (args) async {
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
server.tool(
  name: 'query-users',
  description: 'Query user database',
  inputSchema: {
    'type': 'object',
    'properties': {
      'filters': {
        'type': 'object',
        'properties': {
          'age_min': {'type': 'integer'},
          'age_max': {'type': 'integer'},
          'role': {'type': 'string'},
        },
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 100,
        'default': 10,
      },
    },
  },
  callback: (args) async {
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
server.tool(
  name: 'read-file',
  description: 'Read file contents',
  readOnlyHint: true,
  inputSchema: {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'File path',
      },
      'encoding': {
        'type': 'string',
        'enum': ['utf8', 'latin1', 'ascii'],
        'default': 'utf8',
      },
    },
    'required': ['path'],
  },
  callback: (args) async {
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
server.tool(
  name: 'search',
  description: 'Search the knowledge base using keywords. '
               'Returns up to 10 most relevant results ranked '
               'by relevance score.',
  ...
);

// ❌ Bad
server.tool(
  name: 'search',
  description: 'Searches',
  ...
);
```

### 2. Comprehensive Schemas

```dart
// ✅ Good - descriptive, with validation
inputSchema: {
  'type': 'object',
  'properties': {
    'query': {
      'type': 'string',
      'description': 'Search query (keywords)',
      'minLength': 1,
      'maxLength': 200,
    },
  },
  'required': ['query'],
}

// ❌ Bad - minimal, no validation
inputSchema: {
  'type': 'object',
  'properties': {
    'query': {'type': 'string'},
  },
}
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

    server.tool(
      name: 'add',
      inputSchema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number'},
          'b': {'type': 'number'},
        },
      },
      callback: (args) async {
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
