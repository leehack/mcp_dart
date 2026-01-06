import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Phase 3: Edge cases and error handling for types.dart
void main() {
  group('ErrorCode Edge Cases', () {
    test('ErrorCode.fromValue returns null for unknown code', () {
      expect(ErrorCode.fromValue(99999), isNull);
      expect(ErrorCode.fromValue(0), isNull);
      expect(ErrorCode.fromValue(-1), isNull);
    });

    test('ErrorCode.fromValue finds all standard codes', () {
      expect(ErrorCode.fromValue(-32000), equals(ErrorCode.connectionClosed));
      expect(ErrorCode.fromValue(-32001), equals(ErrorCode.requestTimeout));
      expect(ErrorCode.fromValue(-32700), equals(ErrorCode.parseError));
      expect(ErrorCode.fromValue(-32600), equals(ErrorCode.invalidRequest));
      expect(ErrorCode.fromValue(-32601), equals(ErrorCode.methodNotFound));
      expect(ErrorCode.fromValue(-32602), equals(ErrorCode.invalidParams));
      expect(ErrorCode.fromValue(-32603), equals(ErrorCode.internalError));
    });
  });

  group('JsonRpcErrorData Edge Cases', () {
    test('JsonRpcErrorData with null data field', () {
      final errorData = const JsonRpcErrorData(
        code: -32600,
        message: 'Test error',
        data: null,
      );

      final json = errorData.toJson();
      expect(json['code'], equals(-32600));
      expect(json['message'], equals('Test error'));
      expect(json.containsKey('data'), isFalse);
    });

    test('JsonRpcErrorData with complex nested data', () {
      final errorData = const JsonRpcErrorData(
        code: -32600,
        message: 'Complex error',
        data: {
          'nested': {'level': 2},
          'array': [1, 2, 3],
        },
      );

      final json = errorData.toJson();
      expect(json['data']['nested']['level'], equals(2));
      expect(json['data']['array'], equals([1, 2, 3]));

      final restored = JsonRpcErrorData.fromJson(json);
      expect(restored.data['nested']['level'], equals(2));
    });
  });

  group('JsonRpcCancelledNotification Edge Cases', () {
    test('throws FormatException when params is missing', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/cancelled',
        // Missing 'params'
      };

      expect(
        () => JsonRpcCancelledNotification.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Missing params'),
          ),
        ),
      );
    });

    test('handles optional reason field correctly', () {
      // With reason
      final withReason = const CancelledNotificationParams(
        requestId: 123,
        reason: 'User cancelled',
      );
      var json = withReason.toJson();
      expect(json['reason'], equals('User cancelled'));

      // Without reason
      final withoutReason = const CancelledNotificationParams(requestId: 456);
      json = withoutReason.toJson();
      expect(json.containsKey('reason'), isFalse);
    });

    test('handles meta field in cancelled notification', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/cancelled',
        'params': {
          'requestId': 789,
          '_meta': {'timestamp': 12345},
        },
      };

      final notification = JsonRpcCancelledNotification.fromJson(json);
      expect(notification.meta, equals({'timestamp': 12345}));
      expect(notification.cancelParams.requestId, equals(789));
    });
  });

  group('JsonRpcInitializeRequest Edge Cases', () {
    test('throws FormatException when params is missing', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        // Missing 'params'
      };

      expect(
        () => JsonRpcInitializeRequest.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Missing params'),
          ),
        ),
      );
    });

    test('handles meta field in initialize request', () {
      final json = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, dynamic>{
          'protocolVersion': latestProtocolVersion,
          'capabilities': <String, dynamic>{},
          'clientInfo': <String, dynamic>{'name': 'test', 'version': '1.0'},
          '_meta': <String, dynamic>{'sessionId': 'abc123'},
        },
      };

      final request = JsonRpcInitializeRequest.fromJson(json);
      expect(request.meta, equals({'sessionId': 'abc123'}));
    });
  });

  group('JsonRpcProgressNotification Edge Cases', () {
    test('throws FormatException when params is missing', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        // Missing 'params'
      };

      expect(
        () => JsonRpcProgressNotification.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Missing params'),
          ),
        ),
      );
    });

    test('handles progress with optional total field', () {
      // With total
      final withTotal = const Progress(progress: 50, total: 100);
      var json = withTotal.toJson();
      expect(json['progress'], equals(50));
      expect(json['total'], equals(100));

      // Without total
      final withoutTotal = const Progress(progress: 50);
      json = withoutTotal.toJson();
      expect(json['progress'], equals(50));
      expect(json.containsKey('total'), isFalse);
    });

    test('handles meta field in progress notification', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        'params': {
          'progressToken': 'token123',
          'progress': 75,
          '_meta': {'source': 'background-task'},
        },
      };

      final notification = JsonRpcProgressNotification.fromJson(json);
      expect(notification.meta, equals({'source': 'background-task'}));
      expect(notification.progressParams.progress, equals(75));
    });
  });

  group('JsonRpcMessage.fromJson Additional Edge Cases', () {
    test('returns generic JsonRpcNotification for unknown notification method',
        () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/unknown',
        // No 'id' makes it a notification
      };

      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcNotification>());
      expect((message as JsonRpcNotification).method,
          equals('notifications/unknown'));
    });

    test('handles response with null id', () {
      final json = {
        'jsonrpc': '2.0',
        'id': null,
        'result': {'data': 'test'},
      };

      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcResponse>());
      expect((message as JsonRpcResponse).id, isNull);
    });

    test('handles error with null id', () {
      final json = {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32600, 'message': 'Error'},
      };

      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcError>());
      expect((message as JsonRpcError).id, isNull);
    });

    test('handles response with nested _meta in result', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'data': 'value',
          '_meta': {
            'nested': {'key': 'value'},
          },
        },
      };

      final message = JsonRpcMessage.fromJson(json);
      expect(message, isA<JsonRpcResponse>());
      final response = message as JsonRpcResponse;
      expect(response.result['data'], equals('value'));
      expect(response.meta!['nested']['key'], equals('value'));
    });
  });

  group('ClientCapabilities Edge Cases', () {
    test('handles all null optional fields', () {
      final caps = const ClientCapabilities();

      final json = caps.toJson();
      expect(json.isEmpty, isTrue);

      final restored = ClientCapabilities.fromJson(json);
      expect(restored.experimental, isNull);
      expect(restored.sampling, isNull);
      expect(restored.roots, isNull);
      expect(restored.elicitation, isNull);
    });

    test('handles null roots and elicitation maps', () {
      final json = {
        'experimental': {'feature': true},
        'sampling': {'enabled': true},
        'roots': null,
        'elicitation': null,
      };

      final caps = ClientCapabilities.fromJson(json);
      expect(caps.experimental, isNotNull);
      expect(caps.sampling, isNotNull);
      expect(caps.roots, isNull);
      expect(caps.elicitation, isNull);
    });
  });

  group('ServerCapabilities Edge Cases', () {
    test('handles all null optional fields', () {
      final caps = const ServerCapabilities();

      final json = caps.toJson();
      expect(json.isEmpty, isTrue);

      final restored = ServerCapabilities.fromJson(json);
      expect(restored.experimental, isNull);
      expect(restored.logging, isNull);
      expect(restored.prompts, isNull);
      expect(restored.resources, isNull);
      expect(restored.tools, isNull);
      expect(restored.completions, isNull);
    });

    test('handles null capability maps', () {
      final json = {
        'experimental': {'feature': true},
        'logging': {'level': 'info'},
        'prompts': null,
        'resources': null,
        'tools': null,
        'completions': null,
      };

      final caps = ServerCapabilities.fromJson(json);
      expect(caps.experimental, isNotNull);
      expect(caps.logging, isNotNull);
      expect(caps.prompts, isNull);
      expect(caps.resources, isNull);
      expect(caps.tools, isNull);
      expect(caps.completions, isNull);
    });
  });

  group('InitializeResult Edge Cases', () {
    test('handles optional instructions field', () {
      // With instructions
      final withInstructions = const InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test', version: '1.0'),
        instructions: 'How to use this server',
      );
      var json = withInstructions.toJson();
      expect(json['instructions'], equals('How to use this server'));

      // Without instructions
      final withoutInstructions = const InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test', version: '1.0'),
      );
      json = withoutInstructions.toJson();
      expect(json.containsKey('instructions'), isFalse);
    });

    test('extracts _meta from result JSON', () {
      final json = <String, dynamic>{
        'protocolVersion': latestProtocolVersion,
        'capabilities': <String, dynamic>{},
        'serverInfo': <String, dynamic>{'name': 'test', 'version': '1.0'},
        '_meta': <String, dynamic>{'sessionId': 'xyz'},
      };

      final result = InitializeResult.fromJson(json);
      expect(result.meta, equals({'sessionId': 'xyz'}));
    });
  });

  group('EmptyResult Edge Cases', () {
    test('handles null meta field', () {
      final result = const EmptyResult();
      expect(result.meta, isNull);
      expect(result.toJson(), isEmpty);
    });

    test('includes meta when present', () {
      final result = const EmptyResult(meta: {'key': 'value'});
      expect(result.meta, equals({'key': 'value'}));
    });
  });

  group('ClientCapabilitiesRoots Edge Cases', () {
    test('handles null listChanged field', () {
      final roots = const ClientCapabilitiesRoots();
      final json = roots.toJson();
      expect(json.isEmpty, isTrue);

      final restored = ClientCapabilitiesRoots.fromJson({});
      expect(restored.listChanged, isNull);
    });

    test('includes listChanged when explicitly false', () {
      final roots = const ClientCapabilitiesRoots(listChanged: false);
      final json = roots.toJson();
      expect(json['listChanged'], isFalse);
    });
  });

  group('ServerCapabilities Subtype Edge Cases', () {
    test('ServerCapabilitiesPrompts handles null listChanged', () {
      final prompts = const ServerCapabilitiesPrompts();
      expect(prompts.toJson().isEmpty, isTrue);
    });

    test('ServerCapabilitiesResources handles null fields', () {
      final resources = const ServerCapabilitiesResources();
      expect(resources.toJson().isEmpty, isTrue);

      // Only subscribe set
      final onlySubscribe = const ServerCapabilitiesResources(subscribe: true);
      final json = onlySubscribe.toJson();
      expect(json['subscribe'], isTrue);
      expect(json.containsKey('listChanged'), isFalse);
    });

    test('ServerCapabilitiesTools handles null listChanged', () {
      final tools = const ServerCapabilitiesTools();
      expect(tools.toJson().isEmpty, isTrue);
    });

    test('ServerCapabilitiesCompletions handles null listChanged', () {
      final completions = const ServerCapabilitiesCompletions();
      expect(completions.toJson().isEmpty, isTrue);
    });
  });
}
