import 'package:mcp_dart/src/types/content.dart';
import 'package:mcp_dart/src/types/json_value.dart';
import 'package:mcp_dart/src/types/json_rpc.dart';
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

    test('rejects malformed wire fields', () {
      expect(
        () => ModelHint.fromJson({'name': 1}),
        throwsA(isA<FormatException>()),
      );
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

    test('rejects non-finite priorities', () {
      for (final value in [double.nan, double.infinity]) {
        expect(
          () => ModelPreferences.fromJson({'costPriority': value}),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ModelPreferences(costPriority: value).toJson(),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
      }
    });

    test('rejects malformed hint lists', () {
      expect(
        () => ModelPreferences.fromJson({'hints': 'model-a'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ModelPreferences.fromJson({
          'hints': [
            {'name': 1},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
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
        final json = {
          'type': 'text',
          'text': 'Parsed text',
          'annotations': {
            'audience': ['user'],
            'vendor': {'hint': true},
          },
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingTextContent>());
        final text = content as SamplingTextContent;
        expect(text.text, equals('Parsed text'));
        expect(text.annotations?['vendor'], equals({'hint': true}));
      });

      test('validates shared annotation fields', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'text',
            'text': 'Parsed text',
            'annotations': {
              'audience': ['model'],
            },
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const SamplingTextContent(
            text: 'Parsed text',
            annotations: {
              'priority': 2,
            },
          ).toJson(),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects malformed text wire fields', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 1,
            'text': 'Parsed text',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingContent.fromJson({
            'type': 'text',
            'text': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingTextContent.fromJson({
            'text': 'Parsed text',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingTextContent.fromJson({
            'type': 'image',
            'text': 'Parsed text',
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('SamplingImageContent', () {
      test('constructs correctly', () {
        const imageData = 'YmFzZTY0ZGF0YQ==';
        const content =
            SamplingImageContent(data: imageData, mimeType: 'image/png');
        expect(content.data, equals(imageData));
        expect(content.mimeType, equals('image/png'));
      });

      test('toJson serializes correctly', () {
        const imageData = 'aW1nZGF0YQ==';
        const content =
            SamplingImageContent(data: imageData, mimeType: 'image/jpeg');
        final json = content.toJson();
        expect(json['type'], equals('image'));
        expect(json['data'], equals(imageData));
        expect(json['mimeType'], equals('image/jpeg'));
      });

      test('fromJson parses correctly', () {
        const imageData = 'ZW5jb2RlZA==';
        final json = {
          'type': 'image',
          'data': imageData,
          'mimeType': 'image/gif',
          'annotations': {
            'audience': ['assistant'],
          },
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingImageContent>());
        final img = content as SamplingImageContent;
        expect(img.data, equals(imageData));
        expect(img.mimeType, equals('image/gif'));
        expect(img.annotations?['audience'], equals(['assistant']));
      });

      test('validates base64 byte data', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'image',
            'data': 'not base64!',
            'mimeType': 'image/png',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const SamplingImageContent(
            data: 'not base64!',
            mimeType: 'image/png',
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects malformed image wire fields', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'image',
            'data': 'aW1nZGF0YQ==',
            'mimeType': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingImageContent.fromJson({
            'data': 'aW1nZGF0YQ==',
            'mimeType': 'image/png',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingImageContent.fromJson({
            'type': 'text',
            'data': 'aW1nZGF0YQ==',
            'mimeType': 'image/png',
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('SamplingAudioContent', () {
      test('constructs correctly', () {
        const audioData = 'YmFzZTY0YXVkaW8=';
        const content = SamplingAudioContent(
          data: audioData,
          mimeType: 'audio/wav',
        );
        expect(content.data, equals(audioData));
        expect(content.mimeType, equals('audio/wav'));
      });

      test('toJson serializes correctly', () {
        const audioData = 'YXVkaW8tZGF0YQ==';
        const content = SamplingAudioContent(
          data: audioData,
          mimeType: 'audio/mpeg',
        );
        final json = content.toJson();
        expect(json['type'], equals('audio'));
        expect(json['data'], equals(audioData));
        expect(json['mimeType'], equals('audio/mpeg'));
      });

      test('fromJson parses correctly', () {
        const audioData = 'ZW5jb2RlZC1hdWRpbw==';
        final json = {
          'type': 'audio',
          'data': audioData,
          'mimeType': 'audio/ogg',
          'annotations': {
            'priority': 0.2,
          },
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingAudioContent>());
        final audio = content as SamplingAudioContent;
        expect(audio.data, equals(audioData));
        expect(audio.mimeType, equals('audio/ogg'));
        expect(audio.annotations?['priority'], equals(0.2));
      });

      test('validates base64 byte data', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'audio',
            'data': 'not base64!',
            'mimeType': 'audio/wav',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const SamplingAudioContent(
            data: 'not base64!',
            mimeType: 'audio/wav',
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects malformed audio wire fields', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'audio',
            'data': 'YXVkaW8tZGF0YQ==',
            'mimeType': 1,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingAudioContent.fromJson({
            'data': 'YXVkaW8tZGF0YQ==',
            'mimeType': 'audio/wav',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingAudioContent.fromJson({
            'type': 'image',
            'data': 'YXVkaW8tZGF0YQ==',
            'mimeType': 'audio/wav',
          }),
          throwsA(isA<FormatException>()),
        );
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

      test('rejects non-JSON input objects', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'tool_use',
            'id': 'tu1',
            'name': 'fetch',
            'input': {1: 'bad'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const SamplingToolUseContent(
            id: 'tu1',
            name: 'fetch',
            input: {'bad': Object()},
          ).toJson(),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects malformed tool use wire fields', () {
        expect(
          () => SamplingContent.fromJson({
            'type': 'tool_use',
            'id': 1,
            'name': 'fetch',
            'input': {'url': 'http://test.com'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingContent.fromJson({
            'type': 'tool_use',
            'id': 'tu1',
            'name': 1,
            'input': {'url': 'http://test.com'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolUseContent.fromJson({
            'id': 'tu1',
            'name': 'fetch',
            'input': {'url': 'http://test.com'},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolUseContent.fromJson({
            'type': 'tool_result',
            'id': 'tu1',
            'name': 'fetch',
            'input': {'url': 'http://test.com'},
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('SamplingToolResultContent', () {
      test('constructs correctly', () {
        const content = SamplingToolResultContent(
          toolUseId: 'result-123',
          content: [
            TextContent(text: 'ok'),
          ],
        );
        expect(content.toolUseId, equals('result-123'));
      });

      test('toJson serializes correctly', () {
        const content = SamplingToolResultContent(
          toolUseId: 'res1',
          content: [
            TextContent(text: 'value 42'),
          ],
          structuredContent: {'value': 42},
          isError: true,
        );
        final json = content.toJson();
        expect(json['type'], equals('tool_result'));
        expect(json['toolUseId'], equals('res1'));
        expect(json['isError'], isTrue);
        expect(json['structuredContent'], equals({'value': 42}));
        expect(json['content'], isA<List>());
        expect((json['content'] as List).first['type'], equals('text'));
      });

      test('toJson preserves arbitrary structured JSON values', () {
        final content = SamplingToolResultContent(
          toolUseId: 'res1',
          content: [
            const TextContent(text: 'array result'),
          ],
          structuredContentJson: JsonValue.array(['alpha', 'beta']),
        );
        final json = content.toJson();
        expect(json['structuredContent'], equals(['alpha', 'beta']));

        const nullContent = SamplingToolResultContent(
          toolUseId: 'res2',
          content: [
            TextContent(text: 'null result'),
          ],
          structuredContentJson: JsonValue.nullValue,
          hasStructuredContent: true,
        );
        final nullJson = nullContent.toJson();
        expect(nullJson.containsKey('structuredContent'), isTrue);
        expect(nullJson['structuredContent'], isNull);
      });

      test('normalizes contradictory structured inputs', () {
        final arrayContent = SamplingToolResultContent(
          toolUseId: 'res1',
          content: const [],
          structuredContent: const {'legacy': true},
          structuredContentJson: JsonValue.array(['canonical']),
          hasStructuredContent: false,
        );

        expect(arrayContent.hasStructuredContent, isTrue);
        expect(arrayContent.structuredContent, isNull);
        expect(arrayContent.structuredContentJson?.toJson(), ['canonical']);
        expect(arrayContent.toJson()['structuredContent'], ['canonical']);

        final objectContent = SamplingToolResultContent(
          toolUseId: 'res2',
          content: const [],
          structuredContent: const {'legacy': true},
          structuredContentJson: JsonValue.object({'canonical': true}),
          hasStructuredContent: false,
        );

        expect(objectContent.hasStructuredContent, isTrue);
        expect(objectContent.structuredContent, {'canonical': true});
        expect(
          objectContent.structuredContentJson?.toJson(),
          {'canonical': true},
        );
        expect(
          objectContent.toJson()['structuredContent'],
          {'canonical': true},
        );

        const legacyContent = SamplingToolResultContent(
          toolUseId: 'res3',
          content: [],
          structuredContent: {'legacy': true},
          hasStructuredContent: false,
        );
        expect(legacyContent.hasStructuredContent, isTrue);
        expect(legacyContent.structuredContent, {'legacy': true});
        expect(legacyContent.structuredContentJson?.toJson(), {'legacy': true});

        const canonicalNullContent = SamplingToolResultContent(
          toolUseId: 'res4',
          content: [],
          structuredContent: {'legacy': true},
          structuredContentJson: JsonValue.nullValue,
          hasStructuredContent: false,
        );
        expect(canonicalNullContent.hasStructuredContent, isTrue);
        expect(canonicalNullContent.structuredContent, isNull);
        expect(canonicalNullContent.structuredContentJson?.toJson(), isNull);
        expect(
          canonicalNullContent.toJson(),
          containsPair('structuredContent', null),
        );

        const explicitNullContent = SamplingToolResultContent(
          toolUseId: 'res5',
          content: [],
          hasStructuredContent: true,
        );
        expect(explicitNullContent.hasStructuredContent, isTrue);
        expect(explicitNullContent.structuredContentJson?.toJson(), isNull);
      });

      test('fromJson parses correctly', () {
        final json = {
          'type': 'tool_result',
          'toolUseId': 'tr1',
          'content': [
            {'type': 'text', 'text': 'result data'},
          ],
          'structuredContent': {'status': 'ok'},
          'isError': false,
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingToolResultContent>());
        final result = content as SamplingToolResultContent;
        expect(result.isError, isFalse);
        expect(result.toolUseId, equals('tr1'));
        expect(result.structuredContent, equals({'status': 'ok'}));
        expect(result.content, hasLength(1));
        expect(result.content.first, isA<TextContent>());
      });

      test('fromJson parses arbitrary structured JSON values', () {
        final json = {
          'type': 'tool_result',
          'toolUseId': 'tr1',
          'content': [
            {'type': 'text', 'text': 'result data'},
          ],
          'structuredContent': ['alpha', 'beta'],
        };
        final content = SamplingContent.fromJson(json);
        expect(content, isA<SamplingToolResultContent>());
        final result = content as SamplingToolResultContent;
        expect(result.hasStructuredContent, isTrue);
        expect(
          result.structuredContentJson?.toJson(),
          equals(['alpha', 'beta']),
        );

        final nullJson = {
          'type': 'tool_result',
          'toolUseId': 'tr2',
          'content': [
            {'type': 'text', 'text': 'result data'},
          ],
          'structuredContent': null,
        };
        final nullContent =
            SamplingContent.fromJson(nullJson) as SamplingToolResultContent;
        expect(nullContent.hasStructuredContent, isTrue);
        expect(nullContent.structuredContentJson?.toJson(), isNull);
      });

      test('rejects malformed tool result wire fields', () {
        final content = [
          {'type': 'text', 'text': 'result data'},
        ];
        expect(
          () => SamplingContent.fromJson({
            'type': 'tool_result',
            'toolUseId': 1,
            'content': content,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingContent.fromJson({
            'type': 'tool_result',
            'toolUseId': 'tr1',
            'content': content,
            'isError': 'false',
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolResultContent.fromJson({
            'toolUseId': 'tr1',
            'content': content,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => SamplingToolResultContent.fromJson({
            'type': 'tool_use',
            'toolUseId': 'tr1',
            'content': content,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => const SamplingToolResultContent(
            toolUseId: 'tr1',
            content: {1: 'bad'},
          ).toJson(),
          throwsA(isA<FormatException>()),
        );
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

    test('validates role wire values', () {
      expect(
        () => SamplingMessage.fromJson({
          'role': 'system',
          'content': {'type': 'text', 'text': 'Question'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SamplingMessage.fromJson({
          'role': 1,
          'content': {'type': 'text', 'text': 'Question'},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('supports array content with normalized contentBlocks', () {
      final msg = const SamplingMessage(
        role: SamplingMessageRole.assistant,
        content: [
          SamplingTextContent(text: 'Part 1'),
          SamplingTextContent(text: 'Part 2'),
        ],
      );

      expect(msg.content, isA<List<SamplingContent>>());
      expect(msg.contentBlocks, hasLength(2));
      expect(msg.toJson()['content'], isA<List>());
    });

    test('rejects non-JSON metadata objects', () {
      expect(
        () => SamplingMessage.fromJson({
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
          '_meta': {1: 'bad'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const SamplingMessage(
          role: SamplingMessageRole.user,
          content: SamplingTextContent(text: 'Hello'),
          meta: {'bad': Object()},
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
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

    test('supports legacy toolChoice map with type', () {
      final params = const CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Hello'),
          ),
        ],
        maxTokens: 500,
        toolChoice: {'type': 'required'},
      );

      expect(params.toolChoice, {'type': 'required'});
      expect(params.toolChoiceConfig?.mode, ToolChoiceMode.required);
      expect(params.toJson()['toolChoice'], {'mode': 'required'});
    });

    test('supports typed ToolChoice in constructor', () {
      final params = const CreateMessageRequestParams(
        messages: [
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Hello'),
          ),
        ],
        maxTokens: 500,
        toolChoice: ToolChoice(mode: ToolChoiceMode.auto),
      );

      expect(params.toolChoiceConfig?.mode, ToolChoiceMode.auto);
      expect(params.toJson()['toolChoice'], {'mode': 'auto'});
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

    test('validates enum wire fields', () {
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
        },
      ];
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'includeContext': 'nearbyServers',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'includeContext': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'toolChoice': {'mode': 'sometimes'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'toolChoice': {'mode': 1},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const CreateMessageRequestParams(
          messages: [
            SamplingMessage(
              role: SamplingMessageRole.user,
              content: SamplingTextContent(text: 'Hello'),
            ),
          ],
          maxTokens: 100,
          toolChoice: {1: 'required'},
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
    });

    test('validates string wire fields', () {
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
        },
      ];
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'systemPrompt': 1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'stopSequences': 'STOP',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'stopSequences': ['STOP', 1],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('validates tool wire fields', () {
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
        },
      ];
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'tools': 'bad',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'tools': [1],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts whole-number JSON maxTokens values', () {
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
        },
      ];

      final params = CreateMessageRequestParams.fromJson({
        'messages': messages,
        'maxTokens': 100.0,
      });

      expect(params.maxTokens, 100);
      expect(params.toJson()['maxTokens'], 100);

      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100.5,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-finite temperature values', () {
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
        },
      ];
      for (final value in [double.nan, double.infinity]) {
        expect(
          () => CreateMessageRequestParams.fromJson({
            'messages': messages,
            'maxTokens': 100,
            'temperature': value,
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => CreateMessageRequestParams(
            messages: const [
              SamplingMessage(
                role: SamplingMessageRole.user,
                content: SamplingTextContent(text: 'Hello'),
              ),
            ],
            maxTokens: 100,
            temperature: value,
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test('rejects non-JSON metadata objects', () {
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'Hello'},
        },
      ];
      expect(
        () => CreateMessageRequestParams.fromJson({
          'messages': messages,
          'maxTokens': 100,
          'metadata': {1: 'bad'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const CreateMessageRequestParams(
          messages: [
            SamplingMessage(
              role: SamplingMessageRole.user,
              content: SamplingTextContent(text: 'Hello'),
            ),
          ],
          maxTokens: 100,
          metadata: {'bad': Object()},
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
    });

    group('tool-use message sequence validation', () {
      const toolUseA = SamplingToolUseContent(
        id: 'call-a',
        name: 'lookup',
        input: {'query': 'a'},
      );
      const toolUseB = SamplingToolUseContent(
        id: 'call-b',
        name: 'lookup',
        input: {'query': 'b'},
      );
      const resultA = SamplingToolResultContent(
        toolUseId: 'call-a',
        content: [TextContent(text: 'A')],
      );
      const resultB = SamplingToolResultContent(
        toolUseId: 'call-b',
        content: [TextContent(text: 'B')],
      );

      test('accepts exactly matched parallel tool uses and results', () {
        final request = const CreateMessageRequestParams(
          messages: [
            SamplingMessage(
              role: SamplingMessageRole.assistant,
              content: [toolUseA, toolUseB],
            ),
            SamplingMessage(
              role: SamplingMessageRole.user,
              content: [resultB, resultA],
            ),
            SamplingMessage(
              role: SamplingMessageRole.assistant,
              content: SamplingTextContent(text: 'Done'),
            ),
          ],
          maxTokens: 100,
        );

        expect(request.toJson()['messages'], hasLength(3));
      });

      test('rejects a user message that mixes tool results and text', () {
        expect(
          () => const CreateMessageRequestParams(
            messages: [
              SamplingMessage(
                role: SamplingMessageRole.assistant,
                content: toolUseA,
              ),
              SamplingMessage(
                role: SamplingMessageRole.user,
                content: [
                  SamplingTextContent(text: 'Result:'),
                  resultA,
                ],
              ),
            ],
            maxTokens: 100,
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects missing, unexpected, and duplicate tool result IDs', () {
        for (final results in <List<SamplingContent>>[
          const [resultA],
          const [
            resultA,
            SamplingToolResultContent(
              toolUseId: 'call-extra',
              content: [TextContent(text: 'extra')],
            ),
          ],
          const [resultA, resultA],
        ]) {
          expect(
            () => CreateMessageRequestParams(
              messages: [
                const SamplingMessage(
                  role: SamplingMessageRole.assistant,
                  content: [toolUseA, toolUseB],
                ),
                SamplingMessage(
                  role: SamplingMessageRole.user,
                  content: results,
                ),
              ],
              maxTokens: 100,
            ).toJson(),
            throwsA(isA<ArgumentError>()),
          );
        }
      });

      test('reports mismatched tool IDs in sorted order', () {
        expect(
          () => const CreateMessageRequestParams(
            messages: [
              SamplingMessage(
                role: SamplingMessageRole.assistant,
                content: [toolUseB, toolUseA],
              ),
              SamplingMessage(
                role: SamplingMessageRole.user,
                content: [
                  SamplingToolResultContent(
                    toolUseId: 'call-z',
                    content: [TextContent(text: 'z')],
                  ),
                  SamplingToolResultContent(
                    toolUseId: 'call-c',
                    content: [TextContent(text: 'c')],
                  ),
                ],
              ),
            ],
            maxTokens: 100,
          ).toJson(),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains(
                'missing: [call-a, call-b], '
                'unexpected: [call-c, call-z]',
              ),
            ),
          ),
        );
      });

      test('rejects a tool use without an immediate result message', () {
        expect(
          () => const CreateMessageRequestParams(
            messages: [
              SamplingMessage(
                role: SamplingMessageRole.assistant,
                content: toolUseA,
              ),
              SamplingMessage(
                role: SamplingMessageRole.assistant,
                content: SamplingTextContent(text: 'continued'),
              ),
            ],
            maxTokens: 100,
          ).toJson(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects orphan and role-invalid tool blocks when decoding', () {
        for (final messages in <List<Map<String, dynamic>>>[
          [
            {
              'role': 'user',
              'content': resultA.toJson(),
            },
          ],
          [
            {
              'role': 'user',
              'content': toolUseA.toJson(),
            },
          ],
          [
            {
              'role': 'assistant',
              'content': resultA.toJson(),
            },
          ],
        ]) {
          expect(
            () => CreateMessageRequestParams.fromJson({
              'messages': messages,
              'maxTokens': 100,
            }),
            throwsA(isA<FormatException>()),
          );
        }
      });
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

    test('supports array content with normalized contentBlocks', () {
      const result = CreateMessageResult(
        role: SamplingMessageRole.assistant,
        content: [
          SamplingTextContent(text: 'Part 1'),
          SamplingTextContent(text: 'Part 2'),
        ],
        model: 'gpt-4',
      );

      expect(result.contentBlocks, hasLength(2));
      expect(result.toJson()['content'], isA<List>());
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

    test('validates role wire values', () {
      expect(
        () => CreateMessageResult.fromJson({
          'role': 'system',
          'content': {'type': 'text', 'text': 'Msg'},
          'model': 'model-x',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CreateMessageResult.fromJson({
          'role': 1,
          'content': {'type': 'text', 'text': 'Msg'},
          'model': 'model-x',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('validates model wire field', () {
      expect(
        () => CreateMessageResult.fromJson({
          'role': 'assistant',
          'content': {'type': 'text', 'text': 'Msg'},
          'model': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-JSON metadata objects', () {
      expect(
        () => CreateMessageResult.fromJson({
          'role': 'assistant',
          'content': {'type': 'text', 'text': 'Message'},
          'model': 'model-x',
          '_meta': {1: 'bad'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const CreateMessageResult(
          role: SamplingMessageRole.assistant,
          content: SamplingTextContent(text: 'Message'),
          model: 'model-x',
          meta: {'bad': Object()},
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
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

    test('fromJson rejects non-object params', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'sampling/createMessage',
        'params': 'bad',
      };
      expect(
        () => JsonRpcCreateMessageRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson rejects wrong wrapper constants', () {
      final params = {
        'messages': [
          {
            'role': 'user',
            'content': {'type': 'text', 'text': 'Question'},
          },
        ],
        'maxTokens': 100,
      };

      expect(
        () => JsonRpcCreateMessageRequest.fromJson({
          'jsonrpc': '1.0',
          'id': 1,
          'method': Method.samplingCreateMessage,
          'params': params,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRpcCreateMessageRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.elicitationCreate,
          'params': params,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('embedded input requests do not require JSON-RPC wrapper fields', () {
      final request = InputRequest.fromJson({
        'method': Method.samplingCreateMessage,
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Question'},
            },
          ],
          'maxTokens': 100,
        },
      });

      expect(request.method, Method.samplingCreateMessage);
      expect(request.createMessageParams.maxTokens, 100);
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
      expect(StopReason.values, hasLength(4));
      expect(StopReason.endTurn.name, equals('endTurn'));
      expect(StopReason.stopSequence.name, equals('stopSequence'));
      expect(StopReason.maxTokens.name, equals('maxTokens'));
      expect(StopReason.toolUse.name, equals('toolUse'));
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
