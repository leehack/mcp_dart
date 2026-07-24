import 'package:mcp_dart/mcp_dart.dart';

const _resourceUri = 'demo://status';

Future<void> main() async {
  late final McpServer server;
  server = McpServer(
    const Implementation(
      name: 'stateless-input-required-fixture',
      version: '1.0.0',
    ),
    options: const McpServerOptions(
      protocol: McpProtocol.require2026,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(subscribe: true),
      ),
    ),
  );

  server.registerStatelessTool(
    'collect_profile',
    description: 'Requests form input from the inspecting client.',
    callback: (args, extra) async {
      final response = extra.inputResponses?['profile'];
      if (response != null) {
        return CallToolResult.fromStructuredContent(response.toJson());
      }
      return InputRequiredResult(
        inputRequests: <String, InputRequest>{
          'profile': InputRequest.elicit(
            ElicitRequest.form(
              message: 'What name should the fixture use?',
              requestedSchema: JsonSchema.object(
                properties: <String, JsonSchema>{
                  'name': JsonSchema.string(minLength: 1),
                },
                required: <String>['name'],
              ),
            ),
          ),
        },
      );
    },
  );

  server.registerStatelessTool(
    'list_client_roots',
    description: 'Requests roots from the inspecting client.',
    callback: (args, extra) async {
      final response = extra.inputResponses?['roots'];
      if (response != null) {
        return CallToolResult.fromStructuredContent(response.toJson());
      }
      return InputRequiredResult(
        inputRequests: <String, InputRequest>{
          'roots': InputRequest.listRoots(),
        },
      );
    },
  );

  server.registerStatelessTool(
    'sample_text',
    description: 'Requests sampling from the inspecting client.',
    callback: (args, extra) async {
      final response = extra.inputResponses?['sample'];
      if (response != null) {
        return CallToolResult.fromStructuredContent(response.toJson());
      }
      return InputRequiredResult(
        inputRequests: <String, InputRequest>{
          'sample': InputRequest.createMessage(
            const CreateMessageRequest(
              messages: <SamplingMessage>[
                SamplingMessage(
                  role: SamplingMessageRole.user,
                  content: SamplingTextContent(text: 'Say hello.'),
                ),
              ],
              maxTokens: 8,
            ),
          ),
        },
      );
    },
  );

  server.registerResource(
    'status',
    _resourceUri,
    (
      description: 'Fixture status.',
      mimeType: 'text/plain',
    ),
    (uri, extra) async => ReadResourceResult(
      contents: <ResourceContents>[
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: 'ready',
        ),
      ],
    ),
  );

  server.server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
    Method.subscriptionsListen,
    (request, extra) async {
      final acknowledged = request.listenParams.notifications.acknowledgedBy(
        server.server.getCapabilities(),
      );
      await extra.sendSubscriptionAcknowledged(acknowledged);
      await extra.sendSubscriptionNotification(
        JsonRpcResourceUpdatedNotification(
          updatedParams: const ResourceUpdatedNotification(uri: _resourceUri),
        ),
      );
      return const EmptyResult();
    },
    (id, params, meta) => JsonRpcSubscriptionsListenRequest(
      id: id,
      listenParams: SubscriptionsListenRequest.fromJson(params!),
      meta: meta,
    ),
  );

  await server.connect(StdioServerTransport());
}
