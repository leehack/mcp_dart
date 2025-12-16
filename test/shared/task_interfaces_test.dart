import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/types/json_rpc.dart';
import 'package:test/test.dart';

void main() {
  group('QueuedMessage', () {
    test('constructs with required parameters', () {
      final message = const JsonRpcNotification(
        method: 'test/notify',
        params: {'key': 'value'},
      );
      final queuedMessage = QueuedMessage(
        type: 'notification',
        message: message,
        timestamp: 1234567890,
      );
      expect(queuedMessage.type, equals('notification'));
      expect(queuedMessage.message, equals(message));
      expect(queuedMessage.timestamp, equals(1234567890));
    });

    test('supports different message types', () {
      final request = const JsonRpcRequest(
        id: 1,
        method: 'test/request',
        params: {},
      );
      final requestQueued = QueuedMessage(
        type: 'request',
        message: request,
        timestamp: 100,
      );
      expect(requestQueued.type, equals('request'));

      final response = const JsonRpcResponse(id: 1, result: {'data': 'test'});
      final responseQueued = QueuedMessage(
        type: 'response',
        message: response,
        timestamp: 200,
      );
      expect(responseQueued.type, equals('response'));

      final error = const JsonRpcError(
        id: 1,
        error: JsonRpcErrorData(code: -1, message: 'error'),
      );
      final errorQueued = QueuedMessage(
        type: 'error',
        message: error,
        timestamp: 300,
      );
      expect(errorQueued.type, equals('error'));
    });
  });

  group('RelatedTaskMetadata', () {
    test('constructs with taskId', () {
      const metadata = RelatedTaskMetadata(taskId: 'task-123');
      expect(metadata.taskId, equals('task-123'));
    });

    test('fromJson parses correctly', () {
      final json = {'taskId': 'task-456'};
      final metadata = RelatedTaskMetadata.fromJson(json);
      expect(metadata.taskId, equals('task-456'));
    });

    test('toJson serializes correctly', () {
      const metadata = RelatedTaskMetadata(taskId: 'task-789');
      final json = metadata.toJson();
      expect(json, equals({'taskId': 'task-789'}));
    });

    test('roundtrip serialization works', () {
      const original = RelatedTaskMetadata(taskId: 'task-roundtrip');
      final json = original.toJson();
      final restored = RelatedTaskMetadata.fromJson(json);
      expect(restored.taskId, equals(original.taskId));
    });
  });

  group('AuthInfo', () {
    test('constructs with data map', () {
      const authInfo = AuthInfo({'token': 'abc123', 'user': 'testuser'});
      expect(authInfo.data['token'], equals('abc123'));
      expect(authInfo.data['user'], equals('testuser'));
    });

    test('handles empty data', () {
      const authInfo = AuthInfo({});
      expect(authInfo.data, isEmpty);
    });

    test('handles nested data', () {
      const authInfo = AuthInfo({
        'credentials': {
          'apiKey': 'key123',
          'secret': 'secret456',
        },
        'permissions': ['read', 'write'],
      });
      expect(authInfo.data['credentials'], isA<Map>());
      expect(authInfo.data['permissions'], isA<List>());
    });
  });

  group('RequestInfo', () {
    test('constructs with data map', () {
      const requestInfo = RequestInfo({
        'method': 'tools/call',
        'path': '/api/v1/tools',
      });
      expect(requestInfo.data['method'], equals('tools/call'));
      expect(requestInfo.data['path'], equals('/api/v1/tools'));
    });

    test('handles empty data', () {
      const requestInfo = RequestInfo({});
      expect(requestInfo.data, isEmpty);
    });

    test('handles complex request metadata', () {
      const requestInfo = RequestInfo({
        'headers': {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token',
        },
        'query': {'page': 1, 'limit': 10},
        'timestamp': 1234567890,
      });
      expect(requestInfo.data['headers'], isA<Map>());
      expect(requestInfo.data['query'], isA<Map>());
      expect(requestInfo.data['timestamp'], equals(1234567890));
    });
  });
}
