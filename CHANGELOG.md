## Unreleased

### Platform support

- Inherited the stable 2.2.2 web/WASM-safe default export path, preserving
  Dart IO native exports while working around pub.dev/pana 0.23.13 WASM
  platform scoring for conditional exports.

### Conformance and interoperability

- Updated official conformance gates to
  `@modelcontextprotocol/conformance@0.2.0-alpha.9`, including the stricter
  `MissingRequiredClientCapability` `requiredCapabilities` object assertion in
  the 2026 stateless server suite.
- Updated the TypeScript SDK 2026-07-28 RC interop fixture to published
  `@modelcontextprotocol/client@2.0.0-beta.3` and
  `@modelcontextprotocol/server@2.0.0-beta.3` packages after verifying both
  Dart -> TypeScript and TypeScript -> Dart 2026 draft/RC paths.
- Expanded the reverse Dart 2026 client -> TypeScript SDK beta server fixture
  with a 2026 `input_required` elicitation retry flow.
- Aligned MCP `2026-07-28` draft URL elicitation with the current draft
  schema: URL-mode `elicitation/create` no longer emits or accepts
  `elicitationId`, and `notifications/elicitation/complete` is treated as a
  legacy/non-draft notification rather than a typed draft notification.
- Re-pinned the TypeScript SDK 2026-07-28 RC interop fixture from `pkg.pr.new`
  previews to published `@modelcontextprotocol/client@2.0.0-beta.1` and
  `@modelcontextprotocol/server@2.0.0-beta.1` packages after verifying both
  Dart -> TypeScript and TypeScript -> Dart 2026 draft/RC paths.
- Updated official conformance gates to
  `@modelcontextprotocol/conformance@0.2.0-alpha.8`, adding the new stateless
  diagnostic probes for missing client capabilities, response-stream shape, and
  request-scoped logging. The 2026-07-28 RC server suite now has no expected
  failures; the 2026 client suite keeps only the upstream
  `json-schema-ref-no-deref` fixture gap expected.
- Added a dedicated CI workflow for the TypeScript SDK 2026-07-28 RC beta
  interop fixture on relevant PRs, `dev/2026-07-28-rc` pushes, daily schedule,
  and manual dispatch.
- Added an MCP 2026-07-28 draft/RC spec coverage matrix that maps the opt-in
  profile to official conformance, local tests, and TypeScript SDK beta interop.
- Switched the reverse Dart 2026 client -> TypeScript SDK beta server fixture
  to the TypeScript SDK's 2026 HTTP handler entry, making `server/discover`,
  `tools/list`, and `tools/call` strict interop checks instead of diagnostic
  skips.
- Recorded overridden conformance package names in 2026-07-28 RC summary artifacts so
  ad hoc package-bump checks are auditable.
- Added `SubscriptionsListenResult` for graceful `subscriptions/listen` closure
  and now include the required `io.modelcontextprotocol/subscriptionId` metadata
  in Dart server responses and client `McpSubscription.done` results.
- Cleaned up root analyzer coverage for standalone example packages and opted
  Streamable HTTP, Flutter/Jaspr web client, and MCP Apps examples into the
  `2026-07-28` preview protocol profile with stable fallback where applicable.
- Broadened preview client discovery fallback so servers that implement
  `server/discover` but advertise only stable protocol versions can still
  connect through the stable `initialize` flow.

## 2.3.0-dev.1

This dev preview refreshes MCP `2026-07-28` draft/RC support while keeping MCP
`2025-11-25` as the default protocol profile.

### MCP 2026-07-28 draft/RC refresh

- Aligned draft protocol-defined error codes with the live draft:
  `HeaderMismatch` is now `-32020`,
  `MissingRequiredClientCapability` is now `-32021`, and
  `UnsupportedProtocolVersion` is now `-32022`.
- Marked `server/discover` as a 2026 cacheable result so stateless responses
  include default `ttlMs` and `cacheScope` hints.
- Removed the legacy `DRAFT-2026-v1` draft alias now that official conformance
  targets the `2026-07-28` wire version.
- Ported the JSON Schema boolean-subschema preservation fix onto the RC dev
  line, including legacy tool-schema shims.

### Conformance and interoperability

- Updated official conformance gates to
  `@modelcontextprotocol/conformance@0.2.0-alpha.4`, with full 2026-07-28 RC server
  scenario coverage and alpha.4's spec-filtered 2026 client scenario list in CI.
- Expanded the manual TypeScript SDK 2026-07-28 RC interop fixture pinned to the
  upstream PR #2327 preview package, covering modern negotiation,
  `server/discover` cache metadata, `tools/list`, `tools/call`,
  `x-mcp-header` mirroring, progress notifications, raw HTTP header validation,
  unsupported-version and removed core RPC rejection, `subscriptions/listen`,
  and Streamable HTTP SSE cancellation.
