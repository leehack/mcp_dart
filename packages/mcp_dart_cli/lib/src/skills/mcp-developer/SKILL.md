---
name: mcp-developer
description: Use when building, testing, debugging, or reviewing Model Context Protocol servers, clients, transports, tools, resources, prompts, and agent host configuration.
---

# MCP Developer

Use this skill when the work involves MCP protocol behavior, cross-SDK interop, server/client debugging, or host configuration.

## Workflow

1. Identify the transport first: stdio, Streamable HTTP, SSE, or a host-specific adapter.
2. Preserve wire-level MCP semantics. Keep JSON-RPC ids, method names, capability flags, metadata, and error codes in their original spec-compatible shape.
3. Check advertised capabilities before calling capability-specific methods.
4. Reproduce with a protocol-level tool before editing app code:
   - `mcp_dart inspect-server --json -- <server-command> ...`
   - Configure a client/agent host to launch `mcp_dart inspect-client --report /tmp/mcp-client-report.json`
   - Configure a client/agent host to launch `mcp_dart trace --report /tmp/mcp-trace.json -- <real-server-command> ...`
   - `mcp_dart list-tools -- <server-command> ...`
   - `mcp_dart call-tool <tool> --json-args '{"key":"value"}' -- <server-command> ...`
   - `mcp_dart inspect --url http://localhost:3000/mcp`
5. Use `--probe-config` with `inspect-server` when a server needs real tool arguments, resource URIs, prompt arguments, completion values, or task behavior. Keep destructive app actions out of default probes.
6. Treat `inspect-server`, `inspect-client`, and `trace` as the live debugging workflow. They return protocol checks or traffic evidence for real targets; there is no separate live validation command to prefer.
7. If changing this Dart SDK/CLI package itself, also run `mcp_dart conformance --suite all --json` for the built-in protocol regression fixtures.
8. For cross-language issues, test at least one non-Dart peer. Prefer the official TypeScript or Python MCP SDK when a reproduction can be made small, and use published servers such as filesystem/time when the bug depends on real package behavior.
9. When changing protocol behavior, add regression coverage for the raw wire shape or interop edge case, not only a convenience API test.

## Host Configuration Checks

- Confirm the host launches the exact command and arguments you tested manually.
- Keep secrets in environment variables or host secret stores, not generated config files.
- Avoid printing diagnostic text to stdout for stdio servers; stdout is reserved for JSON-RPC frames.
- Use `inspect-client --report <path>` for agent hosts or clients that need a disposable MCP server to connect to.
- Record the MCP protocol version, SDK/package version, and transport in issue notes.

## Release And Install Checks

- If the CLI is needed on machines without Dart, use the GitHub release binary.
- Use `mcp_dart update` for normal upgrades. For manual installs, rerun the installer command against the same install directory.
- Before recommending a release, verify `dart analyze`, focused tests, and any TypeScript/Python interop smoke tests affected by the change.
