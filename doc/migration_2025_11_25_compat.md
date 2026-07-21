# MCP 2025-11-25 Compatibility Migration

> This guide covers the `McpProtocol.legacy` and MCP 2025-11-25
> initialization-era surface. The dev.2
> default prefers MCP `2026-07-28`; see the
> [transition guide](mcp-2026-07-28.md) for current default behavior.

This guide helps update existing code that used older sampling/tool-choice APIs.

## What changed

- `CreateMessageRequest.toolChoice` can be legacy map or typed `ToolChoice`.
- `CreateMessageRequest.toolChoiceConfig` is the normalized typed accessor.
- `SamplingMessage.content` and `CreateMessageResult.content` may contain a
  single block or a list of blocks.
- `SamplingMessage.contentBlocks` and `CreateMessageResult.contentBlocks`
  provide normalized list access.
- `tasks/cancel` returns the final cancelled `Task` as its JSON-RPC result.
  Use `onCancelTaskWithResult`, `CancelTaskResultHandler.cancelTaskWithResult`,
  and `TaskClient.cancelTaskWithResult` to access the result explicitly.
  Legacy `onCancelTask`, `ToolTaskHandler.cancelTask`, and
  `TaskClient.cancelTask` remain available as deprecated compatibility shims for
  one release window.
- Task serialization keeps the MCP-required `ttl` field even when it is `null`,
  while omitting optional `pollInterval` when it is not set.
- Task status notifications now serialize and parse the full MCP
  `NotificationParams & Task` shape. The `ttl`, `createdAt`, and
  `lastUpdatedAt` fields are required at the wire boundary, even when `ttl` is
  `null`.
- Task stores treat terminal tasks (`completed`, `failed`, `cancelled`) as
  immutable. Later status or result writes are ignored instead of overwriting
  the terminal state.
- `Task` constructor now requires `ttl`, `createdAt`, and `lastUpdatedAt`,
  so valid task instances serialize without throwing.
- Task-augmented requests require explicit `tasks.requests.*` negotiation. A
  top-level `tasks` capability is not enough: task-based tool calls require
  `tasks.requests.tools.call`, task sampling handlers require
  `tasks.requests.sampling.createMessage`, and task elicitation handlers require
  `tasks.requests.elicitation.create`.
- Streamable HTTP defaults are stricter for protocol-version headers, DNS
  rebinding protection, and batch request rejection.
- MCP/JSON-RPC wire parsing now rejects malformed request IDs, progress tokens,
  and sampling tool-use requests that were not negotiated via
  `ClientCapabilities.sampling.tools`.
- Servers now reject normal incoming requests before `initialize` and before
  the client sends `notifications/initialized`; `ping` remains available during
  lifecycle setup. Clients likewise reject server-initiated operation requests
  until their initialized notification has been sent. The interop suite covers
  official TypeScript SDK clients listing tools immediately after the lifecycle
  handshake over stdio and Streamable HTTP.
- `elicitation/create` parameters are validated as the MCP 2025-11-25 form/URL
  union. Form mode requires `requestedSchema`; URL mode requires `mode: "url"`,
  `url`, and `elicitationId`.
- Form elicitation schemas must now be object-root schemas whose properties are
  primitive string, number, integer, boolean, enum, or multiselect schemas.
- Tool inputs and MCP 2025-11-25 structured outputs are object-rooted. A
  non-object `inputSchema` fails at parse/serialization boundaries;
  initialization-era client/server compatibility paths omit or ignore MCP
  `2026-07-28`-only non-object output schemas and structured values.
- MCP 2025-11-25 metadata serializers no longer emit legacy singular `icon`
  fields,
  `ResourceAnnotations.title`, `ToolAnnotations.priority`, or
  `ToolAnnotations.audience`. Those fields still parse into deprecated Dart
  accessors for legacy peers.
- MCP 2025-11-25 server capabilities no longer emit top-level `elicitation` or
  `tasks.listChanged`; legacy payloads still parse for compatibility.
- Required result arrays are strict at incoming wire boundaries. Empty arrays
  remain valid when the required key is present, but missing `resources`,
  `resourceTemplates`, `contents`, `prompts`, `tools`, `roots`, `messages`,
  `values`, or `tasks` fields are rejected.
- Successful JSON-RPC responses require a string or integer `id`. Error
  responses may omit `id`; legacy error payloads with `id: null` still parse but
  serialize by omitting the field.
- OAuth authorization-code discovery now refuses authorization servers that
  omit `code_challenge_methods_supported` or do not advertise PKCE `S256`.
- First-class OAuth discovery requires callback `state`, accepts same-origin
  HTTPS endpoints by default, allows loopback-to-loopback development flows,
  and requires `oauthUriValidator` approval for other trusted HTTPS origins.
- Streamable HTTP resumability now writes an initial empty SSE event with an
  `id` when an event store is configured, so clients can reconnect using
  `Last-Event-ID` even before JSON-RPC data has been sent.

## Capability enforcement

For source compatibility, `ProtocolOptions.enforceStrictCapabilities` remains
opt-in for outgoing requests and notifications. High-level APIs still perform
targeted checks for compatibility-sensitive behavior, such as task
subcapabilities, sampling tools, and elicitation mode support. Enable strict
capabilities in tests or production integrations that should fail fast when a
peer has not advertised the required capability.

