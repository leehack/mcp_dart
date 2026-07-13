# Python SDK 2026-07-28 RC Interop

This fixture verifies the MCP `2026-07-28` draft/RC path in both directions
against the official Python SDK `mcp==2.0.0b1` package. It is separate from the
stable Python fixture, which continues to cover the released 2025 protocol.

## Run

From the repository root:

```bash
python3 -m venv .dart_tool/python-2026-interop
.dart_tool/python-2026-interop/bin/python -m pip install \
  -r test/interop/python_2026_07_28_rc/requirements.txt
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_rc_interop.dart
```

The runner checks Python client -> Dart server negotiation, `tools/list`, and
`tools/call`, then checks Dart client -> Python server discovery, tool listing,
and tool execution. Both paths must negotiate `2026-07-28`.