- Added a diagnostic Dart preview client -> TypeScript server alpha path and
  documented the current TS alpha gaps around mandatory `server/discover` and
  stateless `resultType` responses.

## 2.3.0-dev.0

This is a dev preview for MCP `2026-07-28` draft/RC support. MCP
`2025-11-25` remains the default protocol profile; draft/RC behavior is enabled
explicitly and may still change before the official spec release.

### MCP 2026-07-28 draft/RC preview

- Added `McpProtocol.preview2026` and `McpProtocol.require2026` profiles for
  clients and servers, with stable `initialize` behavior preserved by default.
- Added `server/discover` negotiation, per-request stateless metadata,
  protocol/client/capability validation, and version-aware fallback behavior.
- Added stateless Streamable HTTP behavior for POST-only requests, no
  `Mcp-Session-Id`, `Mcp-Name` task routing, `Mcp-Param-*` argument headers,
  CORS preflights, SSE cancellation, and request-scoped logging.
- Added draft-only flows for `subscriptions/listen`, MCP Tasks extension
  handlers, MRTR `input_required` results, cacheable list/read results, and
  `input_required` prompt/resource responses.
- Added explicit typed APIs for non-object draft result data, including
  `JsonValue`, `structuredContentJson`,
  `CallToolResult.fromStructuredArray()`, and server `outputJsonSchema`.

### Stable compatibility

- Kept stable public tool-result APIs object-rooted and omitted non-object
  structured output from stable MCP `2025-11-25` responses.
- Preserved stable session behavior, registration-order list output, legacy task
  augmentation, stable-only `Tool.execution` metadata, and legacy resource error
  codes outside the 2026 stateless profile.
- Preserved numeric JSON-RPC request IDs and progress tokens end-to-end while
  continuing to reject non-finite numeric values.

### Spec hardening

- Tightened JSON-RPC envelope parsing, wrapper constant checks, error object
  validation, `_meta` key validation, and mixed request/response rejection.
- Accepted and preserved JSON Schema 2020-12 boolean subschemas in nested
  schema positions such as object properties, array items, composition
  keywords, and `not`.
- Tightened typed parsing for content, resources, prompts, tools, roots,
  sampling, elicitation, tasks, subscriptions, completions, capabilities, and
  JSON Schema fields so malformed wire values fail with protocol errors instead
  of Dart cast errors.
- Validated JSON-only metadata and result data across JSON-RPC, MRTR, task,
  subscription, sampling, tool, resource, and content boundaries.

### Conformance and release readiness

- Added official MCP `2025-11-25` and MCP `2026-07-28` draft/RC client/server
  conformance gates to core CI.
- Added `tool/spec_example_audit.dart` for parsing upstream machine-readable
  spec examples through checked-in SDK types during RC/final release audits.
- Prepared the dev release workflow so prerelease tags are GitHub prereleases,
  publish jobs run `dart pub publish --dry-run`, and the draft/RC transition
  guide includes a dev release checklist.
- Pointed prerelease package documentation links at `dev/2026-07-28-rc` so
  pub.dev users see the draft/RC docs that match the dev package.

## 2.2.2

### Platform support

- Made the package barrel's default export path web/WASM-safe while preserving
  Dart IO native exports, working around pub.dev/pana 0.23.13 WASM platform
  scoring for conditional exports.

## 2.2.1

### Spec Alignment

- Accepted and preserved JSON Schema 2020-12 boolean subschemas in nested
  schema positions such as object properties, array items, composition
  keywords, and `not`.

## 2.2.0

### Documentation

- Added interoperability, Flutter recipe, and migration cookbook guides, and expanded MCP Apps example guidance with host compatibility notes.
- Added an MCP 2025-11-25 spec coverage matrix that maps high-risk
  requirements to unit tests, TypeScript interop tests, CLI conformance cases,
  and known follow-up gaps.
- Added deployment-oriented security coverage for Streamable HTTP Host/Origin
  allowlists, auth gating, compatibility-toggle trade-offs, and OAuth PKCE S256
  example flow, including TypeScript SDK OAuth interop coverage.
- Documented first-class OAuth protected-resource metadata and bearer challenge
  support for `StreamableMcpServer`.
- Refreshed example documentation for current stdio, weather, Streamable HTTP,
  Flutter, Jaspr, and MCP Apps flows, including non-credentialed smoke commands.
- Refreshed additional guide snippets for request timeouts, task capability
  pre-advertisement, progress reporting, local documentation links, and
  documented `dart run` targets.
- Improved pub.dev discoverability metadata with a clearer package
  description, documentation link, topics, platform declarations, and package
  page summary copy.

### Spec Alignment

- Preserved the MCP `Result._meta` field across typed result serializers,
  including initialization, roots, resources, prompts, completion, elicitation,
  tools, tasks, sampling, and empty results.
- Aligned stable completions support with MCP 2025-11-25 by advertising
  `{"completions": {}}` and moving the old completion list-changed helper to an
  explicit experimental notification namespace.
