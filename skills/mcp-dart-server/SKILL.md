---
name: mcp-dart-server
description: >-
  Use when building or extending a Model Context Protocol (MCP) server in Dart
  with mcp_dart: structuring the project, creating an McpServer, adding tools,
  resources, resource templates or prompts, returning tool results and errors,
  reporting progress, running over stdio, or testing the server.
---

# Building an MCP server with mcp_dart

`McpServer` exposes tools, resources and prompts to MCP clients. By default it
speaks MCP 2026-07-28 and falls back to initialization-era versions (MCP
2025-11-25 and earlier) for legacy clients. Import everything from
`package:mcp_dart/mcp_dart.dart`.

## Project structure

Keep MCP wiring thin and separate from the application's logic. This is the
layout that `mcp_dart create` generates; use it for hand-written servers too:

```text
my_server/
  bin/server.dart               # Reads config, builds shared services, picks the transport.
  lib/mcp/mcp.dart              # createMcpServer(services): the only server factory.
  lib/mcp/tools/base_tool.dart  # BaseTool + registerBaseTool extension.
  lib/mcp/tools/*_tool.dart     # One class per tool; dependencies via the constructor.
  lib/mcp/resources/            # Resources and resource templates.
  lib/mcp/prompts/              # Prompts.
  lib/src/                      # Domain services and models; no mcp_dart imports.
  test/                         # In-process client/server tests.
```

- If `lib/mcp/tools/base_tool.dart` already exists, the project came from
  `mcp_dart create`. Follow it: add a `BaseTool` subclass and list it in
  `createAllTools()`, and use `BaseResource`/`BasePrompt` the same way. Do not
  add inline `registerTool` calls beside that pattern.
- To start a new standalone server, `dart pub global activate mcp_dart_cli`
  then `mcp_dart create my_server` (the CLI needs Dart 3.12; the generated
  project adds `args` and `logging` and targets Dart 3.4). Adding a server to
  an existing package needs only `dart pub add mcp_dart`.
- Tool classes are adapters: parse arguments, call a domain service, map
  domain failures to `CallToolResult(isError: true)`. Keep business rules,
  I/O and state in `lib/src/` so they are testable without MCP.
- Build services once in `bin/server.dart` and pass them to
  `createMcpServer`. Never create state inside a tool call or inside a
  Streamable HTTP `serverFactory`, which runs per request or session.
- Read configuration and secrets at startup (arguments, environment) and pass
  them in. Never log secrets or read them inside handlers.

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
  transport; build a fresh instance per transport from `createMcpServer`.
- Describe tool inputs with `JsonSchema.object(properties: ..., required: ...)`.
  The SDK validates arguments before the callback runs, so the callback may
  cast declared fields (`args['a'] as num`). Still validate business rules.
- Tool callbacks take `(Map<String, dynamic> args, RequestHandlerExtra extra)`
  and return `CallToolResult`. Return `CallToolResult(isError: true, ...)` for
  expected domain failures (not found, bad input, upstream API errors) so the
  model can recover. Throw `McpError(ErrorCode.x.value, message)` only for
  protocol-level failures.
- For typed output, declare `outputSchema` and return
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
  For an unknown URI, throw `McpError` with `invalidParams` for MCP 2026-07-28
  requests and `resourceNotFound` for legacy ones.
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
- Test through a real client over an in-process `IOStreamTransport` pair with
  fake or in-memory services. Check a running server by hand with
  `mcp_dart inspect` (the CLI's `mcp_dart skills install` adds a debugging
  workflow skill for its inspect and trace commands).

## Examples

A complete server in the layout above. Each block is one file, named by its
first line; `my_server` is the package name.

```dart
// file: lib/src/note_repository.dart
/// Thrown when a note violates a business rule.
class NoteRejected implements Exception {
  NoteRejected(this.message);

  final String message;
}

/// Domain service; it knows nothing about MCP.
class NoteRepository {
  final Map<String, String> _notes = {};

  Iterable<String> get ids => _notes.keys;

  String? read(String id) => _notes[id];

  void save(String id, String text) {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id)) {
      throw NoteRejected('id must be lowercase letters, digits or hyphens.');
    }
    _notes[id] = text;
  }
}
```

