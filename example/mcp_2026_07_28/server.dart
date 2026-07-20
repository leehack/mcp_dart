import 'package:mcp_dart/mcp_dart.dart';

const _statusResourceUri = 'mcp://greeting/status';

/// Parses the elicitation response associated with the greeting input request.
ElicitResult parseGreetingProfileResponse(InputResponse response) {
  try {
    return ElicitResult.fromJson(response.toJson());
  } on FormatException {
    throw McpError(
      ErrorCode.invalidParams.value,
      'The profile response must be an elicitation result.',
    );
  } on ArgumentError {
    throw McpError(
      ErrorCode.invalidParams.value,
      'The profile response must be an elicitation result.',
    );
  } on TypeError {
    throw McpError(
      ErrorCode.invalidParams.value,
      'The profile response must be an elicitation result.',
    );
  }
}

/// Strict MCP 2026-07-28 server example.
///
/// The paired client starts this server over stdio and demonstrates stateless
/// discovery, `subscriptions/listen`, multi-round-trip `input_required`, and a
/// non-object structured tool result.
Future<void> main() async {
  late final McpServer server;
  var greetingStatus = 'waiting for a profile';
  server = McpServer(
    const Implementation(name: 'mcp-2026-example-server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.require2026,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        resources: ServerCapabilitiesResources(subscribe: true),
      ),
    ),
  );

  server.registerResource(
    'greeting-status',
    _statusResourceUri,
    (mimeType: 'text/plain', description: 'Current greeting workflow status'),
    (uri, extra) async => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: greetingStatus,
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

      greetingStatus = 'ready for a greeting';
      await extra.sendSubscriptionNotification(
        JsonRpcResourceUpdatedNotification(
          updatedParams:
              const ResourceUpdatedNotification(uri: _statusResourceUri),
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

  server.registerStatelessTool(
    'personalized_greeting',
    description: 'Collect a name, then return a personalized greeting.',
    inputSchema: JsonSchema.object(properties: {}),
    outputJsonSchema: JsonSchema.string(),
    callback: (args, extra) async {
      final profileResponse = extra.inputResponses?['profile'];
      if (profileResponse == null) {
        return InputRequiredResult(
          requestState: 'greeting-v1',
          inputRequests: {
            'profile': InputRequest.elicit(
              ElicitRequest.form(
                message: 'What name should the greeting use?',
                requestedSchema: JsonSchema.object(
                  properties: {
                    'name': JsonSchema.string(minLength: 1),
                  },
                  required: ['name'],
                ),
              ),
            ),
          },
        );
      }

      if (extra.requestState != 'greeting-v1') {
        throw McpError(
          ErrorCode.invalidParams.value,
          'Unexpected request state.',
        );
      }

      final elicitation = parseGreetingProfileResponse(profileResponse);
      if (elicitation.declined) {
        return CallToolResult.fromStructuredString('Greeting declined.');
      }
      if (elicitation.cancelled) {
        return CallToolResult.fromStructuredString('Greeting cancelled.');
      }

      final name = elicitation.content?['name'];
      if (name is! String || name.isEmpty) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'The profile response must contain a name.',
        );
      }

      return CallToolResult.fromStructuredString('Hello, $name!');
    },
  );

  await server.connect(StdioServerTransport());
}
