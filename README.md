# MCP (Model Context Protocol) for Dart

[![Coverage](https://img.shields.io/codecov/c/github/leehack/mcp_dart)](https://app.codecov.io/gh/leehack/mcp_dart)
[![Pub Version](https://img.shields.io/pub/v/mcp_dart?color=blueviolet)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

`mcp_dart` is a dual-era Dart and Flutter SDK for MCP clients, servers, and AI
hosts. It implements the complete core client/server wire surface of the locked
MCP `2026-07-28` release candidate, retains the MCP `2025-11-25` feature set,
and negotiates supported earlier initialization-based versions.

Here, core means the normative wire requirements assigned to client and server
roles by the pinned RC. It excludes optional MCP extensions, host UI behavior,
an authorization-server implementation, and a general-purpose JSON Schema
validation engine.

> [!IMPORTANT]
> This prerelease coordinates `mcp_dart 2.3.0-dev.2` and
> `mcp_dart_cli 0.2.0-dev.2`. All current official conformance scenarios
> applicable to the SDK's core client/server roles pass for both MCP
> `2025-11-25` and the `2026-07-28` RC. This is prerelease evidence, not a
> claim about the final specification, which has not shipped.

## Requirements

| Package | Minimum Dart SDK |
| --- | --- |
| `mcp_dart 2.3.0-dev.2` | 3.5 |
| `mcp_dart_cli 0.2.0-dev.2` | 3.7 |

Install Dart from [dart.dev](https://dart.dev/get-dart).

## Installation

Use the latest stable SDK for production projects:

```bash
dart pub add mcp_dart
```

To test the 2026 preview, select the prerelease explicitly:

```yaml
dependencies:
  mcp_dart: ^2.3.0-dev.2
```

The remainder of this README describes dev.2. Stable users should follow the
documentation for the version resolved in their own `pubspec.lock`.

Prerelease packages are published in order: SDK first, then CLI. Verify the
requested version is available on pub.dev before installing the CLI or creating
a clean consumer project.

## What the SDK provides

- MCP servers, clients, and host integrations with null-safe Dart APIs.
- Core tools, resources, prompts, completion, elicitation, subscriptions,
  logging, roots, and sampling APIs with behavior selected for the negotiated
  protocol era. MCP 2026 logging is retained for compatibility but is
  deprecated upstream.
- Stdio, Streamable HTTP, IO stream, and custom transports.
- OAuth client discovery/PKCE hooks, server authentication callbacks, DNS
  rebinding protection, and strict Streamable HTTP validation.
- A Tasks extension implementation, MCP Apps metadata helpers, and generic
  extension negotiation. Extensions are separate from core protocol coverage.
- Automated 2025 and 2026 RC conformance, bidirectional TypeScript/Python
  interoperability fixtures, and a real-browser Streamable HTTP smoke test.

MCP has three roles: a host owns the user experience, a client connects that
host to one server, and a server exposes tools, resources, and prompts. A host
can manage multiple clients and servers.

## Protocol profiles

| Profile | Protocol behavior |
| --- | --- |
| `McpProtocol.stable` | Default dual-era profile: prefer the `2026-07-28` RC, then fall back to initialization-based MCP |
| `McpProtocol.legacy` | Initialization-era profile: negotiate `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05`, or `2024-10-07` |
| `McpProtocol.require2026` | Require the `2026-07-28` RC and reject legacy initialization |

The `stable` profile name describes the SDK's default compatibility policy, not
the maturity of the preferred wire version. Use `stableProtocolVersion` for
the official `2025-11-25` version, `previewProtocolVersion` for the locked RC,
and `defaultProtocolVersion` for this SDK preview's preferred version.

Select a profile only when you need to constrain negotiation:

```dart
final legacyClient = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(protocol: McpProtocol.legacy),
);

final strictPreviewServer = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
  options: const McpServerOptions(protocol: McpProtocol.require2026),
);
```

See the [2026 transition guide](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/mcp-2026-07-28-rc.md)
for fallback rules and 2026-only APIs, or run the
[strict 2026 example](https://github.com/leehack/mcp_dart/tree/v2.3.0-dev.2/example/mcp_2026_07_28).

## Quick start with the CLI

Install the matching preview CLI:

```bash
dart pub global activate mcp_dart_cli 0.2.0-dev.2
mcp_dart create my_server
cd my_server
mcp_dart inspect
```

The dev.2 CLI creates a project with `mcp_dart: ^2.3.0-dev.2`. The inspector
launches the generated stdio server itself. After leaving the interactive
inspector, you can run a single tool directly:

```bash
mcp_dart inspect --tool add --json-args '{"a": 1, "b": 2}'
```

Useful commands:

| Command | Purpose |
| --- | --- |
| `create` | Scaffold a Dart MCP server using the SDK channel paired with the CLI |
| `serve` | Run a generated server over stdio or HTTP |
| `doctor` | Check project health and connectivity |
| `inspect` | Interactively use a server's capabilities |
| `inspect-server` | Produce a structured report for a live server |
| `inspect-client` | Run a stdio harness that inspects a connecting client |
| `trace` | Proxy and record a real stdio session |
| `conformance` | Run the repository's built-in protocol regression fixtures |

See the [CLI documentation](https://github.com/leehack/mcp_dart/tree/mcp_dart_cli-v0.2.0-dev.2/packages/mcp_dart_cli)
for command options and scope.

## Documentation

- Start: [getting started](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/getting-started.md), [server guide](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/server-guide.md), [client guide](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/client-guide.md), [quick reference](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/quick-reference.md)
- Build: [tools](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/tools.md), [transports](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/transports.md), [examples](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/examples.md), [MCP Apps](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/mcp-apps.md)
- Deploy: [Streamable HTTP security](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/transports.md#dns-rebinding-protection), [OAuth examples](https://github.com/leehack/mcp_dart/tree/v2.3.0-dev.2/example/authentication), [Flutter recipes](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/flutter-recipes.md)
- Verify: [interop matrix](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/interoperability.md), [2025 coverage](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/spec-coverage-2025-11-25.md), [2026 preview coverage](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/spec-coverage-2026-07-28-rc.md), [day-0 runbook](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/mcp-2026-07-28-release-runbook.md)

## Authentication

`StreamableHttpClientTransport` supports `OAuthClientProvider` and optional
authorization-code discovery. Servers can use `authenticator` or
`authenticationHandler` and publish protected-resource metadata.

The checked-in OAuth examples store tokens in plaintext files for local
learning. Production applications must use platform secure storage or an
encrypted credential service. See the [OAuth examples](https://github.com/leehack/mcp_dart/tree/v2.3.0-dev.2/example/authentication)
and [Streamable HTTP authentication](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/transports.md#streamable-http-authentication).

## Platform support

| Target | Stdio | Streamable HTTP | IO/custom stream |
| --- | --- | --- | --- |
| Dart VM / desktop server | Yes | Client and server | Yes |
| Browser / Flutter Web | No process spawning | Client | Yes |
| Flutter mobile | Only app-managed native helpers | Remote client | Yes |
| Flutter desktop | Local helper processes | Client and server | Yes |

See [Flutter host and client recipes](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/doc/flutter-recipes.md)
for lifecycle and secure-storage guidance.

## Choosing a Dart MCP package

The Dart team maintains [`dart_mcp`](https://pub.dev/packages/dart_mcp) in
[`dart-lang/ai`](https://github.com/dart-lang/ai/tree/main/pkgs/dart_mcp).
Choose it when you prefer the Dart team's APIs. Choose `mcp_dart` when you need
this SDK's transport, security, compatibility, extension, and inspection
surface. Re-check both packages' current releases before a production decision.

## Support

- [Issues and bug reports](https://github.com/leehack/mcp_dart/issues)
- [SDK on pub.dev](https://pub.dev/packages/mcp_dart)
- [dev.2 API reference](https://pub.dev/documentation/mcp_dart/2.3.0-dev.2/)
- [Changelog](https://github.com/leehack/mcp_dart/blob/v2.3.0-dev.2/CHANGELOG.md)
- [MCP 2026-07-28 RC](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/)
- [MCP 2025-11-25 specification](https://modelcontextprotocol.io/specification/2025-11-25)