- Aligned URL-mode elicitation responses with MCP 2025-11-25: URL accept
  results now serialize only the user `action`, while completion still uses
  `notifications/elicitation/complete`. `ElicitResult.fromJson()` now rejects
  actions outside `accept`, `decline`, and `cancel`.
- Changed titled `JsonEnum` output to JSON Schema 2020-12-native `oneOf` or
  array-item `anyOf` const/title entries while continuing to parse legacy
  `enumNames` payloads.
- Added first-class MCP OAuth client discovery for
  `StreamableHttpClientTransport` through optional
  `OAuthAuthorizationCodeProvider` support: bearer challenge parsing,
  protected-resource metadata discovery, authorization-server/OIDC metadata
  discovery, PKCE S256 authorization URLs with `resource`, and token exchange
  with `code_verifier` and `resource`.
- Added `OAuthAuthorizationCodeTokens` for token response metadata returned by
  the authorization-code exchange path without changing the base `OAuthTokens`
  API shape used by existing providers and subclasses.
- Added `StreamableMcpAuthenticationResult` for high-level Streamable HTTP
  servers that need to distinguish allow, unauthorized, and OAuth
  `insufficient_scope` 403 responses while preserving the existing bool
  `authenticator` path.
- Tightened MCP/JSON-RPC boundary validation for request IDs, progress tokens,
  cancellation request IDs, and sampling tool-use capability gating so malformed
  wire values and unsupported `sampling.tools` requests fail before handler code
  runs.
- Added optional `StreamableMcpServer` OAuth protected-resource support that
  serves OAuth Protected Resource Metadata and returns spec-shaped
  `WWW-Authenticate: Bearer ... resource_metadata=...` challenges for failed
  authentication, including an explicit public metadata URL for reverse-proxy
  deployments, while preserving legacy generic-auth `403` behavior when the
  option is not configured.
- Enforced MCP task related-metadata and progress rules by overwriting
  reserved related-task metadata from the SDK's source task id, preserving
  unrelated handler metadata, and rejecting repeated/decreasing progress values
  before sending invalid progress notifications.
- Added MCP `completion/complete` wire support for
  `context.arguments` and `PromptReference.title`, including context-aware
  server completion callbacks for prompt and resource-template completions.
- Enforced explicit task-augmented request negotiation via `tasks.requests.*`:
  task-based tool calls require `tasks.requests.tools.call`, server-initiated
  task sampling requires `tasks.requests.sampling.createMessage`, and
  server-initiated task elicitation requires `tasks.requests.elicitation.create`.
- Enforced MCP lifecycle ordering for incoming protocol messages: servers now
  reject operation requests before `initialize` and before
  `notifications/initialized`, and clients now reject server-initiated operation
  requests before sending `notifications/initialized`.
- Validated `elicitation/create` parameters as the MCP 2025-11-25 form/URL
  union, including URL-only client handler registration and unsupported
  elicitation-mode rejection.
- Added MCP 2025-11-25 stable metadata coverage for `Resource.size`,
  `Root._meta`, stable `icons`, resource annotations, and tool annotations.
  Legacy singular `icon` fields and non-stable annotation helper fields remain
  parse-compatible but are no longer emitted on stable schema objects.
- Enforced stable `Tool.inputSchema` and `Tool.outputSchema` root-object shapes
  at parse and serialization boundaries while preserving the existing
  `JsonSchema`-typed public fields for source compatibility.
- Aligned JSON-RPC response ID handling with the MCP schema: result responses
  require a string or integer `id`, error responses may omit `id`, and malformed
  response IDs fail during parsing.
- Stopped serializing non-stable server capability fields such as top-level
  `elicitation` and `tasks.listChanged`; legacy payloads still parse for
  compatibility.
- Tightened MCP form elicitation validation to require object-root
  `requestedSchema` values with primitive property schemas, restricted
  `ElicitResult.content` to spec-supported primitive values, and validated
  URL-required error data.
- Kept task `_meta` only where MCP permits result or notification metadata:
  bare nested `Task` values in task lists and task creation results no longer
  serialize `_meta`.
- Refused OAuth authorization-code discovery when the authorization server
  metadata omits `code_challenge_methods_supported` or does not advertise
  `S256`.
- Added Streamable HTTP resumability priming events so server-initiated SSE
  streams with an `EventStore` begin with an event `id` and empty `data` frame,
  matching the MCP `Last-Event-ID` reconnection guidance.

### Compatibility Notes (Potentially Breaking)

