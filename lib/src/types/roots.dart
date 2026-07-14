import 'json_rpc.dart';
import 'validation.dart';

String _readRootUri(Object? value) {
  final uri = readRequiredString(value, 'Root.uri');
  if (!isAbsoluteUriString(uri)) {
    throw const FormatException('Root.uri must be an absolute URI');
  }
  if (!uri.startsWith('file://')) {
    throw const FormatException('Root.uri must start with file://');
  }
  return uri;
}

void _validateRootUri(String uri) {
  validateAbsoluteUriString(uri, 'Root.uri');
  if (!uri.startsWith('file://')) {
    throw ArgumentError.value(uri, 'uri', 'Root.uri must start with file://');
  }
}

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  expectJsonRpcMethod(json, expected, context);
}

/// Represents a root directory or file the server can operate on.
class Root {
  /// URI identifying the root (must start with `file://`).
  final String uri;

  /// Optional name for the root.
  final String? name;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  Root({
    required this.uri,
    this.name,
    this.meta,
  }) {
    _validateRootUri(uri);
  }

  factory Root.fromJson(Map<String, dynamic> json) {
    return Root(
      uri: _readRootUri(json['uri']),
      name: readOptionalString(json['name'], 'Root.name'),
      meta: readOptionalJsonObject(json['_meta'], 'Root._meta'),
    );
  }

  Map<String, dynamic> toJson() {
    _validateRootUri(uri);
    return {
      'uri': uri,
      if (name != null) 'name': name,
      if (meta != null) '_meta': readJsonObject(meta, 'Root._meta'),
    };
  }
}

/// Request sent from server to client to get the list of root URIs.
class JsonRpcListRootsRequest extends JsonRpcRequest {
  const JsonRpcListRootsRequest({required super.id, super.meta})
      : super(method: Method.rootsList);

  factory JsonRpcListRootsRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(json, Method.rootsList, 'JsonRpcListRootsRequest');
    _readOptionalParamsObject(json, 'JsonRpcListRootsRequest.params');
    return JsonRpcListRootsRequest(
      id: parseRequestId(json['id']),
      meta: extractRequestMeta(json),
    );
  }
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
    final meta = readOptionalJsonObject(json['_meta'], 'ListRootsResult._meta');
    final roots = json['roots'];
    if (roots is! List) {
      throw const FormatException('ListRootsResult.roots is required');
    }
    return ListRootsResult(
      roots: [
        for (var i = 0; i < roots.length; i++)
          Root.fromJson(
            readJsonObject(roots[i], 'ListRootsResult.roots[$i]'),
          ),
      ],
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'roots': roots.map((r) => r.toJson()).toList(),
        if (meta != null)
          '_meta': readJsonObject(meta, 'ListRootsResult._meta'),
      };
}

/// Notification from client indicating the list of roots has changed.
class JsonRpcRootsListChangedNotification extends JsonRpcNotification {
  const JsonRpcRootsListChangedNotification({super.meta})
      : super(method: Method.notificationsRootsListChanged);

  factory JsonRpcRootsListChangedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    _expectJsonRpcMethod(
      json,
      Method.notificationsRootsListChanged,
      'JsonRpcRootsListChangedNotification',
    );
    _readOptionalParamsObject(
      json,
      'JsonRpcRootsListChangedNotification.params',
    );
    return JsonRpcRootsListChangedNotification(meta: extractRequestMeta(json));
  }
}

void _readOptionalParamsObject(Map<String, dynamic> json, String field) {
  if (!json.containsKey('params')) {
    return;
  }
  readJsonObject(json['params'], field);
}
