# MCP 2026-07-28 Draft/RC Spec Coverage Matrix

This matrix maps high-risk MCP `2026-07-28` draft/RC requirements to checked-in
`mcp_dart` coverage. MCP `2025-11-25` remains the default runtime profile; this
matrix only applies when callers opt into `McpProtocol.preview2026` or
`McpProtocol.require2026`.

The protocol is still draft/RC. Treat this as release-prep evidence for the
`dev/2026-07-28-rc` branch, not as a final-spec guarantee.

## Gates

Run the official conformance gates from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.9 client \
  --command "dart run test/conformance/mcp_2026_07_28_rc_client.dart" \
  --suite all \
  --spec-version 2025-11-25
dart run test/conformance/run_2026_07_28_rc_server_conformance.dart
dart run test/conformance/run_2026_07_28_rc_client_conformance.dart
```

Run the TypeScript SDK beta interop gate from the repository root:

```bash
cd test/interop/ts_2026_07_28_rc
npm ci
cd ../../..
dart run tool/testing/run_ts_2026_07_28_rc_interop.dart
```

CI runs the official conformance gates in the core workflow. The
`Run MCP 2026-07-28 TypeScript Interop` workflow runs the TypeScript SDK beta
interop fixture on relevant PRs, `dev/2026-07-28-rc` pushes, a daily schedule,
and manual dispatch.

## Matrix

| Spec area | Draft source | Requirement tracked here | Local coverage | Cross-SDK coverage | Official conformance | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Opt-in profile and stable default | [Versioning and compatibility](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Stable MCP `2025-11-25` remains default, while 2026 behavior is selected explicitly with preview or require profiles. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`doc/mcp-2026-07-28-rc.md`](mcp-2026-07-28-rc.md) | TypeScript SDK beta interop uses explicit 2026 clients and servers only. | 2025 and 2026 conformance both run in CI. | Verified |
| Version negotiation and discovery | [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Servers implement `server/discover`, advertise supported versions and capabilities, reject unsupported versions with draft error data, and clients retry or fall back according to transport-era rules. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart), [`test/conformance/mcp_2026_07_28_rc_client.dart`](../test/conformance/mcp_2026_07_28_rc_client.dart) | [`tool/testing/run_ts_2026_07_28_rc_interop.dart`](../tool/testing/run_ts_2026_07_28_rc_interop.dart) validates TypeScript SDK beta client -> Dart server and Dart 2026 client -> TypeScript SDK beta server discovery. | `protocol-version`, `server/discover`, and client negotiation scenarios in alpha.9. | Verified |
| Stateless request metadata | [Overview](https://modelcontextprotocol.io/specification/draft/basic), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Every 2026 request carries protocol version, client identity, and client capabilities in `_meta`; servers do not infer protocol state from a prior request. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | TypeScript SDK beta client fixture exercises normal request paths with 2026 metadata. | `stateless` and `stateless-http` scenarios in alpha.9. | Verified |
| Streamable HTTP routing headers | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | 2026 HTTP POST requests include required protocol, method, name, and parameter-routing headers; mismatches reject with draft header errors. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | TypeScript SDK beta client fixture validates `x-mcp-header` mirroring and raw header rejection against the Dart server. | `stateless-http.requires-routing-headers`, `stateless-http.validates-parameter-headers`, and related alpha.9 cases. | Verified |
| Removed session and resumability behavior | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | 2026 Streamable HTTP omits protocol-level sessions, rejects removed GET/DELETE behaviors, rejects JSON-RPC batches, and treats closed SSE response streams as request cancellation without legacy redelivery. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart) | TypeScript SDK beta fixture closes the Dart SSE response stream and verifies no legacy `notifications/cancelled` side effect is required. | `stateless-http.rejects-non-post-methods`, `stateless-http.rejects-batch-payloads`, and related alpha.9 cases. | Verified |
| Cacheable results and deterministic lists | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover) | `server/discover`, list, and read responses include `resultType`, `ttlMs`, and `cacheScope`; stateless `tools/list` is deterministic and omits stable-only tool execution metadata. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart) | TypeScript SDK beta client fixture checks discovery cache metadata and `tools/list` cache metadata. | Cacheable-result and tools-list scenarios in alpha.9. | Verified |
| Tools and JSON Schema 2020-12 | [Tools](https://modelcontextprotocol.io/specification/draft/server/tools), [Overview JSON Schema usage](https://modelcontextprotocol.io/specification/draft/basic) | Tool schemas preserve JSON Schema 2020-12 constructs, including nested boolean schemas; stable root-object compatibility remains intact for 2025 behavior. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart) | TypeScript SDK beta fixture validates `tools/list` and `tools/call`; deeper schema semantics are covered by local and conformance tests. | 2026 server suite is green; 2026 client suite keeps the upstream `json-schema-ref-no-deref` fixture gap expected. | Verified with one upstream client fixture gap |
| MRTR and elicitation | [Message patterns](https://modelcontextprotocol.io/specification/draft/basic), [Schema reference](https://modelcontextprotocol.io/specification/draft/schema#elicitrequesturlparams) | 2026 `input_required` results are emitted only for supported requests and require advertised client capabilities. URL-mode `elicitation/create` uses `mode`, `message`, and `url` without legacy `elicitationId` or `notifications/elicitation/complete`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/elicitation_test.dart`](../test/elicitation_test.dart) | TypeScript SDK beta client fixture completes a 2026 `input_required` retry flow against the Dart server; the reverse Dart preview client fixture completes an `input_required` elicitation retry against the TypeScript SDK beta server. | `mrtr` scenarios in alpha.9. | Verified |
| Subscriptions | [Subscriptions](https://modelcontextprotocol.io/specification/draft/basic/utilities/subscriptions), [Schema reference](https://modelcontextprotocol.io/specification/draft/schema#subscriptionslistenresult) | `subscriptions/listen` acknowledges before list-change notifications, filters unsupported notification types, correlates notifications through `io.modelcontextprotocol/subscriptionId`, and returns `SubscriptionsListenResult` with the same required subscription id metadata on graceful close. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart) | TypeScript SDK beta fixture validates `subscriptions/listen` acknowledgment and list-change notification correlation against the Dart server. | Subscription scenarios in alpha.9. | Verified |
| Request-scoped logging and removed core RPCs | [Logging](https://modelcontextprotocol.io/specification/draft/server/utilities/logging), [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | 2026 stateless requests use request-scoped logging metadata, and removed stable-era core RPCs/notifications are rejected in the 2026 profile. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/server_advanced_test.dart`](../test/server/server_advanced_test.dart) | TypeScript SDK beta fixture validates raw removed-RPC rejection against the Dart server. | Removed-RPC and logging scenarios in alpha.9. | Verified |
| Draft-only public APIs | [Schema reference](https://modelcontextprotocol.io/specification/draft/schema) | APIs that are useful only for 2026, such as non-object structured tool output and 2026 protocol profiles, are documented as draft/RC APIs and do not change stable defaults. | [`doc/mcp-2026-07-28-rc.md`](mcp-2026-07-28-rc.md), public dartdoc on protocol profiles and draft-only helpers. | Not cross-SDK specific. | Covered indirectly by 2026 conformance and local parser/serializer tests. | Verified |

## Known Gaps

- The official conformance package is still alpha. The 2026 client suite keeps
  `json-schema-ref-no-deref` expected-failed because the alpha.9 mock server for
  that scenario still behaves like a stable-only server.
- The reverse Dart 2026 client -> TypeScript SDK beta server path now covers
  discovery, `tools/list`, `tools/call`, and a TypeScript-server
  `input_required` elicitation retry. Broader reverse-path coverage for
  subscriptions/listen, cacheable result fields, and other streaming/result
  paths should follow as the TypeScript SDK beta server surface stabilizes.
