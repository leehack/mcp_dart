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

The alpha.9 MCP 2026-07-28 client suite passes all 25 authorization scenarios.
The published server suite retains exactly three expected `server-stateless`
diagnostics, listed in
[`test/conformance/2026_07_28_expected_failures.txt`](../test/conformance/2026_07_28_expected_failures.txt),
because it predates PR #3002.

Until the final tag exists, CI checks out the commit pinned in
[`tool/testing/mcp_2026_07_28_spec_ref.txt`](../tool/testing/mcp_2026_07_28_spec_ref.txt).
It parses all 128 machine-readable examples and inventories all 31 official
draft specification documents against checked-in scope, evidence, and
normalized SHA-256 content hashes. Any prose change at a new pinned revision
fails the inventory until that document is explicitly reviewed and its hash is
updated. The current day-0 readiness matrix was last reviewed against upstream
commit
[`88191b9`](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/88191b9f574d67d553ea9372278a14e09d762f55).
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
  --direction=ts-to-dart
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
| Default stable profile with legacy opt-out | [Versioning and compatibility](https://modelcontextprotocol.io/specification/draft/basic/versioning) | The 2.3 line defaults to `McpProtocol.stable`. Current source bounds silent discovery on body-only transports to five seconds before legacy fallback; HTTP keeps its normal request timeout. Callers can explicitly select `McpProtocol.legacy` or `McpProtocol.require2026`. | [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`doc/mcp-2026-07-28.md`](mcp-2026-07-28.md) | TypeScript SDK beta interop covers explicit MCP 2026-07-28 negotiation; local tests cover the default-option and silent-legacy-server paths. | MCP 2025-11-25 and MCP 2026-07-28 conformance both run in CI. | Verified |
| Version negotiation and discovery | [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Servers implement `server/discover`, advertise supported versions and capabilities, reject unsupported versions with draft error data, and clients retry or fall back according to transport-era rules. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart), [`test/conformance/mcp_2026_07_28_client.dart`](../test/conformance/mcp_2026_07_28_client.dart) | Published TypeScript beta.5 passes both directions on the post-#3002 wire. Dart retains temporary legacy-body read compatibility for Python beta and older peers; the published Python client remains a known pre-#3002 gap. | Published alpha.9 predates #3002; conformance PR #403 semantics are verified locally against the merged PR source. | Verified locally; published Python/referee gaps |
| Stateless request metadata | [Overview](https://modelcontextprotocol.io/specification/draft/basic), [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning) | Every MCP 2026-07-28 request carries protocol version and client capabilities in `_meta`; client identity is optional, while a present malformed identity is rejected. Servers do not infer protocol state from a prior request. Non-MCP metadata remains opaque and is preserved. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | Published TypeScript SDK beta clients exercise identified requests; local tests and merged conformance PR #403 source cover anonymous requests. | Published alpha.9 incorrectly requires `clientInfo`; its three stale `server-stateless` diagnostics are matched exactly until a release includes conformance PR #403. | Verified locally; published referee gap |
| Stateless result identity | [Schema reference](https://modelcontextprotocol.io/specification/draft/schema) | `McpServer` stamps its configured identity by default in successful MCP 2026-07-28 result `_meta["io.modelcontextprotocol/serverInfo"]`. A valid handler-authored value wins, `null` omits the optional key, and malformed non-null output is rejected before serialization. Discovery has no body `serverInfo`; missing canonical identity is anonymous, while a present malformed or `null` canonical value is rejected. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types_test.dart`](../test/types_test.dart) cover discovery, list/tool/task/subscription metadata merging, handler precedence, anonymous identity, malformed output, and legacy isolation. | Published TypeScript beta.5 validates the final result metadata shape in both directions. Dart temporarily reads legacy discovery-body identity from Python beta and older peers and ignores malformed values in that obsolete location. | Conformance PR #403 checks discovery identity metadata; published alpha.9 predates it. | Verified locally; published Python/referee gaps |
| JSON-RPC envelopes and errors | [Base protocol](https://modelcontextprotocol.io/specification/draft/basic) | String and integer request IDs retain their wire identity, arbitrary JSON-RPC error `data` remains observable, and unknown metadata is preserved. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Cross-SDK fixtures exercise normal success and error envelopes. | Error and malformed-request scenarios in alpha.9. | Verified |
| Streamable HTTP routing headers | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | MCP 2026-07-28 HTTP POST requests include required protocol, method, name, and parameter-routing headers; mismatches reject with draft header errors. A `HeaderMismatch` refreshes `tools/list` metadata before one retry. Stateless SSE responses preserve browser CORS headers. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | Published TypeScript beta.5 validates `x-mcp-header` mirroring and raw rejection against Dart; its server validates Dart's schema-refresh retry. Chrome validates the real cross-origin path. | `stateless-http.requires-routing-headers`, `stateless-http.validates-parameter-headers`, and related alpha.9 cases. | Verified |
| Removed session and resumability behavior | [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | MCP 2026-07-28 Streamable HTTP omits protocol-level sessions, rejects removed GET/DELETE behaviors, JSON-RPC batches, and client response/error POSTs, and cancels a stateless request by closing only that POST response stream without legacy notification redelivery. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | Published TypeScript beta.5 verifies request cancellation and recovery in both directions. Loopback HTTP and real Chrome add sibling isolation and cleanup coverage. Python cancellation is not yet covered. | `stateless-http.rejects-non-post-methods`, `stateless-http.rejects-batch-payloads`, and related alpha.9 cases. | Verified |
| Cacheable results and deterministic lists | [Caching](https://modelcontextprotocol.io/specification/draft/server/utilities/caching), [Discovery](https://modelcontextprotocol.io/specification/draft/server/discover) | `server/discover`, list, and read responses include `resultType`, `ttlMs`, and `cacheScope`; completed `resources/read` MRTR retries are forced immediately stale and private even when a handler supplies reusable hints. Stateless `tools/list` is deterministic and omits initialization-era-only tool execution metadata. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart) | Published TypeScript beta.5 checks discovery and `tools/list` cache metadata. | Cacheable-result and tools-list scenarios in alpha.9. | Verified |
| Tools and JSON Schema 2020-12 | [Tools](https://modelcontextprotocol.io/specification/draft/server/tools), [Overview JSON Schema usage](https://modelcontextprotocol.io/specification/draft/basic) | Tool schemas preserve JSON Schema 2020-12 constructs, including nested boolean schemas; MCP 2025-11-25 root-object compatibility remains intact. The built-in validator defaults to Draft 2020-12, accepts an explicitly declared Draft 7 schema for MCP 2025-11-25 compatibility, and synchronously resolves local fragments plus absolute or relative identifiers that stay inside the supplied schema document, including dynamic references. Unresolved references outside that document, unsupported dialects, and custom vocabularies are rejected without network I/O. Schema-invalid tool arguments skip callback invocation and return a complete tool result with `isError: true`; malformed calls and unknown or unavailable tools remain JSON-RPC errors. Invalid or unsupported registered input or output schemas, omitted structured output, and output-schema mismatches return JSON-RPC `internalError` as server-side contract failures. Explicit structured JSON `null` remains distinct from omission and is validated normally. Clients enforce the same output presence and schema checks. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/shared/json_schema_validator_test.dart`](../test/shared/json_schema_validator_test.dart), [`test/shared/json_schema_validator_io_test.dart`](../test/shared/json_schema_validator_io_test.dart), [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/server/output_validation_test.dart`](../test/server/output_validation_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/client/client_tool_validation_test.dart`](../test/client/client_tool_validation_test.dart), [`tool/testing/run_json_schema_2020_12_suite.dart`](../tool/testing/run_json_schema_2020_12_suite.dart), [`tool/testing/run_json_schema_draft7_suite.dart`](../tool/testing/run_json_schema_draft7_suite.dart), [`tool/testing/json_schema_suite_runner.dart`](../tool/testing/json_schema_suite_runner.dart), [`tool/testing/json_schema_test_suite_ref.txt`](../tool/testing/json_schema_test_suite_ref.txt), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Published TypeScript beta.5 validates `tools/list` and `tools/call`; schema-validation and error-channel semantics plus the no-network policy are locally tested. | The MCP 2026-07-28 client suite is green; the published server suite keeps only the three exactly matched `server-stateless` pre-#3002 diagnostics. The pinned official JSON Schema Test Suite gates pass all supported assertions, while a loopback security test proves rejected network `$ref` values cause no HTTP request. | Verified with a published referee gap |
| Resource semantics | [Resources](https://modelcontextprotocol.io/specification/draft/server/resources) | Successful reads preserve typed contents and cache metadata; a missing resource returns `InvalidParams` (`-32602`) rather than an empty result. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart) | Current beta fixtures focus on discovery and tools rather than MCP 2026-07-28 resource errors. | Official `sep-2164-resource-not-found` plus resource list/read scenarios in alpha.9. | Verified |
| MRTR and elicitation | [MRTR](https://modelcontextprotocol.io/specification/draft/basic/patterns/mrtr), [Elicitation](https://modelcontextprotocol.io/specification/draft/client/elicitation) | MCP 2026-07-28 `input_required` results are emitted only for supported requests and require advertised client capabilities. URL-mode `elicitation/create` uses `mode`, `message`, and `url` without legacy `elicitationId` or `notifications/elicitation/complete`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | Published TypeScript beta.5 completes MCP 2026-07-28 `input_required` retries in both directions. | `mrtr` scenarios in alpha.9. | Verified |
| Subscriptions | [Subscriptions](https://modelcontextprotocol.io/specification/draft/basic/patterns/subscriptions), [Schema reference](https://modelcontextprotocol.io/specification/draft/schema#subscriptionslistenresult) | Every `subscriptions/listen` stream sends exactly one acknowledgment before events or completion. Its filter must be a subset of the requested filter, and later events must stay inside the acknowledged scope. Other subscription IDs may interleave on stdio. The SDK correlates through `io.modelcontextprotocol/subscriptionId`, returns the same ID on graceful close, and restores active stateless stdio subscriptions after an unexpected child exit. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/client/stdio_client_test.dart`](../test/client/stdio_client_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | Published TypeScript beta.5 validates acknowledgment and list-change notification correlation against Dart. | Subscription scenarios in alpha.9; restart recovery is transport-local. | Verified |
| Deprecated request-scoped logging and removed core RPCs | [Logging](https://modelcontextprotocol.io/specification/draft/server/utilities/logging), [Key changes](https://modelcontextprotocol.io/specification/draft/changelog) | The deprecated MCP 2026-07-28 logging wire behavior is retained for compatibility with request-scoped metadata, while removed initialization-era core RPCs and notifications are rejected in the MCP 2026-07-28 profile. Known server-to-client notifications are rejected in the client-to-server direction, but unknown notification methods remain available to negotiated extensions. Stateless HTTP cancellation closes the response stream instead of sending `notifications/cancelled`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/server_advanced_test.dart`](../test/server/server_advanced_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | Published TypeScript beta.5 validates raw removed-RPC rejection against the Dart server. | Removed-RPC and logging scenarios in alpha.9. | Verified |
| Tasks extension | [Tasks extension SEP-2663](https://tasks.extensions.modelcontextprotocol.io/seps/2663-tasks-extension) | The `io.modelcontextprotocol/tasks` extension uses base task creation seeds and exact status-specific detailed state for `tasks/get` and `notifications/tasks`. Task methods, notification subscriptions, and embedded input requests enforce per-request capabilities. Protocol-era routing keeps `tasks/update` and extension results out of legacy sessions and keeps removed legacy methods out of stateless sessions. A legacy `TaskStore` may coexist for dual-era compatibility but is never adapted into modern extension persistence. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types/tasks_extension_test.dart`](../test/types/tasks_extension_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), CLI task-extension conformance cases, [`tool/testing/mcp_2026_07_28_tasks_spec_ref.txt`](../tool/testing/mcp_2026_07_28_tasks_spec_ref.txt) | No checked-in MCP 2026-07-28 cross-SDK task-extension fixture yet. | The alpha.9 official server/client scenario lists do not cover the Tasks extension. | Local only |
| Authorization and HTTP deployment security | [Authorization](https://modelcontextprotocol.io/specification/draft/basic/authorization), [Transports](https://modelcontextprotocol.io/specification/draft/basic/transports) | Covers protected-resource and authorization-server discovery, exact raw issuer matching, bearer challenge parsing, pre-registered/CIMD/deprecated-DCR selection, HTTPS or loopback-HTTP redirect URIs, PKCE S256, callback state and issuer, supported token-endpoint authentication, issuer/resource-bound token persistence, exact Origin handling, Host validation, and safe loopback defaults. | [`test/client/oauth_2026_compliance_test.dart`](../test/client/oauth_2026_compliance_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/) | Stable TypeScript OAuth interop covers the complete protected-resource flow; current MCP 2026-07-28 beta interop has limited credentialed coverage. | All 25 alpha.9 client authorization scenarios pass; server-side deployment policy remains locally tested. | Verified |
| MCP 2026-07-28 preview public APIs | [Schema reference](https://modelcontextprotocol.io/specification/draft/schema) | APIs useful only for MCP 2026-07-28, such as non-object structured tool output and MCP 2026-07-28 protocol profiles, are documented as preview APIs. Callers can explicitly select the legacy profile when those APIs are unsuitable. | [`doc/mcp-2026-07-28.md`](mcp-2026-07-28.md), public dartdoc on protocol profiles and MCP 2026-07-28 helpers. | Not cross-SDK specific. | Covered indirectly by MCP 2026-07-28 conformance and local parser/serializer tests. | Verified |

## Known Gaps

These are gaps in external evidence unless stated otherwise; they are not known
missing core protocol behavior.

- Published `@modelcontextprotocol/conformance@0.2.0-alpha.9` predates spec
  PR #3002 and conformance PR #403, so its three stale `server-stateless`
  diagnostics are matched exactly while merged-PR-source verification is green.
- Published TypeScript SDK beta.5 includes the post-#3002 discovery identity
  shape and passes the checked-in bidirectional fixture. The temporary
  legacy-body identity reader remains for Python beta and older peers.
- Published Python SDK `mcp==2.0.0b2` also requires body
  `DiscoverResult.serverInfo`. Dart-client -> Python-server remains required
  through the same read fallback; Python-client -> Dart-server asserts its
  exact 2026 -> 2025 fallback as a self-expiring expected gap.
- The official conformance package is still alpha, so its scenario inventory
  and assertions may continue to change before the final specification tag.
  The current alpha.9 client suite passes with no expected failures; a local
  network-`$ref` security canary remains as regression coverage.
- Legacy providers may still return plain `OAuthTokens` for source
  compatibility. Those tokens do not carry issuer/resource bindings, so
  providers must persist `OAuthIssuerBoundAuthorizationCodeTokens` before
  relying on migration-safe credential reuse checks.
- The Tasks extension is locally covered but is absent from the current
  official alpha.9 scenario inventory and from checked-in MCP 2026-07-28 cross-SDK
  interop. Do not describe it as cross-SDK verified yet.
- The current core draft assigns `MissingRequiredClientCapability` code
  `-32021`, while the independently published Tasks extension draft still
  names `-32003`. The SDK follows the core error registry. Both repositories
  are pinned separately, and the stable release is blocked until the final
  texts establish one interoperable value.
- The Tasks prose calls `ttlMs` and `pollIntervalMs` integer milliseconds,
  while its generated schema currently accepts any JSON number. The SDK uses
  `int` and rejects fractional values. The separately pinned Tasks audit makes
  schema drift visible, and the stable metadata gate remains false until the
  final source resolves the mismatch or explicitly confirms integer semantics.
- The pinned Core draft is internally ambiguous about server-initiated
  subscription teardown: the cancellation page requires
  `notifications/cancelled`, the subscriptions page describes a terminal empty
  response followed by close, and the schema describes server cancellation
  specifically for stdio. The SDK currently sends cancellation before the
  terminal completion or error response on stdio, and sends the terminal
  response only on Streamable HTTP. A
  stable-release metadata gate remains false until the final texts and both
  transport paths are reconciled.
- Stable publication is also blocked by
  `releaseDocumentation.finalReleaseReviewed` until the day-of documentation
  sweep removes current preview/release-candidate language and verifies every
  public version and protocol-constant claim against the final release.
- The reverse Dart MCP 2026-07-28 client -> TypeScript SDK beta server path now covers
  discovery, `tools/list`, `tools/call`, one-time `HeaderMismatch` recovery,
  and a TypeScript-server `input_required` elicitation retry. Broader
  reverse-path coverage for subscriptions/listen, cacheable result fields, and
  other streaming/result paths should follow as the TypeScript SDK beta server
  surface stabilizes.
