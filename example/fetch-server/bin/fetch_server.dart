import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';

void main(List<String> arguments) async {
  final server = Server(
    const Implementation(
      name: 'fetch',
      version: '0.1.0',
    ),
    options: const ServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  server.setRequestHandler<JsonRpcListToolsRequest>(
    'tools/list',
    (request, _) async {
      return const ListToolsResult(
        tools: [
          Tool(
            name: 'fetch',
            description:
                'Fetches a URL from the internet and optionally extracts its contents as markdown.',
            inputSchema: ToolInputSchema(
              properties: {
                'url': {
                  'description': 'URL to fetch',
                  'format': 'uri',
                  'minLength': 1,
                  'title': 'Url',
                  'type': 'string',
                },
                'max_length': {
                  'default': 5000,
                  'description': 'Maximum number of characters to return.',
                  'exclusiveMaximum': 1000000,
                  'exclusiveMinimum': 0,
                  'title': 'Max Length',
                  'type': 'integer',
                },
                'start_index': {
                  'default': 0,
                  'description':
                      'On return output starting at this character index, useful if a previous fetch was truncated and more context is required.',
                  'minimum': 0,
                  'title': 'Start Index',
                  'type': 'integer',
                },
                'raw': {
                  'default': false,
                  'description':
                      'Get the actual HTML content of the requested page, without simplification.',
                  'title': 'Raw',
                  'type': 'boolean',
                },
              },
            ),
          ),
        ],
      );
    },
    (id, params, meta) => JsonRpcListToolsRequest.fromJson({
      'id': id,
      'params': params,
      if (meta != null) '_meta': meta,
    }),
  );

  server.setRequestHandler<JsonRpcCallToolRequest>(
    'tools/call',
    (request, _) async {
      if (request.callParams.name != 'fetch') {
        throw McpError(
          ErrorCode.methodNotFound.value,
          'Unknown tool: ${request.callParams.name}',
        );
      }

      final args = request.callParams.arguments ?? {};
      final url = args['url'];
      final maxLength = (args['max_length'] as num?)?.toInt() ?? 5000;
      final startIndex = (args['start_index'] as num?)?.toInt() ?? 0;
      final raw = args['raw'] as bool? ?? false;

      if (url == null || url is! String || url.isEmpty) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'Missing or invalid "url" argument.',
        );
      }

      try {
        final response = await http.get(Uri.parse(url));

        if (response.statusCode != 200) {
          return CallToolResult.fromContent(
            content: [
              TextContent(
                text:
                    'Fetch error: ${response.statusCode} - ${response.reasonPhrase}',
              ),
            ],
            isError: true,
          );
        }

        String content = response.body;

        // Basic handling for raw and truncation (more sophisticated parsing could be added here)
        if (!raw) {
          // In a real server, you might use a library to parse HTML and extract meaningful text.
          // For this example, we'll just return the raw text content.
        }

        // Apply start_index and max_length
        final effectiveStartIndex = startIndex.clamp(0, content.length);
        final effectiveEndIndex =
            (effectiveStartIndex + maxLength).clamp(0, content.length);
        content = content.substring(effectiveStartIndex, effectiveEndIndex);

        return CallToolResult.fromContent(
          content: [
            TextContent(
              text: content,
            ),
          ],
        );
      } catch (e) {
        return CallToolResult.fromContent(
          content: [
            TextContent(
              text: 'Fetch error: ${e.toString()}',
            ),
          ],
          isError: true,
        );
      }
    },
    (id, params, meta) => JsonRpcCallToolRequest.fromJson({
      'id': id,
      'params': params,
      if (meta != null) '_meta': meta,
    }),
  );

  final transport = StdioServerTransport();
  await server.connect(transport);
  stderr.writeln('Fetch MCP server running on stdio');
}
