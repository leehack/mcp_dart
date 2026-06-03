# mcp_dart_cli

Command-line tools for creating, serving, inspecting, and testing Model Context
Protocol (MCP) servers and clients. The CLI is useful for Dart projects, but
the debugging commands are intended to work against any spec-compatible MCP
server.

## Installation

With the Dart SDK:

```bash
dart pub global activate mcp_dart_cli
```

Without the Dart SDK, install the latest standalone binary from GitHub Releases:

```bash
curl -fsSL https://raw.githubusercontent.com/leehack/mcp_dart/main/tool/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/leehack/mcp_dart/main/tool/install.ps1 | iex
```

Set `MCP_DART_INSTALL_DIR` to choose the installation directory. Re-running the
same command upgrades the binary. Installed binaries can also run:

```bash
mcp_dart update
```

## Usage

### Create a new project

```bash
mcp_dart create <project_name> [directory]
```

Or simply specify the directory and let the CLI infer the project name:

```bash
mcp_dart create path/to/my_project
```

If `directory` is omitted, the project will be created in the current directory with the name `<project_name>`.


### Create from a specific template

You can use a local path, a Git URL, or a GitHub tree URL as a template.

```bash
# From a local path
mcp_dart create <project_name> --template path/to/template

# From a Git repository
mcp_dart create <project_name> --template https://github.com/username/repo.git

# From a Git repository with a specific ref and path
mcp_dart create <project_name> --template https://github.com/username/repo.git#ref:path/to/brick

# From a GitHub repository using short syntax
mcp_dart create <project_name> --template owner/repo/path/to/brick@ref

# From a specific path in a GitHub repository (tree URL)
mcp_dart create <project_name> --template https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple
```

## Commands

- `create`: Creates a new MCP server project.
- `serve`: Runs the MCP server in the current directory.
- `doctor`: Checks the project for common issues and verifies connectivity.
- `inspect`: Interacts with an MCP server (local or external).
- `inspect-server`: Produces a structured inspection report for a live MCP server.
- `inspect-client`: Runs a stdio MCP test server that inspects a connecting client.
- `trace`: Proxies stdio MCP traffic between a client and server and writes a JSON trace.
- `list-tools`: Lists tools advertised by a stdio or Streamable HTTP server.
- `call-tool`: Calls one tool with JSON arguments.
- `conformance`: Runs this package's built-in protocol regression fixtures.
- `skills`: Installs or prints bundled MCP agent workflow skills.
- `update`: Updates the CLI to the latest version.

## Inspection Scope

Use `inspect-server` and `inspect-client` as the live inspection workflow for
MCP servers, clients, and agent hosts. These commands connect to a real target,
exercise advertised protocol features, and return pass/warning/fail checks in a
structured report.

`inspect` remains the broader interactive command for ad hoc tools, resources,
prompts, sampling, and notification debugging. `trace` captures a real stdio
client/server session without changing the JSON-RPC traffic. `list-tools` and
`call-tool` provide small scriptable smoke tests.

`conformance` is not a second live target validator. It runs this Dart
package's built-in JSON-RPC/MCP regression fixtures for SDK and CLI
development.

Current scope:

- `inspect-server` connects to a live stdio or Streamable HTTP MCP server and
  reports handshake, implementation metadata, capabilities, ping, tools,
  resources, resource templates, prompts, completions, logging, tasks,
  notifications, Streamable HTTP sessions, and OAuth protected-resource
  discovery when those features are advertised or applicable. Optional probe
  config files let developers provide real tool arguments, resource URIs,
  prompt arguments, completion values, and task behavior.
- `inspect-client` runs a stdio test server that agent hosts and MCP clients can
  launch. It records initialize/initialized behavior, client capabilities, and
  whether the client discovers or calls the inspector's test primitives. It also
  actively probes advertised roots, sampling, and elicitation support.
- `trace` launches a stdio server command, forwards traffic between the real
  client and server, and writes a chronological report with raw frames, parsed
  JSON-RPC messages, methods, ids, stderr, and malformed-frame errors.
- `inspect`, `list-tools`, and `call-tool` remain lightweight live server
  inspection and smoke test commands.
- `conformance` is a built-in SDK/fixture regression gate for MCP
  2025-11-25-sensitive wire cases in this package.