## Runtime compatibility toggles

Use these options to keep older runtime behavior while migrating:

```dart
final server = StreamableMcpServer(
  serverFactory: (sid) => McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
  ),
  strictProtocolVersionHeaderValidation: false,
  rejectBatchJsonRpcPayloads: false,
  enableDnsRebindingProtection: false,
);
```

For low-level transport usage:

```dart
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    strictProtocolVersionHeaderValidation: false,
    rejectBatchJsonRpcPayloads: false,
    enableDnsRebindingProtection: false,
  ),
);
```

## Auto-fix with Dart

Run a standard Dart fix pass first, then format and analyze:

```bash
dart fix --apply
dart format path/to/your_project
dart analyze
```

`dart fix` will handle available analyzer/lint fixes. For API-shape updates
like `toolChoice` and `contentBlocks`, use the examples below where needed.

## Manual migration examples

### Tool choice accessor

Before:

```dart
final mode = request.toolChoice?.mode;
```

After:

```dart
final mode = request.toolChoiceConfig?.mode;
```

### Tool choice constructor argument

Before:

```dart
CreateMessageRequest(
  messages: messages,
  maxTokens: 500,
  toolChoice: {'type': 'auto'},
)
```

After:

```dart
CreateMessageRequest(
  messages: messages,
  maxTokens: 500,
  toolChoice: const ToolChoice(mode: ToolChoiceMode.auto),
)
```

### Multi-block sampling content

Use normalized block access:

```dart
for (final block in result.contentBlocks) {
  // ...
}
```

### Task cancellation result

Before:

```dart
server.experimental.onCancelTask((taskId, extra) async {
  await store.cancelTask(taskId);
});

await taskClient.cancelTask(taskId);
```

The deprecated `onCancelTask` compatibility shim may still be used during the
migration window, but it must be paired with `onGetTask` so the server can return
the final cancelled task on the wire.

After:

```dart
server.experimental.onCancelTaskWithResult((taskId, extra) async {
  final cancelled = await store.cancelTask(taskId);
  if (!cancelled) {
    throw McpError(
      ErrorCode.invalidParams.value,
      'Cannot cancel task: not found or already terminal',
    );
  }
  final task = await store.getTask(taskId);
  if (task == null) {
    throw McpError(ErrorCode.invalidParams.value, 'Task not found');
  }
  return task;
});

final cancelledTask = await taskClient.cancelTaskWithResult(taskId);
```

Returned cancelled tasks should include the MCP-required task fields:
`taskId`, `status`, `createdAt`, `lastUpdatedAt`, and `ttl` (`null` is valid
for `ttl`).

### Tool and elicitation schemas

Before, some code used primitive root schemas for a single value:

```dart
Tool(
  name: 'set-enabled',
  inputSchema: JsonSchema.boolean(),
);
```

Use an object-root schema instead:

```dart
Tool(
  name: 'set-enabled',
  inputSchema: JsonSchema.object(
    properties: {
      'enabled': JsonSchema.boolean(),
    },
    required: ['enabled'],
  ),
);
```

The same rule applies to form elicitation:

```dart
ElicitRequest(
  message: 'Choose a display name',
  requestedSchema: JsonSchema.object(
    properties: {
      'displayName': JsonSchema.string(),
    },
    required: ['displayName'],
  ),
);
```

### Task request capability negotiation

MCP 2025-11-25 treats `tasks.requests` as an exhaustive list of request methods
that may be task-augmented. Advertising top-level `tasks` alone no longer allows
every task-related request shape.

For task-based tools, register task tools before `connect()` so the server can
auto-advertise `tasks.requests.tools.call`:

```dart
server.experimental.registerToolTask(
  'slow-tool',
  inputSchema: const ToolInputSchema(),
  handler: SlowToolTaskHandler(),
);
```

If task tools are registered after `connect()`, pre-advertise the capability in
server options before connecting:

```dart
final server = McpServer(
  const Implementation(name: 'server', version: '1.0.0'),
  options: const McpServerOptions(
    capabilities: ServerCapabilities(
      tasks: ServerCapabilitiesTasks(
        requests: ServerCapabilitiesTasksRequests(
          tools: ServerCapabilitiesTasksTools(
            call: ServerCapabilitiesTasksToolsCall(),
          ),
        ),
      ),
    ),
  ),
);
```

For server-initiated task interactions, clients must advertise the exact task
request handlers they register:

```dart
final client = McpClient(
  const Implementation(name: 'client', version: '1.0.0'),
  options: const McpClientOptions(
    capabilities: ClientCapabilities(
      tasks: ClientCapabilitiesTasks(
        requests: ClientCapabilitiesTasksRequests(
          sampling: ClientCapabilitiesTasksSampling(
            createMessage: ClientCapabilitiesTasksSamplingCreateMessage(),
          ),
          elicitation: ClientCapabilitiesTasksElicitation(
            create: ClientCapabilitiesTasksElicitationCreate(),
          ),
        ),
      ),
    ),
  ),
);
```
