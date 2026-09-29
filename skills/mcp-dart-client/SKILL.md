---
name: mcp-dart-client
description: >-
  Use when connecting a Dart or Flutter app to a Model Context Protocol (MCP)
  server with mcp_dart: creating an McpClient, launching a local server over
  stdio or reaching a remote one over Streamable HTTP, listing and calling
  tools, reading resources, getting prompts, paginating, handling tool errors,
  timeouts and cancellation, or exposing MCP tools to an LLM host.
---

# Building an MCP client with mcp_dart

`McpClient` connects to one MCP server through a transport. By default it
tries MCP 2026-07-28 discovery and falls back to initialization-era versions
(MCP 2025-11-25 and earlier) for legacy servers, so it works with Dart,
TypeScript and Python servers alike. Import everything from
`package:mcp_dart/mcp_dart.dart`.

## Guidelines

- Create one `McpClient` per server connection and always
  `await client.close()` in a `finally` block or when the owning object is
  disposed. `close()` also stops a spawned stdio process.
- Pick the transport by where the server runs:
  - Local helper process (Dart VM, desktop): `StdioClientTransport(
    StdioServerParameters(command: ..., args: [...]))`.
  - Remote service, browser, Flutter Web or mobile: `StreamableHttpClientTransport(
    Uri.parse('https://host/mcp'))`. Browsers and mobile apps cannot spawn
    stdio servers.
  - `SseClientTransport` is deprecated legacy HTTP+SSE; use it only for old
    servers that lack Streamable HTTP.
- Keep the default `McpProtocol.stable` profile. Pass
  `McpClientOptions(protocol: McpProtocol.legacy)` or
  `McpProtocol.require2026` only to pin an era. The era is fixed per
  connection; open a new connection to change it.
- Stdio child processes inherit the parent environment by default. To keep
  host secrets from a third-party server, pass a sanitized `environment` and
  `includeParentEnvironment: false`.
- After `connect`, check `client.getServerCapabilities()` before optional
  operations (`resources`, `prompts`, `completions`, legacy
  `resources.subscribe`). An SDK method existing does not mean the server
  supports it.
- Treat `listTools()` results as the source of truth for tool names and input
  schemas. List methods are paginated: pass `nextCursor` back unchanged until
  it is null, and stop if a cursor repeats.
- `callTool` returns `CallToolResult`. Check `result.isError` first: it marks a
  tool-domain failure the model should see and may retry. Protocol failures
  (unknown tool, malformed request, timeout) throw `McpError`; compare
  `error.code` with `ErrorCode.x.value`.
- Inspect every item in `result.content` (`TextContent`, `ImageContent`,
  `AudioContent`, `EmbeddedResource`, `ResourceLink`). Prefer
  `result.structuredContent` when the tool declares an `outputSchema`.
- Pass `RequestOptions(timeout: ..., onprogress: ..., signal: ...)` to
  long-running calls. Cancel with a `BasicAbortController`; the pending future
  then completes with `AbortError`.
- Server-initiated features need both a client capability and a handler:
  `ClientCapabilities(sampling: ...)` with `client.onSamplingRequest`, or
  `ClientCapabilities(elicitation: ...)` with `client.onElicitRequest`. Set
  handlers before `connect`, and advertise only what the host implements.
- To hand MCP tools to an LLM, map each `Tool` to the provider's tool format
  with `tool.name`, `tool.description` and `tool.inputSchema.toJson()`, then
  forward the model's tool calls to `client.callTool`.

## Examples

Launch a local stdio server, list all tools across pages, call one and read a
resource:

```dart
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<List<Tool>> listAllTools(McpClient client) async {
  final tools = <Tool>[];
  final seen = <String>{};
  String? cursor;
  do {
    final page = await client.listTools(
      params: cursor == null ? null : ListToolsRequest(cursor: cursor),
    );
    tools.addAll(page.tools);
    cursor = page.nextCursor;
    if (cursor != null && !seen.add(cursor)) {
      throw StateError('tools/list repeated cursor "$cursor"');
    }
  } while (cursor != null);
  return tools;
}

Future<void> main() async {
  final client = McpClient(
    const Implementation(name: 'notes-client', version: '1.0.0'),
  );
  try {
    await client.connect(
      StdioClientTransport(
        const StdioServerParameters(
          command: 'dart',
          args: ['run', 'bin/server.dart'],
        ),
      ),
    );
    print('connected to ${client.getServerVersion()?.name} '
        'using MCP ${client.getProtocolVersion()}');

    for (final tool in await listAllTools(client)) {
      print('${tool.name}: ${tool.description ?? ''}');
    }

    final result = await client.callTool(
      const CallToolRequest(
        name: 'add_note',
        arguments: {'id': 'todo', 'text': 'Ship the release'},
      ),
      options: const RequestOptions(timeout: Duration(seconds: 30)),
    );
    for (final content in result.content) {
      if (content is TextContent) {
        (result.isError ? stderr : stdout).writeln(content.text);
      }
    }

    if (client.getServerCapabilities()?.resources != null) {
      final read = await client.readResource(
        const ReadResourceRequest(uri: 'notes://index'),
      );
      for (final contents in read.contents) {
        if (contents is TextResourceContents) {
          print(contents.text);
        }
      }
    }
  } on McpError catch (error) {
    stderr.writeln('MCP error ${error.code}: ${error.message}');
  } finally {
    await client.close();
  }
}
```

Connect to a remote server, get a prompt, and cancel a slow tool call with
progress:

```dart
import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final client = McpClient(
    const Implementation(name: 'remote-client', version: '1.0.0'),
  );
  try {
    await client.connect(
      StreamableHttpClientTransport(Uri.parse('https://mcp.example.com/mcp')),
    );

    if (client.getServerCapabilities()?.prompts != null) {
      final prompt = await client.getPrompt(
        const GetPromptRequest(
          name: 'summarize_note',
          arguments: {'id': 'todo'},
        ),
      );
      for (final message in prompt.messages) {
        final content = message.content;
        if (content is TextContent) {
          print('${message.role.name}: ${content.text}');
        }
      }
    }

    final controller = BasicAbortController();
    final pending = client.callTool(
      const CallToolRequest(name: 'export_rows', arguments: {'rows': 5000}),
      options: RequestOptions(
        signal: controller.signal,
        onprogress: (progress) {
          print('${progress.progress}/${progress.total} ${progress.message}');
          if (progress.progress >= 1000) {
            controller.abort('User cancelled');
          }
        },
      ),
    );
    try {
      await pending;
    } on AbortError {
      print('export cancelled');
    }
  } finally {
    await client.close();
  }
}
```

## More

- Client guide: https://github.com/leehack/mcp_dart/blob/main/doc/client-guide.md
- Transports and stdio options: https://github.com/leehack/mcp_dart/blob/main/doc/transports.md
- Flutter lifecycle and secure storage: https://github.com/leehack/mcp_dart/blob/main/doc/flutter-recipes.md
- OAuth and Streamable HTTP servers: the `mcp-dart-streamable-http` skill.
