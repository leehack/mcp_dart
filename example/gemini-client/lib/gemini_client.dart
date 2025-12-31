import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

/// Extension to provide utility methods for the `Schema` class.
extension SchemaExtension on Schema {
  /// Creates a `Schema` object from a JSON map.
  ///
  /// [json] is the JSON map representing the schema.
  /// Throws [UnsupportedError] if the schema type is unsupported.
  static Schema? fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'object' =>
        json['properties'] != null
            ? json['properties'].isEmpty
                ? null
                : Schema.object(
                  properties: (json['properties'] as Map<String, dynamic>).map(
                    (key, value) =>
                        MapEntry(key, SchemaExtension.fromJson(value)!),
                  ),
                )
            : throw UnsupportedError(
              "Unsupported schema type: ${json['type']}",
            ),
      'string' =>
        json['enum'] != null
            ? Schema.enumString(
              enumValues: json['enum'].cast<String>(),
              description: json['description'],
            )
            : Schema.string(description: json['description']),
      'number' => Schema.number(description: json['description']),
      'boolean' => Schema.boolean(description: json['description']),
      'array' =>
        json['items'] != null
            ? Schema.array(items: SchemaExtension.fromJson(json['items'])!)
            : throw UnsupportedError(
              "Unsupported schema type: ${json['type']}",
            ),
      _ => throw UnsupportedError("Unsupported schema type: ${json['type']}"),
    };
  }
}

/// A client for interacting with an MCP server and Google's Generative AI API.
class GoogleMcpClient {
  /// The MCP client instance.
  final mcp_dart.McpClient mcp;

  /// The Generative AI model instance.
  final GenerativeModel model;

  /// The transport layer for communicating with the MCP server.
  mcp_dart.StdioClientTransport? transport;

  /// List of tools available for use.
  List<Tool> tools = [];

  /// Creates an instance of [GoogleMcpClient].
  ///
  /// [model] is the Generative AI model.
  /// [mcp] is the MCP client instance.
  GoogleMcpClient(this.model, this.mcp);

  /// Connects to the MCP server using the specified command and arguments.
  ///
  /// [cmd] is the command to execute.
  /// [args] is the list of arguments for the command.
  /// Throws an error if the connection fails.
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
            return Tool(
              functionDeclarations: [
                FunctionDeclaration(
                  tool.name,
                  tool.description ?? '',
                  SchemaExtension.fromJson(tool.inputSchema.toJson()),
                ),
              ],
            );
          }).toList();
    } catch (e) {
      print("Failed to connect to MCP server: $e");
      rethrow;
    }
  }

  /// Processes a user query by sending it to Google's Generative AI API and handling tool usage.
  ///
  /// [query] is the user's input query.
  /// Returns the response as a string.
  Future<String> processQuery(String query) async {
    final messages = [Content.text(query)];
    final response = await model.generateContent(messages, tools: tools);
    final finalText = <String>[];

    for (final candidate in response.candidates) {
      final part = candidate.content.parts.first;
      if (part is TextPart) {
        finalText.add(part.text);
      } else if (part is FunctionCall) {
        final result = await mcp.callTool(
          mcp_dart.CallToolRequest(name: part.name, arguments: part.args),
        );
        finalText.add(
          "[Calling tool ${part.name} with args ${jsonEncode(part.args)}]",
        );

        for (final c in result.content) {
          if (c is mcp_dart.TextContent) {
            messages.add(Content.text(c.text));
          }
          if (c is mcp_dart.ImageContent) {
            messages.add(Content.data(c.mimeType, base64Decode(c.data)));
            print(c.data);
          }
        }
        final finalRes = await model.generateContent(messages);
        finalText.add(
          finalRes.candidates.first.content.parts.map((c) {
            if (c is TextPart) {
              return c.text;
            } else if (c is DataPart) {
              return "[Image: ${c.mimeType}]";
            } else if (c is FilePart) {
              return "[File: ${c.uri}]";
            } else {
              return "[Unknown part type]";
            }
          }).join(),
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
