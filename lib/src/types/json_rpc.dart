import 'misc.dart';
import 'initialization.dart';
import 'resources.dart';
import 'prompts.dart';
import 'elicitation.dart';
import 'tools.dart';
import 'logging.dart';
import 'sampling.dart';
import 'completion.dart';
import 'roots.dart';
import 'subscriptions.dart';
import 'tasks.dart';
import 'validation.dart';

/// The MCP `2026-07-28` version used by the SDK preview.
const previewProtocolVersion = "2026-07-28";

/// The newest MCP version that uses the `initialize` lifecycle.
///
/// Keep this separate from [stableProtocolVersion]: after MCP `2026-07-28`
/// becomes stable, legacy fallback must still initialize with `2025-11-25`.
const latestInitializationProtocolVersion = "2025-11-25";

/// The latest officially stable MCP protocol version supported.
const stableProtocolVersion = latestInitializationProtocolVersion;

/// The protocol version preferred by default in this SDK preview.
///
/// The upstream `2026-07-28` specification is still a release candidate, but
/// this preview prefers it by default while retaining
/// legacy initialization fallback.
const defaultProtocolVersion = previewProtocolVersion;

/// The newest MCP version that uses the `initialize` lifecycle.
///
/// This preserves the value published by mcp_dart 2.2. Use
/// [defaultProtocolVersion] for the 2.3 default profile.
@Deprecated(
  'Use latestInitializationProtocolVersion for initialize, or '
  'defaultProtocolVersion for the default profile.',
)
const latestProtocolVersion = latestInitializationProtocolVersion;

/// High-level MCP protocol compatibility profiles.
///
/// In the 2.3.0 preview, [McpClientOptions] and [McpServerOptions]
/// default to [stable]. Use [legacy] to explicitly keep the MCP `2025-11-25`
/// initialization flow, or [require2026] when a peer must support the MCP
/// `2026-07-28` stateless protocol.
enum McpProtocol {
  /// Default SDK compatibility behavior.
  ///
  /// This profile prefers MCP `2026-07-28` stateless negotiation, including
  /// `server/discover`, and falls back to legacy initialization for older
  /// peers.
  stable,

  /// Legacy behavior using the MCP `2025-11-25` initialization flow.
  ///
  /// This explicit compatibility profile targets MCP 2025-11-25 and earlier
  /// supported versions. It does not probe with `server/discover` by default.
  legacy,

  /// Require the MCP `2026-07-28` stateless protocol.
  ///
  /// This profile is intended for conformance tests and deployments where
  /// connecting to older MCP servers would be a configuration error.
  require2026;

  /// Preferred protocol version for outgoing negotiation.
  String get preferredProtocolVersion {
    return switch (this) {
      McpProtocol.stable || McpProtocol.require2026 => defaultProtocolVersion,
      McpProtocol.legacy => latestInitializationProtocolVersion,
    };
  }

  /// Protocol versions this profile advertises or accepts.
  List<String> get supportedVersions {
    return switch (this) {
      McpProtocol.stable => allSupportedProtocolVersions,
      McpProtocol.legacy => legacyProtocolVersions,
      McpProtocol.require2026 => statelessProtocolVersions,
    };
  }

  /// Whether clients should probe with `server/discover` by default.
  bool get useServerDiscoverByDefault {
    return switch (this) {
      McpProtocol.stable || McpProtocol.require2026 => true,
      McpProtocol.legacy => false,
    };
  }

  /// Whether failed discovery should fall back to legacy initialization.
  bool get allowLegacyInitializationFallbackByDefault {
    return switch (this) {
      McpProtocol.stable || McpProtocol.legacy => true,
      McpProtocol.require2026 => false,
    };
  }

  /// Whether this profile advertises support for stateless MCP versions.
  bool get supportsStatelessProtocol =>
      supportedVersions.any(isStatelessProtocolVersion);
}

/// Model Context Protocol versions retained for initialization compatibility.
const legacyProtocolVersions = [
  latestInitializationProtocolVersion,
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
  "2024-10-07",
];

/// Initialization-lifecycle protocol versions supported by mcp_dart.
///
/// This preserves the public value published by mcp_dart 2.2. Use
/// [allSupportedProtocolVersions] for the 2.3 default compatibility profile.
@Deprecated(
  'Use legacyProtocolVersions for initialize, or '
  'allSupportedProtocolVersions for the default profile.',
)
const supportedProtocolVersions = legacyProtocolVersions;

/// Protocol versions supported by the 2.3 default compatibility profile.
const allSupportedProtocolVersions = [
  defaultProtocolVersion,
  ...legacyProtocolVersions,
];

/// Protocol versions that use per-request metadata instead of initialization.
const statelessProtocolVersions = [
  defaultProtocolVersion,
];

/// Returns true when [version] uses the `2026-07-28` stateless request
/// model.
bool isStatelessProtocolVersion(String version) =>
    statelessProtocolVersions.contains(version);

/// Selects the first locally preferred version supported by a peer.
String? negotiateProtocolVersion(
  Iterable<String> peerSupportedVersions, {
  Iterable<String> localSupportedVersions = allSupportedProtocolVersions,
}) {
  final peerVersions = peerSupportedVersions.toSet();
  for (final version in localSupportedVersions) {
    if (peerVersions.contains(version)) {
      return version;
    }
  }
  return null;
}