- **MCP 2025-11-25 wire validation is stricter**:
  - Stable metadata serializers no longer emit legacy singular `icon` fields,
    `ResourceAnnotations.title`, `ToolAnnotations.priority`, or
    `ToolAnnotations.audience`; those fields still parse into deprecated Dart
    accessors for one compatibility window.
  - Missing required result arrays such as `resources`, `resourceTemplates`,
    `contents`, `prompts`, `tools`, `roots`, and `tasks` now fail during
    parsing. Empty arrays remain valid when the required key is present.
  - `Tool.inputSchema`, `Tool.outputSchema`, and form elicitation
    `requestedSchema` values must serialize as root JSON objects. Primitive
    root schemas are rejected at the MCP wire boundary.
  - Successful JSON-RPC responses with `id: null` are rejected. Error responses
    may omit `id`; legacy `id: null` error payloads still parse, but serialize
    by omitting the field.
  - OAuth authorization-code discovery now requires advertised PKCE `S256`
    support; clients refuse servers that omit
    `code_challenge_methods_supported`.
- **Stable completion list-changed wire behavior is removed**:
  - `ServerCapabilitiesCompletions(listChanged: true)` remains source-compatible
    and still parses legacy payloads, but serializes as the stable MCP
    `completions: {}` capability.
  - `sendCompletionListChanged()` is deprecated and emits
    `notifications/experimental/completions/list_changed` instead of the
    non-spec stable method.
- **URL-mode elicitation result echoes are no longer emitted**:
  - Deprecated `ElicitResult.url` and `ElicitResult.elicitationId` fields remain
    parse-compatible for legacy payloads, but `toJson()` omits them.
  - Invalid `ElicitResult.action` values now fail during parsing.
- **Lifecycle and elicitation validation are stricter**:
  - Peers that send operation requests before initialization completes now
    receive `invalidRequest` errors instead of reaching request handlers.
  - Invalid form/URL `elicitation/create` parameter combinations now fail during
    parsing or serialization.
  - No public API signatures were removed or renamed; this is a behavioral
    wire-protocol compatibility change.
- **Task cancellation now returns the final task state**:
  - `tasks/cancel` responses now serialize the cancelled `Task` required by MCP
    2025-11-25 instead of an empty result object.
  - New spec-compliant APIs expose that result explicitly:
    `onCancelTaskWithResult`, `CancelTaskCallback`,
    `CancelTaskResultHandler.cancelTaskWithResult`, and
    `TaskClient.cancelTaskWithResult` return the cancelled `Task`.
  - Legacy APIs remain source-compatible for one compatibility window:
    `onCancelTask`, `ToolTaskHandler.cancelTask`, and `TaskClient.cancelTask`
    are deprecated shims. The server-side legacy shims still return a full
    cancelled `Task` on the wire by resolving the post-cancel task through
    `onGetTask`/`getTask`.
  - `TaskClient.cancelTaskWithResult` expects a task-shaped result and will
    reject older non-compliant servers that still return `{}`. Deprecated
    `TaskClient.cancelTask` remains available when callers intentionally need
    the legacy empty-result behavior.
  - `Task.fromJson()` requires MCP-required task fields (`createdAt`,
    `lastUpdatedAt`, and `ttl`), and the `Task` constructor now requires
    `ttl`, `createdAt`, and `lastUpdatedAt` so serialization is non-throwing
    for valid task instances.
  - `TaskStatusNotification.fromJson()` likewise requires the full MCP
    `NotificationParams & Task` shape (`taskId`, `status`, `ttl`, `createdAt`,
    and `lastUpdatedAt`), and task status notifications always serialize the
    required `ttl` key even when it is `null`.
  - `Task.toJson()` continues to serialize required `ttl` even when it is
    `null`, and now omits optional `pollInterval` when it is not set.
  - Task stores now treat terminal tasks (`completed`, `failed`, `cancelled`) as
    immutable, preventing later status or result overwrites.
- **Streamable HTTP session/replay semantics are stricter**:
  - Custom `sessionIdGenerator` output must now be non-empty visible ASCII
    without spaces or control characters; invalid generated IDs fail
    initialization before an `MCP-Session-Id` header is written.
  - Concurrent standalone GET SSE streams no longer receive broadcast copies of
    each server-originated message. Messages are routed to one active stream so
    resumability can preserve the MCP stream ownership boundary.
  - Custom `EventStore` implementations must return non-empty visible-ASCII SSE
    event IDs without spaces or control characters, scope `Last-Event-ID`
    replay to the owning live transport/session stream, and reject unknown or
    foreign event IDs instead of replaying unrelated stream history.

### Compatibility Notes

- **Custom transports remain source-compatible while string request routing is available**:
  - `Transport.send(... relatedRequestId: ...)` keeps the existing `int?`
    signature for third-party custom transports and middleware.
  - Transports that route by JSON-RPC request ID can opt into
    `RequestIdAwareTransport.sendWithRequestId(... relatedRequestId: ...)` to
    receive the full MCP/JSON-RPC request ID shape (`String` or `int`).
  - Middleware wrappers that implement `RequestIdAwareTransport` should forward
    through `sendPreservingRequestId(...)` so string IDs are not dropped.

### Reliability

