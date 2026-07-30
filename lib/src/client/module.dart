/// This module exports the core Model Context Protocol client components.
///
/// - `client.dart`: Contains the client-side implementation for the MCP protocol.
/// - `stdio.dart`: Provides utilities for client communication using standard I/O.
library;

export './client.dart'; // Client-side implementation for MCP protocol.
export './sse.dart'; // Deprecated HTTP+SSE compatibility transport.
export './stdio.dart'; // Standard I/O-based client communication utilities.
export './streamable_https.dart'; // Streamable HTTPS communication utilities.
export './task_client.dart'; // Task client helper.
