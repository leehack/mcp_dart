import 'initialization.dart';
import 'json_rpc.dart';
import 'misc.dart';
import 'validation.dart';

/// Notification filter requested by `subscriptions/listen`.
class SubscriptionFilter {
  /// Subscribe to `notifications/tools/list_changed`.
  final bool? toolsListChanged;

  /// Subscribe to `notifications/prompts/list_changed`.
  final bool? promptsListChanged;

  /// Subscribe to `notifications/resources/list_changed`.
  final bool? resourcesListChanged;

  /// Subscribe to `notifications/resources/updated` for the given URIs and
  /// their sub-resources.
  final List<String>? resourceSubscriptions;

  /// Subscribe to `notifications/tasks` for the given task ids.
  final List<String>? taskIds;

  const SubscriptionFilter({
    this.toolsListChanged,
    this.promptsListChanged,
    this.resourcesListChanged,
    this.resourceSubscriptions,
    this.taskIds,
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
      taskIds: _readOptionalStringList(
        json['taskIds'],
        'SubscriptionFilter.taskIds',
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
      resourceSubscriptions: resourceSubscriptions != null &&
              (capabilities.resources?.subscribe ?? false)
          ? List<String>.unmodifiable(resourceSubscriptions!)
          : null,
      taskIds: taskIds != null && capabilities.supportsTasksExtension
          ? List<String>.unmodifiable(taskIds!)
          : null,
    );
  }

  /// Whether this filter is a subset of [requested].
  bool isSubsetOf(SubscriptionFilter requested) {
    if (toolsListChanged == true && requested.toolsListChanged != true) {
      return false;
    }
    if (promptsListChanged == true && requested.promptsListChanged != true) {
      return false;
    }
    if (resourcesListChanged == true &&
        requested.resourcesListChanged != true) {
      return false;
    }
    if (!_stringListSubsetOf(
      resourceSubscriptions,
      requested.resourceSubscriptions,
    )) {
      return false;
    }
    if (!_stringListSubsetOf(taskIds, requested.taskIds)) {
      return false;
    }
    return true;
  }

  /// Whether this acknowledged filter allows [notification].
  bool allowsNotification(JsonRpcNotification notification) {
    switch (notification.method) {
      case Method.notificationsToolsListChanged:
        return toolsListChanged == true;
      case Method.notificationsPromptsListChanged:
        return promptsListChanged == true;
      case Method.notificationsResourcesListChanged:
        return resourcesListChanged == true;
      case Method.notificationsResourcesUpdated:
        final uri = notification.params?['uri'];
        return uri is String && _allowsResourceUri(uri, resourceSubscriptions);
      case Method.notificationsTasks:
        final taskId = notification.params?['taskId'];
        return taskId is String && (taskIds?.contains(taskId) ?? false);
      default:
        return false;
    }
  }

  Map<String, dynamic> toJson() => {
        if (toolsListChanged != null) 'toolsListChanged': toolsListChanged,
        if (promptsListChanged != null)
          'promptsListChanged': promptsListChanged,
        if (resourcesListChanged != null)
          'resourcesListChanged': resourcesListChanged,
        if (resourceSubscriptions != null)
          'resourceSubscriptions': resourceSubscriptions,
        if (taskIds != null) 'taskIds': taskIds,
      };
}

bool _allowsResourceUri(String uri, List<String>? subscribedUris) {
  if (subscribedUris == null) {
    return false;
  }
  return subscribedUris.any((subscribedUri) {
    if (uri == subscribedUri) {
      return true;
    }
    return _isSubResourceUri(uri, subscribedUri);
  });
}

bool _isSubResourceUri(String uri, String subscribedUri) {
  final updated = Uri.tryParse(uri);
  final subscribed = Uri.tryParse(subscribedUri);
  if (updated == null ||
      subscribed == null ||
      !updated.hasScheme ||
      !subscribed.hasScheme) {
    return false;
  }
  if (updated.scheme != subscribed.scheme ||
      updated.authority != subscribed.authority) {
    return false;
  }
  if (subscribed.query.isNotEmpty || subscribed.fragment.isNotEmpty) {
    return false;
  }

  final subscribedPath = subscribed.path.isEmpty ? '/' : subscribed.path;
  final childPathPrefix =
      subscribedPath.endsWith('/') ? subscribedPath : '$subscribedPath/';
  return updated.path.startsWith(childPathPrefix);
}

/// Parameters for a `subscriptions/listen` request.
class SubscriptionsListenRequest {
  /// Notifications the client opts into on this stream.
  final SubscriptionFilter notifications;

  const SubscriptionsListenRequest({required this.notifications});

