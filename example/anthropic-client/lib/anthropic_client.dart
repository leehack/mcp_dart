import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

/// Generates the next Anthropic message for a conversation transcript.
typedef AnthropicMessageGenerator =
    Future<Message> Function(MessageCreateRequest request);

/// Executes an MCP tool call.
typedef McpToolCaller =
    Future<mcp_dart.CallToolResult> Function(mcp_dart.CallToolRequest request);

/// Decides whether an Anthropic-requested MCP tool call may run.
typedef McpToolApprover =
    Future<bool> Function(String name, Map<String, Object?> arguments);

/// Lists one page of MCP tools.
typedef McpToolLister =
    Future<mcp_dart.ListToolsResult> Function(
      mcp_dart.ListToolsRequest? request,
    );

/// Reads one line of interactive input, or returns `null` at end of input.
typedef AnthropicLineReader = Future<String?> Function();

/// Writes one line of interactive output.
typedef AnthropicLineWriter = void Function(String message);

/// Current default model for this example.
const defaultAnthropicModel = 'claude-sonnet-5';

final _anthropicToolNamePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
const _anthropicEnvironmentVariables = {'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL'};

/// A client for interacting with an MCP server and Anthropic's API.
class AnthropicMcpClient {
  final mcp_dart.McpClient mcp;
  final AnthropicClient anthropic;
  final AnthropicMessageGenerator? _messageGenerator;
  final McpToolCaller? _toolCaller;
  final McpToolApprover? _toolApprover;
  final McpToolLister? _toolLister;
  final Map<String, String> _mcpNameByAnthropicName = {};
  final int maxToolPages;
  final int maxToolRounds;
  final String model;
  mcp_dart.StdioClientTransport? transport;
  List<ToolDefinition> tools = [];

  AnthropicMcpClient(
    this.anthropic,
    this.mcp, {
    AnthropicMessageGenerator? messageGenerator,
    McpToolCaller? toolCaller,
    McpToolApprover? toolApprover,
    McpToolLister? toolLister,
    this.maxToolPages = 100,
    this.maxToolRounds = 8,
    this.model = defaultAnthropicModel,
  }) : _messageGenerator = messageGenerator,
       _toolCaller = toolCaller,
       _toolApprover = toolApprover,
       _toolLister = toolLister {
    if (maxToolPages < 1) {
      throw ArgumentError.value(maxToolPages, 'maxToolPages', 'must be > 0');
    }
    if (maxToolRounds < 1) {
      throw ArgumentError.value(maxToolRounds, 'maxToolRounds', 'must be > 0');
    }
  }

