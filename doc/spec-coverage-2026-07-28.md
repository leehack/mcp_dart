# MCP 2026-07-28 Specification Coverage Matrix

`mcp_dart` implements the complete core client/server wire surface of the MCP
2026-07-28 specification. This matrix indexes the high-risk and
release-changing requirements against checked-in evidence; it is not an
exhaustive inventory of every schema type or API. mcp_dart 2.3.0 defaults to
`McpProtocol.stable`, while `McpProtocol.legacy` retains the full MCP
2025-11-25 feature set and negotiates supported earlier initialization
versions.

Core means the normative wire requirements assigned to client and server roles
by the MCP 2026-07-28 specification. It excludes optional MCP
extensions, host UI behavior, an authorization-server implementation, JSON
Schema external-reference resolution, and custom JSON Schema vocabularies.

This matrix records the evidence used for the stable SDK release.

`Verified` means the row has executable local evidence plus the applicable
interop or official conformance evidence. `Local only` means checked-in Dart
coverage exists, but no current cross-SDK or official scenario covers it.

## Gates

Run the official conformance gates from the repository root:

```bash
dart run test/conformance/run_2025_server_conformance.dart
npx -y @modelcontextprotocol/conformance@0.2.0-alpha.10 client \
  --command "dart run test/conformance/mcp_2026_07_28_client.dart" \
  --suite all \
  --spec-version 2025-11-25
dart run test/conformance/run_2026_07_28_server_conformance.dart
dart run test/conformance/run_2026_07_28_client_conformance.dart
```

The alpha.10 MCP 2026-07-28 client suite passes all 25 authorization scenarios.
The published server suite includes conformance PR #403 and passes every
checked-in MCP 2026-07-28 scenario without expected failures.

CI checks out the final Core release commit pinned in
[`tool/testing/mcp_2026_07_28_spec_ref.txt`](../tool/testing/mcp_2026_07_28_spec_ref.txt).
It parses all 129 machine-readable examples and inventories all 31 official
versioned specification documents against checked-in scope, evidence, and
normalized SHA-256 content hashes. Any prose change at a new pinned revision
fails the inventory until that document is explicitly reviewed and its hash is
updated. The day-0 readiness matrix was reviewed against final Core release
commit
[`5f5440b`](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/5f5440bb26a62e2cf3440b92da5a667efa03b267).
The readable source links below remain mutable; the immutable commit keeps the
release evidence underneath a green run fixed.

The document inventory is a drift guard, not a semantic proof by itself. The
matrix, regression tests, interop fixtures, and conformance suites provide the
behavioral evidence for each claim.

Audit the final machine-readable examples and specification documents with:

```bash
dart run tool/spec_example_audit.dart \
  /path/to/modelcontextprotocol/schema/2026-07-28/examples
dart run tool/spec_document_inventory_audit.dart \
  /path/to/modelcontextprotocol/docs/specification/2026-07-28
```

Run the TypeScript SDK 2.0.0 interop gate from the repository root:

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
dart run tool/testing/run_json_schema_draft7_format_suite.dart \
  .dart_tool/json-schema-test-suite/tests/draft7/optional/format
