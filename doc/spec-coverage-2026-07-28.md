# MCP 2026-07-28 Specification Coverage Matrix

`mcp_dart` implements the complete core client/server wire surface of the
locked release candidate for the MCP 2026-07-28 specification. This matrix indexes the high-risk
and release-changing requirements against checked-in evidence; it is not an
exhaustive inventory of every schema type or API. The dev.2 preview defaults to
`McpProtocol.stable`, while `McpProtocol.legacy` retains the full MCP
2025-11-25 feature set and negotiates supported earlier initialization
versions.

Core means the normative wire requirements assigned to client and server roles
by the pinned release-candidate specification. It excludes optional MCP
extensions, host UI behavior, an authorization-server implementation, JSON
Schema external-reference resolution, and custom JSON Schema vocabularies.

The protocol is still a release candidate. Treat this as prerelease evidence,
not as a final-spec guarantee.

`Verified` means the row has executable local evidence plus the applicable
interop or official conformance evidence. `Local only` means checked-in Dart
coverage exists, but no current cross-SDK or official scenario covers it.

## Gates

Run the official conformance gates from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.9 client \
  --command "dart run test/conformance/mcp_2026_07_28_client.dart" \
  --suite all \
  --spec-version 2025-11-25
dart run test/conformance/run_2026_07_28_server_conformance.dart
dart run test/conformance/run_2026_07_28_client_conformance.dart
```

The published conformance alpha predates spec PR #3002. Reproduce the corrected
stateless identity check against the immutable merged conformance PR #403
source with:

```bash
dart run test/conformance/run_2026_07_28_server_conformance.dart \
  --scenario server-stateless \
  --conformance-package \
    github:modelcontextprotocol/conformance#d1c0b9591786726d8a4bec05306eb103ba6894ff \
  --expected-failures \
    test/conformance/2026_07_28_post_3002_expected_failures.txt
```

Until the final tag exists, CI checks out the commit pinned in
[`tool/testing/mcp_2026_07_28_spec_ref.txt`](../tool/testing/mcp_2026_07_28_spec_ref.txt).
It parses all 128 machine-readable examples and inventories all 31 official
draft specification documents against checked-in scope, evidence, and
normalized SHA-256 content hashes. Any prose change at a new pinned revision
fails the inventory until that document is explicitly reviewed and its hash is
updated. The dev.2 matrix was last reviewed against upstream commit
[`71e3069`](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/71e306956a4959c9655e5036be215d41986596e6).
The readable source links below remain mutable; the immutable commit keeps a
moving draft from changing the evidence underneath a green run.

The document inventory is a drift guard, not a semantic proof by itself. The
matrix, regression tests, interop fixtures, and conformance suites provide the
behavioral evidence for each claim.

After the final upstream tag exists, audit its machine-readable examples with:

```bash
dart run tool/spec_example_audit.dart \
  /path/to/modelcontextprotocol/schema/2026-07-28/examples
dart run tool/spec_document_inventory_audit.dart \
  /path/to/modelcontextprotocol/docs/specification/2026-07-28
```

Run the TypeScript SDK beta interop gate from the repository root:

```bash
cd test/interop/ts_2026_07_28
npm ci
cd ../../..
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=dart-to-ts
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=ts-to-dart \
  --expect-published-ts-client-gap
```

Run the independent JSON Schema Draft 2020-12 and Draft 7 compatibility gates
against their pinned upstream revision:

```bash
JSON_SCHEMA_SUITE_REF="$(tr -d '[:space:]' \
  < tool/testing/json_schema_test_suite_ref.txt)"
git clone --filter=blob:none --no-checkout \
  https://github.com/json-schema-org/JSON-Schema-Test-Suite.git \
  .dart_tool/json-schema-test-suite
git -C .dart_tool/json-schema-test-suite fetch --depth=1 \
  origin "$JSON_SCHEMA_SUITE_REF"
git -C .dart_tool/json-schema-test-suite checkout --detach FETCH_HEAD
dart run tool/testing/run_json_schema_2020_12_suite.dart \
  .dart_tool/json-schema-test-suite/tests/draft2020-12
dart run tool/testing/run_json_schema_draft7_suite.dart \
  .dart_tool/json-schema-test-suite/tests/draft7
