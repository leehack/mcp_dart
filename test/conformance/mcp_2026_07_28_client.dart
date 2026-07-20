import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

const _clientInfo = Implementation(
  name: 'mcp-dart-2026-07-28-conformance-client',
  version: '0.0.0',
);

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    _printUsage();
    return;
  }

  final serverUrl = Uri.parse(args.last);
  final scenario = Platform.environment['MCP_CONFORMANCE_SCENARIO'];
  final protocolVersion =
      Platform.environment['MCP_CONFORMANCE_PROTOCOL_VERSION'] ??
          previewProtocolVersion;
  final context = _readContext();

  switch (scenario) {
    case 'initialize':
      await _withClient(serverUrl, protocolVersion: protocolVersion);
    case 'tools_call':
      if (isStatelessProtocolVersion(protocolVersion)) {
        final client = _RawStatelessClient(serverUrl, protocolVersion);
        try {
          await client.request(Method.serverDiscover, const {});
          await client.listTools();
          await client.callTool(
            'add_numbers',
            arguments: const {'a': 2, 'b': 3},
          );
        } finally {
          client.close();
        }
      } else {
        await _withClient(
          serverUrl,
          protocolVersion: protocolVersion,
          action: (client) async {
            await client.listTools();
            await client.callTool(
              const CallToolRequest(
                name: 'add_numbers',
                arguments: {'a': 2, 'b': 3},
              ),
            );
          },
        );
      }
    case 'elicitation-sep1034-client-defaults':
      await _runElicitationDefaults(serverUrl, protocolVersion);
    case 'request-metadata':
      await _runRequestMetadata(serverUrl, protocolVersion);
    case 'sep-2322-client-request-state':
      await _runMrtrRequestState(serverUrl, protocolVersion);
    case 'http-standard-headers':
      await _runStandardHeaders(serverUrl, protocolVersion);
    case 'http-custom-headers':
      await _runCustomHeaders(serverUrl, protocolVersion, context);
    case 'http-invalid-tool-headers':
      await _runInvalidToolHeaders(serverUrl, protocolVersion);
    case 'json-schema-ref-no-deref':
      await _runSchemaRefNoDeref(serverUrl, protocolVersion);
    case 'sse-retry':
      await _withClient(
        serverUrl,
        protocolVersion: protocolVersion,
        action: (client) async {
          await client.listTools();
          await client.callTool(
            const CallToolRequest(name: 'test_reconnection'),
            options: const RequestOptions(timeout: Duration(seconds: 5)),
          );
        },
      );
    default:
      if (scenario != null && scenario.startsWith('auth/')) {
        await _runAuthScenario(serverUrl, protocolVersion, scenario, context);
      } else {
        stderr.writeln('Unsupported conformance client scenario: $scenario');
      }
  }
  exit(0);
}

const _draftCapabilities = ClientCapabilities(
  roots: ClientCapabilitiesRoots(listChanged: true),
  sampling: ClientCapabilitiesSampling(tools: true),
  elicitation: ClientElicitation(
    form: ClientElicitationForm(applyDefaults: true),
  ),
);

Map<String, dynamic> _readContext() {
  final raw = Platform.environment['MCP_CONFORMANCE_CONTEXT'];
  if (raw == null || raw.isEmpty) {
    return const {};
  }
  final decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic> ? decoded : const {};
}

Future<void> _withClient(
  Uri serverUrl, {
  required String protocolVersion,
  ClientCapabilities capabilities = const ClientCapabilities(),
  Future<void> Function(McpClient client)? action,
}) async {
  final transport = StreamableHttpClientTransport(serverUrl);
  final client = McpClient(
    _clientInfo,
    options: McpClientOptions(
      capabilities: capabilities,
      protocolVersion: protocolVersion,
      useServerDiscover: isStatelessProtocolVersion(protocolVersion),
    ),
  );
  if (capabilities.roots != null) {
    client.setRequestHandler<JsonRpcListRootsRequest>(
      Method.rootsList,
      (request, extra) async => ListRootsResult(
        roots: [Root(uri: Directory.current.uri.toString(), name: 'workspace')],
      ),
      (id, params, meta) => JsonRpcListRootsRequest(id: id, meta: meta),
    );
  }
  client.onSamplingRequest = (params) async {
    final firstText = params.messages
        .expand((message) => message.contentBlocks)
        .whereType<SamplingTextContent>()
        .map((content) => content.text)
        .firstOrNull;
    return CreateMessageResult(
      role: SamplingMessageRole.assistant,
      model: 'mcp-dart-conformance-model',
      content: SamplingTextContent(text: firstText ?? 'ok'),
    );
  };
  client.onElicitRequest = (params) async {
    final content = <String, dynamic>{};
    return ElicitResult(action: 'accept', content: content);
  };

  try {
    await client.connect(transport);
    await action?.call(client);
  } finally {
    await client.close();
  }
}

