# Anthropic MCP Client Example

This example demonstrates how to connect Anthropic's current Messages API to
an MCP server with `mcp_dart`. It uses the community-maintained
[`anthropic_sdk_dart`](https://pub.dev/packages/anthropic_sdk_dart) package.

The client preserves each assistant tool-use turn and returns MCP results as
correlated Anthropic `tool_result` blocks. Multiple tool calls in one assistant
turn and multiple tool-use rounds are supported.

This example adopts `anthropic_sdk_dart` 11's default Claude API version
`2026-10-21` (previously `2023-06-01`), without a legacy API-version override.
Its requests do not use the removed sampling parameters or unsupported
assistant document inputs. See the
[SDK migration guide](https://github.com/davidmigloz/ai_clients_dart/blob/anthropic_sdk_dart-v11.0.0/packages/anthropic_sdk_dart/MIGRATION.md)
before adapting other request shapes. The SDK upgrade also adds the transitive
`crypto` dependency (`^3.0.8`); this example adds no direct dependency.

Unknown Anthropic stop reasons fail the query with the original wire value;
partial text is not returned as success, and accompanying tool calls are not
approved or executed.

Its `McpClient` uses the SDK's default dual-era compatibility profile: it
prefers MCP 2026-07-28 and falls back to the MCP 2025-11-25 initialization flow
for legacy servers.

The CLI asks for approval before every Anthropic-requested tool call and
rejects names the MCP server did not advertise. Only `y` or `yes` approves a
call; every other answer, including end-of-input, declines it. Programmatic
users must pass a `toolApprover` callback to `AnthropicMcpClient`; without one,
calls are denied. Connect only to MCP servers you trust, inspect tool arguments
before approving them, and add application-specific authorization before
adapting this example for production. The spawned MCP process receives a copy
of the parent environment with `ANTHROPIC_API_KEY` and `ANTHROPIC_MODEL`
removed.

Anthropic requires each tool's `input_schema` root and each generated tool-use
`input` to be a JSON object. This adapter rejects MCP tools with non-object
input-schema roots instead of weakening or casting their schemas.

The client refreshes the complete paginated tool list before each user query,
then keeps that snapshot fixed across the query's tool-use rounds. MCP metadata
and extension fields are excluded from provider requests.

## Data Sent to Anthropic

Anthropic receives:

- Each user query.
- Every advertised MCP tool name or alias, description, and input schema.
- Anthropic-generated function names and arguments, including arguments
  approved for local execution.
- Approved MCP tool results, including supported text, images, and structured
  content.
- Correlated decline messages and MCP error strings.

MCP `_meta`, content annotations, and extension fields are not forwarded. The
Anthropic API key is sent only to Anthropic and is not exposed to the spawned
MCP server. Review Anthropic's
[API and data-retention guidance](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)
before using sensitive queries, schemas, arguments, or results.

## How to run

This example requires Dart 3.12 or later, matching the minimum required by
`anthropic_sdk_dart` 10 and 11. This example-only requirement does not change
the core SDK's Dart 3.4 minimum or the CLI package's Dart 3.12 minimum.

First add the Anthropic API key to your environment variables:

```bash
export ANTHROPIC_API_KEY=your_api_key
```

The example defaults to
[`claude-sonnet-5`](https://platform.claude.com/docs/en/about-claude/models/overview)
with adaptive thinking disabled to keep this basic tool bridge predictable.
Override it without changing the source when you need another compatible
model:

```bash
export ANTHROPIC_MODEL=claude-sonnet-5
```

Then, you can run the example using either AOT (Ahead of Time) or JIT (Just in Time) compilation.

### JIT

To run the example in JIT mode, use the following command:

```bash
dart run bin/main.dart dart ../server_stdio.dart
```

### AOT

To run the example in AOT mode, first compile the Anthropic client:

```bash
dart compile exe bin/main.dart -o ./app
```

Then run that compiled client and point it at the Dart stdio server:

```bash
./app dart ../server_stdio.dart
```
