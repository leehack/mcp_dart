import '../types.dart';
import 'json_rpc.dart';
import 'validation.dart';

/// Additional properties describing a Resource to clients.
class ResourceAnnotations {
  /// A human-readable title for the resource.
  @Deprecated(
    'MCP 2025-11-25 uses Resource.title at top level; annotations.title is parsed only for legacy compatibility.',
  )
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
  }) : assert(
          priority == null || (priority >= 0 && priority <= 1),
          'priority must be between 0 and 1',
        );

  factory ResourceAnnotations.fromJson(Map<String, dynamic> json) {
    return ResourceAnnotations(
      title: json['title'] as String?,
      audience: (json['audience'] as List<dynamic>?)?.cast<String>(),
      priority:
          readUnitDouble(json['priority'], 'ResourceAnnotations.priority'),
      lastModified: json['lastModified'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    validateUnitDouble(priority, 'ResourceAnnotations.priority');
    return {
      if (audience != null) 'audience': audience,
      if (priority != null) 'priority': priority,
      if (lastModified != null) 'lastModified': lastModified,
    };
  }
}

/// A known resource offered by the server.
class Resource {
  /// The URI identifying this resource.
  final String uri;

  /// A human-readable name for the resource.
  final String name;

  /// A human-readable title for the resource.
  final String? title;

  /// A description of what the resource represents.
  final String? description;

  /// The MIME type, if known.
  final String? mimeType;

  /// Optional icon for the resource.
  @Deprecated(
    'MCP 2025-11-25 uses icons; singular icon is parsed only for legacy compatibility and is not serialized.',
  )
  final ImageContent? icon;

  /// Optional set of icons for the resource.
  final List<McpIcon>? icons;

  /// Raw resource size in bytes, if known.
  final int? size;

  /// Optional additional properties describing the resource.
  final ResourceAnnotations? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const Resource({
    required this.uri,
    required this.name,
    this.title,
    this.description,
    this.mimeType,
    this.icon,
    this.icons,
    this.size,
    this.annotations,
    this.meta,
  });

  /// Creates from JSON.
  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      uri: json['uri'] as String,
      name: json['name'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      icon: json['icon'] != null
          ? ImageContent.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      icons: (json['icons'] as List<dynamic>?)
          ?.map((e) => McpIcon.fromJson(e as Map<String, dynamic>))
          .toList(),
      size: readOptionalInteger(json['size'], 'Resource.size'),
      annotations: json['annotations'] != null
          ? ResourceAnnotations.fromJson(
              json['annotations'] as Map<String, dynamic>,
            )
          : null,
      meta: readOptionalJsonObject(json['_meta'], 'Resource._meta'),
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (icons != null)
          'icons': icons!.map((icon) => icon.toJson()).toList(),
        if (size != null) 'size': size,
        if (annotations != null) 'annotations': annotations!.toJson(),
        if (meta != null) '_meta': readJsonObject(meta, 'Resource._meta'),
      };
}

/// A template description for resources available on the server.
class ResourceTemplate {
  /// A URI template (RFC 6570) to construct resource URIs.
  final String uriTemplate;

  /// A human-readable name for the type of resource this template refers to.
  final String name;

  /// A human-readable title for this template.
  final String? title;

  /// A description of what this template is for.
  final String? description;

  /// The MIME type for all resources matching this template, if consistent.
  final String? mimeType;

  /// Optional icon for the resource template.
  @Deprecated(
    'MCP 2025-11-25 uses icons; singular icon is parsed only for legacy compatibility and is not serialized.',
  )
  final ImageContent? icon;

  /// Optional set of icons for the resource template.
  final List<McpIcon>? icons;

  /// Optional additional properties describing the resource template.
  final ResourceAnnotations? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  /// Creates a resource template description.
  const ResourceTemplate({
    required this.uriTemplate,
    required this.name,
    this.title,
    this.description,
    this.mimeType,
    this.icon,
    this.icons,
    this.annotations,
    this.meta,
  });

  /// Creates from JSON.
  factory ResourceTemplate.fromJson(Map<String, dynamic> json) {
    return ResourceTemplate(
      uriTemplate: json['uriTemplate'] as String,
      name: json['name'] as String,
      title: json['title'] as String?,
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
      meta: readOptionalJsonObject(json['_meta'], 'ResourceTemplate._meta'),
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'uriTemplate': uriTemplate,
        'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (icons != null)
          'icons': icons!.map((icon) => icon.toJson()).toList(),
        if (annotations != null) 'annotations': annotations!.toJson(),
        if (meta != null)
          '_meta': readJsonObject(meta, 'ResourceTemplate._meta'),
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
    final meta = extractRequestMeta(json);
    return JsonRpcListResourcesRequest(
      id: parseRequestId(json['id']),
      params:
          paramsMap == null ? null : ListResourcesRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/list` request.
class ListResourcesResult implements CacheableResultData {
  /// The list of resources found.
  final List<Resource> resources;

  /// Opaque token for pagination, indicating more results might be available.
  final Cursor? nextCursor;

  /// How long, in milliseconds, the client may consider this result fresh.
  @override
  final int? ttlMs;

  /// Intended cache visibility: `public` or `private`.
  @override
  final String? cacheScope;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  /// Creates a list resources result.
  const ListResourcesResult({
    required this.resources,
    this.nextCursor,
    this.ttlMs,
    this.cacheScope,
    this.meta,
  });

  /// Creates from JSON.
  factory ListResourcesResult.fromJson(Map<String, dynamic> json) {
    final meta = readOptionalJsonObject(
      json['_meta'],
      'ListResourcesResult._meta',
    );
    final resources = json['resources'];
    if (resources is! List) {
      throw const FormatException('ListResourcesResult.resources is required');
    }
    return ListResourcesResult(
      resources: resources
          .map((e) => Resource.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      ttlMs: readOptionalTtlMs(json['ttlMs'], 'ListResourcesResult.ttlMs'),
      cacheScope: readOptionalCacheScope(
        json['cacheScope'],
        'ListResourcesResult.cacheScope',
      ),
      meta: meta,
    );
  }

  /// Converts to JSON (excluding meta).
  @override
  Map<String, dynamic> toJson() {
    validateTtlMs(ttlMs, 'ListResourcesResult.ttlMs');
    validateCacheScope(cacheScope, 'ListResourcesResult.cacheScope');
    return {
      'resources': resources.map((r) => r.toJson()).toList(),
      if (nextCursor != null) 'nextCursor': nextCursor,
      if (ttlMs != null) 'ttlMs': ttlMs,
      if (cacheScope != null) 'cacheScope': cacheScope,
      if (meta != null)
        '_meta': readJsonObject(meta, 'ListResourcesResult._meta'),
    };
  }
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
    final meta = extractRequestMeta(json);
    return JsonRpcListResourceTemplatesRequest(
      id: parseRequestId(json['id']),
      params: paramsMap == null
          ? null
          : ListResourceTemplatesRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/templates/list` request.
class ListResourceTemplatesResult implements CacheableResultData {
  /// The list of resource templates found.
  final List<ResourceTemplate> resourceTemplates;

  /// Opaque token for pagination.
  final Cursor? nextCursor;

  /// How long, in milliseconds, the client may consider this result fresh.
  @override
  final int? ttlMs;

  /// Intended cache visibility: `public` or `private`.
  @override
  final String? cacheScope;

  @override
  final Map<String, dynamic>? meta;

  const ListResourceTemplatesResult({
    required this.resourceTemplates,
    this.nextCursor,
    this.ttlMs,
    this.cacheScope,
    this.meta,
  });

  factory ListResourceTemplatesResult.fromJson(Map<String, dynamic> json) {
    final meta = readOptionalJsonObject(
      json['_meta'],
      'ListResourceTemplatesResult._meta',
    );
    final resourceTemplates = json['resourceTemplates'];
    if (resourceTemplates is! List) {
      throw const FormatException(
        'ListResourceTemplatesResult.resourceTemplates is required',
      );
    }
    return ListResourceTemplatesResult(
      resourceTemplates: resourceTemplates
          .map((e) => ResourceTemplate.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      ttlMs: readOptionalTtlMs(
        json['ttlMs'],
        'ListResourceTemplatesResult.ttlMs',
      ),
      cacheScope: readOptionalCacheScope(
        json['cacheScope'],
        'ListResourceTemplatesResult.cacheScope',
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    validateTtlMs(ttlMs, 'ListResourceTemplatesResult.ttlMs');
    validateCacheScope(cacheScope, 'ListResourceTemplatesResult.cacheScope');
    return {
      'resourceTemplates': resourceTemplates.map((t) => t.toJson()).toList(),
      if (nextCursor != null) 'nextCursor': nextCursor,
      if (ttlMs != null) 'ttlMs': ttlMs,
      if (cacheScope != null) 'cacheScope': cacheScope,
      if (meta != null)
        '_meta': readJsonObject(meta, 'ListResourceTemplatesResult._meta'),
    };
  }
}

/// Parameters for the `resources/read` request.
class ReadResourceRequest {
  /// The URI of the resource to read.
  final String uri;

  /// Client responses to MRTR input requests when retrying this read request.
  final InputResponses? inputResponses;

  /// Opaque MRTR state returned by the server and echoed on retry.
  final String? requestState;

  const ReadResourceRequest({
    required this.uri,
    this.inputResponses,
    this.requestState,
  });

  factory ReadResourceRequest.fromJson(Map<String, dynamic> json) =>
      ReadResourceRequest(
        uri: json['uri'] as String,
        inputResponses: InputResponse.mapFromJson(
          json['inputResponses'],
          'ReadResourceRequest.inputResponses',
        ),
        requestState: readOptionalString(
          json['requestState'],
          'ReadResourceRequest.requestState',
        ),
      );

  Map<String, dynamic> toJson() => {
        'uri': uri,
        if (inputResponses != null)
          'inputResponses': InputResponse.mapToJson(inputResponses!),
        if (requestState != null) 'requestState': requestState,
      };
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
    final meta = extractRequestMeta(json);
    return JsonRpcReadResourceRequest(
      id: parseRequestId(json['id']),
      readParams: ReadResourceRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Result data for a successful `resources/read` request.
class ReadResourceResult implements CacheableResultData {
  /// The contents of the resource (can be multiple parts).
  final List<ResourceContents> contents;

  /// How long, in milliseconds, the client may consider this result fresh.
  @override
  final int? ttlMs;

  /// Intended cache visibility: `public` or `private`.
  @override
  final String? cacheScope;

  @override
  final Map<String, dynamic>? meta;

  const ReadResourceResult({
    required this.contents,
    this.ttlMs,
    this.cacheScope,
    this.meta,
  });

  factory ReadResourceResult.fromJson(Map<String, dynamic> json) {
    final meta = readOptionalJsonObject(
      json['_meta'],
      'ReadResourceResult._meta',
    );
    final contents = json['contents'];
    if (contents is! List) {
      throw const FormatException('ReadResourceResult.contents is required');
    }
    return ReadResourceResult(
      contents: contents
          .map((e) => ResourceContents.fromJson(e as Map<String, dynamic>))
          .toList(),
      ttlMs: readOptionalTtlMs(json['ttlMs'], 'ReadResourceResult.ttlMs'),
      cacheScope: readOptionalCacheScope(
        json['cacheScope'],
        'ReadResourceResult.cacheScope',
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    validateTtlMs(ttlMs, 'ReadResourceResult.ttlMs');
    validateCacheScope(cacheScope, 'ReadResourceResult.cacheScope');
    return {
      'contents': contents.map((c) => c.toJson()).toList(),
      if (ttlMs != null) 'ttlMs': ttlMs,
      if (cacheScope != null) 'cacheScope': cacheScope,
      if (meta != null)
        '_meta': readJsonObject(meta, 'ReadResourceResult._meta'),
    };
  }
}

/// Notification from server indicating the list of available resources has changed.
class JsonRpcResourceListChangedNotification extends JsonRpcNotification {
  const JsonRpcResourceListChangedNotification({super.meta})
      : super(method: Method.notificationsResourcesListChanged);

  factory JsonRpcResourceListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      JsonRpcResourceListChangedNotification(meta: extractRequestMeta(json));
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
    final meta = extractRequestMeta(json);
    return JsonRpcSubscribeRequest(
      id: parseRequestId(json['id']),
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
    final meta = extractRequestMeta(json);
    return JsonRpcUnsubscribeRequest(
      id: parseRequestId(json['id']),
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
    final meta = readOptionalJsonObject(
      paramsMap['_meta'],
      'JsonRpcResourceUpdatedNotification._meta',
    );
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
