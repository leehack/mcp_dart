# Python SDK 2026-07-28 Interop

This fixture verifies the MCP `2026-07-28` path in both directions
against the official Python SDK `mcp==2.0.0b1` package. It is separate from the
stable Python fixture, which continues to cover the released MCP 2025-11-25
specification.

## Run

From the repository root:

```bash
python3 -m venv .dart_tool/python-2026-interop
.dart_tool/python-2026-interop/bin/python -m pip install \
  -r test/interop/python_2026_07_28/requirements.txt
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart
```

The runner checks Python client -> Dart server negotiation, `tools/list`, and
`tools/call`, then checks Dart client -> Python server discovery, tool listing,
and tool execution. Both paths must negotiate MCP 2026-07-28.
