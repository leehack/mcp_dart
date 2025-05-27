# MCP Web Client Example

This is an example Flutter web application that demonstrates how to use the MCP (Model Context Protocol) client in a web environment. The application provides a simple button-based interface for direct interaction with an MCP server using streamable HTTP connections.

## Features

- Connect to any MCP-compliant server
- Discover and call server tools
- List and retrieve prompts
- View available resources
- Receive and display notifications from the server
- Full support for StreamableHttpClientTransport from the MCP Dart library

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK (latest stable version)
- An MCP server to connect to (use the included test server)

### Running the Example

1. First, start an MCP server:

```shell
cd /path/to/mcp_dart/example/streamable_https
dart server_streamable_https.dart
```

This will start an MCP server on `http://localhost:3000/mcp`.

2. In a separate terminal, run the Flutter web app:

```shell
cd /path/to/mcp_dart/example/web_client
flutter run -d chrome
```

This will launch the application in Chrome. You can also use other browsers by specifying a different device.

3. In the application, click the "Connect" button to establish a connection to the server.

4. Once connected, you can use various buttons to interact with the server:
   - List Tools: See available tools on the server
   - Call Tool: Execute a tool with arguments
   - List Prompts: View available prompts
   - List Resources: See available resources
   - Start Notifications: Begin receiving server notifications

## Project Structure

- `lib/main.dart` - Entry point of the application
- `lib/services/streamable_mcp_service.dart` - Service for communicating with MCP servers
- `lib/screens/mcp_client_screen.dart` - Main UI interface with button controls
- `lib/screens/settings_screen.dart` - Settings screen for connection management
- `lib/widgets/chat_widgets.dart` - UI components for the chat interface
- `test_server.dart` - Simple MCP server for testing

## Understanding MCP Communication

The application demonstrates key aspects of MCP client implementation:

1. **Connection**: The client establishes a connection to the MCP server and retrieves capabilities.
2. **Tool Calling**: The client calls tools on the server with parameters.
3. **Notifications**: The client receives real-time notifications from server tools.
4. **Streaming Responses**: For a more interactive experience, the server can stream partial responses as they are generated.

The `McpClientService` class handles all communication with the server and exposes streams that the UI can listen to for updates.

## Customization

You can modify this example to connect to different MCP servers or implement additional features:

- Change the server URL in the settings
- Add support for more complex tool parameters
- Implement authentication for secure MCP servers
- Add file upload/download capabilities
- Customize the UI for your specific use case

## Web Compatibility

This example demonstrates the web-compatible implementation of MCP using streamable HTTP connections. The `mcp_dart` library provides platform-specific implementations that work seamlessly in web environments.
