import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anthropic_client/anthropic_client.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// The main entry point for the MCP client application.
///
/// [args] should contain the command and its arguments to connect to the MCP server.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run bin/main.dart <command> [args ...]');
    exitCode = 64;
    return;
  }

  final apiKey = Platform.environment['ANTHROPIC_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('Please set the ANTHROPIC_API_KEY environment variable.');
    exitCode = 78;
    return;
  }

  final configuredModel = Platform.environment['ANTHROPIC_MODEL']?.trim();
  final model =
      configuredModel == null || configuredModel.isEmpty
          ? defaultAnthropicModel
          : configuredModel;
  final console = _ConsoleLines();

  final client = AnthropicMcpClient(
    AnthropicClient.withApiKey(apiKey),
    McpClient(const Implementation(name: 'mcp-client-cli', version: '1.0.0')),
    model: model,
    toolApprover: (name, arguments) async {
      stdout.writeln(
        '\nAnthropic requested MCP tool ${jsonEncode(name)} with arguments:\n'
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
    final completedWithoutErrors = await client.chatLoop(
      readLine: console.nextLine,
    );
    if (!completedWithoutErrors) {
      exitCode = 1;
    }
    print('Exiting...');
  } catch (error, stackTrace) {
    stderr.writeln('Anthropic MCP client failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    try {
      await client.cleanup();
    } catch (error) {
      stderr.writeln('Failed to clean up the Anthropic MCP client: $error');
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
