/// Support for Model Controller Protocol (MCP) SDK for Dart.
///
/// This package provides a Dart implementation of the Model Controller Protocol (MCP),
/// which is designed to facilitate communication between clients and servers in a
/// structured and extensible way.
///
/// The library exports key modules and types for building MCP-based applications,
/// including server implementations, type definitions, and utilities.
library;

// Common exports for all platforms
export 'src/types.dart'; // Exports shared types used across the MCP protocol.
export 'src/shared/uuid.dart'; // Exports UUID generation utilities.
export 'src/shared/logging.dart'; // Exports logging for customization

// Platform-specific exports
export 'src/exports.dart' // Stub export for other platforms
    if (dart.library.js_interop) 'src/exports_web.dart'; // Web-specific exports
