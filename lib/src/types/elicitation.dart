import '../shared/json_schema/json_schema.dart';
import 'json_rpc.dart';
import 'tasks.dart';
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

/// Legacy alias for [JsonSchema] used in elicitation requests.
typedef ElicitationInputSchema = JsonSchema;

/// Elicitation mode: 'form' for in-band structured data, 'url' for out-of-band interaction.
enum ElicitationMode {
  /// In-band structured data collection with optional schema validation.
  /// Data is exposed to the client.
  form,

  /// Out-of-band interaction via URL navigation.
  /// Data (other than the URL itself) is NOT exposed to the client.
  url,
}

/// Parameters for the `elicitation/create` request.
///
/// Supports two modes:
/// - **Form mode**: Collects structured data directly through the MCP client
/// - **URL mode**: Directs users to external URLs for sensitive interactions
class ElicitRequest {
  /// The mode of elicitation. Defaults to 'form' if omitted (for backwards compatibility).
  final ElicitationMode? mode;

  /// A human-readable message explaining why the interaction is needed.
  final String message;

  /// The JSON Schema defining what type of input to collect.
  /// Required for form mode, not used for URL mode.
  final ElicitationInputSchema? requestedSchema;

  /// The URL that the user should navigate to.
  /// Required for URL mode, not used for form mode.
  final String? url;

  /// A unique identifier for the elicitation.
  /// Required for URL mode to correlate with completion notifications.
  final String? elicitationId;

  /// Task metadata for task-augmented execution.
  final TaskCreation? task;

  const ElicitRequest({
    this.mode,
    required this.message,
    this.requestedSchema,
    this.url,
    this.elicitationId,
    this.task,
  })  : assert(
          mode != ElicitationMode.url || requestedSchema == null,
          'URL elicitation must not include requestedSchema.',
        ),
        assert(
          mode != ElicitationMode.url || url != null,
          'URL elicitation requires url.',
        ),
        assert(
          mode != ElicitationMode.url || elicitationId != null,
          'URL elicitation requires elicitationId.',
        ),
        assert(
          mode == ElicitationMode.url || requestedSchema != null,
          'Form elicitation requires requestedSchema.',
        ),
        assert(
          mode == ElicitationMode.url || url == null,
          'Form elicitation must not include url.',
        ),
        assert(
          mode == ElicitationMode.url || elicitationId == null,
          'Form elicitation must not include elicitationId.',
        );

  /// Creates form mode elicitation parameters.
  const ElicitRequest.form({
    required this.message,
    required ElicitationInputSchema this.requestedSchema,
    this.task,
  })  : mode = ElicitationMode.form,
        url = null,
        elicitationId = null;

  /// Creates URL mode elicitation parameters.
  const ElicitRequest.url({
    required this.message,
    required String this.url,
    required String this.elicitationId,
    this.task,
  })  : mode = ElicitationMode.url,
        requestedSchema = null;

  factory ElicitRequest.fromJson(
    Map<String, dynamic> json, {
    String? protocolVersion,
  }) {
    final modeValue = json['mode'];
    if (modeValue != null && modeValue is! String) {
      throw const FormatException('Elicitation mode must be a string.');
    }

    ElicitationMode? mode;
    if (modeValue != null) {
      try {
        mode = ElicitationMode.values.byName(modeValue);
      } catch (_) {
        throw FormatException('Unsupported elicitation mode: $modeValue');
      }
    }

    final message = json['message'];
    if (message is! String) {
      throw const FormatException('Elicitation message is required.');
    }

    final requestedSchemaJson = readOptionalJsonObject(
      json['requestedSchema'],
      'ElicitRequest.requestedSchema',
    );
    final url = json['url'];
    final elicitationId = json['elicitationId'];
    final task = readOptionalJsonObject(json['task'], 'ElicitRequest.task');

    if (mode == ElicitationMode.url) {
      if (url is! String) {
        throw const FormatException('URL elicitation requires url.');
      }
      _validateUrlElicitationUri(url, formatException: true);
      if (elicitationId is! String) {
        throw const FormatException('URL elicitation requires elicitationId.');
      }
      if (requestedSchemaJson != null) {
        throw const FormatException(
          'URL elicitation must not include requestedSchema.',
        );
      }
      return ElicitRequest.url(
        message: message,
        url: url,
        elicitationId: elicitationId,
        task: task == null ? null : TaskCreation.fromJson(task),
      );
    }

    if (requestedSchemaJson == null) {
      throw const FormatException('Form elicitation requires requestedSchema.');
    }
    _validateFormRequestedSchemaJson(
      requestedSchemaJson,
      protocolVersion: protocolVersion,
    );
    if (url != null) {
      throw const FormatException('Form elicitation must not include url.');
    }
    if (elicitationId != null) {
      throw const FormatException(
        'Form elicitation must not include elicitationId.',
      );
    }

    return ElicitRequest(
      mode: mode,
      message: message,
      requestedSchema: JsonSchema.fromJson(requestedSchemaJson),
      task: task == null ? null : TaskCreation.fromJson(task),
    );
  }

