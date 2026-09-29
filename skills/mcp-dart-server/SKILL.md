---
name: mcp-dart-server
description: >-
  Use when building a Model Context Protocol (MCP) server in Dart or Flutter
  with mcp_dart: creating an McpServer, registering tools, resources, resource
  templates or prompts, returning tool results and errors, reporting progress,
  or running the server over stdio.
---

# Building an MCP server with mcp_dart

`McpServer` exposes tools, resources and prompts to MCP clients. By default it
speaks MCP 2026-07-28 and falls back to initialization-era versions (MCP
2025-11-25 and earlier) for legacy clients. Import everything from
`package:mcp_dart/mcp_dart.dart`.

## Guidelines

- Create the server with `McpServer(Implementation(name:, version:))`. The
  `register*` methods advertise the `tools`, `resources` and `prompts`
  capabilities automatically; pass `McpServerOptions(capabilities: ...)` only
  for extra flags such as `listChanged` or `subscribe`, and advertise only
  what the server actually implements.
- Keep the default `McpProtocol.stable` profile. Use
  `McpServerOptions(protocol: McpProtocol.legacy)` or
  `McpProtocol.require2026` only when a deployment must pin one protocol era.
- Register everything before `connect`. One `McpServer` instance owns one
  transport; build a fresh instance per transport from a shared registration
  function.
- Describe tool inputs with `JsonSchema.object(properties: ..., required: ...)`.
  The SDK validates arguments before the callback runs, so the callback may
  cast declared fields (`args['a'] as num`). Still validate business rules in
  the callback.
- Tool callbacks have the signature `(Map<String, dynamic> args,
  RequestHandlerExtra extra)` and return `CallToolResult`. Return
  `CallToolResult(isError: true, content: [...])` for expected domain failures
  (not found, bad input, upstream API errors) so the model can recover. Throw
  `McpError(ErrorCode.x.value, message)` only for protocol-level failures.
- For typed output, pass `outputSchema:` and return
  `CallToolResult.fromStructuredContent({...})`; it also fills `content` with
  the serialized JSON for clients that ignore structured content.
- Set `ToolAnnotations(readOnlyHint: true)`, `destructiveHint`,
  `idempotentHint` or `openWorldHint` honestly; they are hints, not access
  control.
- Long-running tools call `extra.sendProgress(done, total: n, message: ...)`
  (a no-op when the client sent no progress token) and check
  `extra.signal.aborted` to stop promptly after cancellation.
- Resources: `registerResource(name, uri, (description:, mimeType:), callback)`
  for fixed URIs; `registerResourceTemplate(name,
  ResourceTemplateRegistration('scheme://{var}', listCallback: null), ...)` for
  URI families. Return contents whose `uri` is the concrete requested URI.
  For an unknown concrete URI, throw `McpError` with `invalidParams` for MCP
  2026-07-28 requests and `resourceNotFound` for legacy ones (see the
  template example).
- Prompts: `registerPrompt(name, argsSchema: {...}, callback: ...)`. The
  prompt callback's `args` and `extra` are nullable.
- A callback that must ask the client for more input mid-call (MCP 2026-07-28
  `InputRequiredResult`) needs the `registerStateless*` counterpart. Use the
  plain `register*` methods otherwise.
- Stdio servers must write only MCP frames to stdout. Send application logs
  to `stderr`, never `print`. Tune SDK-internal logs with `setMcpLogHandler`
  or `silenceMcpLogs`.
- Each incoming stdio message is limited to 10 MiB by default; raise it with
  `StdioServerTransport(maxIncomingMessageBytes: ...)` only when needed, and
  keep it finite.
- Test servers in-process with `IOStreamTransport` pairs instead of spawning
  processes (see the last example).

## Examples

A complete stdio server with a tool, a structured-output tool, a resource, a
resource template and a prompt:

