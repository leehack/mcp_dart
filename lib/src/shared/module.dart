/// This module exports key components of the MCP server implementation.
///
/// It includes the main server logic, server-sent events (SSE) handling,
/// MCP protocol utilities, and standard I/O-based server communication.
library;

export 'iostream.dart'; // Core server implementation for handling MCP logic.
export 'json_schema_validator.dart'; // JSON Schema validator.
export 'protocol.dart'; // MCP protocol utilities for message serialization/deserialization.
export 'transport.dart'; // Transport layer for server-client communication.
export 'task_interfaces.dart'; // Task interfaces.
