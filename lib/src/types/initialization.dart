import 'json_rpc.dart';

/// Describes the name and version of an MCP implementation (client or server).
class Implementation {
  /// The name of the implementation.
  final String name;

  /// The version string of the implementation.
  final String version;

  /// A description of the implementation.
  final String? description;

  const Implementation({
    required this.name,
    required this.version,
    this.description,
  });

  factory Implementation.fromJson(Map<String, dynamic> json) {
    return Implementation(
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        if (description != null) 'description': description,
      };
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
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
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
      applyDefaults: json['applyDefaults'] as bool?,
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

    final formMap = (json['form'] as Map?)?.cast<String, dynamic>();
    final urlMap = (json['url'] as Map?)?.cast<String, dynamic>();

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
  /// Whether the client supports sampling with tools.
  final bool tools;

  const ClientCapabilitiesSampling({this.tools = false});

  factory ClientCapabilitiesSampling.fromJson(Map<String, dynamic> json) {
    return ClientCapabilitiesSampling(
      tools: json['tools'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (tools) 'tools': tools,
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
    final createMap = json['create'] as Map<String, dynamic>?;
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
    final createMessageMap = json['createMessage'] as Map<String, dynamic>?;
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
    final elicitationMap = json['elicitation'] as Map<String, dynamic>?;
    final samplingMap = json['sampling'] as Map<String, dynamic>?;

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
    final requestsMap = json['requests'] as Map<String, dynamic>?;
    return ClientCapabilitiesTasks(
      cancel: json['cancel'] as bool?,
      list: json['list'] as bool?,
      requests: requestsMap == null
          ? null
          : ClientCapabilitiesTasksRequests.fromJson(requestsMap),
    );
  }

  Map<String, dynamic> toJson() => {
        if (cancel != null) 'cancel': cancel,
        if (list != null) 'list': list,
        if (requests != null) 'requests': requests!.toJson(),
      };
}

/// Capabilities a client may support.
class ClientCapabilities {
  /// Experimental, non-standard capabilities.
  final Map<String, dynamic>? experimental;

  /// Present if the client supports sampling (`sampling/createMessage`).
  final ClientCapabilitiesSampling? sampling;

  /// Present if the client supports listing roots (`roots/list`).
  final ClientCapabilitiesRoots? roots;

  /// Present if the client supports elicitation (`elicitation/create`).
  final ClientElicitation? elicitation;

  /// Present if the client supports tasks (`tasks/list`, `tasks/requests`, etc).
  final ClientCapabilitiesTasks? tasks;

  const ClientCapabilities({
    this.experimental,
    this.sampling,
    this.roots,
    this.elicitation,
    this.tasks,
  });

  factory ClientCapabilities.fromJson(Map<String, dynamic> json) {
    final rootsMap = json['roots'] as Map<String, dynamic>?;
    final elicitationMap = json['elicitation'] as Map<String, dynamic>?;
    final tasksMap = json['tasks'] as Map<String, dynamic>?;
    final samplingMap = json['sampling'] as Map<String, dynamic>?;

    return ClientCapabilities(
      experimental: json['experimental'] as Map<String, dynamic>?,
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
    );
  }

  Map<String, dynamic> toJson() => {
        if (experimental != null) 'experimental': experimental,
        if (sampling != null) 'sampling': sampling!.toJson(),
        if (roots != null) 'roots': roots!.toJson(),
        if (elicitation != null) 'elicitation': elicitation!.toJson(),
        if (tasks != null) 'tasks': tasks!.toJson(),
      };
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
        protocolVersion: json['protocolVersion'] as String,
        capabilities: ClientCapabilities.fromJson(
          json['capabilities'] as Map<String, dynamic>,
        ),
        clientInfo: Implementation.fromJson(
          json['clientInfo'] as Map<String, dynamic>,
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
    final paramsMap = json['params'] as Map<String, dynamic>?;
    if (paramsMap == null) {
      throw const FormatException("Missing params for initialize request");
    }
    final meta = paramsMap['_meta'] as Map<String, dynamic>?;
    return JsonRpcInitializeRequest(
      id: json['id'],
      initParams: InitializeRequest.fromJson(paramsMap),
      meta: meta,
    );
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
    final formMap = json['form'] as Map<String, dynamic>?;
    final urlMap = json['url'] as Map<String, dynamic>?;

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
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to resources.
class ServerCapabilitiesResources {
  /// Whether the server supports `resources/subscribe` and `resources/unsubscribe`.
  final bool? subscribe;

  /// Whether the server supports `notifications/resources/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesResources({
    this.subscribe,
    this.listChanged,
  });

  factory ServerCapabilitiesResources.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesResources(
      subscribe: json['subscribe'] as bool?,
      listChanged: json['listChanged'] as bool?,
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
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to completions.
class ServerCapabilitiesCompletions {
  /// Whether the server supports `notifications/completions/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesCompletions({
    this.listChanged,
  });

  factory ServerCapabilitiesCompletions.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesCompletions(
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Describes capabilities related to tasks.
class ServerCapabilitiesTasks {
  /// Whether the server supports `notifications/tasks/list_changed`.
  final bool? listChanged;

  const ServerCapabilitiesTasks({
    this.listChanged,
  });

  factory ServerCapabilitiesTasks.fromJson(Map<String, dynamic> json) {
    return ServerCapabilitiesTasks(
      listChanged: json['listChanged'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (listChanged != null) 'listChanged': listChanged,
      };
}

/// Capabilities a server may support.
class ServerCapabilities {
  /// Experimental, non-standard capabilities.
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
  final ServerCapabilitiesElicitation? elicitation;

  const ServerCapabilities({
    this.experimental,
    this.logging,
    this.prompts,
    this.resources,
    this.tools,
    this.completions,
    this.tasks,
    this.elicitation,
  });

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    final pMap = json['prompts'] as Map<String, dynamic>?;
    final rMap = json['resources'] as Map<String, dynamic>?;
    final cMap = json['completions'] as Map<String, dynamic>?;
    final tMap = json['tools'] as Map<String, dynamic>?;
    final tasksMap = json['tasks'] as Map<String, dynamic>?;
    final elicitationMap = json['elicitation'] as Map<String, dynamic>?;

    return ServerCapabilities(
      experimental: json['experimental'] as Map<String, dynamic>?,
      logging: json['logging'] as Map<String, dynamic>?,
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
    );
  }

  Map<String, dynamic> toJson() => {
        if (experimental != null) 'experimental': experimental,
        if (logging != null) 'logging': logging,
        if (prompts != null) 'prompts': prompts!.toJson(),
        if (resources != null) 'resources': resources!.toJson(),
        if (tools != null) 'tools': tools!.toJson(),
        if (completions != null) 'completions': completions!.toJson(),
        if (tasks != null) 'tasks': tasks!.toJson(),
        if (elicitation != null) 'elicitation': elicitation!.toJson(),
      };
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
    final meta = json['_meta'] as Map<String, dynamic>?;
    return InitializeResult(
      protocolVersion: json['protocolVersion'] as String,
      capabilities: ServerCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>,
      ),
      serverInfo: Implementation.fromJson(
        json['serverInfo'] as Map<String, dynamic>,
      ),
      instructions: json['instructions'] as String?,
      meta: meta,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'capabilities': capabilities.toJson(),
        'serverInfo': serverInfo.toJson(),
        if (instructions != null) 'instructions': instructions,
      };
}

/// Notification sent from the client to the server after initialization is finished.
class JsonRpcInitializedNotification extends JsonRpcNotification {
  const JsonRpcInitializedNotification()
      : super(method: Method.notificationsInitialized);

  factory JsonRpcInitializedNotification.fromJson(Map<String, dynamic> json) =>
      const JsonRpcInitializedNotification();
}

/// Deprecated alias for [InitializeRequest].
@Deprecated('Use InitializeRequest instead')
typedef InitializeRequestParams = InitializeRequest;
