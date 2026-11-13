import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Search the web or fetch a page through the anonymous Parallel Search MCP.
Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !const ['search', 'fetch'].contains(args.first) ||
      args[1].trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run example/parallel_search.dart search "query"\n'
      '       dart run example/parallel_search.dart fetch "https://example.com"',
    );
    exitCode = 64;
    return;
  }
  if (args.first == 'fetch') {
    final url = Uri.tryParse(args[1]);
    if (url == null ||
        !const ['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty) {
      stderr.writeln('Fetch requires an HTTP or HTTPS URL.');
      exitCode = 64;
      return;
    }
  }

  final client = McpClient(
    const Implementation(
      name: 'mcp_dart-parallel-search-example',
      version: '1.0.0',
    ),
  );
  final transport = StreamableHttpClientTransport(
    Uri.parse('https://search.parallel.ai/mcp'),
    opts: const StreamableHttpClientTransportOptions(
      requestInit: {
        'headers': {
          'User-Agent': 'mcp_dart-parallel-search-example/1.0.0',
        },
      },
    ),
  );

  try {
    await client.connect(transport);
    final toolName = args.first == 'search' ? 'web_search' : 'web_fetch';
    final tools = await client.listTools();
    if (!tools.tools.any((tool) => tool.name == toolName)) {
      throw StateError('Server does not advertise $toolName.');
    }
    final result = await client.callTool(
      CallToolRequest(
        name: toolName,
        arguments: args.first == 'search'
            ? {
                'objective': args[1],
                'search_queries': [args[1]],
              }
            : {
                'urls': [args[1]],
              },
      ),
      options: const RequestOptions(timeout: Duration(seconds: 60)),
    );
    for (final content in result.content.whereType<TextContent>()) {
      print(content.text);
    }
    if (result.isError == true) {
      stderr.writeln('Parallel returned a tool error.');
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln('Parallel Search MCP failed: $error');
    exitCode = 1;
  } finally {
    await client.close();
  }
}
