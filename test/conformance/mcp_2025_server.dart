import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
const _wavSilence =
    'UklGRiQAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQAAAAA=';

/// Dedicated HTTP server fixture for the stable MCP 2025-11-25 conformance
/// suite.
///
/// The conformance package calls hard-coded diagnostic tools, prompts, and
/// resources. Keep those names isolated here so the cross-SDK interop fixture
/// remains representative of a normal application server.
Future<void> main(List<String> args) async {
  var host = 'localhost';
  var port = 0;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--host':
        if (i + 1 < args.length) {
          host = args[++i];
        }
      case '--port':
        if (i + 1 < args.length) {
          final parsed = int.tryParse(args[++i]);
          if (parsed != null) {
            port = parsed;
          }
        }
      case '--help':
        _printUsage();
        return;
    }
  }

  final server = StreamableMcpServer(
    serverFactory: (_) => _createConformanceServer(),
    host: host,
    port: port,
    eventStore: InMemoryEventStore(),
  );

  await server.start();
  stdout.writeln(
    'MCP 2025 conformance server listening on '
    'http://$host:${server.boundPort}${server.path}',
  );

  await Future.any([
    ProcessSignal.sigint.watch().first,
    ProcessSignal.sigterm.watch().first,
  ]);
  await server.stop();
}

McpServer _createConformanceServer() {
  final server = McpServer(
    const Implementation(
      name: 'dart-2025-conformance-server',
      version: '1.0.0',
    ),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        logging: {},
        resources: ServerCapabilitiesResources(
          subscribe: true,
          listChanged: true,
        ),
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        tools: ServerCapabilitiesTools(listChanged: true),
        completions: ServerCapabilitiesCompletions(),
      ),
    ),
  );

  registerStableConformanceFeatures(server);

  return server;
}

/// Registers the stable conformance package's diagnostic tools, resources, and
/// prompts on [server].
///
/// The 2026 fixture reuses these registrations because the alpha conformance
/// package tags several stable scenarios for `2026-07-28`. Resource
/// subscription handlers remain 2025-only unless [includeResourceSubscriptions]
/// is enabled.
void registerStableConformanceFeatures(
  McpServer server, {
  bool includeResourceSubscriptions = true,
}) {
  _registerTools(server);
  _registerResources(server);
  _registerPrompts(server);
  if (includeResourceSubscriptions) {
    _registerResourceSubscriptions(server);
  }
}

