import 'dart:convert';
import 'dart:io';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

/// A client for interacting with an MCP server and Anthropic's API.
class AnthropicMcpClient {
  final mcp_dart.McpClient mcp;
  final AnthropicClient anthropic;
  mcp_dart.StdioClientTransport? transport;
  List<mcp_dart.Tool> tools = [];

  AnthropicMcpClient(this.anthropic, this.mcp);

  /// Connects to the MCP server using the specified command and arguments.
  ///
  /// [cmd] is the command to execute.
  /// [args] is the list of arguments for the command.
  Future<void> connectToServer(String cmd, List<String> args) async {
    try {
      transport = mcp_dart.StdioClientTransport(
        mcp_dart.StdioServerParameters(
          command: cmd,
          args: args,
          stderrMode: ProcessStartMode.normal,
        ),
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
          toolsResult.tools.map((tool) {
            return Tool.custom(
              name: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema.toJson(),
            );
          }).toList();

      print(
        "Connected to server with tools: ${tools.map((t) => t.name).toList()}",
      );
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
    final messages = [
      Message(role: MessageRole.user, content: MessageContent.text(query)),
    ];

    final response = await anthropic.createMessage(
      request: CreateMessageRequest(
        model: Model.model(Models.claude35Sonnet20241022),
        maxTokens: 1000,
        messages: messages,
        tools: tools,
      ),
    );

    final finalText = <String>[];
    final toolResults = <dynamic>[];

    for (final content in response.content.blocks) {
      if (content.type == "text") {
        finalText.add(content.text);
      } else if (content case ToolUseBlock()) {
        final result = await mcp.callTool(
          mcp_dart.CallToolRequest(
            name: content.name,
            arguments: content.input,
          ),
        );
        toolResults.add(result);
        finalText.add(
          "[Calling tool ${content.name} with args ${jsonEncode(content.input)}]",
        );

        messages.add(
          Message(
            role: MessageRole.user,
            content: MessageContent.blocks(
              result.content.map((c) => Block.fromJson(c.toJson())).toList(),
            ),
          ),
        );

        final nextResponse = await anthropic.createMessage(
          request: CreateMessageRequest(
            model: Model.model(Models.claude35Sonnet20241022),
            maxTokens: 1000,
            messages: messages,
          ),
        );

        finalText.add(
          nextResponse.content.blocks.first.type == "text"
              ? nextResponse.content.blocks.first.text
              : "",
        );
      }
    }

    return finalText.join("\n");
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
