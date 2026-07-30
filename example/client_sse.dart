import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Legacy MCP HTTP+SSE client example.
///
/// New clients should use Streamable HTTP. This example is intentionally
/// explicit about the deprecated transport and MCP 2025-11-25 compatibility
/// profile so it does not change the SDK's modern default behavior.
Future<void> main() async {
  final serverUrl = Uri.parse(
    Platform.environment['MCP_SERVER_URL'] ?? 'http://127.0.0.1:3000/sse',
  );
  // This example exists specifically to demonstrate the deprecated transport.
  // ignore: deprecated_member_use_from_same_package
  final transport = SseClientTransport(serverUrl);
  final client = McpClient(
    const Implementation(name: 'example-sse-client', version: '1.0.0'),
    options: const McpClientOptions(protocol: McpProtocol.legacy),
  );

  try {
    await client.connect(transport);
    print('Negotiated protocol: ${client.getProtocolVersion()}');

    final tools = await client.listTools();
    print(
      'Available tools: ${tools.tools.map((tool) => tool.name).join(', ')}',
    );

    final result = await client.callTool(
      const CallToolRequest(
        name: 'calculate',
        arguments: {
          'operation': 'add',
          'a': 5,
          'b': 10,
        },
      ),
    );
    final text = result.content.whereType<TextContent>().firstOrNull?.text;
    print(text ?? result.toJson());
  } catch (error, stackTrace) {
    stderr
      ..writeln('Legacy SSE client failed: $error')
      ..writeln(stackTrace);
    exitCode = 1;
  } finally {
    await client.close();
  }
}
