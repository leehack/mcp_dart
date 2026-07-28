# Python SDK 2026-07-28 Interop

This fixture tracks both MCP `2026-07-28` directions against the official
Python SDK `mcp==2.0.0` and `mcp-types==2.0.0` packages. Both Dart
client -> Python server and Python client -> Dart server are required compatible
paths. This fixture is separate from the stable Python fixture, which continues
to cover the released MCP 2025-11-25 specification.

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
tool execution. The reverse direction first sends an independent anonymous raw
`server/discover` request to the Dart server. That probe requires MCP
`2026-07-28` acceptance without `clientInfo`, no obsolete body `serverInfo`,
and canonical server identity in
`_meta["io.modelcontextprotocol/serverInfo"]`; the Python stable client must
then negotiate MCP `2026-07-28` and complete the scenario.