Future<void> _runElicitationDefaults(
  Uri serverUrl,
  String protocolVersion,
) async {
  await _withClient(
    serverUrl,
    protocolVersion: protocolVersion,
    capabilities: const ClientCapabilities(
      elicitation: ClientElicitation(
        form: ClientElicitationForm(applyDefaults: true),
      ),
    ),
    action: (client) async {
      await client.listTools();
      await client.callTool(
        const CallToolRequest(name: 'test_client_elicitation_defaults'),
      );
    },
  );
}

Future<void> _runMrtrRequestState(Uri serverUrl, String protocolVersion) async {
  final client = _RawStatelessClient(serverUrl, protocolVersion);
  await client.callToolResolvingInputRequired('test_mrtr_echo_state');
  await client.callToolResolvingInputRequired('test_mrtr_no_state');
  await client.callTool('test_mrtr_unrelated');
  await client.callToolResolvingInputRequired('test_mrtr_no_result_type');
}

Future<void> _runRequestMetadata(Uri serverUrl, String protocolVersion) async {
  await _RawStatelessClient(
    serverUrl,
    defaultProtocolVersion,
  ).request(Method.serverDiscover, const {});
  await _RawStatelessClient(
    serverUrl,
    protocolVersion,
  ).request(Method.serverDiscover, const {});
}

Future<void> _runStandardHeaders(Uri serverUrl, String protocolVersion) async {
  final transport = await _startedTransport(serverUrl, protocolVersion);
  try {
    await transport.send(
      JsonRpcInitializeRequest(
        id: 1,
        initParams: InitializeRequest(
          protocolVersion: protocolVersion,
          capabilities: _draftCapabilities,
          clientInfo: _clientInfo,
        ),
      ),
    );
    await transport.send(const JsonRpcInitializedNotification());
    await transport.send(const JsonRpcListToolsRequest(id: 2));
    await transport.send(
      JsonRpcCallToolRequest(
        id: 3,
        params: const CallToolRequest(name: 'test_headers').toJson(),
      ),
    );
    await transport.send(JsonRpcListResourcesRequest(id: 4));
    await transport.send(
      JsonRpcReadResourceRequest(
        id: 5,
        readParams: const ReadResourceRequest(
          uri: 'file:///path/to/file%20name.txt',
        ),
      ),
    );
    await transport.send(JsonRpcListPromptsRequest(id: 6));
    await transport.send(
      JsonRpcGetPromptRequest(
        id: 7,
        getParams: const GetPromptRequest(name: 'test_prompt'),
      ),
    );
  } finally {
    await transport.close();
  }
}

Future<void> _runCustomHeaders(
  Uri serverUrl,
  String protocolVersion,
  Map<String, dynamic> context,
) async {
  final transport = await _startedTransport(serverUrl, protocolVersion);
  transport.setToolParameterHeaderMappings(const {
    'test_custom_headers': {
      'region': 'Region',
      'priority': 'Priority',
      'verbose': 'Verbose',
      'debug': 'Debug',
      'empty_val': 'EmptyVal',
      'method_val': 'Method',
      'non_ascii_val': 'NonAscii',
      'whitespace_val': 'Whitespace',
      'leading_space_val': 'LeadingSpace',
      'trailing_space_val': 'TrailingSpace',
      'internal_space_val': 'InternalSpace',
      'control_char_val': 'ControlChar',
      'crlf_val': 'CrLf',
      'tab_val': 'Tab',
    },
    'test_custom_headers_null': {
      'region': 'Region',
      'priority': 'Priority',
      'verbose': 'Verbose',
    },
  });

  try {
    await transport.send(
      JsonRpcInitializeRequest(
        id: 1,
        initParams: InitializeRequest(
          protocolVersion: protocolVersion,
          capabilities: _draftCapabilities,
          clientInfo: _clientInfo,
        ),
      ),
    );
    await transport.send(const JsonRpcInitializedNotification());
    await transport.send(const JsonRpcListToolsRequest(id: 2));

    final toolCalls = context['toolCalls'];
    if (toolCalls is List) {
      var id = 3;
      for (final call in toolCalls.whereType<Map>()) {
        final name = call['name'];
        if (name is! String) {
          continue;
        }
        final arguments = call['arguments'];
        await transport.send(
          JsonRpcCallToolRequest(
            id: id++,
            params: CallToolRequest(
              name: name,
              arguments: arguments is Map
                  ? arguments.cast<String, dynamic>()
                  : const {},
            ).toJson(),
          ),
        );
      }
    }
  } finally {
    await transport.close();
  }
}

