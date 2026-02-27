# Examples Guide

Real-world examples and usage patterns for the MCP Dart SDK.

## Overview

The SDK includes extensive examples in the [`example/`](../example/) directory. This guide highlights key examples and explains their usage.

## Basic Examples

### Stdio Server and Client

**Location**: [`example/server_stdio.dart`](../example/server_stdio.dart), [`example/client_stdio.dart`](../example/client_stdio.dart)

Complete stdio-based server with tools, resources, and prompts:

```bash
# Run server
dart run example/server_stdio.dart

# Run client (in another terminal)
dart run example/client_stdio.dart
```

**Features**:

- Multiple tools (echo, add, longRunningOperation)
- Static and template-based resources
- Prompt templates with arguments
- Progress notifications
- Comprehensive error handling

### Weather API Integration

**Location**: [`example/weather.dart`](../example/weather.dart)

Real-world API integration example:

```bash
dart run example/weather.dart
```

**Features**:

- External API calls (OpenWeatherMap)
- Environment variable configuration
- Error handling for API failures
- JSON response formatting
- Type-safe parameter validation

## Transport Examples

### HTTP/SSE Server

**Location**: [`example/server_sse.dart`](../example/server_sse.dart)

Server-Sent Events based server:

```bash
dart run example/server_sse.dart
```

**Features**:

- HTTP server setup
- SSE transport configuration
- Session management
- Multiple concurrent connections

### Streamable HTTPS

**Location**: [`example/streamable_https/`](../example/streamable_https/)

Modern HTTP streaming with resumability:

```bash
# Start server
dart run example/streamable_https/server_streamable_https.dart

# Run client
dart run example/streamable_https/client_streamable_https.dart
```

**Features**:

- Session persistence
- Connection resumption
- Stateful and stateless modes
- CORS support

### High-Level Streamable Server

**Location**: [`example/streamable_https/high_level_server.dart`](../example/streamable_https/high_level_server.dart)

Simplified Streamable HTTP server setup using `StreamableMcpServer`:

```bash
dart run example/streamable_https/high_level_server.dart
```

**Features**:

- Simplified server creation
- built-in session management
- built-in event store
- Automatic transport handling

### In-Process Communication

**Location**: [`example/iostream-client-server/`](../example/iostream-client-server/)

Stream-based in-process communication:

```bash
dart run example/iostream-client-server/simple.dart
```

**Features**:

- Stream transport
- In-process client-server communication
- Useful for testing
- No external processes needed

## Authentication Examples

### OAuth2 Server with PKCE

**Location**: [`example/authentication/oauth_server_example.dart`](../example/authentication/oauth_server_example.dart)

Complete OAuth2 implementation:

```bash
dart run example/authentication/oauth_server_example.dart
```

**Features**:

- OAuth2 authorization flow
- PKCE support (RFC 7636)
- Token generation and validation
- Secure token storage
- Refresh token support

### OAuth2 Client

**Location**: [`example/authentication/oauth_client_example.dart`](../example/authentication/oauth_client_example.dart)

Client-side OAuth2 integration:

```bash
dart run example/authentication/oauth_client_example.dart
```

**Features**:

- Authorization code flow
- PKCE challenge generation
- Token exchange
- Authenticated requests

### GitHub OAuth Integration

**Location**: [`example/authentication/github_oauth_example.dart`](../example/authentication/github_oauth_example.dart)

Real GitHub OAuth provider integration:

```bash
# Set environment variables
export GITHUB_CLIENT_ID=your_client_id
export GITHUB_CLIENT_SECRET=your_secret

dart run example/authentication/github_oauth_example.dart
```

**Features**:

- GitHub OAuth provider
- User authentication
- API access with tokens
- Profile information retrieval

### GitHub Personal Access Token

**Location**: [`example/authentication/github_pat_example.dart`](../example/authentication/github_pat_example.dart)

Simpler PAT-based authentication:

```bash
export GITHUB_TOKEN=your_pat
dart run example/authentication/github_pat_example.dart
```

**Features**:

- Personal access token authentication
- Repository access
- API integration
- Simpler than OAuth for scripts

## Advanced Features

### MCP Apps Helpers (TypeScript-style)

**Location**: [`example/mcp_apps_helpers_server.dart`](../example/mcp_apps_helpers_server.dart)

TypeScript-style helper APIs for MCP Apps registration:

