import '../types.dart';

/// Additional properties describing a Resource to clients.
class ResourceAnnotations {
  /// A human-readable title for the resource.
  final String? title;

  /// The intended audience for the resource (e.g., `["user", "assistant"]`).
  final List<String>? audience;

  /// The priority of the resource (0.0 to 1.0).
  final double? priority;

  /// ISO 8601 timestamp when the resource was last modified.
  final String? lastModified;

  const ResourceAnnotations({
    this.title,
    this.audience,
    this.priority,
    this.lastModified,
  });

  factory ResourceAnnotations.fromJson(Map<String, dynamic> json) {
    return ResourceAnnotations(
      title: json['title'] as String?,
      audience: (json['audience'] as List<dynamic>?)?.cast<String>(),
      priority: (json['priority'] as num?)?.toDouble(),
      lastModified: json['lastModified'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (audience != null) 'audience': audience,
        if (priority != null) 'priority': priority,
        if (lastModified != null) 'lastModified': lastModified,
      };
}

/// A known resource offered by the server.
class Resource {
  /// The URI identifying this resource.
  final String uri;

  /// A human-readable name for the resource.
  final String name;

  /// A description of what the resource represents.
  final String? description;

  /// The MIME type, if known.
  final String? mimeType;

  /// Optional icon for the resource.
  final ImageContent? icon;

  /// Optional set of icons for the resource.
  final List<McpIcon>? icons;

  /// Optional additional properties describing the resource.
  final ResourceAnnotations? annotations;

  const Resource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
    this.icon,
    this.icons,
    this.annotations,
  });

