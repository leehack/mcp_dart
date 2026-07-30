# MCP (Model Context Protocol) for Dart

[![Coverage](https://img.shields.io/codecov/c/github/leehack/mcp_dart)](https://app.codecov.io/gh/leehack/mcp_dart)
[![Stable package](https://img.shields.io/pub/v/mcp_dart?color=blueviolet&label=stable)](https://pub.dev/packages/mcp_dart)
[![likes](https://img.shields.io/pub/likes/mcp_dart?logo=dart)](https://pub.dev/packages/mcp_dart/score)

`mcp_dart` is a dual-era Dart and Flutter SDK for MCP clients, servers, and AI
hosts. It implements the complete core client/server wire surface of the locked
MCP 2026-07-28 specification, retains the MCP 2025-11-25 feature set, and
negotiates supported earlier initialization-based specifications.

Here, core means the normative wire requirements assigned to client and server
roles by the pinned final specification. It excludes optional MCP
extensions, host UI behavior, an authorization-server implementation, JSON
Schema external-reference resolution, and custom JSON Schema vocabularies.

> [!IMPORTANT]
> The coordinated stable release pairs `mcp_dart 2.3.0` with
> `mcp_dart_cli 0.2.0`. Current source passes the official alpha.10 MCP
> `2026-07-28` client and server suites with no expected failures, including
> all 25 authorization scenarios, plus bidirectional published TypeScript SDK
> 2.0.0 and Python SDK 2.0.0 interoperability.

## SDK Tier 1 target

The project is pursuing
[MCP SDK Tier 1](https://modelcontextprotocol.io/community/sdk-tiers). Tier 1
is not yet claimed or assigned. The technical baseline is green; the remaining
official audit, repository-governance, and SDK Working Group steps are tracked
in the [roadmap](ROADMAP.md) and
[48-feature coverage inventory](doc/sdk-tier-1-feature-coverage.md).

The public maintenance contract is documented in the
[contribution guide](CONTRIBUTING.md), [security policy](SECURITY.md),
[dependency policy](DEPENDENCY_POLICY.md), and
[versioning policy](VERSIONING.md).

## Requirements

| Package | Minimum Dart SDK |
| --- | --- |
| `mcp_dart 2.3.0` | 3.4 |
| `mcp_dart_cli 0.2.0` | 3.12 |

SDK-only generated projects retain the SDK's Dart 3.4 minimum. CLI projects
use Dart 3.12 because the CLI and its toolchain target that release.

Install Dart from [dart.dev](https://dart.dev/get-dart).

## Installation

### Production channel

Use the latest stable package for production projects:

```bash
dart pub add mcp_dart
```

### Pin the coordinated stable release

Pin the stable 2.3 line explicitly when reproducible dependency resolution is
important:

```yaml
dependencies:
  mcp_dart: ^2.3.0
```

The snippets below use the coordinated stable package line. Package versions
remain separate from protocol profiles: `McpProtocol.stable` names the SDK's
default compatibility policy.

The coordinated release publishes the SDK first and the CLI after the exact SDK
version is available on pub.dev.

For direct SDK integration, start with the
[getting-started guide](https://github.com/leehack/mcp_dart/blob/main/doc/getting-started.md).
The CLI below is optional and provides scaffolding, inspection, and conformance
commands.

## What the SDK provides

- MCP servers, clients, and host integrations with null-safe Dart APIs.
- Core tools, resources, prompts, completion, elicitation, subscriptions,
  logging, roots, and sampling APIs with behavior selected for the negotiated
  protocol era. MCP 2026-07-28 logging is retained for compatibility but is
  deprecated upstream.
- Stdio, Streamable HTTP, IO stream, and custom transports.
- OAuth client discovery/PKCE hooks, server authentication callbacks, DNS
  rebinding protection, and strict Streamable HTTP validation.
- An experimental Tasks extension implementation, MCP Apps metadata helpers,
  and generic extension negotiation. Extensions are separate from core
  protocol coverage; Tasks is not an official extension or part of the SDK's
  core conformance claim.
- Automated MCP 2025-11-25 and MCP 2026-07-28 conformance, bidirectional
  published TypeScript SDK 2.0.0 interoperability, bidirectional Python SDK
  2.0.0 interoperability, real-browser transport tests, a real Flutter Web
  service integration in Chrome, deterministic widget tests, and an
  independent pinned JSON Schema Test Suite gate.
- Current unreleased source adds a deprecated, opt-in legacy HTTP+SSE client
  with same-origin routing and official TypeScript SSE server interoperability.
  Stable `2.3.0` does not include that client; it requires the next approved
  minor SDK release.

MCP has three roles: a host owns the user experience, a client connects that
host to one server, and a server exposes tools, resources, and prompts. A host
can manage multiple clients and servers.

## Protocol profiles

| Profile | Protocol behavior |
| --- | --- |
| `McpProtocol.stable` | Default dual-era profile: prefer MCP 2026-07-28, then fall back to initialization-based MCP specifications; body-only discovery probes are bounded to 5 seconds |
| `McpProtocol.legacy` | Initialization-era profile: negotiate the MCP 2025-11-25, MCP 2025-06-18, MCP 2025-03-26, MCP 2024-11-05, or MCP 2024-10-07 specification |
| `McpProtocol.require2026` | Require MCP 2026-07-28 and reject legacy initialization |

Use `stableProtocolVersion` or `defaultProtocolVersion` for MCP `2026-07-28`.
`previewProtocolVersion` remains as a deprecated alias for applications built
against a 2.3 prerelease.
`latestInitializationProtocolVersion` remains `2025-11-25` when the default
profile falls back to the legacy lifecycle. For compatibility,
`latestProtocolVersion` and `supportedProtocolVersions` retain their mcp_dart
2.2 initialization-era values; use `allSupportedProtocolVersions` for the
dual-era list.

Select a profile only when you need to constrain negotiation:

```dart
final legacyClient = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(protocol: McpProtocol.legacy),
);

final strict2026Server = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
  options: const McpServerOptions(protocol: McpProtocol.require2026),
);
```

See the [MCP 2026-07-28 transition guide](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-07-28.md)
for fallback rules and APIs specific to MCP 2026-07-28, or run the
[strict MCP 2026-07-28 example](https://github.com/leehack/mcp_dart/tree/main/example/mcp_2026_07_28).
Applications upgrading from the stable 2.2 line should also follow the
[2.2 to 2.3 migration guide](https://github.com/leehack/mcp_dart/blob/main/doc/migration-2.2-to-2.3.md).

## Quick start with the CLI

Install the matching stable CLI:

```bash
dart pub global activate mcp_dart_cli 0.2.0
mcp_dart create my_server
cd my_server
mcp_dart inspect
```

The `0.2.0` CLI creates a project with `mcp_dart: ^2.3.0`. The inspector
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

See the [CLI documentation](https://github.com/leehack/mcp_dart/tree/main/packages/mcp_dart_cli)
for command options and scope.

## Documentation

- Start: [getting started](https://github.com/leehack/mcp_dart/blob/main/doc/getting-started.md), [server guide](https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md), [client guide](https://github.com/leehack/mcp_dart/blob/main/doc/client-guide.md), [quick reference](https://github.com/leehack/mcp_dart/blob/main/doc/quick-reference.md)
- Upgrade: [2.2 to 2.3 migration guide](https://github.com/leehack/mcp_dart/blob/main/doc/migration-2.2-to-2.3.md), [migration cookbooks](https://github.com/leehack/mcp_dart/blob/main/doc/migration-cookbooks.md), [MCP 2026-07-28 transition guide](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-07-28.md)
- Build: [tools](https://github.com/leehack/mcp_dart/blob/main/doc/tools.md), [transports](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md), [examples](https://github.com/leehack/mcp_dart/blob/main/doc/examples.md), [MCP Apps](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-apps.md)
- Deploy: [Streamable HTTP security](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md#dns-rebinding-protection), [OAuth examples](https://github.com/leehack/mcp_dart/tree/main/example/authentication), [Flutter recipes](https://github.com/leehack/mcp_dart/blob/main/doc/flutter-recipes.md)
- Verify: [interop matrix](https://github.com/leehack/mcp_dart/blob/main/doc/interoperability.md), [MCP 2025-11-25 coverage](https://github.com/leehack/mcp_dart/blob/main/doc/spec-coverage-2025-11-25.md), [MCP 2026-07-28 coverage](https://github.com/leehack/mcp_dart/blob/main/doc/spec-coverage-2026-07-28.md), [day-0 runbook](https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-07-28-release-runbook.md)

Standalone integration examples may declare newer Dart SDK requirements; check
each example README before running it.

## Authentication

`StreamableHttpClientTransport` supports `OAuthClientProvider` and optional
authorization-code discovery. Servers can use `authenticator` or
`authenticationHandler` and publish protected-resource metadata.

The checked-in OAuth examples store tokens in plaintext files for local
learning. Production applications must use platform secure storage or an
encrypted credential service. See the [OAuth examples](https://github.com/leehack/mcp_dart/tree/main/example/authentication)
and [Streamable HTTP authentication](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md#streamable-http-authentication).

Do not expose example HTTP servers directly to untrusted networks. Production
deployments should use TLS, authenticate requests, and configure the documented
[Host and Origin protections](https://github.com/leehack/mcp_dart/blob/main/doc/transports.md#dns-rebinding-protection).

## Platform support

| Target | Stdio | Streamable HTTP | Legacy HTTP+SSE | IO/custom stream |
| --- | --- | --- | --- | --- |
| Dart VM / desktop server | Yes | Client and server | Client and server | Yes |
| Browser / Flutter Web | No process spawning | Client | Client | Yes |
| Flutter mobile | Only app-managed native helpers | Remote client | Remote client | Yes |
| Flutter desktop | Local helper processes | Client and server | Client and server | Yes |

Legacy HTTP+SSE is deprecated under MCP SEP-2596 and is retained only for
explicit compatibility. Use Streamable HTTP for new remote integrations.

See [Flutter host and client recipes](https://github.com/leehack/mcp_dart/blob/main/doc/flutter-recipes.md)
for lifecycle and secure-storage guidance.

## Choosing a Dart MCP package

The Dart team maintains [`dart_mcp`](https://pub.dev/packages/dart_mcp) in
[`dart-lang/ai`](https://github.com/dart-lang/ai/tree/main/pkgs/dart_mcp).
Choose it when you prefer the Dart team's APIs. Choose `mcp_dart` when you need
this SDK's transport, security, compatibility, extension, and inspection
surface. Re-check both packages' current releases before a production decision.

## Support

- [Issues and bug reports](https://github.com/leehack/mcp_dart/issues)
- [Contribution and issue-triage policy](https://github.com/leehack/mcp_dart/blob/main/CONTRIBUTING.md)
- [Security policy](https://github.com/leehack/mcp_dart/blob/main/SECURITY.md)
- [Dependency policy](https://github.com/leehack/mcp_dart/blob/main/DEPENDENCY_POLICY.md)
- [Versioning policy](https://github.com/leehack/mcp_dart/blob/main/VERSIONING.md)
- [Tier 1 roadmap](https://github.com/leehack/mcp_dart/blob/main/ROADMAP.md)
- [SDK on pub.dev](https://pub.dev/packages/mcp_dart)
- [2.3.0 API reference](https://pub.dev/documentation/mcp_dart/2.3.0/)
- [Changelog](https://github.com/leehack/mcp_dart/blob/main/CHANGELOG.md)
- [MCP 2026-07-28 specification](https://modelcontextprotocol.io/specification/2026-07-28)
- [MCP 2025-11-25 specification](https://modelcontextprotocol.io/specification/2025-11-25)
