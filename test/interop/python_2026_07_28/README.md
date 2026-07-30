# Python SDK 2.0.0 Interop

This fixture tracks both directions against the official Python SDK
`mcp==2.0.0` and `mcp-types==2.0.0` packages. Each direction covers modern
Streamable HTTP with MCP `2026-07-28` and the published SDK's deprecated
HTTP+SSE compatibility APIs with MCP `2025-11-25`.

## Run

From the repository root:

```bash
python3 -m venv .dart_tool/python-2026-interop
.dart_tool/python-2026-interop/bin/python -m pip install \
  -r test/interop/python_2026_07_28/requirements.txt
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart \
  --direction=dart-to-python
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart \
  --direction=python-to-dart
```

The Dart client -> Python server direction checks discovery, tool listing, and
tool execution over Streamable HTTP, then initialization, tool listing, and a
tool call over legacy SSE. The reverse direction first sends an independent
anonymous raw `server/discover` request to the Dart server. That probe requires
MCP `2026-07-28` acceptance without `clientInfo`, no obsolete body
`serverInfo`, and canonical server identity in
`_meta["io.modelcontextprotocol/serverInfo"]`; the Python stable client then
negotiates MCP `2026-07-28`. Its legacy SSE client separately negotiates MCP
`2025-11-25` and completes the same public tool flow.
