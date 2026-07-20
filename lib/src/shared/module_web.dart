/// This module exports the web-compatible components of the MCP shared implementation.
///
/// For web platforms, certain IO-dependent functionality is excluded or replaced
/// with web-compatible alternatives.
library;

export 'iostream.dart'; // Stream/sink transport without dart:io dependencies.
export 'json_schema/json_schema_validator.dart'
    hide JsonSchemaDefinitionException; // JSON Schema validation.
export 'protocol.dart'; // MCP protocol utilities for message serialization/deserialization.
export 'task_interfaces.dart'; // Task interfaces.
export 'transport.dart'; // Transport layer for server-client communication.
export 'uri_template.dart'; // URI template utilities.