```

The runners fail on any supported mandatory or declared-format assertion
mismatch. Their exact file, group, assertion, and exclusion manifests are
pinned so an upstream suite change or a broader policy exclusion cannot pass
silently. At the pinned revision, the Draft 2020-12 gate evaluates 1,244
supported assertions and the
Draft 7 compatibility gate evaluates 904 supported assertions across 37 files
and 257 groups. Its separate format gate evaluates all 587 assertions across
18 files and 20 groups. The Draft 7 gate excludes exactly 11 external-reference
groups and no unsupported-dialect or invalid-schema groups.

CI runs the official conformance gates in the core workflow. The
`Run MCP 2026-07-28 Interop` workflow runs the TypeScript SDK 2.0.0 and Python
SDK 2.0.0 interop fixtures on relevant PRs, manual dispatch, and the daily
`main` schedule.

## Matrix

| Spec area | Official source | Requirement tracked here | Local coverage | Cross-SDK coverage | Official conformance | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Default stable profile with legacy opt-out | [Versioning and compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning), [stdio backward compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio#backward-compatibility) | The 2.3 line defaults to `McpProtocol.stable`. Current source bounds silent discovery on body-only transports to five seconds before legacy fallback; if a stdio server exits during that probe, the transport starts a fresh child before `initialize`. HTTP keeps its normal request timeout. Callers can explicitly select `McpProtocol.legacy` or `McpProtocol.require2026`. | [`test/client/client_test.dart`](../test/client/client_test.dart), [`test/client/stdio_client_test.dart`](../test/client/stdio_client_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`doc/mcp-2026-07-28.md`](mcp-2026-07-28.md) | TypeScript SDK 2.0.0 interop covers explicit MCP 2026-07-28 negotiation; local tests cover the default-option, silent-legacy-server, process-exit fallback, and strict no-fallback paths. | MCP 2025-11-25 and MCP 2026-07-28 conformance both run in CI. | Verified |
| Version negotiation and discovery | [Discovery](https://modelcontextprotocol.io/specification/2026-07-28/server/discover), [Versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning) | Servers implement `server/discover`, advertise supported versions and capabilities, reject unsupported versions with structured error data, and clients retry or fall back according to transport-era rules. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart), [`test/conformance/mcp_2026_07_28_client.dart`](../test/conformance/mcp_2026_07_28_client.dart) | Published TypeScript SDK 2.0.0 and Python SDK 2.0.0 pass both directions on the post-#3002 wire. Dart retains read-only legacy-body compatibility for older prerelease peers. | Published alpha.10 includes conformance PR #403 and passes the post-#3002 discovery semantics. | Verified |
| Stateless request metadata | [Overview](https://modelcontextprotocol.io/specification/2026-07-28/basic), [Versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning) | Every MCP 2026-07-28 request carries protocol version and client capabilities in `_meta`; client identity is optional, while a present malformed identity is rejected. Servers do not infer protocol state from a prior request. Non-MCP metadata remains opaque and is preserved. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | Published TypeScript SDK 2.0.0 and conformance alpha.10 cover identified and anonymous requests. | Published alpha.10 accepts omitted `clientInfo`; `server-stateless` passes without an expected failure. | Verified |
| Stateless result identity | [Schema reference](https://modelcontextprotocol.io/specification/2026-07-28/schema) | `McpServer` stamps its configured identity by default in successful MCP 2026-07-28 result `_meta["io.modelcontextprotocol/serverInfo"]`. A valid handler-authored value wins, `null` omits the optional key, and malformed non-null output is rejected before serialization. Discovery has no body `serverInfo`; missing canonical identity is anonymous, while a present malformed or `null` canonical value is rejected. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types_test.dart`](../test/types_test.dart) cover discovery, list/tool/task/subscription metadata merging, handler precedence, anonymous identity, malformed output, and legacy isolation. | Published TypeScript SDK 2.0.0 and Python SDK 2.0.0 validate the final result metadata shape in both directions. Dart reads legacy discovery-body identity from older prerelease peers and ignores malformed values in that obsolete location. | Published alpha.10 checks canonical discovery identity metadata. | Verified |
| JSON-RPC envelopes and errors | [Base protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic) | String and integer request IDs retain their wire identity, arbitrary JSON-RPC error `data` remains observable, and unknown metadata is preserved. | [`test/types_edge_cases_test.dart`](../test/types_edge_cases_test.dart), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Cross-SDK fixtures exercise normal success and error envelopes. | Error and malformed-request scenarios in alpha.10. | Verified |
| Streamable HTTP routing headers | [Key changes](https://modelcontextprotocol.io/specification/2026-07-28/changelog), [Transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports) | MCP 2026-07-28 HTTP POST requests include required protocol, method, name, and parameter-routing headers; mismatches reject with routing-header errors. A `HeaderMismatch` refreshes `tools/list` metadata before one retry. Stateless SSE responses preserve browser CORS headers. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | Published TypeScript SDK 2.0.0 validates `x-mcp-header` mirroring and raw rejection against Dart; its server validates Dart's schema-refresh retry. Chrome validates the real cross-origin path. | `stateless-http.requires-routing-headers`, `stateless-http.validates-parameter-headers`, and related alpha.10 cases. | Verified |
| Removed session and resumability behavior | [Key changes](https://modelcontextprotocol.io/specification/2026-07-28/changelog) | MCP 2026-07-28 Streamable HTTP omits protocol-level sessions, rejects removed GET/DELETE behaviors, JSON-RPC batches, and client response/error POSTs, and cancels a stateless request by closing only that POST response stream without legacy notification redelivery. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/browser/mcp_2026_07_28_streamable_http_test.dart`](../test/browser/mcp_2026_07_28_streamable_http_test.dart) | Published TypeScript SDK 2.0.0 verifies request cancellation and recovery in both directions. Loopback HTTP and real Chrome add sibling isolation and cleanup coverage. Python cancellation is not yet covered. | `stateless-http.rejects-non-post-methods`, `stateless-http.rejects-batch-payloads`, and related alpha.10 cases. | Verified |
| Cacheable results and deterministic lists | [Caching](https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching), [Discovery](https://modelcontextprotocol.io/specification/2026-07-28/server/discover) | `server/discover`, list, and read responses include `resultType`, `ttlMs`, and `cacheScope`; completed `resources/read` MRTR retries are forced immediately stale and private even when a handler supplies reusable hints. Stateless `tools/list` is deterministic and omits initialization-era-only tool execution metadata. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart) | Published TypeScript SDK 2.0.0 checks discovery and `tools/list` cache metadata. | Cacheable-result and tools-list scenarios in alpha.10. | Verified |
| Tools and JSON Schema 2020-12 | [Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools), [Overview JSON Schema usage](https://modelcontextprotocol.io/specification/2026-07-28/basic) | Tool schemas preserve JSON Schema 2020-12 constructs, including nested boolean schemas; MCP 2025-11-25 root-object compatibility remains intact. The built-in validator defaults to Draft 2020-12, accepts an explicitly declared Draft 7 schema for MCP 2025-11-25 compatibility, and synchronously resolves local fragments plus absolute or relative identifiers that stay inside the supplied schema document, including dynamic references. Unresolved references outside that document and unsupported dialects are rejected without network I/O; custom vocabularies are preserved but not interpreted. Schema-invalid tool arguments skip callback invocation and return a complete tool result with `isError: true`; malformed calls and unknown or unavailable tools remain JSON-RPC errors. Invalid or unsupported registered input or output schemas, omitted structured output, and output-schema mismatches return JSON-RPC `internalError` as server-side contract failures. Explicit structured JSON `null` remains distinct from omission and is validated normally. Clients enforce the same output presence and schema checks. | [`test/tool_schema_test.dart`](../test/tool_schema_test.dart), [`test/shared/json_schema_validator_test.dart`](../test/shared/json_schema_validator_test.dart), [`test/shared/json_schema_validator_io_test.dart`](../test/shared/json_schema_validator_io_test.dart), [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/server/output_validation_test.dart`](../test/server/output_validation_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/client/client_tool_validation_test.dart`](../test/client/client_tool_validation_test.dart), [`tool/testing/run_json_schema_2020_12_suite.dart`](../tool/testing/run_json_schema_2020_12_suite.dart), [`tool/testing/run_json_schema_draft7_suite.dart`](../tool/testing/run_json_schema_draft7_suite.dart), [`tool/testing/run_json_schema_draft7_format_suite.dart`](../tool/testing/run_json_schema_draft7_format_suite.dart), [`tool/testing/json_schema_suite_runner.dart`](../tool/testing/json_schema_suite_runner.dart), [`tool/testing/json_schema_test_suite_ref.txt`](../tool/testing/json_schema_test_suite_ref.txt), [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart) | Published TypeScript SDK 2.0.0 validates `tools/list` and `tools/call`; schema-validation and error-channel semantics plus the no-network policy are locally tested. | Both published alpha.10 client and server suites are green. The pinned official JSON Schema gates pass all 1,244 supported Draft 2020-12 assertions, 904 Draft 7 mandatory assertions, and 587 Draft 7 format assertions, while a loopback security test proves rejected network `$ref` values cause no HTTP request. | Verified |
| Resource semantics | [Resources](https://modelcontextprotocol.io/specification/2026-07-28/server/resources) | Successful reads preserve typed contents and cache metadata; a missing resource returns `InvalidParams` (`-32602`) rather than an empty result. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/mcp_server_test.dart`](../test/server/mcp_server_test.dart), [`test/types/resources_test.dart`](../test/types/resources_test.dart) | Current peer fixtures focus on discovery and tools rather than MCP 2026-07-28 resource errors. | Official `sep-2164-resource-not-found` plus resource list/read scenarios in alpha.10. | Verified |
| MRTR and elicitation | [MRTR](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr), [Elicitation](https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation) | MCP 2026-07-28 `input_required` results are emitted only for supported requests and require advertised client capabilities. URL-mode `elicitation/create` uses `mode`, `message`, and `url` without legacy `elicitationId` or `notifications/elicitation/complete`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/elicitation_test.dart`](../test/elicitation_test.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | Published TypeScript SDK 2.0.0 completes MCP 2026-07-28 `input_required` retries in both directions. | `mrtr` scenarios in alpha.10. | Verified |
| Subscriptions | [Subscriptions](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions), [Schema reference](https://modelcontextprotocol.io/specification/2026-07-28/schema#subscriptionslistenresult) | Every `subscriptions/listen` stream sends exactly one acknowledgment before events or completion. Its filter must be a subset of the requested filter, and later events must stay inside the acknowledged scope. Other subscription IDs may interleave on stdio. The SDK correlates through `io.modelcontextprotocol/subscriptionId`, returns the same ID on graceful close, and restores active stateless stdio subscriptions after an unexpected child exit. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/client/stdio_client_test.dart`](../test/client/stdio_client_test.dart), [`test/conformance/mcp_2026_07_28_server.dart`](../test/conformance/mcp_2026_07_28_server.dart), [`example/mcp_2026_07_28/`](../example/mcp_2026_07_28/) | Published TypeScript SDK 2.0.0 validates acknowledgment and list-change notification correlation against Dart. | Subscription scenarios in alpha.10; restart recovery is transport-local. | Verified |
| Deprecated request-scoped logging and removed core RPCs | [Logging](https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/logging), [Key changes](https://modelcontextprotocol.io/specification/2026-07-28/changelog) | The deprecated MCP 2026-07-28 logging wire behavior is retained for compatibility with request-scoped metadata, while removed initialization-era core RPCs and notifications are rejected in the MCP 2026-07-28 profile. Known server-to-client notifications are rejected in the client-to-server direction, but unknown notification methods remain available to negotiated extensions. Stateless HTTP cancellation closes the response stream instead of sending `notifications/cancelled`. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/server/server_advanced_test.dart`](../test/server/server_advanced_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart) | Published TypeScript SDK 2.0.0 validates raw removed-RPC rejection against the Dart server. | Removed-RPC and logging scenarios in alpha.10. | Verified |
| Experimental Tasks extension | [Tasks extension SEP-2663](https://tasks.extensions.modelcontextprotocol.io/seps/2663-tasks-extension) | The experimental, non-official `io.modelcontextprotocol/tasks` extension uses base task creation seeds and exact status-specific detailed state for `tasks/get` and `notifications/tasks`. Task methods, notification subscriptions, and embedded input requests enforce per-request capabilities. Protocol-era routing keeps `tasks/update` and extension results out of legacy sessions and keeps removed legacy methods out of stateless sessions. A legacy `TaskStore` may coexist for dual-era compatibility but is never adapted into modern extension persistence. | [`test/mcp_2026_07_28_test.dart`](../test/mcp_2026_07_28_test.dart), [`test/types/tasks_extension_test.dart`](../test/types/tasks_extension_test.dart), [`test/client/task_client_test.dart`](../test/client/task_client_test.dart), [`test/server/server_test.dart`](../test/server/server_test.dart), [`test/server/streamable_https_test.dart`](../test/server/streamable_https_test.dart), CLI task-extension conformance cases, [`tool/testing/mcp_2026_07_28_tasks_spec_ref.txt`](../tool/testing/mcp_2026_07_28_tasks_spec_ref.txt) | No checked-in MCP 2026-07-28 cross-SDK task-extension fixture yet. | The alpha.10 official server/client scenario lists do not cover the Tasks extension. | Experimental; local only |
| Authorization and HTTP deployment security | [Authorization](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization), [Transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports) | Covers protected-resource and authorization-server discovery, exact raw issuer matching, bearer challenge parsing, pre-registered/CIMD/deprecated-DCR selection, HTTPS or loopback-HTTP redirect URIs, PKCE S256, callback state and issuer, supported token-endpoint authentication, issuer/resource-bound token persistence, exact Origin handling, Host validation, and safe loopback defaults. | [`test/client/oauth_2026_compliance_test.dart`](../test/client/oauth_2026_compliance_test.dart), [`test/client/streamable_https_test.dart`](../test/client/streamable_https_test.dart), [`test/server/streamable_security_harness_test.dart`](../test/server/streamable_security_harness_test.dart), [`test/server/streamable_mcp_server_test.dart`](../test/server/streamable_mcp_server_test.dart), [`test/example/oauth_client_example_test.dart`](../test/example/oauth_client_example_test.dart), [`example/authentication/`](../example/authentication/) | Stable TypeScript OAuth interop covers the complete protected-resource flow; current MCP 2026-07-28 peer interop has limited credentialed coverage. | All 25 alpha.10 client authorization scenarios pass; server-side deployment policy remains locally tested. | Verified |
| MCP 2026-07-28 public APIs | [Schema reference](https://modelcontextprotocol.io/specification/2026-07-28/schema) | APIs specific to MCP 2026-07-28, such as non-object structured tool output and protocol profiles, are documented as stable APIs. Callers can explicitly select the legacy profile when those APIs are unsuitable. | [`doc/mcp-2026-07-28.md`](mcp-2026-07-28.md), public dartdoc on protocol profiles and MCP 2026-07-28 helpers. | Not cross-SDK specific. | Covered indirectly by MCP 2026-07-28 conformance and local parser/serializer tests. | Verified |

## Known Gaps

These are gaps in external evidence unless stated otherwise; they are not known
missing core protocol behavior.

- Published TypeScript SDK 2.0.0 and Python SDK 2.0.0 include the post-#3002
  discovery identity shape and pass their checked-in bidirectional fixtures.
  The read-only legacy-body identity reader remains for older prerelease peers.
- The official conformance package is still alpha, so its scenario inventory
  and assertions may continue to change independently of the specification.
  The current alpha.10 client and server suites pass with no expected failures,
  including the MCP 2026-07-28 network-`$ref` security canary.
- Legacy providers may still return plain `OAuthTokens` for source
  compatibility. Those tokens do not carry issuer/resource bindings, so
  providers must persist `OAuthIssuerBoundAuthorizationCodeTokens` before
  relying on migration-safe credential reuse checks.
- The Tasks extension is experimental and not an official MCP extension. It is
  locally covered but absent from the current official alpha.10 scenario
  inventory and from checked-in MCP 2026-07-28 cross-SDK interop. Do not
  describe it as stable, official, or cross-SDK verified.
- The final Core release assigns `MissingRequiredClientCapability` code
  `-32021`, while the experimental Tasks extension draft names `-32003`. The
  SDK follows the Core error registry. This known extension difference is not
  part of the stable Core interoperability claim.
- The Tasks failed-state prose describes a JSON-RPC error shape, while its
  generated schema accepts a generic JSON object. The SDK exposes
  `JsonRpcErrorData`; cross-SDK Tasks behavior is therefore not claimed.
- The Tasks prose calls `ttlMs` and `pollIntervalMs` integer milliseconds,
  while its generated schema currently accepts any JSON number. The SDK uses
  `int` and rejects fractional values. The separately pinned Tasks audit makes
  schema drift visible, and this difference is documented as experimental
  extension behavior.
- The final Core release remains internally ambiguous about server-initiated
  subscription teardown: the cancellation page requires
  `notifications/cancelled`, the subscriptions page describes a terminal empty
  response followed by close, and the schema describes server cancellation
  specifically for stdio. The SDK currently sends cancellation before the
  terminal completion or error response on stdio, and sends the terminal
  response only on Streamable HTTP. The informational
  `subscriptionTermination.finalTextsAgree` field remains false until later
  upstream texts and both transport paths are reconciled; the checked-in wire
  behavior and regression tests define the current release contract.
- The reverse Dart MCP 2026-07-28 client -> TypeScript SDK 2.0.0 server path covers
  discovery, `tools/list`, `tools/call`, one-time `HeaderMismatch` recovery,
  and a TypeScript-server `input_required` elicitation retry. Broader
  reverse-path coverage for subscriptions/listen, cacheable result fields, and
  other streaming/result paths should follow as the TypeScript SDK server
  surface evolves.
