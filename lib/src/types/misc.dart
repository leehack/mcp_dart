import 'json_rpc.dart';
import 'validation.dart';

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  final version = readRequiredString(json['jsonrpc'], '$context.jsonrpc');
  if (version != jsonRpcVersion) {
    throw FormatException('$context.jsonrpc must be "$jsonRpcVersion"');
  }

  final method = readRequiredString(json['method'], '$context.method');
  if (method != expected) {
    throw FormatException('$context.method must be "$expected"');
  }
}

void _readOptionalParamsObject(Map<String, dynamic> json, String field) {
  if (!json.containsKey('params')) {
    return;
  }
  readJsonObject(json['params'], field);
}

/// A response that indicates success but carries no specific data.
class EmptyResult implements BaseResultData {
  @override
  final Map<String, dynamic>? meta;

  const EmptyResult({this.meta});

  @override
  Map<String, dynamic> toJson() => {
        if (meta != null) '_meta': readJsonObject(meta, 'EmptyResult._meta'),
      };
}

/// Parameters for the `notifications/cancelled` notification.
class CancelledNotification {
  /// The ID of the request to cancel.
  final RequestId? requestId;

  /// An optional string describing the reason for the cancellation.
  final String? reason;

  const CancelledNotification({this.requestId, this.reason});

  factory CancelledNotification.fromJson(Map<String, dynamic> json) =>
      CancelledNotification(
        requestId: json.containsKey('requestId')
            ? parseRequestId(json['requestId'], fieldName: 'requestId')
            : null,
        reason: readOptionalString(
          json['reason'],
          'CancelledNotification.reason',
        ),
      );

  Map<String, dynamic> toJson() => {
        if (requestId != null)
          'requestId': parseRequestId(requestId, fieldName: 'requestId'),
        if (reason != null) 'reason': reason,
      };
}

/// Notification sent by either side to indicate cancellation of a request.
class JsonRpcCancelledNotification extends JsonRpcNotification {
  /// The parameters detailing which request is cancelled and why.
  final CancelledNotification cancelParams;

  JsonRpcCancelledNotification({required this.cancelParams, super.meta})
      : super(
          method: Method.notificationsCancelled,
          params: cancelParams.toJson(),
        );

  factory JsonRpcCancelledNotification.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.notificationsCancelled,
      'JsonRpcCancelledNotification',
    );
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcCancelledNotification.params',
    );
    if (paramsMap == null) {
      throw const FormatException("Missing params for cancelled notification");
    }
    final meta = readOptionalJsonObject(
      paramsMap['_meta'],
      'JsonRpcCancelledNotification._meta',
    );
    return JsonRpcCancelledNotification(
      cancelParams: CancelledNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// A ping request, sent by either side to check liveness. Expects an empty result.
class JsonRpcPingRequest extends JsonRpcRequest {
  const JsonRpcPingRequest({required super.id, super.meta})
      : super(method: Method.ping);

  factory JsonRpcPingRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(json, Method.ping, 'JsonRpcPingRequest');
    _readOptionalParamsObject(json, 'JsonRpcPingRequest.params');
    return JsonRpcPingRequest(
      id: parseRequestId(json['id']),
      meta: extractRequestMeta(json),
    );
  }
}

/// Represents progress information for a long-running request.
class Progress {
  /// The progress thus far (should increase monotonically).
  final num progress;

  /// Total number of items or total progress required, if known.
  final num? total;

  /// An optional human-readable message about the current progress.
  final String? message;

  const Progress({
    required this.progress,
    this.total,
    this.message,
  });

  factory Progress.fromJson(Map<String, dynamic> json) {
    return Progress(
      progress: readFiniteNumber(json['progress'], 'Progress.progress'),
      total: readOptionalFiniteNumber(json['total'], 'Progress.total'),
      message: readOptionalString(json['message'], 'Progress.message'),
    );
  }

  Map<String, dynamic> toJson() {
    validateFiniteNumber(progress, 'Progress.progress');
    validateOptionalFiniteNumber(total, 'Progress.total');
    return {
      'progress': progress,
      if (total != null) 'total': total,
      if (message != null) 'message': message,
    };
  }
}

/// Parameters for the `notifications/progress` notification.
class ProgressNotification implements Progress {
  /// The token originally provided in the request's `_meta`.
  final ProgressToken progressToken;

  /// The progress thus far.
  @override
  final num progress;

  /// Total progress required, if known.
  @override
  final num? total;

  /// An optional human-readable message about the current progress.
  @override
  final String? message;

  const ProgressNotification({
    required this.progressToken,
    required this.progress,
    this.total,
    this.message,
  });

  factory ProgressNotification.fromJson(Map<String, dynamic> json) {
    final progressData = Progress.fromJson(json);
    return ProgressNotification(
      progressToken: parseProgressToken(json['progressToken']),
      progress: progressData.progress,
      total: progressData.total,
      message: progressData.message,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'progressToken': parseProgressToken(progressToken),
        ...Progress(
          progress: progress,
          total: total,
          message: message,
        ).toJson(),
      };
}

/// Out-of-band notification informing the receiver of progress on a request.
class JsonRpcProgressNotification extends JsonRpcNotification {
  /// The progress parameters.
  final ProgressNotification progressParams;

  /// Creates a progress notification.
  JsonRpcProgressNotification({required this.progressParams, super.meta})
      : super(
          method: Method.notificationsProgress,
          params: progressParams.toJson(),
        );

  /// Creates from JSON.
  factory JsonRpcProgressNotification.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.notificationsProgress,
      'JsonRpcProgressNotification',
    );
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcProgressNotification.params',
    );
    if (paramsMap == null) {
      throw const FormatException("Missing params for progress notification");
    }
    final meta = readOptionalJsonObject(
      paramsMap['_meta'],
      'JsonRpcProgressNotification._meta',
    );
    return JsonRpcProgressNotification(
      progressParams: ProgressNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Deprecated alias for [CancelledNotification].
@Deprecated('Use CancelledNotification instead')
typedef CancelledNotificationParams = CancelledNotification;

/// Deprecated alias for [ProgressNotification].
@Deprecated('Use ProgressNotification instead')
typedef ProgressNotificationParams = ProgressNotification;
