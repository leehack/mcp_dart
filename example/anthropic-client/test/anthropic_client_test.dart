import 'dart:convert';

import 'package:anthropic_client/anthropic_client.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;
import 'package:test/test.dart';

void main() {
  test('preserves tool-use turns and correlates MCP tool results', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final requests = <MessageCreateRequest>[];
    final toolRequests = <mcp_dart.CallToolRequest>[];
    final responses = <Message>[
      _message([
        {'type': 'text', 'text': 'I will check.'},
        {
          'type': 'tool_use',
          'id': 'toolu_weather_1',
          'name': 'weather',
          'input': {'city': 'Toronto'},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'It is 23 C.'},
      ]),
    ];

    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolApprover: _approveAll,
      toolLister: _listTools([
        const mcp_dart.Tool(
          name: 'weather',
          description: 'Get the weather',
          inputSchema: mcp_dart.JsonObject(
            properties: {'city': mcp_dart.JsonString()},
            required: ['city'],
          ),
        ),
      ]),
      toolCaller: (request) async {
        toolRequests.add(request);
        return const mcp_dart.CallToolResult(
          content: [mcp_dart.TextContent(text: '23 C')],
          structuredContent: {'temperature': 23},
        );
      },
    );
    final output = await client.processQuery('Weather in Toronto?');

    expect(
      output,
      'I will check.\n'
      '[Calling tool "weather" with args {"city":"Toronto"}]\n'
      'It is 23 C.',
    );
    expect(toolRequests, hasLength(1));
    expect(toolRequests.single.name, 'weather');
    expect(toolRequests.single.arguments, {'city': 'Toronto'});
    expect(requests, hasLength(2));
    expect(
      requests.every((request) => request.model == defaultAnthropicModel),
      isTrue,
    );
    expect(requests.every((request) => request.tools?.length == 1), isTrue);
    expect(_wireJson(requests.first)['thinking'], {'type': 'disabled'});

    final followUp = _wireJson(requests[1]);
    final messages = followUp['messages'] as List<dynamic>;
    expect(messages, hasLength(3));
    expect(messages[0], {'role': 'user', 'content': 'Weather in Toronto?'});

    final assistant = messages[1] as Map<String, dynamic>;
    expect(assistant['role'], 'assistant');
    expect(assistant['content'], [
      {'type': 'text', 'text': 'I will check.'},
      {
        'type': 'tool_use',
        'id': 'toolu_weather_1',
        'name': 'weather',
        'input': {'city': 'Toronto'},
      },
    ]);

    final userResult = messages[2] as Map<String, dynamic>;
    expect(userResult['role'], 'user');
    final resultBlock =
        (userResult['content'] as List<dynamic>).single as Map<String, dynamic>;
    expect(resultBlock['type'], 'tool_result');
    expect(resultBlock['tool_use_id'], 'toolu_weather_1');
    expect(resultBlock.containsKey('is_error'), isFalse);
    final resultContent = resultBlock['content'] as List<dynamic>;
    expect(resultContent, [
      {'type': 'text', 'text': '23 C'},
      {'type': 'text', 'text': 'Structured content: {"temperature":23}'},
    ]);
  });

  test('returns multiple tool results in assistant order', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final requests = <MessageCreateRequest>[];
    final responses = <Message>[
      _message([
        {
          'type': 'tool_use',
          'id': 'call_1',
          'name': 'first',
          'input': <String, dynamic>{},
        },
        {
          'type': 'tool_use',
          'id': 'call_2',
          'name': 'second',
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'Done'},
      ]),
    ];

    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolApprover: _approveAll,
      toolLister: _listNamedTools(['first', 'second']),
      toolCaller:
          (request) async => mcp_dart.CallToolResult(
            content: [mcp_dart.TextContent(text: request.name)],
            isError: request.name == 'second',
          ),
    );
    await client.processQuery('Run both');

    final messages = _wireJson(requests[1])['messages'] as List<dynamic>;
    final resultTurn = messages[2] as Map<String, dynamic>;
    final results = resultTurn['content'] as List<dynamic>;
    expect(results.map((result) => (result as Map)['tool_use_id']), [
      'call_1',
      'call_2',
    ]);
    expect((results[0] as Map).containsKey('is_error'), isFalse);
    expect((results[1] as Map)['is_error'], isTrue);
  });

  test('continues through multiple tool-use rounds', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final requests = <MessageCreateRequest>[];
    final responses = <Message>[
      _message([
        {
          'type': 'tool_use',
          'id': 'call_1',
          'name': 'first',
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {
          'type': 'tool_use',
          'id': 'call_2',
          'name': 'second',
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'Done'},
      ]),
    ];

    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolApprover: _approveAll,
      toolLister: _listNamedTools(['first', 'second']),
      toolCaller: (request) async => const mcp_dart.CallToolResult(content: []),
    );
    expect(await client.processQuery('Run the workflow'), contains('Done'));
    expect(requests, hasLength(3));
    final finalMessages = _wireJson(requests.last)['messages'] as List<dynamic>;
    expect(finalMessages.map((message) => (message as Map)['role']), [
      'user',
      'assistant',
      'user',
      'assistant',
      'user',
    ]);
  });

  test('uses every tools/list page and maps collision-safe aliases', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final cursors = <String?>[];
    final requests = <MessageCreateRequest>[];
    final toolRequests = <mcp_dart.CallToolRequest>[];
    final longName = List.filled(70, 'x').join();
    late String dottedAlias;
    final responses = <Message>[];

    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      toolLister: (request) async {
        cursors.add(request?.cursor);
        if (request == null) {
          return mcp_dart.ListToolsResult(
            tools: [
              const mcp_dart.Tool(
                name: 'admin_tools_list',
                description: 'Reserved valid name',
                inputSchema: mcp_dart.JsonObject(),
              ),
              const mcp_dart.Tool(
                name: 'admin.tools.list',
                description: 'Dotted name',
                inputSchema: mcp_dart.JsonObject(
                  additionalProperties: false,
                  extra: {
                    r'$defs': {
                      'identifier': {'type': 'string'},
                    },
                  },
                ),
              ),
            ],
            nextCursor: 'page-2',
          );
        }
        return mcp_dart.ListToolsResult(
          tools: [
            mcp_dart.Tool(
              name: longName,
              description: 'Long name',
              inputSchema: const mcp_dart.JsonObject(),
            ),
          ],
        );
      },
      toolApprover: _approveAll,
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolCaller: (request) async {
        toolRequests.add(request);
        return const mcp_dart.CallToolResult(
          content: [mcp_dart.TextContent(text: 'done')],
        );
      },
    );

    await client.refreshTools();

    expect(cursors, [null, 'page-2']);
    final toolJson = client.tools.map((tool) => tool.toJson()).toList();
    final names = toolJson.map((tool) => tool['name'] as String).toList();
    expect(names, hasLength(3));
    expect(names.toSet(), hasLength(3));
    expect(names[0], 'admin_tools_list');
    dottedAlias = names[1];
    expect(dottedAlias, isNot('admin.tools.list'));
    expect(dottedAlias, isNot('admin_tools_list'));
    expect(names[2], isNot(longName));
    for (final name in names) {
      expect(name, matches(RegExp(r'^[a-zA-Z0-9_-]{1,64}$')));
    }
    final dottedSchema = toolJson[1]['input_schema'] as Map<String, dynamic>;
    expect(dottedSchema['additionalProperties'], isFalse);
    expect(dottedSchema[r'$defs'], {
      'identifier': {'type': 'string'},
    });

    responses.addAll([
      _message([
        {
          'type': 'tool_use',
          'id': 'call_dotted',
          'name': dottedAlias,
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'Done'},
      ]),
    ]);

    await client.processQuery('Use the dotted tool');

    expect(toolRequests.single.name, 'admin.tools.list');
    expect(requests.first.tools?.map((tool) => tool.toJson()['name']), names);
  });

  test('refreshes tools once per query and drops revoked tools', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);
    final requests = <MessageCreateRequest>[];
    var refreshes = 0;
    var toolCalled = false;
    final responses = <Message>[
      _message([
        {'type': 'text', 'text': 'First query'},
      ]),
      _message([
        {
          'type': 'tool_use',
          'id': 'revoked_call',
          'name': 'revoked',
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'Rejected'},
      ]),
    ];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      toolLister: (_) async {
        refreshes++;
        return mcp_dart.ListToolsResult(
          tools:
              refreshes == 1
                  ? [
                    const mcp_dart.Tool(
                      name: 'revoked',
                      inputSchema: mcp_dart.JsonObject(),
                    ),
                  ]
                  : const [],
        );
      },
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolApprover: _approveAll,
      toolCaller: (_) async {
        toolCalled = true;
        return const mcp_dart.CallToolResult(content: []);
      },
    );

    await client.processQuery('First');
    final output = await client.processQuery('Second');

    expect(refreshes, 2);
    expect(requests[0].tools, hasLength(1));
    expect(requests[1].tools, isEmpty);
    expect(requests[2].tools, isEmpty);
    expect(toolCalled, isFalse);
    expect(output, contains('[Rejected unadvertised tool "revoked"]'));
  });

  test('escapes server-controlled tool names in user-visible output', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);
    const unsafeName = 'danger\u001b[2J';
    String? approvedName;
    var messageNumber = 0;
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      toolLister: _listNamedTools([unsafeName]),
      messageGenerator: (request) async {
        if (messageNumber++ == 0) {
          final alias = request.tools!.single.toJson()['name'] as String;
          return _message([
            {
              'type': 'tool_use',
              'id': 'unsafe_name_call',
              'name': alias,
              'input': <String, dynamic>{},
            },
          ]);
        }
        return _message([
          {'type': 'text', 'text': 'Done'},
        ]);
      },
      toolApprover: (name, _) async {
        approvedName = name;
        return true;
      },
      toolCaller: (_) async => const mcp_dart.CallToolResult(content: []),
    );

    final output = await client.processQuery('Run it');

    expect(approvedName, unsafeName);
    expect(output, isNot(contains('\u001b')));
    expect(output, contains(r'\u001b'));
  });

  test('rejects repeated tools/list cursors', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      toolLister:
          (_) async =>
              const mcp_dart.ListToolsResult(tools: [], nextCursor: 'repeated'),
    );

    await expectLater(
      client.refreshTools(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('repeated cursor'),
        ),
      ),
    );
  });

  test('requires a positive tools/list page limit', () {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    expect(
      () => AnthropicMcpClient(
        anthropic,
        mcp_dart.McpClient(
          const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
        ),
        maxToolPages: 0,
      ),
      throwsArgumentError,
    );
  });

  test('stops tools/list pagination after the configured page limit', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);
    var calls = 0;
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      maxToolPages: 2,
      toolLister: (_) async {
        calls++;
        return mcp_dart.ListToolsResult(
          tools: const [],
          nextCursor: 'unique-page-$calls',
        );
      },
    );

    await expectLater(
      client.refreshTools(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('exceeded 2 pages'),
        ),
      ),
    );
    expect(calls, 2);
  });

  test('executes advertised tools after explicit approval', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final approvals = <MapEntry<String, Map<String, Object?>>>[];
    final toolRequests = <mcp_dart.CallToolRequest>[];
    final responses = <Message>[
      _message([
        {
          'type': 'tool_use',
          'id': 'approved_call',
          'name': 'sensitive_action',
          'input': {'target': 'record-1'},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'Approved action completed.'},
      ]),
    ];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (_) async => responses.removeAt(0),
      toolApprover: (name, arguments) async {
        approvals.add(MapEntry(name, arguments));
        return true;
      },
      toolLister: _listNamedTools(['sensitive_action']),
      toolCaller: (request) async {
        toolRequests.add(request);
        return const mcp_dart.CallToolResult(
          content: [mcp_dart.TextContent(text: 'changed')],
        );
      },
    );
    final output = await client.processQuery('Change the record');

    expect(approvals.single.key, 'sensitive_action');
    expect(approvals.single.value, {'target': 'record-1'});
    expect(toolRequests.single.name, 'sensitive_action');
    expect(output, contains('[Calling tool "sensitive_action"'));
  });

  test('returns a correlated error when approval is declined', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final requests = <MessageCreateRequest>[];
    var toolCalled = false;
    final responses = <Message>[
      _message([
        {
          'type': 'tool_use',
          'id': 'declined_call',
          'name': 'sensitive_action',
          'input': {'target': 'record-1'},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'The action was not run.'},
      ]),
    ];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolApprover: (_, _) async => false,
      toolLister: _listNamedTools(['sensitive_action']),
      toolCaller: (_) async {
        toolCalled = true;
        return const mcp_dart.CallToolResult(content: []);
      },
    );
    final output = await client.processQuery('Change the record');

    expect(toolCalled, isFalse);
    expect(output, contains('[Declined tool "sensitive_action"]'));
    final result = _firstToolResult(requests[1]);
    expect(result['tool_use_id'], 'declined_call');
    expect(result['is_error'], isTrue);
    expect(jsonEncode(result), contains('user declined'));
  });

  test('denies advertised tools when no approver is configured', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final requests = <MessageCreateRequest>[];
    var toolCalled = false;
    final responses = <Message>[
      _message([
        {
          'type': 'tool_use',
          'id': 'default_denied_call',
          'name': 'sensitive_action',
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'The action was not run.'},
      ]),
    ];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolLister: _listNamedTools(['sensitive_action']),
      toolCaller: (_) async {
        toolCalled = true;
        return const mcp_dart.CallToolResult(content: []);
      },
    );
    await client.processQuery('Change the record');

    expect(toolCalled, isFalse);
    final result = _firstToolResult(requests[1]);
    expect(result['tool_use_id'], 'default_denied_call');
    expect(result['is_error'], isTrue);
  });

  test(
    'rejects unadvertised tool names when the server has no tools',
    () async {
      final anthropic = AnthropicClient.withApiKey('unused');
      addTearDown(anthropic.close);

      final requests = <MessageCreateRequest>[];
      var approvalRequested = false;
      var toolCalled = false;
      final responses = <Message>[
        _message([
          {
            'type': 'tool_use',
            'id': 'unadvertised_call',
            'name': 'not_advertised',
            'input': <String, dynamic>{},
          },
        ]),
        _message([
          {'type': 'text', 'text': 'The action was not run.'},
        ]),
      ];
      final client = AnthropicMcpClient(
        anthropic,
        mcp_dart.McpClient(
          const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
        ),
        messageGenerator: (request) async {
          requests.add(request);
          return responses.removeAt(0);
        },
        toolApprover: (_, _) async {
          approvalRequested = true;
          return true;
        },
        toolLister: _listTools(const []),
        toolCaller: (_) async {
          toolCalled = true;
          return const mcp_dart.CallToolResult(content: []);
        },
      );
      final output = await client.processQuery('Run an unknown tool');

      expect(approvalRequested, isFalse);
      expect(toolCalled, isFalse);
      expect(output, contains('[Rejected unadvertised tool "not_advertised"]'));
      final result = _firstToolResult(requests[1]);
      expect(result['tool_use_id'], 'unadvertised_call');
      expect(result['is_error'], isTrue);
      expect(jsonEncode(result), contains('unadvertised MCP tool'));
    },
  );

  test('rejects non-object MCP input-schema roots', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      toolLister: _listTools([
        mcp_dart.Tool(
          name: 'string_input',
          inputSchema: mcp_dart.JsonSchema.fromJson({'type': 'string'}),
        ),
      ]),
    );

    await expectLater(
      client.refreshTools(),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          allOf(contains('object-root input schema'), contains('string_input')),
        ),
      ),
    );
    expect(client.tools, isEmpty);
  });

  test('translates typed MCP results without forwarding metadata', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final requests = <MessageCreateRequest>[];
    final responses = <Message>[
      _message([
        {
          'type': 'tool_use',
          'id': 'call_typed',
          'name': 'typed',
          'input': <String, dynamic>{},
        },
      ]),
      _message([
        {'type': 'text', 'text': 'Done'},
      ]),
    ];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (request) async {
        requests.add(request);
        return responses.removeAt(0);
      },
      toolApprover: _approveAll,
      toolLister: _listNamedTools(['typed']),
      toolCaller:
          (_) async => mcp_dart.CallToolResult(
            content: const [
              mcp_dart.TextContent(
                text: 'plain text',
                meta: {'textSecret': 'sentinel-text-meta'},
              ),
              mcp_dart.ImageContent(
                data: 'AQ==',
                mimeType: 'image/png',
                meta: {'imageSecret': 'sentinel-image-meta'},
              ),
            ],
            structuredContentJson: mcp_dart.JsonValue.array([1, 2]),
            meta: const {'resultSecret': 'sentinel-result-meta'},
            extra: const {'vendorSecret': 'sentinel-extra'},
          ),
    );
    await client.processQuery('Return typed content');

    final messages = _wireJson(requests[1])['messages'] as List<dynamic>;
    final resultTurn = messages[2] as Map<String, dynamic>;
    final resultBlock =
        (resultTurn['content'] as List<dynamic>).single as Map<String, dynamic>;
    expect(resultBlock['content'], [
      {'type': 'text', 'text': 'plain text'},
      {
        'type': 'image',
        'source': {'type': 'base64', 'data': 'AQ==', 'media_type': 'image/png'},
      },
      {'type': 'text', 'text': 'Structured content: [1,2]'},
    ]);
    final resultWire = jsonEncode(resultBlock);
    expect(resultWire, isNot(contains('sentinel-')));
    expect(resultWire, isNot(contains('_meta')));
  });

  test(
    'correlates timeout and custom errors and continues remaining tool calls',
    () async {
      final anthropic = AnthropicClient.withApiKey('unused');
      addTearDown(anthropic.close);

      final requests = <MessageCreateRequest>[];
      final calledTools = <String>[];
      final responses = <Message>[
        _message([
          {
            'type': 'tool_use',
            'id': 'call_timeout',
            'name': 'timeout',
            'input': <String, dynamic>{},
          },
          {
            'type': 'tool_use',
            'id': 'call_custom',
            'name': 'custom',
            'input': <String, dynamic>{},
          },
          {
            'type': 'tool_use',
            'id': 'call_good',
            'name': 'good',
            'input': <String, dynamic>{},
          },
        ]),
        _message([
          {'type': 'text', 'text': 'Recovered'},
        ]),
      ];
      final client = AnthropicMcpClient(
        anthropic,
        mcp_dart.McpClient(
          const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
        ),
        messageGenerator: (request) async {
          requests.add(request);
          return responses.removeAt(0);
        },
        toolApprover: _approveAll,
        toolLister: _listNamedTools(['timeout', 'custom', 'good']),
        toolCaller: (request) async {
          calledTools.add(request.name);
          if (request.name == 'timeout') {
            throw mcp_dart.McpError(
              mcp_dart.ErrorCode.requestTimeout.value,
              'Timed out locally',
            );
          }
          if (request.name == 'custom') {
            throw mcp_dart.McpError(-32099, 'Custom server failure');
          }
          return const mcp_dart.CallToolResult(
            content: [mcp_dart.TextContent(text: 'ok')],
          );
        },
      );
      expect(await client.processQuery('Run both'), contains('Recovered'));
      expect(calledTools, ['timeout', 'custom', 'good']);

      final messages = _wireJson(requests[1])['messages'] as List<dynamic>;
      final resultTurn = messages[2] as Map<String, dynamic>;
      final results = resultTurn['content'] as List<dynamic>;
      expect((results[0] as Map)['tool_use_id'], 'call_timeout');
      expect((results[0] as Map)['is_error'], isTrue);
      expect(jsonEncode(results[0]), contains('Timed out locally'));
      expect((results[1] as Map)['tool_use_id'], 'call_custom');
      expect((results[1] as Map)['is_error'], isTrue);
      expect(jsonEncode(results[1]), contains('Custom server failure'));
      expect((results[2] as Map)['tool_use_id'], 'call_good');
      expect((results[2] as Map).containsKey('is_error'), isFalse);
    },
  );

  test('rethrows connection-closed tool errors', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);
    final calledTools = <String>[];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator:
          (_) async => _message([
            {
              'type': 'tool_use',
              'id': 'call_closed',
              'name': 'closed',
              'input': <String, dynamic>{},
            },
            {
              'type': 'tool_use',
              'id': 'call_not_reached',
              'name': 'not_reached',
              'input': <String, dynamic>{},
            },
          ]),
      toolApprover: _approveAll,
      toolLister: _listNamedTools(['closed', 'not_reached']),
      toolCaller: (request) async {
        calledTools.add(request.name);
        throw mcp_dart.McpError(
          mcp_dart.ErrorCode.connectionClosed.value,
          'Connection closed',
        );
      },
    );

    await expectLater(
      client.processQuery('Run both'),
      throwsA(
        isA<mcp_dart.McpError>().having(
          (error) => error.code,
          'code',
          mcp_dart.ErrorCode.connectionClosed.value,
        ),
      ),
    );
    expect(calledTools, ['closed']);
  });

  test('does not execute tool blocks from a truncated response', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    var approvalRequested = false;
    var toolCalled = false;
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator:
          (_) async => _message([
            {
              'type': 'tool_use',
              'id': 'incomplete_call',
              'name': 'dangerous',
              'input': {'partial': true},
            },
          ], stopReason: 'max_tokens'),
      toolApprover: (_, _) async {
        approvalRequested = true;
        return true;
      },
      toolLister: _listNamedTools(['dangerous']),
      toolCaller: (_) async {
        toolCalled = true;
        return const mcp_dart.CallToolResult(content: []);
      },
    );
    await expectLater(
      client.processQuery('Do something'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('max_tokens'),
        ),
      ),
    );
    expect(approvalRequested, isFalse);
    expect(toolCalled, isFalse);
  });

  test(
    'reports refused responses instead of returning empty success',
    () async {
      final anthropic = AnthropicClient.withApiKey('unused');
      addTearDown(anthropic.close);

      final client = AnthropicMcpClient(
        anthropic,
        mcp_dart.McpClient(
          const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
        ),
        messageGenerator:
            (_) async => _message(const [], stopReason: 'refusal'),
        toolLister: _listTools(const []),
      );

      await expectLater(
        client.processQuery('Hello'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('refused'),
          ),
        ),
      );
    },
  );

  test('interactive processing reports failed queries', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    final errors = <String>[];
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      messageGenerator: (_) async => throw StateError('sentinel-query-error'),
      toolLister: _listTools(const []),
    );

    final succeeded = await client.processMessages(
      Stream.fromIterable(['hello', 'quit']),
      onOutput: (_) {},
      onError: errors.add,
    );

    expect(succeeded, isFalse);
    expect(errors.single, contains('sentinel-query-error'));
  });

  test('uses an explicitly configured model', () async {
    final anthropic = AnthropicClient.withApiKey('unused');
    addTearDown(anthropic.close);

    late MessageCreateRequest request;
    final client = AnthropicMcpClient(
      anthropic,
      mcp_dart.McpClient(
        const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
      ),
      model: 'claude-opus-4-6',
      toolLister: _listTools(const []),
      messageGenerator: (value) async {
        request = value;
        return _message([
          {'type': 'text', 'text': 'Done'},
        ]);
      },
    );

    await client.processQuery('Hello');

    expect(request.model, 'claude-opus-4-6');
  });
}

