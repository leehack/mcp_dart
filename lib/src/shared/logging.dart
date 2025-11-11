import 'dart:io';

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
    stderr.writeln("[${level.name.toUpperCase()}][$loggerName] $message");
  }

  void log(LogLevel level, String message) {
    _handler(name, level, message);
  }

  void debug(String message) => log(LogLevel.debug, message);
  void info(String message) => log(LogLevel.info, message);
  void warn(String message) => log(LogLevel.warn, message);
  void error(String message) => log(LogLevel.error, message);
}