  factory SubscriptionsListenRequest.fromJson(Map<String, dynamic> json) {
    final notifications = _readRequiredJsonObject(
      json['notifications'],
      'SubscriptionsListenRequest.notifications',
    );

    return SubscriptionsListenRequest(
      notifications: SubscriptionFilter.fromJson(notifications),
    );
  }

  Map<String, dynamic> toJson() => {
        'notifications': notifications.toJson(),
      };
}

/// The response sent when a `subscriptions/listen` stream ends gracefully.
class SubscriptionsListenResult extends EmptyResult {
  SubscriptionsListenResult({
    required RequestId subscriptionId,
    Map<String, dynamic>? meta,
  }) : super(meta: _subscriptionResultMeta(subscriptionId, meta));

  factory SubscriptionsListenResult.fromJson(Map<String, dynamic> json) {
    final meta = _readRequiredJsonObject(
      json['_meta'],
      'SubscriptionsListenResult._meta',
    );
    final subscriptionId = _readSubscriptionId(
      meta,
      'SubscriptionsListenResult._meta.${McpMetaKey.subscriptionId}',
    );

    return SubscriptionsListenResult(
      subscriptionId: subscriptionId,
      meta: meta,
    );
  }

  /// JSON-RPC request ID for the subscription stream this response closes.
  RequestId get subscriptionId => _readSubscriptionId(
        meta,
        'SubscriptionsListenResult._meta.${McpMetaKey.subscriptionId}',
      );
}

Map<String, dynamic> _subscriptionResultMeta(
  RequestId subscriptionId,
  Map<String, dynamic>? meta,
) {
  final parsedSubscriptionId = parseRequestId(
    subscriptionId,
    fieldName: 'SubscriptionsListenResult.subscriptionId',
  );
  return <String, dynamic>{
    ...?meta,
    McpMetaKey.subscriptionId: parsedSubscriptionId,
  };
}

RequestId _readSubscriptionId(Object? meta, String fieldName) {
  final metaMap =
      _readRequiredJsonObject(meta, 'SubscriptionsListenResult._meta');
  return parseRequestId(
    metaMap[McpMetaKey.subscriptionId],
    fieldName: fieldName,
  );
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
    _expectJsonRpcMethod(
      json,
      Method.subscriptionsListen,
      'JsonRpcSubscriptionsListenRequest',
    );
    final paramsMap = _readRequiredParamsObject(
      json,
      'JsonRpcSubscriptionsListenRequest.params',
    );
    final meta = validateRequestMeta(
      readJsonObject(
        paramsMap['_meta'],
        'JsonRpcSubscriptionsListenRequest.params._meta',
      ),
      validateKeys: true,
    )!;

    return JsonRpcSubscriptionsListenRequest(
      id: parseRequestId(json['id']),
      listenParams: SubscriptionsListenRequest.fromJson(paramsMap),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final meta = this.meta;
    if (meta == null) {
      throw const FormatException(
        'JsonRpcSubscriptionsListenRequest.params._meta is required',
      );
    }
    return {
      'jsonrpc': jsonrpc,
      'id': parseRequestId(
        id,
        fieldName: 'JsonRpcSubscriptionsListenRequest.id',
      ),
      'method': method,
      'params': <String, dynamic>{
        ...listenParams.toJson(),
        '_meta': readJsonObject(
          validateRequestMeta(meta, validateKeys: true),
          'JsonRpcSubscriptionsListenRequest.params._meta',
        ),
      },
    };
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
    final notifications = _readRequiredJsonObject(
      json['notifications'],
      'SubscriptionsAcknowledgedNotification.notifications',
    );

    return SubscriptionsAcknowledgedNotification(
      notifications: SubscriptionFilter.fromJson(notifications),
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
    _expectJsonRpcMethod(
      json,
      Method.notificationsSubscriptionsAcknowledged,
      'JsonRpcSubscriptionsAcknowledgedNotification',
    );
    final paramsMap = _readRequiredParamsObject(
      json,
      'JsonRpcSubscriptionsAcknowledgedNotification.params',
    );

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

Map<String, dynamic> _readRequiredJsonObject(Object? value, String field) {
  return readJsonObject(value, field);
}

Map<String, dynamic> _readRequiredParamsObject(
  Map<String, dynamic> json,
  String field,
) {
  if (!json.containsKey('params')) {
    throw FormatException('$field is required');
  }
  return _readRequiredJsonObject(json['params'], field);
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

bool _stringListSubsetOf(List<String>? subset, List<String>? superset) {
  if (subset == null || subset.isEmpty) {
    return true;
  }
  final allowed = superset?.toSet();
  if (allowed == null) {
    return false;
  }
  return subset.every(allowed.contains);
}

Map<String, dynamic>? _readOptionalJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return readJsonObject(value, field);
}

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  expectJsonRpcMethod(json, expected, context);
}