- Scoped Streamable HTTP SSE resumability to the stream identified by
  `Last-Event-ID`, allowing multiple concurrent GET SSE streams per session
  without replaying events from unrelated streams.
- Routed each server-originated standalone GET SSE message to one active stream
  instead of broadcasting the same JSON-RPC message across concurrent streams,
  and retried another active stream when the selected target was stale.
- Returned `404 Session not found` for stale, unknown, or terminated Streamable
  HTTP session IDs across high-level and bare transports, retried client
  initialization once without a stale preconfigured session ID, refreshed stale
  sessions with single-flight reinitialization before retrying post-initialize
  requests, and stopped old SSE reconnect loops after a session reset.
- Honored `RequestOptions.resetTimeoutOnProgress` and `maxTotalTimeout` together
  so progress notifications can reset inactivity timers without bypassing the
  absolute total timeout cap.
- Supported string progress tokens end-to-end for outgoing requests that supply
  a custom `progressToken`, while preserving generated integer tokens for the
  default `RequestOptions.onprogress` path.
- Preserved string JSON-RPC request IDs when handler code sends nested requests,
  notifications, or cancellation notifications, keeping related-request routing
  compatible with clients that use string IDs.
- Improved JSON Schema parsing and validation for `const`, enum-only schemas,
  titled enum `const` entries, and simple `type` array unions such as nullable
  schemas.
- Fixed browser example interoperability by allowing the MCP protocol-version
  header in CORS preflight responses, mapping Flutter prompt input to advertised
  prompt arguments, and using typed DOM inputs in the Jaspr client.

### Tooling

- Added `mcp_dart conformance` with built-in JSON-RPC and protocol-version fixture checks, deterministic JSON-RPC fuzz cases, exact-case filtering, and JSON output for CI/scripts.
- Added a `mcp_dart conformance --suite spec` gate for MCP 2025-11-25
  lifecycle, capability, elicitation, task-metadata, and progress-token
  raw-wire checks.
- CI now runs `mcp_dart conformance --suite all --json` so JSON-RPC and
  protocol-version fixtures are checked with the spec suite.
- Added local non-credentialed example smoke tests for stdio, iostream,
  required-field schema preservation, CLI inspect, completions, and MCP Apps
  metadata examples.
- Added Markdown documentation guards for broken local links and documented
  `dart run` targets.

## 2.1.1

### Compatibility Notes (Potentially Breaking)

- **`JsonEnum` wire format is now standard JSON Schema**:
  - `JsonEnum.toJson()` emits standard JSON Schema enum forms instead of the legacy
    `type: 'enum'` / `values` shape.
  - Legacy serialized enum input using `values` is still accepted when parsing.

### Reliability

- Fixed `JsonEnum` tool/input schema serialization to use standard JSON Schema enum output,
  improving compatibility with downstream consumers that reject the legacy
  `type: 'enum'` / `values` shape.
- Serialized concurrent stdio transport writes so overlapping requests no longer
  trip Dart `IOSink` write/flush errors.

### Documentation

- Updated installation snippets and schema/stdio transport guidance for the 2.1.1 release.

## 2.1.0

### Compatibility Notes (Potentially Breaking)

- **Streamable HTTP defaults are stricter**:
  - DNS rebinding protection is enabled by default for Streamable HTTP server entry points.
  - Unsupported `MCP-Protocol-Version` request headers are rejected by default.
  - JSON-RPC batch POST payloads are rejected by default.
  - Use compatibility toggles to preserve legacy behavior during rollout:
    - `strictProtocolVersionHeaderValidation: false`
    - `rejectBatchJsonRpcPayloads: false`
    - `enableDnsRebindingProtection: false`
- **Sampling response shape can now be multi-block**:
  - `SamplingMessage.content` and `CreateMessageResult.content` may be either a single block or a list.
  - Prefer normalized access via `contentBlocks`.
- **Enum expansion**:
  - `StopReason` now includes `toolUse`; exhaustive `switch` statements may need an additional branch.

### Features

- Added SDK runtime logging helper APIs: `setMcpLogHandler`, `resetMcpLogHandler`, and `silenceMcpLogs`.
- Added `Logger.resetHandler()` to restore the default internal log output.
- Added backward-compatible sampling/content API shims while keeping 2025-11-25 wire-format compliance:
  - `CreateMessageRequest.toolChoice` supports legacy map and typed `ToolChoice`
  - `SamplingMessage.content` and `CreateMessageResult.content` accept single or array content forms with normalized `contentBlocks` access
  - `ResourceLink.annotations` supports map form with typed `parsedAnnotations` accessor
- Added Streamable HTTP compatibility toggles:
  - `strictProtocolVersionHeaderValidation`
  - `rejectBatchJsonRpcPayloads`
- Added related-task metadata compatibility behavior by dual-writing
  `io.modelcontextprotocol/related-task` and legacy `relatedTask` keys.

### Documentation

