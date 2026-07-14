# MCP 2025-11-25 Spec Coverage Matrix

The `McpProtocol.legacy` path retains the MCP `2025-11-25` client/server feature
set and negotiates `2025-06-18`, `2025-03-26`, `2024-11-05`, and `2024-10-07`
for older peers. This matrix maps high-risk `2025-11-25` requirements to
checked-in evidence. A row is `Verified` only when the repository has an
executable test or CI command for the behavior.

## Conformance Gate

Run the matrix-critical local gate from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.9 client \
  --command "dart run test/conformance/mcp_2026_07_28_rc_client.dart" \
  --suite all \
  --spec-version 2025-11-25

cd packages/mcp_dart_cli
dart pub get
dart run bin/mcp_dart.dart conformance --suite all --json
```

Despite its filename, `mcp_2026_07_28_rc_client.dart` is the dual-era official
client fixture. `--spec-version 2025-11-25` selects its initialization-era path.

Run the cross-SDK interop gate from the repository root:

```bash
cd test/interop/ts
npm ci
npm run build
cd ../../..
dart test -t interop
```

CI runs the official conformance gate, TypeScript interop suite, and full CLI
conformance gate. The CLI workflow also runs the CLI tests and conformance gate.
See the [2026-07-28 matrix](spec-coverage-2026-07-28-rc.md) for draft/RC gates.

## Matrix

| Spec area | Spec source | Requirement tracked here | Local coverage | Interop coverage | Conformance case or gap | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Lifecycle initialization ordering | [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle) | `initialize` is first, peers do not run normal operations before lifecycle readiness, clients do not attempt to cancel `initialize`, and `notifications/initialized` transitions the session into normal operation. | [`test/lifecycle_test.dart`](../test/lifecycle_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/lifecycle_client.ts`](../test/interop/ts/src/lifecycle_client.ts) | `lifecycle.rejects-pre-initialize-request`, `lifecycle.gates-until-initialized-notification`, `lifecycle.does-not-cancel-initialize` | Verified |
| Cancellation notifications | [Cancellation](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation) | `notifications/cancelled` preserves a string-or-integer JSON-RPC request ID and rejects payloads that omit or malform the ID. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | Covered by TypeScript interop cancellation flows. | `cancellation.requires-request-id` | Verified |
| Protocol version negotiation and HTTP header behavior | [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle), [Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Peers negotiate a supported initialization-era version and Streamable HTTP requests carry a valid `MCP-Protocol-Version` after initialization. | [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart) | Official 2025 server/client lifecycle and protocol-version scenarios. | Verified |
| Stable schema metadata and capabilities | [Schema reference](https://modelcontextprotocol.io/specification/2025-11-25/schema) | Stable model serializers preserve schema fields such as `Resource.size` and `Root._meta`, emit stable `icons` and annotation fields, and avoid non-stable server capability fields. | [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart) | Covered by TypeScript interop initialization and list/read flows. | Legacy singular `icon`, `ResourceAnnotations.title`, `ToolAnnotations.priority`, `ToolAnnotations.audience`, top-level server `elicitation`, and `tasks.listChanged` parse for compatibility but do not serialize on stable wire objects. | Verified |
| JSON-RPC responses and strict required fields | [Schema reference JSON-RPC](https://modelcontextprotocol.io/specification/2025-11-25/schema#jsonrpcmessage) | JSON-RPC response IDs preserve string-or-integer identity, successful responses require an `id`, error responses may omit it, request/notification envelopes do not mix `method` with response fields, required request params such as `tools/call.params` are not synthesized, and required result arrays are not silently synthesized when absent. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart) | Covered by TypeScript interop request/response flows. | `jsonrpc.preserves-string-response-id`, `jsonrpc.accepts-omitted-error-response-id`, `jsonrpc.rejects-method-response-envelope`, `tools-call.requires-params`; additional strict-array regression coverage lives in `test/mcp_2025_11_25_test.dart`. | Verified |
| Negotiated capability enforcement | [Lifecycle capability negotiation](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#capability-negotiation), [Sampling](https://modelcontextprotocol.io/specification/2025-11-25/client/sampling) | Requests that require an unadvertised feature are rejected before handler code observes them. | [`test/client/client_tool_validation_test.dart`](../test/client/client_tool_validation_test.dart), [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart) | `capabilities.rejects-unnegotiated-sampling-tools`, `capabilities.rejects-unnegotiated-sampling-context` | Verified |
| Tool schema root-object validation | [Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [Schema reference tools](https://modelcontextprotocol.io/specification/2025-11-25/schema#tool) | `Tool.inputSchema` and `Tool.outputSchema` serialize as object-root JSON Schema values and reject primitive root schemas at the wire boundary. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart) | Covered by tool-list and tool-call interop tests. | Root object validation is enforced in `Tool.fromJson()` and `Tool.toJson()` while preserving `JsonSchema`-typed source compatibility. | Verified |
| Elicitation form/URL variant validation | [Elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation) | `elicitation/create` is treated as a discriminated form/URL shape, form schemas use object-root primitive property schemas, URL-required errors contain URL-mode elicitation requests, and invalid mixed payloads are rejected. | [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`test/client/client_elicitation_defaults_test.dart`](../test/client/client_elicitation_defaults_test.dart), [`test/server/server_validation_test.dart`](../test/server/server_validation_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart) | `elicitation.rejects-invalid-form-url-union` | Verified |
| Task metadata and related-task propagation | [Schema reference tasks](https://modelcontextprotocol.io/specification/2025-11-25/schema#tasks) | Task-augmented requests require negotiated task support and related-task metadata is preserved only where task association is valid. | [`test/server/tasks_test.dart`](../test/server/tasks_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/shared/protocol_task_handlers_test.dart`](../test/shared/protocol_task_handlers_test.dart), [`test/server/tasks_components_test.dart`](../test/server/tasks_components_test.dart), [`test/server/mcp_test.dart`](../test/server/mcp_test.dart) | [`test/interop/dart_client_with_ts_server_task_test.dart`](../test/interop/dart_client_with_ts_server_task_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/client.ts`](../test/interop/ts/src/client.ts) | `tasks.strips-unnegotiated-related-task-metadata`; SDK-generated related responses preserve the source task identity. | Verified |
| Resource read error semantics | [Resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources) | Missing resources return the stable resource-not-found error instead of an ambiguous empty `contents` array. | [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart) | TypeScript interop covers successful reads. | Stable missing-resource regression tests. | Verified |
| Progress token preservation and progress stream validation | [Progress](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress) | Progress tokens preserve string-or-integer wire shape, malformed token shapes fail at decode boundaries, and progress values should advance monotonically for a request. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/shared/progress_test.dart`](../test/shared/progress_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | `jsonrpc.preserves-string-progress-token`, `progress.rejects-malformed-progress-token`; `RequestHandlerExtra.sendProgress` rejects repeated/decreasing progress before sending invalid notifications. | Verified |
| Streamable HTTP sessions, stale recovery, SSE replay, and batch rejection | [Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Session IDs, stale-session retry, initial SSE event IDs, `Last-Event-ID` replay, protocol-version headers, and JSON-RPC batch rejection are covered for stateful Streamable HTTP. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart) | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/replay_client.ts`](../test/interop/ts/src/replay_client.ts) | Official 2025 Streamable HTTP scenarios plus local stale-session and replay tests. | Verified |
| Auth/security deployment behavior | [Authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization), [Transports security notes](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning) | OAuth, DNS rebinding, Origin/Host restrictions, and production deployment toggles are covered by executable harnesses where practical. Authorization-code clients require PKCE `S256`, callback state, and explicit trust for cross-origin OAuth endpoints. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/), [`doc/transports.md`](transports.md) | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/oauth_client.ts`](../test/interop/ts/src/oauth_client.ts) | Covers safe Host/Origin scenarios, bearer gating, protected-resource discovery, PKCE S256, state validation, trusted-origin policy, resource-bound exchange, insufficient-scope upscoping, and bearer reconnect. | Verified |

## Stable Conformance Case Names

The CLI exposes exact names so CI and downstream SDK checks can select one case
without relying on output text:

- `jsonrpc.rejects-invalid-version`
- `jsonrpc.rejects-malformed-message`
- `jsonrpc.rejects-non-string-method`
- `jsonrpc.rejects-result-error-response`
- `jsonrpc.rejects-method-response-envelope`
- `jsonrpc.rejects-malformed-error-object`
- `jsonrpc.rejects-null-error-response-id`
- `jsonrpc.accepts-omitted-error-response-id`
- `jsonrpc.rejects-null-params-member`
- `tools-call.requires-params`
- `jsonrpc.preserves-string-response-id`
- `jsonrpc.preserves-integer-response-id`
- `jsonrpc.preserves-string-progress-token`
- `jsonrpc.preserves-integer-progress-token`
- `jsonrpc.rejects-fractional-ids-and-progress-tokens`
- `lifecycle.rejects-pre-initialize-request`
- `lifecycle.gates-until-initialized-notification`
- `lifecycle.does-not-cancel-initialize`
- `cancellation.requires-request-id`
- `capabilities.rejects-unnegotiated-sampling-tools`
- `capabilities.rejects-unnegotiated-sampling-context`
- `capabilities.unadvertised-peer-methods-use-method-not-found`
- `capabilities.task-scoped-peer-methods-use-method-not-found`
- `elicitation.rejects-invalid-form-url-union`
- `tasks.strips-unnegotiated-related-task-metadata`
- `progress.rejects-malformed-progress-token`
- `progress.dispatches-integer-progress-token`

The CLI also includes 2026 draft/RC cases. They are scoped in the
[2026-07-28 coverage matrix](spec-coverage-2026-07-28-rc.md), not here.

Use exact-case filtering when diagnosing one row:

```bash
cd packages/mcp_dart_cli
dart run bin/mcp_dart.dart conformance --suite all --case lifecycle.rejects-pre-initialize-request
```