void _registerTools(McpServer server) {
  server.registerTool(
    'test_reconnection',
    description: 'Closes and resumes the SSE response during execution',
    callback: (args, extra) async {
      final closeSSEStream = extra.closeSSEStream;
      if (closeSSEStream == null) {
        throw StateError('Resumable SSE stream control is unavailable');
      }

      closeSSEStream();
      return _textResult('Reconnection test completed successfully');
    },
  );

  server.registerTool(
    'test_simple_text',
    description: 'Returns a simple text content block',
    callback: (args, extra) async => _textResult(
      'This is a simple text response for testing.',
    ),
  );

  server.registerTool(
    'test_image_content',
    description: 'Returns image content',
    callback: (args, extra) async => const CallToolResult(
      content: [ImageContent(data: _png1x1, mimeType: 'image/png')],
    ),
  );

  server.registerTool(
    'test_audio_content',
    description: 'Returns audio content',
    callback: (args, extra) async => const CallToolResult(
      content: [AudioContent(data: _wavSilence, mimeType: 'audio/wav')],
    ),
  );

  server.registerTool(
    'test_embedded_resource',
    description: 'Returns an embedded resource content block',
    callback: (args, extra) async => const CallToolResult(
      content: [
        EmbeddedResource(
          resource: TextResourceContents(
            uri: 'test://embedded-resource',
            mimeType: 'text/plain',
            text: 'This is an embedded resource content.',
          ),
        ),
      ],
    ),
  );

  server.registerTool(
    'test_multiple_content_types',
    description: 'Returns text, image, and embedded resource content',
    callback: (args, extra) async => CallToolResult(
      content: [
        const TextContent(text: 'Multiple content types test:'),
        const ImageContent(data: _png1x1, mimeType: 'image/png'),
        EmbeddedResource(
          resource: TextResourceContents(
            uri: 'test://mixed-content-resource',
            mimeType: 'application/json',
            text: jsonEncode({'test': 'data', 'value': 123}),
          ),
        ),
      ],
    ),
  );

  server.registerTool(
    'test_tool_with_logging',
    description: 'Sends log messages during tool execution',
    callback: (args, extra) async {
      await _sendLog(server, extra, 'Tool execution started');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _sendLog(server, extra, 'Tool processing data');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _sendLog(server, extra, 'Tool execution completed');
      return _textResult('Tool execution completed');
    },
  );

  server.registerTool(
    'test_error_handling',
    description: 'Returns a tool error result',
    callback: (args, extra) async => const CallToolResult(
      isError: true,
      content: [
        TextContent(
          text: 'This tool intentionally returns an error for testing',
        ),
      ],
    ),
  );

  server.registerTool(
    'test_tool_with_progress',
    description: 'Sends progress notifications during tool execution',
    callback: (args, extra) async {
      for (final progress in const [0.0, 50.0, 100.0]) {
        await extra.sendProgress(progress, total: 100.0);
        if (progress != 100) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      return _textResult('Progress completed');
    },
  );

  server.registerTool(
    'test_sampling',
    description: 'Requests sampling from the client',
    inputSchema: JsonSchema.object(
      properties: {
        'prompt': JsonSchema.string(description: 'Prompt to send to the LLM'),
      },
      required: ['prompt'],
    ),
    callback: (args, extra) async {
      final prompt = args['prompt'] as String? ?? 'Test prompt for sampling';
      final result = await server.server.createMessage(
        CreateMessageRequest(
          messages: [
            SamplingMessage(
              role: SamplingMessageRole.user,
              content: SamplingTextContent(text: prompt),
            ),
          ],
          maxTokens: 100,
        ),
      );
      final text = result.contentBlocks
          .whereType<SamplingTextContent>()
          .map((content) => content.text)
          .join('\n');
      return _textResult('LLM response: ${text.isEmpty ? result.model : text}');
    },
  );

  server.registerTool(
    'test_elicitation',
    description: 'Requests structured input from the client',
    inputSchema: JsonSchema.object(
      properties: {
        'message':
            JsonSchema.string(description: 'Message to show to the user'),
      },
      required: ['message'],
    ),
    callback: (args, extra) async {
      final message =
          args['message'] as String? ?? 'Please provide your information';
      final result = await server.server.elicitInput(
        ElicitRequest.form(
          message: message,
          requestedSchema: JsonSchema.fromJson({
            'type': 'object',
            'properties': {
              'username': {
                'type': 'string',
                'description': "User's response",
              },
              'email': {
                'type': 'string',
                'description': "User's email address",
              },
            },
            'required': ['username', 'email'],
          }),
        ),
      );
      return _textResult('User response: ${jsonEncode(result.toJson())}');
    },
  );

  server.registerTool(
    'json_schema_2020_12_tool',
    description: 'Tool with JSON Schema 2020-12 features',
    inputSchema: JsonObject.fromJson(_jsonSchema2020_12),
    callback: (args, extra) async => _textResult('schema-ok'),
  );

  server.registerTool(
    'test_elicitation_sep1034_defaults',
    description: 'Requests elicitation with primitive default values',
    callback: (args, extra) async {
      final result = await server.server.elicitInput(
        ElicitRequest.form(
          message: 'Please confirm default values',
          requestedSchema: JsonSchema.fromJson(_elicitationDefaultsSchema),
        ),
      );
      return _textResult(
        'Elicitation completed: ${jsonEncode(result.toJson())}',
      );
    },
  );

  server.registerTool(
    'test_elicitation_sep1330_enums',
    description: 'Requests elicitation with enum schemas',
    callback: (args, extra) async {
      final result = await server.server.elicitInput(
        ElicitRequest.form(
          message: 'Please choose enum values',
          requestedSchema: JsonSchema.fromJson(_elicitationEnumSchema),
        ),
      );
      return _textResult(
        'Elicitation completed: ${jsonEncode(result.toJson())}',
      );
    },
  );
}

void _registerResources(McpServer server) {
  server.registerResource(
    'Static Text',
    'test://static-text',
    (description: 'Static text resource', mimeType: 'text/plain'),
    (uri, extra) async => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: 'This is a static text resource for conformance testing.',
        ),
      ],
    ),
  );

  server.registerResource(
    'Static Binary',
    'test://static-binary',
    (description: 'Static binary resource', mimeType: 'image/png'),
    (uri, extra) async => ReadResourceResult(
      contents: [
        BlobResourceContents(
          uri: uri.toString(),
          mimeType: 'image/png',
          blob: _png1x1,
        ),
      ],
    ),
  );

  server.registerResource(
    'Watched Resource',
    'test://watched-resource',
    (description: 'Subscribable resource', mimeType: 'text/plain'),
    (uri, extra) async => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: 'Watched resource content',
        ),
      ],
    ),
  );

  server.registerResourceTemplate(
    'Template Data',
    ResourceTemplateRegistration(
      'test://template/{id}/data',
      listCallback: null,
    ),
    (description: 'Template resource', mimeType: 'application/json'),
    (uri, variables, extra) async {
      final id = variables['id'] ?? '';
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'application/json',
            text: jsonEncode({
              'id': id,
              'templateTest': true,
              'data': 'Data for ID: $id',
            }),
          ),
        ],
      );
    },
  );
}

