import 'package:mcp_dart/mcp_dart.dart';

/// Runs the strict MCP 2026-07-28 example over stdio.
///
/// Run from the repository root:
///
/// ```bash
/// dart run example/mcp_2026_07_28/client.dart
/// ```
Future<void> main() async {
  final client = McpClient(
    const Implementation(name: 'mcp-2026-example-client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.require2026,
      capabilities: ClientCapabilities(
        elicitation: ClientElicitation.formOnly(),
      ),
    ),
  );

  client.onElicitRequest = (request) async {
    print('Input requested: ${request.message}');
    // A real host would collect and validate this value in its UI.
    return const ElicitResult(
      action: 'accept',
      content: {'name': 'Ada'},
    );
  };

  final transport = StdioClientTransport(
    const StdioServerParameters(
      command: 'dart',
      args: ['run', 'example/mcp_2026_07_28/server.dart'],
    ),
  );

  try {
    await client.connect(transport);
    final protocolVersion = client.getProtocolVersion();
    if (protocolVersion != previewProtocolVersion) {
      throw StateError(
        'Expected $previewProtocolVersion, got $protocolVersion',
      );
    }
    print('Negotiated protocol: $protocolVersion');

    final subscription = client.listenSubscriptions(
      const SubscriptionsListenRequest(
        notifications: SubscriptionFilter(
          resourceSubscriptions: ['mcp://greeting/status'],
        ),
      ),
    );
    final resourceUpdate = subscription.notifications.firstWhere(
      (notification) => notification is JsonRpcResourceUpdatedNotification,
    );
    final acknowledged = await subscription.acknowledged;
    final resourceSubscriptions =
        acknowledged.notifications.resourceSubscriptions;
    if (resourceSubscriptions == null ||
        resourceSubscriptions.length != 1 ||
        resourceSubscriptions.single != 'mcp://greeting/status') {
      throw StateError('The resource subscription was not acknowledged.');
    }
    print('Subscription acknowledged: ${resourceSubscriptions.single}');
    await resourceUpdate;

    final status = await client.readResource(
      const ReadResourceRequest(uri: 'mcp://greeting/status'),
    );
    final statusContent = status.contents.single as TextResourceContents;
    print('Subscription update: ${statusContent.text}');

    final completed = await subscription.done;
    if (completed.subscriptionId != subscription.id) {
      throw StateError('Subscription completed with the wrong ID.');
    }
    print('Subscription closed cleanly.');

    final tools = await client.listTools();
    print('Tools: ${tools.tools.map((tool) => tool.name).join(', ')}');

    final result = await client.callTool(
      const CallToolRequest(name: 'personalized_greeting'),
    );
    print('Structured result: ${result.structuredContentJson?.toJson()}');
  } finally {
    await client.close();
  }
}
