# Server Guide

Complete guide to building MCP servers with the Dart SDK.

## Table of Contents

- [Creating a Server](#creating-a-server)
- [Server Capabilities](#server-capabilities)
- [Registering Tools](#registering-tools)
- [Providing Resources](#providing-resources)
- [Creating Prompts](#creating-prompts)
- [MCP Apps Metadata](#mcp-apps-metadata)
- [Long-running tasks](#long-running-tasks)
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
    options: McpServerOptions(
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
  options: McpServerOptions(
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(),
      resources: ServerCapabilitiesResources(),
      prompts: ServerCapabilitiesPrompts(),
    ),
  ),
);
```

### Protocol Profile

Servers in the 2.3.0 preview use `McpProtocol.stable` by default. They
advertise and accept the stateless MCP `2026-07-28` draft/RC protocol alongside
legacy versions, including `server/discover`. Select the legacy profile
explicitly to advertise only MCP `2025-11-25` and earlier versions:

```dart
final server = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
  options: const McpServerOptions(
    protocol: McpProtocol.legacy,
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(),
    ),
  ),
);
```

Use `McpServerOptions(protocol: McpProtocol.require2026)` when the server
should reject legacy initialization.

## Server Capabilities

Registering a tool, resource, or prompt declares the corresponding base
capability. Optional behavior such as subscriptions, list-change
notifications, logging, and tasks must be advertised explicitly so peers do not
infer support from structure alone:

```dart
const McpServerOptions(
  capabilities: ServerCapabilities(
    tools: ServerCapabilitiesTools(listChanged: true),
    resources: ServerCapabilitiesResources(
      subscribe: true,
      listChanged: true,
    ),
    prompts: ServerCapabilitiesPrompts(listChanged: true),
    logging: <String, dynamic>{},
  ),
);
```

### Tool Capabilities

```dart
// Base tools support is declared when the first tool is registered.
server.registerTool('my-tool', callback: ...);

// Set ServerCapabilitiesTools(listChanged: true) before sending list changes.
```

### Resource Capabilities

```dart
// Base resources support is declared when a resource is registered.
server.registerResource('Data', 'file:///data', null, readCallback);

// Advertise subscribe/listChanged explicitly before implementing either.
```

### Prompt Capabilities

```dart
// Base prompt support is declared when the first prompt is registered.
server.registerPrompt('my-prompt', ...);

// Advertise ServerCapabilitiesPrompts(listChanged: true) before sending
// prompt-list change notifications.
```

## MCP Apps Metadata

Use TypeScript-style helper APIs to register app tools/resources with `_meta.ui`.

```dart
const resourceUri = 'ui://dashboard/view.html';

registerAppTool(
  server,
  'dashboard_show',
  McpUiAppToolConfig(
    meta: const {
      'ui': {
        'resourceUri': resourceUri,
      },
    },
  ),
  (args, extra) async => const CallToolResult(
    content: [TextContent(text: 'ok')],
  ),
);

registerAppResource(
  server,
  'Dashboard UI',
  resourceUri,
  const McpUiAppResourceConfig(
    meta: {
      'ui': {
        'prefersBorder': true,
      },
    },
  ),
  (uri, extra) async => ReadResourceResult(
    contents: [
      TextResourceContents(
        uri: uri.toString(),
        mimeType: mcpUiResourceMimeType,
        text: '<!doctype html><html></html>',
        meta: const McpUiResourceMeta(
          prefersBorder: true,
        ).toMeta(),
      ),
    ],
  ),
);
```

For a complete example, see [MCP Apps guide](mcp-apps.md).

## Registering Tools

Tools allow clients to execute actions through your server.

### Simple Tool

```dart
server.registerTool(
  'echo',
  description: 'Echo back a message',
  inputSchema: JsonSchema.object(
    properties: {
      'message': JsonSchema.string(),
    },
    required: ['message'],
  ),
  callback: (args, extra) async {
    final message = args['message'] as String;
    return CallToolResult(
      content: [TextContent(text: message)],
    );
  },
);
```

### Tool with Complex Schema

```dart
server.registerTool(
  'search-database',
  description: 'Search database with filters',
  inputSchema: JsonSchema.object(
    properties: {
      'query': JsonSchema.string(description: 'Search query'),
      'filters': JsonSchema.object(
        properties: {
          'category': JsonSchema.string(),
          'minPrice': JsonSchema.number(),
          'maxPrice': JsonSchema.number(),
        },
      ),
      'limit': JsonSchema.integer(
        minimum: 1,
        maximum: 100,
        defaultValue: 10,
      ),
    },
    required: ['query'],
  ),
  callback: (args, extra) async {
    final query = args['query'] as String;
    final filters = args['filters'] as Map<String, dynamic>?;
    final limit = args['limit'] as int? ?? 10;

    final results = await database.search(
      query: query,
      filters: filters,
      limit: limit,
    );

    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode(results),
        ),
      ],
    );
  },
);
```

### Reporting Progress

For long-running operations, you can report progress back to the client:

```dart
server.registerTool(
  'long-task',
  inputSchema: JsonSchema.object(properties: {}),
  callback: (args, extra) async {
    for (var i = 0; i < 100; i++) {
      await Future.delayed(Duration(milliseconds: 100));
      await extra.sendProgress(
        i.toDouble(),
        total: 100,
        message: 'Processing item $i',
      );
    }
    return CallToolResult(content: [TextContent(text: 'Done')]);
  },
);
```

See [Tools Documentation](tools.md#progress-notifications) for more details.

### Tool Annotations

Provide hints about tool behavior:

```dart
server.registerTool(
  'delete-user',
  description: 'Permanently delete a user account',
  annotations: const ToolAnnotations(
    destructiveHint: true,
    idempotentHint: true,
  ),
  inputSchema: JsonSchema.object(properties: {}),
  callback: (args, extra) async {
    // Delete logic
    return CallToolResult(
      content: [TextContent(text: 'User deleted')],
    );
  },
);

server.registerTool(
  'get-user-info',
  description: 'Get user information',
  annotations: const ToolAnnotations(readOnlyHint: true),
  inputSchema: JsonSchema.object(properties: {}),
  callback: (args, extra) async {
    // Get logic
    return CallToolResult(
      content: [TextContent(text: 'User info')],
    );
  },
);
```

### Tool with Multiple Content Types

```dart
server.registerTool(
  'generate-report',
  description: 'Generate a report with chart',
  inputSchema: JsonSchema.object(properties: {}),
  callback: (args, extra) async {
    final report = await generateReport(args);
    final chart = await generateChart(report);

    return CallToolResult(
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

### Tool Returning a Resource Link

```dart
server.registerTool(
  'latest-report',
  description: 'Return a link to the latest generated report',
  inputSchema: JsonSchema.object(properties: {}),
  callback: (args, extra) async {
    return CallToolResult(
      content: [
        TextContent(text: 'Latest report is available.'),
        ResourceLink(
          uri: 'file:///reports/latest.md',
          name: 'latest-report',
          mimeType: 'text/markdown',
        ),
      ],
    );
  },
);
```

### Error Handling in Tools

```dart
server.registerTool(
  'divide',
  description: 'Divide two numbers',
  inputSchema: JsonSchema.object(
    properties: {
      'a': JsonSchema.number(),
      'b': JsonSchema.number(),
    },
    required: ['a', 'b'],
  ),
  callback: (args, extra) async {
    final a = args['a'] as num;
    final b = args['b'] as num;

    if (b == 0) {
      // Return error content
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'Error: Division by zero'),
        ],
      );
    }

    return CallToolResult(
      content: [TextContent(text: '${a / b}')],
    );
  },
);
```

## Providing Resources

Resources provide data and context to clients.

### Simple Resource

```dart
server.registerResource(
  'README',
  'file:///docs/readme.md',
  null,
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
server.registerResourceTemplate(
  'User Profile',
  ResourceTemplateRegistration(
    'users://{userId}/profile',
    listCallback: null,
  ),
  null,
  (uri, vars, extra) async {
    // Extract userId from variables
    final userId = vars['userId'];
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

### Resource Template Completions

Resource template completion callbacks can use `CompletionContext.arguments` to
tailor suggestions based on other arguments the client already collected:

```dart
server.registerResourceTemplate(
  'User Profile',
  ResourceTemplateRegistration(
    'users://{organization}/{userId}/profile',
    listCallback: null,
    completeCallbacksWithContext: {
      'userId': (currentValue, context) async {
        final organization = context?.arguments?['organization'];
        return directory
            .suggestUsers(organization: organization, prefix: currentValue);
      },
    },
  ),
  null,
  (uri, vars, extra) async {
    final profile = await database.getUserProfile(vars['userId']);
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
server.registerResourceTemplate(
  'Project File',
  ResourceTemplateRegistration(
    'projects://{orgId}/{projectId}/files/{filePath}',
    listCallback: null,
  ),
  null,
  (uri, vars, extra) async {
    final orgId = vars['orgId'];
    final projectId = vars['projectId'];
    final filePath = vars['filePath'];

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

### Query Parameter URI Templates (RFC 6570)

```dart
server.registerResourceTemplate(
  'Entity List',
  ResourceTemplateRegistration(
    'entity://list{?status,assignee}',
    listCallback: null,
  ),
  null,
  (uri, vars, extra) async {
    final status = vars['status'] as String?;
    final assignee = vars['assignee'] as String?;
    final data = await repository.list(
      status: status,
      assignee: assignee,
    );

    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: jsonEncode(data),
          mimeType: 'application/json',
        ),
      ],
    );
  },
);
```

### Binary Resources

```dart
server.registerResource(
  'Company Logo',
  'file:///images/logo.png',
  null,
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
server.registerResource(
  'Metrics',
  'file:///data/metrics.json',
  null,
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

// Later, notify clients of changes through the low-level protocol surface.
await server.server.sendResourceUpdated(
  const ResourceUpdatedNotification(uri: 'file:///data/metrics.json'),
);

// Notify after an external registry change. registerResource already notifies.
server.sendResourceListChanged();
```

## Creating Prompts

Prompts are reusable templates with arguments.

### Simple Prompt

```dart
server.registerPrompt(
  'review-code',
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
server.registerPrompt(
  'translate',
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
    final language = args?['target_language'] as String;
    final formality = args?['formality'] as String? ?? 'neutral';

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

### Prompt Argument Completions

Prompt argument completions can also receive the request context. Use
`completeWithContext` when suggestions depend on other prompt arguments:

```dart
server.registerPrompt(
  'translate',
  description: 'Generate translation prompt',
  argsSchema: {
    'source_language': PromptArgumentDefinition(type: String),
    'target_language': PromptArgumentDefinition(
      type: String,
      completable: CompletableField(
        def: CompletableDef(
          complete: (value) async => languageCatalog.suggest(value),
          completeWithContext: (value, context) async {
            final sourceLanguage = context?.arguments?['source_language'];
            return languageCatalog.suggestTargets(
              prefix: value,
              sourceLanguage: sourceLanguage,
            );
          },
        ),
      ),
    ),
  },
  callback: (args, extra) async => GetPromptResult(
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: TextContent(text: 'Translate using $args'),
      ),
    ],
  ),
);
```

### Multi-Message Prompts

```dart
server.registerPrompt(
  'brainstorm',
  description: 'Brainstorming session prompt',
  argsSchema: {
    'topic': PromptArgumentDefinition(
      type: String,
      description: 'Topic to brainstorm',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final topic = args?['topic'] as String;

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
server.registerPrompt(
  'analyze-file',
  description: 'Analyze a file',
  argsSchema: {
    'file_uri': PromptArgumentDefinition(
      type: String,
      description: 'URI of file to analyze',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final fileUri = args?['file_uri'] as String;
    final fileText = await File(Uri.parse(fileUri).toFilePath()).readAsString();

    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: EmbeddedResource(
            resource: TextResourceContents(
              uri: fileUri,
              text: fileText,
              mimeType: 'text/plain',
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

## Long-running tasks

MCP has two task protocols that are not wire-compatible. Use the 2026 extension
for stateless peers and retain the 2025 API only when interoperating with a
legacy peer.

### MCP 2026 Tasks extension

Declare `io.modelcontextprotocol/tasks` on both peers. Task creation is
server-directed: a normal `tools/call` may return `CreateTaskExtensionResult`
only when that request's client capabilities include the extension. Store the
task before returning it; the SDK verifies that the new ID is immediately
resolvable through `tasks/get`.

The low-level handlers below show the minimum creation and polling shape:

```dart
final tasks = <String, TaskExtensionTask>{};
final server = McpServer(
  const Implementation(name: 'task-server', version: '1.0.0'),
  options: McpServerOptions(
    protocol: McpProtocol.stable,
    capabilities: ServerCapabilities(
      tools: const ServerCapabilitiesTools(),
      extensions: withMcpTasksExtension(),
    ),
  ),
);

server.server.setRequestHandler<JsonRpcGetTaskRequest>(
  Method.tasksGet,
  (request, extra) async {
    final task = tasks[request.getParams.taskId];
    if (task == null) {
      throw McpError(ErrorCode.invalidParams.value, 'Task not found');
    }
    return GetTaskExtensionResult(task: task);
  },
  (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
    'jsonrpc': jsonRpcVersion,
    'id': id,
    'method': Method.tasksGet,
    'params': params,
    if (meta != null) '_meta': meta,
  }),
);

server.server.setRequestHandler<JsonRpcCallToolRequest>(
  Method.toolsCall,
  (request, extra) async {
    if (!(extra.clientCapabilities?.supportsTasksExtension ?? false)) {
      return const CallToolResult(
        content: [TextContent(text: 'Completed synchronously')],
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final task = TaskExtensionTask(
      taskId: generateUUID(),
      status: TaskStatus.working,
      createdAt: now,
      lastUpdatedAt: now,
      ttlMs: 60000,
      pollIntervalMs: 1000,
    );
    tasks[task.taskId] = task; // Persist durably in production.
    return CreateTaskExtensionResult(task: task);
  },
  (id, params, meta) => JsonRpcCallToolRequest.fromJson({
    'jsonrpc': jsonRpcVersion,
    'id': id,
    'method': Method.toolsCall,
    'params': params,
    if (meta != null) '_meta': meta,
  }),
);
```

A complete service must also handle `tasks/update` and `tasks/cancel` for task
input and cancellation; successful handlers return
`TaskExtensionAcknowledgementResult`. The 2026 extension has no `tasks/list`,
`tasks/result`, or client-supplied `task` option. `McpClient.callTool()` polls
`tasks/get` and returns the final `CallToolResult` transparently.

### MCP 2025-11-25 legacy task augmentation

The legacy flow advertises `tasks.requests.*`, lets clients opt in per request,
and includes `tasks/list` and `tasks/result`. Configure it through
`server.experimental` only for `McpProtocol.legacy` interoperability:

```dart
server.experimental.onListTasks((extra) async {
  return ListTasksResult(
    tasks: [
      Task(
        taskId: 'task-1',
        status: TaskStatus.working,
        statusMessage: 'Long operation is running',
        ttl: null,
        createdAt: DateTime.now().toIso8601String(),
        lastUpdatedAt: DateTime.now().toIso8601String(),
      ),
    ],
  );
});

server.experimental.onCancelTaskWithResult((taskId, extra) async {
  // Logic to cancel the task
  return Task(
    taskId: taskId,
    status: TaskStatus.cancelled,
    statusMessage: 'Task cancelled',
    ttl: null,
    createdAt: DateTime.now().toIso8601String(),
    lastUpdatedAt: DateTime.now().toIso8601String(),
  );
});

server.experimental.onGetTask((taskId, extra) async {
  // Return the task details
  return Task(
    taskId: taskId,
    status: TaskStatus.working,
    ttl: null,
    createdAt: DateTime.now().toIso8601String(),
    lastUpdatedAt: DateTime.now().toIso8601String(),
  );
});

server.experimental.onTaskResult((taskId, extra) async {
  // Return the task result
  return CallToolResult(
    content: [TextContent(text: 'Result')],
  );
});
```

## Handling Client Requests

### Request Lifecycle

1. Client sends request
2. Server validates request
3. Server calls appropriate handler
4. Server returns result or error

### Logging

Send log messages to the client:

```dart
// Local application/SDK logging (not sent over MCP).
final logger = Logger('my-server');
logger.info('Server started');
logger.warn('Rate limit approaching');
logger.error('Database connection failed');

// Custom log levels
await server.sendLoggingMessage(
  LoggingMessageNotification(
    level: LoggingLevel.debug,
    data: 'Detailed debug information',
    logger: 'MyComponent',
  ),
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
    options: McpServerOptions(
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
  Logger('my-server').error('Failed to start server: $e');
  rethrow;
}
```

## Advanced Topics

### Choose a transport per server instance

Register shared capabilities in a factory, then create a separate `McpServer`
instance for each transport. A connected server instance owns one transport;
run stdio and HTTP entry points in separate processes or isolates.

```dart
void main() async {
  final server = McpServer(
    Implementation(
      name: 'multi-transport-server',
      version: '1.0.0',
    ),
    options: McpServerOptions(
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

}
```

### Custom Validation

```dart
server.registerTool(
  'custom-validation',
  description: 'Tool with custom validation',
  inputSchema: {...},
  callback: (args, extra) async {
    // Custom validation logic
    if (!_isValid(args)) {
      throw McpError(
        ErrorCode.invalidParams.value,
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
server.registerTool('tool1', ...);

// Later, add more tools dynamically
void addNewTool() {
  server.registerTool('tool2', ...);
}
```

When `tools.listChanged` is advertised and the server is connected,
`registerTool` sends the list-change notification. Do not send a duplicate
notification. The high-level registry currently returns its complete resource
list; implement a lower-level request handler if an application needs custom
pagination.

## Best Practices

### 1. Clear Descriptions

```dart
// ✅ Good
server.registerTool(
  'search',
  description: 'Search the knowledge base using keywords. '
               'Returns up to 10 most relevant results.',
  ...
);

// ❌ Bad
server.registerTool(
  'search',
  description: 'Searches stuff',
  ...
);
```

### 2. Comprehensive Schemas

```dart
// ✅ Good
inputSchema: JsonSchema.object(
  properties: {
    'query': JsonSchema.string(
      description: 'Search keywords',
      minLength: 1,
      maxLength: 200,
    ),
    'filters': JsonSchema.array(
      items: JsonSchema.string(),
      description: 'Optional category filters',
    ),
  },
  required: ['query'],
)

// ❌ Bad
inputSchema: JsonSchema.object(
  properties: {
    'query': JsonSchema.string(),
  },
)
```

### 3. Proper Error Handling

```dart
// ✅ Good
callback: (args, extra) async {
  try {
    final result = await riskyOperation(args);
    return CallToolResult(
      content: [TextContent(text: result)],
    );
  } catch (error, stackTrace) {
    logger.severe('Unexpected tool failure', error, stackTrace);
    return const CallToolResult(
      isError: true,
      content: [TextContent(text: 'Operation failed')],
    );
  }
}

// ❌ Bad - uncaught exceptions
callback: (args, extra) async {
  final result = await riskyOperation(args);  // May throw!
  return CallToolResult(
    content: [TextContent(text: result)],
  );
}
```

### 4. Use Appropriate Hints

```dart
// Destructive operations
server.registerTool(
  'delete-account',
  annotations: const ToolAnnotations(destructiveHint: true),
  ...
);

// Read-only operations
server.registerTool(
  'get-stats',
  annotations: const ToolAnnotations(readOnlyHint: true),
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