/// Standard MCP `_meta` keys used by the `2026-07-28` stateless request and
/// result models.
///
/// `_meta` itself is extensible; keys not defined by MCP remain application or
/// extension metadata and are preserved on the wire.
class McpMetaKey {
  static const protocolVersion = 'io.modelcontextprotocol/protocolVersion';
  static const clientInfo = 'io.modelcontextprotocol/clientInfo';
  static const serverInfo = 'io.modelcontextprotocol/serverInfo';
  static const clientCapabilities =
      'io.modelcontextprotocol/clientCapabilities';
  static const logLevel = 'io.modelcontextprotocol/logLevel';
  static const subscriptionId = 'io.modelcontextprotocol/subscriptionId';

  const McpMetaKey._();
}

/// Builds request metadata for the `2026-07-28` stateless request model.
///
/// [clientInfo] is recommended by MCP but may be omitted for an anonymous
/// client. Protocol version and client capabilities remain required.
Map<String, dynamic> buildProtocolRequestMeta({
  required String protocolVersion,
  Implementation? clientInfo,
  required ClientCapabilities clientCapabilities,
  Map<String, dynamic>? meta,
  Object? logLevel,
}) {
  final requestMeta = <String, dynamic>{
    ...?validateRequestMeta(meta, validateKeys: true),
  }..remove(McpMetaKey.clientInfo);

  return <String, dynamic>{
    ...requestMeta,
    McpMetaKey.protocolVersion: protocolVersion,
    if (clientInfo != null) McpMetaKey.clientInfo: clientInfo.toJson(),
    McpMetaKey.clientCapabilities: clientCapabilities.toJson(
      omitLegacyTasks: isStatelessProtocolVersion(protocolVersion),
      omitLegacyRootsListChanged: isStatelessProtocolVersion(protocolVersion),
    ),
    if (logLevel != null) McpMetaKey.logLevel: logLevel,
  };
}

/// JSON-RPC protocol version string.
const jsonRpcVersion = "2.0";

/// Standard MCP JSON-RPC methods.
class Method {
  static const serverDiscover = "server/discover";
  static const initialize = "initialize";
  static const ping = "ping";
  static const resourcesList = "resources/list";
  static const resourcesRead = "resources/read";
  static const resourcesTemplatesList = "resources/templates/list";
  static const resourcesSubscribe = "resources/subscribe";
  static const resourcesUnsubscribe = "resources/unsubscribe";
  static const subscriptionsListen = "subscriptions/listen";
  static const promptsList = "prompts/list";
  static const promptsGet = "prompts/get";
  static const elicitationCreate = "elicitation/create";
  static const toolsList = "tools/list";
  static const toolsCall = "tools/call";
  static const loggingSetLevel = "logging/setLevel";
  static const samplingCreateMessage = "sampling/createMessage";
  static const completionComplete = "completion/complete";
  static const rootsList = "roots/list";
  static const tasksList = "tasks/list";
  static const tasksCancel = "tasks/cancel";
  static const tasksGet = "tasks/get";
  static const tasksResult = "tasks/result";
  static const tasksUpdate = "tasks/update";

  static const notificationsInitialized = "notifications/initialized";
  static const notificationsCancelled = "notifications/cancelled";
  static const notificationsProgress = "notifications/progress";
  static const notificationsResourcesListChanged =
      "notifications/resources/list_changed";
  static const notificationsResourcesUpdated =
      "notifications/resources/updated";
  static const notificationsSubscriptionsAcknowledged =
      "notifications/subscriptions/acknowledged";
  static const notificationsPromptsListChanged =
      "notifications/prompts/list_changed";
  static const notificationsToolsListChanged =
      "notifications/tools/list_changed";

  /// Deprecated completion list-change notification method.
  ///
  /// Stable MCP `2025-11-25` does not include this method. Use
  /// [notificationsExperimentalCompletionsListChanged] for extension behavior.
  @Deprecated(
    'notifications/completions/list_changed is not part of stable MCP 2025-11-25. '
    'Use notifications/experimental/completions/list_changed for extension behavior.',
  )
  static const notificationsCompletionsListChanged =
      "notifications/completions/list_changed";
  static const notificationsExperimentalCompletionsListChanged =
      "notifications/experimental/completions/list_changed";
  static const notificationsMessage = "notifications/message";
  static const notificationsRootsListChanged =
      "notifications/roots/list_changed";
  static const notificationsTasksStatus = "notifications/tasks/status";
  static const notificationsTasks = "notifications/tasks";
  static const notificationsElicitationComplete =
      "notifications/elicitation/complete";

  const Method._();
}

/// A progress token, used to associate progress notifications with the original request.
typedef ProgressToken = dynamic;

