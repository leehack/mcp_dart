import 'package:mcp_dart/src/types/sampling.dart';
import 'package:test/test.dart';

void main() {
  group('ModelHint', () {
    test('constructs with name', () {
      const hint = ModelHint(name: 'gpt-4');
      expect(hint.name, equals('gpt-4'));
    });

    test('toJson serializes correctly', () {
      const hint = ModelHint(name: 'claude-3');
      final json = hint.toJson();
      expect(json, equals({'name': 'claude-3'}));
    });

    test('fromJson parses correctly', () {
      final json = {'name': 'gemini-pro'};
      final hint = ModelHint.fromJson(json);
      expect(hint.name, equals('gemini-pro'));
    });
  });

  group('ModelPreferences', () {
    test('constructs with all fields', () {
      const prefs = ModelPreferences(
        hints: [ModelHint(name: 'gpt-4')],
        costPriority: 0.5,
        speedPriority: 0.3,
        intelligencePriority: 0.8,
      );
      expect(prefs.hints, hasLength(1));
      expect(prefs.costPriority, equals(0.5));
    });

    test('toJson serializes all fields', () {
      const prefs = ModelPreferences(
        hints: [ModelHint(name: 'claude')],
        costPriority: 0.2,
        speedPriority: 0.5,
        intelligencePriority: 0.9,
      );
      final json = prefs.toJson();
      expect(json['hints'], isA<List>());
      expect(json['costPriority'], equals(0.2));
      expect(json['speedPriority'], equals(0.5));
      expect(json['intelligencePriority'], equals(0.9));
    });

    test('toJson omits null fields', () {
      const prefs = ModelPreferences();
      final json = prefs.toJson();
      expect(json.containsKey('hints'), isFalse);
      expect(json.containsKey('costPriority'), isFalse);
    });

    test('fromJson parses correctly', () {
      final json = {
        'hints': [
          {'name': 'model-a'},
        ],
        'costPriority': 0.1,
        'speedPriority': 0.4,
        'intelligencePriority': 0.7,
      };
      final prefs = ModelPreferences.fromJson(json);
      expect(prefs.hints, hasLength(1));
      expect(prefs.hints![0].name, equals('model-a'));
      expect(prefs.costPriority, equals(0.1));
    });

    test('fromJson handles missing fields', () {
      final json = <String, dynamic>{};
      final prefs = ModelPreferences.fromJson(json);
      expect(prefs.hints, isNull);
      expect(prefs.costPriority, isNull);
    });
  });

  group('SamplingContent', () {
    group('SamplingTextContent', () {
      test('constructs correctly', () {
        const content = SamplingTextContent(text: 'Hello world');
        expect(content.text, equals('Hello world'));
        expect(content.type, equals('text'));
      });

      test('toJson serializes correctly', () {
        const content = SamplingTextContent(text: 'Test message');
        final json = content.toJson();
        expect(json['type'], equals('text'));
        expect(json['text'], equals('Test message'));
      });

      test('fromJson parses correctly', () {
        final json = {'type': 'text', 'text': 'Parsed text'};
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingTextContent>());
        expect((content as SamplingTextContent).text, equals('Parsed text'));
      });
    });

    group('SamplingImageContent', () {
      test('constructs correctly', () {
        const content =
            SamplingImageContent(data: 'base64data', mimeType: 'image/png');
        expect(content.data, equals('base64data'));
        expect(content.mimeType, equals('image/png'));
      });

      test('toJson serializes correctly', () {
        const content =
            SamplingImageContent(data: 'imgdata', mimeType: 'image/jpeg');
        final json = content.toJson();
        expect(json['type'], equals('image'));
        expect(json['data'], equals('imgdata'));
        expect(json['mimeType'], equals('image/jpeg'));
      });

      test('fromJson parses correctly', () {
        final json = {
          'type': 'image',
          'data': 'encoded',
          'mimeType': 'image/gif',
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingImageContent>());
        final img = content as SamplingImageContent;
        expect(img.data, equals('encoded'));
        expect(img.mimeType, equals('image/gif'));
      });
    });

    group('SamplingToolUseContent', () {
      test('constructs correctly', () {
        const content = SamplingToolUseContent(
          id: 'tool-123',
          name: 'calculator',
          input: {'x': 1, 'y': 2},
        );
        expect(content.id, equals('tool-123'));
        expect(content.name, equals('calculator'));
      });

      test('toJson serializes correctly', () {
        const content = SamplingToolUseContent(
          id: 'id1',
          name: 'search',
          input: {'query': 'test'},
        );
        final json = content.toJson();
        expect(json['type'], equals('tool_use'));
        expect(json['id'], equals('id1'));
        expect(json['name'], equals('search'));
        expect(json['input'], equals({'query': 'test'}));
      });

      test('fromJson parses correctly', () {
        final json = {
          'type': 'tool_use',
          'id': 'tu1',
          'name': 'fetch',
          'input': {'url': 'http://test.com'},
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingToolUseContent>());
        final tool = content as SamplingToolUseContent;
        expect(tool.name, equals('fetch'));
        expect(tool.id, equals('tu1'));
      });
    });

    group('SamplingToolResultContent', () {
      test('constructs correctly', () {
        const content = SamplingToolResultContent(
          toolUseId: 'result-123',
          content: {'status': 'ok'},
        );
        expect(content.toolUseId, equals('result-123'));
      });

      test('toJson serializes correctly', () {
        const content = SamplingToolResultContent(
          toolUseId: 'res1',
          content: {'value': 42},
          isError: true,
        );
        final json = content.toJson();
        expect(json['type'], equals('tool_result'));
        expect(json['toolUseId'], equals('res1'));
        expect(json['isError'], isTrue);
        expect(json['content'], equals({'value': 42}));
      });

      test('fromJson parses correctly', () {
        final json = {
          'type': 'tool_result',
          'toolUseId': 'tr1',
          'content': {'data': 'result data'},
          'isError': false,
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingToolResultContent>());
        final result = content as SamplingToolResultContent;
        expect(result.isError, isFalse);
        expect(result.toolUseId, equals('tr1'));
      });
    });
  });

  group('SamplingMessage', () {
    test('constructs with role and content', () {
      const msg = SamplingMessage(
        role: SamplingMessageRole.user,
        content: SamplingTextContent(text: 'Hello'),
      );
      expect(msg.role, equals(SamplingMessageRole.user));
      expect(msg.content, isA<SamplingTextContent>());
    });

    test('toJson serializes correctly', () {
      const msg = SamplingMessage(
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: 'Response'),
      );
      final json = msg.toJson();
      expect(json['role'], equals('assistant'));
      expect(json['content'], isA<Map>());
      expect(json['content']['text'], equals('Response'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'role': 'user',
        'content': {'type': 'text', 'text': 'Question'},
      };
      final msg = SamplingMessage.fromJson(json);
      expect(msg.role, equals(SamplingMessageRole.user));
      expect(msg.content, isA<SamplingTextContent>());
    });
  });

  group('CreateMessageRequestParams', () {
    test('constructs with required fields', () {
      final params = const CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Test'),
          ),
        ],
        maxTokens: 100,
      );
      expect(params.messages, hasLength(1));
      expect(params.maxTokens, equals(100));
    });

    test('toJson serializes all fields', () {
      final params = const CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Hello'),
          ),
        ],
        maxTokens: 500,
        includeContext: IncludeContext.thisServer,
        modelPreferences: ModelPreferences(costPriority: 0.5),
        stopSequences: ['STOP'],
        temperature: 0.7,
      );
      final json = params.toJson();
      expect(json['maxTokens'], equals(500));
      expect(json['includeContext'], equals('thisServer'));
      expect(json['stopSequences'], contains('STOP'));
      expect(json['temperature'], equals(0.7));
    });

    test('fromJson parses correctly', () {
      final json = {
        'messages': [
          {
            'role': 'assistant',
            'content': {'type': 'text', 'text': 'Response'},
          },
        ],
        'maxTokens': 200,
        'includeContext': 'allServers',
      };
      final params = CreateMessageRequestParams.fromJson(json);
      expect(params.messages, hasLength(1));
      expect(params.maxTokens, equals(200));
      expect(params.includeContext, equals(IncludeContext.allServers));
    });
  });

  group('CreateMessageResult', () {
    test('constructs with all fields', () {
      const result = CreateMessageResult(
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: 'Reply'),
        model: 'gpt-4',
        stopReason: StopReason.endTurn,
      );
      expect(result.role, equals(SamplingMessageRole.assistant));
      expect(result.model, equals('gpt-4'));
      expect(result.stopReason, equals(StopReason.endTurn));
    });

    test('toJson serializes correctly', () {
      const result = CreateMessageResult(
        role: SamplingMessageRole.assistant,
        content: SamplingTextContent(text: 'Answer'),
        model: 'claude-3',
        stopReason: StopReason.maxTokens,
      );
      final json = result.toJson();
      expect(json['role'], equals('assistant'));
      expect(json['model'], equals('claude-3'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'role': 'assistant',
        'content': {'type': 'text', 'text': 'Message'},
        'model': 'gemini',
        'stopReason': 'stopSequence',
      };
      final result = CreateMessageResult.fromJson(json);
      expect(result.role, equals(SamplingMessageRole.assistant));
      expect(result.model, equals('gemini'));
      expect(result.stopReason, equals(StopReason.stopSequence));
    });

    test('handles string stopReason', () {
      final json = {
        'role': 'assistant',
        'content': {'type': 'text', 'text': 'Msg'},
        'model': 'model-x',
        'stopReason': 'customReason',
      };
      final result = CreateMessageResult.fromJson(json);
      expect(result.stopReason, equals('customReason'));
    });
  });

  group('JsonRpcCreateMessageRequest', () {
    test('constructs correctly', () {
      final request = JsonRpcCreateMessageRequest(
        id: 1,
        createParams: const CreateMessageRequestParams(
          messages: [
            SamplingMessage(
              role: SamplingMessageRole.user,
              content: SamplingTextContent(text: 'Hi'),
            ),
          ],
          maxTokens: 50,
        ),
      );
      expect(request.id, equals(1));
      expect(request.method, equals('sampling/createMessage'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 42,
        'method': 'sampling/createMessage',
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Question'},
            },
          ],
          'maxTokens': 100,
        },
      };
      final request = JsonRpcCreateMessageRequest.fromJson(json);
      expect(request.id, equals(42));
      expect(request.createParams.maxTokens, equals(100));
    });

    test('fromJson throws on missing params', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'sampling/createMessage',
      };
      expect(
        () => JsonRpcCreateMessageRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('IncludeContext', () {
    test('has all expected values', () {
      expect(IncludeContext.values, hasLength(3));
      expect(IncludeContext.none.name, equals('none'));
      expect(IncludeContext.thisServer.name, equals('thisServer'));
      expect(IncludeContext.allServers.name, equals('allServers'));
    });
  });

  group('StopReason', () {
    test('has all expected values', () {
      expect(StopReason.values, hasLength(3));
      expect(StopReason.endTurn.name, equals('endTurn'));
      expect(StopReason.stopSequence.name, equals('stopSequence'));
      expect(StopReason.maxTokens.name, equals('maxTokens'));
    });
  });

  group('SamplingMessageRole', () {
    test('has all expected values', () {
      expect(SamplingMessageRole.values, hasLength(2));
      expect(SamplingMessageRole.user.name, equals('user'));
      expect(SamplingMessageRole.assistant.name, equals('assistant'));
    });
  });
}
