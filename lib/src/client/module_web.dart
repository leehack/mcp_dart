/// This module exports the core components required for the MCP client implementation
/// that are compatible with web platforms.
///
/// Web platforms have certain restrictions and not all functionality
/// is available. This module only includes web-compatible components.
library;

export './client.dart'; // Client-side implementation for MCP protocol.
export './streamable_https.dart'; // Streamable HTTPS implementation.
export './task_client.dart'; // Task client helper.