Future<void> _runInvalidToolHeaders(
  Uri serverUrl,
  String protocolVersion,
) async {
  final transport = await _startedTransport(serverUrl, protocolVersion);
  transport.setToolParameterHeaderMappings(const {
    'valid_tool': {'region': 'Region'},
  });
  try {
    await transport.send(
      JsonRpcInitializeRequest(
        id: 1,
        initParams: InitializeRequest(
          protocolVersion: protocolVersion,
          capabilities: _draftCapabilities,
          clientInfo: _clientInfo,
        ),
      ),
    );
    await transport.send(const JsonRpcInitializedNotification());
    await transport.send(const JsonRpcListToolsRequest(id: 2));
    await transport.send(
      JsonRpcCallToolRequest(
        id: 3,
        params: const CallToolRequest(
          name: 'valid_tool',
          arguments: {'region': 'us-west1'},
        ).toJson(),
      ),
    );
  } finally {
    await transport.close();
  }
}

Future<void> _runSchemaRefNoDeref(
  Uri serverUrl,
  String protocolVersion,
) async {
  final transport = await _startedTransport(serverUrl, protocolVersion);
  try {
    await transport.send(
      JsonRpcInitializeRequest(
        id: 1,
        initParams: InitializeRequest(
          protocolVersion: protocolVersion,
          capabilities: _draftCapabilities,
          clientInfo: _clientInfo,
        ),
      ),
    );
    await transport.send(const JsonRpcInitializedNotification());
    await transport.send(const JsonRpcListToolsRequest(id: 2));
  } finally {
    await transport.close();
  }
}

Future<void> _runAuthScenario(
  Uri serverUrl,
  String protocolVersion,
  String scenario,
  Map<String, dynamic> context,
) async {
  final provider = _ConformanceOAuthProvider(scenario, context);
  final client = _RawOAuthClient(serverUrl, protocolVersion, provider);
  const allowClientErrorScenarios = {
    'auth/resource-mismatch',
    'auth/scope-retry-limit',
    'auth/iss-supported-missing',
    'auth/iss-wrong-issuer',
    'auth/iss-unexpected',
    'auth/iss-normalized',
    'auth/metadata-issuer-mismatch',
  };

  try {
    await client.start();
    await client.initialize(
      maxAuthAttempts: scenario == 'auth/scope-retry-limit' ? 1 : 4,
    );

    switch (scenario) {
      case 'auth/authorization-server-migration':
        await client.callTool('test-tool');
        await client.callTool('test-tool');
      case 'auth/scope-step-up':
        await client.listTools();
        await client.callTool('test-tool');
      case 'auth/scope-retry-limit':
        try {
          await client.listTools(maxAuthAttempts: 1);
        } catch (_) {
          // The scenario only needs to observe a bounded number of auth
          // retries; the server intentionally never grants the scope.
        }
      default:
        await client.listTools();
        await client.callTool('test-tool');
    }
  } catch (error) {
    if (!allowClientErrorScenarios.contains(scenario)) {
      rethrow;
    }
  } finally {
    await client.close();
  }
}

Future<StreamableHttpClientTransport> _startedTransport(
  Uri serverUrl,
  String protocolVersion,
) async {
  final transport = StreamableHttpClientTransport(serverUrl);
  transport.protocolVersion = protocolVersion;
  await transport.start();
  return transport;
}

class _RawStatelessClient {
  final Uri serverUrl;
  final String protocolVersion;
  final HttpClient _httpClient = HttpClient();
  var _nextId = 1;

  _RawStatelessClient(this.serverUrl, this.protocolVersion);

  void close() {
    _httpClient.close(force: true);
  }

  Future<Map<String, dynamic>> listTools() {
    return request(Method.toolsList, const {});
  }

  Future<Map<String, dynamic>> callTool(
    String name, {
    Map<String, dynamic> arguments = const {},
    InputResponses? inputResponses,
    String? requestState,
  }) {
    return request(
      Method.toolsCall,
      {
        'name': name,
        'arguments': arguments,
        if (inputResponses != null)
          'inputResponses': InputResponse.mapToJson(inputResponses),
        if (requestState != null) 'requestState': requestState,
      },
    );
  }

