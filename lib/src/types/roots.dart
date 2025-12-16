import 'json_rpc.dart';

/// Represents a root directory or file the server can operate on.
class Root {
  /// URI identifying the root (must start with `file://`).
  final String uri;

  /// Optional name for the root.
  final String? name;

  Root({
    required this.uri,
    this.name,
  }) : assert(uri.startsWith("file://"));

  factory Root.fromJson(Map<String, dynamic> json) {
    return Root(
      uri: json['uri'] as String,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uri': uri,
        if (name != null) 'name': name,
      };
}

/// Request sent from server to client to get the list of root URIs.
class JsonRpcListRootsRequest extends JsonRpcRequest {
  const JsonRpcListRootsRequest({required super.id})
      : super(method: Method.rootsList);

  factory JsonRpcListRootsRequest.fromJson(Map<String, dynamic> json) =>
      JsonRpcListRootsRequest(id: json['id']);
}

/// Result data for a successful `roots/list` request.
class ListRootsResult implements BaseResultData {
  /// The list of roots provided by the client.
  final List<Root> roots;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const ListRootsResult({required this.roots, this.meta});

  factory ListRootsResult.fromJson(Map<String, dynamic> json) {
    final meta = json['_meta'] as Map<String, dynamic>?;
    return ListRootsResult(
      roots: (json['roots'] as List<dynamic>?)
              ?.map((r) => Root.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'roots': roots.map((r) => r.toJson()).toList(),
      };
}

/// Notification from client indicating the list of roots has changed.
class JsonRpcRootsListChangedNotification extends JsonRpcNotification {
  const JsonRpcRootsListChangedNotification()
      : super(method: Method.notificationsRootsListChanged);

  factory JsonRpcRootsListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) =>
      const JsonRpcRootsListChangedNotification();
}
