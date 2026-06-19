import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import '../interop/test_dart_server.dart' as interop;
import 'mcp_2025_server.dart' as stable_conformance;

int _streamCancellationCount = 0;

/// Dedicated HTTP server fixture for the MCP 2026 RC conformance package.
///
/// This deliberately starts from the existing cross-SDK interop server and
/// uses the default Streamable HTTP SSE response mode so request-scoped
/// progress notifications remain observable. Conformance-specific diagnostic
/// tools can be added here without changing the stable interop fixture.
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
    enableJsonResponse: false,
  );

  await server.start();
  stdout.writeln(
    'MCP 2026 RC conformance server listening on '
    'http://$host:${server.boundPort}${server.path}',
  );

  await Future.any([
    ProcessSignal.sigint.watch().first,
    ProcessSignal.sigterm.watch().first,
  ]);
  await server.stop();
}

McpServer _createConformanceServer() {
  final server = interop.createServer(
    options: const McpServerOptions(
      protocol: McpProtocol.preview2026,
    ),
  );

  stable_conformance.registerStableConformanceFeatures(
    server,
    includeResourceSubscriptions: false,
  );
  server.server.registerCapabilities(
    const ServerCapabilities(
      tools: ServerCapabilitiesTools(listChanged: true),
    ),
  );

  server.registerTool(
    'a_header_probe',
    description: 'No-op tool for HTTP header conformance checks',
    callback: (args, extra) async => const CallToolResult(content: []),
  );

  server.registerTool(
    'test_custom_headers_valid',
    description: 'Exercises valid 2026 x-mcp-header parameter mirroring',
    inputSchema: JsonSchema.object(
      properties: {
        'region': JsonSchema.string(mcpHeader: 'Region'),
        'count': JsonSchema.integer(mcpHeader: 'Count'),
        'dryRun': JsonSchema.boolean(mcpHeader: 'Dry-Run'),
        'auth': JsonSchema.object(
          properties: {
            'tenant': JsonSchema.string(mcpHeader: 'Tenant'),
          },
          required: ['tenant'],
        ),
      },
      required: ['region', 'count', 'dryRun', 'auth'],
    ),
    callback: (args, extra) async {
      return const CallToolResult(
        content: [TextContent(text: 'custom-header-ok')],
      );
    },
  );

  _registerStreamDiagnostics(server);
  _registerInputRequiredDiagnostics(server);

  return server;
}

void _registerStreamDiagnostics(McpServer server) {
  server.registerTool(
    'test_stream_cancellation',
    description: 'Keeps an SSE response open until the HTTP client aborts it',
    callback: (args, extra) async {
      final observed = Completer<void>();
      final abortSub = extra.signal.onAbort.listen((_) {
        _streamCancellationCount++;
        if (!observed.isCompleted) {
          observed.complete();
        }
      });

      try {
        await extra.sendProgress(
          1,
          total: 1,
          message: 'cancellation probe started',
        );
        await observed.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            if (!observed.isCompleted) {
              observed.complete();
            }
          },
        );
      } finally {
        await abortSub.cancel();
      }

      return _textResult(
        extra.signal.aborted ? 'cancelled' : 'not-cancelled',
      );
    },
  );

  server.registerTool(
    'test_stream_cancellation_status',
    description: 'Reports observed HTTP stream cancellation count',
    callback: (args, extra) async {
      return _textResult(_streamCancellationCount.toString());
    },
  );

  server.server.setRequestHandler<JsonRpcSubscriptionsListenRequest>(
    Method.subscriptionsListen,
    (request, extra) async {
      final acknowledged = request.listenParams.notifications.acknowledgedBy(
        server.server.getCapabilities(),
      );
      await extra.sendSubscriptionAcknowledged(acknowledged);
      await extra.sendSubscriptionNotification(
        const JsonRpcToolListChangedNotification(),
      );
      return const EmptyResult();
    },
    (id, params, meta) => JsonRpcSubscriptionsListenRequest(
      id: id,
      listenParams: SubscriptionsListenRequest.fromJson(params!),
      meta: meta,
    ),
  );
}