/// Parses a wire progress token.
///
/// MCP progress tokens are JSON strings or integers. Reject malformed wire
/// shapes at decode boundaries instead of allowing dynamic values to leak into
/// higher-level protocol code.
ProgressToken parseProgressToken(
  Object? value, {
  String fieldName = 'progressToken',
}) {
  if (value is String) {
    return value;
  }
  final integer = readOptionalInteger(value, fieldName);
  if (integer != null) {
    return integer;
  }
  throw FormatException(
    'Invalid $fieldName: expected string or integer, '
    'got ${value.runtimeType}',
  );
}

/// An opaque token used to represent a cursor for pagination.
typedef Cursor = String;

/// A uniquely identifying ID for a request in JSON-RPC.
typedef RequestId = dynamic;

/// Parses a JSON-RPC request identifier.
///
/// JSON-RPC/MCP request IDs are JSON strings or integers for SDK request
/// boundaries. Notifications omit the `id` member entirely, and responses may
/// omit the `id` member for JSON-RPC error cases.
RequestId parseRequestId(Object? value, {String fieldName = 'id'}) {
  if (value is String) {
    return value;
  }
  final integer = readOptionalInteger(value, fieldName);
  if (integer != null) {
    return integer;
  }
  throw FormatException(
    'Invalid $fieldName: expected string or integer, '
    'got ${value.runtimeType}',
  );
}

String _parseMethod(Object? value) {
  if (value is String) {
    return value;
  }
  throw FormatException(
    'Invalid method: expected string, got ${value.runtimeType}',
  );
}

int _parseErrorCode(Object? value) {
  final code = readOptionalInteger(value, 'JsonRpcErrorData.code');
  if (code == null) {
    throw const FormatException('JsonRpcErrorData.code is required');
  }
  return code;
}

String _parseErrorMessage(Object? value) {
  final message = readOptionalString(value, 'JsonRpcErrorData.message');
  if (message == null) {
    throw const FormatException('JsonRpcErrorData.message is required');
  }
  return message;
}

RequestId _parseResultResponseId(Object? value) {
  return parseRequestId(value);
}

RequestId? _parseErrorResponseId(Map<String, dynamic> json) {
  if (!json.containsKey('id')) {
    return null;
  }
  return parseRequestId(json['id']);
}

Map<String, dynamic>? _parseOptionalParamsObject(
  Map<String, dynamic> json,
  String fieldName,
) {
  if (!json.containsKey('params')) {
    return null;
  }
  return readJsonObject(json['params'], fieldName);
}

Object _requestIdToJson(RequestId id, String fieldName) {
  return parseRequestId(id, fieldName: fieldName);
}

final _metaPrefixLabelPattern = RegExp(
  r'^[A-Za-z](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
);
final _metaNamePattern = RegExp(
  r'^(?:[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?)?$',
);

/// Validates an MCP `2026-07-28` `_meta` key name.
///
/// MCP `2026-07-28` constrains metadata keys to an optional
/// dot-separated prefix followed by `/`, plus a name segment. Earlier protocol
/// versions did not define this grammar, so callers choose when to enforce it.
void validateMetaKeyName(String key, {String fieldName = '_meta'}) {
  final slashIndex = key.indexOf('/');
  final prefix = slashIndex == -1 ? null : key.substring(0, slashIndex);
  final name = slashIndex == -1 ? key : key.substring(slashIndex + 1);

  if (prefix != null) {
    if (prefix.isEmpty) {
      throw FormatException(
        'Invalid $fieldName key "$key": prefix must not be empty',
      );
    }
    final labels = prefix.split('.');
    for (final label in labels) {
      if (!_metaPrefixLabelPattern.hasMatch(label)) {
        throw FormatException(
          'Invalid $fieldName key "$key": invalid prefix label "$label"',
        );
      }
    }
  }

  if (!_metaNamePattern.hasMatch(name)) {
    throw FormatException(
      'Invalid $fieldName key "$key": invalid name segment "$name"',
    );
  }
}

/// Validates request metadata that can affect protocol behavior.
///
/// `_meta.progressToken` is an MCP wire token and must be a string or integer
/// when present. [validateKeys] opts in to the MCP `2026-07-28`
/// `_meta` key-name grammar without changing stable/legacy request parsing.
Map<String, dynamic>? validateRequestMeta(
  Map<String, dynamic>? meta, {
  bool validateKeys = false,
}) {
  if (meta == null) {
    return null;
  }

  if (validateKeys) {
    for (final key in meta.keys) {
      validateMetaKeyName(key);
    }
  }

  if (meta.containsKey('progressToken')) {
    parseProgressToken(
      meta['progressToken'],
      fieldName: '_meta.progressToken',
    );
  }
  return meta;
}

Map<String, dynamic>? _parseRequestMeta(Object? value) {
  if (value == null) {
    return null;
  }
  return validateRequestMeta(readJsonObject(value, '_meta'));
}

/// Extracts request metadata, preferring spec-defined params-nested `_meta`.
Map<String, dynamic>? extractRequestMeta(Map<String, dynamic> json) {
  final topLevelMeta = _parseRequestMeta(json['_meta']);
  final params = json['params'];
  final paramsMeta = params is Map ? _parseRequestMeta(params['_meta']) : null;
  return paramsMeta ?? topLevelMeta;
}

