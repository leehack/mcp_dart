# Examples Guide

Real-world examples and usage patterns for the MCP Dart SDK.

## Overview

The SDK includes examples in [`example/`](../example/) for each supported
protocol era. Choose the profile that matches what you want to test:

| Profile | Start with | Purpose |
| --- | --- | --- |
| Strict MCP `2026-07-28` | [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | Guarantee discovery and the stateless 2026 request model |
| Default dual-era | [`server_stdio.dart`](../example/server_stdio.dart), [`client_stdio.dart`](../example/client_stdio.dart), [`streamable_https/`](../example/streamable_https/) | Prefer 2026 and retain legacy fallback |
| Representative MCP 2025 / legacy | [`simple_task_interactive_server.dart`](../example/simple_task_interactive_server.dart), [`elicitation_http_server.dart`](../example/elicitation_http_server.dart), [`server_sse.dart`](../example/server_sse.dart) | Demonstrate initialization-era APIs retained for compatibility |

For task-focused guidance, also see:

- [MCP 2026 Tasks extension](tools.md#mcp-2026-tasks-extension) for the client
  flow and links to the server handlers.
- [SDK interoperability matrix](interoperability.md) for verified cross-SDK scenarios.
- [Flutter host and client recipes](flutter-recipes.md) for platform-specific Flutter guidance.
- [MCP migration cookbooks](migration-cookbooks.md) for TypeScript SDK, `dart_mcp`, stdio-to-HTTP, and version migrations.
- [MCP Apps guide](mcp-apps.md) for `io.modelcontextprotocol/ui` metadata and host compatibility notes.

## MCP 2026-07-28 core

### Strict server and client

**Location**: [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/)

The client starts the server over stdio, so the complete flow uses one command:

```bash
dart run example/mcp_2026_07_28/client.dart
```

**Features**:

- `McpProtocol.require2026` and `server/discover` negotiation
- Per-request protocol, identity, and capability metadata
- `subscriptions/listen` acknowledgment, resource update, and graceful close
- Automatic `input_required` elicitation and retry with preserved request state
- Explicit accept, decline, and cancel handling
- String-root output schema and structured tool result
- A process smoke test in `test/example/non_credentialed_examples_smoke_test.dart`

## Default dual-era examples

These examples use `McpProtocol.stable`, explicitly or by default. Compatible
peers negotiate MCP 2026; older peers use initialization fallback.

### Stdio Server and Client

**Location**: [`example/server_stdio.dart`](../example/server_stdio.dart), [`example/client_stdio.dart`](../example/client_stdio.dart)

Complete stdio-based server with tools, resources, and prompts:

```bash
# The client starts example/server_stdio.dart over stdio.
dart run example/client_stdio.dart
```

**Features**:

- Tool invocation with the `calculate` arithmetic tool
- Static resource reading from `file:///logs`
- Prompt retrieval with the `analyze-code` prompt
- Capability discovery and clean stdio shutdown

### Weather API Integration

**Location**: [`example/weather.dart`](../example/weather.dart)

Real-world API integration example using the US National Weather Service API:

```bash
dart run packages/mcp_dart_cli/bin/mcp_dart.dart inspect \
  --tool get-alerts \
  --json-args '{"state":"CA"}' \
  dart run example/weather.dart
```

**Features**:

- External API calls to `api.weather.gov`
- No API key required
- US alert lookup by two-letter state code
- US forecast lookup by latitude and longitude
- Error handling for API failures
- Type-safe parameter validation

### Safe HTTP Fetch Server

**Location**: [`example/fetch-server/`](../example/fetch-server/)

A bounded stdio tool for fetching public HTTP(S) text:

```bash
cd example/fetch-server
dart pub get
dart run bin/fetch_server.dart
```

The example rejects credentials and non-public network destinations, pins
connections to validated DNS answers, revalidates redirects, and caps time,
redirects, and response bytes. Its
[README](../example/fetch-server/README.md) explains the remaining production
egress, authentication, and rate-limit responsibilities.

## Transport Examples

### Legacy SSE Server (Deprecated)

**Location**: [`example/server_sse.dart`](../example/server_sse.dart)

Older Server-Sent Events transport retained with `McpProtocol.legacy`. Use the
Streamable HTTP example below for new projects.

```bash
dart run example/server_sse.dart
```

**Features**:

- HTTP server setup
- SSE transport configuration
- Session management
- Multiple concurrent connections
- Explicit Host and Origin allowlists for DNS-rebinding protection

### Streamable HTTP

**Location**: [`example/streamable_https/`](../example/streamable_https/)

Modern Streamable HTTP with dual-era protocol negotiation:

```bash
# Start server
dart run example/streamable_https/server_streamable_https.dart

# Run client
dart run example/streamable_https/client_streamable_https.dart
```

**Features**:

- Stateless POST requests for MCP 2026
- Session persistence and connection resumption for legacy MCP
- CORS support for browser examples

### High-Level Streamable Server

**Location**: [`example/streamable_https/high_level_server.dart`](../example/streamable_https/high_level_server.dart)

Simplified Streamable HTTP server setup using `StreamableMcpServer`:

```bash
dart run example/streamable_https/high_level_server.dart
```

**Features**:

- Simplified server creation
- Stateless 2026 request routing
- Sessions, event storage, and resumability for legacy MCP
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

### OAuth protected resource

**Location**: [`example/authentication/oauth_server_example.dart`](../example/authentication/oauth_server_example.dart)

Local protected-resource metadata and bearer-challenge pattern:

```bash
MCP_BEARER_TOKEN=local-secret \
  dart run example/authentication/oauth_server_example.dart
```

**Features**:

- Protected-resource metadata
- `401` bearer challenges
- Fail-closed static token check for local testing
- Explicit application boundary for production token verification

### OAuth2 Client

**Location**: [`example/authentication/oauth_client_example.dart`](../example/authentication/oauth_client_example.dart)

Generic OAuth client building blocks pinned to the initialization-era profile:

```bash
dart run example/authentication/oauth_client_example.dart
```

**Features**:

- Authorization code flow
- PKCE challenge generation
- Token exchange
- Callback-state validation
- Token refresh and plaintext local storage

The generic example does not host a callback or target a real provider.

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
- PKCE S256 and callback-state validation
- Plaintext token reuse for local testing
- Connection and tool discovery against the configured MCP endpoint

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

## MCP extensions

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
- Weather dashboard card pattern with text fallback, `ResourceLink`, structured content, and host-facing UI metadata

See [MCP Apps Support](mcp-apps.md) for host compatibility notes and additional UI patterns.

### MCP Apps Manual Metadata

**Location**: [`example/mcp_apps_metadata_server.dart`](../example/mcp_apps_metadata_server.dart)

Low-level MCP Apps metadata wiring without helper wrappers:

```bash
dart run example/mcp_apps_metadata_server.dart
```

**Features**:

- Manual `_meta` payloads for MCP Apps resources and tools
- `ui://weather/dashboard` HTML resource registration
- `ResourceLink` output from a tool result
- Host-facing `io.modelcontextprotocol/ui` metadata

MCP Apps is an optional extension and is tracked separately from core protocol
coverage.

## MCP 2025 and legacy compatibility

### Core task augmentation

**Location**: [`example/simple_task_interactive_server.dart`](../example/simple_task_interactive_server.dart), [`example/simple_task_interactive_client.dart`](../example/simple_task_interactive_client.dart)

This pair explicitly selects `McpProtocol.legacy` to demonstrate the 2025-era
core task APIs, including task-scoped elicitation and sampling. MCP 2026 uses
`input_required` in core and exposes long-running Tasks as an extension; start
with the strict 2026 pair for the modern input flow.

### Argument Completions

**Location**: [`example/completions_capability_demo.dart`](../example/completions_capability_demo.dart)

Initialization-era auto-completion for arguments. This example explicitly uses
`McpProtocol.legacy` because its commentary targets the 2025 feature shape.

```bash
dart run example/completions_capability_demo.dart
```

**Features**:

- Resource URI template completion
- Prompt argument completion
- Up to 100 suggestions
- Pagination support

### Server-initiated user input

**Location**: [`example/elicitation_http_server.dart`](../example/elicitation_http_server.dart)

Session-scoped server-initiated input collection with `McpProtocol.legacy`:

```bash
dart run example/elicitation_http_server.dart
```

**Features**:

- Multiple input types (boolean, string, number, enum)
- Schema validation
- Action handling (accept/decline/cancel)
- Structured, non-secret form data results

Form elicitation must not collect passwords, access tokens, or other secrets.

For MCP 2026, return `InputRequiredResult` from the tool, resource, or prompt
handler as shown in the strict 2026 example.

## Other feature examples

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
dart run bin/main.dart dart ../server_stdio.dart
```

**Features**:

- Current Anthropic Messages API and model override support
- Complete paginated MCP tool discovery with collision-safe provider aliases
- Correlated `tool_use` / `tool_result` turns
- Multiple tool calls and tool-use rounds
- Explicit per-call approval and rejection of unadvertised tool names
- Native text/image result mapping, structured-result preservation, and
  correlated recoverable MCP errors

### Google Gemini Client

**Location**: [`example/gemini-client/`](../example/gemini-client/)

Integration with Gemini API:

```bash
export GEMINI_API_KEY=your_key
cd example/gemini-client
dart run bin/main.dart dart ../server_stdio.dart
```

**Features**:

- Current Gemini Interactions API with stored multi-turn interactions
- Complete paginated MCP tool discovery with collision-safe provider aliases
- Correlated function-call / function-response turns
- Parallel and sequential tool calls with explicit per-call approval
- Native text/image/structured result mapping without MCP metadata leakage
- Fail-closed conversion for Gemini's supported JSON Schema subset

## Flutter Examples

### Flutter HTTP Client

**Location**: [`example/flutter_http_client/`](../example/flutter_http_client/)

Flutter Web app with MCP integration:

```bash
dart run example/streamable_https/server_streamable_https.dart

cd example/flutter_http_client
flutter run -d chrome --web-port 8080
```

**Features**:

- Cross-platform (iOS, Android, Web)
- Streamable HTTP transport configuration
- UI state management with connection, notification, tool, prompt, and resource state
- Error handling in Flutter
- Mobile/web lifecycle guidance

See [Flutter Host and Client Recipes](flutter-recipes.md) for platform-specific transport, lifecycle, authentication, and testing guidance.

### Jaspr MCP 2025 task client

**Location**: [`example/jaspr-client/`](../example/jaspr-client/)

Browser client explicitly using `McpProtocol.legacy` for elicitation, sampling,
and 2025-era task-aware tool flows:

```bash
dart run example/simple_task_interactive_server.dart

cd example/jaspr-client
dart pub get
jaspr serve
```

**Features**:

- Browser-compatible Streamable HTTP transport
- Tool discovery and form-based argument input
- Elicitation dialog handling for `confirm_delete`
- Sampling dialog handling for `write_haiku`
- Console-style event log for connection and task events

## Common Patterns

### Error Handling Pattern

```dart
// From weather.dart
server.registerTool(
  'get-alerts',
  description: 'Get weather alerts for a state',
  inputSchema: JsonSchema.object(
    properties: {
      'state': JsonSchema.string(
        description: 'Two-letter state code (e.g. CA, NY)',
      ),
    },
    required: ['state'],
  ),
  callback: (args, extra) async {
    final state = (args['state'] as String?)?.toUpperCase();
    if (state == null || state.length != 2) {
      return const CallToolResult(
        isError: true,
        content: [TextContent(text: 'Invalid state code provided.')],
      );
    }

    final alertsData = await makeNWSRequest('$nwsApiBase/alerts?area=$state');
    if (alertsData == null) {
      return const CallToolResult(
        isError: true,
        content: [TextContent(text: 'Failed to retrieve alerts data.')],
      );
    }

    final features = alertsData['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) {
      return CallToolResult.fromContent(
        [TextContent(text: 'No active alerts for $state.')],
      );
    }

    return CallToolResult.fromContent(
      [TextContent(text: 'Active alerts for $state: ...')],
    );
  },
);
```

### Progress Tracking Pattern

```dart
server.registerTool(
  'long-running-operation',
  inputSchema: JsonSchema.object(properties: {}),
  callback: (args, extra) async {
    for (var i = 0; i <= 100; i += 10) {
      await Future.delayed(Duration(milliseconds: 100));
      await extra.sendProgress(
        i.toDouble(),
        total: 100,
        message: 'Processing $i%',
      );
    }

    return CallToolResult.fromContent(
      [const TextContent(text: 'Operation complete')],
    );
  },
);
```

### Resource Template Pattern

```dart
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

### OAuth boundary pattern

Use `OAuthAuthorizationCodeProvider` when the client transport should discover
metadata, create the PKCE request, and exchange the returned code. On servers,
use `OAuthProtectedResourceOptions` plus `authenticationHandler`; the
application must still verify token signature or introspection, issuer,
resource audience, expiry, and scopes. See the
[authentication examples](../example/authentication/README.md).

### Completion Handler Pattern

```dart
// Argument completion
final result = await client.complete(
  CompleteRequest(
    ref: const ResourceReference(
      uri: 'users://{organization}/{userId}/profile',
    ),
    argument: const ArgumentCompletionInfo(
      name: 'userId',
      value: 'ali',  // Partial input
    ),
    context: const CompletionContext(
      arguments: {'organization': 'engineering'},
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
    inputSchema: JsonSchema.object(
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

  expect(
    result.content.first,
    isA<TextContent>().having((content) => content.text, 'text', '8'),
  );

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

Credentialed examples require environment variables:

```bash
# GitHub examples
export GITHUB_CLIENT_ID=your_id
export GITHUB_CLIENT_SECRET=your_secret
export GITHUB_TOKEN=your_pat

# Local protected-resource example
export MCP_BEARER_TOKEN=local-secret
export MCP_AUTHORIZATION_SERVER=https://auth.example.com

# LLM examples
export ANTHROPIC_API_KEY=your_key
export GEMINI_API_KEY=your_key
```

### Running Individual Examples

```bash
# Stdio examples
dart run example/server_stdio.dart
dart run example/client_stdio.dart

# Strict MCP 2026 example (starts its paired server)
dart run example/mcp_2026_07_28/client.dart

# HTTP examples
dart run example/server_sse.dart
dart run example/streamable_https/server_streamable_https.dart

# Auth examples (server also needs MCP_BEARER_TOKEN)
MCP_BEARER_TOKEN=local-secret dart run example/authentication/oauth_server_example.dart
dart run example/authentication/github_oauth_example.dart

# Feature examples
dart run example/completions_capability_demo.dart
dart run example/elicitation_http_server.dart

# Flutter example
dart run example/streamable_https/server_streamable_https.dart
cd example/flutter_http_client
flutter run -d chrome --web-port 8080

# Non-credentialed smoke checks used by CI/local release validation
dart test test/example/non_credentialed_examples_smoke_test.dart
```

Core CI also analyzes, tests, and AOT-compiles the nested Anthropic, Gemini,
and fetch packages; builds the Jaspr production bundle; and analyzes, tests,
and builds the Flutter web app.

## Next Steps

### For Beginners

1. Start with [server_stdio.dart](../example/server_stdio.dart)
2. Try [client_stdio.dart](../example/client_stdio.dart)
3. Explore [weather.dart](../example/weather.dart) for API integration

### For Advanced Users

1. Run the [strict MCP 2026 example](../example/mcp_2026_07_28/)
2. Study the [authentication boundary guide](../example/authentication/OAUTH_SERVER_GUIDE.md)
3. Review the [protocol coverage matrices](spec-coverage-2026-07-28.md)

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

1. Create the example in the `example/` directory
2. State whether it is strict 2026, dual-era, or intentionally legacy
3. Add a README explaining the example
4. Include comments for clarity
5. Test on the applicable platforms
6. Submit a pull request
