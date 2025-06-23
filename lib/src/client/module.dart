/// This module exports the core components required for the MCP (Multi-Channel Protocol) client implementation.
///
/// - `client.dart`: Contains the client-side implementation for the MCP protocol.
/// - `stdio.dart`: Provides utilities for client communication using standard I/O (VM only).
/// - `streamable_https.dart`: Provides cross-platform HTTPS communication utilities.
library;

export 'client.dart'; // Client-side implementation for MCP protocol.
export 'stdio_stub.dart'
    if (dart.library.io) 'stdio.dart'; // Standard I/O-based client communication utilities (VM only).
export 'streamable_https.dart'; // Cross-platform HTTPS communication utilities.
