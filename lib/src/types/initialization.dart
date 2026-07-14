import 'content.dart';
import 'json_rpc.dart';
import 'validation.dart';

Map<String, dynamic>? _asJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value ? <String, dynamic>{} : null;
  }
  return readJsonObject(value, field);
}

String? _readOptionalPresentString(
  Map<String, dynamic> json,
  String key,
  String field,
) {
  if (!json.containsKey(key)) {
    return null;
  }
  return readRequiredString(json[key], field);
}

bool _isAbsoluteUri(String value) {
  return Uri.tryParse(value)?.hasScheme ?? false;
}

void _expectJsonRpcMethod(
  Map<String, dynamic> json,
  String expected,
  String context,
) {
  expectJsonRpcMethod(json, expected, context);
}

void _readOptionalParamsObject(Map<String, dynamic> json, String field) {
  if (!json.containsKey('params')) {
    return;
  }
  readJsonObject(json['params'], field);
}

String? _readOptionalPresentUriString(
  Map<String, dynamic> json,
  String key,
  String field,
) {
  final value = _readOptionalPresentString(json, key, field);
  if (value == null) {
    return null;
  }
  if (!_isAbsoluteUri(value)) {
    throw FormatException('$field must be an absolute URI');
  }
  return value;
}

void _validateAbsoluteUriString(String value, String field) {
  if (!_isAbsoluteUri(value)) {
    throw ArgumentError.value(value, field, 'must be an absolute URI');
  }
}

List<McpIcon>? _readOptionalIconList(
  Map<String, dynamic> json,
  String key,
  String field,
) {
  if (!json.containsKey(key)) {
    return null;
  }

  final value = json[key];
  if (value is! List) {
    throw FormatException('$field must be a list of objects');
  }

  return [
    for (var i = 0; i < value.length; i++)
      McpIcon.fromJson(readJsonObject(value[i], '$field[$i]')),
  ];
}

Map<String, dynamic>? _asStrictJsonObject(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return readJsonObject(value, field);
}

Map<String, dynamic>? _asJsonObjectMap(Object? value, String field) {
  final map = _asStrictJsonObject(value, field);
  if (map == null) {
    return null;
  }

  return map.map((key, item) {
    final object = _asStrictJsonObject(item, '$field.$key');
    if (object == null) {
      throw FormatException('$field.$key must be an object');
    }
    return MapEntry(key, object);
  });
}

Map<String, dynamic>? _serializeJsonObjectMap(
  Map<String, dynamic>? value,
  String field,
) {
  if (value == null) {
    return null;
  }

  return value.map((key, item) {
    final object = _asStrictJsonObject(item, '$field.$key');
    if (object == null) {
      throw ArgumentError.value(item, '$field.$key', 'must be an object');
    }
    return MapEntry(key, object);
  });
}

Map<String, Map<String, dynamic>>? _asExtensionMap(
  Object? value,
  String field,
) {
  final map = _asJsonObjectMap(value, field);
  return map?.map(
    (key, value) => MapEntry(key, value.cast<String, dynamic>()),
  );
}

Map<String, Map<String, dynamic>>? _serializeExtensionMap(
  Map<String, Map<String, dynamic>>? value,
  String field,
) {
  final map = _serializeJsonObjectMap(value, field);
  return map?.map(
    (key, value) => MapEntry(key, value.cast<String, dynamic>()),
  );
}

Map<String, dynamic>? _readAdditionalCapabilities(
  Map<String, dynamic> json,
  Set<String> knownKeys,
  String field,
) {
  final additional = <String, dynamic>{};
  for (final entry in json.entries) {
    if (knownKeys.contains(entry.key)) {
      continue;
    }
    additional[entry.key] = readJsonValue(
      entry.value,
      '$field.${entry.key}',
    );
  }
  return additional.isEmpty ? null : additional;
}

Map<String, dynamic>? _serializeAdditionalCapabilities(
  Map<String, dynamic>? value,
  Set<String> knownKeys,
  String field,
) {
  if (value == null) {
    return null;
  }

  final additional = <String, dynamic>{};
  for (final entry in value.entries) {
    if (knownKeys.contains(entry.key)) {
      throw ArgumentError.value(
        entry.key,
        '$field.${entry.key}',
        'must not duplicate a known capability key',
      );
    }
    additional[entry.key] = readJsonValue(
      entry.value,
      '$field.${entry.key}',
    );
  }
  return additional;
}

bool? _capabilityDeclared(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  readJsonObject(value, field);
  return true;
}

Map<String, dynamic>? _serializeCapabilityObject(bool? declared) {
  if (declared == true) {
    return <String, dynamic>{};
  }
  return null;
}

/// MCP Tasks extension identifier.
const mcpTasksExtensionId = 'io.modelcontextprotocol/tasks';

/// Returns [extensions] with the MCP Tasks extension capability declared.
Map<String, Map<String, dynamic>> withMcpTasksExtension([
  Map<String, Map<String, dynamic>>? extensions,
]) {
  return {
    ...?extensions,
    mcpTasksExtensionId: <String, dynamic>{},
  };
}

