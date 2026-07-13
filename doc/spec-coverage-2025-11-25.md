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
dart run bin/mcp_dart.dart conformance --suite all --json
```

Run the cross-SDK interop gate from the repository root:

```bash
cd test/interop/ts
npm ci
npm run build
cd ../../..
dart test -t interop
```

For MCP `2026-07-28` draft/RC or final release audits, also run the upstream
machine-readable example corpus through the checked-in typed parsers after
extracting the upstream `modelcontextprotocol` archive:

```bash
dart run tool/spec_example_audit.dart /path/to/modelcontextprotocol/schema/draft/examples
```

CI runs both gates: the core workflow runs the TypeScript interop suite and the
full CLI conformance gate, while the CLI workflow runs the conformance gate with
the CLI test suite.

## Matrix

| Spec area | Spec source | Requirement tracked here | Local coverage | Interop coverage | Conformance case or gap | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Lifecycle initialization ordering | [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle) | `initialize` is first, peers do not run normal operations before lifecycle readiness, clients do not attempt to cancel `initialize`, and `notifications/initialized` transitions the session into normal operation. | [`test/lifecycle_test.dart`](../test/lifecycle_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/lifecycle_client.ts`](../test/interop/ts/src/lifecycle_client.ts) | `lifecycle.rejects-pre-initialize-request`, `lifecycle.gates-until-initialized-notification`, `lifecycle.does-not-cancel-initialize` | Verified |
| Cancellation notifications | [Cancellation](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation) | `notifications/cancelled` preserves a string-or-integer JSON-RPC request ID and rejects payloads that omit or malform the ID; task cancellation uses `tasks/cancel` rather than cancellation notifications. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | Covered by TypeScript interop cancellation and task flows where applicable. | `cancellation.requires-request-id`; task cancellation coverage lives in `tasks-extension.task-store-uses-extension-result-shapes`. | Verified |
| Protocol version negotiation and HTTP header behavior | [Lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle), [Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [Draft lifecycle](https://modelcontextprotocol.io/specification/draft/basic/lifecycle) | Peers negotiate a supported protocol version, Streamable HTTP requests carry valid `MCP-Protocol-Version` after initialization, draft stateless requests include protocol, client identity, client capabilities, method, name, and parameter routing headers while omitting stable-only capability fields removed from the draft, and draft HTTP clients inspect modern JSON-RPC `400` error bodies before deciding whether to fall back to legacy `initialize`. | [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart) | `protocol-version.advertises-latest-2026-07-28`, `stateless.requires-complete-request-meta`, `protocol-version.http-modern-400-retries-discovery`, `capabilities.http-modern-400-does-not-fallback`, `stateless-http.requires-routing-headers`, `stateless-http.validates-parameter-header-values`, `stateless-http.encodes-parameter-header-values` | Verified |
| Stable schema metadata and capabilities | [Schema reference](https://modelcontextprotocol.io/specification/2025-11-25/schema) | Stable model serializers preserve schema fields such as `Resource.size` and `Root._meta`, emit stable `icons` and annotation fields, and avoid non-stable server capability fields. | [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart) | Covered by TypeScript interop initialization and list/read flows. | Legacy singular `icon`, `ResourceAnnotations.title`, `ToolAnnotations.priority`, `ToolAnnotations.audience`, top-level server `elicitation`, and `tasks.listChanged` parse for compatibility but do not serialize on stable wire objects. | Verified |
| JSON-RPC responses and strict required fields | [Schema reference JSON-RPC](https://modelcontextprotocol.io/specification/2025-11-25/schema#jsonrpcmessage) | JSON-RPC response IDs preserve string-or-integer identity, successful responses require an `id`, error responses may omit it, request/notification envelopes do not mix `method` with response fields, required request params such as `tools/call.params` are not synthesized, and required result arrays are not silently synthesized when absent. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart) | Covered by TypeScript interop request/response flows. | `jsonrpc.preserves-string-response-id`, `jsonrpc.accepts-omitted-error-response-id`, `jsonrpc.rejects-method-response-envelope`, `tools-call.requires-params`; additional strict-array regression coverage lives in `test/mcp_2025_11_25_test.dart`. | Verified |
| Negotiated capability enforcement | [Lifecycle capability negotiation](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#capability-negotiation), [Sampling](https://modelcontextprotocol.io/specification/2025-11-25/client/sampling), [Draft MethodNotFoundError](https://modelcontextprotocol.io/specification/draft/schema#methodnotfounderror) | Requests that require an unadvertised feature are rejected before handler code observes them, and unadvertised peer method capabilities surface `MethodNotFound` (`-32601`). | [`test/client/client_tool_validation_test.dart`](../test/client/client_tool_validation_test.dart), [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart) | `capabilities.rejects-unnegotiated-sampling-tools`, `capabilities.rejects-unnegotiated-sampling-context`; `capabilities.unadvertised-peer-methods-use-method-not-found` | Verified |
| Tool schema root-object validation | [Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [Schema reference tools](https://modelcontextprotocol.io/specification/2025-11-25/schema#tool) | `Tool.inputSchema` and `Tool.outputSchema` serialize as object-root JSON Schema values and reject primitive root schemas at the wire boundary. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart) | Covered by tool-list and tool-call interop tests. | Root object validation is enforced in `Tool.fromJson()` and `Tool.toJson()` while preserving `JsonSchema`-typed source compatibility. | Verified |
| Elicitation form/URL variant validation | [Elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation) | `elicitation/create` is treated as a discriminated form/URL shape, form schemas use object-root primitive property schemas, URL-required errors contain URL-mode elicitation requests, and invalid mixed payloads are rejected. | [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`test/client/client_elicitation_defaults_test.dart`](../test/client/client_elicitation_defaults_test.dart), [`test/server/server_validation_test.dart`](../test/server/server_validation_test.dart), [`test/mcp_2025_11_25_test.dart`](../test/mcp_2025_11_25_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart) | `elicitation.rejects-invalid-form-url-union` | Verified |
| Task metadata and related-task propagation | [Schema reference tasks](https://modelcontextprotocol.io/specification/2025-11-25/schema#tasks) | Task-augmented requests require negotiated task support, related-task metadata is preserved only where task association is valid, and clients do not emit legacy task augmentation on 2026 stateless requests where the schema removed it. | [`test/server/tasks_test.dart`](../test/server/tasks_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/shared/protocol_task_handlers_test.dart`](../test/shared/protocol_task_handlers_test.dart), [`test/server/tasks_components_test.dart`](../test/server/tasks_components_test.dart), [`test/server/mcp_test.dart`](../test/server/mcp_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | [`test/interop/dart_client_with_ts_server_task_test.dart`](../test/interop/dart_client_with_ts_server_task_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/client.ts`](../test/interop/ts/src/client.ts) | `tasks.strips-unnegotiated-related-task-metadata`, `stateless-client.rejects-legacy-task-options`; SDK-generated related responses and `tasks/result` overwrite reserved related-task metadata from the source task id while preserving unrelated handler metadata. | Verified |
| Draft cacheable result and list stability | [Draft caching](https://modelcontextprotocol.io/specification/draft/server/utilities/caching), [Draft tools](https://modelcontextprotocol.io/specification/draft/server/tools) | Stateless `tools/list`, `prompts/list`, `resources/list`, `resources/templates/list`, and `resources/read` cacheable results include `resultType`, `ttlMs`, and `cacheScope`; `tools/list` results are deterministic for client-side caching and omit stable-only `Tool.execution` metadata removed from the draft schema. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Covered by stateless conformance until a released 2026 interop fixture is available. | `stateless.adds-result-type-and-cache-defaults`, `tools-list.stateless-returns-deterministic-order`, `tools-list.stateless-omits-legacy-execution` | Verified |
| Resource read error semantics | [Resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources), [Draft resources](https://modelcontextprotocol.io/specification/draft/server/resources) | Missing resources return the current stable resource-not-found code for legacy requests and draft `InvalidParams` (`-32602`) for 2026 stateless requests, without returning an ambiguous empty `contents` array. | [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Covered by TypeScript interop resource read flows for successful reads. | `resources.missing-resource-error-code-by-version` | Verified |
| Draft request-scoped logging | [Draft logging](https://modelcontextprotocol.io/specification/draft/server/utilities/logging), [Draft schema request metadata](https://modelcontextprotocol.io/specification/draft/schema#requestmetaobject) | Stateless requests use `io.modelcontextprotocol/logLevel` as the per-request logging opt-in, removed `logging/setLevel` is rejected, and servers do not emit `notifications/message` unless the request opts in. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/server_advanced_test.dart`](../test/server/server_advanced_test.dart) | Covered by stateless conformance until a released 2026 interop fixture is available. | `stateless.rejects-removed-core-rpcs`, `logging.stateless-requires-request-log-level` | Verified |
| Draft notification subscriptions | [Draft subscriptions](https://modelcontextprotocol.io/specification/draft/server/utilities/subscriptions), [Draft schema subscriptions](https://modelcontextprotocol.io/specification/draft/schema#subscriptionslistenrequest) | `subscriptions/listen` requests require per-request `_meta`, acknowledged subscription filters include only supported notification types, and `notifications/subscriptions/acknowledged` typed parsing rejects mismatched JSON-RPC wrapper constants. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Covered by stateless conformance until a released 2026 interop fixture is available. | `subscriptions-listen.requires-request-meta`, `subscriptions-listen.resource-subscriptions-require-capability`, `subscriptions-acknowledged.rejects-wrapper-mismatch` | Verified |
| Progress token preservation and progress stream validation | [Progress](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress) | Progress tokens preserve string-or-integer wire shape, malformed token shapes fail at decode boundaries, and progress values should advance monotonically for a request. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/shared/progress_test.dart`](../test/shared/progress_test.dart), [`test/shared/protocol_test.dart`](../test/shared/protocol_test.dart) | [`test/interop/dart_client_with_ts_server_features_test.dart`](../test/interop/dart_client_with_ts_server_features_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/test_dart_server.dart`](../test/interop/test_dart_server.dart) | `jsonrpc.preserves-string-progress-token`, `progress.rejects-malformed-progress-token`; `RequestHandlerExtra.sendProgress` rejects repeated/decreasing progress before sending invalid notifications. | Verified |
| Streamable HTTP sessions, stateless connection-independence, stale recovery, SSE replay, and batch rejection | [Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [Draft lifecycle](https://modelcontextprotocol.io/specification/draft/basic/lifecycle) | Session IDs, stale-session retry, initial SSE event IDs for resumability, `Last-Event-ID` replay, protocol-version headers, JSON-RPC batch rejection, and draft stateless connection-independence are covered by Streamable HTTP and stateless lifecycle checks. Draft HTTP GET/DELETE removal is enforced with `405 Method Not Allowed`, and draft stateless POST bodies are rejected unless they contain exactly one JSON-RPC message. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart) | [`test/interop/dart_client_with_ts_server_test.dart`](../test/interop/dart_client_with_ts_server_test.dart), [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/replay_client.ts`](../test/interop/ts/src/replay_client.ts) | `stateless-http.rejects-non-post-methods`, `stateless-http.rejects-batch-payloads`; `stateless.related-task-uses-explicit-id-across-transports` covers draft related operations across separate transports. | Verified |
| Auth/security deployment behavior | [Authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization), [Transports security notes](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning) | OAuth, DNS rebinding, Origin/Host restrictions, and production deployment toggles are covered by executable harnesses where practical. OAuth authorization-code clients require authorization servers to advertise PKCE `S256`. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/), [`doc/transports.md`](transports.md) | [`test/interop/ts_client_with_dart_server_test.dart`](../test/interop/ts_client_with_dart_server_test.dart), [`test/interop/ts/src/oauth_client.ts`](../test/interop/ts/src/oauth_client.ts) | Safe local-development and production Host/Origin scenarios, bearer-token gating, compatibility-toggle trade-offs, first-class OAuth protected-resource metadata/challenges, OAuth insufficient-scope 403 challenges, official TypeScript SDK upscoping, OAuth protected-resource discovery, PKCE S256 authorization redirect, resource-bound token exchange, missing-PKCE-metadata refusal, and bearer reconnect are covered by tests. | Verified |

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
- `protocol-version.advertises-latest-2026-07-28`
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

The same CLI gate also includes draft MCP 2026-07-28 RC cases while that spec
is being prepared:

- `protocol-version.advertises-draft-2026-07-28`
- `server-discover.requires-request-meta`
- `server-discover.returns-draft-capabilities`
- `protocol-version.rejects-unsupported-stateless-version`
- `stateless.requires-complete-request-meta`
- `protocol-version.http-modern-400-retries-discovery`
- `capabilities.http-modern-400-does-not-fallback`
- `protocol-version.initialize-negotiates-stateful-version`
- `capabilities.stateless-does-not-infer-initialize-extensions`
- `stateless-http.rejects-mismatched-routing-headers`
- `stateless-http.requires-routing-headers`
- `stateless-http.rejects-non-post-methods`
- `stateless-http.rejects-batch-payloads`
- `stateless-http.task-requests-require-name-header`
- `stateless-http.validates-parameter-headers`
- `stateless-http.omits-invalid-numeric-parameter-headers`
- `stateless-http.encodes-parameter-header-values`
- `stateless-http.accepts-response-posts`
- `stateless-http.task-subscription-requires-client-capability`
- `stateless-http.omits-session-header-after-initialize`
- `stateless.related-task-uses-explicit-id-across-transports`
- `stateless.ignores-legacy-task-parameter`
- `stateless-client.rejects-legacy-task-options`
- `stateless.adds-result-type-and-cache-defaults`
- `tools-list.stateless-returns-deterministic-order`
- `tools-list.stateless-omits-legacy-execution`
- `resources.missing-resource-error-code-by-version`
- `stateless.rejects-unrecognized-result-type`
- `mrtr.input-required-supported-requests`
- `mrtr.rejects-unsupported-input-required-results`
- `mrtr.input-requests-require-client-capabilities`
- `stateless.rejects-removed-core-rpcs`
- `stateless.rejects-removed-core-notifications`
- `logging.stateless-requires-request-log-level`
- `tasks-extension.lifecycle-methods-do-not-require-repeated-capability`
- `tasks-extension.task-store-uses-extension-result-shapes`
- `tasks-extension.call-tool-result-cannot-spoof-task-result`
- `tasks-extension.task-result-requires-client-extension`
- `subscriptions-listen.task-ids-require-client-capability`
- `subscriptions-listen.requires-request-meta`
- `subscriptions-listen.resource-subscriptions-require-capability`
- `subscriptions-acknowledged.rejects-wrapper-mismatch`
- `capabilities.stateless-omits-legacy-task-capabilities`
- `elicitation.accepts-numeric-number-schema-keywords`

Use exact-case filtering when diagnosing one row:

```bash
cd packages/mcp_dart_cli
dart run bin/mcp_dart.dart conformance --suite all --case lifecycle.rejects-pre-initialize-request
```

## Known Gaps

- [#96](https://github.com/leehack/mcp_dart/issues/96): broader CLI debugging
  commands such as replay/proxy/validate flows.
