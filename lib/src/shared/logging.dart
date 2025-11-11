import 'logging_io.dart' if (dart.library.js_interop) 'logging_web.dart';

enum LogLevel { debug, info, warn, error }

typedef LogHandler = void Function(
  String loggerName,
  LogLevel level,
  String message,
);

final class Logger {
  static LogHandler _handler = _defaultLogHandler;
  final String name;

  Logger(this.name);

  static void setHandler(LogHandler handler) {
    _handler = handler;
  }

  static void _defaultLogHandler(
    String loggerName,
    LogLevel level,
    String message,
  ) {
    writeLog("[${level.name.toUpperCase()}][$loggerName] $message");
  }

  void log(LogLevel level, String message) {
    _handler(name, level, message);
  }

  void debug(String message) => log(LogLevel.debug, message);
  void info(String message) => log(LogLevel.info, message);
  void warn(String message) => log(LogLevel.warn, message);
  void error(String message) => log(LogLevel.error, message);
}
