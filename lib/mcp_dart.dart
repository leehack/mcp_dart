/// Support for Model Controller Protocol (MCP) SDK for Dart.
///
/// This package provides a Dart implementation of the Model Controller Protocol (MCP),
/// which is designed to facilitate communication between clients and servers in a
/// structured and extensible way.
///
/// The library exports key modules and types for building MCP-based applications,
/// including server implementations, type definitions, and utilities.
library;

export 'src/server/server_stub.dart'
    if (dart.library.io) 'src/server/module.dart'; // Exports the server module for handling MCP server logic (VM only).
export 'src/client/module.dart'; // Exports the client module for handling MCP client logic.
export 'src/shared/module.dart'; // Exports the shared module for handling MCP shared logic.
export 'src/types.dart'; // Exports shared types used across the MCP protocol.
export 'src/shared/uuid.dart'; // Exports UUID generation utilities.
