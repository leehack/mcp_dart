import 'dart:io';

import 'package:gemini_client/gemini_client.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print("Usage: {command} arg1 arg2 ...");
    return;
  }

  final apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print("Please set the GEMINI_API_KEY environment variable.");
    return;
  }

  final client = GoogleMcpClient(
    GenerativeModel(model: 'gemini-2.0-flash', apiKey: apiKey),
    McpClient(Implementation(name: "gemini-client", version: "1.0.0")),
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