```

The runners fail on any supported mandatory assertion mismatch. Their exact
file, group, assertion, and exclusion manifests are pinned so an upstream suite
change or a broader policy exclusion cannot pass silently. At the pinned
revision, the Draft 2020-12 gate evaluates 1,242 supported assertions and the
Draft 7 compatibility gate evaluates 904 supported assertions across 37 files
and 257 groups. The Draft 7 gate excludes exactly 11 external-reference groups
and no unsupported-dialect or invalid-schema groups.

CI runs the official conformance gates in the core workflow. The
`Run MCP 2026-07-28 Interop` workflow runs the TypeScript and Python SDK beta
interop fixtures on relevant PRs, manual dispatch, and the daily `main`
schedule.

## Matrix

| Spec area | Official source | Requirement tracked here | Local coverage | Cross-SDK coverage | Official conformance | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Default stable profile with legacy opt-out | [Versioning and compatibility](https://modelcontextprotocol.io/specification/draft/basic/versioning) | The dev.2 preview defaults to `McpProtocol.stable`, while callers can explicitly select `McpProtocol.legacy` or `McpProtocol.require2026`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`doc/mcp-2026-07-28.md`](mcp-2026-07-28.md) | TypeScript SDK beta interop covers explicit MCP 2026-07-28 negotiation; local tests cover the default-option path. | MCP 2025-11-25 and MCP 2026-07-28 conformance both run in CI. | Verified |
| Version negotiation and discovery | [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Servers implement `server/discover`, advertise supported versions and capabilities, reject unsupported versions with draft error data, and clients retry or fall back according to transport-era rules. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart), [`test/conformance/mcp_2026_07_28_client.dart`](../test/conformance/mcp_2026_07_28_client.dart) | Dart clients retain temporary legacy-body read compatibility with published TypeScript and Python beta servers. Their published beta clients remain known pre-#3002 gaps against a spec-correct Dart server; TypeScript SDK #2513 preview provides forward validation. | Published alpha.9 predates #3002; conformance PR #403 semantics are verified locally against the merged PR source. | Verified locally; published peer/referee gaps |
| Stateless request metadata | [Overview](https://modelcontextprotocol.io/specification/draft/basic), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Every MCP 2026-07-28 request carries protocol version and client capabilities in `_meta`; client identity is optional, while a present malformed identity is rejected. Servers do not infer protocol state from a prior request. Non-MCP metadata remains opaque and is preserved. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | Published TypeScript SDK beta clients exercise identified requests; local tests and merged conformance PR #403 source cover anonymous requests. | Published alpha.9 incorrectly requires `clientInfo`; its three stale `server-stateless` diagnostics are matched exactly until a release includes conformance PR #403. | Verified locally; published referee gap |
| Stateless result identity | [Schema reference](https://modelcontextprotocol.io/specification/draft/schema) | `McpServer` stamps its configured identity by default in successful MCP 2026-07-28 result `_meta["io.modelcontextprotocol/serverInfo"]`. A valid handler-authored value wins, `null` omits the optional key, and malformed non-null output is rejected before serialization. Discovery has no body `serverInfo`; missing canonical identity is anonymous, while a present malformed or `null` canonical value is rejected. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types_test.dart`](../test/types_test.dart) cover discovery, list/tool/task/subscription metadata merging, handler precedence, anonymous identity, malformed output, and legacy isolation. | Dart temporarily reads legacy discovery-body identity from published TypeScript and Python beta servers and ignores malformed values in that obsolete location; TypeScript SDK #2513 preview validates the final result metadata shape. | Conformance PR #403 checks discovery identity metadata; published alpha.9 predates it. | Verified locally; published peer/referee gaps |
| JSON-RPC envelopes and errors | [Base protocol](https://modelcontextprotocol.io/specification/draft/basic) | String and integer request IDs retain their wire identity, arbitrary JSON-RPC error `data` remains observable, and unknown metadata is preserved. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Cross-SDK fixtures exercise normal success and error envelopes. | Error and malformed-request scenarios in alpha.9. | Verified |
| Streamable HTTP routing headers | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | MCP 2026-07-28 HTTP POST requests include required protocol, method, name, and parameter-routing headers; mismatches reject with draft header errors. A `HeaderMismatch` refreshes `tools/list` metadata before one retry. Stateless SSE responses preserve browser CORS headers. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | The TypeScript SDK #2513 preview validates `x-mcp-header` mirroring and raw rejection against Dart; the published TypeScript server validates Dart's schema-refresh retry. Chrome validates the real cross-origin path. | `stateless-http.requires-routing-headers`, `stateless-http.validates-parameter-headers`, and related alpha.9 cases. | Verified |
| Removed session and resumability behavior | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | MCP 2026-07-28 Streamable HTTP omits protocol-level sessions, rejects removed GET/DELETE behaviors and JSON-RPC batches, and cancels a stateless request by closing only that POST response stream without legacy notification redelivery. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | The published TypeScript server path verifies Dart request cancellation and recovery; the #2513 preview verifies the reverse server-observed close. Loopback HTTP and real Chrome add sibling isolation and cleanup coverage. Python cancellation is not yet covered. | `stateless-http.rejects-non-post-methods`, `stateless-http.rejects-batch-payloads`, and related alpha.9 cases. | Verified |
| Cacheable results and deterministic lists | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover) | `server/discover`, list, and read responses include `resultType`, `ttlMs`, and `cacheScope`; stateless `tools/list` is deterministic and omits stable-only tool execution metadata. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart) | The TypeScript SDK #2513 preview fixture checks discovery and `tools/list` cache metadata. | Cacheable-result and tools-list scenarios in alpha.9. | Verified |
| Tools and JSON Schema 2020-12 | [Tools](https://modelcontextprotocol.io/specification/draft/server/tools), [Overview JSON Schema usage](https://modelcontextprotocol.io/specification/draft/basic) | Tool schemas preserve JSON Schema 2020-12 constructs, including nested boolean schemas; stable root-object compatibility remains intact for MCP 2025-11-25 behavior. The built-in validator defaults to Draft 2020-12, accepts an explicitly declared Draft 7 schema for MCP 2025-11-25 compatibility, and synchronously resolves local fragments plus absolute or relative identifiers that stay inside the supplied schema document, including dynamic references. Unresolved references outside that document, unsupported dialects, and custom vocabularies are rejected without network I/O. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/shared/json_schema_validator_test.dart`](../test/shared/json_schema_validator_test.dart), [`test/shared/json_schema_validator_io_test.dart`](../test/shared/json_schema_validator_io_test.dart), [`tool/testing/run_json_schema_2020_12_suite.dart`](../tool/testing/run_json_schema_2020_12_suite.dart), [`tool/testing/run_json_schema_draft7_suite.dart`](../tool/testing/run_json_schema_draft7_suite.dart), [`tool/testing/json_schema_suite_runner.dart`](../tool/testing/json_schema_suite_runner.dart), [`tool/testing/json_schema_test_suite_ref.txt`](../tool/testing/json_schema_test_suite_ref.txt), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | The published TypeScript server and #2513 preview client validate `tools/list` and `tools/call`; schema-validation semantics and the no-network policy are locally tested. | The MCP 2026-07-28 client suite is green; the published server suite keeps only the three exactly matched `server-stateless` pre-#3002 diagnostics. The pinned official JSON Schema Test Suite gates pass all supported assertions, while a loopback security test proves rejected network `$ref` values cause no HTTP request. | Verified with a published referee gap |
| Resource semantics | [Resources](https://modelcontextprotocol.io/specification/draft/server/resources) | Successful reads preserve typed contents and cache metadata; a missing resource returns `InvalidParams` (`-32602`) rather than an empty result. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart) | Current beta fixtures focus on discovery and tools rather than MCP 2026-07-28 resource errors. | Official `sep-2164-resource-not-found` plus resource list/read scenarios in alpha.9. | Verified |
| MRTR and elicitation | [MRTR](https://modelcontextprotocol.io/specification/draft/basic/patterns/mrtr), [Elicitation](https://modelcontextprotocol.io/specification/draft/client/elicitation) | MCP 2026-07-28 `input_required` results are emitted only for supported requests and require advertised client capabilities. URL-mode `elicitation/create` uses `mode`, `message`, and `url` without legacy `elicitationId` or `notifications/elicitation/complete`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | The TypeScript SDK #2513 preview client completes an MCP 2026-07-28 `input_required` retry against Dart; the Dart stable-profile client completes the reverse retry against the published TypeScript beta server. | `mrtr` scenarios in alpha.9. | Verified |
| Subscriptions | [Subscriptions](https://modelcontextprotocol.io/specification/draft/basic/patterns/subscriptions), [Schema reference](https://modelcontextprotocol.io/specification/draft/schema#subscriptionslistenresult) | Each `subscriptions/listen` stream acknowledges before any later notification carrying that subscription ID. Other subscription IDs may interleave on stdio. The SDK filters unsupported types, correlates through `io.modelcontextprotocol/subscriptionId`, and returns the same ID on graceful close. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | The TypeScript SDK #2513 preview validates acknowledgment and list-change notification correlation against Dart. | Subscription scenarios in alpha.9. | Verified |
| Deprecated request-scoped logging and removed core RPCs | [Logging](https://modelcontextprotocol.io/specification/draft/server/utilities/logging), [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | The deprecated MCP 2026-07-28 logging wire behavior is retained for compatibility with request-scoped metadata, while removed stable-era core RPCs and notifications are rejected in the MCP 2026-07-28 profile. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/server_advanced_test.dart`](../test/server/server_advanced_test.dart) | The TypeScript SDK #2513 preview fixture validates raw removed-RPC rejection against the Dart server. | Removed-RPC and logging scenarios in alpha.9. | Verified |
| Tasks extension | [Tasks extension SEP-2663](https://tasks.extensions.modelcontextprotocol.io/seps/2663-tasks-extension) | The `io.modelcontextprotocol/tasks` extension negotiates task support, returns extension result shapes, and implements `tasks/get`, `tasks/update`, and `tasks/cancel` without restoring removed core task augmentation. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types/tasks_extension_test.dart`](../test/types/tasks_extension_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), CLI task-extension conformance cases | No checked-in MCP 2026-07-28 cross-SDK task-extension fixture yet. | The alpha.9 official server/client scenario lists do not cover the Tasks extension. | Local only |
| Authorization and HTTP deployment security | [Authorization](https://modelcontextprotocol.io/specification/draft/basic/authorization), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | Covers OAuth protected-resource discovery, bearer challenges, PKCE S256, callback state, trusted discovery origins, redirect refusal, resource-bound token exchange, exact Origin handling, Host validation, and safe loopback defaults. | [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/) | Stable TypeScript OAuth interop covers the complete protected-resource flow; current MCP 2026-07-28 beta interop has limited credentialed coverage. | The alpha.9 client runner contains authorization scenarios; server-side deployment policy remains locally tested. | Verified |
| MCP 2026-07-28 preview public APIs | [Schema reference](https://modelcontextprotocol.io/specification/draft/schema) | APIs useful only for MCP 2026-07-28, such as non-object structured tool output and MCP 2026-07-28 protocol profiles, are documented as preview APIs. Callers can explicitly select the legacy profile when those APIs are unsuitable. | [`doc/mcp-2026-07-28.md`](mcp-2026-07-28.md), public dartdoc on protocol profiles and MCP 2026-07-28 helpers. | Not cross-SDK specific. | Covered indirectly by MCP 2026-07-28 conformance and local parser/serializer tests. | Verified |

## Known Gaps

These are gaps in external evidence unless stated otherwise; they are not known
missing core protocol behavior.

- Published `@modelcontextprotocol/conformance@0.2.0-alpha.9` predates spec
  PR #3002 and conformance PR #403, so its three stale `server-stateless`
  diagnostics are matched exactly while merged-PR-source verification is green.
- Published TypeScript SDK beta.4 requires body `DiscoverResult.serverInfo`.
  Dart keeps the Dart-client -> TypeScript-server path through a temporary read
  fallback, while the TypeScript-client -> Dart-server direction remains an
  exact expected negotiation gap until TypeScript SDK PR #2513 is released.
- Published Python SDK `mcp==2.0.0b2` also requires body
  `DiscoverResult.serverInfo`. Dart-client -> Python-server remains required
  through the same read fallback; Python-client -> Dart-server asserts its
  exact 2026 -> 2025 fallback as a self-expiring expected gap.
- The official conformance package is still alpha, so its scenario inventory
  and assertions may continue to change before the final specification tag.
  The current alpha.9 client suite passes with no expected failures; a local
  network-`$ref` security canary remains as regression coverage.
- The Tasks extension is locally covered but is absent from the current
  official alpha.9 scenario inventory and from checked-in MCP 2026-07-28 cross-SDK
  interop. Do not describe it as cross-SDK verified yet.
- The reverse Dart MCP 2026-07-28 client -> TypeScript SDK beta server path now covers
  discovery, `tools/list`, `tools/call`, one-time `HeaderMismatch` recovery,
  and a TypeScript-server `input_required` elicitation retry. Broader
  reverse-path coverage for subscriptions/listen, cacheable result fields, and
  other streaming/result paths should follow as the TypeScript SDK beta server
  surface stabilizes.
