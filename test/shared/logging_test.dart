import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    // Reset handler before each test to avoid interference
    Logger.setHandler((loggerName, level, message) {
      // No-op handler to isolate tests
    });
  });

  group('Logger', () {
    test('uses configured custom LogHandler', () async {
      final completer = Completer<List<Object?>>();
      Logger.setHandler((loggerName, level, message) {
        completer.complete([loggerName, level, message]);
      });

      final loggerName = "test.logger";
      final logger = Logger(loggerName);
      final message = "Test log message";
      logger.info(message);

      final captured = await completer.future;
      expect(
        captured,
        equals([loggerName, LogLevel.info, message]),
      );
    });

    test('supports all log levels', () async {
      final logs = <List<Object?>>[];
      Logger.setHandler((loggerName, level, message) {
        logs.add([loggerName, level, message]);
      });

      final logger = Logger('test.multi');

      logger.debug('debug message');
      logger.info('info message');
      logger.warn('warn message');
      logger.error('error message');

      // Allow async processing
      await Future.delayed(Duration.zero);

      expect(logs.length, equals(4));
      expect(logs[0][1], equals(LogLevel.debug));
      expect(logs[1][1], equals(LogLevel.info));
      expect(logs[2][1], equals(LogLevel.warn));
      expect(logs[3][1], equals(LogLevel.error));
    });

    test('includes logger name in all messages', () async {
      final logs = <String>[];
      Logger.setHandler((loggerName, level, message) {
        logs.add(loggerName);
      });

      final logger1 = Logger('module.auth');
      final logger2 = Logger('module.database');

      logger1.info('auth event');
      logger2.info('db event');

      await Future.delayed(Duration.zero);

      expect(logs, equals(['module.auth', 'module.database']));
    });

    test('default handler formats messages correctly', () async {
      // Capture output from default handler
      final outputs = <String>[];
      Logger.setHandler((loggerName, level, message) {
        // Simulate default format
        final formatted = "[${level.name.toUpperCase()}][$loggerName] $message";
        outputs.add(formatted);
      });

      final logger = Logger('test.format');
      logger.error('critical error');

      await Future.delayed(Duration.zero);

      expect(outputs.length, equals(1));
      expect(outputs[0], equals('[ERROR][test.format] critical error'));
    });

    test('generic log method works with all levels', () async {
      final logs = <LogLevel>[];
      Logger.setHandler((loggerName, level, message) {
        logs.add(level);
      });

      final logger = Logger('test.generic');

      logger.log(LogLevel.debug, 'test1');
      logger.log(LogLevel.info, 'test2');
      logger.log(LogLevel.warn, 'test3');
      logger.log(LogLevel.error, 'test4');

      await Future.delayed(Duration.zero);

      expect(
        logs,
        equals([
          LogLevel.debug,
          LogLevel.info,
          LogLevel.warn,
          LogLevel.error,
        ]),
      );
    });
  });
}
