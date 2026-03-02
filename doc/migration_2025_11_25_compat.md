# MCP 2025-11-25 Compatibility Migration

This guide helps update existing code that used older sampling/tool-choice APIs.

## What changed

- `CreateMessageRequest.toolChoice` can be legacy map or typed `ToolChoice`.
- `CreateMessageRequest.toolChoiceConfig` is the normalized typed accessor.
- `SamplingMessage.content` and `CreateMessageResult.content` may contain a
  single block or a list of blocks.
- `SamplingMessage.contentBlocks` and `CreateMessageResult.contentBlocks`
  provide normalized list access.
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