  /// Connects to the MCP server using the specified command and arguments.
  ///
  /// [cmd] is the command to execute.
  /// [args] is the list of arguments for the command.
  Future<void> connectToServer(String cmd, List<String> args) async {
    try {
      final serverEnvironment = Map<String, String>.of(Platform.environment)
        ..removeWhere(
          (name, _) =>
              _anthropicEnvironmentVariables.contains(name.toUpperCase()),
        );
      transport = mcp_dart.StdioClientTransport(
        mcp_dart.StdioServerParameters(
          command: cmd,
          args: args,
          environment: serverEnvironment,
          includeParentEnvironment: false,
          stderrMode: ProcessStartMode.inheritStdio,
        ),
      );
      transport!.onerror = (error) {
        print("Transport error: $error");
      };
      transport!.onclose = () {
        print("Transport closed.");
      };
      await mcp.connect(transport!);

      await refreshTools();

      print(
        "Connected to server with tools: "
        "${_mcpNameByAnthropicName.entries.map((entry) {
          return entry.key == entry.value ? jsonEncode(entry.value) : '${jsonEncode(entry.value)} (as ${jsonEncode(entry.key)})';
        }).toList()}",
      );
    } catch (e) {
      print("Failed to connect to MCP server: $e");
      rethrow;
    }
  }

  /// Loads every `tools/list` page and prepares Anthropic-compatible aliases.
  Future<void> refreshTools() async {
    final discoveredTools = <mcp_dart.Tool>[];
    final seenCursors = <String>{};
    String? cursor;

    for (var pageNumber = 0; pageNumber < maxToolPages; pageNumber++) {
      final result = await _listTools(
        cursor == null ? null : mcp_dart.ListToolsRequest(cursor: cursor),
      );
      discoveredTools.addAll(result.tools);

      final nextCursor = result.nextCursor;
      if (nextCursor == null) {
        _configureTools(discoveredTools);
        return;
      }
      if (!seenCursors.add(nextCursor)) {
        throw StateError('MCP tools/list repeated cursor "$nextCursor".');
      }
      cursor = nextCursor;
    }

    throw StateError('MCP tools/list exceeded $maxToolPages pages.');
  }

  /// Processes a user query by sending it to Anthropic's API and handling tool usage.
  ///
  /// Tool discovery is refreshed once before the query and then held stable
  /// across every tool-use round so provider call/result correlation cannot
  /// change mid-query.
  /// [query] is the user's input query.
  /// Returns the response as a string.
  Future<String> processQuery(String query) async {
    await refreshTools();
    final queryTools = List<ToolDefinition>.unmodifiable(tools);
    final queryMcpNameByAnthropicName = Map<String, String>.unmodifiable(
      _mcpNameByAnthropicName,
    );
    final messages = <InputMessage>[InputMessage.user(query)];
    final finalText = <String>[];

    for (var toolRound = 0; ;) {
      final response = await _createMessage(
        MessageCreateRequest(
          model: model,
          maxTokens: 1000,
          messages: messages,
          thinking: ThinkingConfig.disabled(),
          tools: queryTools,
        ),
      );
      final responseBlocks = response.content;

      for (final block in responseBlocks.whereType<TextBlock>()) {
        finalText.add(block.text);
      }

      final toolUses = responseBlocks.whereType<ToolUseBlock>().toList();
      final stopReason = response.stopReason;
      if (stopReason == StopReason.endTurn ||
          stopReason == StopReason.stopSequence) {
        if (toolUses.isNotEmpty) {
          throw StateError(
            'Anthropic returned tool_use content with stop reason '
            '${stopReason?.value}.',
          );
        }
        return finalText.join("\n");
      }
      if (stopReason != StopReason.toolUse) {
        throw StateError(_stopReasonFailure(response));
      }
      if (toolUses.isEmpty) {
        throw StateError(
          'Anthropic stopped for tool use without a tool_use block.',
        );
      }
      if (toolRound >= maxToolRounds) {
        throw StateError('Anthropic exceeded $maxToolRounds tool rounds');
      }
      toolRound++;

      // The assistant tool-use turn must precede the matching user results.
      messages.add(
        InputMessage.assistantBlocks(
          responseBlocks
              .map((block) => InputContentBlock.fromJson(block.toJson()))
              .toList(),
        ),
      );

      final resultBlocks = <InputContentBlock>[];
      for (final toolUse in toolUses) {
        final mcpToolName = queryMcpNameByAnthropicName[toolUse.name];
        if (mcpToolName == null) {
          finalText.add(
            '[Rejected unadvertised tool ${jsonEncode(toolUse.name)}]',
          );
          resultBlocks.add(
            ToolResultInputBlock.text(
              toolUseId: toolUse.id,
              text:
                  'Anthropic requested unadvertised MCP tool '
                  '${jsonEncode(toolUse.name)}.',
              isError: true,
            ),
          );
          continue;
        }

        final approver = _toolApprover;
        final approved =
            approver != null &&
            await approver(
              mcpToolName,
              Map<String, Object?>.unmodifiable(toolUse.input),
            );
        if (!approved) {
          finalText.add('[Declined tool ${jsonEncode(mcpToolName)}]');
          resultBlocks.add(
            ToolResultInputBlock.text(
              toolUseId: toolUse.id,
              text: 'The user declined this MCP tool call.',
              isError: true,
            ),
          );
          continue;
        }

        finalText.add(
          '[Calling tool ${jsonEncode(mcpToolName)} with args '
          '${jsonEncode(toolUse.input)}]',
        );
        try {
          final result = await _callTool(
            mcp_dart.CallToolRequest(
              name: mcpToolName,
              arguments: toolUse.input,
            ),
          );
          resultBlocks.add(_toAnthropicToolResult(toolUse.id, result));
        } on mcp_dart.McpError catch (error) {
          if (!_isRecoverableToolError(error)) {
            rethrow;
          }
          resultBlocks.add(
            ToolResultInputBlock.text(
              toolUseId: toolUse.id,
              text:
                  'MCP tool ${jsonEncode(mcpToolName)} failed: '
                  '${error.message}',
              isError: true,
            ),
          );
        }
      }

      messages.add(InputMessage.userBlocks(resultBlocks));
    }
  }

  Future<mcp_dart.ListToolsResult> _listTools(
    mcp_dart.ListToolsRequest? request,
  ) {
    final lister = _toolLister;
    if (lister != null) {
      return lister(request);
    }
    return mcp.listTools(params: request);
  }

  void _configureTools(List<mcp_dart.Tool> discoveredTools) {
    final originalNames = <String>{};
    for (final tool in discoveredTools) {
      if (!originalNames.add(tool.name)) {
        throw StateError(
          'MCP server returned duplicate tool ${jsonEncode(tool.name)}.',
        );
      }
    }

    final reservedNames = {
      for (final tool in discoveredTools)
        if (_anthropicToolNamePattern.hasMatch(tool.name)) tool.name,
    };
    final usedNames = <String>{};
    final mcpNameByAnthropicName = <String, String>{};
    final configuredTools = <ToolDefinition>[];

    for (final tool in discoveredTools) {
      final inputSchema = tool.inputSchema.toJson();
      if (inputSchema['type'] != 'object') {
        throw UnsupportedError(
          'Anthropic requires an object-root input schema, but MCP tool '
          '${jsonEncode(tool.name)} advertises ${jsonEncode(inputSchema)}.',
        );
      }
      final anthropicName =
          _anthropicToolNamePattern.hasMatch(tool.name)
              ? tool.name
              : _anthropicToolAlias(tool.name, {
                ...reservedNames,
                ...usedNames,
              });
      usedNames.add(anthropicName);
      mcpNameByAnthropicName[anthropicName] = tool.name;

      configuredTools.add(
        ToolDefinition.custom(
          Tool(
            name: anthropicName,
            description: tool.description,
            inputSchema: InputSchema.fromJson(inputSchema),
          ),
        ),
      );
    }

    tools = configuredTools;
    _mcpNameByAnthropicName
      ..clear()
      ..addAll(mcpNameByAnthropicName);
  }

  String _anthropicToolAlias(String originalName, Set<String> unavailable) {
    var base = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (base.isEmpty) {
      base = 'tool';
    }

    final hash = _stableToolNameHash(originalName);
    for (var attempt = 0; ; attempt++) {
      final suffix = attempt == 0 ? '_$hash' : '_${hash}_$attempt';
      final prefixLength = 64 - suffix.length;
      final prefix =
          base.length <= prefixLength ? base : base.substring(0, prefixLength);
      final candidate = '$prefix$suffix';
      if (!unavailable.contains(candidate)) {
        return candidate;
      }
    }
  }

  String _stableToolNameHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _stopReasonFailure(Message response) {
    return switch (response.stopReason) {
      StopReason.maxTokens =>
        'Anthropic response was truncated because max_tokens was reached.',
      StopReason.modelContextWindowExceeded =>
        'Anthropic response was truncated because the context window was exceeded.',
      StopReason.refusal =>
        'Anthropic refused the request${response.stopDetails?.explanation == null ? '.' : ': ${response.stopDetails!.explanation}'}',
      StopReason.pauseTurn =>
        'Anthropic paused the turn unexpectedly for this client-tool-only request.',
      StopReason.compaction =>
        'Anthropic returned an unsupported compaction stop reason.',
      StopReason.endTurn || StopReason.stopSequence || StopReason.toolUse =>
        'Unexpected Anthropic stop reason: ${response.stopReason?.value}.',
      null => 'Anthropic response omitted stop_reason.',
    };
  }

  bool _isRecoverableToolError(mcp_dart.McpError error) {
    return error.code != mcp_dart.ErrorCode.connectionClosed.value;
  }

  ToolResultInputBlock _toAnthropicToolResult(
    String toolUseId,
    mcp_dart.CallToolResult result,
  ) {
    final content = <ToolResultContent>[
      for (final item in result.content) ..._toAnthropicResultContent(item),
    ];

    if (result.hasStructuredContent) {
      final structuredJson = jsonEncode(result.structuredContentJson!.toJson());
      final alreadyIncluded = content.whereType<ToolResultTextContent>().any(
        (item) => item.text == structuredJson,
      );
      if (!alreadyIncluded) {
        content.add(
          ToolResultContent.text('Structured content: $structuredJson'),
        );
      }
    }

    return ToolResultInputBlock(
      toolUseId: toolUseId,
      content: content.isEmpty ? null : content,
      isError: result.isError ? true : null,
    );
  }

  List<ToolResultContent> _toAnthropicResultContent(mcp_dart.Content content) {
    return switch (content) {
      mcp_dart.TextContent(:final text) => [ToolResultContent.text(text)],
      final mcp_dart.ImageContent image => [_toAnthropicImageContent(image)],
      final mcp_dart.AudioContent audio => [
        ToolResultContent.text(
          jsonEncode({
            'type': 'audio',
            'data': audio.data,
            'mimeType': audio.mimeType,
          }),
        ),
      ],
      final mcp_dart.EmbeddedResource embedded => [
        ToolResultContent.text(
          jsonEncode({
            'type': 'resource',
            'resource': _resourceForModel(embedded.resource),
          }),
        ),
      ],
      final mcp_dart.ResourceLink link => [
        ToolResultContent.text(
          jsonEncode({
            'type': 'resource_link',
            'uri': link.uri,
            'name': link.name,
            if (link.title != null) 'title': link.title,
            if (link.description != null) 'description': link.description,
            if (link.mimeType != null) 'mimeType': link.mimeType,
            if (link.size != null) 'size': link.size,
          }),
        ),
      ],
      mcp_dart.UnknownContent(:final type) => [
        ToolResultContent.text(jsonEncode({'type': type})),
      ],
    };
  }

  ToolResultContent _toAnthropicImageContent(mcp_dart.ImageContent image) {
    try {
      return ToolResultContent.image(
        ImageSource.base64(
          data: image.data,
          mediaType: ImageMediaType.fromMimeType(image.mimeType),
        ),
      );
    } on FormatException {
      return ToolResultContent.text(
        jsonEncode({
          'type': 'image',
          'data': image.data,
          'mimeType': image.mimeType,
        }),
      );
    }
  }

  Map<String, dynamic> _resourceForModel(mcp_dart.ResourceContents resource) {
    return {
      'uri': resource.uri,
      if (resource.mimeType != null) 'mimeType': resource.mimeType,
      ...switch (resource) {
        mcp_dart.TextResourceContents(:final text) => {'text': text},
        mcp_dart.BlobResourceContents(:final blob) => {'blob': blob},
        mcp_dart.UnknownResourceContents() => <String, dynamic>{},
      },
    };
  }

  Future<Message> _createMessage(MessageCreateRequest request) {
    final generator = _messageGenerator;
    if (generator != null) {
      return generator(request);
    }
    return anthropic.messages.create(request);
  }

  Future<mcp_dart.CallToolResult> _callTool(mcp_dart.CallToolRequest request) {
    final caller = _toolCaller;
    if (caller != null) {
      return caller(request);
    }
    return mcp.callTool(request);
  }

  /// Starts a chat loop, allowing the user to input queries interactively.
  ///
  /// Type 'quit' to exit the loop.
  Future<bool> chatLoop({
    AnthropicLineReader? readLine,
    AnthropicLineWriter? writeLine,
    AnthropicLineWriter? writeError,
  }) async {
    final iterator =
        readLine == null
            ? StreamIterator(
              stdin.transform(utf8.decoder).transform(const LineSplitter()),
            )
            : null;
    Future<String?> readFromStdin() async {
      if (await iterator!.moveNext()) {
        return iterator.current;
      }
      return null;
    }

    final reader = readLine ?? readFromStdin;
    final writer = writeLine ?? print;
    writer("\nMCP Client Started!");
    writer("Type your queries or 'quit' to exit.");

    try {
      return await _processLines(reader, onOutput: writer, onError: writeError);
    } finally {
      await iterator?.cancel();
    }
  }

  /// Processes interactive input and reports whether every query succeeded.
  Future<bool> processMessages(
    Stream<String> messages, {
    void Function(String message)? onOutput,
    void Function(String message)? onError,
  }) async {
    final iterator = StreamIterator(messages);
    Future<String?> readLine() async {
      if (await iterator.moveNext()) {
        return iterator.current;
      }
      return null;
    }

    try {
      return await _processLines(
        readLine,
        onOutput: onOutput,
        onError: onError,
      );
    } finally {
      await iterator.cancel();
    }
  }

  Future<bool> _processLines(
    AnthropicLineReader readLine, {
    AnthropicLineWriter? onOutput,
    AnthropicLineWriter? onError,
  }) async {
    final writeOutput = onOutput ?? (message) => print(message);
    final writeError = onError ?? (message) => stderr.writeln(message);
    var succeeded = true;

    while (true) {
      final message = await readLine();
      if (message == null || message.trim().toLowerCase() == "quit") {
        break;
      }
      try {
        final response = await processQuery(message);
        writeOutput("\n$response");
      } catch (e) {
        writeError("Error processing query: $e");
        succeeded = false;
      }
    }

    return succeeded;
  }

  /// Cleans up the MCP connection and Anthropic HTTP client.
  Future<void> cleanup() async {
    try {
      await mcp.close();
    } finally {
      anthropic.close();
    }
  }
}