void _expectJsonRpcVersion(Map<String, dynamic> json, String context) {
  final version = readRequiredString(json['jsonrpc'], '$context.jsonrpc');
  if (version != jsonRpcVersion) {
    throw FormatException('$context.jsonrpc must be "$jsonRpcVersion"');
  }
}

/// Validates the JSON-RPC wrapper fields for a typed request or notification.
///
/// This is hidden from the public `mcp_dart` export surface but shared by the
/// typed protocol modules so direct parser calls enforce the same envelope
/// constraints as [JsonRpcMessage.fromJson].
void expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  _expectJsonRpcVersion(json, context);

  final method = readRequiredString(json['method'], '$context.method');
  if (method != expected) {
    throw FormatException('$context.method must be "$expected"');
  }
  if (json.containsKey('result') || json.containsKey('error')) {
    throw const FormatException(
      'Invalid JSON-RPC message: method cannot be combined with result or error',
    );
  }
}

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  expectJsonRpcMethod(json, expected, context);
}

/// Base class for all JSON-RPC messages (requests, notifications, responses, errors).
sealed class JsonRpcMessage {
  /// The JSON-RPC version string. Always "2.0".
  final String jsonrpc = jsonRpcVersion;

  /// Constant constructor for subclasses.
  const JsonRpcMessage();

  /// Parses a JSON map into a specific [JsonRpcMessage] subclass.
  factory JsonRpcMessage.fromJson(Map<String, dynamic> json) {
    if (json['jsonrpc'] != jsonRpcVersion) {
      throw FormatException('Invalid JSON-RPC version: ${json['jsonrpc']}');
    }

    final hasMethod = json.containsKey('method');
    final hasResult = json.containsKey('result');
    final hasError = json.containsKey('error');

    if (hasResult && hasError) {
      throw const FormatException(
        'Invalid JSON-RPC response: result and error are mutually exclusive',
      );
    }
    if (hasMethod && (hasResult || hasError)) {
      throw const FormatException(
        'Invalid JSON-RPC message: method cannot be combined with result or error',
      );
    }

    if (hasMethod) {
      final method = _parseMethod(json['method']);
      final hasId = json.containsKey('id');
      final params = _parseOptionalParamsObject(
        json,
        hasId ? 'JsonRpcRequest.params' : 'JsonRpcNotification.params',
      );

      if (hasId) {
        return switch (method) {
          Method.serverDiscover => JsonRpcServerDiscoverRequest.fromJson(json),
          Method.initialize => JsonRpcInitializeRequest.fromJson(json),
          Method.ping => JsonRpcPingRequest.fromJson(json),
          Method.resourcesList => JsonRpcListResourcesRequest.fromJson(json),
          Method.resourcesRead => JsonRpcReadResourceRequest.fromJson(json),
          Method.resourcesTemplatesList =>
            JsonRpcListResourceTemplatesRequest.fromJson(json),
          Method.resourcesSubscribe => JsonRpcSubscribeRequest.fromJson(json),
          Method.resourcesUnsubscribe =>
            JsonRpcUnsubscribeRequest.fromJson(json),
          Method.subscriptionsListen =>
            JsonRpcSubscriptionsListenRequest.fromJson(json),
          Method.promptsList => JsonRpcListPromptsRequest.fromJson(json),
          Method.promptsGet => JsonRpcGetPromptRequest.fromJson(json),
          Method.elicitationCreate => JsonRpcElicitRequest.fromJson(json),
          Method.toolsList => JsonRpcListToolsRequest.fromJson(json),
          Method.toolsCall => JsonRpcCallToolRequest.fromJson(json),
          Method.loggingSetLevel => JsonRpcSetLevelRequest.fromJson(json),
          Method.samplingCreateMessage => JsonRpcCreateMessageRequest.fromJson(
              json,
            ),
          Method.completionComplete => JsonRpcCompleteRequest.fromJson(json),
          Method.rootsList => JsonRpcListRootsRequest.fromJson(json),
          Method.tasksList => JsonRpcListTasksRequest.fromJson(json),
          Method.tasksCancel => JsonRpcCancelTaskRequest.fromJson(json),
          Method.tasksGet => JsonRpcGetTaskRequest.fromJson(json),
          Method.tasksResult => JsonRpcTaskResultRequest.fromJson(json),
          Method.tasksUpdate => JsonRpcUpdateTaskRequest.fromJson(json),
          _ => JsonRpcRequest(
              id: parseRequestId(json['id']),
              method: method,
              params: params,
              meta: extractRequestMeta(json),
            ),
        };
      } else {
        return switch (method) {
          Method.notificationsInitialized =>
            JsonRpcInitializedNotification.fromJson(json),
          Method.notificationsCancelled =>
            JsonRpcCancelledNotification.fromJson(
              json,
            ),
          Method.notificationsProgress => JsonRpcProgressNotification.fromJson(
              json,
            ),
          Method.notificationsResourcesListChanged =>
            JsonRpcResourceListChangedNotification.fromJson(json),
          Method.notificationsResourcesUpdated =>
            JsonRpcResourceUpdatedNotification.fromJson(json),
          Method.notificationsSubscriptionsAcknowledged =>
            JsonRpcSubscriptionsAcknowledgedNotification.fromJson(json),
          Method.notificationsPromptsListChanged =>
            JsonRpcPromptListChangedNotification.fromJson(json),
          Method.notificationsToolsListChanged =>
            JsonRpcToolListChangedNotification.fromJson(json),
          Method.notificationsExperimentalCompletionsListChanged =>
            JsonRpcCompletionListChangedNotification.fromJson(json),
          Method.notificationsMessage =>
            JsonRpcLoggingMessageNotification.fromJson(
              json,
            ),
          Method.notificationsRootsListChanged =>
            JsonRpcRootsListChangedNotification.fromJson(json),
          Method.notificationsTasksStatus =>
            JsonRpcTaskStatusNotification.fromJson(json),
          Method.notificationsTasks => JsonRpcTaskNotification.fromJson(json),
          _ => JsonRpcNotification(
              method: method,
              params: params,
              meta: extractRequestMeta(json),
            ),
        };
      }
    } else if (hasResult) {
      final id = _parseResultResponseId(json['id']);
      final resultData =
          readJsonObject(json['result'], 'JsonRpcResponse.result');
      final meta = readOptionalJsonObject(
        resultData['_meta'],
        'JsonRpcResponse._meta',
      );
      final actualResult = Map<String, dynamic>.from(resultData)
        ..remove('_meta');
      return JsonRpcResponse(id: id, result: actualResult, meta: meta);
    } else if (hasError) {
      return JsonRpcError.fromJson(json);
    } else {
      throw FormatException('Invalid JSON-RPC message format: $json');
    }
  }