  void _validateShape({String? protocolVersion}) {
    if (isUrlMode) {
      if (requestedSchema != null) {
        throw ArgumentError(
          'URL elicitation must not include requestedSchema.',
        );
      }
      if (url == null) {
        throw ArgumentError('URL elicitation requires url.');
      }
      _validateUrlElicitationUri(url!);
      if (elicitationId == null) {
        throw ArgumentError('URL elicitation requires elicitationId.');
      }
      return;
    }

    if (requestedSchema == null) {
      throw ArgumentError('Form elicitation requires requestedSchema.');
    }
    _validateFormRequestedSchema(
      requestedSchema!,
      protocolVersion: protocolVersion,
    );
    if (url != null) {
      throw ArgumentError('Form elicitation must not include url.');
    }
    if (elicitationId != null) {
      throw ArgumentError('Form elicitation must not include elicitationId.');
    }
  }

  Map<String, dynamic> toJson({String? protocolVersion}) {
    _validateShape(protocolVersion: protocolVersion);
    return {
      if (mode != null) 'mode': mode!.name,
      'message': message,
      if (requestedSchema != null) 'requestedSchema': requestedSchema!.toJson(),
      if (url != null) 'url': url,
      if (elicitationId != null) 'elicitationId': elicitationId,
      if (task != null) 'task': task!.toJson(),
    };
  }

  /// Whether this is a form mode elicitation.
  bool get isFormMode => mode == null || mode == ElicitationMode.form;

  /// Whether this is a URL mode elicitation.
  bool get isUrlMode => mode == ElicitationMode.url;
}

/// Request sent from server to client to elicit user input
class JsonRpcElicitRequest extends JsonRpcRequest {
  /// The elicit parameters
  final ElicitRequest elicitParams;

  JsonRpcElicitRequest({
    required super.id,
    required this.elicitParams,
    super.meta,
    String? protocolVersion,
  }) : super(
          method: Method.elicitationCreate,
          params: elicitParams.toJson(
            protocolVersion: protocolVersion ?? _protocolVersionFromMeta(meta),
          ),
        );

  factory JsonRpcElicitRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.elicitationCreate,
      'JsonRpcElicitRequest',
    );
    final paramsMap =
        _readRequiredParamsObject(json, 'JsonRpcElicitRequest.params');
    final meta = extractRequestMeta(json);
    final protocolVersion = _protocolVersionFromMeta(meta);
    return JsonRpcElicitRequest(
      id: parseRequestId(json['id']),
      elicitParams: ElicitRequest.fromJson(
        paramsMap,
        protocolVersion: protocolVersion,
      ),
      meta: meta,
      protocolVersion: protocolVersion,
    );
  }
}

/// Result data for a successful `elicitation/create` response
class ElicitResult implements BaseResultData {
  /// The action taken by the user: 'accept', 'decline', or 'cancel'
  final String _action;

  /// The action taken by the user: 'accept', 'decline', or 'cancel'
  String get action {
    _validateElicitAction(_action);
    return _action;
  }

  /// The submitted form data (only present when action is 'accept')
  final Map<String, dynamic>? content;

  /// Legacy URL-mode response echo.
  ///
  /// MCP 2025-11-25 keeps URL and elicitation id on the request and completion
  /// notification, not on successful URL-mode accept results.
  @Deprecated(
    'URL-mode elicitation results no longer emit url; use the original request or completion notification.',
  )
  final String? url;

