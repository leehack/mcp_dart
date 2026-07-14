# MCP 2026-07-28 RC core example

This pair requires the `2026-07-28` protocol instead of falling back to legacy
initialization. The client starts the server over stdio, so one command runs the
complete flow:

```bash
dart pub get
dart run example/mcp_2026_07_28/client.dart
```

Run both commands from the repository root. A successful run ends with output
like:

```text
Negotiated protocol: 2026-07-28
Subscription acknowledged: mcp://greeting/status
Subscription update: ready for a greeting
Subscription closed cleanly.
Tools: personalized_greeting
Input requested: What name should the greeting use?
Structured result: Hello, Ada!
```

It demonstrates:

- `server/discover` negotiation with `McpProtocol.require2026`;
- per-request client identity, capabilities, and protocol metadata;
- `subscriptions/listen` acknowledgment, correlated update, and graceful close;
- `InputRequiredResult` with automatic client fulfillment and retry;
- opaque `requestState` preservation across the retry;
- explicit accept, decline, and cancel handling; and
- a string-root output schema and structured tool result.

The hard-coded elicitation response stands in for a host UI. Replace
`client.onElicitRequest` with real user interaction in an application.

This example covers the 2026 core protocol. Tasks and MCP Apps are optional MCP
extensions; see the [examples guide](../../doc/examples.md) for MCP Apps
examples and links to the Tasks-extension API guides.
