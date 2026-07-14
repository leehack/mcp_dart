# MCP 2026-07-28 Draft/RC Spec Coverage Matrix

`mcp_dart` implements the complete core client/server wire surface of the
locked MCP `2026-07-28` release candidate. This matrix indexes the high-risk
and release-changing requirements against checked-in evidence; it is not an
exhaustive inventory of every schema type or API. The dev.2 preview defaults to
`McpProtocol.stable`, while `McpProtocol.legacy` retains the full MCP
`2025-11-25` feature set and negotiates supported earlier initialization
versions.

Core means the normative wire requirements assigned to client and server roles
by the pinned RC. It excludes optional MCP extensions, host UI behavior, an
authorization-server implementation, and a general-purpose JSON Schema
validation engine.

The protocol is still draft/RC. Treat this as prerelease evidence, not as a
final-spec guarantee.

`Verified` means the row has executable local evidence plus the applicable
interop or official conformance evidence. `Local only` means checked-in Dart
coverage exists, but no current cross-SDK or official scenario covers it.

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

Until the final tag exists, CI checks out the commit pinned in
[`tool/testing/mcp_2026_release_spec_ref.txt`](../tool/testing/mcp_2026_release_spec_ref.txt)
and audits its `schema/draft/examples` directory. The dev.2 matrix was audited
against upstream commit
[`3e0df99`](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/3e0df99d829b5a3120ff9fb5c0c752dd3355d5d6).
The readable Draft source links below remain mutable; the pinned commit keeps a
moving draft from changing the evidence underneath a green run.

After the final upstream tag exists, audit its machine-readable examples with:

```bash
dart run tool/spec_example_audit.dart \
  /path/to/modelcontextprotocol/schema/2026-07-28/examples
```

Run the TypeScript SDK beta interop gate from the repository root:

```bash
cd test/interop/ts_2026_07_28_rc
npm ci
cd ../../..
dart run tool/testing/run_ts_2026_07_28_rc_interop.dart
```

CI runs the official conformance gates in the core workflow. The
`Run MCP 2026-07-28 Interop` workflow runs the TypeScript and Python SDK beta
interop fixtures on relevant PRs, manual dispatch, and the daily `main`
schedule.

## Matrix

