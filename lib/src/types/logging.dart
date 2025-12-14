import 'json_rpc.dart';

/// Severity levels for log messages (syslog levels).
enum LoggingLevel {
  debug,
  info,
  notice,
  warning,
  error,
  critical,
  alert,
  emergency,
}

/// Parameters for the `logging/setLevel` request.
class SetLevelRequestParams {
  /// The minimum logging level the client wants to receive.
  final LoggingLevel level;

  const SetLevelRequestParams({required this.level});

  factory SetLevelRequestParams.fromJson(Map<String, dynamic> json) =>
      SetLevelRequestParams(
        level: LoggingLevel.values.byName(json['level'] as String),
      );

  Map<String, dynamic> toJson() => {'level': level.name};
}

/// Request sent from client to enable or adjust logging level from the server.
class JsonRpcSetLevelRequest extends JsonRpcRequest {
  /// The set level parameters.
  final SetLevelRequestParams setParams;

  JsonRpcSetLevelRequest({
    required super.id,
    required this.setParams,
    super.meta,
  }) : super(method: Method.loggingSetLevel, params: setParams.toJson());

  factory JsonRpcSetLevelRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for set level request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcSetLevelRequest(
      id: json['id'],
      setParams: SetLevelRequestParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `notifications/message` (or `logging/message`) notification.
class LoggingMessageNotificationParams {
  /// The severity of this log message.
  final LoggingLevel level;

  /// Optional name of the logger issuing the message.
  final String? logger;

  /// The data to be logged (string, object, etc.).
  final dynamic data;

  const LoggingMessageNotificationParams({
    required this.level,
    this.logger,
    this.data,
  });

  factory LoggingMessageNotificationParams.fromJson(
    Map<String, dynamic> json,
  ) =>
      LoggingMessageNotificationParams(
        level: LoggingLevel.values.byName(json['level'] as String),
        logger: json['logger'] as String?,
        data: json['data'],
      );

  Map<String, dynamic> toJson() => {
        'level': level.name,
        if (logger != null) 'logger': logger,
        'data': data,
      };
}

/// Notification of a log message passed from server to client.
class JsonRpcLoggingMessageNotification extends JsonRpcNotification {
  /// The logging parameters.
  final LoggingMessageNotificationParams logParams;

  JsonRpcLoggingMessageNotification({required this.logParams, super.meta})
      : super(method: Method.notificationsMessage, params: logParams.toJson());

  factory JsonRpcLoggingMessageNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException(
        "Missing params for logging message notification",
      );
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcLoggingMessageNotification(
      logParams: LoggingMessageNotificationParams.fromJson(paramsMap),
      meta: meta,
    );
  }
}
