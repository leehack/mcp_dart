# Examples

Choose an example by protocol profile:

- **Strict MCP 2026-07-28:**
  [`mcp_2026_07_28/`](mcp_2026_07_28/) demonstrates `server/discover`,
  `subscriptions/listen`, `input_required`, and non-object structured output.
- **Default dual-era:** [`server_stdio.dart`](server_stdio.dart) with
  [`client_stdio.dart`](client_stdio.dart), or
  [`streamable_https/`](streamable_https/), prefers 2026 and retains legacy
  fallback.
- **Representative MCP 2025 / legacy:**
  [`simple_task_interactive_server.dart`](simple_task_interactive_server.dart),
  [`elicitation_http_server.dart`](elicitation_http_server.dart), and
  [`server_sse.dart`](server_sse.dart) intentionally demonstrate retained
  initialization-era behavior.
- **Optional extensions:** [`mcp_apps_helpers_server.dart`](mcp_apps_helpers_server.dart)
  and [`mcp_apps_metadata_server.dart`](mcp_apps_metadata_server.dart) cover MCP
  Apps metadata separately from core protocol support.

See the complete [examples guide](../doc/examples.md) for setup instructions,
authentication examples, Flutter clients, and integration recipes.
