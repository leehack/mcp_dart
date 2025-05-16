/// This module exports the web-compatible components of the MCP shared implementation.
///
/// For web platforms, certain IO-dependent functionality is excluded or replaced
/// with web-compatible alternatives.
library;

export 'protocol.dart'; // MCP protocol utilities for message serialization/deserialization.
export 'transport.dart'; // Transport layer for server-client communication.
export 'uri_template.dart'; // URI template utilities.