  Future<Map<String, dynamic>> callToolResolvingInputRequired(
    String name,
  ) async {
    InputResponses? inputResponses;
    String? requestState;
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = await callTool(
        name,
        inputResponses: inputResponses,
        requestState: requestState,
      );
      final result = response['result'];
      if (result is! Map<String, dynamic> ||
          result['resultType'] != resultTypeInputRequired) {
        return response;
      }

      final inputRequired = InputRequiredResult.fromJson(result);
      inputResponses = _resolveInputRequests(inputRequired.inputRequests);
      requestState = inputRequired.requestState;
    }
    throw StateError('Exceeded input_required retries for $name');
  }

  InputResponses? _resolveInputRequests(InputRequests? inputRequests) {
    if (inputRequests == null) {
      return null;
    }
    return {
      for (final entry in inputRequests.entries)
        entry.key: InputResponse.fromResult(_resolveInputRequest(entry.value)),
    };
  }

  BaseResultData _resolveInputRequest(InputRequest request) {
    return switch (request.method) {
      Method.elicitationCreate => const ElicitResult(
          action: 'accept',
          content: {'confirmed': true},
        ),
      Method.samplingCreateMessage => const CreateMessageResult(
          role: SamplingMessageRole.assistant,
          model: 'mcp-dart-conformance-model',
          content: SamplingTextContent(text: 'ok'),
        ),
      Method.rootsList => ListRootsResult(
          roots: [Root(uri: Directory.current.uri.toString())],
        ),
      _ =>
        throw UnsupportedError('Unsupported input request ${request.method}'),
    };
  }

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = _nextId++;
    final request = await _httpClient.postUrl(serverUrl);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('MCP-Protocol-Version', protocolVersion);
    request.headers.set('Mcp-Method', method);
    final name = _mcpName(method, params);
    if (name != null) {
      request.headers.set('Mcp-Name', name);
    }
    request.write(
      jsonEncode({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': method,
        'params': {
          ...params,
          '_meta': buildProtocolRequestMeta(
            protocolVersion: protocolVersion,
            clientInfo: _clientInfo,
            clientCapabilities: _draftCapabilities,
          ),
        },
      }),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (body.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Expected JSON object response, got $decoded');
    }
    return decoded;
  }

  String? _mcpName(String method, Map<String, dynamic> params) {
    return switch (method) {
      Method.toolsCall => params['name'] as String?,
      Method.promptsGet => params['name'] as String?,
      Method.resourcesRead => params['uri'] as String?,
      _ => null,
    };
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run test/conformance/mcp_2026_07_28_client.dart <server-url>',
  );
}

class _AuthorizationRedirect {
  final String code;
  final String? state;
  final String? issuer;

  const _AuthorizationRedirect({
    required this.code,
    required this.state,
    required this.issuer,
  });
}

class _ConformanceOAuthProvider implements OAuthAuthorizationCodeProvider {
  static const _clientMetadataDocumentUrl =
      'https://conformance-test.local/client-metadata.json';

  final String scenario;
  final Map<String, dynamic> context;
  OAuthTokens? _tokens;
  _AuthorizationRedirect? _redirect;

  _ConformanceOAuthProvider(this.scenario, this.context);

  @override
  String get clientId {
    final contextClientId = context['client_id'];
    if (contextClientId is String && contextClientId.isNotEmpty) {
      return contextClientId;
    }
    if (scenario == 'auth/basic-cimd') {
      return _clientMetadataDocumentUrl;
    }
    // An empty ID explicitly selects deprecated Dynamic Client Registration.
    // Supplying a non-empty ID means the credentials are pre-registered and
    // must take priority over CIMD and DCR.
    return '';
  }

  @override
  Uri get redirectUri => Uri.parse('http://127.0.0.1/oauth/callback');

  @override
  String? get clientSecret {
    final contextClientSecret = context['client_secret'];
    return contextClientSecret is String ? contextClientSecret : null;
  }

  @override
  List<String> get scopes => const [];

  @override
  Future<OAuthTokens?> tokens() async => _tokens;

  @override
  Future<void> redirectToAuthorization() async {
    throw UnauthorizedError('Authorization-code redirect is required');
  }

  @override
  Future<void> redirectToAuthorizationUrl(Uri authorizationUri) async {
    _redirect = await _performAuthorizationRedirect(authorizationUri);
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    _tokens = tokens;
  }