- Added runtime logging guidance with `package:logging` integration examples using import aliases.
- Updated transport logging middleware examples to match SDK logger methods (`debug/info/warn/error`).
- Added `doc/migration_2025_11_25_compat.md` with compatibility-mode and API migration guidance.
- Updated transport/client/quick-reference docs for strict defaults and compatibility toggles.

### Reliability

- Fixed Streamable HTTP `Accept` header parsing to handle repeated/multi-value headers without throwing `HttpException`, improving compatibility with clients that send duplicated or split `Accept` values.
- Centralized DNS rebinding validation across Streamable HTTP and legacy SSE server entry points.
- Added interop coverage for Dart/TypeScript sampling flows (`sampling.tools` capability and tool-choice propagation).

## 2.0.0

### Breaking Changes

- **JSON Schema API**:
  - `JsonObject.additionalProperties` and `JsonSchema.object(additionalProperties: ...)` now use `Object?` instead of `bool?`.
  - `additionalProperties` may now be either `bool` or `JsonSchema`, matching the JSON Schema specification.

### Features

- **MCP Apps Support**:
  - Added typed MCP Apps metadata models and helpers (`McpUiToolMeta`, `McpUiResourceMeta`, `McpUiCsp`, `McpUiPermissions`) with extension capability helpers for `io.modelcontextprotocol/ui`.
  - Added TypeScript-style server helpers (`registerAppTool`, `registerAppResource`, `getUiCapability`) and metadata normalization for `_meta.ui.resourceUri` and legacy `_meta['ui/resourceUri']`.
  - Added MCP Apps server examples for helper-based and manual metadata wiring.

### Compatibility

- **Host Rendering**:
  - Updated MCP Apps weather examples to use host-safe tool names (`weather_get_current`), include explicit `resource_link` tool output, and demonstrate host-rendered UI updates from tool input/result notifications.

### Documentation

- Added and expanded MCP Apps documentation across guides and quick reference, including host compatibility guidance for tool naming constraints.

### Reliability

- **JSON Schema Parsing**:
  - Fixed `JsonObject.fromJson` to accept untyped map values for `additionalProperties` (for example `{}` decoded as `Map<dynamic, dynamic>`), so schema objects are not silently dropped.

## 1.3.0

- **Spec Alignment**:
  - Added `ResourceLink` (`resource_link`) content type support.
  - Added icon metadata support with `McpIcon`, `IconTheme`, and optional `icons` fields across tools/prompts/resources/templates.
  - Added `ResourceAnnotations.lastModified` (ISO 8601).
  - Added MCP `extensions` capability support for client/server initialization capability negotiation.
- **Security**:
  - Added optional DNS rebinding protection to streamable HTTP/SSE server entry points via host/origin allowlists.
- **Reliability**:
  - Tightened null handling for JSON-RPC tool params and task store TTL parsing paths.
  - Fixed URI template matching for RFC 6570 multi-variable operators (for example `{?status,assignee}`) so `resources/read` resolves templated URIs correctly.
  - Fixed tool metadata passthrough so registered `meta` (including nested `_meta` values) is preserved in `tools/list` responses.
  - Improved URI template variable typing and protocol cancellation reason typing.
- **Docs**:
  - Updated transport, client, server, tools, and quick-reference docs for new fields and security options.

## 1.2.2

- Fix pana analysis issues

## 1.2.1

- **Features**:
  - **Progress Notifications**: Implemented full support for progress tracking.
    - Added `RequestHandlerExtra.sendProgress()` helper for servers to report progress.
    - Added `RequestOptions.onprogress` callback for clients to receive progress updates.
    - Updated `Progress` and `ProgressNotification` types to include optional `message` field (compliant with 2025-11-25 spec).
  - **Protocol Improvements**:
    - `JsonRpcMessage.fromJson` now supports custom/unknown methods instead of throwing.
    - Fixed `JsonRpcRequest` metadata extraction to correctly handle nested `_meta` in `params`.
    - Updated `ToolAnnotations` to make `title` optional, preventing deserialization errors when the field is missing.

- **Fixes**:
  - **StreamableHTTP**: Prevented the client from attempting to "reconnect" to short-lived POST response streams (used for tool calls). This fixes an issue where multiple tool calls could exhaust the browser's connection limit by spawning zombie reconnection attempts.

- **Examples**:
  - **New Jaspr Client**: Added a comprehensive web client example (`example/jaspr-client`) built with Jaspr, featuring:
    - Interactive UI for Tools, Resources, Prompts, and Tasks.
    - Real-time connection management.
    - Visual task progression and sampling dialogs.
  - **Anthropic Client**: Fixed issues in the Anthropic client example.
  - **Task Server**: Added CORS headers and logging to `simple_task_interactive_server.dart`.
  - Updated examples to remove deprecated API usage.

- **Documentation**:
  - Overhauled documentation (`doc/`) to match current API (v1.1.2+).
  - Added `AGENTS.md` with comprehensive developer guidelines.