  /// Legacy URL-mode response echo.
  @Deprecated(
    'URL-mode elicitation results no longer emit elicitationId; use the original request or completion notification.',
  )
  final String? elicitationId;

  /// Optional metadata
  @override
  final Map<String, dynamic>? meta;

  const ElicitResult({
    required String action,
    this.content,
    this.url,
    this.elicitationId,
    this.meta,
  }) : _action = action;

  factory ElicitResult.fromJson(Map<String, dynamic> json) {
    final action = json['action'];
    if (action is! String || !_isValidElicitAction(action)) {
      throw FormatException('Invalid elicitation action: $action');
    }

    final content = _parseElicitResultContent(json['content']);
    _validateElicitResultContentForAction(
      action,
      content,
      formatException: true,
    );

    return ElicitResult(
      action: action,
      content: content,
      url: readOptionalString(json['url'], 'ElicitResult.url'),
      elicitationId: readOptionalString(
        json['elicitationId'],
        'ElicitResult.elicitationId',
      ),
      meta: readOptionalJsonObject(json['_meta'], 'ElicitResult._meta'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final resultAction = action;
    _validateElicitResultContentForAction(resultAction, content);
    final normalizedContent = _normalizeElicitResultContent(content);
    return {
      'action': resultAction,
      if (normalizedContent != null) 'content': normalizedContent,
      if (meta != null) '_meta': readJsonObject(meta, 'ElicitResult._meta'),
    };
  }

  /// Helper to check if the user accepted the input
  bool get accepted => action == 'accept';

  /// Helper to check if the user declined the input
  bool get declined => action == 'decline';

  /// Helper to check if the user cancelled the input
  bool get cancelled => action == 'cancel';
}

bool _isValidElicitAction(String action) =>
    action == 'accept' || action == 'decline' || action == 'cancel';

void _validateElicitAction(String action) {
  if (!_isValidElicitAction(action)) {
    throw ArgumentError.value(
      action,
      'action',
      'ElicitResult.action must be accept, decline, or cancel.',
    );
  }
}

/// Parameters for the `notifications/elicitation/complete` notification.
///
/// Sent by servers when an out-of-band interaction started by URL mode
/// elicitation is completed.
/// Parameters for the `notifications/elicitation/complete` notification.
///
/// Sent by servers when an out-of-band interaction started by URL mode
/// elicitation is completed.
class ElicitationCompleteNotification {
  /// The unique identifier for the elicitation, matching the original request.
  final String elicitationId;

  const ElicitationCompleteNotification({required this.elicitationId});

  factory ElicitationCompleteNotification.fromJson(Map<String, dynamic> json) {
    return ElicitationCompleteNotification(
      elicitationId: readRequiredString(
        json['elicitationId'],
        'ElicitationCompleteNotification.elicitationId',
      ),
    );
  }

  Map<String, dynamic> toJson() => {'elicitationId': elicitationId};
}

/// Notification sent from server to client when URL mode elicitation completes.
///
/// This allows clients to react programmatically when an out-of-band
/// interaction (started via URL mode elicitation) is completed.
class JsonRpcElicitationCompleteNotification extends JsonRpcNotification {
  /// The notification parameters containing the elicitation ID.
  final ElicitationCompleteNotification completeParams;

  JsonRpcElicitationCompleteNotification({
    required this.completeParams,
    super.meta,
  }) : super(
          method: Method.notificationsElicitationComplete,
          params: completeParams.toJson(),
        );

  factory JsonRpcElicitationCompleteNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    _expectJsonRpcMethod(
      json,
      Method.notificationsElicitationComplete,
      'JsonRpcElicitationCompleteNotification',
    );
    final paramsMap = _readRequiredParamsObject(
      json,
      'JsonRpcElicitationCompleteNotification.params',
    );
    final meta = readOptionalJsonObject(
      paramsMap['_meta'],
      'JsonRpcElicitationCompleteNotification._meta',
    );
    return JsonRpcElicitationCompleteNotification(
      completeParams: ElicitationCompleteNotification.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Data structure for URLElicitationRequiredError (-32042).
///
/// Contains a list of URL mode elicitations that must be completed
/// before the original request can be retried.
class URLElicitationRequiredErrorData {
  /// List of elicitations that are required to complete.
  /// All elicitations MUST be URL mode and have an elicitationId.
  final List<ElicitRequest> elicitations;

  const URLElicitationRequiredErrorData({required this.elicitations});

  factory URLElicitationRequiredErrorData.fromJson(Map<String, dynamic> json) {
    final elicitationsList = json['elicitations'];
    if (elicitationsList is! List) {
      throw const FormatException(
        'URLElicitationRequiredErrorData.elicitations is required',
      );
    }
    final elicitations = elicitationsList.indexed
        .map(
          (entry) => ElicitRequest.fromJson(
            readJsonObject(
              entry.$2,
              'URLElicitationRequiredErrorData.elicitations[${entry.$1}]',
            ),
          ),
        )
        .toList();
    _validateUrlElicitations(elicitations, formatException: true);
    return URLElicitationRequiredErrorData(elicitations: elicitations);
  }

  Map<String, dynamic> toJson() {
    _validateUrlElicitations(elicitations);
    return {
      'elicitations': elicitations.map((e) => e.toJson()).toList(),
    };
  }
}

/// Deprecated alias for [ElicitRequest].
@Deprecated('Use ElicitRequest instead')
typedef ElicitRequestParams = ElicitRequest;

/// Deprecated alias for [ElicitationCompleteNotification].
@Deprecated('Use ElicitationCompleteNotification instead')
typedef ElicitationCompleteParams = ElicitationCompleteNotification;

void _validateFormRequestedSchema(
  ElicitationInputSchema schema, {
  String? protocolVersion,
}) {
  _validateFormRequestedSchemaJson(
    schema.toJson(),
    protocolVersion: protocolVersion,
  );
}

void _validateFormRequestedSchemaJson(
  Map<String, dynamic> json, {
  String? protocolVersion,
}) {
  _ensureAllowedKeys(
    json,
    const {r'$schema', 'type', 'properties', 'required'},
    'ElicitRequest.requestedSchema',
  );
  _validateOptionalStringKeyword(
    json,
    r'$schema',
    'ElicitRequest.requestedSchema',
  );
  if (json['type'] != 'object') {
    throw const FormatException(
      'Form elicitation requestedSchema must have type object.',
    );
  }
  final properties = readOptionalJsonObject(
    json['properties'],
    'ElicitRequest.requestedSchema.properties',
  );
  if (properties == null) {
    throw const FormatException(
      'Form elicitation requestedSchema.properties is required.',
    );
  }
  for (final entry in properties.entries) {
    if (entry.value is! Map) {
      throw const FormatException(
        'Form elicitation requestedSchema properties must be schema objects.',
      );
    }
    _validatePrimitiveSchema(
      readJsonObject(
        entry.value,
        'ElicitRequest.requestedSchema.properties.${entry.key}',
      ),
      'ElicitRequest.requestedSchema.properties.${entry.key}',
      protocolVersion: protocolVersion,
    );
  }
  final required = json['required'];
  if (required != null &&
      (required is! List || required.any((value) => value is! String))) {
    throw const FormatException(
      'Form elicitation requestedSchema.required must be a string array.',
    );
  }
}

void _validatePrimitiveSchema(
  Map<String, dynamic> json,
  String context, {
  String? protocolVersion,
}) {
  final type = json['type'];
  switch (type) {
    case 'string':
      _validateStringOrSingleEnumSchema(json, context);
      return;
    case 'number':
    case 'integer':
      _ensureAllowedKeys(
        json,
        const {
          'type',
          'title',
          'description',
          'minimum',
          'maximum',
          'default',
        },
        context,
      );
      _validatePrimitiveBaseKeywords(json, context);
      _validateNumberSchemaKeywords(
        json,
        context,
        protocolVersion: protocolVersion,
      );
      return;
    case 'boolean':
      _ensureAllowedKeys(
        json,
        const {'type', 'title', 'description', 'default'},
        context,
      );
      _validatePrimitiveBaseKeywords(json, context);
      if (json['default'] != null && json['default'] is! bool) {
        throw FormatException('$context.default must be a boolean.');
      }
      return;
    case 'array':
      _validateMultiSelectEnumSchema(json, context);
      return;
    default:
      throw FormatException(
        '$context must be a primitive elicitation schema.',
      );
  }
}

void _validatePrimitiveBaseKeywords(
  Map<String, dynamic> json,
  String context,
) {
  _validateOptionalStringKeyword(json, 'title', context);
  _validateOptionalStringKeyword(json, 'description', context);
}

void _validateNumberSchemaKeywords(
  Map<String, dynamic> json,
  String context, {
  String? protocolVersion,
}) {
  if (!_usesDraftNumberSchemaKeywords(protocolVersion)) {
    for (final key in const ['default', 'minimum', 'maximum']) {
      _validateOptionalIntegerKeyword(json, key, context);
    }
    return;
  }

  for (final key in const ['default', 'minimum', 'maximum']) {
    if (json[key] != null) {
      readFiniteNumber(json[key], '$context.$key');
    }
  }
}

void _validateStringOrSingleEnumSchema(
  Map<String, dynamic> json,
  String context,
) {
  if (json.containsKey('oneOf')) {
    _ensureAllowedKeys(
      json,
      const {'type', 'title', 'description', 'oneOf', 'default'},
      context,
    );
    _validatePrimitiveBaseKeywords(json, context);
    _validateOptionalStringKeyword(json, 'default', context);
    final oneOf = json['oneOf'];
    if (oneOf is! List ||
        oneOf.any(
          (value) =>
              value is! Map ||
              value['const'] is! String ||
              value['title'] is! String,
        )) {
      throw FormatException('$context.oneOf must contain const/title strings.');
    }
    return;
  }

  _ensureAllowedKeys(
    json,
    const {
      'type',
      'title',
      'description',
      'minLength',
      'maxLength',
      'format',
      'default',
      'enum',
      'enumNames',
    },
    context,
  );
  _validatePrimitiveBaseKeywords(json, context);
  _validateOptionalStringKeyword(json, 'default', context);
  _validateOptionalIntegerKeyword(json, 'minLength', context);
  _validateOptionalIntegerKeyword(json, 'maxLength', context);
  final enumValues = json['enum'];
  if (enumValues != null &&
      (enumValues is! List || enumValues.any((value) => value is! String))) {
    throw FormatException('$context.enum must be a string array.');
  }
  final enumNames = json['enumNames'];
  if (enumNames != null &&
      (enumNames is! List || enumNames.any((value) => value is! String))) {
    throw FormatException('$context.enumNames must be a string array.');
  }
  if (enumNames != null && enumValues == null) {
    throw FormatException('$context.enumNames requires enum.');
  }
  final format = json['format'];
  if (format != null &&
      !const {'email', 'uri', 'date', 'date-time'}.contains(format)) {
    throw FormatException('$context.format is not allowed for elicitation.');
  }
}

void _validateMultiSelectEnumSchema(
  Map<String, dynamic> json,
  String context,
) {
  _ensureAllowedKeys(
    json,
    const {
      'type',
      'title',
      'description',
      'minItems',
      'maxItems',
      'items',
      'default',
    },
    context,
  );
  _validatePrimitiveBaseKeywords(json, context);
  _validateOptionalIntegerKeyword(json, 'minItems', context);
  _validateOptionalIntegerKeyword(json, 'maxItems', context);
  _validateOptionalStringListKeyword(json, 'default', context);
  final items = json['items'];
  if (items is! Map) {
    throw FormatException('$context.items is required for array schemas.');
  }
  final itemMap = readJsonObject(items, '$context.items');
  if (itemMap.containsKey('enum')) {
    _ensureAllowedKeys(itemMap, const {'type', 'enum'}, '$context.items');
    if (itemMap['type'] != 'string') {
      throw FormatException('$context.items.type must be string.');
    }
    _validateRequiredStringListKeyword(itemMap, 'enum', '$context.items');
    return;
  }
  final anyOf = itemMap['anyOf'];
  if (anyOf is List &&
      anyOf.every(
        (value) =>
            value is Map &&
            value['const'] is String &&
            value['title'] is String,
      )) {
    return;
  }
  throw FormatException('$context.items must define a string enum.');
}

void _validateOptionalStringKeyword(
  Map<String, dynamic> json,
  String key,
  String context,
) {
  final value = json[key];
  if (value != null && value is! String) {
    throw FormatException('$context.$key must be a string.');
  }
}

void _validateOptionalIntegerKeyword(
  Map<String, dynamic> json,
  String key,
  String context,
) {
  if (json[key] == null) {
    return;
  }
  readOptionalInteger(json[key], '$context.$key');
}

void _validateOptionalStringListKeyword(
  Map<String, dynamic> json,
  String key,
  String context,
) {
  if (json[key] == null) {
    return;
  }
  _validateRequiredStringListKeyword(json, key, context);
}

void _validateRequiredStringListKeyword(
  Map<String, dynamic> json,
  String key,
  String context,
) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$context.$key must be a string array.');
  }
}

void _ensureAllowedKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String context,
) {
  final unsupported = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unsupported.isNotEmpty) {
    throw FormatException(
      '$context contains unsupported fields: ${unsupported.join(', ')}',
    );
  }
}

