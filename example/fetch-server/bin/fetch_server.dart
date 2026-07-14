import 'dart:io';

import 'package:fetch_server/safe_fetcher.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main(List<String> arguments) async {
  final server = McpServer(
    const Implementation(
      name: 'fetch',
      version: '0.1.0',
    ),
  );
  final fetcher = SafeFetcher();

  server.registerTool(
    'fetch',
    description: 'Fetches bounded text content from a public HTTP(S) URL.',
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
      },
      required: const ['url'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    ),
    callback: (args, _) async {
      final url = args['url'];
      final maxLengthValue = args['max_length'];
      final startIndexValue = args['start_index'];

      if (url == null || url is! String || url.isEmpty) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'Missing or invalid "url" argument.',
        );
      }
      if (maxLengthValue != null && maxLengthValue is! int) {
        throw McpError(
          ErrorCode.invalidParams.value,
          '"max_length" must be an integer.',
        );
      }
      if (startIndexValue != null && startIndexValue is! int) {
        throw McpError(
          ErrorCode.invalidParams.value,
          '"start_index" must be an integer.',
        );
      }

      final maxLength = maxLengthValue as int? ?? 5000;
      final startIndex = startIndexValue as int? ?? 0;
      if (maxLength <= 0 || maxLength >= 1000000) {
        throw McpError(
          ErrorCode.invalidParams.value,
          '"max_length" must be between 1 and 999999.',
        );
      }
      if (startIndex < 0) {
        throw McpError(
          ErrorCode.invalidParams.value,
          '"start_index" must be zero or greater.',
        );
      }

      final uri = Uri.tryParse(url);
      if (uri == null) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'The "url" argument is not a valid URI.',
        );
      }

      try {
        final response = await fetcher.fetch(uri);

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

        var content = response.body;

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
