import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gemini_client/gemini_client.dart';
import 'package:mcp_dart/mcp_dart.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run bin/main.dart <command> [args ...]');
    exitCode = 64;
    return;
  }

  final apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('Please set the GEMINI_API_KEY environment variable.');
    exitCode = 78;
    return;
  }

  final model = Platform.environment['GEMINI_MODEL']?.trim();
  final console = _ConsoleLines();
  final client = GoogleMcpClient(
    GeminiInteractionsApi(
      apiKey: apiKey,
      model: model == null || model.isEmpty ? 'gemini-3.5-flash' : model,
    ),
    McpClient(const Implementation(name: 'gemini-client', version: '1.0.0')),
    toolApprover: (name, arguments) async {
      stdout.writeln(
        '\nGemini requested MCP tool ${jsonEncode(name)} with arguments:\n'
        '${jsonEncode(arguments)}',
      );
      stdout.write('Approve this tool call? [y/N] ');
      await stdout.flush();
      final answer = (await console.nextLine())?.trim().toLowerCase();
      final approved = answer == 'y' || answer == 'yes';
      if (!approved) {
        stdout.writeln('Tool call declined.');
      }
      return approved;
    },
  );

  try {
    await client.connectToServer(args[0], args.sublist(1));
    await client.chatLoop(readLine: console.nextLine);
    print('Exiting...');
  } catch (error, stackTrace) {
    stderr.writeln('Gemini MCP client failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    try {
      await client.cleanup();
    } catch (error) {
      stderr.writeln('Failed to clean up the Gemini MCP client: $error');
      exitCode = 1;
    }
    await console.close();
  }
}

final class _ConsoleLines {
  final StreamIterator<String> _iterator = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );

  Future<String?> nextLine() async {
    if (await _iterator.moveNext()) {
      return _iterator.current;
    }
    return null;
  }

  Future<void> close() => _iterator.cancel();
}