  /// Converts the message object to its JSON representation.
  Map<String, dynamic> toJson();
}

/// Base class for JSON-RPC requests that expect a response.
class JsonRpcRequest extends JsonRpcMessage {
  /// The request identifier.
  final RequestId id;

  /// The method to be invoked.
  final String method;

  /// The parameters for the method, if any.
  final Map<String, dynamic>? params;

  /// Optional metadata associated with the request.
  final Map<String, dynamic>? meta;

  /// Creates a JSON-RPC request.
  const JsonRpcRequest({
    required this.id,
    required this.method,
    this.params,
    this.meta,
  });

  /// The progress token for out-of-band progress notifications.
  ProgressToken? get progressToken {
    final token = meta?['progressToken'];
    return token == null ? null : parseProgressToken(token);
  }

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'id': _requestIdToJson(id, 'JsonRpcRequest.id'),
        'method': method,
        if (params != null || meta != null)
          'params': <String, dynamic>{
            if (params != null)
              ...readJsonObject(params, 'JsonRpcRequest.params'),
            if (meta != null)
              '_meta': readJsonObject(
                validateRequestMeta(meta),
                'JsonRpcRequest._meta',
              ),
          },
      };
}

/// Base class for JSON-RPC notifications which do not expect a response.
class JsonRpcNotification extends JsonRpcMessage {
  /// The method to be invoked.
  final String method;

  /// The parameters for the method, if any.
  final Map<String, dynamic>? params;

  /// Optional metadata associated with the notification.
  final Map<String, dynamic>? meta;

  /// Creates a JSON-RPC notification.
  const JsonRpcNotification({required this.method, this.params, this.meta});

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'method': method,
        if (params != null || meta != null)
          'params': <String, dynamic>{
            if (params != null)
              ...readJsonObject(params, 'JsonRpcNotification.params'),
            if (meta != null)
              '_meta': readJsonObject(meta, 'JsonRpcNotification._meta'),
          },
      };
}

/// Represents a successful (non-error) response to a request.
class JsonRpcResponse extends JsonRpcMessage {
  /// The identifier matching the original request.
  final RequestId id;

  /// The result data of the method invocation.
  final Map<String, dynamic> result;

  /// Optional metadata associated with the response.
  final Map<String, dynamic>? meta;

  /// Creates a successful JSON-RPC response.
  const JsonRpcResponse({required this.id, required this.result, this.meta});

  @override
  Map<String, dynamic> toJson() {
    final resultJson = readJsonObject(result, 'JsonRpcResponse.result');
    final resultMeta = readOptionalJsonObject(
      resultJson['_meta'],
      'JsonRpcResponse.result._meta',
    );
    final responseMeta =
        meta == null ? null : readJsonObject(meta, 'JsonRpcResponse._meta');
    final wireResult = Map<String, dynamic>.from(resultJson)..remove('_meta');
    final wireMeta = <String, dynamic>{
      ...?resultMeta,
      ...?responseMeta,
    };
    final hasWireMeta = resultJson.containsKey('_meta') || meta != null;

    return {
      'jsonrpc': jsonrpc,
      'id': _requestIdToJson(id, 'JsonRpcResponse.id'),
      'result': <String, dynamic>{
        ...wireResult,
        if (hasWireMeta) '_meta': wireMeta,
      },
    };
  }
}
// --- JSON-RPC Error ---

/// Standard JSON-RPC error codes.
enum ErrorCode {
  connectionClosed(-32000),
  requestTimeout(-32001),

  /// HTTP request metadata headers do not match the JSON-RPC body.
  headerMismatch(-32020),

