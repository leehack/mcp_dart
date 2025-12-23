import 'dart:io';

import 'package:anthropic_client/anthropic_client.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// The main entry point for the MCP client application.
///
/// [args] should contain the command and its arguments to connect to the MCP server.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print("Usage: {command} arg1 arg2 ...");
    return;
  }

  final apiKey = Platform.environment['ANTHROPIC_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print("Please set the ANTHROPIC_API_KEY environment variable.");
    return;
  }

  final client = AnthropicMcpClient(
    AnthropicClient(apiKey: apiKey),
    McpClient(Implementation(name: "mcp-client-cli", version: "1.0.0")),
  );
  try {
    await client.connectToServer(args[0], args.sublist(1));
    await client.chatLoop();
    print("Exiting...");
  } finally {
    await client.cleanup();
    exit(0);
  }
}
