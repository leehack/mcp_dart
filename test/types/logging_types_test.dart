import 'package:mcp_dart/src/types/logging.dart';
import 'package:test/test.dart';

void main() {
  group('LoggingLevel', () {
    test('has all expected values', () {
      expect(LoggingLevel.values, hasLength(8));
      expect(LoggingLevel.debug.name, equals('debug'));
      expect(LoggingLevel.info.name, equals('info'));
      expect(LoggingLevel.notice.name, equals('notice'));
      expect(LoggingLevel.warning.name, equals('warning'));
      expect(LoggingLevel.error.name, equals('error'));
      expect(LoggingLevel.critical.name, equals('critical'));
      expect(LoggingLevel.alert.name, equals('alert'));
      expect(LoggingLevel.emergency.name, equals('emergency'));
    });
  });

  group('SetLevelRequestParams', () {
    test('constructs with level', () {
      const params = SetLevelRequestParams(level: LoggingLevel.debug);
      expect(params.level, equals(LoggingLevel.debug));
    });

    test('fromJson parses correctly', () {
      final json = {'level': 'warning'};
      final params = SetLevelRequestParams.fromJson(json);
      expect(params.level, equals(LoggingLevel.warning));
    });

    test('toJson serializes correctly', () {
      const params = SetLevelRequestParams(level: LoggingLevel.error);
      final json = params.toJson();
      expect(json, equals({'level': 'error'}));
    });

    test('roundtrip serialization works', () {
      const original = SetLevelRequestParams(level: LoggingLevel.critical);
      final json = original.toJson();
      final restored = SetLevelRequestParams.fromJson(json);
      expect(restored.level, equals(original.level));
    });

    test('fromJson handles all logging levels', () {
      for (final level in LoggingLevel.values) {
        final json = {'level': level.name};
        final params = SetLevelRequestParams.fromJson(json);
        expect(params.level, equals(level));
      }
    });
  });

  group('JsonRpcSetLevelRequest', () {
    test('constructs correctly', () {
      final request = JsonRpcSetLevelRequest(
        id: 1,
        setParams: const SetLevelRequestParams(level: LoggingLevel.info),
      );
      expect(request.id, equals(1));
      expect(request.method, equals('logging/setLevel'));
      expect(request.setParams.level, equals(LoggingLevel.info));
    });

    test('fromJson parses correctly', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 42,
        'method': 'logging/setLevel',
        'params': {'level': 'debug'},
      };
      final request = JsonRpcSetLevelRequest.fromJson(json);
      expect(request.id, equals(42));
      expect(request.setParams.level, equals(LoggingLevel.debug));
    });

    test('fromJson with meta', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'logging/setLevel',
        'params': {
          'level': 'info',
          '_meta': {'progressToken': 'abc'},
        },
      };
      final request = JsonRpcSetLevelRequest.fromJson(json);
      expect(request.meta, isNotNull);
      expect(request.meta!['progressToken'], equals('abc'));
    });

    test('fromJson throws on missing params', () {
      final json = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'logging/setLevel',
      };
      expect(
        () => JsonRpcSetLevelRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson serializes correctly', () {
      final request = JsonRpcSetLevelRequest(
        id: 5,
        setParams: const SetLevelRequestParams(level: LoggingLevel.warning),
      );
      final json = request.toJson();
      expect(json['id'], equals(5));
      expect(json['method'], equals('logging/setLevel'));
      expect(json['params']['level'], equals('warning'));
    });
  });

  group('LoggingMessageNotificationParams', () {
    test('constructs with required level', () {
      const params = LoggingMessageNotificationParams(
        level: LoggingLevel.error,
      );
      expect(params.level, equals(LoggingLevel.error));
      expect(params.logger, isNull);
      expect(params.data, isNull);
    });

    test('constructs with all parameters', () {
      const params = LoggingMessageNotificationParams(
        level: LoggingLevel.info,
        logger: 'myapp.module',
        data: 'Log message here',
      );
      expect(params.level, equals(LoggingLevel.info));
      expect(params.logger, equals('myapp.module'));
      expect(params.data, equals('Log message here'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'level': 'warning',
        'logger': 'test.logger',
        'data': {'message': 'structured log'},
      };
      final params = LoggingMessageNotificationParams.fromJson(json);
      expect(params.level, equals(LoggingLevel.warning));
      expect(params.logger, equals('test.logger'));
      expect(params.data, isA<Map>());
    });

    test('fromJson handles missing optional fields', () {
      final json = {'level': 'debug'};
      final params = LoggingMessageNotificationParams.fromJson(json);
      expect(params.level, equals(LoggingLevel.debug));
      expect(params.logger, isNull);
      expect(params.data, isNull);
    });

    test('toJson serializes required fields', () {
      const params = LoggingMessageNotificationParams(
        level: LoggingLevel.alert,
      );
      final json = params.toJson();
      expect(json['level'], equals('alert'));
      expect(json.containsKey('logger'), isFalse);
      expect(json.containsKey('data'), isTrue); // data is always included
    });

    test('toJson serializes all fields', () {
      const params = LoggingMessageNotificationParams(
        level: LoggingLevel.emergency,
        logger: 'critical.system',
        data: 'System failure',
      );
      final json = params.toJson();
      expect(json['level'], equals('emergency'));
      expect(json['logger'], equals('critical.system'));
      expect(json['data'], equals('System failure'));
    });

    test('roundtrip serialization works', () {
      const original = LoggingMessageNotificationParams(
        level: LoggingLevel.notice,
        logger: 'roundtrip.test',
        data: {'key': 'value', 'count': 42},
      );
      final json = original.toJson();
      final restored = LoggingMessageNotificationParams.fromJson(json);
      expect(restored.level, equals(original.level));
      expect(restored.logger, equals(original.logger));
      expect(restored.data, equals(original.data));
    });
  });

  group('JsonRpcLoggingMessageNotification', () {
    test('constructs correctly', () {
      final notification = JsonRpcLoggingMessageNotification(
        logParams: const LoggingMessageNotificationParams(
          level: LoggingLevel.info,
          data: 'Test message',
        ),
      );
      expect(notification.method, equals('notifications/message'));
      expect(notification.logParams.level, equals(LoggingLevel.info));
    });

    test('fromJson parses correctly', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/message',
        'params': {
          'level': 'error',
          'logger': 'test',
          'data': 'Error occurred',
        },
      };
      final notification = JsonRpcLoggingMessageNotification.fromJson(json);
      expect(notification.logParams.level, equals(LoggingLevel.error));
      expect(notification.logParams.logger, equals('test'));
      expect(notification.logParams.data, equals('Error occurred'));
    });

    test('fromJson with meta', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/message',
        'params': {
          'level': 'debug',
          '_meta': {'contextId': 'ctx-123'},
        },
      };
      final notification = JsonRpcLoggingMessageNotification.fromJson(json);
      expect(notification.meta, isNotNull);
      expect(notification.meta!['contextId'], equals('ctx-123'));
    });

    test('fromJson throws on missing params', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'notifications/message',
      };
      expect(
        () => JsonRpcLoggingMessageNotification.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson serializes correctly', () {
      final notification = JsonRpcLoggingMessageNotification(
        logParams: const LoggingMessageNotificationParams(
          level: LoggingLevel.critical,
          logger: 'app.core',
          data: 'Critical failure',
        ),
      );
      final json = notification.toJson();
      expect(json['method'], equals('notifications/message'));
      expect(json['params']['level'], equals('critical'));
      expect(json['params']['logger'], equals('app.core'));
    });
  });
}