  /// Resource not found in stable MCP 2025-11-25.
  resourceNotFound(-32002),

  /// Required per-request client capabilities were not declared.
  missingRequiredClientCapability(-32021),

  /// The requested protocol version is unsupported by the receiver.
  unsupportedProtocolVersion(-32022),

  /// URL mode elicitation is required before the request can be processed.
  /// The error data contains elicitations that must be completed.
  urlElicitationRequired(-32042),

  parseError(-32700),
  invalidRequest(-32600),
  methodNotFound(-32601),
  invalidParams(-32602),
  internalError(-32603);

  final int value;
  const ErrorCode(this.value);

  /// Finds an [ErrorCode] based on its integer [value], or returns null.
  static ErrorCode? fromValue(int value) => values
      .cast<ErrorCode?>()
      .firstWhere((e) => e?.value == value, orElse: () => null);
}

/// Represents the `error` object in a JSON-RPC error response.
class JsonRpcErrorData {
  final int code;
  final String message;
  final dynamic data;

  const JsonRpcErrorData({
    required this.code,
    required this.message,
    this.data,
  });

  factory JsonRpcErrorData.fromJson(Map<String, dynamic> json) =>
      JsonRpcErrorData(
        code: _parseErrorCode(json['code']),
        message: _parseErrorMessage(json['message']),
        data: json.containsKey('data')
            ? readJsonValue(json['data'], 'JsonRpcErrorData.data')
            : null,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': readJsonValue(data, 'JsonRpcErrorData.data'),
      };
}

/// Represents a response indicating an error occurred during a request.
class JsonRpcError extends JsonRpcMessage {
  final RequestId? id;
  final JsonRpcErrorData error;

  const JsonRpcError({required this.id, required this.error});

  factory JsonRpcError.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcVersion(json, 'JsonRpcError');
    if (json.containsKey('method')) {
      throw const FormatException(
        'Invalid JSON-RPC error response: method cannot be combined with error',
      );
    }
    if (json.containsKey('result')) {
      throw const FormatException(
        'Invalid JSON-RPC error response: result and error are mutually exclusive',
      );
    }

    return JsonRpcError(
      id: _parseErrorResponseId(json),
      error: JsonRpcErrorData.fromJson(
        readJsonObject(json['error'], 'JsonRpcError.error'),
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        if (id != null) 'id': _requestIdToJson(id, 'JsonRpcError.id'),
        'error': error.toJson(),
      };
}

/// Base class for specific MCP result types.
abstract class BaseResultData {
  /// Optional metadata associated with the result.
  Map<String, dynamic>? get meta;

  /// Converts the result data to its JSON representation.
  ///
  /// Implementations must include `_meta` when [meta] is non-null so typed
  /// results preserve the MCP `Result._meta` field during direct serialization.
  Map<String, dynamic> toJson();
}

/// Result data that carries MCP cache freshness hints.
abstract class CacheableResultData implements BaseResultData {
  /// How long, in milliseconds, the client may consider this result fresh.
  int? get ttlMs;

  /// Intended cache visibility: [CacheScope.public] or [CacheScope.private].
  String? get cacheScope;
}

/// Allowed cache scopes for MCP cacheable results.
class CacheScope {
  static const public = 'public';
  static const private = 'private';

  const CacheScope._();
}

/// Result type for completed MCP requests.
const resultTypeComplete = 'complete';

/// Result type for MCP multi round-trip requests needing more input.
const resultTypeInputRequired = 'input_required';

/// Result type for MCP task extension task creation results.
const resultTypeTask = 'task';

/// Map of server-assigned input request keys to requested inputs.
typedef InputRequests = Map<String, InputRequest>;

/// Map of server-assigned input request keys to client responses.
typedef InputResponses = Map<String, InputResponse>;

/// A server-to-client request embedded in an MRTR `InputRequiredResult`.
class InputRequest {
  /// Request method. Must be one of the MRTR-supported server request methods.
  final String method;

  /// Request params, when present.
  final Map<String, dynamic>? params;

  const InputRequest._({required this.method, this.params});

  /// Creates an embedded `elicitation/create` input request.
  factory InputRequest.elicit(ElicitRequest params) {
    final inputParams = params.toJson(
      protocolVersion: defaultProtocolVersion,
    )..remove('task');
    return InputRequest._(
      method: Method.elicitationCreate,
      params: inputParams,
    );
  }

  /// Creates an embedded `sampling/createMessage` input request.
  factory InputRequest.createMessage(CreateMessageRequest params) {
    final inputParams = params.toJson(omitToolExecution: true)..remove('task');
    return InputRequest._(
      method: Method.samplingCreateMessage,
      params: inputParams,
    );
  }

  /// Creates an embedded `roots/list` input request.
  factory InputRequest.listRoots({Map<String, dynamic>? params}) {
    return InputRequest._(
      method: Method.rootsList,
      params: params,
    );
  }

