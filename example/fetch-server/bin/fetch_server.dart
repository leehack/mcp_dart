import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';

void main(List<String> arguments) async {
  final server = McpServer(
    const Implementation(
      name: 'fetch',
      version: '0.1.0',
    ),
  );

  server.registerTool(
    'fetch',
    description:
        'Fetches a URL from the internet and optionally extracts its contents as markdown.',
    inputSchema: ToolInputSchema(
      properties: {
        'url': JsonSchema.string(
          description: 'URL to fetch',
          format: 'uri',
          minLength: 1,
          title: 'Url',
        ),
        'max_length': JsonSchema.integer(
          defaultValue: 5000,
          description: 'Maximum number of characters to return.',
          exclusiveMaximum: 1000000,
          exclusiveMinimum: 0,
          title: 'Max Length',
        ),
        'start_index': JsonSchema.integer(
          defaultValue: 0,
          description:
              'On return output starting at this character index, useful if a previous fetch was truncated and more context is required.',
          minimum: 0,
          title: 'Start Index',
        ),
        'raw': JsonSchema.boolean(
          defaultValue: false,
          description:
              'Get the actual HTML content of the requested page, without simplification.',
          title: 'Raw',
        ),
      },
    ),
    callback: (args, _) async {
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
          return CallToolResult(
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
          [
            TextContent(
              text: content,
            ),
          ],
        );
      } catch (e) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Fetch error: ${e.toString()}',
            ),
          ],
          isError: true,
        );
      }
    },
  );

  final transport = StdioServerTransport();
  await server.connect(transport);
  stderr.writeln('Fetch MCP server running on stdio');
}