void _registerInputRequiredDiagnostics(McpServer server) {
  server.registerTool(
    'test_input_required_result_elicitation',
    description: 'Exercises an elicitation InputRequiredResult retry flow',
    callback: (args, extra) async {
      final content = _acceptedContent(extra.inputResponses, 'user_name');
      final name = content?['name'];
      if (name is String) {
        return _textResult('Hello, $name!');
      }

      return InputRequiredResult(
        inputRequests: {
          'user_name': _elicitationInput(
            message: 'What is your name?',
            properties: {'name': JsonSchema.string()},
            required: ['name'],
          ),
        },
      );
    },
  );

  server.registerTool(
    'test_input_required_result_sampling',
    description: 'Exercises a sampling InputRequiredResult retry flow',
    callback: (args, extra) async {
      final answer = _samplingText(extra.inputResponses, 'capital_question');
      if (answer != null) {
        return _textResult(answer);
      }

      return InputRequiredResult(
        inputRequests: {
          'capital_question': _samplingInput(
            'What is the capital of France?',
            maxTokens: 100,
          ),
        },
      );
    },
  );

  server.registerTool(
    'test_input_required_result_list_roots',
    description: 'Exercises a roots/list InputRequiredResult retry flow',
    callback: (args, extra) async {
      final roots = _roots(extra.inputResponses, 'client_roots');
      if (roots != null) {
        return _textResult('Received ${roots.length} roots.');
      }

      return InputRequiredResult(
        inputRequests: {
          'client_roots': InputRequest.listRoots(params: const {}),
        },
      );
    },
  );

  server.registerTool(
    'test_input_required_result_request_state',
    description: 'Exercises requestState echo validation',
    callback: (args, extra) async {
      const state = 'request-state-v1';
      final content = _acceptedContent(extra.inputResponses, 'confirm');
      if (content != null) {
        _requireRequestState(extra.requestState, state);
        return _textResult('state-ok');
      }

      return InputRequiredResult(
        requestState: state,
        inputRequests: {
          'confirm': _elicitationInput(
            message: 'Please confirm',
            properties: {'ok': JsonSchema.boolean()},
            required: ['ok'],
          ),
        },
      );
    },
  );

  server.registerTool(
    'test_input_required_result_multiple_inputs',
    description: 'Exercises multiple simultaneous InputRequiredResult requests',
    callback: (args, extra) async {
      const state = 'multiple-inputs-v1';
      final responses = extra.inputResponses;
      final user = _acceptedContent(responses, 'user_name');
      final greeting = _samplingText(responses, 'greeting');
      final roots = _roots(responses, 'client_roots');
      if (user != null && greeting != null && roots != null) {
        _requireRequestState(extra.requestState, state);
        return _textResult(
          'Hello ${user['name'] ?? 'there'}: $greeting (${roots.length} roots)',
        );
      }

      return InputRequiredResult(
        requestState: state,
        inputRequests: {
          'user_name': _elicitationInput(
            message: 'What is your name?',
            properties: {'name': JsonSchema.string()},
            required: ['name'],
          ),
          'greeting': _samplingInput('Generate a greeting', maxTokens: 50),
          'client_roots': InputRequest.listRoots(params: const {}),
        },
      );
    },
  );

  server.registerTool(
    'test_input_required_result_multi_round',
    description: 'Exercises a multi-round InputRequiredResult flow',
    callback: (args, extra) async {
      switch (extra.requestState) {
        case null:
          return InputRequiredResult(
            requestState: 'multi-round-1',
            inputRequests: {
              'step1': _elicitationInput(
                message: 'Step 1: What is your name?',
                properties: {'name': JsonSchema.string()},
                required: ['name'],
              ),
            },
          );
        case 'multi-round-1':
          if (_acceptedContent(extra.inputResponses, 'step1') == null) {
            return InputRequiredResult(
              requestState: 'multi-round-1',
              inputRequests: {
                'step1': _elicitationInput(
                  message: 'Step 1: What is your name?',
                  properties: {'name': JsonSchema.string()},
                  required: ['name'],
                ),
              },
            );
          }
          return InputRequiredResult(
            requestState: 'multi-round-2',
            inputRequests: {
              'step2': _elicitationInput(
                message: 'Step 2: What is your favorite color?',
                properties: {'color': JsonSchema.string()},
                required: ['color'],
              ),
            },
          );
        case 'multi-round-2':
          if (_acceptedContent(extra.inputResponses, 'step2') == null) {
            return InputRequiredResult(
              requestState: 'multi-round-2',
              inputRequests: {
                'step2': _elicitationInput(
                  message: 'Step 2: What is your favorite color?',
                  properties: {'color': JsonSchema.string()},
                  required: ['color'],
                ),
              },
            );
          }
          return _textResult('multi-round complete');
        default:
          throw McpError(
            ErrorCode.invalidParams.value,
            'Invalid requestState',
          );
      }
    },
  );

  server.registerTool(
    'test_input_required_result_tampered_state',
    description: 'Rejects modified requestState values',
    callback: (args, extra) async {
      const state = 'tamper-proof-state-v1';
      final content = _acceptedContent(extra.inputResponses, 'confirm');
      if (content != null) {
        _requireRequestState(extra.requestState, state);
        return _textResult('tamper state accepted');
      }

      return InputRequiredResult(
        requestState: state,
        inputRequests: {
          'confirm': _elicitationInput(
            message: 'Please confirm',
            properties: {'ok': JsonSchema.boolean()},
            required: ['ok'],
          ),
        },
      );
    },
  );

  server.registerTool(
    'test_input_required_result_capabilities',
    description: 'Only emits input requests supported by client capabilities',
    callback: (args, extra) async {
      final capabilities = extra.clientCapabilities;
      final inputRequests = <String, InputRequest>{};
      if (capabilities?.sampling != null) {
        inputRequests['sampling'] = _samplingInput(
          'Generate a capability-safe response',
          maxTokens: 50,
        );
      }
      if (capabilities?.elicitation != null) {
        inputRequests['elicitation'] = _elicitationInput(
          message: 'Provide context',
          properties: {'context': JsonSchema.string()},
          required: ['context'],
        );
      }
      if (capabilities?.roots != null) {
        inputRequests['roots'] = InputRequest.listRoots(params: const {});
      }
      if (inputRequests.isEmpty) {
        return _textResult('No declared input capabilities.');
      }

      return InputRequiredResult(inputRequests: inputRequests);
    },
  );

  server.registerPrompt(
    'test_input_required_result_prompt',
    description: 'Exercises InputRequiredResult from prompts/get',
    callback: (args, extra) async {
      final content = _acceptedContent(extra?.inputResponses, 'user_context');
      final context = content?['context'];
      if (context is String) {
        return GetPromptResult(
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(text: 'Use this context: $context'),
            ),
          ],
        );
      }

      return InputRequiredResult(
        inputRequests: {
          'user_context': _elicitationInput(
            message: 'What context should the prompt use?',
            properties: {'context': JsonSchema.string()},
            required: ['context'],
          ),
        },
      );
    },
  );
}