  factory InputRequest.fromJson(Map<String, dynamic> json) {
    final method = json['method'];
    if (method is! String) {
      throw const FormatException('InputRequest.method is required');
    }

    switch (method) {
      case Method.elicitationCreate:
        final params = _readRequiredJsonObject(
          json['params'],
          'InputRequest.params',
        );
        if (params.containsKey('task')) {
          throw const FormatException(
            'InputRequest elicitation/create params must not include '
            'legacy task metadata',
          );
        }
        ElicitRequest.fromJson(
          params,
          protocolVersion: defaultProtocolVersion,
        );
        return InputRequest._(method: method, params: params);
      case Method.samplingCreateMessage:
        final params = _readRequiredJsonObject(
          json['params'],
          'InputRequest.params',
        );
        if (params.containsKey('task')) {
          throw const FormatException(
            'InputRequest sampling/createMessage params must not include '
            'legacy task metadata',
          );
        }
        CreateMessageRequest.fromJson(params);
        return InputRequest._(method: method, params: params);
      case Method.rootsList:
        return InputRequest._(
          method: method,
          params: _readOptionalJsonObject(
            json['params'],
            'InputRequest.params',
          ),
        );
      default:
        throw const FormatException(
          'InputRequest.method must be one of '
          '${Method.elicitationCreate}, ${Method.samplingCreateMessage}, '
          'or ${Method.rootsList}',
        );
    }
  }

  /// Parses an input request map.
  static InputRequests? mapFromJson(Object? value, String field) {
    if (value == null) {
      return null;
    }
    final json = _readRequiredJsonObject(value, field);
    return json.map(
      (key, value) => MapEntry(
        key,
        InputRequest.fromJson(_readRequiredJsonObject(value, '$field.$key')),
      ),
    );
  }

  /// Converts an input request map to JSON.
  static Map<String, dynamic> mapToJson(InputRequests requests) {
    return requests.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
  }

  /// The typed params for an embedded `elicitation/create` request.
  ElicitRequest get elicitParams {
    if (method != Method.elicitationCreate || params == null) {
      throw StateError('InputRequest is not an elicitation/create request');
    }
    return ElicitRequest.fromJson(
      params!,
      protocolVersion: defaultProtocolVersion,
    );
  }

  /// The typed params for an embedded `sampling/createMessage` request.
  CreateMessageRequest get createMessageParams {
    if (method != Method.samplingCreateMessage || params == null) {
      throw StateError('InputRequest is not a sampling/createMessage request');
    }
    return CreateMessageRequest.fromJson(params!);
  }

  Map<String, dynamic> toJson() => {
        'method': method,
        if (params != null)
          'params': readJsonObject(params, 'InputRequest.params'),
      };
}

/// A client response to an MRTR [InputRequest].
class InputResponse {
  /// Raw result object for the embedded request.
  final Map<String, dynamic> value;

  const InputResponse.raw(this.value);

  /// Creates an input response from a typed MCP result.
  factory InputResponse.fromResult(BaseResultData result) {
    return InputResponse.raw(_inputResponseJsonForResult(result));
  }

  factory InputResponse.fromJson(Map<String, dynamic> json) {
    final value = Map<String, dynamic>.from(json);
    _validateInputResponse(value);
    return InputResponse.raw(value);
  }

  /// Parses an input response map.
  static InputResponses? mapFromJson(Object? value, String field) {
    if (value == null) {
      return null;
    }
    final json = _readRequiredJsonObject(value, field);
    return json.map(
      (key, value) => MapEntry(
        key,
        InputResponse.fromJson(_readRequiredJsonObject(value, '$field.$key')),
      ),
    );
  }

  /// Converts an input response map to JSON.
  static Map<String, dynamic> mapToJson(InputResponses responses) {
    return responses.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
  }

  Map<String, dynamic> toJson() {
    final json = readJsonObject(value, 'InputResponse');
    _validateInputResponse(json);
    return json;
  }
}

Map<String, dynamic> _inputResponseJsonForResult(BaseResultData result) {
  final json = Map<String, dynamic>.from(result.toJson());
  if (result is ElicitResult || result is ListRootsResult) {
    json.remove('_meta');
  }
  _validateInputResponse(json);
  return json;
}

void _validateInputResponse(Map<String, dynamic> json) {
  if (_canParseInputResponse(CreateMessageResult.fromJson, json)) {
    return;
  }

  if (_canParseInputResponse(ListRootsResult.fromJson, json)) {
    _rejectInputResponseMeta(json, 'ListRootsResult');
    return;
  }

  if (_canParseInputResponse(ElicitResult.fromJson, json)) {
    _rejectInputResponseMeta(json, 'ElicitResult');
    return;
  }

  throw const FormatException(
    'InputResponse must be a CreateMessageResult, ListRootsResult, '
    'or ElicitResult',
  );
}

void _rejectInputResponseMeta(Map<String, dynamic> json, String resultName) {
  if (json.containsKey('_meta')) {
    throw FormatException(
      'InputResponse $resultName must not include _meta in MCP 2026-07-28',
    );
  }
}

bool _canParseInputResponse(
  BaseResultData Function(Map<String, dynamic> json) parser,
  Map<String, dynamic> json,
) {
  try {
    parser(json);
    return true;
  } on FormatException {
    return false;
  } on ArgumentError {
    return false;
  } on TypeError {
    return false;
  }
}

/// Result returned when a request needs extra client input before retry.
class InputRequiredResult implements BaseResultData {
  /// Server-to-client requests the client must fulfill before retry.
  final InputRequests? inputRequests;

