import 'dart:async';

import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

class MockTransport extends Transport {
  final List<JsonRpcMessage> sent = [];

  @override
  String? get sessionId => null;

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sent.add(message);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> start() async {
    // Implemented start method
    // No-op for mock transport
  }

  void emitMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

void main() {
  group('Server Validation', () {
    late Server server;
    late MockTransport transport;

    setUp(() {
      server = Server(
        const Implementation(name: 'test', version: '1.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      transport = MockTransport();
      server.connect(transport);
    });

    test('createMessage validates tool use/result pairing', () async {
      // Need to simulate initialization to set client capabilities
      final initReq = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: '2024-11-05',
          capabilities: ClientCapabilities(
            sampling: ClientCapabilitiesSampling(tools: true), // Corrected
            elicitation: ClientElicitation.all(), // Corrected
          ),
          clientInfo: Implementation(name: 'client', version: '1.0'),
        ),
      );

      transport.emitMessage(initReq);
      await Future.delayed(Duration.zero);

      transport.emitMessage(const JsonRpcInitializedNotification());
      await Future.delayed(Duration.zero);

      // Case 1: Valid pairing (validation passes, request sent, awaits response)
      final validParams = const CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.user, // Corrected
            content: SamplingTextContent(text: 'call tool'), // Corrected
          ),
          SamplingMessage(
            role: SamplingMessageRole.assistant, // Corrected
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ), // Corrected
          ),
          SamplingMessage(
            role: SamplingMessageRole.user, // Corrected
            content: SamplingToolResultContent(
              toolUseId: 'call1',
              content: [TextContent(text: 'tool result')],
            ),
          ),
        ],
        maxTokens: 100,
        tools: [],
      );

      final validFuture = server.createMessage(validParams);
      await Future.delayed(Duration.zero);

      // Check if request was sent
      expect(
        transport.sent.any(
          (m) => m is JsonRpcRequest && m.method == 'sampling/createMessage',
        ),
        isTrue,
      );

      // Emit response to complete the future
      final req = transport.sent.last as JsonRpcRequest;
      transport.emitMessage(
        JsonRpcResponse(
          id: req.id,
          result: const CreateMessageResult(
            model: 'test-model', // Required parameter
            role: SamplingMessageRole.assistant, // Corrected
            content: SamplingTextContent(text: 'done'), // Corrected
          ).toJson(),
        ),
      );

      await expectLater(validFuture, completes);

      // Case 2: Invalid pairing - mismatch ID
      final invalidParams = const CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.assistant, // Corrected
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ), // Corrected
          ),
          SamplingMessage(
            role: SamplingMessageRole.user, // Corrected
            content: SamplingToolResultContent(
              toolUseId: 'call2',
              content: [TextContent(text: 'tool result')],
            ), // Corrected
          ),
        ],
        maxTokens: 100,
        tools: [],
      );

      expect(
        () => server.createMessage(invalidParams),
        throwsA(isA<McpError>()),
      );
    });

    test('createMessage validates every sampling tool turn and role', () {
      final invalidHistories = <String, List<SamplingMessage>>{
        'unresolved earlier tool use': const [
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ),
          ),
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'skipped the tool result'),
          ),
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingTextContent(text: 'continued anyway'),
          ),
        ],
        'tool use on a user message': const [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ),
          ),
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingToolResultContent(
              toolUseId: 'call1',
              content: [TextContent(text: 'result')],
            ),
          ),
        ],
        'tool result on an assistant message': const [
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ),
          ),
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingToolResultContent(
              toolUseId: 'call1',
              content: [TextContent(text: 'result')],
            ),
          ),
        ],
        'unresolved final tool use': const [
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ),
          ),
        ],
        'mixed tool result content in earlier history': const [
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingToolUseContent(
              id: 'call1',
              name: 'tool1',
              input: {},
            ),
          ),
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: [
              SamplingToolResultContent(
                toolUseId: 'call1',
                content: [TextContent(text: 'result')],
              ),
              SamplingTextContent(text: 'mixed content'),
            ],
          ),
          SamplingMessage(
            role: SamplingMessageRole.assistant,
            content: SamplingTextContent(text: 'later message'),
          ),
        ],
      };

      for (final MapEntry(:key, :value) in invalidHistories.entries) {
        expect(
          () => server.createMessage(
            CreateMessageRequestParams(
              messages: value,
              maxTokens: 100,
            ),
          ),
          throwsA(
            isA<McpError>().having(
              (error) => error.code,
              'code',
              ErrorCode.invalidParams.value,
            ),
          ),
          reason: key,
        );
      }
    });

    test('elicitInput validates schema', () async {
      // Initialize
      final initReq = JsonRpcInitializeRequest(
        id: 1,
        initParams: const InitializeRequestParams(
          protocolVersion: '2024-11-05',
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(), // Corrected
          ),
          clientInfo: Implementation(name: 'client', version: '1.0'),
        ),
      );
      transport.emitMessage(initReq);
      await Future.delayed(Duration.zero);
      transport.emitMessage(const JsonRpcInitializedNotification());
      await Future.delayed(Duration.zero);

      final schema = JsonSchema.object(
        properties: {
          'foo': JsonSchema.string(),
        },
        required: ['foo'],
      );

      final params = ElicitRequestParams.form(
        message: 'test',
        requestedSchema: schema,
      );

      // Case 1: Invalid response
      final future = server.elicitInput(params);

      await Future.delayed(Duration.zero);
      expect(
        transport.sent.any(
          (m) => m is JsonRpcRequest && m.method == 'elicitation/create',
        ),
        isTrue,
      );
      final elicitMsg = transport.sent.last as JsonRpcRequest;

      transport.emitMessage(
        JsonRpcResponse(
          id: elicitMsg.id,
          result: const ElicitResult(
            action: 'accept',
            content: {'bar': 'baz'}, // Missing 'foo'
          ).toJson(),
        ),
      );

      await expectLater(future, throwsA(isA<McpError>()));

      // Case 2: Valid response
      final future2 = server.elicitInput(params);
      await Future.delayed(Duration.zero);
      final elicitMsg2 = transport.sent.last as JsonRpcRequest;

      transport.emitMessage(
        JsonRpcResponse(
          id: elicitMsg2.id,
          result: const ElicitResult(
            action: 'accept',
            content: {'foo': 'bar'},
          ).toJson(),
        ),
      );

      await expectLater(future2, completes);
    });
  });
}
