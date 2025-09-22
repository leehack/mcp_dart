import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('it uses the configured LogHandler', () async {
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
}
