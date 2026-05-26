# MCP 2025-11-25 Spec Coverage Matrix

This matrix maps high-risk MCP 2025-11-25 requirements to checked-in
`mcp_dart` coverage. It is intentionally conservative: a row is marked
`Verified` only when the repository has executable tests or a CI command for
the behavior.

## Conformance Gate

Run the matrix-critical local gate from the repository root:

```bash
cd packages/mcp_dart_cli
dart pub get
dart run bin/mcp_dart.dart conformance --suite spec --json
```

Run the cross-SDK interop gate from the repository root:

```bash
cd test/interop/ts
npm ci
npm run build
cd ../../..
dart test -t interop
```

CI runs both gates: the core workflow runs the TypeScript interop suite and the
CLI spec conformance gate, while the CLI workflow runs the conformance gate with
the CLI test suite.

## Matrix

| Spec area | Spec source | Requirement tracked here | Local coverage | Interop coverage | Conformance case or gap | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Lifecycle initialization ordering | [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle) | `initialize` is first, peers do not run normal operations before lifecycle readiness, and `notifications/initialized` transitions the session into normal operation. | [`test/lifecycle_test.dart`](../test/lifecycle_test.dart) | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/lifecycle_client.ts`](../test/interop/ts/src/lifecycle_client.ts) | `lifecycle.rejects-pre-initialize-request` | Verified |
| Protocol version negotiation and HTTP header behavior | [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle), [Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Peers negotiate a supported protocol version, and Streamable HTTP requests carry valid `MCP-Protocol-Version` after initialization. | [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart) | `protocol-version.advertises-latest-2025-11-25` | Verified |
| Negotiated capability enforcement | [Lifecycle capability negotiation](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#capability-negotiation), [Sampling](https://modelcontextprotocol.io/specification/2025-11-25/client/sampling) | Requests that require an unadvertised feature are rejected before handler code observes them. | [`test/client/client_tool_validation_test.dart`](../test/client/client_tool_validation_test.dart), [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart) | `capabilities.rejects-unnegotiated-sampling-tools` | Verified |
| Elicitation form/URL variant validation | [Elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation) | `elicitation/create` is treated as a discriminated form/URL shape and invalid mixed payloads are rejected. | [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`test/client/client_elicitation_defaults_test.dart`](../test/client/client_elicitation_defaults_test.dart), [`test/server/server_validation_test.dart`](../test/server/server_validation_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart) | `elicitation.rejects-invalid-form-url-union` | Verified |
| Task metadata and related-task propagation | [Schema reference tasks](https://modelcontextprotocol.io/specification/2025-11-25/schema#tasks) | Task-augmented requests require negotiated task support, and related-task metadata is preserved only where task association is valid. | [`test/server/tasks_test.dart`](../test/server/tasks_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/shared/protocol_task_handlers_test.dart`](../test/shared/protocol_task_handlers_test.dart), [`test/server/tasks_components_test.dart`](../test/server/tasks_components_test.dart), [`test/server/mcp_test.dart`](../test/server/mcp_test.dart) | [`test/interop/dart_client_with_ts_server_task_test.dart`](../test/interop/dart_client_with_ts_server_task_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/client.ts`](../test/interop/ts/src/client.ts) | `tasks.strips-unnegotiated-related-task-metadata`; SDK-generated related responses and `tasks/result` overwrite reserved related-task metadata from the source task id while preserving unrelated handler metadata. | Verified |
| Progress token preservation and progress stream validation | [Progress](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress) | Progress tokens preserve string-or-integer wire shape, malformed token shapes fail at decode boundaries, and progress values should advance monotonically for a request. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/shared/progress_test.dart`](../test/shared/progress_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | `jsonrpc.preserves-string-progress-token`, `progress.rejects-malformed-progress-token`; `RequestHandlerExtra.sendProgress` rejects repeated/decreasing progress before sending invalid notifications. | Verified |
| Streamable HTTP sessions, stale recovery, SSE replay, and batch rejection | [Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Session IDs, stale-session retry, `Last-Event-ID` replay, protocol-version headers, and JSON-RPC batch rejection follow Streamable HTTP semantics. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/replay_client.ts`](../test/interop/ts/src/replay_client.ts) | Covered by `dart test -t interop` and unit tests; no separate CLI raw-wire case yet because this requires HTTP server fixtures. | Verified |
| Auth/security deployment behavior | [Authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization), [Transports security notes](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning) | OAuth, DNS rebinding, Origin/Host restrictions, and production deployment toggles are covered by executable harnesses where practical. | [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/), [`doc/transports.md`](transports.md) | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/oauth_client.ts`](../test/interop/ts/src/oauth_client.ts) | Safe local-development and production Host/Origin scenarios, bearer-token gating, compatibility-toggle trade-offs, OAuth protected-resource discovery, PKCE S256 authorization redirect, resource-bound token exchange, and bearer reconnect are covered by tests. | Verified |

## Stable Conformance Case Names

The CLI exposes exact names so CI and downstream SDK checks can select one case
without relying on output text:

- `jsonrpc.rejects-invalid-version`
- `jsonrpc.rejects-malformed-message`
- `jsonrpc.preserves-string-response-id`
- `jsonrpc.preserves-string-progress-token`
- `protocol-version.advertises-latest-2025-11-25`
- `lifecycle.rejects-pre-initialize-request`
- `capabilities.rejects-unnegotiated-sampling-tools`
- `elicitation.rejects-invalid-form-url-union`
- `tasks.strips-unnegotiated-related-task-metadata`
- `progress.rejects-malformed-progress-token`

Use exact-case filtering when diagnosing one row:

```bash
cd packages/mcp_dart_cli
dart run bin/mcp_dart.dart conformance --suite spec --case lifecycle.rejects-pre-initialize-request
```

## Known Gaps

- [#96](https://github.com/leehack/mcp_dart/issues/96): broader CLI debugging
  commands such as replay/proxy/validate flows.