```bash
dart run example/mcp_apps_helpers_server.dart
```

**Features**:

- `registerAppTool(...)` metadata normalization (`ui.resourceUri` + `ui/resourceUri`)
- `registerAppResource(...)` with default `text/html;profile=mcp-app`
- `ui://` resource registration and `_meta.ui` metadata
- Extension capability declaration (`withMcpUiExtension`)

### MCP Apps Manual Metadata

**Location**: [`example/mcp_apps_metadata_server.dart`](../example/mcp_apps_metadata_server.dart)

Low-level MCP Apps metadata wiring without helper wrappers:

```bash
dart run example/mcp_apps_metadata_server.dart
```

### Argument Completions

**Location**: [`example/completions_capability_demo.dart`](../example/completions_capability_demo.dart)

Auto-completion for arguments:

```bash
dart run example/completions_capability_demo.dart
```

**Features**:

- Resource URI template completion
- Prompt argument completion
- Up to 100 suggestions
- Pagination support

### User Input Elicitation

**Location**: [`example/elicitation_http_server.dart`](../example/elicitation_http_server.dart)

Server-initiated user input collection:

```bash
dart run example/elicitation_http_server.dart
```

**Features**:

- Multiple input types (boolean, string, number, enum)
- Schema validation
- Action handling (accept/decline/cancel)
- Structured form data results

### Required Fields Validation

**Location**: [`example/required_fields_demo.dart`](../example/required_fields_demo.dart)

Schema validation demonstration:

```bash
dart run example/required_fields_demo.dart
```

**Features**:

- Required vs optional fields
- Type validation
- Error handling for missing fields
- JSON schema enforcement

## LLM Integration

### Anthropic Claude Client

**Location**: [`example/anthropic-client/`](../example/anthropic-client/)

Integration with Claude API:

```bash
export ANTHROPIC_API_KEY=your_key
cd example/anthropic-client
dart run
```

**Features**:

- Claude API integration
- Message formatting
- Streaming responses
- Tool use with Claude

### Google Gemini Client

**Location**: [`example/gemini-client/`](../example/gemini-client/)

Integration with Gemini API:

```bash
export GEMINI_API_KEY=your_key
cd example/gemini-client
dart run
```

**Features**:

- Gemini API integration
- Multi-turn conversations
- Content generation
- Function calling

## Flutter Examples

### Flutter HTTP Client

**Location**: [`example/flutter_http_client/`](../example/flutter_http_client/)

Flutter mobile app with MCP integration:

```bash
cd example/flutter_http_client
flutter run
```

**Features**:

- Cross-platform (iOS, Android, Web)
- HTTP transport configuration
- UI state management
- Error handling in Flutter
- Mobile-optimized UX

## Common Patterns

### Error Handling Pattern

```dart
// From weather.dart
server.registerTool(
  'get-weather',
  inputSchema: ToolInputSchema(
    properties: {
      'city': JsonSchema.string(),
    },
    required: ['city'],
  ),
  callback: (args, extra) async {
    try {
      final weather = await weatherApi.getCurrent(
        city: args['city'] as String,
      );

      return CallToolResult(
        content: [TextContent(text: jsonEncode(weather))],
      );
    } on HttpException catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'API error: ${e.message}')],
      );
    } catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Unexpected error: $e')],
      );
    }
  },
);
```

### Progress Tracking Pattern

```dart
// From server_stdio.dart
server.registerTool(
  'longRunningOperation',
  inputSchema: ToolInputSchema(properties: {}),
  callback: (args, extra) async {
    final progressToken = extra.progressToken;

    for (var i = 0; i <= 100; i += 10) {
      await Future.delayed(Duration(milliseconds: 100));

      if (progressToken != null) {
        await server.sendProgress(
          progressToken: progressToken,
          progress: i,
          total: 100,
        );
      }
    }

    return CallToolResult(
      content: [TextContent(text: 'Operation complete')],
    );
  },
);
```

### Resource Template Pattern

```dart
// URI template for dynamic resources
// URI template for dynamic resources
server.registerResourceTemplate(
  'User Profile',
  ResourceTemplateRegistration(
    'user://{userId}/profile',
    listCallback: null,
  ),
  null,
  (uri, vars, extra) async {
    final userId = vars['userId'];
    final profile = await database.getUser(userId);

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

### OAuth Flow Pattern

```dart
// From oauth_server_example.dart

