/// This module provides stubs or minimal functionality for server components
/// that are compatible with web platforms.
///
/// Note that most server functionality is not intended to run in web browsers.
/// These exports provide stubs or limited functionality for web compatibility.
library;

export 'io_stubs.dart'; // API-compatible stubs for IO-only transports.
export 'mcp_server.dart'; // Web-safe MCP server facade and helpers.
export 'mcp_ui.dart'; // MCP Apps helper registrations.
export 'server.dart'; // Core server implementation.
export 'tasks.dart'; // Task management utilities.