String? _protocolVersionFromMeta(Map<String, dynamic>? meta) {
  final protocolVersion = meta?[McpMetaKey.protocolVersion];
  return protocolVersion is String ? protocolVersion : null;
}

bool _usesDraftNumberSchemaKeywords(String? protocolVersion) {
  return protocolVersion != null && isStatelessProtocolVersion(protocolVersion);
}

Map<String, dynamic>? _parseElicitResultContent(Object? content) {
  if (content == null) {
    return null;
  }
  final result = readJsonObject(content, 'ElicitResult.content');
  return _normalizeElicitResultContent(result, formatException: true);
}

Map<String, dynamic> _readRequiredParamsObject(
  Map<String, dynamic> json,
  String field,
) {
  if (!json.containsKey('params')) {
    throw FormatException('$field is required');
  }
  return readJsonObject(json['params'], field);
}

Map<String, dynamic>? _normalizeElicitResultContent(
  Map<String, dynamic>? content, {
  bool formatException = false,
}) {
  if (content == null) {
    return null;
  }
  final normalized = <String, dynamic>{};
  for (final entry in content.entries) {
    final value = entry.value;
    if (value is String || value is bool) {
      normalized[entry.key] = value;
      continue;
    }
    if (value is int) {
      normalized[entry.key] = value;
      continue;
    }
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      normalized[entry.key] = value.toInt();
      continue;
    }
    if (value is List && value.every((item) => item is String)) {
      normalized[entry.key] = List<String>.from(value);
      continue;
    }
    if (formatException) {
      throw FormatException(
        'ElicitResult.content.${entry.key} must be string, integer, boolean, or string[]',
      );
    }
    throw ArgumentError.value(
      value,
      'content.${entry.key}',
      'ElicitResult content values must be string, integer, boolean, or string[]',
    );
  }
  return normalized;
}