// 1. Client requests authorization
final authUrl = buildAuthorizationUrl(
  clientId: clientId,
  redirectUri: redirectUri,
  codeChallenge: challenge,
);

// 2. User approves

// 3. Exchange code for token
final token = await exchangeCodeForToken(
  code: authCode,
  codeVerifier: verifier,
);

// 4. Use token for requests
final response = await makeAuthenticatedRequest(
  accessToken: token.accessToken,
);
```

### Completion Handler Pattern

```dart
// Argument completion
final result = await client.complete(
  CompleteRequest(
    ref: CompletionReference(
      type: CompletionReferenceType.resourceRef,
      uri: 'users://{userId}/profile',
    ),
    argument: CompletionArgument(
      name: 'userId',
      value: 'ali',  // Partial input
    ),
  ),
);

// Display suggestions
for (final suggestion in result.completion.values) {
  print('  - $suggestion');
}
```

## Testing Examples

### Unit Test Pattern

```dart
// Testing tools with stream transport
test('tool execution', () async {
  // Setup streams
  final s2c = StreamController<String>();
  final c2s = StreamController<String>();

  // Create server
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
      required: ['a', 'b'],
    ),
    callback: (args, extra) async {
      final sum = (args['a'] as num) + (args['b'] as num);
      return CallToolResult(
        content: [TextContent(text: '$sum')],
      );
    },
  );

  // Connect server
  await server.connect(IOStreamTransport(
    stream: c2s.stream,
    sink: s2c.sink,
  ));

  // Create client
  final client = McpClient(
    Implementation(name: 'test', version: '1.0.0'),
  );

  await client.connect(IOStreamTransport(
    stream: s2c.stream,
    sink: c2s.sink,
  ));

  // Test
  final result = await client.callTool(CallToolRequest(
    name: 'add',
    arguments: {'a': 5, 'b': 3},
  ));

  expect(result.content.first.text, '8');

  // Cleanup
  await client.close();
  await server.close();
});
```

## Running Examples

### Prerequisites

```bash
# Install Dart SDK
# Install dependencies
dart pub get

# For Flutter examples
flutter pub get
```

### Environment Variables

Many examples require environment variables:

```bash
# Weather example
export OPENWEATHER_API_KEY=your_key

# GitHub examples
export GITHUB_CLIENT_ID=your_id
export GITHUB_CLIENT_SECRET=your_secret
export GITHUB_TOKEN=your_pat

# LLM examples
export ANTHROPIC_API_KEY=your_key
export GEMINI_API_KEY=your_key
```

### Running Individual Examples

```bash
# Stdio examples
dart run example/server_stdio.dart
dart run example/client_stdio.dart

# HTTP examples
dart run example/server_sse.dart
dart run example/streamable_https/server_streamable_https.dart

# Auth examples
dart run example/authentication/oauth_server_example.dart
dart run example/authentication/github_oauth_example.dart

# Feature examples
dart run example/completions_capability_demo.dart
dart run example/elicitation_http_server.dart

# Flutter example
cd example/flutter_http_client
flutter run
```

## Next Steps

### For Beginners

1. Start with [server_stdio.dart](../example/server_stdio.dart)
2. Try [client_stdio.dart](../example/client_stdio.dart)
3. Explore [weather.dart](../example/weather.dart) for API integration

### For Advanced Users

1. Study [oauth_server_example.dart](../example/authentication/oauth_server_example.dart)
2. Explore [completions_capability_demo.dart](../example/completions_capability_demo.dart)
3. Review [elicitation_http_server.dart](../example/elicitation_http_server.dart)

### For Flutter Developers

1. Check out [flutter_http_client/](../example/flutter_http_client/)
2. Understand mobile transport configuration
3. Learn state management patterns

### For LLM Integration

1. Review [anthropic-client/](../example/anthropic-client/)
2. Study [gemini-client/](../example/gemini-client/)
3. Understand message formatting for LLMs

## Related Documentation

- [Getting Started Guide](getting-started.md) - Basic concepts
- [Server Guide](server-guide.md) - Building servers
- [Client Guide](client-guide.md) - Building clients
- [Transports](transports.md) - Transport options

## Contributing Examples

Have a great example? Contributions are welcome!

1. Create example in `example/` directory
2. Add README explaining the example
3. Include comments for clarity
4. Test on multiple platforms
5. Submit a pull request