This is a practical inspector and regression gate, not a formal certification
suite. It can catch common lifecycle, capability, primitive-shape, and client
handshake problems, but it does not prove full MCP spec compliance for a target.

Current MCP 2025-11-25 coverage:

| Area | Current CLI coverage |
| --- | --- |
| Base lifecycle and JSON-RPC | `inspect-server` verifies initialize, server info, capabilities, and ping on live targets. `inspect-client` verifies initialize-first, initialized notification, client info, capabilities, and well-formed observed JSON-RPC. `conformance` adds built-in malformed JSON-RPC, string id/token, pre-initialize, and protocol-version regression cases. |
| Transports | Live inspection supports stdio and Streamable HTTP targets. Streamable HTTP reports session/protocol metadata, probes GET without/bogus sessions, records Origin-header behavior, and attempts DELETE session termination. `trace` proxies stdio sessions. It does not yet run resumability or redelivery probes. |
| Server tools | `inspect-server` verifies advertised tools, `tools/list`, unique/spec-shaped names, object input schemas, object output schemas when present, and descriptions as warnings. Probe configs can call selected tools with developer-provided arguments and validate structured output against output schemas through the SDK client. `call-tool` can exercise one tool and returns non-zero on `isError`. It does not automatically invoke every ordinary tool. |
| Server resources | `inspect-server` verifies the resources capability, `resources/list`, `resources/templates/list`, unique resource URIs/templates, parseable URIs, non-empty names, first or configured `resources/read`, and subscribe/unsubscribe when advertised or requested. It does not yet auto-read every resource or trigger resource update notifications. |
| Server prompts | `inspect-server` verifies the prompts capability, `prompts/list`, unique prompt names, unique/non-empty argument names, and first or configured `prompts/get`. Interactive `inspect` can get a specified prompt. Live inspection does not yet auto-run `prompts/get` for every prompt or validate every prompt message content variant. |
| Server completion | `inspect-server` probes `completion/complete` when the server advertises completions and exposes a prompt argument that can be completed safely. |
| Client roots, sampling, and elicitation | `inspect-server` advertises roots, sampling, and form elicitation so live servers can request them. `inspect-client` actively sends `roots/list`, `sampling/createMessage`, and `elicitation/create` probes to clients that advertise those capabilities. |
| Logging, progress, and list-changed notifications | `inspect-server` calls `logging/setLevel` when logging is advertised, records server notifications, and checks observed progress notifications for numeric progress, valid tokens, and non-decreasing progress per token. `conformance` has a malformed progress-token case. The CLI does not yet trigger list-changed notifications itself. |
| Cancellation | Not actively inspected yet. |
| Authorization | Streamable HTTP inspection probes OAuth protected-resource metadata discovery at the endpoint-specific and root `.well-known` locations, records 401 `WWW-Authenticate` challenges, fetches authorization-server/OIDC metadata when advertised, and warns when PKCE S256 is missing. It does not complete token exchange without user-provided credentials. |
| Tasks | `inspect-server` records advertised tasks capabilities, calls `tasks/list` when advertised, exercises one task-augmented tool call, records created/status/result lifecycle messages, validates task result structured output when an output schema is present, and can run a configured task cancellation probe. It does not yet trigger every possible task status transition or task status notification. |
| 2025-11-25 metadata/schema updates | Tool name guidance is checked. Output schemas are validated for configured tool/task probes when structured output is available. Icons, titles, implementation descriptions, task execution metadata, elicitation URL mode, sampling tool loops, and full JSON Schema 2020-12 validation are preserved where the SDK models expose them but are not fully validated by live inspection yet. |

Future issue slices can add replay, credentialed auth flows, Streamable HTTP
resumability/redelivery checks, and raw-wire negative probes without splitting
the live inspection workflow into a separate validation command.

The CLI e2e suite runs these commands against Dart fixtures, official
TypeScript/Python SDK fixtures, a Streamable HTTP TypeScript server, the
published `@modelcontextprotocol/server-filesystem` package, the published
`mcp-server-time` Python package, and TypeScript/Python clients connected to the
`inspect-client` harness.

### Doctor

Run `mcp_dart doctor` in your project directory to check for configuration issues and verify that tools/resources/prompts are reachable.

```bash
mcp_dart doctor
```

### Inspect

Use `mcp_dart inspect` to interact with an MCP server by listing capabilities or executing tools, resources, and prompts.