  /// Opaque server state to echo exactly on retry.
  final String? requestState;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const InputRequiredResult({
    this.inputRequests,
    this.requestState,
    this.meta,
  }) : assert(
          inputRequests != null || requestState != null,
          'InputRequiredResult requires inputRequests or requestState',
        );

  factory InputRequiredResult.fromJson(Map<String, dynamic> json) {
    if (json['resultType'] != resultTypeInputRequired) {
      throw const FormatException(
        'InputRequiredResult.resultType must be input_required',
      );
    }

    final inputRequests = InputRequest.mapFromJson(
      json['inputRequests'],
      'InputRequiredResult.inputRequests',
    );
    final requestState = readOptionalString(
      json['requestState'],
      'InputRequiredResult.requestState',
    );
    if (inputRequests == null && requestState == null) {
      throw const FormatException(
        'InputRequiredResult requires inputRequests or requestState',
      );
    }

    return InputRequiredResult(
      inputRequests: inputRequests,
      requestState: requestState,
      meta: _readOptionalJsonObject(json['_meta'], 'InputRequiredResult._meta'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    if (inputRequests == null && requestState == null) {
      throw StateError(
        'InputRequiredResult requires inputRequests or requestState',
      );
    }

    return {
      'resultType': resultTypeInputRequired,
      if (inputRequests != null)
        'inputRequests': InputRequest.mapToJson(inputRequests!),
      if (requestState != null) 'requestState': requestState,
      if (meta != null)
        '_meta': readJsonObject(meta, 'InputRequiredResult._meta'),
    };
  }
}

Map<String, dynamic> _readRequiredJsonObject(Object? value, String field) {
  return readJsonObject(value, field);
}

Map<String, dynamic>? _readOptionalJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return _readRequiredJsonObject(value, field);
}

/// Custom error class for MCP specific errors.
class McpError extends Error {
  /// The error code (typically from [ErrorCode] or custom).
  final int code;

  /// The error message.
  final String message;

  /// Optional additional data associated with the error.
  final dynamic data;

  McpError(this.code, this.message, [this.data]);

  @override
  String toString() =>
      'McpError $code: $message ${data != null ? '(data: $data)' : ''}';
}

/// JSON-RPC request to list tools.
class JsonRpcListToolsRequest extends JsonRpcRequest {
  const JsonRpcListToolsRequest({
    required super.id,
    super.params,
    super.meta,
  }) : super(method: Method.toolsList);

  /// Deprecated typed-params constructor retained for compatibility.
  ///
  /// Prefer passing `params?.toJson()` to [JsonRpcListToolsRequest].
  @Deprecated(
    'Use JsonRpcListToolsRequest(id: ..., params: params?.toJson(), meta: meta) instead.',
  )
  factory JsonRpcListToolsRequest.fromListParams({
    required RequestId id,
    ListToolsRequest? params,
    Map<String, dynamic>? meta,
  }) {
    return JsonRpcListToolsRequest(
      id: id,
      params: params?.toJson(),
      meta: meta,
    );
  }

  factory JsonRpcListToolsRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(json, Method.toolsList, 'JsonRpcListToolsRequest');
    return JsonRpcListToolsRequest(
      id: parseRequestId(json['id']),
      params: readOptionalJsonObject(
        json['params'],
        'JsonRpcListToolsRequest.params',
      ),
      meta: extractRequestMeta(json),
    );
  }

  ListToolsRequest get listParams {
    final requestParams = params;
    if (requestParams == null) {
      return const ListToolsRequest();
    }
    return ListToolsRequest.fromJson(requestParams);
  }
}

/// JSON-RPC request to call a tool.
class JsonRpcCallToolRequest extends JsonRpcRequest {
  const JsonRpcCallToolRequest({
    required super.id,
    required Map<String, dynamic> params,
    super.meta,
  }) : super(method: Method.toolsCall, params: params);

  factory JsonRpcCallToolRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(json, Method.toolsCall, 'JsonRpcCallToolRequest');
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcCallToolRequest.params',
    );
    if (paramsMap == null) {
      throw const FormatException(
        'JsonRpcCallToolRequest.params is required',
      );
    }
    return JsonRpcCallToolRequest(
      id: parseRequestId(json['id']),
      params: paramsMap,
      meta: extractRequestMeta(json),
    );
  }

  CallToolRequest get callParams {
    final requestParams = params;
    if (requestParams == null) {
      throw const FormatException('Missing params for call tool request');
    }
    return CallToolRequest.fromJson(requestParams);
  }

  bool get isTaskAugmented {
    // Check for task augmentation in meta or params as per convention
    // Usually handled by side-channel or specific params
    return meta?.containsKey('task') == true ||
        params?.containsKey('task') == true;
  }

  TaskCreation? get taskParams {
    final taskMap = meta?['task'] ?? params?['task'];
    if (taskMap is Map<String, dynamic>) {
      return TaskCreation.fromJson(taskMap);
    }
    return null;
  }
}