void _registerPrompts(McpServer server) {
  server.registerPrompt(
    'test_simple_prompt',
    description: 'Simple conformance prompt',
    callback: (args, extra) async => const GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'This is a simple prompt for testing.'),
        ),
      ],
    ),
  );

  server.registerPrompt(
    'test_prompt_with_arguments',
    description: 'Conformance prompt with arguments',
    argsSchema: {
      'arg1': const PromptArgumentDefinition(
        description: 'First test argument',
        required: true,
        completable: CompletableField(
          def: CompletableDef(
            complete: _completeTestArg,
          ),
        ),
      ),
      'arg2': const PromptArgumentDefinition(
        description: 'Second test argument',
        required: true,
      ),
    },
    callback: (args, extra) async {
      final arg1 = args?['arg1'] ?? '';
      final arg2 = args?['arg2'] ?? '';
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: "Prompt with arguments: arg1='$arg1', arg2='$arg2'",
            ),
          ),
        ],
      );
    },
  );

  server.registerPrompt(
    'test_prompt_with_embedded_resource',
    description: 'Conformance prompt with embedded resource',
    argsSchema: {
      'resourceUri': const PromptArgumentDefinition(
        description: 'URI of the resource to embed',
        required: true,
      ),
    },
    callback: (args, extra) async {
      final resourceUri = args?['resourceUri'] ?? 'test://example-resource';
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: EmbeddedResource(
              resource: TextResourceContents(
                uri: resourceUri,
                mimeType: 'text/plain',
                text: 'Embedded resource content for testing.',
              ),
            ),
          ),
          const PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: 'Please process the embedded resource above.',
            ),
          ),
        ],
      );
    },
  );

  server.registerPrompt(
    'test_prompt_with_image',
    description: 'Conformance prompt with image content',
    callback: (args, extra) async => const GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: ImageContent(data: _png1x1, mimeType: 'image/png'),
        ),
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Please analyze the image above.'),
        ),
      ],
    ),
  );
}

