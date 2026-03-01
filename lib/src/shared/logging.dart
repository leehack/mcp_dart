import 'logging_io.dart' if (dart.library.js_interop) 'logging_web.dart';

enum LogLevel { debug, info, warn, error }

typedef LogHandler = void Function(
  String loggerName,
  LogLevel level,
  String message,
);

/// Sets the log handler used by MCP SDK runtime logging.
///
/// This affects internal SDK diagnostics (transport/protocol/client/server logs),
/// not protocol `notifications/message` logs sent between MCP peers.
void setMcpLogHandler(LogHandler handler) {
  Logger.setHandler(handler);
}

/// Restores MCP SDK runtime logging to the default handler.
///
/// The default handler writes to `stderr` on VM and `print` on web.
void resetMcpLogHandler() {
  Logger.resetHandler();
}

/// Silences all MCP SDK runtime logs.
void silenceMcpLogs() {
  Logger.setHandler(_noopLogHandler);
}

void _noopLogHandler(String loggerName, LogLevel level, String message) {}

final class Logger {
  static LogHandler _handler = _defaultLogHandler;
  final String name;

  Logger(this.name);

  /// Sets the global handler used by all [Logger] instances.
  static void setHandler(LogHandler handler) {
    _handler = handler;
  }

  /// Restores the default global log handler.
  static void resetHandler() {
    _handler = _defaultLogHandler;
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