| Spec area | Draft source | Requirement tracked here | Local coverage | Cross-SDK coverage | Official conformance | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Default stable profile with legacy opt-out | [Versioning and compatibility](https://modelcontextprotocol.io/specification/draft/basic/versioning) | The dev.2 preview defaults to `McpProtocol.stable`, while callers can explicitly select `McpProtocol.legacy` or `McpProtocol.require2026`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`doc/mcp-2026-07-28-rc.md`](mcp-2026-07-28-rc.md) | TypeScript SDK beta interop covers explicit 2026 negotiation; local tests cover the default-option path. | 2025 and 2026 conformance both run in CI. | Verified |
| Version negotiation and discovery | [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Servers implement `server/discover`, advertise supported versions and capabilities, reject unsupported versions with draft error data, and clients retry or fall back according to transport-era rules. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart), [`test/conformance/mcp_2026_07_28_rc_client.dart`](../test/conformance/mcp_2026_07_28_rc_client.dart) | The TypeScript and Python SDK beta fixtures validate discovery and protocol selection in both directions. | `protocol-version`, `server/discover`, and client negotiation scenarios in alpha.9. | Verified |
| Stateless request metadata | [Overview](https://modelcontextprotocol.io/specification/draft/basic), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Every 2026 request carries protocol version, client identity, and client capabilities in `_meta`; servers do not infer protocol state from a prior request. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | TypeScript SDK beta client fixture exercises normal request paths with 2026 metadata. | `stateless` and `stateless-http` scenarios in alpha.9. | Verified |
| Streamable HTTP routing headers | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | 2026 HTTP POST requests include required protocol, method, name, and parameter-routing headers; mismatches reject with draft header errors. Stateless SSE responses preserve browser CORS headers. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | TypeScript SDK beta validates `x-mcp-header` mirroring and raw header rejection; Chrome validates the real cross-origin 2026 path. | `stateless-http.requires-routing-headers`, `stateless-http.validates-parameter-headers`, and related alpha.9 cases. | Verified |
| Removed session and resumability behavior | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | 2026 Streamable HTTP omits protocol-level sessions, rejects removed GET/DELETE behaviors, rejects JSON-RPC batches, and treats closed SSE response streams as request cancellation without legacy redelivery. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart) | TypeScript SDK beta fixture closes the Dart SSE response stream and verifies no legacy `notifications/cancelled` side effect is required. | `stateless-http.rejects-non-post-methods`, `stateless-http.rejects-batch-payloads`, and related alpha.9 cases. | Verified |
| Cacheable results and deterministic lists | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover) | `server/discover`, list, and read responses include `resultType`, `ttlMs`, and `cacheScope`; stateless `tools/list` is deterministic and omits stable-only tool execution metadata. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart) | TypeScript SDK beta client fixture checks discovery cache metadata and `tools/list` cache metadata. | Cacheable-result and tools-list scenarios in alpha.9. | Verified |
| Tools and JSON Schema 2020-12 | [Tools](https://modelcontextprotocol.io/specification/draft/server/tools), [Overview JSON Schema usage](https://modelcontextprotocol.io/specification/draft/basic) | Tool schemas preserve JSON Schema 2020-12 constructs, including nested boolean schemas; stable root-object compatibility remains intact for 2025 behavior. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart) | TypeScript SDK beta fixture validates `tools/list` and `tools/call`; deeper schema semantics are covered by local and conformance tests. | Both 2026 server and client suites are green with no expected failures; a local network-`$ref` security canary remains covered. | Verified |
| Resource semantics | [Resources](https://modelcontextprotocol.io/specification/draft/server/resources) | Successful reads preserve typed contents and cache metadata; a missing resource returns `InvalidParams` (`-32602`) rather than an empty result. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart) | Current beta fixtures focus on discovery and tools rather than 2026 resource errors. | Official `sep-2164-resource-not-found` plus resource list/read scenarios in alpha.9. | Verified |
| MRTR and elicitation | [Message patterns](https://modelcontextprotocol.io/specification/draft/basic), [Schema reference](https://modelcontextprotocol.io/specification/draft/schema#elicitrequesturlparams) | 2026 `input_required` results are emitted only for supported requests and require advertised client capabilities. URL-mode `elicitation/create` uses `mode`, `message`, and `url` without legacy `elicitationId` or `notifications/elicitation/complete`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | TypeScript SDK beta client fixture completes a 2026 `input_required` retry flow against the Dart server; the reverse Dart stable-profile client fixture completes an `input_required` elicitation retry against the TypeScript SDK beta server. | `mrtr` scenarios in alpha.9. | Verified |
| Subscriptions | [Subscriptions](https://modelcontextprotocol.io/specification/draft/basic/utilities/subscriptions), [Schema reference](https://modelcontextprotocol.io/specification/draft/schema#subscriptionslistenresult) | `subscriptions/listen` acknowledges before list-change notifications, filters unsupported notification types, correlates notifications through `io.modelcontextprotocol/subscriptionId`, and returns `SubscriptionsListenResult` with the same required subscription id metadata on graceful close. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_rc_server.dart`](../test/conformance/mcp_2026_07_28_rc_server.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | TypeScript SDK beta fixture validates `subscriptions/listen` acknowledgment and list-change notification correlation against the Dart server. | Subscription scenarios in alpha.9. | Verified |
| Deprecated request-scoped logging and removed core RPCs | [Logging](https://modelcontextprotocol.io/specification/draft/server/utilities/logging), [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | The deprecated 2026 logging wire behavior is retained for compatibility with request-scoped metadata, while removed stable-era core RPCs and notifications are rejected in the 2026 profile. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/server_advanced_test.dart`](../test/server/server_advanced_test.dart) | TypeScript SDK beta fixture validates raw removed-RPC rejection against the Dart server. | Removed-RPC and logging scenarios in alpha.9. | Verified |
| Tasks extension | [Tasks extension SEP-2663](https://tasks.extensions.modelcontextprotocol.io/seps/2663-tasks-extension) | The `io.modelcontextprotocol/tasks` extension negotiates task support, returns extension result shapes, and implements `tasks/get`, `tasks/update`, and `tasks/cancel` without restoring removed core task augmentation. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types/tasks_extension_test.dart`](../test/types/tasks_extension_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), CLI task-extension conformance cases | No checked-in 2026 cross-SDK task-extension fixture yet. | The alpha.9 official server/client scenario lists do not cover the Tasks extension. | Local only |
| Authorization and HTTP deployment security | [Authorization](https://modelcontextprotocol.io/specification/draft/basic/authorization), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | Covers OAuth protected-resource discovery, bearer challenges, PKCE S256, callback state, trusted discovery origins, redirect refusal, resource-bound token exchange, exact Origin handling, Host validation, and safe loopback defaults. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/) | Stable TypeScript OAuth interop covers the complete protected-resource flow; current 2026 beta interop has limited credentialed coverage. | The alpha.9 client runner contains authorization scenarios; server-side deployment policy remains locally tested. | Verified |
| Draft/RC public APIs | [Schema reference](https://modelcontextprotocol.io/specification/draft/schema) | APIs useful only for 2026, such as non-object structured tool output and 2026 protocol profiles, are documented as draft/RC APIs. Callers can explicitly select the legacy profile when those APIs are unsuitable. | [`doc/mcp-2026-07-28-rc.md`](mcp-2026-07-28-rc.md), public dartdoc on protocol profiles and draft-only helpers. | Not cross-SDK specific. | Covered indirectly by 2026 conformance and local parser/serializer tests. | Verified |

## Known Gaps

These are gaps in external evidence unless stated otherwise; they are not known
missing core protocol behavior.

- The official conformance package is still alpha, so its scenario inventory
  and assertions may continue to change before the final specification tag.
  The current alpha.9 server and client suites pass with no expected failures;
  a local network-`$ref` security canary remains as regression coverage.
- The Tasks extension is locally covered but is absent from the current
  official alpha.9 scenario inventory and from checked-in 2026 cross-SDK
  interop. Do not describe it as cross-SDK verified yet.
- The reverse Dart 2026 client -> TypeScript SDK beta server path now covers
  discovery, `tools/list`, `tools/call`, one-time `HeaderMismatch` recovery,
  and a TypeScript-server `input_required` elicitation retry. Broader
  reverse-path coverage for subscriptions/listen, cacheable result fields, and
  other streaming/result paths should follow as the TypeScript SDK beta server
  surface stabilizes.
