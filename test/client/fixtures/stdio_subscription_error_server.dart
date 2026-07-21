import 'package:mcp_dart/mcp_dart.dart';

class _UnserializableSubscriptionResult implements BaseResultData {
  const _UnserializableSubscriptionResult();

  @override
  Map<String, dynamic>? get meta => null;

  @override
  Map<String, dynamic> toJson() {
    throw StateError('sentinel subscription serialization failure');
  }
}

Future<void> main(List<String> arguments) async {
  final server = Server(
    const Implementation(
      name: 'stdio-subscription-error-fixture',
      version: '1.0.0',
    ),
    options: const McpServerOptions(
      protocol: McpProtocol.require2026,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
    ),
  );
  server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
    Method.subscriptionsListen,
    (request, extra) async {
      await extra.sendSubscriptionAcknowledged(
        const SubscriptionFilter(toolsListChanged: true),
      );
      if (arguments.contains('--serialization-error')) {
        return const _UnserializableSubscriptionResult();
      }
      throw McpError(
        ErrorCode.invalidRequest.value,
        'subscription failed',
      );
    },
    (id, params, meta) => JsonRpcSubscriptionsListenRequest(
      id: id,
      listenParams: SubscriptionsListenRequest.fromJson(params!),
      meta: meta,
    ),
  );

  await server.connect(StdioServerTransport());
}