**Local Project:**

Run inside an MCP Dart project directory:

```bash
# List all capabilities
mcp_dart inspect

# Execute a tool
mcp_dart inspect --tool add --json-args '{"a": 1, "b": 2}'

# Read a resource
mcp_dart inspect --resource manifest://app

# Get a prompt
mcp_dart inspect --prompt greeting --json-args '{"name": "World"}'
```

**External Server (via Command):**

Connect to any MCP server executable. Use `--` to separate the server command and arguments from `mcp_dart` flags:

```bash
# Using standard separator (Recommended)
mcp_dart inspect -- npx -y @modelcontextprotocol/server-filesystem /path/to/files

# Or using explicit flags
mcp_dart inspect -c npx -a "-y @modelcontextprotocol/server-filesystem /path/to/files"

# Pass environment variables
mcp_dart inspect --env API_KEY=secret -- python my_server.py
```

**External Server (via HTTP URL):**

Connect to an MCP server via Streamable HTTP:

```bash
mcp_dart inspect --url http://localhost:3000/mcp
```

**Options:**

- `--tool`: Name of a tool to execute.
- `--resource`: URI of a resource to read.
- `--prompt`: Name of a prompt to retrieve.
- `--json-args`: JSON arguments for the tool or prompt.
- `--url`: URL of the MCP server (Streamable HTTP).
- `--command` (`-c`): Executable command to start the server.
- `--server-args` (`-a`): Arguments to pass to the server command.
- `--env`: Environment variables in `KEY=VALUE` format.
- `--wait` (`-w`): Milliseconds to wait for notifications (defaults to 500ms for HTTP).

**Sampling Support:**

The CLI supports `sampling/createMessage` requests from the server (often used by tools like `summarize` that need an LLM). Currently, it returns a placeholder response to ensure tools complete successfully.

### Inspect Server

Use `inspect-server` when you need a structured live-observation report for an
MCP server.
It connects, completes initialization, pings the server, checks advertised
capabilities, and lists tools, resources, resource templates, and prompts when
the server advertises those capabilities. It also performs safe feature probes
for resource reads/subscriptions, prompt get, completions, logging, tasks,
notifications, Streamable HTTP sessions, and OAuth protected-resource metadata.

```bash
# Stdio TypeScript SDK server
mcp_dart inspect-server --json -- node dist/server.js --transport stdio

# Stdio Python SDK server
mcp_dart inspect-server -- python server.py

# Streamable HTTP server
mcp_dart inspect-server --json --url http://localhost:3000/mcp
```

Use `--probe-config` when the server needs real arguments or when you want to
exercise a specific primitive instead of the inspector's safe first item:

```json
{
  "tools": [
    {
      "name": "search",
      "arguments": { "query": "mcp" }
    }
  ],
  "resource": { "uri": "file:///tmp/example.txt", "subscribe": false },
  "prompt": {
    "name": "summarize",
    "arguments": { "topic": "MCP debugging" }
  },
  "completion": {
    "prompt": "summarize",
    "argument": "topic",
    "value": "M"
  },
  "task": {
    "tool": "long_running",
    "arguments": { "duration": 250 },
    "ttl": 60000,
    "cancel": false
  }
}
```

```bash
mcp_dart inspect-server --json --probe-config probes.json -- node server.js
```

`inspect-server` exits non-zero when a failing check is found. Warnings do not
fail by default; add `--strict` to make warnings fail CI too.

### Inspect Client

Use `inspect-client` as a temporary MCP server that a client or agent host
launches. Because stdout is reserved for JSON-RPC protocol traffic, pass
`--report` to write the inspection report to disk.

```bash
mcp_dart inspect-client --report /tmp/mcp-client-report.json
```

For clients that accept a server command, point them at the inspector:

```bash
node client.js \
  --server-command mcp_dart \
  --server-args "inspect-client --report /tmp/mcp-client-report.json"
```

The harness exposes an `echo` tool plus one resource and one prompt, then
records whether the client initialized correctly and exercised those primitives.
When the connecting client advertises roots, sampling, or elicitation, the
harness actively sends the matching server-initiated request and records whether
the client responds.

### Trace

Use `trace` when you need to debug the exact stdio traffic between an MCP client
or agent host and a real server. Configure the client to launch `mcp_dart trace`
instead of the server, then pass the real server command after `--`.