void _validateElicitResultContentForAction(
  String action,
  Map<String, dynamic>? content, {
  bool formatException = false,
}) {
  if (content == null || action == 'accept') {
    return;
  }
  if (formatException) {
    throw const FormatException(
      'ElicitResult.content is only allowed when action is accept.',
    );
  }
  throw ArgumentError.value(
    content,
    'content',
    'ElicitResult.content is only allowed when action is accept.',
  );
}

void _validateUrlElicitations(
  List<ElicitRequest> elicitations, {
  bool formatException = false,
}) {
  for (final elicitation in elicitations) {
    if (!elicitation.isUrlMode) {
      if (formatException) {
        throw const FormatException(
          'URLElicitationRequiredErrorData only accepts URL-mode elicitations',
        );
      }
      throw ArgumentError.value(
        elicitation,
        'elicitations',
        'URLElicitationRequiredErrorData only accepts URL-mode elicitations',
      );
    }
  }
}

void _validateUrlElicitationUri(
  String url, {
  bool formatException = false,
}) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.hasScheme) {
    return;
  }
  if (formatException) {
    throw const FormatException(
      'URL elicitation url must be an absolute URI.',
    );
  }
  throw ArgumentError.value(
    url,
    'url',
    'URL elicitation url must be an absolute URI.',
  );
}