- **Testing**:
  - Updated `test/types_test.dart` and `test/types_edge_cases_test.dart` to correct expectations for unknown methods. `JsonRpcMessage.fromJson` returns a generic `JsonRpcRequest` (or `JsonRpcNotification`) for unknown methods instead of throwing, aligning tests with existing library behavior.

## 1.2.0

### Breaking Changes

> [!TIP]
> All breaking changes below are auto-fixable. Run `dart fix --apply` to automatically update your code.

- **Renamed Core Classes**:
  - `Client` is now `McpClient` to avoid conflicts with other libraries (like `http`).
  - `ClientOptions` is now `McpClientOptions`.
  - `ServerOptions` is now `McpServerOptions`.
- **Renamed Request/Notification Parameters**:
  - `ReadResourceRequestParams` -> `ReadResourceRequest`
  - `GetPromptRequestParams` -> `GetPromptRequest`
  - `ElicitRequestParams` -> `ElicitRequest`
  - `CreateMessageRequestParams` -> `CreateMessageRequest`
  - `LoggingMessageNotificationParams` -> `LoggingMessageNotification`
  - `CancelledNotificationParams` -> `CancelledNotification`
  - `ProgressNotificationParams` -> `ProgressNotification`
  - `TaskCreationParams` -> `TaskCreation`

## 1.1.2

- **Fixed StdioClientTransport stderr handling**: Corrected process mode to always use `ProcessStartMode.normal` to ensure stdin/stdout piping works correctly. Fixed inverted stderr mode logic where `stderrMode: normal` now properly exposes stderr via getter (without internal listening), and `stderrMode: inheritStdio` now manually pipes stderr to parent process.

## 1.1.1

- **Structured Content Support**: Added explicit `structuredContent` field to `CallToolResult` with automatic backward compatibility support.
  - `CallToolResult.fromStructuredContent` now automatically populates both `structuredContent` (for modern clients) and `content` (as JSON string for legacy clients).
  - Updated validation logic to correctly validate `structuredContent` payload against tool schema.

## 1.1.0

### Breaking Changes

- **Protocol Version Update**: Updated default protocol version to `2025-11-25`.
- **Strict Capabilities Typing**: `ServerCapabilities` and `ClientCapabilities` fields (tasks, sampling, elicitation, etc.) are now strictly typed objects instead of `Map<String, dynamic>` or `bool`.
  - Updated `ServerCapabilities` to use `ServerCapabilitiesTasks`, `ServerCapabilitiesTools`, etc.
  - Updated `ClientCapabilities` to use `ClientCapabilitiesTasks`, `ClientCapabilitiesElicitation`, `ClientCapabilitiesSampling`, etc.
  - **Migration**: Update capability declarations to use the new typed classes (e.g., `ServerCapabilities(tasks: ServerCapabilitiesTasks(listChanged: true))`).
- **File Removal**: `lib/src/server/mcp.dart` has been removed. Use `lib/src/server/mcp_server.dart` (exported via `lib/src/server/module.dart`) instead.
- **Transport Interface Change**: `Transport.send` now accepts an optional named parameter `relatedRequestId`. Custom transports must update their method signature.
- **Client Validation**: `Client.callTool` now strictly validates tool outputs against their defined JSON schema (if present). Mismatches will throw an `McpError(ErrorCode.invalidParams)`.
- **API Refactoring**:
  - `McpServer.tool`, `resource`, and `prompt` are **deprecated**. Use `registerTool`, `registerResource`, and `registerPrompt` instead.
  - `McpServer.registerTool` uses a new callback signature: `FutureOr<CallToolResult> Function(Map<String, dynamic> args, RequestHandlerExtra extra)`.
  - The deprecated `McpServer.tool` retains the old named-parameter signature for backward compatibility.
- **Tool Schema Definitions**: `ToolInputSchema` (aka `JsonObject`) now requires properties to be defined using `JsonSchema` objects (e.g., `JsonSchema.string()`) instead of raw Maps.
- **Tool Listing Types**: `ListToolsRequestParams` has been replaced by `ListToolsRequest` (update any code passing `params:` to `Client.listTools` or constructing `JsonRpcListToolsRequest`).
- **Tool Result Structured Content**: `CallToolResult` no longer uses a dedicated `structuredContent` field in its API; structured results are represented as additional top-level fields (`CallToolResult.extra`). `CallToolResult.fromStructuredContent` now takes a single `Map<String, dynamic>` argument.
- **RequestHandlerExtra Signature Changes**: `RequestHandlerExtra.sendNotification` and `RequestHandlerExtra.sendRequest` have updated signatures (added task-related metadata/options). Update any server callbacks that call these helpers directly.

### Features

- **Task Management System**:
  - Implemented comprehensive Task support in `lib/src/server/tasks/`.
  - Introduced `TaskStore` abstract interface with `InMemoryTaskStore` as the default implementation.
  - Added strictly typed `TaskResultHandler` and `TaskSession`.
  - Introduced `TaskMessageQueue` for handling task messages.
