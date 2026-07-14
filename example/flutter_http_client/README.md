# MCP Web Client Example

This Flutter Web application demonstrates an MCP client using Streamable HTTP.
Its button-based UI covers connection state, tools, prompts, resources, and
notifications against both MCP 2026 and initialization-era servers.

## Features

- Connect to any MCP-compliant server
- Discover and call server tools
- List and retrieve prompts
- View available resources
- Receive and display notifications from the server
- Full support for StreamableHttpClientTransport from the MCP Dart library

## Getting Started

### Prerequisites

- Flutter SDK with Dart 3.7.2 or later
- Chrome
- An MCP server to connect to (for local testing, use the Streamable HTTP example server)

### Running the Example

1. First, start an MCP server:

```shell
cd /path/to/mcp_dart
dart run example/streamable_https/server_streamable_https.dart
```

This will start an MCP server on `http://localhost:3000/mcp`.

2. In a separate terminal, run the Flutter app:

```shell
cd /path/to/mcp_dart/example/flutter_http_client
flutter run -d chrome --web-port 8080
```

The fixed port matches the server's default `MCP_ALLOWED_ORIGIN`. If you use a
different browser origin, start the server with that exact value, for example
`MCP_ALLOWED_ORIGIN=http://localhost:9000 dart run ...`.

3. In the application, click the "Connect" button to establish a connection to the server.

4. Once connected, you can use various buttons to interact with the server:
   - List Tools: See available tools on the server
   - Call Tool: Enter a scalar for a one-argument tool, or a JSON object for a tool with multiple arguments
   - List Prompts: View available prompts
   - Get Prompt: Retrieve the selected prompt using its advertised prompt argument schema
   - List Resources: See available resources

### Local Smoke Flow

The default server exposes a `greet` tool and a `greeting-template` prompt.
After connecting to `http://localhost:3000/mcp`, enter a name in the text field,
then run `List Tools`, `Call Tool`, `List Prompts`, `Get Prompt`, and
`List Resources`.

For a browser connection-reuse smoke test, run `List Tools` 12 times and call
`greet` 12 times without reconnecting or reloading. Every request should finish
and each tool response should contain the name you entered.

### Validation

```shell
# From example/flutter_http_client
flutter analyze
flutter test
flutter build web

# From the repository root: real Chrome, 12 list requests and 12 tool calls
# against both the 2026 default and 2025 legacy profiles
dart run tool/testing/run_browser_2026_07_28_interop.dart
```

## Project Structure

- `lib/main.dart` - Entry point of the application
- `lib/services/streamable_mcp_service.dart` - Service for communicating with MCP servers
- `lib/screens/mcp_client_screen.dart` - Main UI interface with button controls

## Understanding MCP Communication

The application demonstrates key aspects of MCP client implementation:

1. **Connection**: The client establishes a connection to the MCP server and retrieves capabilities.
2. **Tool Calling**: The client calls tools on the server with parameters.
3. **Progress**: The client displays request-scoped progress while a tool call is active. Try `multi-greet`, or pass `{"interval": 100, "count": 5}` to `start-notification-stream`.
4. **Dual-era behavior**: The default profile prefers MCP 2026 and can fall back
   to initialization-era servers. Session controls are enabled only after a
   legacy session is negotiated.

The `StreamableMcpService` class handles all communication with the server and updates `ChangeNotifier` state that the UI listens to.

## Customization

You can modify this example to connect to different MCP servers or implement additional features:

- Change the server URL in the settings
- Add support for more complex tool parameters
- Implement authentication for secure MCP servers
- Add file upload/download capabilities
- Customize the UI for your specific use case

## Web Compatibility

This example uses the browser implementation of Streamable HTTP. Browser
servers must allow the exact app origin and all MCP request headers in CORS
preflight responses; the paired server example handles both fixed headers and
dynamic `Mcp-Param-*` headers.
