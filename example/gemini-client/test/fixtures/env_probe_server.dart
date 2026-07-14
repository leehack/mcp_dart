import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Expected one probe output path.');
    exitCode = 64;
    return;
  }

  // Exceed typical pipe capacity before MCP startup. The client must keep
  // child stderr drained or this fixture will block before discovery.
  stderr.write(List.filled(2 * 1024 * 1024, 'x').join());
  await stderr.flush();

  await File(args.single).writeAsString(
    jsonEncode({
      'hasGeminiApiKey': _hasEnvironmentVariable('gemini_api_key'),
      'hasGeminiModel': _hasEnvironmentVariable('gemini_model'),
      'marker': Platform.environment['GEMINI_ENV_PROBE_MARKER'],
    }),
    flush: true,
  );

  final server = McpServer(
    const Implementation(name: 'environment-probe', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  server.registerTool(
    'environment_probe',
    inputSchema: JsonSchema.object(),
    callback:
        (_, _) async =>
            const CallToolResult(content: [TextContent(text: 'ok')]),
  );
  await server.connect(StdioServerTransport());
}

bool _hasEnvironmentVariable(String lowerCaseName) => Platform.environment.keys
    .any((name) => name.toLowerCase() == lowerCaseName);