  /// Creates from JSON.
  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      uri: json['uri'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      icon: json['icon'] != null
          ? ImageContent.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      icons: (json['icons'] as List<dynamic>?)
          ?.map((e) => McpIcon.fromJson(e as Map<String, dynamic>))
          .toList(),
      annotations: json['annotations'] != null
          ? ResourceAnnotations.fromJson(
              json['annotations'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (icon != null) 'icon': icon!.toJson(),
        if (icons != null)
          'icons': icons!.map((icon) => icon.toJson()).toList(),
        if (annotations != null) 'annotations': annotations!.toJson(),
      };
}

/// A template description for resources available on the server.
class ResourceTemplate {
  /// A URI template (RFC 6570) to construct resource URIs.
  final String uriTemplate;

  /// A human-readable name for the type of resource this template refers to.
  final String name;

  /// A description of what this template is for.
  final String? description;

  /// The MIME type for all resources matching this template, if consistent.
  final String? mimeType;

  /// Optional icon for the resource template.
  final ImageContent? icon;

  /// Optional set of icons for the resource template.
  final List<McpIcon>? icons;

  /// Optional additional properties describing the resource template.
  final ResourceAnnotations? annotations;

  /// Creates a resource template description.
  const ResourceTemplate({
    required this.uriTemplate,
    required this.name,
    this.description,
    this.mimeType,
    this.icon,
    this.icons,
    this.annotations,
  });

  /// Creates from JSON.
  factory ResourceTemplate.fromJson(Map<String, dynamic> json) {
    return ResourceTemplate(
      uriTemplate: json['uriTemplate'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      icon: json['icon'] != null
          ? ImageContent.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      icons: (json['icons'] as List<dynamic>?)
          ?.map((e) => McpIcon.fromJson(e as Map<String, dynamic>))
          .toList(),
      annotations: json['annotations'] != null
          ? ResourceAnnotations.fromJson(
              json['annotations'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'uriTemplate': uriTemplate,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (icon != null) 'icon': icon!.toJson(),
        if (icons != null)
          'icons': icons!.map((icon) => icon.toJson()).toList(),
        if (annotations != null) 'annotations': annotations!.toJson(),
      };
}

/// Parameters for the `resources/list` request. Includes pagination.
class ListResourcesRequest {
  /// Opaque token for pagination, requesting results after this cursor.
  final Cursor? cursor;

  /// Creates list resources parameters.
  const ListResourcesRequest({this.cursor});

  /// Creates from JSON.
  factory ListResourcesRequest.fromJson(Map<String, dynamic> json) =>
      ListResourcesRequest(cursor: json['cursor'] as String?);

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available resources.
class JsonRpcListResourcesRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListResourcesRequest listParams;

  /// Creates a list resources request.
  JsonRpcListResourcesRequest({
    required super.id,
    ListResourcesRequest? params,
    super.meta,
  })  : listParams = params ?? const ListResourcesRequest(),
        super(method: Method.resourcesList, params: params?.toJson());

  /// Creates from JSON.
  factory JsonRpcListResourcesRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListResourcesRequest(
      id: json['id'],
      params:
          paramsMap == null ? null : ListResourcesRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/list` request.
class ListResourcesResult implements BaseResultData {
  /// The list of resources found.
  final List<Resource> resources;

  /// Opaque token for pagination, indicating more results might be available.
  final Cursor? nextCursor;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  /// Creates a list resources result.
  const ListResourcesResult({
    required this.resources,
    this.nextCursor,
    this.meta,
  });

  /// Creates from JSON.
  factory ListResourcesResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListResourcesResult(
      resources: (json['resources'] as List<dynamic>?)
              ?.map((e) => Resource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  /// Converts to JSON (excluding meta).
  @override
  Map<String, dynamic> toJson() => {
        'resources': resources.map((r) => r.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for the `resources/templates/list` request. Includes pagination.
class ListResourceTemplatesRequest {
  /// Opaque token for pagination.
  final Cursor? cursor;

  const ListResourceTemplatesRequest({this.cursor});

  factory ListResourceTemplatesRequest.fromJson(
    Map<String, dynamic> json,
  ) =>
      ListResourceTemplatesRequest(cursor: json['cursor'] as String?);

  Map<String, dynamic> toJson() => {if (cursor != null) 'cursor': cursor};
}

/// Request sent from client to list available resource templates.
class JsonRpcListResourceTemplatesRequest extends JsonRpcRequest {
  /// The list parameters (containing cursor).
  final ListResourceTemplatesRequest listParams;

  JsonRpcListResourceTemplatesRequest({
    required super.id,
    ListResourceTemplatesRequest? params,
    super.meta,
  })  : listParams = params ?? const ListResourceTemplatesRequest(),
        super(method: Method.resourcesTemplatesList, params: params?.toJson());

  factory JsonRpcListResourceTemplatesRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    final meta = paramsMap?['_meta'] as Map<String, dynamic>?;
    return JsonRpcListResourceTemplatesRequest(
      id: json['id'],
      params: paramsMap == null
          ? null
          : ListResourceTemplatesRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/templates/list` request.
class ListResourceTemplatesResult implements BaseResultData {
  /// The list of resource templates found.
  final List<ResourceTemplate> resourceTemplates;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  @override
  final Map<String, dynamic>? meta;

  const ListResourceTemplatesResult({
    required this.resourceTemplates,
    this.nextCursor,
    this.meta,
  });

  factory ListResourceTemplatesResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListResourceTemplatesResult(
      resourceTemplates: (json['resourceTemplates'] as List<dynamic>?)
              ?.map((e) => ResourceTemplate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'resourceTemplates': resourceTemplates.map((t) => t.toJson()).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// Parameters for the `resources/read` request.
class ReadResourceRequest {
  /// The URI of the resource to read.
  final String uri;

  const ReadResourceRequest({required this.uri});

  factory ReadResourceRequest.fromJson(Map<String, dynamic> json) =>
      ReadResourceRequest(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Request sent from client to read a specific resource.
class JsonRpcReadResourceRequest extends JsonRpcRequest {
  /// The read parameters (containing URI).
  final ReadResourceRequest readParams;

  JsonRpcReadResourceRequest({
    required super.id,
    required this.readParams,
    super.meta,
  }) : super(method: Method.resourcesRead, params: readParams.toJson());

  factory JsonRpcReadResourceRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for read resource request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcReadResourceRequest(
      id: json['id'],
      readParams: ReadResourceRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/read` request.
class ReadResourceResult implements BaseResultData {
  /// The contents of the resource (can be multiple parts).
  final List<ResourceContents> contents;

  @override
  final Map<String, dynamic>? meta;

  const ReadResourceResult({required this.contents, this.meta});

  factory ReadResourceResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ReadResourceResult(
      contents: (json['contents'] as List<dynamic>?)
              ?.map((e) => ResourceContents.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'contents': contents.map((c) => c.toJson()).toList(),
      };
}

/// Notification from server indicating the list of available resources has changed.
class JsonRpcResourceListChangedNotification extends JsonRpcNotification {
  const JsonRpcResourceListChangedNotification()
      : super(method: Method.notificationsResourcesListChanged);

  factory JsonRpcResourceListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcResourceListChangedNotification();
}

/// Parameters for the `resources/subscribe` request.
class SubscribeRequest {
  /// The URI of the resource to subscribe to for updates.
  final String uri;

  const SubscribeRequest({required this.uri});

  factory SubscribeRequest.fromJson(Map<String, dynamic> json) =>
      SubscribeRequest(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Request sent from client to subscribe to updates for a resource.
class JsonRpcSubscribeRequest extends JsonRpcRequest {
  /// The subscribe parameters (containing URI).
  final SubscribeRequest subParams;

  JsonRpcSubscribeRequest({
    required super.id,
    required this.subParams,
    super.meta,
  }) : super(method: Method.resourcesSubscribe, params: subParams.toJson());

  factory JsonRpcSubscribeRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for subscribe request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcSubscribeRequest(
      id: json['id'],
      subParams: SubscribeRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `resources/unsubscribe` request.
class UnsubscribeRequest {
  /// The URI of the resource to unsubscribe from.
  final String uri;

  const UnsubscribeRequest({required this.uri});

  factory UnsubscribeRequest.fromJson(Map<String, dynamic> json) =>
      UnsubscribeRequest(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Request sent from client to cancel a resource subscription.
class JsonRpcUnsubscribeRequest extends JsonRpcRequest {
  /// The unsubscribe parameters (containing URI).
  final UnsubscribeRequest unsubParams;

  JsonRpcUnsubscribeRequest({
    required super.id,
    required this.unsubParams,
    super.meta,
  }) : super(method: Method.resourcesUnsubscribe, params: unsubParams.toJson());

  factory JsonRpcUnsubscribeRequest.fromJson(Map<String, dynamic> json) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for unsubscribe request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcUnsubscribeRequest(
      id: json['id'],
      unsubParams: UnsubscribeRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Parameters for the `notifications/resources/updated` notification.
class ResourceUpdatedNotification {
  /// The URI of the resource that has been updated (possibly a sub-resource).
  final String uri;

  const ResourceUpdatedNotification({required this.uri});

  factory ResourceUpdatedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      ResourceUpdatedNotification(uri: json['uri'] as String);

  Map<String, dynamic> toJson() => {'uri': uri};
}

/// Notification from server indicating a subscribed resource has changed.
class JsonRpcResourceUpdatedNotification extends JsonRpcNotification {
  /// The updated parameters (containing URI).
  final ResourceUpdatedNotification updatedParams;

  JsonRpcResourceUpdatedNotification({required this.updatedParams, super.meta})
      : super(
          method: Method.notificationsResourcesUpdated,
          params: updatedParams.toJson(),
        );

  factory JsonRpcResourceUpdatedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException(
        "Missing params for resource updated notification",
      );
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcResourceUpdatedNotification(
      updatedParams: ResourceUpdatedNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Deprecated alias for [ListResourcesRequest].
@Deprecated('Use ListResourcesRequest instead')
typedef ListResourcesRequestParams = ListResourcesRequest;

/// Deprecated alias for [ListResourceTemplatesRequest].
@Deprecated('Use ListResourceTemplatesRequest instead')
typedef ListResourceTemplatesRequestParams = ListResourceTemplatesRequest;

/// Deprecated alias for [ReadResourceRequest].
@Deprecated('Use ReadResourceRequest instead')
typedef ReadResourceRequestParams = ReadResourceRequest;

/// Deprecated alias for [SubscribeRequest].
@Deprecated('Use SubscribeRequest instead')
typedef SubscribeRequestParams = SubscribeRequest;

/// Deprecated alias for [UnsubscribeRequest].
@Deprecated('Use UnsubscribeRequest instead')
typedef UnsubscribeRequestParams = UnsubscribeRequest;

/// Deprecated alias for [ResourceUpdatedNotification].
@Deprecated('Use ResourceUpdatedNotification instead')
typedef ResourceUpdatedNotificationParams = ResourceUpdatedNotification;