```dart
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

McpServer buildServer() {
  final server = McpServer(
    const Implementation(name: 'notes-server', version: '1.0.0'),
    options: const McpServerOptions(
      instructions: 'Stores short notes. Use add_note, then read notes://.',
    ),
  );
  final notes = <String, String>{};

  server.registerTool(
    'add_note',
    description: 'Store a note under an id.',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(description: 'Lowercase note id'),
        'text': JsonSchema.string(description: 'Note body'),
      },
      required: ['id', 'text'],
    ),
    annotations: const ToolAnnotations(idempotentHint: true),
    callback: (args, extra) async {
      final id = args['id'] as String;
      if (id.isEmpty) {
        return const CallToolResult(
          isError: true,
          content: [TextContent(text: 'id must not be empty.')],
        );
      }
      notes[id] = args['text'] as String;
      return CallToolResult(content: [TextContent(text: 'Saved $id.')]);
    },
  );

  server.registerTool(
    'count_notes',
    description: 'Return how many notes are stored.',
    inputSchema: JsonSchema.object(properties: {}),
    outputSchema: JsonSchema.object(
      properties: {'count': JsonSchema.integer()},
      required: ['count'],
    ),
    annotations: const ToolAnnotations(readOnlyHint: true),
    callback: (args, extra) async =>
        CallToolResult.fromStructuredContent({'count': notes.length}),
  );

  server.registerResource(
    'Note index',
    'notes://index',
    (description: 'All note ids', mimeType: 'text/plain'),
    (uri, extra) async => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: notes.keys.join('\n'),
        ),
      ],
    ),
  );

  server.registerResourceTemplate(
    'Note',
    ResourceTemplateRegistration('notes://{id}', listCallback: null),
    (description: 'One note by id', mimeType: 'text/plain'),
    (uri, variables, extra) async {
      final id = variables['id'];
      final text = id is String ? notes[id] : null;
      if (text == null) {
        final version = extra.protocolVersion;
        throw McpError(
          version != null && isStatelessProtocolVersion(version)
              ? ErrorCode.invalidParams.value
              : ErrorCode.resourceNotFound.value,
          'Resource not found',
          {'uri': uri.toString()},
        );
      }
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'text/plain',
            text: text,
          ),
        ],
      );
    },
  );

  server.registerPrompt(
    'summarize_note',
    description: 'Ask the model to summarize a note.',
    argsSchema: const {
      'id': PromptArgumentDefinition(description: 'Note id', required: true),
    },
    callback: (args, extra) async {
      final id = args?['id'] as String? ?? '';
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: 'Summarize this note:\n${notes[id] ?? '(missing)'}',
            ),
          ),
        ],
      );
    },
  );

  return server;
}

Future<void> main() async {
  final server = buildServer();
  await server.connect(StdioServerTransport());
  stderr.writeln('notes-server ready on stdio');
}
```

A cancellable tool that reports progress:

```dart
import 'package:mcp_dart/mcp_dart.dart';

void registerExport(McpServer server) {
  server.registerTool(
    'export_rows',
    description: 'Export rows in batches.',
    inputSchema: JsonSchema.object(
      properties: {
        'rows': JsonSchema.integer(minimum: 1, maximum: 10000),
      },
      required: ['rows'],
    ),
    callback: (args, extra) async {
      final rows = args['rows'] as int;
      for (var done = 0; done < rows; done += 100) {
        if (extra.signal.aborted) {
          return const CallToolResult(
            isError: true,
            content: [TextContent(text: 'Export cancelled.')],
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await extra.sendProgress(
          done.toDouble(),
          total: rows.toDouble(),
          message: 'Exported $done of $rows rows',
        );
      }
      return CallToolResult(
        content: [TextContent(text: 'Exported $rows rows.')],
      );
    },
  );
}
```

Test a server in-process with a connected client:

```dart
import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final clientToServer = StreamController<List<int>>();
  final serverToClient = StreamController<List<int>>();

  final server = McpServer(
    const Implementation(name: 'test-server', version: '1.0.0'),
  );
  server.registerTool(
    'add',
    inputSchema: JsonSchema.object(
      properties: {'a': JsonSchema.number(), 'b': JsonSchema.number()},
      required: ['a', 'b'],
    ),
    callback: (args, extra) async => CallToolResult(
      content: [
        TextContent(text: '${(args['a'] as num) + (args['b'] as num)}'),
      ],
    ),
  );
  await server.connect(
    IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    ),
  );

  final client = McpClient(
    const Implementation(name: 'test-client', version: '1.0.0'),
  );
  try {
    await client.connect(
      IOStreamTransport(
        stream: serverToClient.stream,
        sink: clientToServer.sink,
      ),
    );
    final result = await client.callTool(
      const CallToolRequest(name: 'add', arguments: {'a': 2, 'b': 3}),
    );
    final first = result.content.first;
    print(first is TextContent ? first.text : first.toJson());
  } finally {
    await client.close();
    await server.close();
    await clientToServer.close();
    await serverToClient.close();
  }
}
```

## More

- Server guide: https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md
- Tools, schemas, errors and progress: https://github.com/leehack/mcp_dart/blob/main/doc/tools.md
- MCP 2026-07-28 APIs (`registerStateless*`, tasks): https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-07-28.md
- Remote HTTP deployment: the `mcp-dart-streamable-http` skill.
