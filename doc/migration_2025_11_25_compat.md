# MCP 2025-11-25 Compatibility Migration

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
- The `Task` constructor now requires `ttl`, `createdAt`, and `lastUpdatedAt`,
  so valid task instances serialize without throwing.
- Streamable HTTP defaults are stricter for protocol-version headers, DNS
  rebinding protection, and batch request rejection.

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
