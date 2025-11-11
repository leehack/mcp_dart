# Server Guide

Complete guide to building MCP servers with the Dart SDK.

## Table of Contents

- [Creating a Server](#creating-a-server)
- [Server Capabilities](#server-capabilities)
- [Registering Tools](#registering-tools)
- [Providing Resources](#providing-resources)
- [Creating Prompts](#creating-prompts)
- [Handling Client Requests](#handling-client-requests)
- [Server Lifecycle](#server-lifecycle)
- [Advanced Topics](#advanced-topics)

## Creating a Server

### Basic Server Setup

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = McpServer(
    Implementation(
      name: 'my-server',
      version: '1.0.0',
    ),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  // Register capabilities (tools, resources, prompts)

  // Connect transport
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

### Server Configuration Options

```dart
final server = McpServer(
  Implementation(
    name: 'my-server',
    version: '1.0.0',
  ),
  options: ServerOptions(
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(),
      resources: ServerCapabilitiesResources(),
      prompts: ServerCapabilitiesPrompts(),
    ),
  ),
);
```

## Server Capabilities

The server automatically advertises its capabilities based on what you register:

```dart
ServerCapabilities(
  tools: {...},           // If you register tools
  resources: {...},       // If you register resources
  prompts: {...},         // If you register prompts
  logging: {...},         // Always available
  experimental: {...},    // Experimental features
)
```

### Tool Capabilities

```dart
// Advertised automatically when you register tools
server.tool(name: 'my-tool', ...);

// Capabilities include:
// - listChanged: true (server can notify of tool list changes)
```

### Resource Capabilities

```dart
// Advertised automatically when you register resources
server.resource(uri: 'file:///data', ...);

// Capabilities include:
// - subscribe: true (clients can subscribe to resource changes)
// - listChanged: true (server can notify of resource list changes)
```

### Prompt Capabilities

```dart
// Advertised automatically when you register prompts
server.prompt(name: 'my-prompt', ...);

// Capabilities include:
// - listChanged: true (server can notify of prompt list changes)
```

## Registering Tools

Tools allow clients to execute actions through your server.

### Simple Tool

```dart
server.tool(
  'echo',
  description: 'Echo back a message',
  toolInputSchema: ToolInputSchema(
    properties: {
      'message': {'type': 'string'},
    },
    required: ['message'],
  ),
  callback: ({args, extra}) async {
    final message = args!['message'] as String;
    return CallToolResult.fromContent(
      content: [TextContent(text: message)],
    );
  },
);
```

### Tool with Complex Schema

```dart
server.tool(
  'search-database',
  description: 'Search database with filters',
  toolInputSchema: ToolInputSchema(
    properties: {
      'query': {
        'type': 'string',
        'description': 'Search query',
      },
      'filters': {
        'type': 'object',
        'properties': {
          'category': {'type': 'string'},
          'minPrice': {'type': 'number'},
          'maxPrice': {'type': 'number'},
        },
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 100,
        'default': 10,
      },
    },
    required: ['query'],
  ),
  callback: ({args, extra}) async {
    final query = args!['query'] as String;
    final filters = args['filters'] as Map<String, dynamic>?;
    final limit = args['limit'] as int? ?? 10;

    final results = await database.search(
      query: query,
      filters: filters,
      limit: limit,
    );

    return CallToolResult.fromContent(
      content: [
        TextContent(
          text: jsonEncode(results),
        ),
      ],
    );
  },
);
```

### Tool Annotations

Provide hints about tool behavior:

```dart
server.tool(
  'delete-user',
  description: 'Permanently delete a user account',
  toolInputSchema: ToolInputSchema(properties: {}),
  callback: ({args, extra}) async {
    // Delete logic
    return CallToolResult.fromContent(
      content: [TextContent(text: 'User deleted')],
    );
  },
);

server.tool(
  'get-user-info',
  description: 'Get user information',
  toolInputSchema: ToolInputSchema(properties: {}),
  callback: ({args, extra}) async {
    // Get logic
    return CallToolResult.fromContent(
      content: [TextContent(text: 'User info')],
    );
  },
);

server.tool(
  'update-cache',
  description: 'Update cache entry',
  toolInputSchema: ToolInputSchema(properties: {}),
  callback: ({args, extra}) async {
    // Update logic
    return CallToolResult.fromContent(
      content: [TextContent(text: 'Cache updated')],
    );
  },
);

server.tool(
  'search-web',
  description: 'Search the web',
  toolInputSchema: ToolInputSchema(properties: {}),
  callback: ({args, extra}) async {
    // Search logic
    return CallToolResult.fromContent(
      content: [TextContent(text: 'Results')],
    );
  },
);
```

### Tool with Multiple Content Types

```dart
server.tool(
  'generate-report',
  description: 'Generate a report with chart',
  toolInputSchema: ToolInputSchema(properties: {}),
  callback: ({args, extra}) async {
    final report = await generateReport(args);
    final chart = await generateChart(report);

    return CallToolResult.fromContent(
      content: [
        TextContent(text: report.summary),
        ImageContent(
          data: base64Encode(chart),
          mimeType: 'image/png',
        ),
      ],
    );
  },
);
```

### Error Handling in Tools

```dart
server.tool(
  'divide',
  description: 'Divide two numbers',
  toolInputSchema: ToolInputSchema(
    properties: {
      'a': {'type': 'number'},
      'b': {'type': 'number'},
    },
    required: ['a', 'b'],
  ),
  callback: ({args, extra}) async {
    final a = args!['a'] as num;
    final b = args['b'] as num;

    if (b == 0) {
      // Return error content
      return CallToolResult.fromContent(
        isError: true,
        content: [
          TextContent(text: 'Error: Division by zero'),
        ],
      );
    }

    return CallToolResult.fromContent(
      content: [TextContent(text: '${a / b}')],
    );
  },
);
```

## Providing Resources

Resources provide data and context to clients.

### Simple Resource

```dart
server.resource(
  'README',
  'file:///docs/readme.md',
  (uri, extra) async {
    final content = await File('README.md').readAsString();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: 'file:///docs/readme.md',
          text: content,
          mimeType: 'text/markdown',
        ),
      ],
    );
  },
);
```

### Resource with URI Template

Use URI templates for dynamic resources:

```dart
server.resourceTemplate(
  'User Profile',
  'users://{userId}/profile',
  (uri, extra) async {
    // Extract userId from URI
    final userId = uri.pathSegments[0];
    final profile = await database.getUserProfile(userId);

    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: jsonEncode(profile),
          mimeType: 'application/json',
        ),
      ],
    );
  },
);
```

### Multiple URI Template Variables

```dart
server.resourceTemplate(
  'Project File',
  'projects://{orgId}/{projectId}/files/{filePath}',
  (uri, extra) async {
    final segments = uri.pathSegments;
    final orgId = segments[0];
    final projectId = segments[1];
    final filePath = segments.sublist(2).join('/');

    final fileContent = await storage.getFile(
      orgId: orgId,
      projectId: projectId,
      path: filePath,
    );

    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: fileContent,
        ),
      ],
    );
  },
);
```

### Binary Resources

```dart
server.resource(
  'Company Logo',
  'file:///images/logo.png',
  (uri, extra) async {
    final bytes = await File('logo.png').readAsBytes();
    return ReadResourceResult(
      contents: [
        BlobResourceContents(
          uri: 'file:///images/logo.png',
          blob: base64Encode(bytes),
          mimeType: 'image/png',
        ),
      ],
    );
  },
);
```

### Resource Updates

Notify clients when resources change:

```dart
// Register resource with change notifications
server.resource(
  'Metrics',
  'file:///data/metrics.json',
  (uri, extra) async {
    final content = await File('metrics.json').readAsString();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: content,
          mimeType: 'application/json',
        ),
      ],
    );
  },
);

// Later, notify clients of changes
await server.sendResourceUpdated('file:///data/metrics.json');

// Or notify of list changes (new/removed resources)
await server.sendResourceListChanged();
```

## Creating Prompts

Prompts are reusable templates with arguments.

### Simple Prompt

```dart
server.prompt(
  name: 'review-code',
  description: 'Generate code review prompt',
  callback: (args, extra) async {
    return GetPromptResult(
      description: 'Review code for quality and best practices',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'Please review the following code for:\n'
                  '- Code quality\n'
                  '- Best practices\n'
                  '- Potential bugs\n'
                  '- Security issues',
          ),
        ),
      ],
    );
  },
);
```

### Prompt with Arguments

```dart
server.prompt(
  name: 'translate',
  description: 'Generate translation prompt',
  argsSchema: {
    'target_language': PromptArgumentDefinition(
      type: String,
      description: 'Language to translate to',
      required: true,
    ),
    'formality': PromptArgumentDefinition(
      type: String,
      description: 'Formality level (casual, formal)',
      required: false,
    ),
  },
  callback: (args, extra) async {
    final language = args['target_language'] as String;
    final formality = args['formality'] as String? ?? 'neutral';

    return GetPromptResult(
      description: 'Translate text to $language',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'Translate the following text to $language '
                  'with a $formality tone:',
          ),
        ),
      ],
    );
  },
);
```

### Multi-Message Prompts

```dart
server.prompt(
  name: 'brainstorm',
  description: 'Brainstorming session prompt',
  argsSchema: {
    'topic': PromptArgumentDefinition(
      type: String,
      description: 'Topic to brainstorm',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final topic = args['topic'] as String;

    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'Let\'s brainstorm ideas about: $topic',
          ),
        ),
        PromptMessage(
          role: PromptMessageRole.assistant,
          content: TextContent(
            text: 'Great! I\'ll help you brainstorm. What aspect '
                  'of $topic interests you most?',
          ),
        ),
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'I\'m particularly interested in practical '
                  'applications.',
          ),
        ),
      ],
    );
  },
);
```

### Prompt with Embedded Resources

```dart
server.prompt(
  name: 'analyze-file',
  description: 'Analyze a file',
  argsSchema: {
    'file_uri': PromptArgumentDefinition(
      type: String,
      description: 'URI of file to analyze',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final fileUri = args['file_uri'] as String;

    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: EmbeddedResource(
            resource: ResourceReference(
              uri: fileUri,
              type: 'resource',
            ),
          ),
        ),
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'Please analyze this file for:\n'
                  '- Structure\n'
                  '- Content quality\n'
                  '- Potential improvements',
          ),
        ),
      ],
    );
  },
);
```

## Handling Client Requests

### Request Lifecycle

1. Client sends request
2. Server validates request
3. Server calls appropriate handler
4. Server returns result or error
5. Server may send progress notifications

### Progress Notifications

For long-running operations:

```dart
server.tool(
  'process-large-file',
  description: 'Process a large file',
  toolInputSchema: ToolInputSchema(properties: {}),
  callback: ({args, extra}) async {
    // Get progress token from extra
    final progressToken = extra?['progressToken'];

    if (progressToken != null) {
      // Send progress updates
      await server.sendProgress(
        progressToken: progressToken,
        progress: 25,
        total: 100,
      );

      // Process...
      await Future.delayed(Duration(seconds: 1));

      await server.sendProgress(
        progressToken: progressToken,
        progress: 50,
        total: 100,
      );

      // More processing...
    }

    return CallToolResult.fromContent(
      content: [TextContent(text: 'Processing complete')],
    );
  },
);
```

### Logging

Send log messages to the client:

```dart
// Set up logging
server.logger.info('Server started');
server.logger.warning('Rate limit approaching');
server.logger.severe('Database connection failed');

// Custom log levels
await server.sendLogMessage(
  level: LoggingLevel.debug,
  message: 'Detailed debug information',
  logger: 'MyComponent',
);
```

## Server Lifecycle

### Initialization

```dart
void main() async {
  final server = McpServer(
    Implementation(
      name: 'my-server',
      version: '1.0.0',
    ),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  // Register all capabilities before connecting
  _registerTools(server);
  _registerResources(server);
  _registerPrompts(server);

  // Connect transport
  final transport = StdioServerTransport();
  await server.connect(transport);

  // Server is now running and handling requests
}
```

### Shutdown

```dart
// Graceful shutdown
await server.close();
```

### Error Recovery

```dart
try {
  await server.connect(transport);
} catch (e) {
  server.logger.severe('Failed to start server: $e');
  rethrow;
}
```

## Advanced Topics

### Multiple Transports

Run server on multiple transports simultaneously:

```dart
void main() async {
  final server = McpServer(
    Implementation(
      name: 'multi-transport-server',
      version: '1.0.0',
    ),
    options: ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(),
        prompts: ServerCapabilitiesPrompts(),
      ),
    ),
  );

  // Register capabilities once
  _registerCapabilities(server);

  // Connect stdio transport
  final stdioTransport = StdioServerTransport();
  await server.connect(stdioTransport);

  // Also listen on HTTP (in a separate process/isolate)
  // See HTTP transport documentation
}
```

### Custom Validation

```dart
server.tool(
  name: 'custom-validation',
  description: 'Tool with custom validation',
  inputSchema: {...},
  callback: ({args, extra}) async {
    // Custom validation logic
    if (!_isValid(args)) {
      throw McpError(
        ErrorCode.invalidParams,
        'Validation failed: ${_getValidationError(args)}',
      );
    }

    // Process request
    return CallToolResult(
      content: [TextContent(text: 'Success')],
    );
  },
);
```

### Dynamic Capability Registration

```dart
final server = McpServer(Implementation(...), options: ...);

// Initial tools
server.tool(name: 'tool1', ...);

// Later, add more tools dynamically
void addNewTool() {
  server.tool(name: 'tool2', ...);

  // Notify clients of the change
  server.sendToolListChanged();
}
```

### Resource Listing with Pagination

```dart
// Clients can request paginated resource lists
// Server automatically handles the pagination

server.resource(uri: 'resource-1', ...);
server.resource(uri: 'resource-2', ...);
server.resource(uri: 'resource-3', ...);
// ... many resources

// Client requests:
// listResources(cursor: null) -> first page
// listResources(cursor: 'page2-token') -> second page
```

## Best Practices

### 1. Clear Descriptions

```dart
// ✅ Good
server.tool(
  name: 'search',
  description: 'Search the knowledge base using keywords. '
               'Returns up to 10 most relevant results.',
  ...
);

// ❌ Bad
server.tool(
  name: 'search',
  description: 'Searches stuff',
  ...
);
```

### 2. Comprehensive Schemas

```dart
// ✅ Good
inputSchema: {
  'type': 'object',
  'properties': {
    'query': {
      'type': 'string',
      'description': 'Search keywords',
      'minLength': 1,
      'maxLength': 200,
    },
    'filters': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Optional category filters',
    },
  },
  'required': ['query'],
}

// ❌ Bad
inputSchema: {
  'type': 'object',
  'properties': {
    'query': {'type': 'string'},
  },
}
```

### 3. Proper Error Handling

```dart
// ✅ Good
callback: (args) async {
  try {
    final result = await riskyOperation(args);
    return CallToolResult(
      content: [TextContent(text: result)],
    );
  } catch (e) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Operation failed: $e')],
    );
  }
}

// ❌ Bad - uncaught exceptions
callback: (args) async {
  final result = await riskyOperation(args);  // May throw!
  return CallToolResult(
    content: [TextContent(text: result)],
  );
}
```

### 4. Use Appropriate Hints

```dart
// Destructive operations
server.tool(
  name: 'delete-account',
  destructiveHint: true,  // ⚠️ Warn clients
  ...
);

// Read-only operations
server.tool(
  name: 'get-stats',
  readOnlyHint: true,  // Safe to call
  ...
);
```

### 5. Resource URI Conventions

```dart
// ✅ Good - clear, hierarchical URIs
'file:///projects/myproject/README.md'
'db://users/123/profile'
'api://external/weather/current'

// ❌ Bad - unclear or flat URIs
'resource1'
'data'
'thing123'
```

## Next Steps

- [Tools Documentation](tools.md) - Deep dive into tools
- [Transports Guide](transports.md) - Transport options
