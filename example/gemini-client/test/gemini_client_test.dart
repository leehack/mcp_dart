import 'dart:async';
import 'dart:convert';

import 'package:gemini_client/gemini_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;
import 'package:test/test.dart';

void main() {
  group('Gemini Interactions REST client', () {
    test(
      'sends the API key and correlates parallel calls by ID and name',
      () async {
        final requests = <http.Request>[];
        final responses = <Map<String, Object?>>[
          _interaction(
            id: 'interaction-1',
            status: 'requires_action',
            steps: [
              _modelOutput('I will run both.'),
              {
                'type': 'function_call',
                'id': 'call-first',
                'name': 'first',
                'arguments': {'value': 1},
              },
              {
                'type': 'function_call',
                'id': 'call-second',
                'name': 'second',
                'arguments': {'value': 2},
              },
            ],
          ),
          _interaction(
            id: 'interaction-2',
            status: 'completed',
            steps: [_modelOutput('Both completed.')],
          ),
        ];
        final api = _fakeApi(responses, requests: requests);
        addTearDown(api.close);

        final startedCalls = <mcp_dart.CallToolRequest>[];
        final bothStarted = Completer<void>();
        final client = GoogleMcpClient(
          api,
          _mcpClient(),
          toolApprover: _approveAll,
          toolLister: _singlePageTools([
            _tool(
              'first',
              description: 'First tool',
              inputSchema: mcp_dart.JsonSchema.object(
                properties: {'value': mcp_dart.JsonSchema.integer()},
              ),
            ),
            _tool(
              'second',
              description: 'Second tool',
              inputSchema: mcp_dart.JsonSchema.object(
                properties: {'value': mcp_dart.JsonSchema.integer()},
              ),
            ),
          ]),
          toolCaller: (request) async {
            startedCalls.add(request);
            if (startedCalls.length == 2) {
              bothStarted.complete();
            }
            await bothStarted.future;
            return mcp_dart.CallToolResult(
              content: [mcp_dart.TextContent(text: request.name)],
              isError: request.name == 'second',
            );
          },
        );

        final output = await client
            .processQuery('Run both')
            .timeout(const Duration(seconds: 2));

        expect(
          output,
          'I will run both.\n'
          '[Calling tool "first" with args {"value":1}]\n'
          '[Calling tool "second" with args {"value":2}]\n'
          'Both completed.',
        );
        expect(startedCalls.map((request) => request.name), [
          'first',
          'second',
        ]);
        expect(startedCalls[0].arguments, {'value': 1});
        expect(startedCalls[1].arguments, {'value': 2});
        expect(requests, hasLength(2));
        expect(
          requests.first.url,
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/interactions',
          ),
        );
        expect(requests.first.headers['x-goog-api-key'], 'test-api-key');
        expect(requests.first.headers['content-type'], 'application/json');

        final initial = _requestBody(requests.first);
        expect(initial['model'], 'gemini-test');
        expect(initial['input'], 'Run both');
        expect(initial['store'], isTrue);
        expect(initial['tools'], client.tools);
        expect(initial, isNot(contains('previous_interaction_id')));

        final followUp = _requestBody(requests[1]);
        expect(followUp['model'], 'gemini-test');
        expect(followUp['previous_interaction_id'], 'interaction-1');
        expect(followUp['tools'], client.tools);
        final results = followUp['input'] as List<Object?>;
        expect(results, hasLength(2));
        expect(results[0], {
          'type': 'function_result',
          'name': 'first',
          'call_id': 'call-first',
          'result': [
            {'type': 'text', 'text': 'first'},
          ],
        });
        expect(results[1], {
          'type': 'function_result',
          'name': 'second',
          'call_id': 'call-second',
          'result': [
            {'type': 'text', 'text': 'second'},
          ],
          'is_error': true,
        });
      },
    );

    test('chains sequential tool rounds through each interaction ID', () async {
      final requests = <http.Request>[];
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'first',
              'arguments': <String, Object?>{},
            },
          ],
        ),
        _interaction(
          id: 'interaction-2',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-2',
              'name': 'second',
              'arguments': <String, Object?>{},
            },
          ],
        ),
        _interaction(
          id: 'interaction-3',
          status: 'completed',
          steps: [_modelOutput('Done')],
        ),
      ], requests: requests);
      addTearDown(api.close);
      final calls = <String>[];
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolApprover: _approveAll,
        toolLister: _singlePageTools([_tool('first'), _tool('second')]),
        toolCaller: (request) async {
          calls.add(request.name);
          return const mcp_dart.CallToolResult(content: []);
        },
      );

      expect(await client.processQuery('Run the workflow'), contains('Done'));

      expect(calls, ['first', 'second']);
      expect(requests, hasLength(3));
      expect(
        _requestBody(requests[1])['previous_interaction_id'],
        'interaction-1',
      );
      expect(
        _requestBody(requests[2])['previous_interaction_id'],
        'interaction-2',
      );
      expect(
        ((_requestBody(requests[1])['input'] as List).single as Map)['call_id'],
        'call-1',
      );
      expect(
        ((_requestBody(requests[2])['input'] as List).single as Map)['call_id'],
        'call-2',
      );
      expect(
        requests.every(
          (request) =>
              _requestBody(request)['tools'].toString() ==
              client.tools.toString(),
        ),
        isTrue,
      );
    });

    test(
      'refreshes once per query and rejects a tool revoked between queries',
      () async {
        final requests = <http.Request>[];
        final api = _fakeApi([
          _interaction(
            id: 'interaction-1',
            status: 'requires_action',
            steps: [
              {
                'type': 'function_call',
                'id': 'call-1',
                'name': 'old_tool',
                'arguments': <String, Object?>{},
              },
            ],
          ),
          _interaction(
            id: 'interaction-2',
            status: 'requires_action',
            steps: [
              {
                'type': 'function_call',
                'id': 'call-2',
                'name': 'old_tool',
                'arguments': <String, Object?>{},
              },
            ],
          ),
          _interaction(
            id: 'interaction-3',
            status: 'completed',
            steps: [_modelOutput('First query done.')],
          ),
          _interaction(
            id: 'interaction-4',
            status: 'requires_action',
            steps: [
              {
                'type': 'function_call',
                'id': 'call-revoked',
                'name': 'old_tool',
                'arguments': <String, Object?>{},
              },
            ],
          ),
        ], requests: requests);
        addTearDown(api.close);
        var refreshCount = 0;
        final invoked = <String>[];
        final client = GoogleMcpClient(
          api,
          _mcpClient(),
          toolApprover: _approveAll,
          toolLister: (request) async {
            expect(request, isNull);
            refreshCount++;
            return mcp_dart.ListToolsResult(
              tools: [_tool(refreshCount == 1 ? 'old_tool' : 'new_tool')],
            );
          },
          toolCaller: (request) async {
            invoked.add(request.name);
            return const mcp_dart.CallToolResult(content: []);
          },
        );

        expect(await client.processQuery('First'), contains('First query'));
        await expectLater(
          client.processQuery('Second'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('unadvertised MCP tool "old_tool"'),
            ),
          ),
        );

        expect(refreshCount, 2);
        expect(invoked, ['old_tool', 'old_tool']);
        expect(requests, hasLength(4));
        expect(
          requests
              .take(3)
              .map(
                (request) =>
                    ((_requestBody(request)['tools'] as List).single
                        as Map)['name'],
              ),
          everyElement('old_tool'),
        );
        expect(
          ((_requestBody(requests.last)['tools'] as List).single
              as Map)['name'],
          'new_tool',
        );
      },
    );

    test('JSON-escapes server-controlled tool names in output', () async {
      const rawName = 'danger\u001b[31m\nnext\ttool';
      final encodedName = jsonEncode(rawName);
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'danger_31m_next_tool',
              'arguments': <String, Object?>{},
            },
          ],
        ),
        _interaction(
          id: 'interaction-2',
          status: 'completed',
          steps: [_modelOutput('Declined safely.')],
        ),
      ]);
      addTearDown(api.close);
      String? approvalName;
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: _singlePageTools([_tool(rawName)]),
        toolApprover: (name, _) async {
          approvalName = name;
          return false;
        },
      );

      final output = await client.processQuery('Run it');

      expect(approvalName, rawName);
      expect(output, contains('[Declined tool $encodedName]'));
      expect(output, isNot(contains('\u001b')));
      expect(output, isNot(contains(rawName)));
    });

    test('denies tool calls when no approval callback is configured', () async {
      final requests = <http.Request>[];
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'sensitive_action',
              'arguments': {'target': 'record-1'},
            },
          ],
        ),
        _interaction(
          id: 'interaction-2',
          status: 'completed',
          steps: [_modelOutput('The action was not run.')],
        ),
      ], requests: requests);
      addTearDown(api.close);
      var invoked = false;
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: _singlePageTools([_tool('sensitive_action')]),
        toolCaller: (_) async {
          invoked = true;
          return const mcp_dart.CallToolResult(content: []);
        },
      );

      final output = await client.processQuery('Change the record');

      expect(invoked, isFalse);
      expect(output, contains('[Declined tool "sensitive_action"]'));
      final result =
          ((_requestBody(requests[1])['input'] as List).single as Map)
              .cast<String, Object?>();
      expect(result['call_id'], 'call-1');
      expect(result['is_error'], isTrue);
      expect(
        ((result['result'] as List).single as Map)['text'],
        'The user declined this MCP tool call.',
      );
    });

    test(
      'rejects unadvertised function names before approval or MCP',
      () async {
        final api = _fakeApi([
          _interaction(
            id: 'interaction-1',
            status: 'requires_action',
            steps: [
              {
                'type': 'function_call',
                'id': 'call-1',
                'name': 'not_advertised',
                'arguments': <String, Object?>{},
              },
            ],
          ),
        ]);
        addTearDown(api.close);
        var approvalRequested = false;
        var invoked = false;
        final client = GoogleMcpClient(
          api,
          _mcpClient(),
          toolLister: _singlePageTools([_tool('advertised')]),
          toolApprover: (_, _) async {
            approvalRequested = true;
            return true;
          },
          toolCaller: (_) async {
            invoked = true;
            return const mcp_dart.CallToolResult(content: []);
          },
        );

        await expectLater(
          client.processQuery('Run it'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('unadvertised MCP tool "not_advertised"'),
            ),
          ),
        );
        expect(approvalRequested, isFalse);
        expect(invoked, isFalse);
      },
    );

    test('rejects Gemini function names outside the provider rules', () async {
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'invalid/name',
              'arguments': <String, Object?>{},
            },
          ],
        ),
      ]);
      addTearDown(api.close);
      var approvalRequested = false;
      var invoked = false;
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: _singlePageTools([_tool('advertised')]),
        toolApprover: (_, _) async {
          approvalRequested = true;
          return true;
        },
        toolCaller: (_) async {
          invoked = true;
          return const mcp_dart.CallToolResult(content: []);
        },
      );

      await expectLater(
        client.processQuery('Run it'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('invalid function name "invalid/name"'),
          ),
        ),
      );
      expect(approvalRequested, isFalse);
      expect(invoked, isFalse);
    });

    test(
      'correlates request-timeout and custom MCP errors in a parallel batch',
      () async {
        final requests = <http.Request>[];
        final api = _fakeApi([
          _interaction(
            id: 'interaction-1',
            status: 'requires_action',
            steps: [
              {
                'type': 'function_call',
                'id': 'call-good',
                'name': 'good',
                'arguments': <String, Object?>{},
              },
              {
                'type': 'function_call',
                'id': 'call-timeout',
                'name': 'timeout',
                'arguments': {'value': -1},
              },
              {
                'type': 'function_call',
                'id': 'call-custom',
                'name': 'custom',
                'arguments': <String, Object?>{},
              },
            ],
          ),
          _interaction(
            id: 'interaction-2',
            status: 'completed',
            steps: [_modelOutput('Handled both results.')],
          ),
        ], requests: requests);
        addTearDown(api.close);
        final client = GoogleMcpClient(
          api,
          _mcpClient(),
          toolApprover: _approveAll,
          toolLister: _singlePageTools([
            _tool('good'),
            _tool('timeout'),
            _tool('custom'),
          ]),
          toolCaller: (request) async {
            if (request.name == 'timeout') {
              throw mcp_dart.McpError(
                mcp_dart.ErrorCode.requestTimeout.value,
                'the tool timed out',
                {'private': 'do-not-send'},
              );
            }
            if (request.name == 'custom') {
              throw mcp_dart.McpError(-32099, 'custom server error');
            }
            return const mcp_dart.CallToolResult(
              content: [mcp_dart.TextContent(text: 'ok')],
            );
          },
        );

        expect(
          await client.processQuery('Run both'),
          contains('Handled both results.'),
        );

        final results = _requestBody(requests[1])['input'] as List<Object?>;
        expect(results[0], {
          'type': 'function_result',
          'name': 'good',
          'call_id': 'call-good',
          'result': [
            {'type': 'text', 'text': 'ok'},
          ],
        });
        expect(results[1], {
          'type': 'function_result',
          'name': 'timeout',
          'call_id': 'call-timeout',
          'result': [
            {
              'type': 'text',
              'text': 'MCP tool error -32001: the tool timed out',
            },
          ],
          'is_error': true,
        });
        expect(results[2], {
          'type': 'function_result',
          'name': 'custom',
          'call_id': 'call-custom',
          'result': [
            {
              'type': 'text',
              'text': 'MCP tool error -32099: custom server error',
            },
          ],
          'is_error': true,
        });
        expect(jsonEncode(results), isNot(contains('do-not-send')));
      },
    );

    test('propagates connection-closed MCP errors', () async {
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'remote',
              'arguments': <String, Object?>{},
            },
          ],
        ),
      ]);
      addTearDown(api.close);
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolApprover: _approveAll,
        toolLister: _singlePageTools([_tool('remote')]),
        toolCaller: (_) async {
          throw mcp_dart.McpError(
            mcp_dart.ErrorCode.connectionClosed.value,
            'connection closed',
          );
        },
      );

      await expectLater(
        client.processQuery('Run it'),
        throwsA(
          isA<mcp_dart.McpError>().having(
            (error) => error.code,
            'code',
            mcp_dart.ErrorCode.connectionClosed.value,
          ),
        ),
      );
    });

    test('forwards text and image payloads without MCP metadata', () async {
      final requests = <http.Request>[];
      final imageData = base64Encode(const [1, 2, 3, 4]);
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'inspect_image',
              'arguments': <String, Object?>{},
            },
          ],
        ),
        _interaction(
          id: 'interaction-2',
          status: 'completed',
          steps: [_modelOutput('Done')],
        ),
      ], requests: requests);
      addTearDown(api.close);
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolApprover: _approveAll,
        toolLister: _singlePageTools([_tool('inspect_image')]),
        toolCaller:
            (_) async => mcp_dart.CallToolResult(
              content: [
                const mcp_dart.TextContent(
                  text: 'visible text',
                  meta: {'privateTextMetadata': 'do-not-send'},
                ),
                const mcp_dart.TextContent(
                  text: 'user-only text',
                  annotations: mcp_dart.Annotations(
                    audience: [mcp_dart.AnnotationAudience.user],
                  ),
                ),
                mcp_dart.ImageContent(
                  data: imageData,
                  mimeType: 'image/png',
                  meta: const {'privateImageMetadata': 'do-not-send'},
                ),
              ],
              meta: const {'privateResultMetadata': 'do-not-send'},
              extra: const {'privateExtension': 'do-not-send'},
            ),
      );

      await client.processQuery('Inspect it');

      final functionResult =
          ((_requestBody(requests[1])['input'] as List).single as Map)
              .cast<String, Object?>();
      expect(functionResult['result'], [
        {'type': 'text', 'text': 'visible text'},
        {'type': 'image', 'mime_type': 'image/png', 'data': imageData},
      ]);
      final encoded = jsonEncode(functionResult);
      expect(encoded, isNot(contains('private')));
      expect(encoded, isNot(contains('user-only')));
      expect(encoded, isNot(contains('annotations')));
      expect(encoded, isNot(contains('_meta')));
    });

    test('forwards object structured content as a native result', () async {
      final requests = <http.Request>[];
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'id': 'call-1',
              'name': 'structured',
              'arguments': <String, Object?>{},
            },
          ],
        ),
        _interaction(
          id: 'interaction-2',
          status: 'completed',
          steps: [_modelOutput('Done')],
        ),
      ], requests: requests);
      addTearDown(api.close);
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolApprover: _approveAll,
        toolLister: _singlePageTools([_tool('structured')]),
        toolCaller:
            (_) async =>
                mcp_dart.CallToolResult.fromStructuredContent({'answer': 42}),
      );

      await client.processQuery('Get structured data');

      final functionResult =
          ((_requestBody(requests[1])['input'] as List).single as Map)
              .cast<String, Object?>();
      expect(functionResult['result'], {'answer': 42});
    });

    test('loads every paginated MCP tools/list page', () async {
      final api = _fakeApi(const []);
      addTearDown(api.close);
      final requestedCursors = <String?>[];
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: (request) async {
          requestedCursors.add(request?.cursor);
          return switch (request?.cursor) {
            null => mcp_dart.ListToolsResult(
              tools: [
                mcp_dart.Tool(
                  name: 'first',
                  inputSchema: mcp_dart.JsonSchema.object(),
                ),
              ],
              nextCursor: 'page-2',
            ),
            'page-2' => mcp_dart.ListToolsResult(
              tools: [
                mcp_dart.Tool(
                  name: 'second',
                  inputSchema: mcp_dart.JsonSchema.object(
                    properties: {'value': mcp_dart.JsonSchema.string()},
                  ),
                ),
              ],
            ),
            final cursor => throw StateError('Unexpected cursor $cursor'),
          };
        },
      );

      await client.refreshTools();

      expect(requestedCursors, [null, 'page-2']);
      expect(client.tools.map((tool) => tool['name']), ['first', 'second']);
      expect(client.tools.first, isNot(contains('parameters')));
      expect(client.tools.last['parameters'], {
        'type': 'object',
        'properties': {
          'value': {'type': 'string'},
        },
      });
    });

    test('bounds MCP tools/list pagination', () async {
      final api = _fakeApi(const []);
      addTearDown(api.close);
      final requestedCursors = <String?>[];
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        maxToolPages: 2,
        toolLister: (request) async {
          requestedCursors.add(request?.cursor);
          final page = requestedCursors.length;
          return mcp_dart.ListToolsResult(
            tools: const [],
            nextCursor: 'page-${page + 1}',
          );
        },
      );

      await expectLater(
        client.refreshTools(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'MCP tools/list exceeded 2 pages',
          ),
        ),
      );
      expect(requestedCursors, [null, 'page-2']);
    });

    test('rejects a repeated MCP tools/list cursor', () async {
      final api = _fakeApi(const []);
      addTearDown(api.close);
      final requestedCursors = <String?>[];
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: (request) async {
          requestedCursors.add(request?.cursor);
          return const mcp_dart.ListToolsResult(
            tools: [],
            nextCursor: 'same-cursor',
          );
        },
      );

      await expectLater(
        client.refreshTools(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('repeated cursor "same-cursor"'),
          ),
        ),
      );
      expect(requestedCursors, [null, 'same-cursor']);
    });

    test('requires positive tool pagination and call-round limits', () {
      final api = _fakeApi(const []);
      addTearDown(api.close);

      expect(
        () => GoogleMcpClient(api, _mcpClient(), maxToolPages: 0),
        throwsArgumentError,
      );
      expect(
        () => GoogleMcpClient(api, _mcpClient(), maxToolRounds: 0),
        throwsArgumentError,
      );
    });

    test(
      'aliases incompatible MCP names without collisions and maps them back',
      () async {
        final safeLongName = List.filled(128, 'a').join();
        final longMcpName = '$safeLongName.tail';
        final longAlias = '${safeLongName.substring(0, 126)}_2';
        final requests = <http.Request>[];
        final api = _fakeApi([
          _interaction(
            id: 'interaction-1',
            status: 'requires_action',
            steps: [
              {
                'type': 'function_call',
                'id': 'call-dot',
                'name': 'weather_current_2',
                'arguments': <String, Object?>{},
              },
              {
                'type': 'function_call',
                'id': 'call-slash',
                'name': 'weather_current_3',
                'arguments': <String, Object?>{},
              },
              {
                'type': 'function_call',
                'id': 'call-long',
                'name': longAlias,
                'arguments': <String, Object?>{},
              },
            ],
          ),
          _interaction(
            id: 'interaction-2',
            status: 'completed',
            steps: [_modelOutput('Done')],
          ),
        ], requests: requests);
        addTearDown(api.close);
        final approvedNames = <String>[];
        final invokedNames = <String>[];
        final discovered = [
          'weather/current',
          longMcpName,
          safeLongName,
          'weather.current',
          'weather_current',
        ];
        final client = GoogleMcpClient(
          api,
          _mcpClient(),
          toolApprover: (name, _) async {
            approvedNames.add(name);
            return true;
          },
          toolCaller: (request) async {
            invokedNames.add(request.name);
            return mcp_dart.CallToolResult(
              content: [mcp_dart.TextContent(text: request.name)],
            );
          },
          toolLister:
              (_) async => mcp_dart.ListToolsResult(
                tools: [
                  for (final name in discovered)
                    mcp_dart.Tool(
                      name: name,
                      inputSchema: mcp_dart.JsonSchema.object(),
                    ),
                ],
              ),
        );

        await client.processQuery('Run aliases');

        expect(client.tools.map((tool) => tool['name']), [
          'weather_current_3',
          longAlias,
          safeLongName,
          'weather_current_2',
          'weather_current',
        ]);
        expect(
          client.tools.every(
            (tool) =>
                (tool['name']! as String).length <= 128 &&
                RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(tool['name']! as String),
          ),
          isTrue,
        );

        expect(approvedNames, [
          'weather.current',
          'weather/current',
          longMcpName,
        ]);
        expect(invokedNames, approvedNames);
        final results = _requestBody(requests[1])['input'] as List<Object?>;
        expect(results.map((result) => (result as Map)['name']), [
          'weather_current_2',
          'weather_current_3',
          longAlias,
        ]);
        expect(results.map((result) => (result as Map)['call_id']), [
          'call-dot',
          'call-slash',
          'call-long',
        ]);
      },
    );

    test('chat loop propagates query failures to the CLI', () async {
      final api = GeminiInteractionsApi(
        apiKey: 'unused',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'status': 'UNAVAILABLE', 'message': 'Try again later'},
            }),
            503,
          ),
        ),
      );
      addTearDown(api.close);
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: _singlePageTools(const []),
      );
      final output = <String>[];
      var readCount = 0;

      await expectLater(
        client.chatLoop(
          readLine: () async => readCount++ == 0 ? 'Hello' : null,
          writeLine: output.add,
        ),
        throwsA(
          isA<GeminiApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
      expect(output, contains('\nMCP Client Started!'));
      expect(output, isNot(anyElement(contains('Error processing query'))));
    });

    test(
      'reports structured HTTP errors without exposing the API key',
      () async {
        final api = GeminiInteractionsApi(
          apiKey: 'secret-api-key',
          model: 'gemini-test',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {
                  'code': 429,
                  'status': 'RESOURCE_EXHAUSTED',
                  'message': 'Quota exceeded',
                },
              }),
              429,
            ),
          ),
        );
        addTearDown(api.close);

        await expectLater(
          api.createInteraction(input: 'Hello', tools: const []),
          throwsA(
            isA<GeminiApiException>()
                .having((error) => error.statusCode, 'statusCode', 429)
                .having(
                  (error) => error.toString(),
                  'message',
                  allOf(
                    contains('RESOURCE_EXHAUSTED: Quota exceeded'),
                    isNot(contains('secret-api-key')),
                  ),
                ),
          ),
        );
      },
    );

    test('rejects a non-object success response', () async {
      final api = GeminiInteractionsApi(
        apiKey: 'unused',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      addTearDown(api.close);

      await expectLater(
        api.createInteraction(input: 'Hello', tools: const []),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Gemini interaction response must be an object',
          ),
        ),
      );
    });

    test('uses the current default model and closes the HTTP client', () async {
      final requests = <http.Request>[];
      final httpClient = _TrackingClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              _interaction(
                id: 'interaction-1',
                status: 'completed',
                steps: [_modelOutput('Hello')],
              ),
            ),
            200,
          );
        }),
      );
      final api = GeminiInteractionsApi(
        apiKey: 'unused',
        httpClient: httpClient,
      );

      await api.createInteraction(input: 'Hello', tools: const []);
      api.close();
      api.close();

      expect(_requestBody(requests.single)['model'], 'gemini-3.5-flash');
      expect(httpClient.closed, isTrue);
    });

    test('rejects malformed function calls before invoking MCP', () async {
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'requires_action',
          steps: [
            {
              'type': 'function_call',
              'name': 'missing-id',
              'arguments': <String, Object?>{},
            },
          ],
        ),
      ]);
      addTearDown(api.close);
      var invoked = false;
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: _singlePageTools(const []),
        toolCaller: (_) async {
          invoked = true;
          return const mcp_dart.CallToolResult(content: []);
        },
      );

      await expectLater(
        client.processQuery('Hello'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Gemini function call "id" must be a non-empty string',
          ),
        ),
      );
      expect(invoked, isFalse);
    });

    test('rejects model-output errors', () async {
      final api = _fakeApi([
        _interaction(
          id: 'interaction-1',
          status: 'completed',
          steps: [
            {
              'type': 'model_output',
              'error': {'code': 13, 'message': 'generation failed'},
            },
          ],
        ),
      ]);
      addTearDown(api.close);
      final client = GoogleMcpClient(
        api,
        _mcpClient(),
        toolLister: _singlePageTools(const []),
      );

      await expectLater(
        client.processQuery('Hello'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Gemini model output failed'),
          ),
        ),
      );
    });
  });

  group('Gemini schema translation', () {
    test('returns raw JSON and preserves required, integer, and boolean', () {
      final schema = GeminiSchemaAdapter.fromJson({
        'type': 'object',
        'description': 'Options',
        'properties': {
          'count': {
            'type': 'integer',
            'format': 'int32',
            'description': 'Number of items',
          },
          'enabled': {'type': 'boolean'},
        },
        'required': ['count'],
      });

      expect(schema, {
        'description': 'Options',
        'type': 'object',
        'properties': {
          'count': {
            'description': 'Number of items',
            'type': 'integer',
            'format': 'int32',
          },
          'enabled': {'type': 'boolean'},
        },
        'required': ['count'],
      });
    });

    test('preserves arrays, string enums, and annotations', () {
      expect(
        GeminiSchemaAdapter.fromJson({
          'type': 'object',
          'properties': {
            'tags': {
              r'$id': 'urn:example:tags',
              'title': 'Tags',
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['one', 'two'],
              },
            },
          },
        }),
        {
          'type': 'object',
          'properties': {
            'tags': {
              r'$id': 'urn:example:tags',
              'title': 'Tags',
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['one', 'two'],
              },
            },
          },
        },
      );
    });

    test('omits parameters for an empty object schema', () {
      expect(
        GeminiSchemaAdapter.fromJson({'type': 'object', 'properties': {}}),
        isNull,
      );
      expect(GeminiSchemaAdapter.fromJson({'type': 'object'}), isNull);
    });

    test('rejects JSON Schema boolean property schemas', () {
      expect(
        () => GeminiSchemaAdapter.fromJson({
          'type': 'object',
          'properties': {'anything': true},
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains(r'$.properties.anything'),
          ),
        ),
      );
    });

    test('rejects union types and combinators', () {
      expect(
        () => GeminiSchemaAdapter.fromJson({
          'type': ['string', 'null'],
        }),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => GeminiSchemaAdapter.fromJson({
          'type': 'string',
          'oneOf': [
            {'const': 'a'},
            {'const': 'b'},
          ],
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('oneOf'),
          ),
        ),
      );
    });

    test('rejects validation constraints Gemini cannot represent', () {
      expect(
        () => GeminiSchemaAdapter.fromJson({
          'type': 'object',
          'properties': {
            'value': {'type': 'string', 'minLength': 1},
          },
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('minLength'),
          ),
        ),
      );
    });

    test('rejects primitive and array tool input schema roots', () {
      for (final schema in [
        <String, Object?>{'type': 'string'},
        <String, Object?>{
          'type': 'array',
          'items': {'type': 'string'},
        },
      ]) {
        expect(
          () => GeminiSchemaAdapter.fromJson(schema),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('must have an object root'),
            ),
          ),
        );
      }
    });

    test('rejects required names missing from properties', () {
      expect(
        () => GeminiSchemaAdapter.fromJson({
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['missing'],
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('unknown properties missing'),
          ),
        ),
      );
    });
  });
}