```dart
// file: lib/mcp/tools/base_tool.dart
import 'package:mcp_dart/mcp_dart.dart';

abstract class BaseTool {
  String get name;
  String get description;
  ToolInputSchema get inputSchema;
  ToolOutputSchema? get outputSchema => null;
  ToolAnnotations? get annotations => null;

  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  );
}

extension ToolRegistration on McpServer {
  void registerBaseTool(BaseTool tool) {
    registerTool(
      tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
      outputSchema: tool.outputSchema,
      annotations: tool.annotations,
      callback: tool.execute,
    );
  }
}
```

```dart
// file: lib/mcp/tools/add_note_tool.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/mcp/tools/base_tool.dart';
import 'package:my_server/src/note_repository.dart';

class AddNoteTool extends BaseTool {
  AddNoteTool(this._notes);

  final NoteRepository _notes;

  @override
  String get name => 'add_note';

  @override
  String get description => 'Store a note under an id.';

  @override
  ToolInputSchema get inputSchema => JsonSchema.object(
        properties: {
          'id': JsonSchema.string(description: 'Lowercase note id'),
          'text': JsonSchema.string(description: 'Note body'),
        },
        required: ['id', 'text'],
      );

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(idempotentHint: true);

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final id = args['id'] as String;
    try {
      _notes.save(id, args['text'] as String);
    } on NoteRejected catch (error) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: error.message)],
      );
    }
    return CallToolResult(content: [TextContent(text: 'Saved $id.')]);
  }
}
```

```dart
// file: lib/mcp/tools/count_notes_tool.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/mcp/tools/base_tool.dart';
import 'package:my_server/src/note_repository.dart';

class CountNotesTool extends BaseTool {
  CountNotesTool(this._notes);

  final NoteRepository _notes;

  @override
  String get name => 'count_notes';

  @override
  String get description => 'Return how many notes are stored.';

  @override
  ToolInputSchema get inputSchema => JsonSchema.object(properties: {});

  @override
  ToolOutputSchema get outputSchema => JsonSchema.object(
        properties: {'count': JsonSchema.integer()},
        required: ['count'],
      );

  @override
  ToolAnnotations get annotations => const ToolAnnotations(readOnlyHint: true);

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async =>
      CallToolResult.fromStructuredContent({'count': _notes.ids.length});
}
```

```dart
// file: lib/mcp/resources/note_resources.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/src/note_repository.dart';

void registerNoteResources(McpServer server, NoteRepository notes) {
  server.registerResource(
    'Note index',
    'notes://index',
    (description: 'All note ids', mimeType: 'text/plain'),
    (uri, extra) => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: notes.ids.join('\n'),
        ),
      ],
    ),
  );

  server.registerResourceTemplate(
    'Note',
    ResourceTemplateRegistration('notes://{id}', listCallback: null),
    (description: 'One note by id', mimeType: 'text/plain'),
    (uri, variables, extra) {
      final id = variables['id'];
      final text = id is String ? notes.read(id) : null;
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
}
```

```dart
// file: lib/mcp/prompts/note_prompts.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/src/note_repository.dart';

void registerNotePrompts(McpServer server, NoteRepository notes) {
  server.registerPrompt(
    'summarize_note',
    description: 'Ask the model to summarize a note.',
    argsSchema: const {
      'id': PromptArgumentDefinition(description: 'Note id', required: true),
    },
    callback: (args, extra) {
      final id = args?['id'] as String? ?? '';
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: 'Summarize this note:\n${notes.read(id) ?? '(missing)'}',
            ),
          ),
        ],
      );
    },
  );
}
```