InputRequest _elicitationInput({
  required String message,
  required Map<String, JsonSchema> properties,
  required List<String> required,
}) {
  return InputRequest.elicit(
    ElicitRequest.form(
      message: message,
      requestedSchema: JsonSchema.object(
        properties: properties,
        required: required,
      ),
    ),
  );
}

InputRequest _samplingInput(String text, {required int maxTokens}) {
  return InputRequest.createMessage(
    CreateMessageRequest(
      messages: [
        SamplingMessage(
          role: SamplingMessageRole.user,
          content: SamplingTextContent(text: text),
        ),
      ],
      maxTokens: maxTokens,
    ),
  );
}

CallToolResult _textResult(String text) {
  return CallToolResult(content: [TextContent(text: text)]);
}

Map<String, dynamic>? _acceptedContent(
  InputResponses? responses,
  String key,
) {
  final response = responses?[key]?.toJson();
  if (response == null || response['action'] != 'accept') {
    return null;
  }
  final content = response['content'];
  if (content is! Map) {
    return null;
  }
  return content.cast<String, dynamic>();
}

String? _samplingText(InputResponses? responses, String key) {
  final response = responses?[key]?.toJson();
  final content = response?['content'];
  if (content is Map && content['type'] == 'text') {
    final text = content['text'];
    return text is String ? text : null;
  }
  return null;
}

List<dynamic>? _roots(InputResponses? responses, String key) {
  final response = responses?[key]?.toJson();
  final roots = response?['roots'];
  return roots is List ? roots : null;
}

void _requireRequestState(String? actual, String expected) {
  if (actual != expected) {
    throw McpError(
      ErrorCode.invalidParams.value,
      'Invalid requestState',
    );
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run test/conformance/mcp_2026_rc_server.dart '
    '[--host localhost] [--port 33125]',
  );
}