  _AuthorizationRedirect takeRedirect() {
    final redirect = _redirect;
    if (redirect == null) {
      throw UnauthorizedError('Authorization redirect did not return a code');
    }
    _redirect = null;
    return redirect;
  }

  Future<_AuthorizationRedirect> _performAuthorizationRedirect(Uri uri) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw UnauthorizedError(
          'Authorization endpoint did not redirect with a code',
        );
      }
      final redirectUri = uri.resolve(location);
      final code = redirectUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw UnauthorizedError('Authorization redirect did not include code');
      }
      return _AuthorizationRedirect(
        code: code,
        state: redirectUri.queryParameters['state'],
        issuer: redirectUri.queryParameters['iss'],
      );
    } finally {
      httpClient.close(force: true);
    }
  }
}

class _RawOAuthClient {
  final Uri serverUrl;
  final String protocolVersion;
  final _ConformanceOAuthProvider authProvider;
  late final StreamableHttpClientTransport transport;
  final Map<Object, Completer<JsonRpcMessage>> _pending = {};
  var _nextId = 1;

  _RawOAuthClient(this.serverUrl, this.protocolVersion, this.authProvider);

  Future<void> start() async {
    transport = StreamableHttpClientTransport(
      serverUrl,
      opts: StreamableHttpClientTransportOptions(authProvider: authProvider),
    );
    transport.protocolVersion = protocolVersion;
    transport.onmessage = (message) {
      switch (message) {
        case JsonRpcResponse(:final id):
          _pending.remove(id)?.complete(message);
        case JsonRpcError(:final id) when id != null:
          _pending.remove(id)?.complete(message);
        default:
          break;
      }
    };
    await transport.start();
  }

  Future<void> close() => transport.close();

  Future<void> initialize({
    int maxAuthAttempts = 4,
  }) async {
    if (isStatelessProtocolVersion(protocolVersion)) {
      await _request(
        JsonRpcRequest(
          id: _nextId++,
          method: Method.serverDiscover,
          meta: _requestMeta(),
        ),
        maxAuthAttempts: maxAuthAttempts,
      );
    } else {
      await _request(
        JsonRpcInitializeRequest(
          id: _nextId++,
          initParams: InitializeRequest(
            protocolVersion: protocolVersion,
            capabilities: _draftCapabilities,
            clientInfo: _clientInfo,
          ),
        ),
      );
      await transport.send(const JsonRpcInitializedNotification());
    }
  }

  Future<Map<String, dynamic>> listTools({
    int maxAuthAttempts = 4,
  }) {
    return _request(
      JsonRpcListToolsRequest(
        id: _nextId++,
        meta: _requestMeta(),
      ),
      maxAuthAttempts: maxAuthAttempts,
    );
  }

  Future<Map<String, dynamic>> callTool(
    String name, {
    int maxAuthAttempts = 4,
  }) {
    return _request(
      JsonRpcCallToolRequest(
        id: _nextId++,
        params: CallToolRequest(name: name).toJson(),
        meta: _requestMeta(),
      ),
      maxAuthAttempts: maxAuthAttempts,
    );
  }

  Map<String, dynamic>? _requestMeta() {
    if (!isStatelessProtocolVersion(protocolVersion)) {
      return null;
    }
    return buildProtocolRequestMeta(
      protocolVersion: protocolVersion,
      clientInfo: _clientInfo,
      clientCapabilities: _draftCapabilities,
    );
  }

  Future<Map<String, dynamic>> _request(
    JsonRpcRequest request, {
    int maxAuthAttempts = 4,
  }) async {
    var authAttempts = 0;
    while (true) {
      final completer = Completer<JsonRpcMessage>();
      _pending[request.id] = completer;
      try {
        await transport.send(request);
      } on UnauthorizedError {
        _pending.remove(request.id);
        if (authAttempts >= maxAuthAttempts) {
          rethrow;
        }
        authAttempts += 1;
        await _finishAuth();
        continue;
      } catch (_) {
        _pending.remove(request.id);
        rethrow;
      }

      final message = await completer.future.timeout(
        const Duration(seconds: 8),
      );
      switch (message) {
        case JsonRpcResponse(:final result):
          return result;
        case JsonRpcError(:final error):
          throw McpError(error.code, error.message, error.data);
        default:
          throw StateError('Unexpected response message $message');
      }
    }
  }

  Future<void> _finishAuth() async {
    final redirect = authProvider.takeRedirect();
    await transport.finishAuthRedirect(
      redirect.code,
      state: redirect.state!,
      issuer: redirect.issuer,
    );
  }
}
