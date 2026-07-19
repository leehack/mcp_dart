# Python SDK 2026-07-28 Interop

This fixture tracks both MCP `2026-07-28` directions against the official
Python SDK `mcp==2.0.0b1` package: Dart client -> Python server remains a
required compatible path, while Python client -> Dart server records the
package's pre-spec-#3002 discovery gap. It is separate from the stable Python
fixture, which continues to cover the released MCP 2025-11-25 specification.

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
  --direction=python-to-dart \
  --expect-published-python-client-gap
```

The Dart client -> Python server direction remains required and checks
discovery, tool listing, and tool execution. The published Python beta client
predates spec PR #3002 and requires obsolete body `serverInfo`, so the reverse
direction asserts its exact 2026 -> 2025 fallback as a temporary expected gap.
The expected-gap command fails if the beta starts passing or fails differently.
