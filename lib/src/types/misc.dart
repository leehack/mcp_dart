import 'json_rpc.dart';

/// A response that indicates success but carries no specific data.
class EmptyResult implements BaseResultData {
  @override
  final Map<String, dynamic>? meta;

  const EmptyResult({this.meta});

  @override
  Map<String, dynamic> toJson() => {};
}

/// Parameters for the `notifications/cancelled` notification.
class CancelledNotification {
  /// The ID of the request to cancel.
  final RequestId requestId;

  /// An optional string describing the reason for the cancellation.
  final String? reason;

  const CancelledNotification({required this.requestId, this.reason});

  factory CancelledNotification.fromJson(Map<String, dynamic> json) =>
      CancelledNotification(
        requestId: json['requestId'],
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
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
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for cancelled notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcCancelledNotification(
      cancelParams: CancelledNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// A ping request, sent by either side to check liveness. Expects an empty result.
class JsonRpcPingRequest extends JsonRpcRequest {
  const JsonRpcPingRequest({required super.id}) : super(method: Method.ping);

  factory JsonRpcPingRequest.fromJson(Map<String, dynamic> json) =>
      JsonRpcPingRequest(id: json['id']);
}

/// Represents progress information for a long-running request.
class Progress {
  /// The progress thus far (should increase monotonically).
  final num progress;

  /// Total number of items or total progress required, if known.
  final num? total;

  const Progress({
    required this.progress,
    this.total,
  });

  factory Progress.fromJson(Map<String, dynamic> json) {
    return Progress(
      progress: json['progress'] as num,
      total: json['total'] as num?,
    );
  }

  Map<String, dynamic> toJson() => {
        'progress': progress,
        if (total != null) 'total': total,
      };
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

  const ProgressNotification({
    required this.progressToken,
    required this.progress,
    this.total,
  });

  factory ProgressNotification.fromJson(Map<String, dynamic> json) {
    final progressData = Progress.fromJson(json);
    return ProgressNotification(
      progressToken: json['progressToken'],
      progress: progressData.progress,
      total: progressData.total,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'progressToken': progressToken,
        ...Progress(
          progress: progress,
          total: total,
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
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for progress notification");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
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
