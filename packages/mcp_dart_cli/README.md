# mcp_dart_cli

Command-line tools for creating Dart MCP servers and inspecting, tracing, or
regression-testing spec-compatible MCP servers and clients in any language.

## Installation

With Dart 3.7 or later, install the stable CLI:

```bash
dart pub global activate mcp_dart_cli
```

Install the coordinated MCP `2026-07-28` draft/RC preview explicitly:

```bash
dart pub global activate mcp_dart_cli 0.2.0-dev.2
```

Prerelease packages are published SDK first, then CLI. Confirm
`mcp_dart 2.3.0-dev.2` is available before installing this CLI preview.

Without Dart, install the latest stable standalone binary:

```bash
curl -fsSL https://raw.githubusercontent.com/leehack/mcp_dart/main/tool/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/leehack/mcp_dart/main/tool/install.ps1 | iex
```

Set `MCP_DART_INSTALL_DIR` to choose the install directory. Standalone
installers and `mcp_dart update` follow stable GitHub releases. Automatic update
checks are disabled in prerelease builds so a preview is never replaced by the
stable channel; reinstall the desired prerelease explicitly.

## Create a server

```bash
mcp_dart create my_server
cd my_server
mcp_dart serve
```

The dev.2 CLI writes `mcp_dart: ^2.3.0-dev.2`, the SDK channel tested with this
CLI. A stable CLI selects its matching stable SDK. You can also supply a local
Mason brick, Git URL, GitHub shorthand, or tree URL:

```bash
mcp_dart create my_server \
  --template owner/repo/path/to/brick@ref
```

## Commands

| Command | Purpose |
| --- | --- |
| `create` | Scaffold an MCP server project |
| `serve` | Run a generated server over stdio or HTTP |
| `doctor` | Check project setup and connectivity |
| `inspect` | Interactively list or invoke server primitives |
| `inspect-server` | Produce a structured report for a live server |
| `inspect-client` | Host a stdio harness that observes a connecting client |
| `trace` | Proxy stdio traffic and write a chronological JSON report |
| `list-tools` | Print a scriptable tool inventory |
| `call-tool` | Invoke one tool with JSON arguments |
| `conformance` | Run this package's built-in protocol regression fixtures |
| `skills` | Install or print the bundled MCP developer skill |
| `update` | Update a stable installation through its install channel |

Run `mcp_dart <command> --help` for every option.

## Inspect a server

Use `inspect` for ad hoc interaction:

```bash
# Project in the current directory
mcp_dart inspect
mcp_dart inspect --tool add --json-args '{"a": 1, "b": 2}'
mcp_dart inspect --resource manifest://app
mcp_dart inspect --prompt greeting --json-args '{"name": "World"}'

# Any stdio server
mcp_dart inspect -- npx -y @modelcontextprotocol/server-filesystem /tmp
mcp_dart inspect --env API_KEY=secret -- python server.py

# Streamable HTTP
mcp_dart inspect --url https://mcp.example.com/mcp
```

Use `inspect-server` for a pass/warning/fail report suitable for review or CI:

```bash
mcp_dart inspect-server --json -- node dist/server.js
mcp_dart inspect-server -- python server.py
mcp_dart inspect-server --json --url http://localhost:3000/mcp
```

Optional probe configuration supplies real arguments without guessing or
invoking every advertised operation:

```json
{
  "tools": [{"name": "search", "arguments": {"query": "mcp"}}],
  "resource": {"uri": "file:///tmp/example.txt", "subscribe": false},
  "prompt": {"name": "summarize", "arguments": {"topic": "MCP"}},
  "task": {
    "tool": "long_running",
    "arguments": {"duration": 250},
    "ttl": 60000,
    "cancel": false
  }
}
```

```bash
mcp_dart inspect-server --json --probe-config probes.json -- node server.js
```

Warnings fail only with `--strict`. The inspector exercises advertised and
safely configurable behavior; it does not certify complete spec compliance.
See the [inspection coverage and limits](https://github.com/leehack/mcp_dart/blob/mcp_dart_cli-v0.2.0-dev.2/packages/mcp_dart_cli/doc/inspection-coverage.md).

## Inspect a client or host

`inspect-client` acts as a temporary stdio MCP server. Point a client or host at
this command and write the report outside stdout, which is reserved for MCP:

```bash
mcp_dart inspect-client --report /tmp/mcp-client-report.json
```

The harness is passive by default. Add `--active-probes` only when you
intentionally want it to call legacy `roots/list`, `sampling/createMessage`, and
`elicitation/create`; those probes can expose local paths, incur model cost, or
open user interface.

The harness supports stateless `server/discover` and legacy initialization. It
records client metadata, capabilities, JSON-RPC shape, and use of the exposed
test tool, resource, and prompt. For legacy clients, it can actively probe
advertised roots, sampling, and elicitation.

## Trace stdio traffic

Configure a client to launch `mcp_dart trace` in place of its server, then put
the real server command after `--`:

```bash
mcp_dart trace --report /tmp/mcp-trace.json -- node server.js
```

The proxy keeps protocol frames on stdout, forwards server stderr, and records
raw frames, parsed messages, methods, IDs, timing, and parse errors.

Inspection and trace reports can contain credentials, tool arguments/results,
prompt or resource content, and other sensitive data. Store them with restricted
permissions, never commit or upload them unreviewed, and delete them when done.

## Scriptable tool smoke tests

```bash
mcp_dart list-tools --json -- node dist/server.js
mcp_dart list-tools --url http://localhost:3000/mcp

mcp_dart call-tool add \
  --json --json-args '{"a": 2, "b": 3}' -- node dist/server.js
mcp_dart call-tool search \
  --url http://localhost:3000/mcp --json-args '{"q": "mcp"}'
```

`call-tool` exits non-zero when the MCP result has `isError: true`.

## Built-in conformance fixtures

`conformance` runs this repository's MCP 2025-11-25 and 2026-07-28 draft/RC
wire regression cases, including malformed JSON-RPC, ID/token preservation,
negotiation, capabilities, stateless metadata, task metadata, and deterministic
fuzz cases.

```bash
mcp_dart conformance --suite all
mcp_dart conformance --suite spec
mcp_dart conformance --case jsonrpc.preserves-string-response-id
mcp_dart conformance --fuzz --iterations 64
mcp_dart conformance --json
```

This is a package regression gate, not a live certification scanner. Combine it
with live inspection, protocol logs, official conformance, and cross-SDK tests.

## Serve, doctor, update, and skills

```bash
mcp_dart serve --transport stdio
mcp_dart serve --transport http --host 127.0.0.1 --port 3000
mcp_dart doctor
mcp_dart update
mcp_dart skills install
```

For compiled stable binaries, `update` downloads the matching asset from the
latest stable CLI GitHub release. Pub-installed stable CLIs delegate to pub.
Prerelease builds require an explicit reinstall.

## Development and release validation

Run package tests from `packages/mcp_dart_cli`:

```bash
dart test
```

Validate the exported CLI package from the repository root:

```bash
dart run tool/validate_cli_publish.dart
```

Before publishing the CLI, validate against the already-published coordinated
SDK rather than the monorepo override:

```bash
dart run tool/validate_cli_publish.dart --published-sdk
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution instructions.
