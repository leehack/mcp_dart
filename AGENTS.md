# mcp_dart

**Dart Implementation of Model Context Protocol (MCP) SDK.**
Enables building MCP servers and clients to connect AI applications with external tools and resources.

## Usage

**Installation:**
```bash
dart pub get
```

**Running Examples:**
```bash
# Server
dart run example/server_stdio.dart

# Client
dart run example/client_stdio.dart
```

**Testing:**
```bash
dart test
```

## Core Concepts

*   **McpServer:** Entry point for creating servers. Defines capabilities (Tools, Resources, Prompts).
*   **Client:** Entry point for connecting to servers and using their capabilities.
*   **Transport:** Communication layer.
    *   `StdioServerTransport` / `StdioClientTransport`: For CLI/Process communication.
    *   `StreamableHTTPClientTransport`: For Web/Remote communication.
*   **Capabilities:**
    *   **Tools:** Executable functions.
    *   **Resources:** Content/data access.
    *   **Prompts:** Reusable interaction templates.

## Reference

*   **Main Entry:** `lib/mcp_dart.dart`
*   **Documentation:** `doc/` contains detailed guides for Server, Client, and Transports.
