# Jaspr MCP Client Example

A modern, web-based MCP (Model Context Protocol) client built with [Jaspr](https://jaspr.site), demonstrating interactive MCP features like **elicitation** and **sampling**.

## Features

- 🔌 **Connection Management** - Connect/disconnect from MCP servers
- 🛠️ **Tool Discovery** - Automatically lists available tools from the server
- 💬 **Elicitation** - Handle server requests for user confirmation via modal dialogs
- ✨ **Sampling** - Handle LLM completion requests with mock or custom responses
- 📊 **Real-time Logging** - Console-style output showing all MCP events
- 🎨 **Modern UI** - Dark theme with glassmorphism effects and smooth animations

## Prerequisites

- Dart SDK ^3.7.2
- Jaspr CLI (`dart pub global activate jaspr_cli`)

## Quick Start

### 1. Start the MCP Server

First, start the interactive task server from the `mcp_dart` example directory:

```bash
cd example
dart run simple_task_interactive_server.dart
```

The server will start on `http://localhost:8000/mcp`.

### 2. Start the Jaspr Client

In a new terminal, navigate to the jaspr-client directory and start the development server:

```bash
cd example/jaspr-client
dart pub get
jaspr serve
```

### 3. Open the Client

Open your browser to `http://localhost:8080`.

## Usage

### Connecting to the Server

1. Enter the server URL (default: `http://localhost:8000/mcp`)
2. Click **Connect**
3. The available tools will be automatically listed

### Using Tools

The server provides two demo tools:

#### `confirm_delete` (Elicitation Demo)

- Click **Call** on the `confirm_delete` tool
- A modal dialog will appear asking for confirmation
- Click **Yes** or **No** to respond
- The result will be displayed in the output panel

#### `write_haiku` (Sampling Demo)

- Click **Call** on the `write_haiku` tool
- A modal dialog will appear requesting an LLM response
- Choose to use the mock haiku response or enter your own
- Click **Submit Response** to complete the request

## Architecture

```
lib/
├── app.dart                    # Main App component with state management
├── main.client.dart            # Browser entry point
├── components/
│   ├── connection_panel.dart   # Server URL input and connect/disconnect
│   ├── tools_panel.dart        # Tool listing and invocation
│   ├── output_panel.dart       # Console-style log viewer
│   ├── elicitation_dialog.dart # Modal for confirmation requests
│   └── sampling_dialog.dart    # Modal for LLM completion requests
└── services/
    └── mcp_service.dart        # Type-safe MCP client service
```

### Key Design Decisions

- **Sealed Event Classes**: The `McpEvent` hierarchy uses Dart's sealed classes for exhaustive pattern matching
- **Stream-based Architecture**: Events are delivered via a broadcast stream for reactive UI updates
- **Type Safety**: Strong typing throughout with proper null safety
- **Separation of Concerns**: UI components are decoupled from the MCP service layer

## Technical Notes

### Transport

This example uses `StreamableHttpClientTransport` which is compatible with web browsers (unlike `StdioClientTransport` which requires `dart:io`).

### Capabilities

The client is configured with:
- **Elicitation**: Form-based elicitation support
- **Sampling**: LLM completion request handling
- **Tasks**: Full task management with elicitation and sampling in task context

## Development

### Project Structure

- `lib/` - Dart source code
- `web/` - Static web assets (HTML, CSS, favicon)
- `pubspec.yaml` - Package dependencies

### Running in Development

```bash
jaspr serve
```

This starts a development server with hot reload at `http://localhost:8080`.

### Building for Production

```bash
jaspr build
```

Output will be in the `build/` directory.

## Troubleshooting

### CORS Issues

If you encounter CORS issues, ensure the MCP server allows cross-origin requests, or run both the server and client on the same origin.

### Connection Refused

Make sure the MCP server is running before attempting to connect:

```bash
dart run example/simple_task_interactive_server.dart
```

## Related Examples

- `anthropic-client/` - CLI-based MCP client with Anthropic API integration
- `gemini-client/` - CLI-based MCP client with Google Gemini integration
- `flutter_http_client/` - Flutter-based MCP client with full mobile support
- `streamable_https/` - Interactive CLI client with streamable HTTP transport