const _clientCapabilityKeys = {
  'experimental',
  'sampling',
  'roots',
  'elicitation',
  'tasks',
  'extensions',
};

const _serverCapabilityKeys = {
  'experimental',
  'logging',
  'prompts',
  'resources',
  'tools',
  'completions',
  'tasks',
  'elicitation',
  'extensions',
};

/// Describes an MCP implementation (client or server).
class Implementation {
  /// The name of the implementation.
  final String name;

  /// A human-readable title for this implementation.
  final String? title;

  /// The version string of the implementation.
  final String version;

  /// A description of the implementation.
  final String? description;

  /// Icons for the implementation.
  final List<McpIcon>? icons;

  /// Website URL for the implementation.
  final String? websiteUrl;

  const Implementation({
    required this.name,
    this.title,
    required this.version,
    this.description,
    this.icons,
    this.websiteUrl,
  });

  factory Implementation.fromJson(Map<String, dynamic> json) {
    return Implementation(
      name: readRequiredString(json['name'], 'Implementation.name'),
      title: _readOptionalPresentString(
        json,
        'title',
        'Implementation.title',
      ),
      version: readRequiredString(json['version'], 'Implementation.version'),
      description: _readOptionalPresentString(
        json,
        'description',
        'Implementation.description',
      ),
      icons: _readOptionalIconList(json, 'icons', 'Implementation.icons'),
      websiteUrl: _readOptionalPresentUriString(
        json,
        'websiteUrl',
        'Implementation.websiteUrl',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final websiteUrl = this.websiteUrl;
    if (websiteUrl != null) {
      _validateAbsoluteUriString(websiteUrl, 'Implementation.websiteUrl');
    }

    return {
      'name': name,
      if (title != null) 'title': title,
      'version': version,
      if (description != null) 'description': description,
      if (icons != null) 'icons': icons?.map((e) => e.toJson()).toList(),
      if (websiteUrl != null) 'websiteUrl': websiteUrl,
    };
  }
}

/// Describes capabilities related to root resources (e.g., workspace folders).
class ClientCapabilitiesRoots {
  /// Whether the client supports `notifications/roots/list_changed`.
  final bool? listChanged;

  const ClientCapabilitiesRoots({
    this.listChanged,
  });

  factory ClientCapabilitiesRoots.fromJson(Map<String, dynamic> json) {
    return ClientCapabilitiesRoots(
      listChanged: readOptionalBool(
        json['listChanged'],
        'ClientCapabilitiesRoots.listChanged',
      ),
    );
  }

  Map<String, dynamic> toJson({bool omitListChanged = false}) => {
        if (!omitListChanged && listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to elicitation > form mode.
class ClientElicitationForm {
  /// Whether the client supports applying default values from the requested schema
  /// to the submitted content of an elicitation response.
  final bool? applyDefaults;

  const ClientElicitationForm({this.applyDefaults});

  factory ClientElicitationForm.fromJson(Map<String, dynamic> json) {
    return ClientElicitationForm(
      applyDefaults: readOptionalBool(
        json['applyDefaults'],
        'ClientElicitationForm.applyDefaults',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (applyDefaults != null) 'applyDefaults': applyDefaults,
      };
}

/// Describes capabilities related to elicitation > URL mode.
class ClientElicitationUrl {
  const ClientElicitationUrl();

  factory ClientElicitationUrl.fromJson(Map<String, dynamic> json) {
    return const ClientElicitationUrl();
  }

  Map<String, dynamic> toJson() => {};
}

/// Describes capabilities related to elicitation (server-initiated user input).
///
/// Clients can declare support for specific elicitation modes:
/// - **form**: In-band structured data collection with JSON Schema validation
/// - **url**: Out-of-band interaction via URL navigation (data not exposed to client)
class ClientElicitation {
  /// Present if the client supports form mode elicitation.
  /// Form mode collects structured data directly through the MCP client.
  final ClientElicitationForm? form;

  /// Present if the client supports URL mode elicitation.
  /// URL mode directs users to external URLs for sensitive interactions.
  final ClientElicitationUrl? url;

  /// Creates elicitation capabilities.
  /// By default, supports form mode only for backwards compatibility.
  const ClientElicitation({
    this.form,
    this.url,
  });

  /// Creates capabilities supporting both form and URL modes.
  const ClientElicitation.all()
      : form = const ClientElicitationForm(),
        url = const ClientElicitationUrl();

  /// Creates capabilities supporting form mode only.
  const ClientElicitation.formOnly()
      : form = const ClientElicitationForm(),
        url = null;

  /// Creates capabilities supporting URL mode only.
  const ClientElicitation.urlOnly()
      : form = null,
        url = const ClientElicitationUrl();

  factory ClientElicitation.fromJson(Map<String, dynamic> json) {
    // Backwards compatibility: empty JSON implies form mode support.
    if (json.isEmpty) {
      return const ClientElicitation.formOnly();
    }

    final formMap = _asJsonObject(json['form'], 'ClientElicitation.form');
    final urlMap = _asJsonObject(json['url'], 'ClientElicitation.url');

    return ClientElicitation(
      form: formMap == null ? null : ClientElicitationForm.fromJson(formMap),
      url: urlMap == null ? null : ClientElicitationUrl.fromJson(urlMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (form != null) 'form': form!.toJson(),
        if (url != null) 'url': url!.toJson(),
      };
}

/// Capabilities related to sampling.
class ClientCapabilitiesSampling {
  /// Whether the client supports context inclusion via `includeContext`.
  final bool context;

  /// Whether the client supports sampling with tools.
  final bool tools;

  const ClientCapabilitiesSampling({
    this.context = false,
    this.tools = false,
  });

  factory ClientCapabilitiesSampling.fromJson(Map<String, dynamic> json) {
    return ClientCapabilitiesSampling(
      context: _capabilityDeclared(
            json['context'],
            'ClientCapabilitiesSampling.context',
          ) ??
          false,
      tools: _capabilityDeclared(
            json['tools'],
            'ClientCapabilitiesSampling.tools',
          ) ??
          false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (context) 'context': <String, dynamic>{},
        if (tools) 'tools': <String, dynamic>{},
      };
}

/// Capabilities related to tasks > elicitation.
class ClientCapabilitiesTasksElicitationCreate {
  const ClientCapabilitiesTasksElicitationCreate();

  factory ClientCapabilitiesTasksElicitationCreate.fromJson(
    Map<String, dynamic> json,
  ) {
    return const ClientCapabilitiesTasksElicitationCreate();
  }

  Map<String, dynamic> toJson() => {};
}

class ClientCapabilitiesTasksElicitation {
  final ClientCapabilitiesTasksElicitationCreate? create;

  const ClientCapabilitiesTasksElicitation({this.create});

  factory ClientCapabilitiesTasksElicitation.fromJson(
    Map<String, dynamic> json,
  ) {
    final createMap = _asJsonObject(
      json['create'],
      'ClientCapabilitiesTasksElicitation.create',
    );
    return ClientCapabilitiesTasksElicitation(
      create: createMap != null
          ? ClientCapabilitiesTasksElicitationCreate.fromJson(createMap)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (create != null) 'create': create!.toJson(),
      };
}

/// Capabilities related to tasks > sampling.
class ClientCapabilitiesTasksSamplingCreateMessage {
  const ClientCapabilitiesTasksSamplingCreateMessage();

  factory ClientCapabilitiesTasksSamplingCreateMessage.fromJson(
    Map<String, dynamic> json,
  ) {
    return const ClientCapabilitiesTasksSamplingCreateMessage();
  }

  Map<String, dynamic> toJson() => {};
}

class ClientCapabilitiesTasksSampling {
  final ClientCapabilitiesTasksSamplingCreateMessage? createMessage;

  const ClientCapabilitiesTasksSampling({this.createMessage});

  factory ClientCapabilitiesTasksSampling.fromJson(Map<String, dynamic> json) {
    final createMessageMap = _asJsonObject(
      json['createMessage'],
      'ClientCapabilitiesTasksSampling.createMessage',
    );
    return ClientCapabilitiesTasksSampling(
      createMessage: createMessageMap != null
          ? ClientCapabilitiesTasksSamplingCreateMessage.fromJson(
              createMessageMap,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (createMessage != null) 'createMessage': createMessage!.toJson(),
      };
}

/// Task capabilities derived from spec:
/// specifies which request types can be augmented with tasks.
class ClientCapabilitiesTasksRequests {
  /// Task support for elicitation-related requests.
  final ClientCapabilitiesTasksElicitation? elicitation;

  /// Task support for sampling-related requests.
  final ClientCapabilitiesTasksSampling? sampling;

  const ClientCapabilitiesTasksRequests({
    this.elicitation,
    this.sampling,
  });

  factory ClientCapabilitiesTasksRequests.fromJson(Map<String, dynamic> json) {
    final elicitationMap = _asJsonObject(
      json['elicitation'],
      'ClientCapabilitiesTasksRequests.elicitation',
    );
    final samplingMap = _asJsonObject(
      json['sampling'],
      'ClientCapabilitiesTasksRequests.sampling',
    );

    return ClientCapabilitiesTasksRequests(
      elicitation: elicitationMap != null
          ? ClientCapabilitiesTasksElicitation.fromJson(elicitationMap)
          : null,
      sampling: samplingMap != null
          ? ClientCapabilitiesTasksSampling.fromJson(samplingMap)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (elicitation != null) 'elicitation': elicitation!.toJson(),
        if (sampling != null) 'sampling': sampling!.toJson(),
      };
}

/// Describes capabilities related to tasks.
class ClientCapabilitiesTasks {
  /// Whether this client supports tasks/cancel.
  final bool? cancel;

  /// Whether this client supports tasks/list.
  final bool? list;

  /// Specifies which request types can be augmented with tasks.
  final ClientCapabilitiesTasksRequests? requests;

  const ClientCapabilitiesTasks({
    this.cancel,
    this.list,
    this.requests,
  });

  factory ClientCapabilitiesTasks.fromJson(Map<String, dynamic> json) {
    final requestsMap = _asJsonObject(
      json['requests'],
      'ClientCapabilitiesTasks.requests',
    );
    return ClientCapabilitiesTasks(
      cancel: _capabilityDeclared(
        json['cancel'],
        'ClientCapabilitiesTasks.cancel',
      ),
      list: _capabilityDeclared(
        json['list'],
        'ClientCapabilitiesTasks.list',
      ),
      requests: requestsMap == null
          ? null
          : ClientCapabilitiesTasksRequests.fromJson(requestsMap),
    );
  }

  Map<String, dynamic> toJson() {
    final cancelCapability = _serializeCapabilityObject(cancel);
    final listCapability = _serializeCapabilityObject(list);

    return {
      if (cancelCapability != null) 'cancel': cancelCapability,
      if (listCapability != null) 'list': listCapability,
      if (requests != null) 'requests': requests!.toJson(),
    };
  }
}

/// Capabilities a client may support.
class ClientCapabilities {
  /// Experimental, non-standard capabilities.
  ///
  /// Each capability value must be a JSON object. Use an empty object to
  /// advertise support without settings.
  final Map<String, dynamic>? experimental;

  /// Present if the client supports sampling (`sampling/createMessage`).
  final ClientCapabilitiesSampling? sampling;

  /// Present if the client supports listing roots (`roots/list`).
  final ClientCapabilitiesRoots? roots;

  /// Present if the client supports elicitation (`elicitation/create`).
  final ClientElicitation? elicitation;

  /// Present if the client supports tasks (`tasks/list`, `tasks/requests`, etc).
  final ClientCapabilitiesTasks? tasks;

  /// Optional MCP extension capabilities.
  ///
  /// Keys are extension identifiers (e.g. `"io.modelcontextprotocol/ui"`),
  /// values are extension-specific settings.
  final Map<String, Map<String, dynamic>>? extensions;

  /// Additional client capabilities not yet modeled by this SDK.
  final Map<String, dynamic>? additionalCapabilities;

  const ClientCapabilities({
    this.experimental,
    this.sampling,
    this.roots,
    this.elicitation,
    this.tasks,
    this.extensions,
    this.additionalCapabilities,
  });

  factory ClientCapabilities.fromJson(Map<String, dynamic> json) {
    final rootsMap = _asJsonObject(json['roots'], 'ClientCapabilities.roots');
    final elicitationMap = _asJsonObject(
      json['elicitation'],
      'ClientCapabilities.elicitation',
    );
    final tasksMap = _asJsonObject(json['tasks'], 'ClientCapabilities.tasks');
    final samplingMap = _asJsonObject(
      json['sampling'],
      'ClientCapabilities.sampling',
    );
    final extensionsMap = _asExtensionMap(
      json['extensions'],
      'ClientCapabilities.extensions',
    );

    return ClientCapabilities(
      experimental: _asJsonObjectMap(
        json['experimental'],
        'ClientCapabilities.experimental',
      ),
      sampling: samplingMap == null
          ? null
          : ClientCapabilitiesSampling.fromJson(samplingMap),
      roots:
          rootsMap == null ? null : ClientCapabilitiesRoots.fromJson(rootsMap),
      elicitation: elicitationMap == null
          ? null
          : ClientElicitation.fromJson(elicitationMap),
      tasks:
          tasksMap == null ? null : ClientCapabilitiesTasks.fromJson(tasksMap),
      extensions: extensionsMap,
      additionalCapabilities: _readAdditionalCapabilities(
        json,
        _clientCapabilityKeys,
        'ClientCapabilities',
      ),
    );
  }

  Map<String, dynamic> toJson({
    bool omitLegacyTasks = false,
    bool omitLegacyRootsListChanged = false,
  }) =>
      {
        if (experimental != null)
          'experimental': _serializeJsonObjectMap(
            experimental,
            'ClientCapabilities.experimental',
          ),
        if (sampling != null) 'sampling': sampling!.toJson(),
        if (roots != null)
          'roots': roots!.toJson(
            omitListChanged: omitLegacyRootsListChanged,
          ),
        if (elicitation != null) 'elicitation': elicitation!.toJson(),
        if (!omitLegacyTasks && tasks != null) 'tasks': tasks!.toJson(),
        if (extensions != null)
          'extensions': _serializeExtensionMap(
            extensions,
            'ClientCapabilities.extensions',
          ),
        ...?_serializeAdditionalCapabilities(
          additionalCapabilities,
          _clientCapabilityKeys,
          'ClientCapabilities.additionalCapabilities',
        ),
      };

  /// Whether the MCP Tasks extension is declared.
  bool get supportsTasksExtension =>
      extensions?.containsKey(mcpTasksExtensionId) ?? false;
}

/// Parameters for the `initialize` request.
class InitializeRequest {
  /// The latest protocol version the client supports.
  final String protocolVersion;

  /// The capabilities the client supports.
  final ClientCapabilities capabilities;

  /// Information about the client implementation.
  final Implementation clientInfo;

  const InitializeRequest({
    required this.protocolVersion,
    required this.capabilities,
    required this.clientInfo,
  });

  factory InitializeRequest.fromJson(Map<String, dynamic> json) =>
      InitializeRequest(
        protocolVersion: readRequiredString(
          json['protocolVersion'],
          'InitializeRequest.protocolVersion',
        ),
        capabilities: ClientCapabilities.fromJson(
          readJsonObject(
            json['capabilities'],
            'InitializeRequest.capabilities',
          ),
        ),
        clientInfo: Implementation.fromJson(
          readJsonObject(json['clientInfo'], 'InitializeRequest.clientInfo'),
        ),
      );

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'capabilities': capabilities.toJson(),
        'clientInfo': clientInfo.toJson(),
      };
}

/// Request sent from client to server upon connection to begin initialization.
class JsonRpcInitializeRequest extends JsonRpcRequest {
  /// The initialization parameters.
  final InitializeRequest initParams;

  JsonRpcInitializeRequest({
    required super.id,
    required this.initParams,
    super.meta,
  }) : super(method: Method.initialize, params: initParams.toJson());

  factory JsonRpcInitializeRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(json, Method.initialize, 'JsonRpcInitializeRequest');
    final paramsMap = readOptionalJsonObject(
      json['params'],
      'JsonRpcInitializeRequest.params',
    );
    if (paramsMap == null) {
      throw const FormatException("Missing params for initialize request");
    }
    final meta = extractRequestMeta(json);
    return JsonRpcInitializeRequest(
      id: parseRequestId(json['id']),
      initParams: InitializeRequest.fromJson(paramsMap),
      meta: meta,
    );
  }
}

/// Request sent by an MCP `2026-07-28` client to discover server support.
class JsonRpcServerDiscoverRequest extends JsonRpcRequest {
  JsonRpcServerDiscoverRequest({
    required super.id,
    super.meta,
  }) : super(method: Method.serverDiscover);

  factory JsonRpcServerDiscoverRequest.fromJson(Map<String, dynamic> json) {
    _expectJsonRpcMethod(
      json,
      Method.serverDiscover,
      'JsonRpcServerDiscoverRequest',
    );
    final params = readJsonObject(
      json['params'],
      'JsonRpcServerDiscoverRequest.params',
    );
    final meta = validateRequestMeta(
      readJsonObject(
        params['_meta'],
        'JsonRpcServerDiscoverRequest.params._meta',
      ),
      validateKeys: true,
    )!;

    return JsonRpcServerDiscoverRequest(
      id: parseRequestId(json['id']),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final meta = this.meta;
    if (meta == null) {
      throw const FormatException(
        'JsonRpcServerDiscoverRequest.params._meta is required',
      );
    }
    return {
      'jsonrpc': jsonrpc,
      'id': parseRequestId(id, fieldName: 'JsonRpcServerDiscoverRequest.id'),
      'method': method,
      'params': <String, dynamic>{
        '_meta': readJsonObject(
          validateRequestMeta(meta, validateKeys: true),
          'JsonRpcServerDiscoverRequest.params._meta',
        ),
      },
    };
  }
}

/// Describes capabilities related to elicitation > form mode for the server.
class ServerElicitationForm {
  const ServerElicitationForm();

  factory ServerElicitationForm.fromJson(Map<String, dynamic> json) {
    return const ServerElicitationForm();
  }

  Map<String, dynamic> toJson() => {};
}

/// Describes capabilities related to elicitation > URL mode for the server.
class ServerElicitationUrl {
  const ServerElicitationUrl();

  factory ServerElicitationUrl.fromJson(Map<String, dynamic> json) {
    return const ServerElicitationUrl();
  }

  Map<String, dynamic> toJson() => {};
}

/// Describes capabilities related to elicitation (server-initiated user input).
class ServerCapabilitiesElicitation {
  /// Present if the server supports form mode elicitation.
  final ServerElicitationForm? form;

  /// Present if the server supports URL mode elicitation.
  final ServerElicitationUrl? url;

  const ServerCapabilitiesElicitation({
    this.form,
    this.url,
  });

  /// Creates capabilities supporting both form and URL modes.
  const ServerCapabilitiesElicitation.all()
      : form = const ServerElicitationForm(),
        url = const ServerElicitationUrl();

  /// Creates capabilities supporting form mode only.
  const ServerCapabilitiesElicitation.formOnly()
      : form = const ServerElicitationForm(),
        url = null;

  /// Creates capabilities supporting URL mode only.
  const ServerCapabilitiesElicitation.urlOnly()
      : form = null,
        url = const ServerElicitationUrl();

  factory ServerCapabilitiesElicitation.fromJson(Map<String, dynamic> json) {
    final formMap = _asJsonObject(
      json['form'],
      'ServerCapabilitiesElicitation.form',
    );
    final urlMap = _asJsonObject(
      json['url'],
      'ServerCapabilitiesElicitation.url',
    );

    return ServerCapabilitiesElicitation(
      form: formMap == null ? null : ServerElicitationForm.fromJson(formMap),
      url: urlMap == null ? null : ServerElicitationUrl.fromJson(urlMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (form != null) 'form': form!.toJson(),
        if (url != null) 'url': url!.toJson(),
      };
}

/// Describes capabilities related to prompts.
class ServerCapabilitiesPrompts {
  /// Whether the server supports `notifications/prompts/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesPrompts({
    this.listChanged,
  });

  factory ServerCapabilitiesPrompts.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesPrompts(
      listChanged: readOptionalBool(
        json['listChanged'],
        'ServerCapabilitiesPrompts.listChanged',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to resources.
class ServerCapabilitiesResources {
  /// Whether the server supports resource update subscriptions.
  ///
  /// MCP `2025-11-25` uses `resources/subscribe` and
  /// `resources/unsubscribe`; MCP `2026-07-28` uses `subscriptions/listen` with
  /// `resourceSubscriptions`.
  final bool? subscribe;

  /// Whether the server supports `notifications/resources/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesResources({
    this.subscribe,
    this.listChanged,
  });

  factory ServerCapabilitiesResources.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesResources(
      subscribe: readOptionalBool(
        json['subscribe'],
        'ServerCapabilitiesResources.subscribe',
      ),
      listChanged: readOptionalBool(
        json['listChanged'],
        'ServerCapabilitiesResources.listChanged',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (subscribe != null) 'subscribe': subscribe,
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to tools.
class ServerCapabilitiesTools {
  /// Whether the server supports `notifications/tools/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesTools({
    this.listChanged,
  });

  factory ServerCapabilitiesTools.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesTools(
      listChanged: readOptionalBool(
        json['listChanged'],
        'ServerCapabilitiesTools.listChanged',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to completions.
class ServerCapabilitiesCompletions {
  /// Legacy non-standard completion list changed flag.
  ///
  /// MCP 2025-11-25 defines `completions` as an empty capability object and
  /// does not define a stable `notifications/completions/list_changed` method.
  @Deprecated(
    'MCP 2025-11-25 completions capability is an empty object; listChanged is ignored when serializing.',
  )
  final bool? listChanged;

  const ServerCapabilitiesCompletions({
    this.listChanged,
  });

  factory ServerCapabilitiesCompletions.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesCompletions(
      listChanged: readOptionalBool(
        json['listChanged'],
        'ServerCapabilitiesCompletions.listChanged',
      ),
    );
  }

  Map<String, dynamic> toJson() => {};
}

/// Describes capabilities related to tasks.
class ServerCapabilitiesTasksToolsCall {
  const ServerCapabilitiesTasksToolsCall();

  factory ServerCapabilitiesTasksToolsCall.fromJson(Map<String, dynamic> json) {
    return const ServerCapabilitiesTasksToolsCall();
  }

  Map<String, dynamic> toJson() => {};
}

class ServerCapabilitiesTasksTools {
  final ServerCapabilitiesTasksToolsCall? call;

  const ServerCapabilitiesTasksTools({this.call});

  factory ServerCapabilitiesTasksTools.fromJson(Map<String, dynamic> json) {
    final callMap = _asJsonObject(
      json['call'],
      'ServerCapabilitiesTasksTools.call',
    );
    return ServerCapabilitiesTasksTools(
      call: callMap == null
          ? null
          : ServerCapabilitiesTasksToolsCall.fromJson(callMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (call != null) 'call': call!.toJson(),
      };
}

class ServerCapabilitiesTasksRequests {
  final ServerCapabilitiesTasksTools? tools;

  const ServerCapabilitiesTasksRequests({this.tools});

  factory ServerCapabilitiesTasksRequests.fromJson(Map<String, dynamic> json) {
    final toolsMap = _asJsonObject(
      json['tools'],
      'ServerCapabilitiesTasksRequests.tools',
    );
    return ServerCapabilitiesTasksRequests(
      tools: toolsMap == null
          ? null
          : ServerCapabilitiesTasksTools.fromJson(toolsMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (tools != null) 'tools': tools!.toJson(),
      };
}

class ServerCapabilitiesTasks {
  /// Whether this server supports `tasks/list`.
  final bool? list;

  /// Whether this server supports `tasks/cancel`.
  final bool? cancel;

  /// Specifies which request types can be augmented with tasks.
  final ServerCapabilitiesTasksRequests? requests;

  /// Legacy non-spec field retained for compatibility.
  @Deprecated(
    'MCP 2025-11-25 ServerCapabilities.tasks does not include listChanged; this is parsed only for legacy compatibility.',
  )
  final bool? listChanged;

  const ServerCapabilitiesTasks({
    this.list,
    this.cancel,
    this.requests,
    this.listChanged,
  });

  factory ServerCapabilitiesTasks.fromJson(Map<String, dynamic> json) {
    final requestsMap = _asJsonObject(
      json['requests'],
      'ServerCapabilitiesTasks.requests',
    );
    return ServerCapabilitiesTasks(
      list: _capabilityDeclared(
        json['list'],
        'ServerCapabilitiesTasks.list',
      ),
      cancel: _capabilityDeclared(
        json['cancel'],
        'ServerCapabilitiesTasks.cancel',
      ),
      requests: requestsMap == null
          ? null
          : ServerCapabilitiesTasksRequests.fromJson(requestsMap),
      listChanged: readOptionalBool(
        json['listChanged'],
        'ServerCapabilitiesTasks.listChanged',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final listCapability = _serializeCapabilityObject(list);
    final cancelCapability = _serializeCapabilityObject(cancel);

    return {
      if (listCapability != null) 'list': listCapability,
      if (cancelCapability != null) 'cancel': cancelCapability,
      if (requests != null) 'requests': requests!.toJson(),
    };
  }
}

/// Capabilities a server may support.
class ServerCapabilities {
  /// Experimental, non-standard capabilities.
  ///
  /// Each capability value must be a JSON object. Use an empty object to
  /// advertise support without settings.
  final Map<String, dynamic>? experimental;

  /// Present if the server supports sending log messages (`notifications/message`).
  final Map<String, dynamic>? logging;

  /// Present if the server offers prompt templates (`prompts/list`, `prompts/get`).
  final ServerCapabilitiesPrompts? prompts;

  /// Present if the server offers resources (`resources/list`, `resources/read`, etc.).
  final ServerCapabilitiesResources? resources;

  /// Present if the server offers tools (`tools/list`, `tools/call`).
  final ServerCapabilitiesTools? tools;

  /// Present if the server offers completions (`completion/complete`).
  final ServerCapabilitiesCompletions? completions;

  /// Present if the server offers tasks (`tasks/list`, etc).
  final ServerCapabilitiesTasks? tasks;

  /// Present if the server offers elicitation (`elicitation/create`).
  @Deprecated(
    'MCP 2025-11-25 advertises elicitation support on client capabilities; server-side elicitation is parsed only for legacy compatibility.',
  )
  final ServerCapabilitiesElicitation? elicitation;

  /// Optional MCP extension capabilities.
  ///
  /// Keys are extension identifiers (e.g. `"io.modelcontextprotocol/ui"`),
  /// values are extension-specific settings.
  final Map<String, Map<String, dynamic>>? extensions;

  /// Additional server capabilities not yet modeled by this SDK.
  final Map<String, dynamic>? additionalCapabilities;

  const ServerCapabilities({
    this.experimental,
    this.logging,
    this.prompts,
    this.resources,
    this.tools,
    this.completions,
    this.tasks,
    this.elicitation,
    this.extensions,
    this.additionalCapabilities,
  });

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    final pMap = _asJsonObject(json['prompts'], 'ServerCapabilities.prompts');
    final rMap = _asJsonObject(
      json['resources'],
      'ServerCapabilities.resources',
    );
    final cMap = _asJsonObject(
      json['completions'],
      'ServerCapabilities.completions',
    );
    final tMap = _asJsonObject(json['tools'], 'ServerCapabilities.tools');
    final tasksMap = _asJsonObject(json['tasks'], 'ServerCapabilities.tasks');
    final elicitationMap = _asJsonObject(
      json['elicitation'],
      'ServerCapabilities.elicitation',
    );
    final extensionsMap = _asExtensionMap(
      json['extensions'],
      'ServerCapabilities.extensions',
    );

    return ServerCapabilities(
      experimental: _asJsonObjectMap(
        json['experimental'],
        'ServerCapabilities.experimental',
      ),
      logging: readOptionalJsonObject(
        json['logging'],
        'ServerCapabilities.logging',
      ),
      prompts: pMap == null ? null : ServerCapabilitiesPrompts.fromJson(pMap),
      resources:
          rMap == null ? null : ServerCapabilitiesResources.fromJson(rMap),
      tools: tMap == null ? null : ServerCapabilitiesTools.fromJson(tMap),
      completions:
          cMap == null ? null : ServerCapabilitiesCompletions.fromJson(cMap),
      tasks:
          tasksMap == null ? null : ServerCapabilitiesTasks.fromJson(tasksMap),
      elicitation: elicitationMap == null
          ? null
          : ServerCapabilitiesElicitation.fromJson(elicitationMap),
      extensions: extensionsMap,
      additionalCapabilities: _readAdditionalCapabilities(
        json,
        _serverCapabilityKeys,
        'ServerCapabilities',
      ),
    );
  }

  Map<String, dynamic> toJson({bool omitLegacyTasks = false}) => {
        if (experimental != null)
          'experimental': _serializeJsonObjectMap(
            experimental,
            'ServerCapabilities.experimental',
          ),
        if (logging != null)
          'logging': readJsonObject(logging, 'ServerCapabilities.logging'),
        if (prompts != null) 'prompts': prompts!.toJson(),
        if (resources != null) 'resources': resources!.toJson(),
        if (tools != null) 'tools': tools!.toJson(),
        if (completions != null) 'completions': completions!.toJson(),
        if (!omitLegacyTasks && tasks != null) 'tasks': tasks!.toJson(),
        if (extensions != null)
          'extensions': _serializeExtensionMap(
            extensions,
            'ServerCapabilities.extensions',
          ),
        ...?_serializeAdditionalCapabilities(
          additionalCapabilities,
          _serverCapabilityKeys,
          'ServerCapabilities.additionalCapabilities',
        ),
      };

  /// Whether the MCP Tasks extension is declared.
  bool get supportsTasksExtension =>
      extensions?.containsKey(mcpTasksExtensionId) ?? false;
}

/// Result data for a successful `initialize` request.
class InitializeResult implements BaseResultData {
  /// The protocol version the server wants to use.
  final String protocolVersion;

  /// The capabilities the server supports.
  final ServerCapabilities capabilities;

  /// Information about the server implementation.
  final Implementation serverInfo;

  /// Instructions describing how to use the server and its features.
  final String? instructions;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const InitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
    this.meta,
  });

  factory InitializeResult.fromJson(Map<String, dynamic> json) {
    final meta =
        readOptionalJsonObject(json['_meta'], 'InitializeResult._meta');
    return InitializeResult(
      protocolVersion: readRequiredString(
        json['protocolVersion'],
        'InitializeResult.protocolVersion',
      ),
      capabilities: ServerCapabilities.fromJson(
        readJsonObject(
          json['capabilities'],
          'InitializeResult.capabilities',
        ),
      ),
      serverInfo: Implementation.fromJson(
        readJsonObject(json['serverInfo'], 'InitializeResult.serverInfo'),
      ),
      instructions: readOptionalString(
        json['instructions'],
        'InitializeResult.instructions',
      ),
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'capabilities': capabilities.toJson(),
        'serverInfo': serverInfo.toJson(),
        if (instructions != null) 'instructions': instructions,
        if (meta != null)
          '_meta': readJsonObject(meta, 'InitializeResult._meta'),
      };
}

/// Result data for a successful `server/discover` request.
class DiscoverResult implements CacheableResultData {
  /// Result discriminator used by the MCP `2026-07-28` result model.
  final String resultType;

  /// Protocol versions supported by the server.
  final List<String> supportedVersions;

  /// Capabilities the server supports.
  final ServerCapabilities capabilities;

  /// Information about the server implementation.
  final Implementation serverInfo;

  /// Instructions describing how to use the server and its features.
  final String? instructions;

  /// How long, in milliseconds, the client may consider this result fresh.
  @override
  final int? ttlMs;

  /// Intended cache visibility: `public` or `private`.
  @override
  final String? cacheScope;

  /// Optional metadata.
  @override
  final Map<String, dynamic>? meta;

  const DiscoverResult({
    this.resultType = 'complete',
    required this.supportedVersions,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
    this.ttlMs,
    this.cacheScope,
    this.meta,
  });

  factory DiscoverResult.fromJson(Map<String, dynamic> json) {
    final resultType = readOptionalString(
      json['resultType'],
      'DiscoverResult.resultType',
    );
    if (resultType != resultTypeComplete) {
      throw const FormatException(
        'DiscoverResult.resultType must be complete',
      );
    }

    final supportedVersions = json['supportedVersions'];
    if (supportedVersions is! List) {
      throw const FormatException(
        'Missing or invalid supportedVersions for discover result',
      );
    }

    return DiscoverResult(
      supportedVersions: [
        for (final version in supportedVersions)
          readRequiredString(version, 'DiscoverResult.supportedVersions items'),
      ],
      capabilities: ServerCapabilities.fromJson(
        readJsonObject(json['capabilities'], 'DiscoverResult.capabilities'),
      ),
      serverInfo: Implementation.fromJson(
        readJsonObject(json['serverInfo'], 'DiscoverResult.serverInfo'),
      ),
      instructions: readOptionalString(
        json['instructions'],
        'DiscoverResult.instructions',
      ),
      ttlMs: readOptionalTtlMs(json['ttlMs'], 'DiscoverResult.ttlMs'),
      cacheScope: readOptionalCacheScope(
        json['cacheScope'],
        'DiscoverResult.cacheScope',
      ),
      meta: readOptionalJsonObject(json['_meta'], 'DiscoverResult._meta'),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    validateTtlMs(ttlMs, 'DiscoverResult.ttlMs');
    validateCacheScope(cacheScope, 'DiscoverResult.cacheScope');
    if (resultType != resultTypeComplete) {
      throw ArgumentError.value(
        resultType,
        'DiscoverResult.resultType',
        'must be complete',
      );
    }

    return {
      'resultType': resultType,
      'supportedVersions': supportedVersions,
      'capabilities': capabilities.toJson(omitLegacyTasks: true),
      'serverInfo': serverInfo.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (ttlMs != null) 'ttlMs': ttlMs,
      if (cacheScope != null) 'cacheScope': cacheScope,
      if (meta != null) '_meta': readJsonObject(meta, 'DiscoverResult._meta'),
    };
  }
}

/// Notification sent from the client to the server after initialization is finished.
class JsonRpcInitializedNotification extends JsonRpcNotification {
  const JsonRpcInitializedNotification({super.meta})
      : super(method: Method.notificationsInitialized);

  factory JsonRpcInitializedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    _expectJsonRpcMethod(
      json,
      Method.notificationsInitialized,
      'JsonRpcInitializedNotification',
    );
    _readOptionalParamsObject(
      json,
      'JsonRpcInitializedNotification.params',
    );
    return JsonRpcInitializedNotification(meta: extractRequestMeta(json));
  }
}

/// Deprecated alias for [InitializeRequest].
@Deprecated('Use InitializeRequest instead')
typedef InitializeRequestParams = InitializeRequest;