Message _message(List<Map<String, dynamic>> content, {String? stopReason}) {
  final resolvedStopReason =
      stopReason ??
      (content.any((block) => block['type'] == 'tool_use')
          ? 'tool_use'
          : 'end_turn');
  return Message.fromJson({
    'id': 'msg_test',
    'type': 'message',
    'role': 'assistant',
    'content': content,
    'model': defaultAnthropicModel,
    'stop_reason': resolvedStopReason,
    'usage': {'input_tokens': 1, 'output_tokens': 1},
  });
}

Map<String, dynamic> _wireJson(MessageCreateRequest request) {
  return jsonDecode(jsonEncode(request.toJson())) as Map<String, dynamic>;
}

Map<String, dynamic> _firstToolResult(MessageCreateRequest request) {
  final messages = _wireJson(request)['messages'] as List<dynamic>;
  final resultTurn = messages.last as Map<String, dynamic>;
  return (resultTurn['content'] as List<dynamic>).first as Map<String, dynamic>;
}

McpToolLister _listNamedTools(List<String> names) {
  return _listTools([
    for (final name in names)
      mcp_dart.Tool(name: name, inputSchema: const mcp_dart.JsonObject()),
  ]);
}

McpToolLister _listTools(List<mcp_dart.Tool> tools) {
  return (_) async => mcp_dart.ListToolsResult(tools: tools);
}

Future<bool> _approveAll(String name, Map<String, Object?> arguments) async =>
    true;
