## 1.1.0

### Breaking Changes

- **Protocol Version Update**: Updated default protocol version to `2025-11-25`.
- **Strict Capabilities Typing**: `ServerCapabilities` and `ClientCapabilities` fields (tasks, sampling, elicitation, etc.) are now strictly typed objects instead of `Map<String, dynamic>` or `bool`.
  - Updated `ServerCapabilities` to use `ServerCapabilitiesTasks`, `ServerCapabilitiesTools`, etc.
  - Updated `ClientCapabilities` to use `ClientCapabilitiesTasks`, `ClientCapabilitiesElicitation`, `ClientCapabilitiesSampling`, etc.
  - **Migration**: Update capability declarations to use the new typed classes (e.g., `ServerCapabilities(tasks: ServerCapabilitiesTasks(listChanged: true))`).
- **Task Management Refactor**: Task management classes have been refactored and moved to `lib/src/server/tasks/`.
  - `TaskStore` is now an abstract interface with `InMemoryTaskStore` as the default implementation.
  - `TaskMessageQueueWithResolvers` renamed to `TaskMessageQueue`.
  - `TaskResultHandler` and `TaskSession` utilize strict typing.
- **Tool Callback Update**: `ToolCallback` signature has been updated to include `RequestHandlerExtra? extra` as a named parameter.
  - New Signature: `FutureOr<BaseResultData> Function({Map<String, dynamic>? args, Map<String, dynamic>? meta, RequestHandlerExtra? extra})`

### Features

- **McpServer Enhancements**:
  - Added `McpServer` high-level support for tasks via `tasks(...)` method.
  - Integrated `notifyTaskStatus` into `McpServer`.
  - Added `McpServer` support for `sampling/createMessage`.
  - Exposed `onError` handler setter/getter on `McpServer`.
- **StreamableMcpServer**:
  - Added `StreamableMcpServer` class for simplified Streamable HTTP server creation (handles `serverFactory`, event store, and connection management).
- **Client Enhancements**:
  - Added `onTaskStatus` callback to `Client`.
  - Simplified client request handlers for sampling and elicitation.

### Fixes

- Fixed `Task` serialization.
- Fixed capabilities recognition in `McpServer`.
- Added comprehensive tests for StreamableMcpServer and Task features.

## 1.0.2

- Fix pana analysis issues
- Fix Web support for StreamableHTTP client

## 1.0.1

- Fix Documentation links in README.md

## 1.0.0

- Update protocol version to 2025-06-18
- Add Elicitation support (server-initiated input collection)
  - API: `McpServer.elicitUserInput()` (server) | `Client.onElicitRequest` (client handler)
  - Types: ElicitRequestParams (`message`, `requestedSchema`), ElicitResult (`action`, `content`), ClientCapabilitiesElicitation
  - Uses `elicitation/create` method (Inspector-compatible)
  - Accepts JSON Schema Maps for flexible schema definition
  - Helpers: `.accepted`, `.declined`, `.cancelled` getters on ElicitResult
  - Example: elicitation_http_server.dart
  - Tests: elicitation_test.dart
- **CRITICAL FIX**: Logger → stderr (prevents JSON-RPC corruption in stdio)
- **Comprehensive Test Coverage**: Added 203 new tests across 4 phases (+13.1% overall coverage: 56.9% → 70.0%)
  - Phase 1: External API coverage (Server MCP, URI templates, Client/Server capabilities) - 108 tests
  - Phase 2: Transport coverage (Stdio, SSE, HTTPS) - 38 tests
  - Phase 3: Types & edge cases (Protocol lifecycle, error handling) - 45 tests
  - Phase 4: Advanced scenarios (Protocol timeouts/aborts, Streamable HTTPS integration) - 12 tests
  - Fixed critical URI template variable duplication bug
  - Fixed McpError code preservation in request handlers
  - All 351 tests passing ✅

## 0.7.0

- Add support for Completions capability per MCP 2025-06-18 spec
- Add ServerCapabilitiesCompletions class for explicit completions capability declaration
- Update ServerCapabilities to include completions field
- Update client capability check to use explicit completions capability instead of inferring from prompts/resources
- Add integration tests and example for completions capability usage

## 0.6.4

- Fix issue with StreamableHTTP server not setting correct content-type for SSE

## 0.6.3

- Replace print statements with lightweight logging implementation

## 0.6.2

- Remove trailing CR before processing the lines

## 0.6.1

- Fix issue with CallToolResult not including metadata

## 0.6.0

- Add ToolInputSchema and ToolOutputSchema support in server.tool()
- Deprecate inputSchemaProperties and outputSchemaProperties in server.tool()
- Update examples to use ToolInputSchema and ToolOutputSchema

## 0.5.3

- Support Web Client for StreamableHTTP

## 0.5.2

- Preserve required fields in ToolInputSchema

## 0.5.1

- Add support for OutputScheme (<https://modelcontextprotocol.io/specification/draft/server/tools#output-schema>)

## 0.5.0

- Protocol version 2025-03-26

## 0.4.3

- Fix SSE behavior on StreamableHTTP
- Added sendNotification and sendRequest to extra for server callbacks

## 0.4.2

- Add Tool Annotation
- Remove additionalProperties from all models
- Add AudioContent

## 0.4.1

- Add IOStreamTransport to connect a client and server via dart streams in a single application

## 0.4.0

- Add support for StreamableHTTP client
- Add support for StreamableHTTP server

## 0.3.6

- Improve pub.dev points

## 0.3.5

- Lower min dart sdk to 3.0.0

## 0.3.4

- Fix Sampling result parsing error

## 0.3.3

- Add Gemini MCP Client Example
- Add Anthropic MCP Client Example
- Add Weather MCP Server Example

## 0.3.2

- Add SSE Server Manager for easier SSE server implementation

## 0.3.1

- Add Client support (stdio)
- Add resource and prompts example to stdio server and client

## 0.3.0

- Full refactor of the codebase to match it with the Typescript SDK implementation.

## 0.2.0

- Make it no need to call trasnport.connect()

## 0.1.1

- Add examples visible in pub.dev

## 0.1.0

- Add SSE support

## 0.0.2

- Expose more types

## 0.0.1

- Initial version.
