# MCP (Model Context Protocol) for Dart

[![Coverage](https://img.shields.io/codecov/c/github/leehack/mcp_dart)](https://app.codecov.io/gh/leehack/mcp_dart)
[![Pub Version](https://img.shields.io/pub/v/mcp_dart?color=blueviolet)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

`mcp_dart` is a Dart and Flutter SDK for building Model Context Protocol
(MCP) servers, clients, and AI host integrations. Use it to expose Dart tools
over stdio or Streamable HTTP, connect Flutter apps to MCP servers, and validate
real deployments with the companion CLI.

The Model Context Protocol (MCP) is a standardized protocol for communication between AI applications and external services. It enables:

- **Tools**: Allow AI to execute actions (API calls, computations, etc.)
- **Resources**: Provide context and data to AI (files, databases, APIs)
- **Prompts**: Pre-built prompt templates with arguments

## Understanding MCP: Client, Server, and Host

MCP follows a **client-server architecture** with three key components:

- **MCP Host**: The AI application that provides the user interface and manages connections to multiple MCP servers.
  - Example: Claude Desktop, IDEs like VS Code, custom AI applications
  - Manages server lifecycle, discovers capabilities, and orchestrates interactions

- **MCP Client**: The protocol implementation within the host that communicates with servers.
  - Handles protocol negotiation, capability discovery, and request/response flow
  - Typically built into or used by the MCP host

- **MCP Server**: Provides capabilities (tools, resources, prompts) that AI can use through the host.
  - Example: Servers for file system access, database queries, or API integrations
  - Runs as a separate process and communicates via standardized transports (stdio, StreamableHTTP)

**Typical Flow**: User ↔ MCP Host (with Client) ↔ MCP Protocol ↔ Your Server ↔ External Services/Data

## Requirements

- Dart SDK version ^3.0.0 or higher

Ensure you have the correct Dart SDK version installed. See <https://dart.dev/get-dart> for installation instructions.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_dart: ^2.2.0
```

Then install dependencies:

```bash
dart pub get
```

## What This SDK Provides

**This SDK lets you build both MCP servers and clients in Dart/Flutter.**

- ✅ **Build MCP Servers** - Create servers that expose tools, resources, and prompts to AI hosts
- ✅ **Build MCP Clients** - Create AI applications that can connect to and use MCP servers
- ✅ **Full MCP Protocol Support** - Complete [MCP specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25) implementation
- ✅ **Multiple Transport Options** - Stdio, StreamableHTTP, IOStream, or custom transports
- ✅ **All Capabilities** - Tools, Resources, Prompts, Sampling, Roots, Completions, Elicitation, Tasks
- ✅ **Extension Support** - Generic `extensions` negotiation with typed MCP Apps helpers and TypeScript-style `registerAppTool` / `registerAppResource`
- ✅ **Latest Content/Metadata Types** - `resource_link`, themed `icons`, `Resource.size`, `Root._meta`, and `annotations.lastModified`
- ✅ **OAuth Authentication Hooks** - `OAuthClientProvider`, MCP OAuth discovery helpers, server authenticators, and OAuth2/PKCE examples
- ✅ **Transport Security Controls** - DNS rebinding protection and strict Streamable HTTP validation with compatibility toggles
- ✅ **Type-Safe** - Comprehensive type definitions with null safety
- ✅ **Cross-Platform** - Works on Linux, Windows, macOS, Web, and Flutter

The goal is to make this SDK as similar as possible to the official SDKs available in other languages, ensuring a consistent developer experience across platforms.

## Choosing between `mcp_dart` and the Dart team `dart_mcp` package

The Dart ecosystem now has more than one MCP package. The Dart team-maintained [`dart_mcp`](https://pub.dev/packages/dart_mcp) package lives in [`dart-lang/ai`](https://github.com/dart-lang/ai/tree/main/pkgs/dart_mcp) and is a good place to look when you specifically want the Dart team's implementation.

`mcp_dart` is a community SDK focused on production-oriented MCP servers and clients for Dart and Flutter applications. It is designed for teams that need broad protocol coverage, multiple transports, security controls, and tooling around real deployments.

| Package | Best fit | Notes |
|---------|----------|-------|
| `dart_mcp` | Projects that prefer the Dart team-maintained package or want to follow the Dart team's evolving MCP APIs closely. | Check the package docs and changelog for its current feature set and stability guarantees. |
| `mcp_dart` | Production-focused Dart/Flutter MCP servers, clients, and hosts that need broad transport, auth, security, and tooling support today. | Includes StreamableHTTP, `OAuthClientProvider` and server `authenticator` hooks with OAuth2/PKCE examples, MCP Apps helpers, strict transport security controls, CLI tooling, and compatibility with MCP protocol version `2025-11-25`. |

Use this comparison as a starting point, not a permanent verdict: both packages can evolve quickly. If you compare them for a production decision, re-check the current pub.dev releases and docs first.

## Model Context Protocol Version

The default protocol profile is MCP `2025-11-25`. This library is designed to
be compatible with this version, and any future updates will preserve an
explicit stable profile.

It's also backward compatible with previous versions including `2025-06-18`, `2025-03-26`, `2024-11-05`, and `2024-10-07`.

MCP `2026-07-28` RC support is available behind an explicit preview profile:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(
    protocol: McpProtocol.preview2026,
  ),
);

final server = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
  options: const McpServerOptions(
    protocol: McpProtocol.preview2026,
  ),
);
```

Use the preview profile while the spec is still an RC. See the
[MCP 2026 RC transition guide](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-rc.md)
for opt-in behavior, fallback rules, and 2026-only APIs.

## Documentation

### Getting Started

- 📖 **[Quick Start Guide](https://github.com/leehack/mcp_dart/blob/main/doc/getting-started.md)** - Get up and running in 5 minutes
- 🔧 **[Server Guide](https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md)** - Complete guide to building MCP servers
- 💻 **[Client Guide](https://github.com/leehack/mcp_dart/blob/main/doc/client-guide.md)** - Complete guide to building MCP clients

### Core Concepts

- 🛠️ **[Tools Documentation](https://github.com/leehack/mcp_dart/blob/main/doc/tools.md)** - Implementing executable tools
- 🔌 **[Transport Options](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md)** - Built-in and custom transport implementations
- 📚 **[Examples](https://github.com/leehack/mcp_dart/blob/main/doc/examples.md)** - Real-world usage examples
- ⚡ **[Quick Reference](https://github.com/leehack/mcp_dart/blob/main/doc/quick-reference.md)** - Fast lookup guide
- 🪵 **[Runtime Logging](https://github.com/leehack/mcp_dart/blob/main/doc/getting-started.md#sdk-runtime-logging)** - Configure and route internal SDK logs
- 🧩 **[MCP Apps Guide](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-apps.md)** - Using `io.modelcontextprotocol/ui` metadata

### Recipes and Compatibility

- 🧪 **[SDK Interoperability Matrix](https://github.com/leehack/mcp_dart/blob/main/doc/interoperability.md)** - Verified Dart/TypeScript and documented cross-SDK scenarios
- ✅ **[MCP 2025-11-25 Spec Coverage Matrix](https://github.com/leehack/mcp_dart/blob/main/doc/spec-coverage-2025-11-25.md)** - Auditable coverage map with CLI conformance cases and known gaps
- 🧭 **[MCP 2026 RC Transition Guide](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-rc.md)** - Opt-in profile, fallback behavior, and draft-only APIs
- 🔒 **[Transport Security Recipes](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md#dns-rebinding-protection)** - Host/Origin allowlists, OAuth layering, and compatibility-toggle trade-offs
- 📱 **[Flutter Recipes](https://github.com/leehack/mcp_dart/blob/main/doc/flutter-recipes.md)** - Flutter Web, mobile, and desktop host/client guidance
- 🔁 **[Migration Cookbooks](https://github.com/leehack/mcp_dart/blob/main/doc/migration-cookbooks.md)** - TypeScript SDK, `dart_mcp`, stdio-to-HTTP, and version migration paths

### Advanced Features

- 🔐 **[OAuth Authentication](https://github.com/leehack/mcp_dart/tree/main/example/authentication)** - OAuth2 guides and examples
- 🔁 **[2025-11-25 Compatibility Migration](https://github.com/leehack/mcp_dart/blob/main/doc/migration_2025_11_25_compat.md)** - Backward-compatible API/runtime migration notes
- 📝 For resources, prompts, and other features, see the Server and Client guides

## Quick Start with CLI

The fastest way to create an MCP server is using the `mcp_dart_cli`:

```bash
# Install the CLI
dart pub global activate mcp_dart_cli

# Create a new project
mcp_dart create my_server

# Navigate and run
cd my_server
mcp_dart serve
```

Your server is now running! Use `mcp_dart inspect` to test it:

```bash
mcp_dart inspect              # List all capabilities
mcp_dart inspect --tool add --json-args '{"a": 1, "b": 2}'   # Call a tool
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `create` | Scaffold a new MCP server project |
| `serve` | Run your server (stdio or HTTP) |
| `doctor` | Check project health and connectivity |
| `inspect` | Test and debug server capabilities |
| `inspect-server` | Produce a structured live server inspection report |
| `inspect-client` | Run a stdio harness that inspects a connecting client |
| `trace` | Proxy stdio client/server traffic and write a JSON trace |

📖 **[Full CLI Documentation](https://github.com/leehack/mcp_dart/tree/main/packages/mcp_dart_cli)**

### Connecting to AI Hosts

Configure your server with AI hosts like Claude Desktop:

```json
{
  "mcpServers": {
    "my_server": {
      "command": "mcp_dart",
      "args": ["serve"],
      "cwd": "/path/to/my_server"
    }
  }
}
```

> [!TIP]
> For manual server implementation or advanced use cases, see the [Server Guide](https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md).

## Authentication

This library provides OAuth-aware client and server authentication hooks, including `OAuthClientProvider` for StreamableHTTP clients, optional `OAuthAuthorizationCodeProvider` discovery support, and server-side `authenticator` / `authenticationHandler` callbacks. For OAuth2/PKCE guides and examples, see the [OAuth Authentication documentation](https://github.com/leehack/mcp_dart/tree/main/example/authentication) and [transport authentication docs](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md#streamable-http-authentication).

## Platform Support

| Platform | Stdio | StreamableHTTP | IOStream | Custom |
|----------|-------|----------------|----------|--------|
| **Desktop** (CLI/Server) | ✅ | ✅ | ✅ | ✅ |
| **Web** (Browser) | ❌ | ✅ | ✅ | ✅ |
| **Flutter** (Mobile/Desktop) | ✅ | ✅ | ✅ | ✅ |

**Custom Transports**: You can implement your own transport layer by extending the transport interfaces if you need specific communication patterns not covered by the built-in options.

## More Examples

For additional examples including authentication, HTTP clients, and advanced features:

- [All Examples](https://github.com/leehack/mcp_dart/tree/main/example)
- [Authentication Examples](https://github.com/leehack/mcp_dart/tree/main/example/authentication)

## Community & Support

- **Issues & Bug Reports**: [GitHub Issues](https://github.com/leehack/mcp_dart/issues)
- **Package**: [pub.dev/packages/mcp_dart](https://pub.dev/packages/mcp_dart)
- **API Docs**: [pub.dev documentation](https://pub.dev/documentation/mcp_dart/latest/)
- **Changelog**: [CHANGELOG.md](https://github.com/leehack/mcp_dart/blob/main/CHANGELOG.md)
- **Protocol Spec**: [MCP Specification](https://modelcontextprotocol.io/specification/2025-11-25)

## Credits

This library is inspired by the following projects:

- <https://github.com/crbrotea/dart_mcp>
- <https://github.com/nmfisher/simple_dart_mcp_server>