void _registerResourceSubscriptions(McpServer server) {
  final subscribedUris = <String>{};

  server.server.setRequestHandler<JsonRpcSubscribeRequest>(
    Method.resourcesSubscribe,
    (request, extra) async {
      subscribedUris.add(request.subParams.uri);
      return const EmptyResult();
    },
    (id, params, meta) => JsonRpcSubscribeRequest.fromJson({
      'jsonrpc': jsonRpcVersion,
      'id': id,
      'method': Method.resourcesSubscribe,
      'params': params,
      if (meta != null) '_meta': meta,
    }),
  );

  server.server.setRequestHandler<JsonRpcUnsubscribeRequest>(
    Method.resourcesUnsubscribe,
    (request, extra) async {
      subscribedUris.remove(request.unsubParams.uri);
      return const EmptyResult();
    },
    (id, params, meta) => JsonRpcUnsubscribeRequest.fromJson({
      'jsonrpc': jsonRpcVersion,
      'id': id,
      'method': Method.resourcesUnsubscribe,
      'params': params,
      if (meta != null) '_meta': meta,
    }),
  );
}

Future<void> _sendLog(
  McpServer server,
  RequestHandlerExtra extra,
  String message,
) {
  return server.sendLoggingMessage(
    LoggingMessageNotification(
      level: LoggingLevel.info,
      logger: 'conformance',
      data: message,
    ),
    sessionId: extra.sessionId,
    requestMeta: extra.meta,
  );
}

List<String> _completeTestArg(String value) {
  return ['testValue1', 'testOption']
      .where((candidate) => candidate.startsWith(value))
      .toList();
}

CallToolResult _textResult(String text) {
  return CallToolResult(content: [TextContent(text: text)]);
}

const _jsonSchema2020_12 = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  r'$defs': {
    'address': {
      r'$anchor': 'addressDef',
      'type': 'object',
      'properties': {
        'street': {'type': 'string'},
        'city': {'type': 'string'},
      },
    },
  },
  'properties': {
    'name': {'type': 'string'},
    'address': {r'$ref': '#/\$defs/address'},
    'contactMethod': {
      'type': 'string',
      'enum': ['phone', 'email'],
    },
    'phone': {'type': 'string'},
    'email': {'type': 'string'},
  },
  'allOf': [
    {
      'anyOf': [
        {
          'required': ['phone'],
        },
        {
          'required': ['email'],
        },
      ],
    },
  ],
  'if': {
    'properties': {
      'contactMethod': {'const': 'phone'},
    },
    'required': ['contactMethod'],
  },
  'then': {
    'required': ['phone'],
  },
  'else': {
    'required': ['email'],
  },
  'additionalProperties': false,
};

const _elicitationDefaultsSchema = {
  'type': 'object',
  'properties': {
    'name': {
      'type': 'string',
      'default': 'John Doe',
    },
    'age': {
      'type': 'integer',
      'default': 30,
    },
    'score': {
      'type': 'number',
      'default': 95.5,
    },
    'status': {
      'type': 'string',
      'enum': ['active', 'inactive', 'pending'],
      'default': 'active',
    },
    'verified': {
      'type': 'boolean',
      'default': true,
    },
  },
  'required': ['name', 'age', 'score', 'status', 'verified'],
};

const _elicitationEnumSchema = {
  'type': 'object',
  'properties': {
    'untitledSingle': {
      'type': 'string',
      'enum': ['option1', 'option2', 'option3'],
    },
    'titledSingle': {
      'type': 'string',
      'oneOf': [
        {'const': 'value1', 'title': 'First Option'},
        {'const': 'value2', 'title': 'Second Option'},
      ],
    },
    'legacyEnum': {
      'type': 'string',
      'enum': ['opt1', 'opt2', 'opt3'],
      'enumNames': ['Option One', 'Option Two', 'Option Three'],
    },
    'untitledMulti': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': ['option1', 'option2', 'option3'],
      },
    },
    'titledMulti': {
      'type': 'array',
      'items': {
        'anyOf': [
          {'const': 'value1', 'title': 'First Choice'},
          {'const': 'value2', 'title': 'Second Choice'},
        ],
      },
    },
  },
  'required': [
    'untitledSingle',
    'titledSingle',
    'legacyEnum',
    'untitledMulti',
    'titledMulti',
  ],
};

void _printUsage() {
  stdout.writeln('''
Usage: dart run test/conformance/mcp_2025_server.dart [options]

Options:
  --host <host>   Host to bind, default: localhost.
  --port <port>   Port to bind, default: 0.
  --help          Show this help.
''');
}
