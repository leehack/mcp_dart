import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Tool parameter header annotations', () {
    test('schema objects preserve x-mcp-header round-trip', () {
      final schema = JsonSchema.object(
        properties: {
          'region': JsonSchema.string(mcpHeader: 'Region'),
          'limit': JsonSchema.number(mcpHeader: 'Limit'),
          'count': JsonSchema.integer(mcpHeader: 'Count'),
          'dryRun': JsonSchema.boolean(mcpHeader: 'Dry-Run'),
        },
      );

      final json = schema.toJson();
      final properties = json['properties'] as Map<String, dynamic>;
      expect(properties['region']['x-mcp-header'], 'Region');
      expect(properties['limit']['x-mcp-header'], 'Limit');
      expect(properties['count']['x-mcp-header'], 'Count');
      expect(properties['dryRun']['x-mcp-header'], 'Dry-Run');

      final parsed = JsonSchema.fromJson(json) as JsonObject;
      final parsedProperties = parsed.properties!;
      expect((parsedProperties['region'] as JsonString).mcpHeader, 'Region');
      expect((parsedProperties['limit'] as JsonNumber).mcpHeader, 'Limit');
      expect((parsedProperties['count'] as JsonInteger).mcpHeader, 'Count');
      expect(
        (parsedProperties['dryRun'] as JsonBoolean).mcpHeader,
        'Dry-Run',
      );
      expect(parsed.toJson(), json);
    });

    test('non-primitive x-mcp-header annotations remain visible', () {
      final schema = JsonSchema.fromJson({
        'type': 'object',
        'x-mcp-header': 'Payload',
      });

      expect(schema, isA<JsonAny>());
      expect(schema.toJson()['x-mcp-header'], 'Payload');
    });
  });

  group('Tool Schema Required Fields Tests', () {
    test('ToolInputSchema preserves required fields during serialization', () {
      final schema = JsonObject(
        properties: {
          'operation': JsonSchema.string(),
          'a': JsonSchema.number(),
          'b': JsonSchema.number(),
        },
        required: ['operation', 'a'],
      );

      final json = schema.toJson();
      expect(json['type'], equals('object'));
      expect(json['properties'], isA<Map<String, dynamic>>());
      expect(json['required'], equals(['operation', 'a']));
    });

    test('ToolInputSchema preserves required fields during deserialization',
        () {
      final json = {
        'type': 'object',
        'properties': {
          'operation': {'type': 'string'},
          'a': {'type': 'number'},
          'b': {'type': 'number'},
        },
        'required': ['operation', 'a'],
      };

      final schema = ToolInputSchema.fromJson(json);
      expect(schema.toJson()['type'], equals('object'));
      expect(schema.toJson()['properties'], equals(json['properties']));
      expect(schema.toJson()['required'], equals(['operation', 'a']));
    });

    test('ToolInputSchema handles empty required array', () {
      final schema = JsonObject(
        properties: {
          'optional': JsonSchema.string(),
        },
        required: [],
      );

      final json = schema.toJson();
      // Empty required array should not be included in JSON
      expect(json.containsKey('required'), isFalse);
    });

    test('ToolInputSchema handles null required field', () {
      final schema = JsonObject(
        properties: {
          'optional': JsonSchema.string(),
        },
        required: null,
      );

      final json = schema.toJson();
      expect(json.containsKey('required'), isFalse);
    });

    test('ToolOutputSchema preserves required fields during serialization', () {
      final schema = JsonObject(
        properties: {
          'result': JsonSchema.string(),
          'status': JsonSchema.number(),
        },
        required: ['result'],
      );

      final json = schema.toJson();
      expect(json['type'], equals('object'));
      expect(json['properties'], isA<Map<String, dynamic>>());
      expect(json['required'], equals(['result']));
    });

    test('ToolOutputSchema preserves required fields during deserialization',
        () {
      final json = {
        'type': 'object',
        'properties': {
          'result': {'type': 'string'},
          'status': {'type': 'number'},
        },
        'required': ['result'],
      };

      final schema = ToolOutputSchema.fromJson(json);
      expect(schema.toJson()['type'], equals('object'));
      expect(schema.toJson()['properties'], equals(json['properties']));
      expect(schema.toJson()['required'], equals(['result']));
    });

    test('Tool preserves input schema required fields end-to-end', () {
      final tool = Tool(
        name: 'calculate',
        description: 'Performs mathematical calculations',
        inputSchema: JsonObject(
          properties: {
            'operation': JsonSchema.string(),
            'a': JsonSchema.number(),
            'b': JsonSchema.number(),
          },
          required: ['operation', 'a'],
        ),
      );

      final json = tool.toJson();
      expect(json['name'], equals('calculate'));
      expect(json['inputSchema']['required'], equals(['operation', 'a']));

      final deserialized = Tool.fromJson(json);
      expect(deserialized.name, equals('calculate'));
      expect(
        (deserialized.inputSchema as JsonObject).required,
        equals(['operation', 'a']),
      );
    });

    test('Tool preserves output schema required fields end-to-end', () {
      final tool = Tool(
        name: 'calculate',
        inputSchema: const JsonObject(),
        outputSchema: JsonObject(
          properties: {
            'result': JsonSchema.number(),
            'equation': JsonSchema.string(),
          },
          required: ['result'],
        ),
      );

      final json = tool.toJson();
      expect(json['outputSchema']['required'], equals(['result']));

      final deserialized = Tool.fromJson(json);
      expect(
        (deserialized.outputSchema as JsonObject?)?.required,
        equals(['result']),
      );
    });

    test('Tool preserves non-object output schemas for MCP 2026', () {
      final tool = Tool(
        name: 'list_results',
        inputSchema: const JsonObject(),
        outputSchema: JsonSchema.array(items: JsonSchema.string()),
      );

      final json = tool.toJson();
      expect(json['outputSchema']['type'], equals('array'));
      expect(json['outputSchema']['items']['type'], equals('string'));

      final deserialized = Tool.fromJson(json);
      expect(
        deserialized.outputSchema?.toJson(),
        equals(json['outputSchema']),
      );
    });

    test('CallToolResult preserves arbitrary JSON structured content', () {
      final values = <Object?>[
        {'status': 'ok'},
        ['alpha', 'beta'],
        'complete',
        42,
        true,
      ];

      for (final value in values) {
        final result = CallToolResult.fromStructuredContent(value);
        final json = result.toJson();

        expect(json['structuredContent'], equals(value));

        final parsed = CallToolResult.fromJson(json);
        expect(parsed.hasStructuredContent, isTrue);
        expect(parsed.structuredContent, equals(value));
      }

      final nullResult = CallToolResult.fromStructuredContent(null);
      final nullJson = nullResult.toJson();
      expect(nullJson.containsKey('structuredContent'), isTrue);
      expect(nullJson['structuredContent'], isNull);

      final parsedNull = CallToolResult.fromJson(nullJson);
      expect(parsedNull.hasStructuredContent, isTrue);
      expect(parsedNull.structuredContent, isNull);
    });

    test('Tool JSON object fields reject non-JSON Dart map values', () {
      expect(
        () => Tool.fromJson({
          'name': 'search',
          'inputSchema': {'type': 'object'},
          '_meta': {'bad': Object()},
        }),
        throwsFormatException,
      );
      expect(
        () => const Tool(
          name: 'search',
          inputSchema: JsonObject(),
          meta: {'bad': Object()},
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => CallToolRequest.fromJson({
          'name': 'search',
          'arguments': {'bad': Object()},
        }),
        throwsFormatException,
      );
      expect(
        () => const CallToolRequest(
          name: 'search',
          arguments: {'bad': Object()},
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => CallToolResult.fromJson({
          'content': <Map<String, dynamic>>[],
          '_meta': {'bad': Object()},
        }),
        throwsFormatException,
      );
      expect(
        () => const CallToolResult(
          content: [],
          meta: {'bad': Object()},
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => CallToolResult.fromJson({
          'content': <Map<String, dynamic>>[],
          'x-extra': Object(),
        }),
        throwsFormatException,
      );
    });

    test('Tool serializes JsonEnum properties as standard enum schema', () {
      const tool = Tool(
        name: 'configure_mode',
        inputSchema: JsonObject(
          properties: {
            'mode': JsonEnum([
              'simple',
              {'value': 'complex', 'title': 'Complex Option'},
            ]),
          },
        ),
      );

      final json = tool.toJson();
      final modeSchema =
          json['inputSchema']['properties']['mode'] as Map<String, dynamic>;

      expect(modeSchema['type'], equals('string'));
      expect(
        modeSchema['oneOf'],
        equals([
          {'const': 'simple'},
          {'const': 'complex', 'title': 'Complex Option'},
        ]),
      );
      expect(modeSchema.containsKey('values'), isFalse);

      final restored = Tool.fromJson(json);
      final restoredMode =
          (restored.inputSchema as JsonObject).properties!['mode'] as JsonEnum;
      expect(restoredMode.normalizedValues, equals(['simple', 'complex']));
      expect((restoredMode.values[1] as Map)['title'], 'Complex Option');
    });

    test('ListToolsResult preserves tool required fields', () {
      final tools = [
        Tool(
          name: 'search',
          inputSchema: JsonObject(
            properties: {
              'query': JsonSchema.string(),
              'limit': JsonSchema.number(),
            },
            required: ['query'],
          ),
        ),
        Tool(
          name: 'create',
          inputSchema: JsonObject(
            properties: {
              'name': JsonSchema.string(),
              'data': JsonSchema.object(),
            },
            required: ['name', 'data'],
          ),
        ),
      ];

      final result = ListToolsResult(tools: tools);
      final json = result.toJson();

      expect(json['tools'][0]['inputSchema']['required'], equals(['query']));
      expect(
        json['tools'][1]['inputSchema']['required'],
        equals(['name', 'data']),
      );

      final deserialized = ListToolsResult.fromJson(json);
      expect(
        (deserialized.tools[0].inputSchema as JsonObject).required,
        equals(['query']),
      );
      expect(
        (deserialized.tools[1].inputSchema as JsonObject).required,
        equals(['name', 'data']),
      );
    });

    test('Real-world MCP server tool schema example', () {
      // Example from a real MCP server like Hugging Face
      final serverResponse = {
        'tools': [
          {
            'name': 'space_search',
            'description': 'Search for Hugging Face Spaces',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': 'Search query for spaces',
                },
                'limit': {
                  'type': 'integer',
                  'description': 'Maximum number of results',
                  'default': 10,
                },
              },
              'required': ['query'],
            },
          }
        ],
      };

      final result = ListToolsResult.fromJson(serverResponse);
      final tool = result.tools.first;

      expect(tool.name, equals('space_search'));
      expect((tool.inputSchema as JsonObject).required, equals(['query']));
      expect(
        (tool.inputSchema as JsonObject).properties?['query']?.toJson()['type'],
        equals('string'),
      );
      expect(
        (tool.inputSchema as JsonObject).properties?['limit']?.defaultValue,
        equals(10),
      );

      // Verify round-trip maintains required fields
      final serialized = result.toJson();
      expect(
        serialized['tools'][0]['inputSchema']['required'],
        equals(['query']),
      );
    });

    test('Backward compatibility with existing code without required fields',
        () {
      // Existing code that doesn't specify required fields should still work
      final tool = Tool(
        name: 'legacy-tool',
        inputSchema: JsonObject(
          properties: {
            'param': JsonSchema.string(),
          },
        ),
      );

      final json = tool.toJson();
      expect(json['name'], equals('legacy-tool'));
      expect(json['inputSchema'].containsKey('required'), isFalse);

      final deserialized = Tool.fromJson(json);
      expect(deserialized.name, equals('legacy-tool'));
      expect((deserialized.inputSchema as JsonObject).required, isNull);
    });

    test('JSON Schema from external server without required fields', () {
      // Some servers might not include required fields
      final externalToolJson = {
        'name': 'external-tool',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'param': {'type': 'string'},
          },
          // No 'required' field
        },
      };

      final tool = Tool.fromJson(externalToolJson);
      expect(tool.name, equals('external-tool'));
      expect((tool.inputSchema as JsonObject).required, isNull);

      // Should still serialize correctly
      final serialized = tool.toJson();
      expect(serialized['inputSchema'].containsKey('required'), isFalse);
    });
  });

  group('LLM Integration Tests', () {
    test('Tool schema is compatible with OpenAI function calling format', () {
      final tool = Tool(
        name: 'get_weather',
        description: 'Get weather information for a location',
        inputSchema: JsonObject(
          properties: {
            'location': JsonSchema.string(
              description: 'The city and state, e.g. San Francisco, CA',
            ),
            'unit': JsonSchema.string(
              enumValues: ['celsius', 'fahrenheit'],
              description: 'Temperature unit',
            ),
          },
          required: ['location'],
        ),
      );

      // Convert to OpenAI function calling format
      final openaiFunction = {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.inputSchema.toJson(),
        },
      };

      final function = openaiFunction['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      final location = properties['location'] as Map<String, dynamic>;

      expect(function['name'], equals('get_weather'));
      expect(parameters['type'], equals('object'));
      expect(parameters['required'], equals(['location']));
      expect(location['type'], equals('string'));
    });

    test('Tool schema is compatible with Anthropic Claude format', () {
      final tool = Tool(
        name: 'analyze_code',
        description: 'Analyze code for potential issues',
        inputSchema: JsonObject(
          properties: {
            'code': JsonSchema.string(description: 'The code to analyze'),
            'language': JsonSchema.string(
              description: 'Programming language',
            ),
            'strict': JsonSchema.boolean(
              description: 'Enable strict mode',
              defaultValue: false,
            ),
          },
          required: ['code', 'language'],
        ),
      );

      // Convert to Anthropic tool format
      final anthropicTool = {
        'name': tool.name,
        'description': tool.description,
        'input_schema': tool.inputSchema.toJson(),
      };

      expect(anthropicTool['name'], equals('analyze_code'));
      final inputSchema = anthropicTool['input_schema'] as Map<String, dynamic>;
      final properties = inputSchema['properties'] as Map<String, dynamic>;
      final strict = properties['strict'] as Map<String, dynamic>;

      expect(inputSchema['required'], equals(['code', 'language']));
      expect(strict['default'], equals(false));
    });
  });
}