- **McpServer Enhancements**:
  - Added `McpServer` high-level support for tasks via `tasks(...)` method.
  - Integrated `notifyTaskStatus` into `McpServer`.
  - Added `McpServer` support for `sampling/createMessage`.
  - Exposed `onError` handler setter/getter on `McpServer`.
- **StreamableMcpServer**:
  - Added `StreamableMcpServer` class for simplified Streamable HTTP server creation (handles `serverFactory`, event store, and connection management).
- **Client Enhancements**:
  - Added `onTaskStatus` callback to `Client`.
  - Simplified client request handlers for sampling and elicitation.

### Fixes

- Fixed `Task` serialization.
- Fixed capabilities recognition in `McpServer`.
- Added comprehensive tests for StreamableMcpServer and Task features.

## 1.0.2

- Fix pana analysis issues
- Fix Web support for StreamableHTTP client

## 1.0.1

- Fix Documentation links in README.md

## 1.0.0

- Update protocol version to 2025-06-18
- Add Elicitation support (server-initiated input collection)
  - API: `McpServer.elicitUserInput()` (server) | `Client.onElicitRequest` (client handler)
  - Types: ElicitRequestParams (`message`, `requestedSchema`), ElicitResult (`action`, `content`), ClientCapabilitiesElicitation
  - Uses `elicitation/create` method (Inspector-compatible)
  - Accepts JSON Schema Maps for flexible schema definition
  - Helpers: `.accepted`, `.declined`, `.cancelled` getters on ElicitResult
  - Example: elicitation_http_server.dart
  - Tests: elicitation_test.dart
- **CRITICAL FIX**: Logger → stderr (prevents JSON-RPC corruption in stdio)
- **Comprehensive Test Coverage**: Added 203 new tests across 4 phases (+13.1% overall coverage: 56.9% → 70.0%)
  - Phase 1: External API coverage (Server MCP, URI templates, Client/Server capabilities) - 108 tests
  - Phase 2: Transport coverage (Stdio, SSE, HTTPS) - 38 tests
  - Phase 3: Types & edge cases (Protocol lifecycle, error handling) - 45 tests
  - Phase 4: Advanced scenarios (Protocol timeouts/aborts, Streamable HTTPS integration) - 12 tests
  - Fixed critical URI template variable duplication bug
  - Fixed McpError code preservation in request handlers
  - All 351 tests passing ✅

## 0.7.0

- Add support for Completions capability per MCP 2025-06-18 spec
- Add ServerCapabilitiesCompletions class for explicit completions capability declaration
- Update ServerCapabilities to include completions field
- Update client capability check to use explicit completions capability instead of inferring from prompts/resources
- Add integration tests and example for completions capability usage

## 0.6.4

- Fix issue with StreamableHTTP server not setting correct content-type for SSE

## 0.6.3

- Replace print statements with lightweight logging implementation

## 0.6.2

- Remove trailing CR before processing the lines

## 0.6.1

- Fix issue with CallToolResult not including metadata

## 0.6.0

- Add ToolInputSchema and ToolOutputSchema support in server.tool()
- Deprecate inputSchemaProperties and outputSchemaProperties in server.tool()
- Update examples to use ToolInputSchema and ToolOutputSchema

## 0.5.3

- Support Web Client for StreamableHTTP

## 0.5.2

- Preserve required fields in ToolInputSchema

## 0.5.1

- Add support for OutputScheme (<https://modelcontextprotocol.io/specification/draft/server/tools#output-schema>)

## 0.5.0

- Protocol version 2025-03-26

## 0.4.3

- Fix SSE behavior on StreamableHTTP
- Added sendNotification and sendRequest to extra for server callbacks

## 0.4.2

- Add Tool Annotation
- Remove additionalProperties from all models
- Add AudioContent

## 0.4.1

- Add IOStreamTransport to connect a client and server via dart streams in a single application

## 0.4.0

- Add support for StreamableHTTP client
- Add support for StreamableHTTP server

## 0.3.6

- Improve pub.dev points

## 0.3.5

- Lower min dart sdk to 3.0.0

## 0.3.4

- Fix Sampling result parsing error

## 0.3.3

- Add Gemini MCP Client Example
- Add Anthropic MCP Client Example
- Add Weather MCP Server Example

## 0.3.2

- Add SSE Server Manager for easier SSE server implementation

## 0.3.1

- Add Client support (stdio)
- Add resource and prompts example to stdio server and client

## 0.3.0

- Full refactor of the codebase to match it with the Typescript SDK implementation.

## 0.2.0

- Make it no need to call trasnport.connect()

## 0.1.1

- Add examples visible in pub.dev

## 0.1.0

- Add SSE support

## 0.0.2

- Expose more types

## 0.0.1

- Initial version.