```bash
mcp_dart trace --report /tmp/mcp-trace.json -- node server.js --transport stdio
```

The proxy writes only MCP frames to stdout, forwards server stderr to stderr, and
writes the trace report out-of-band. The report includes raw lines, parsed
JSON-RPC messages, method counts, ids, timings, stderr, and parse errors.

### List Tools

Use `list-tools` when you need a scriptable inventory of a server's advertised
tools.

```bash
# TypeScript SDK server over stdio
mcp_dart list-tools -- npx -y @modelcontextprotocol/server-filesystem "$PWD"

# Python SDK server over stdio
mcp_dart list-tools -- python server.py

# Streamable HTTP endpoint
mcp_dart list-tools --url http://localhost:3000/mcp

# Machine-readable output
mcp_dart list-tools --json -- node dist/server.js --transport stdio
```

### Call Tool

Use `call-tool` to exercise one tool without writing a client.

```bash
mcp_dart call-tool echo --json-args '{"message":"hello"}' -- python server.py
mcp_dart call-tool add --json --json-args '{"a":2,"b":3}' -- node dist/server.js --transport stdio
mcp_dart call-tool search --url http://localhost:3000/mcp --json-args '{"q":"mcp"}'
```

`call-tool` exits non-zero when the MCP result is marked `isError`.

### Conformance

Run built-in fixture checks, MCP 2025-11-25 spec-critical checks, MCP
2026-07-28 RC stateless checks, and deterministic fuzz checks for protocol edge
cases in this Dart SDK/CLI package. The fixture suite covers JSON-RPC
malformed-message handling, string and integer request IDs, string and integer
progress tokens, fractional ID/token rejection, and advertised protocol-version
support. The spec suite covers raw-wire lifecycle, discovery, stateless
result/cache behavior, capability, elicitation, task-metadata, progress-token
dispatch, and negative cases.

This command is useful as a regression gate for the Dart SDK and CLI, but it is
not a live compliance scanner for arbitrary MCP servers or clients. For external
servers today, combine `inspect-server`, `inspect-client`, `inspect`,
`list-tools`, `call-tool`, and cross-SDK e2e tests with the target's own
protocol logs.

```bash
# Run all built-in fixture cases
mcp_dart conformance

# Run all stable non-fuzz suites
mcp_dart conformance --suite all

# Run only raw-wire spec cases
mcp_dart conformance --suite spec

# Run one case by exact name
mcp_dart conformance --case jsonrpc.preserves-string-response-id

# Run deterministic generated JSON-RPC fuzz cases
mcp_dart conformance --fuzz --iterations 64

# Emit machine-readable results for CI or scripts
mcp_dart conformance --json
```

### Serve

Runs the MCP server in the current directory.

```bash
mcp_dart serve
```

**Options:**

- `--transport` (`-t`): Transport type to use (`stdio` or `http`). Defaults to `stdio`.
- `--host`: Host for HTTP transport. Defaults to `0.0.0.0`.
- `--port` (`-p`): Port for HTTP transport. Defaults to `3000`.
- `--watch`: Restart the server on file changes.

### Update

Updates the CLI to the latest version.

```bash
mcp_dart update
```

For `dart pub global activate` installs, `update` delegates to pub. For
standalone GitHub release binaries, `update` downloads the newest matching
binary asset and replaces the current executable.

### Skills

Install a bundled MCP developer skill into your local Codex skill directory:

```bash
mcp_dart skills install
```

Install into a custom agent skill directory:

```bash
mcp_dart skills install --target ~/.codex/skills
```

Print the skill for another agent or repository workflow:

```bash
mcp_dart skills print
```

## Running Tests

To run the tests for this package:

```bash
dart test
```

## Release Validation

The CLI package lives under `packages/`, while the root SDK package excludes
that directory from its own pub archive. Run CLI publish validation from an
exported tree outside the monorepo git/.pubignore context:

```bash
dart run tool/validate_cli_publish.dart
```

Before the matching `mcp_dart` SDK dev package is published, this uses
`pubspec_overrides.yaml` so the CLI can validate against the local SDK checkout.
After publishing the SDK package, validate the CLI against the pub.dev SDK
version:

```bash
dart run tool/validate_cli_publish.dart --published-sdk
```

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this project.