GeminiInteractionsApi _fakeApi(
  List<Map<String, Object?>> responses, {
  List<http.Request>? requests,
}) {
  var index = 0;
  return GeminiInteractionsApi(
    apiKey: 'test-api-key',
    model: 'gemini-test',
    httpClient: MockClient((request) async {
      requests?.add(request);
      if (index >= responses.length) {
        return http.Response('No fake response remaining', 500);
      }
      return http.Response(jsonEncode(responses[index++]), 200);
    }),
  );
}

mcp_dart.McpClient _mcpClient() => mcp_dart.McpClient(
  const mcp_dart.Implementation(name: 'test', version: '1.0.0'),
);

McpToolLister _singlePageTools(List<mcp_dart.Tool> tools) =>
    (_) async => mcp_dart.ListToolsResult(tools: tools);

mcp_dart.Tool _tool(
  String name, {
  String? description,
  mcp_dart.JsonSchema? inputSchema,
}) => mcp_dart.Tool(
  name: name,
  description: description,
  inputSchema: inputSchema ?? mcp_dart.JsonSchema.object(),
);

Future<bool> _approveAll(String name, Map<String, Object?> arguments) async =>
    true;

Map<String, Object?> _interaction({
  required String id,
  required String status,
  required List<Map<String, Object?>> steps,
}) => {'id': id, 'status': status, 'steps': steps};

Map<String, Object?> _modelOutput(String text) => {
  'type': 'model_output',
  'content': [
    {'type': 'text', 'text': text},
  ],
};

Map<String, Object?> _requestBody(http.Request request) =>
    (jsonDecode(request.body) as Map).cast<String, Object?>();

final class _TrackingClient extends http.BaseClient {
  final http.Client inner;
  bool closed = false;

  _TrackingClient(this.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() {
    closed = true;
    inner.close();
  }
}
