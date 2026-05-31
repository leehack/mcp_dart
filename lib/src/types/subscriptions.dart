import 'initialization.dart';
import 'json_rpc.dart';

/// Notification filter requested by `subscriptions/listen`.
class SubscriptionFilter {
  /// Subscribe to `notifications/tools/list_changed`.
  final bool? toolsListChanged;

  /// Subscribe to `notifications/prompts/list_changed`.
  final bool? promptsListChanged;

  /// Subscribe to `notifications/resources/list_changed`.
  final bool? resourcesListChanged;

  /// Subscribe to `notifications/resources/updated` for the given URIs.
  final List<String>? resourceSubscriptions;

  const SubscriptionFilter({
    this.toolsListChanged,
    this.promptsListChanged,
    this.resourcesListChanged,
    this.resourceSubscriptions,
  });

  factory SubscriptionFilter.fromJson(Map<String, dynamic> json) {
    return SubscriptionFilter(
      toolsListChanged: _readOptionalBool(
        json['toolsListChanged'],
        'SubscriptionFilter.toolsListChanged',
      ),
      promptsListChanged: _readOptionalBool(
        json['promptsListChanged'],
        'SubscriptionFilter.promptsListChanged',
      ),
      resourcesListChanged: _readOptionalBool(
        json['resourcesListChanged'],
        'SubscriptionFilter.resourcesListChanged',
      ),
      resourceSubscriptions: _readOptionalStringList(
        json['resourceSubscriptions'],
        'SubscriptionFilter.resourceSubscriptions',
      ),
    );
  }

  /// Returns the subset this server can honor from this requested filter.
  SubscriptionFilter acknowledgedBy(ServerCapabilities capabilities) {
    return SubscriptionFilter(
      toolsListChanged:
          toolsListChanged == true && (capabilities.tools?.listChanged ?? false)
              ? true
              : null,
      promptsListChanged: promptsListChanged == true &&
              (capabilities.prompts?.listChanged ?? false)
          ? true
          : null,
      resourcesListChanged: resourcesListChanged == true &&
              (capabilities.resources?.listChanged ?? false)
          ? true
          : null,
      resourceSubscriptions:
          resourceSubscriptions != null && capabilities.resources != null
              ? List<String>.unmodifiable(resourceSubscriptions!)
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (toolsListChanged != null) 'toolsListChanged': toolsListChanged,
        if (promptsListChanged != null)
          'promptsListChanged': promptsListChanged,
        if (resourcesListChanged != null)
          'resourcesListChanged': resourcesListChanged,
        if (resourceSubscriptions != null)
          'resourceSubscriptions': resourceSubscriptions,
      };
}

/// Parameters for a `subscriptions/listen` request.
class SubscriptionsListenRequest {
  /// Notifications the client opts into on this stream.
  final SubscriptionFilter notifications;

  const SubscriptionsListenRequest({required this.notifications});

  factory SubscriptionsListenRequest.fromJson(Map<String, dynamic> json) {
    final notifications = json['notifications'];
    if (notifications is! Map) {
      throw const FormatException(
        'SubscriptionsListenRequest.notifications is required',
      );
    }

    return SubscriptionsListenRequest(
      notifications: SubscriptionFilter.fromJson(
        notifications.cast<String, dynamic>(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'notifications': notifications.toJson(),
      };
}

/// Request sent by a client to open a long-lived notification stream.
class JsonRpcSubscriptionsListenRequest extends JsonRpcRequest {
  /// The listen request parameters.
  final SubscriptionsListenRequest listenParams;

  JsonRpcSubscriptionsListenRequest({
    required super.id,
    required this.listenParams,
    super.meta,
  }) : super(
          method: Method.subscriptionsListen,
          params: listenParams.toJson(),
        );

  factory JsonRpcSubscriptionsListenRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException(
        'Missing params for subscriptions/listen request',
      );
    }

    return JsonRpcSubscriptionsListenRequest(
      id: parseRequestId(json['id']),
      listenParams: SubscriptionsListenRequest.fromJson(paramsMap),
      meta: extractRequestMeta(json),
    );
  }
}

/// Parameters for `notifications/subscriptions/acknowledged`.
class SubscriptionsAcknowledgedNotification {
  /// The subset of the requested filter the server agreed to honor.
  final SubscriptionFilter notifications;

  const SubscriptionsAcknowledgedNotification({required this.notifications});

  factory SubscriptionsAcknowledgedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final notifications = json['notifications'];
    if (notifications is! Map) {
      throw const FormatException(
        'SubscriptionsAcknowledgedNotification.notifications is required',
      );
    }

    return SubscriptionsAcknowledgedNotification(
      notifications: SubscriptionFilter.fromJson(
        notifications.cast<String, dynamic>(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'notifications': notifications.toJson(),
      };
}

/// Notification acknowledging a `subscriptions/listen` stream.
class JsonRpcSubscriptionsAcknowledgedNotification extends JsonRpcNotification {
  /// The acknowledgment parameters.
  final SubscriptionsAcknowledgedNotification acknowledgedParams;

  JsonRpcSubscriptionsAcknowledgedNotification({
    required this.acknowledgedParams,
    super.meta,
  }) : super(
          method: Method.notificationsSubscriptionsAcknowledged,
          params: acknowledgedParams.toJson(),
        );

  factory JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException(
        'Missing params for subscriptions acknowledged notification',
      );
    }

    return JsonRpcSubscriptionsAcknowledgedNotification(
      acknowledgedParams:
          SubscriptionsAcknowledgedNotification.fromJson(paramsMap),
      meta: _readOptionalJsonObject(
        paramsMap['_meta'],
        'SubscriptionsAcknowledgedNotification._meta',
      ),
    );
  }
}

bool? _readOptionalBool(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$field must be a boolean');
}

List<String>? _readOptionalStringList(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw FormatException('$field must be an array');
  }
  if (value.any((item) => item is! String)) {
    throw FormatException('$field must contain only strings');
  }
  return value.cast<String>();
}

Map<String, dynamic>? _readOptionalJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw FormatException('$field must be an object with string keys');
    }
    return value.cast<String, dynamic>();
  }
  throw FormatException('$field must be an object');
}
