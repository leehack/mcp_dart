import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:mcp_dart_cli/src/utils/inspect_handlers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('InspectHandlers', () {
    test('silent mode records notifications without logging', () async {
      final logger = MockLogger();
      final handlers = InspectHandlers(logger, silent: true);
      final client = McpClient(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const McpClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(),
            sampling: ClientCapabilitiesSampling(),
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );
      var toolsChanged = 0;
      handlers.onToolsListChanged = () => toolsChanged++;
      handlers.registerHandlers(client);

      await client.fallbackNotificationHandler!(
        const JsonRpcNotification(
          method: 'notifications/message',
          params: <String, dynamic>{
            'level': 'info',
            'logger': 'fixture',
            'data': 'hello',
          },
        ),
      );
      await client.fallbackNotificationHandler!(
        const JsonRpcNotification(
          method: 'notifications/progress',
          params: <String, dynamic>{
            'progressToken': 'probe',
            'progress': 10,
            'total': 20,
          },
        ),
      );
      await client.fallbackNotificationHandler!(
        const JsonRpcNotification(
          method: 'notifications/progress',
          params: <String, dynamic>{
            'progressToken': 'probe',
            'progress': 5,
            'total': 20,
          },
        ),
      );
      await client.fallbackNotificationHandler!(
        const JsonRpcNotification(
          method: 'notifications/tools/list_changed',
        ),
      );
      await client.fallbackNotificationHandler!(
        const JsonRpcNotification(method: 'notifications/custom'),
      );

      final samplingResult = await client.onSamplingRequest!(
        const CreateMessageRequest(
          messages: <SamplingMessage>[
            SamplingMessage(
              role: SamplingMessageRole.user,
              content: SamplingTextContent(text: 'hello'),
            ),
          ],
          systemPrompt: 'system',
          maxTokens: 1,
        ),
      );
      final elicitationResult = await client.onElicitRequest!(
        ElicitRequest.form(
          message: 'Name?',
          requestedSchema: JsonSchema.object(
            properties: <String, JsonSchema>{
              'name': JsonSchema.string(),
            },
          ),
        ),
      );

      expect(toolsChanged, equals(1));
      expect(handlers.notifications, hasLength(5));
      expect(
        handlers.progressIssues.single,
        containsPair('issue', 'progress decreased for token'),
      );
      expect(samplingResult.model, equals('mcp-dart-cli-placeholder'));
      expect(elicitationResult.declined, isTrue);
      verifyNever(() => logger.detail(any()));
      verifyNever(() => logger.info(any()));
      verifyNever(() => logger.warn(any()));
      verifyNever(() => logger.err(any()));
    });

    test('returns a configured elicitation response', () async {
      final logger = MockLogger();
      final handlers = InspectHandlers(
        logger,
        silent: true,
        elicitationResponse: const ElicitResult(
          action: 'accept',
          content: <String, dynamic>{'name': 'Ada'},
        ),
        handleRoots: true,
      );
      final client = McpClient(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const McpClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(),
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );
      handlers.registerHandlers(client);

      final result = await client.onElicitRequest!(
        ElicitRequest.form(
          message: 'Name?',
          requestedSchema: JsonSchema.object(
            properties: <String, JsonSchema>{
              'name': JsonSchema.string(),
            },
            required: <String>['name'],
          ),
        ),
      );

      expect(result.accepted, isTrue);
      expect(result.content, containsPair('name', 'Ada'));
    });
  });
}