```dart
// file: lib/mcp/mcp.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/mcp/prompts/note_prompts.dart';
import 'package:my_server/mcp/resources/note_resources.dart';
import 'package:my_server/mcp/tools/add_note_tool.dart';
import 'package:my_server/mcp/tools/base_tool.dart';
import 'package:my_server/mcp/tools/count_notes_tool.dart';
import 'package:my_server/src/note_repository.dart';

List<BaseTool> createAllTools(NoteRepository notes) => [
      AddNoteTool(notes),
      CountNotesTool(notes),
    ];

McpServer createMcpServer(NoteRepository notes) {
  final server = McpServer(
    const Implementation(name: 'my_server', version: '1.0.0'),
    options: const McpServerOptions(
      instructions: 'Stores short notes. Use add_note, then read notes://.',
    ),
  );
  for (final tool in createAllTools(notes)) {
    server.registerBaseTool(tool);
  }
  registerNoteResources(server, notes);
  registerNotePrompts(server, notes);
  return server;
}
```

```dart
// file: bin/server.dart
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/mcp/mcp.dart';
import 'package:my_server/src/note_repository.dart';

Future<void> main(List<String> args) async {
  final notes = NoteRepository();

  if (!args.contains('--http')) {
    await createMcpServer(notes).connect(StdioServerTransport());
    stderr.writeln('my_server ready on stdio');
    return;
  }

  final server = StreamableMcpServer(
    serverFactory: (sessionId) => createMcpServer(notes),
    host: '127.0.0.1',
    port: 3000,
  );
  await server.start();
  stderr.writeln('my_server listening on http://127.0.0.1:3000/mcp');
  await ProcessSignal.sigint.watch().first;
  await server.stop();
}
```

```dart
// file: test/add_note_tool_test.dart
import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:my_server/mcp/mcp.dart';
import 'package:my_server/src/note_repository.dart';
import 'package:test/test.dart';

void main() {
  late NoteRepository notes;
  late McpServer server;
  late McpClient client;
  late List<StreamController<List<int>>> pipes;

  setUp(() async {
    notes = NoteRepository();
    server = createMcpServer(notes);
    final toServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    pipes = [toServer, toClient];
    await server.connect(
      IOStreamTransport(stream: toServer.stream, sink: toClient.sink),
    );
    client = McpClient(const Implementation(name: 'test', version: '1.0.0'));
    await client.connect(
      IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
    );
  });

  tearDown(() async {
    await client.close();
    await server.close();
    for (final pipe in pipes) {
      await pipe.close();
    }
  });

  test('add_note stores the note', () async {
    final result = await client.callTool(
      const CallToolRequest(
        name: 'add_note',
        arguments: {'id': 'todo', 'text': 'Ship it'},
      ),
    );
    expect(result.isError, isFalse);
    expect(notes.read('todo'), 'Ship it');
  });

  test('add_note returns rejected input as a tool error', () async {
    final result = await client.callTool(
      const CallToolRequest(
        name: 'add_note',
        arguments: {'id': 'Bad Id', 'text': 'x'},
      ),
    );
    expect(result.isError, isTrue);
    expect(notes.ids, isEmpty);
  });
}
```

A cancellable tool that reports progress:

```dart
import 'package:mcp_dart/mcp_dart.dart';

Future<CallToolResult> exportRows(
  Map<String, dynamic> args,
  RequestHandlerExtra extra,
) async {
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
  return CallToolResult(content: [TextContent(text: 'Exported $rows rows.')]);
}
```

## More

- Server guide: https://github.com/leehack/mcp_dart/blob/main/doc/server-guide.md
- Tools, schemas, errors and progress: https://github.com/leehack/mcp_dart/blob/main/doc/tools.md
- MCP 2026-07-28 APIs (`registerStateless*`, tasks): https://github.com/leehack/mcp_dart/blob/main/doc/mcp-2026-07-28.md
- CLI (`create`, `inspect`, `skills install`): https://github.com/leehack/mcp_dart/tree/main/packages/mcp_dart_cli
- Remote HTTP deployment: the `mcp-dart-streamable-http` skill.
