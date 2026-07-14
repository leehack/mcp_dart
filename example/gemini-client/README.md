# Gemini Client Example

This example connects Gemini's current
[Interactions REST API](https://ai.google.dev/api/interactions-api) directly to
an MCP server using `mcp_dart`. It uses `package:http`; it does not depend on the
`google_generative_ai` Dart package, which Google lists as
[not actively maintained](https://ai.google.dev/gemini-api/docs/libraries#legacy-libraries-and-migration).

The adapter preserves each interaction with `previous_interaction_id`, executes
parallel and sequential MCP tool calls, and returns every result with the exact
Gemini function-call `id` and `name` as `call_id` and `name`. Tool declarations
are refreshed once before each user query; every `tools/list` page is captured,
and that fixed snapshot is included on each interaction round. MCP names that
do not fit Gemini's function-name rules are exposed through deterministic,
collision-safe aliases and mapped back before the MCP call runs.

The MCP client uses the SDK's default dual-era compatibility profile. It
prefers MCP `2026-07-28` stateless discovery and falls back to the
`2025-11-25` and earlier supported initialization versions for older servers.
The example does not force either protocol generation.

The CLI asks for approval before every Gemini-requested tool call and rejects
names the MCP server did not advertise. Only `y` or `yes` approves a call; all
other answers, including end-of-input, decline it. Programmatic users must pass
a `toolApprover` callback to `GoogleMcpClient`; without one, calls are denied.
Connect only to MCP servers you trust, inspect arguments before approving, and
add application-specific authorization before adapting this demo for
production. The spawned MCP process receives a copy of the parent environment
with every case variant of `GEMINI_API_KEY` and `GEMINI_MODEL` removed. Its
stderr is inherited so output is continuously drained and remains visible.
Server-controlled tool names are JSON-escaped in terminal and status output.

MCP tool input schemas must have an object root, matching Gemini's function
argument shape. Nested properties may use objects, strings and string enums,
numbers, integers, booleans, and arrays. The adapter also preserves object
`required` fields and emits raw JSON Schema maps for the REST API.

Boolean JSON Schemas, union types, `$ref`, schema combinators, and unsupported
validation keywords are rejected instead of being silently weakened. If a
server advertises one of those schemas, adapt it to this example's supported
subset before using it.

MCP text and Gemini-supported image tool results are forwarded as native
Gemini function-result content. Structured MCP results are preserved as native
objects or strings when possible. MCP metadata and extension fields are never
sent to Gemini. Other MCP content types fail closed instead of being silently
discarded. Every MCP error except a closed connection is returned to Gemini
with its code, message, and original function-call correlation. A closed
connection and non-MCP failures still stop the request.

## Data Sent to Gemini

The example uses `store: true`. Gemini receives or retains:

- Each user query.
- Every advertised MCP tool name or alias, description, and input schema on
  every interaction.
- Gemini-generated function names and arguments. Approved arguments are passed
  locally to the MCP server and remain associated with the stored interaction;
  the follow-up does not duplicate them.
- Approved MCP tool results, including supported text, images, and structured
  content.
- Correlated decline messages and MCP error strings containing the error code
  and message.

MCP `_meta`, content annotations, and extension fields are not forwarded. The
Gemini API key is sent only to Google's API as an authentication header and is
not exposed to the spawned MCP server. Review Google's
[data retention guidance](https://ai.google.dev/gemini-api/terms) before using
the example with sensitive queries, schemas, arguments, or results.

## Requirements

- Dart 3.7.2 or later

## Run

Create an API key in [AI Studio](https://aistudio.google.com/apikey), then set:

```bash
export GEMINI_API_KEY=your_api_key
```

The default model is `gemini-3.5-flash`. To override it:

```bash
export GEMINI_MODEL=gemini-3.5-flash
```

Stored interactions let the example continue tool-call rounds with
`previous_interaction_id`.

### JIT

```bash
dart run bin/main.dart dart ../server_stdio.dart
```

### AOT

```bash
dart compile exe bin/main.dart -o ./gemini_app
./gemini_app dart ../server_stdio.dart
```
