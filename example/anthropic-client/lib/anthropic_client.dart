import 'dart:convert';
import 'dart:io';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

/// A client for interacting with an MCP server and Anthropic's API.
class AnthropicMcpClient {
  final mcp_dart.McpClient mcp;
  final AnthropicClient anthropic;
  mcp_dart.StdioClientTransport? transport;
  List<ToolDefinition> tools = [];

  AnthropicMcpClient(this.anthropic, this.mcp);

  /// Connects to the MCP server using the specified command and arguments.
  ///
  /// [cmd] is the command to execute.
  /// [args] is the list of arguments for the command.
  Future<void> connectToServer(String cmd, List<String> args) async {
    try {
      transport = mcp_dart.StdioClientTransport(
        mcp_dart.StdioServerParameters(command: cmd, args: args, stderrMode: ProcessStartMode.normal),
      );
      transport!.onerror = (error) {
        print("Transport error: $error");
      };
      transport!.onclose = () {
        print("Transport closed.");
      };
      await mcp.connect(transport!);

      final toolsResult = await mcp.listTools();
      tools =
          toolsResult.tools
              .map((tool) {
                return _toAnthropicTool(tool);
              })
              .cast<ToolDefinition>()
              .toList();

      print("Connected to server with tools: ${toolsResult.tools.map((tool) => tool.name).toList()}");
    } catch (e) {
      print("Failed to connect to MCP server: $e");
      rethrow;
    }
  }

  /// Processes a user query by sending it to Anthropic's API and handling tool usage.
  ///
  /// [query] is the user's input query.
  /// Returns the response as a string.
  Future<String> processQuery(String query) async {
    final messages = <InputMessage>[InputMessage(role: MessageRole.user, content: MessageContent.text(query))];
    final transcript = <String>[];

    while (true) {
      final response = await anthropic.messages.create(
        MessageCreateRequest(
          model: 'claude-3-5-sonnet-20241022',
          maxTokens: 1000,
          messages: messages,
          tools: tools.isEmpty ? null : tools,
        ),
      );

      messages.add(_assistantMessageFromResponse(response));

      final toolUses = <ToolUseBlock>[];
      for (final block in response.content) {
        switch (block) {
          case TextBlock(:final text):
            transcript.add(text);
          case ToolUseBlock():
            toolUses.add(block);
          default:
            break;
        }
      }

      if (toolUses.isEmpty) {
        return transcript.join("\n");
      }

      final toolResultBlocks = <InputContentBlock>[];
      for (final toolUse in toolUses) {
        final result = await mcp.callTool(mcp_dart.CallToolRequest(name: toolUse.name, arguments: toolUse.input));
        transcript.add("[Calling tool ${toolUse.name} with args ${jsonEncode(toolUse.input)}]");
        toolResultBlocks.add(
          InputContentBlock.toolResult(
            toolUseId: toolUse.id,
            content: [ToolResultContent.text(_stringifyToolResult(result))],
            isError: result.isError,
          ),
        );
      }

      messages.add(InputMessage(role: MessageRole.user, content: MessageContent.blocks(toolResultBlocks)));
    }
  }

  InputMessage _assistantMessageFromResponse(Message response) {
    final blocks = response.content.map(_toInputContentBlock).nonNulls.toList();
    if (blocks.isNotEmpty) {
      return InputMessage(role: MessageRole.assistant, content: MessageContent.blocks(blocks));
    }
    return InputMessage(role: MessageRole.assistant, content: MessageContent.text(""));
  }

  InputContentBlock? _toInputContentBlock(ContentBlock block) {
    return switch (block) {
      TextBlock(:final text) => InputContentBlock.text(text),
      ToolUseBlock(:final id, :final name, :final input) => InputContentBlock.toolUse(id: id, name: name, input: input),
      _ => null,
    };
  }

  String _stringifyToolResult(mcp_dart.CallToolResult result) {
    if (result.structuredContent != null) {
      return jsonEncode(result.structuredContent);
    }

    final parts =
        result.content.map((content) {
          return switch (content) {
            mcp_dart.TextContent(:final text) => text,
            _ => jsonEncode(content.toJson()),
          };
        }).toList();

    if (parts.isEmpty) {
      return jsonEncode(result.toJson());
    }

    return parts.join("\n");
  }

  ToolDefinition _toAnthropicTool(mcp_dart.Tool tool) {
    final inputSchema = tool.inputSchema.toJson();
    return ToolDefinition.custom(
      Tool(
        name: tool.name,
        description: tool.description,
        inputSchema: InputSchema(
          properties: (inputSchema['properties'] as Map?)?.cast<String, dynamic>(),
          required: (inputSchema['required'] as List?)?.map((value) => value.toString()).toList(),
        ),
      ),
    );
  }

  /// Starts a chat loop, allowing the user to input queries interactively.
  ///
  /// Type 'quit' to exit the loop.
  Future<void> chatLoop() async {
    final stdinStream = stdin.transform(utf8.decoder).transform(LineSplitter());

    print("\nMCP Client Started!");
    print("Type your queries or 'quit' to exit.");

    await for (final message in stdinStream) {
      if (message.toLowerCase() == "quit") {
        break;
      }
      try {
        final response = await processQuery(message);
        print("\n$response");
      } catch (e) {
        print("Error processing query: $e");
      }
    }
  }

  /// Cleans up resources by closing the MCP client connection.
  Future<void> cleanup() async {
    await mcp.close();
  }
}
