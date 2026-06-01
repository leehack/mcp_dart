import 'dart:async';
import 'dart:math';

import 'package:mcp_dart/mcp_dart.dart';

const String _fixtureSuite = 'fixture';
const String _specSuite = 'spec';
const String _allSuites = 'all';

const List<String> conformanceSuiteNames = <String>[
  _fixtureSuite,
  _specSuite,
  _allSuites,
];

/// Result of running one conformance case.
class ConformanceCaseResult {
  final String suite;
  final String name;
  final String description;
  final bool passed;
  final String? diagnostic;

  const ConformanceCaseResult({
    required this.suite,
    required this.name,
    required this.description,
    required this.passed,
    this.diagnostic,
  });

  Map<String, dynamic> toJson() => {
        'suite': suite,
        'name': name,
        'description': description,
        'passed': passed,
        if (diagnostic != null) 'diagnostic': diagnostic,
      };
}

/// Result of running a conformance suite.
class ConformanceSuiteResult {
  final List<ConformanceCaseResult> cases;

  const ConformanceSuiteResult(this.cases);

  int get total => cases.length;
  int get passedCount => cases.where((result) => result.passed).length;
  int get failedCount => total - passedCount;
  bool get passed => failedCount == 0;
  List<String> get caseNames => [for (final result in cases) result.name];

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'total': total,
        'passedCount': passedCount,
        'failedCount': failedCount,
        'cases': [for (final result in cases) result.toJson()],
      };
}

typedef _ConformanceCheck = Future<void> Function();

class _ConformanceCase {
  final String suite;
  final String name;
  final String description;
  final _ConformanceCheck check;

  const _ConformanceCase({
    required this.suite,
    required this.name,
    required this.description,
    required this.check,
  });
}

/// Runs the built-in MCP conformance fixture checks.
class ConformanceRunner {
  final List<_ConformanceCase> _fixtureCases;
  final List<_ConformanceCase> _specCases;

  ConformanceRunner()
      : _fixtureCases = <_ConformanceCase>[
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-invalid-version',
            description:
                'Rejects JSON-RPC messages whose jsonrpc version is not 2.0.',
            check: _rejectsInvalidJsonRpcVersion,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-malformed-message',
            description:
                'Rejects JSON-RPC envelopes without a method, result, or error member.',
            check: _rejectsMalformedJsonRpcMessage,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-result-error-response',
            description:
                'Rejects JSON-RPC responses that include both result and error members.',
            check: _rejectsResultErrorJsonRpcResponse,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.preserves-string-response-id',
            description:
                'Parses and serializes successful responses with string JSON-RPC IDs.',
            check: _preservesStringResponseId,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.preserves-numeric-response-id',
            description:
                'Parses and serializes successful responses with numeric JSON-RPC IDs.',
            check: _preservesNumericResponseId,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.preserves-string-progress-token',
            description:
                'Parses and serializes progress notifications with string progress tokens.',
            check: _preservesStringProgressToken,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.preserves-numeric-progress-token',
            description:
                'Parses and serializes progress notifications with numeric progress tokens.',
            check: _preservesNumericProgressToken,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'protocol-version.advertises-latest-2025-11-25',
            description:
                'Advertises MCP 2025-11-25 as the latest supported protocol version.',
            check: _advertisesLatestProtocolVersion,
          ),
        ],
        _specCases = <_ConformanceCase>[
          _ConformanceCase(
            suite: _specSuite,
            name: 'lifecycle.rejects-pre-initialize-request',
            description:
                'Rejects operation requests before the initialize handshake.',
            check: _rejectsPreInitializeRequest,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'capabilities.rejects-unnegotiated-sampling-tools',
            description:
                'Rejects sampling/createMessage tool-use when sampling.tools was not negotiated.',
            check: _rejectsUnnegotiatedSamplingTools,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'elicitation.rejects-invalid-form-url-union',
            description:
                'Rejects elicitation/create payloads that mix form and URL variants.',
            check: _rejectsInvalidElicitationVariantPayload,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'tasks.strips-unnegotiated-related-task-metadata',
            description:
                'Strips related-task metadata from non-task tool calls when task augmentation was not negotiated.',
            check: _stripsUnnegotiatedRelatedTaskMetadata,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'progress.rejects-malformed-progress-token',
            description:
                'Rejects progress notifications whose progressToken is not a string or finite number.',
            check: _rejectsMalformedProgressToken,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'progress.dispatches-numeric-progress-token',
            description:
                'Dispatches progress notifications for finite numeric progress tokens.',
            check: _dispatchesNumericProgressToken,
          ),
        ];

  /// Runs one named conformance suite.
  Future<ConformanceSuiteResult> runSuite({
    required String suite,
    String? filter,
  }) {
    return switch (suite) {
      _fixtureSuite => runFixtureSuite(filter: filter),
      _specSuite => runSpecSuite(filter: filter),
      _allSuites => runAllSuites(filter: filter),
      _ => throw ArgumentError.value(
          suite,
          'suite',
          'Expected one of: ${conformanceSuiteNames.join(', ')}',
        ),
    };
  }

  /// Runs the built-in fixture suite.
  ///
  /// When [filter] is provided, only exact case-name matches run. Exact matching
  /// keeps CI diagnostics deterministic and prevents accidental broad filters.
  Future<ConformanceSuiteResult> runFixtureSuite({String? filter}) async {
    return _runCases(_fixtureCases, filter: filter);
  }

  /// Runs MCP 2025-11-25 spec-critical raw-wire behavior checks.
  Future<ConformanceSuiteResult> runSpecSuite({String? filter}) {
    return _runCases(_specCases, filter: filter);
  }

  /// Runs all non-fuzz conformance cases.
  Future<ConformanceSuiteResult> runAllSuites({String? filter}) {
    return _runCases([..._fixtureCases, ..._specCases], filter: filter);
  }

  Future<ConformanceSuiteResult> _runCases(
    List<_ConformanceCase> cases, {
    String? filter,
  }) async {
    final selectedCases = filter == null
        ? cases
        : cases.where((testCase) => testCase.name == filter).toList();

    final results = <ConformanceCaseResult>[];
    for (final testCase in selectedCases) {
      try {
        await testCase.check();
        results.add(
          ConformanceCaseResult(
            suite: testCase.suite,
            name: testCase.name,
            description: testCase.description,
            passed: true,
          ),
        );
      } catch (error) {
        results.add(
          ConformanceCaseResult(
            suite: testCase.suite,
            name: testCase.name,
            description: testCase.description,
            passed: false,
            diagnostic: error.toString(),
          ),
        );
      }
    }

    return ConformanceSuiteResult(results);
  }

  /// Runs deterministic parser-fuzz checks against generated JSON-RPC envelopes.
  Future<ConformanceSuiteResult> runFuzzSuite({
    int iterations = 32,
    int seed = 0,
  }) async {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'must be positive');
    }

    final random = Random(seed);
    final results = <ConformanceCaseResult>[];
    for (var index = 0; index < iterations; index += 1) {
      final fixture = _generatedJsonRpcFixture(random, index);
      try {
        fixture.expectation(fixture.message);
        results.add(
          ConformanceCaseResult(
            suite: 'fuzz',
            name: fixture.name,
            description: fixture.description,
            passed: true,
          ),
        );
      } catch (error) {
        results.add(
          ConformanceCaseResult(
            suite: 'fuzz',
            name: fixture.name,
            description: fixture.description,
            passed: false,
            diagnostic: 'Payload: ${fixture.message}; error: $error',
          ),
        );
      }
    }

    return ConformanceSuiteResult(results);
  }
}

class _GeneratedJsonRpcFixture {
  final String name;
  final String description;
  final Map<String, dynamic> message;
  final void Function(Map<String, dynamic> message) expectation;

  const _GeneratedJsonRpcFixture({
    required this.name,
    required this.description,
    required this.message,
    required this.expectation,
  });
}

_GeneratedJsonRpcFixture _generatedJsonRpcFixture(Random random, int index) {
  final numericId = random.nextInt(1000000);
  final numericIdValue =
      random.nextBool() ? numericId : numericId + random.nextDouble();
  final stringId = 'req-${random.nextInt(1000000)}';
  final progressToken =
      random.nextBool() ? numericIdValue : 'progress-$numericId';

  return switch (random.nextInt(6)) {
    0 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.invalid-version.$index',
        description:
            'Generated request with an invalid JSON-RPC version is rejected.',
        message: <String, dynamic>{
          'jsonrpc': '2.${random.nextInt(9) + 1}',
          'id': random.nextBool() ? numericId : stringId,
          'method': Method.ping,
        },
        expectation: _expectFormatExceptionForPayload,
      ),
    1 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.malformed-envelope.$index',
        description:
            'Generated JSON-RPC envelope without request/response members is rejected.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? numericId : stringId,
          'params': <String, dynamic>{'noise': random.nextInt(100)},
        },
        expectation: _expectFormatExceptionForPayload,
      ),
    2 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.request-id.$index',
        description: 'Generated requests preserve string-or-number IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? numericIdValue : stringId,
          'method': Method.ping,
        },
        expectation: _expectRequestIdRoundTrip,
      ),
    3 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.response-id.$index',
        description: 'Generated responses preserve string-or-number IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? numericIdValue : stringId,
          'result': <String, dynamic>{},
        },
        expectation: _expectResponseIdRoundTrip,
      ),
    4 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.progress-token.$index',
        description:
            'Generated progress notifications preserve string-or-number progress tokens.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'method': Method.notificationsProgress,
          'params': <String, dynamic>{
            'progressToken': progressToken,
            'progress': random.nextInt(10),
            'total': 10,
          },
        },
        expectation: _expectProgressTokenRoundTrip,
      ),
    _ => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.error-id.$index',
        description: 'Generated error responses preserve string-or-number IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? numericIdValue : stringId,
          'error': <String, dynamic>{
            'code': ErrorCode.invalidRequest.value,
            'message': 'generated invalid request',
          },
        },
        expectation: _expectErrorIdRoundTrip,
      ),
  };
}

class _ConformanceTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = <JsonRpcMessage>[];
  bool closed = false;
  bool started = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
  }

  @override
  Future<void> close() async {
    closed = true;
    onclose?.call();
  }

  void emit(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

JsonRpcInitializeRequest _initializeRequest({
  RequestId id = 1,
  ClientCapabilities capabilities = const ClientCapabilities(),
}) {
  return JsonRpcInitializeRequest(
    id: id,
    initParams: InitializeRequest(
      protocolVersion: latestProtocolVersion,
      capabilities: capabilities,
      clientInfo: const Implementation(
        name: 'conformance-client',
        version: '1.0.0',
      ),
    ),
  );
}

JsonRpcResponse _initializeResponse({
  required RequestId id,
  ServerCapabilities capabilities = const ServerCapabilities(),
}) {
  return JsonRpcResponse(
    id: id,
    result: InitializeResult(
      protocolVersion: latestProtocolVersion,
      capabilities: capabilities,
      serverInfo: const Implementation(
        name: 'conformance-server',
        version: '1.0.0',
      ),
    ).toJson(),
  );
}

Future<void> _initializeMcpServer(
  McpServer server,
  _ConformanceTransport transport, {
  ClientCapabilities clientCapabilities = const ClientCapabilities(),
}) async {
  await server.connect(transport);
  transport.emit(_initializeRequest(capabilities: clientCapabilities));
  await _settle();
  _expectSingleErrorFreeResponse(transport.sentMessages, id: 1);
  transport.sentMessages.clear();
  transport.emit(const JsonRpcInitializedNotification());
  await _settle();
  transport.sentMessages.clear();
}

Future<void> _initializeClient(
  McpClient client,
  _ConformanceTransport transport,
) async {
  final connectFuture = client.connect(transport);
  await _settle();

  final initializeRequests = transport.sentMessages
      .whereType<JsonRpcRequest>()
      .where((request) => request.method == Method.initialize)
      .toList();
  if (initializeRequests.length != 1) {
    throw StateError('Expected client to send exactly one initialize request.');
  }
  final initializeRequest = initializeRequests.single;

  transport.emit(_initializeResponse(id: initializeRequest.id));
  await connectFuture.timeout(const Duration(seconds: 1));
  transport.sentMessages.clear();
}

Future<void> _rejectsPreInitializeRequest() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  server.registerTool(
    'probe',
    callback: (args, extra) async {
      throw StateError('tools/list reached normal operation handlers.');
    },
  );

  await server.connect(transport);
  transport.emit(const JsonRpcListToolsRequest(id: 100));
  await _settle();

  _expectSingleError(
    transport.sentMessages,
    id: 100,
    code: ErrorCode.invalidRequest.value,
    messageContains: 'before initialize',
  );
  await server.close();
}

Future<void> _rejectsUnnegotiatedSamplingTools() async {
  final transport = _ConformanceTransport();
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      capabilities: ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
      ),
    ),
  );
  var handlerCalled = false;
  client.onSamplingRequest = (params) async {
    handlerCalled = true;
    return const CreateMessageResult(
      model: 'conformance-model',
      role: SamplingMessageRole.assistant,
      content: SamplingTextContent(text: 'unexpected'),
    );
  };

  await _initializeClient(client, transport);
  transport.emit(
    JsonRpcCreateMessageRequest(
      id: 101,
      createParams: const CreateMessageRequest(
        messages: <SamplingMessage>[
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Use a tool'),
          ),
        ],
        maxTokens: 4,
        tools: <Tool>[
          Tool(name: 'search', inputSchema: JsonObject()),
        ],
      ),
    ),
  );
  await _settle();

  if (handlerCalled) {
    throw StateError('sampling handler ran without sampling.tools capability.');
  }
  _expectSingleError(
    transport.sentMessages,
    id: 101,
    code: ErrorCode.invalidRequest.value,
    messageContains: 'sampling.tools',
  );
  await client.close();
}

Future<void> _rejectsInvalidElicitationVariantPayload() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 102,
      'method': Method.elicitationCreate,
      'params': <String, dynamic>{
        'mode': 'form',
        'message': 'Choose an account',
        'requestedSchema': <String, dynamic>{'type': 'object'},
        'url': 'https://example.com/collect',
      },
    }),
  );
}

Future<void> _stripsUnnegotiatedRelatedTaskMetadata() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  RequestHandlerExtra? receivedExtra;
  server.registerTool(
    'metadata_probe',
    callback: (args, extra) async {
      receivedExtra = extra;
      return const CallToolResult(
        content: <Content>[TextContent(text: 'ok')],
      );
    },
  );

  await _initializeMcpServer(server, transport);
  transport.emit(
    const JsonRpcCallToolRequest(
      id: 103,
      params: <String, dynamic>{
        'name': 'metadata_probe',
        'arguments': <String, dynamic>{},
        '_meta': <String, dynamic>{
          relatedTaskMetadataKey: <String, dynamic>{'taskId': 'task-1'},
          'progressToken': 'progress-1',
        },
      },
    ),
  );
  await _settle();

  if (receivedExtra == null) {
    throw StateError('Expected metadata_probe handler to run.');
  }
  if (receivedExtra!.taskId != null ||
      receivedExtra!.taskRequestedTtl != null) {
    throw StateError('Unnegotiated task metadata affected handler task state.');
  }
  if (receivedExtra!.meta?[relatedTaskMetadataKey] != null ||
      receivedExtra!.meta?.containsKey('relatedTask') == true) {
    throw StateError(
        'Unnegotiated related-task metadata reached handler meta.');
  }
  if (receivedExtra!.meta?['progressToken'] != 'progress-1') {
    throw StateError('Non-task request metadata was not preserved.');
  }
  _expectSingleErrorFreeResponse(transport.sentMessages, id: 103);
  await server.close();
}

Future<void> _rejectsMalformedProgressToken() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsProgress,
      'params': <String, dynamic>{
        'progressToken': <String, dynamic>{'bad': true},
        'progress': 1,
      },
    }),
  );
}

Future<void> _dispatchesNumericProgressToken() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  server.registerTool(
    'progress_probe',
    callback: (args, extra) async {
      await extra.sendProgress(1, total: 2, message: 'halfway');
      return const CallToolResult(
        content: <Content>[TextContent(text: 'ok')],
      );
    },
  );

  await _initializeMcpServer(server, transport);
  transport.emit(
    const JsonRpcCallToolRequest(
      id: 104,
      params: <String, dynamic>{
        'name': 'progress_probe',
        'arguments': <String, dynamic>{},
        '_meta': <String, dynamic>{
          'progressToken': 1.5,
        },
      },
    ),
  );
  await _settle();

  final progressMessages = transport.sentMessages
      .whereType<JsonRpcNotification>()
      .where((message) => message.method == Method.notificationsProgress)
      .toList();
  if (progressMessages.length != 1) {
    throw StateError(
      'Expected one progress notification, got ${progressMessages.length}.',
    );
  }
  final progress = ProgressNotification.fromJson(
    progressMessages.single.params ?? const <String, dynamic>{},
  );
  if (progress.progressToken != 1.5) {
    throw StateError('Expected numeric progress token to be preserved.');
  }
  if (progress.progress != 1 || progress.total != 2) {
    throw StateError('Expected progress values to be preserved.');
  }

  final responses =
      transport.sentMessages.whereType<JsonRpcResponse>().toList();
  _expectSingleErrorFreeResponse(responses, id: 104);
  await server.close();
}

Future<void> _rejectsInvalidJsonRpcVersion() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': '1.0',
      'id': 1,
      'method': Method.ping,
    }),
  );
}

Future<void> _rejectsMalformedJsonRpcMessage() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
    }),
  );
}

Future<void> _rejectsResultErrorJsonRpcResponse() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(<String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'result': <String, dynamic>{},
      'error': <String, dynamic>{
        'code': ErrorCode.internalError.value,
        'message': 'Internal error',
      },
    }),
  );
}

Future<void> _preservesStringResponseId() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'id': 'request-1',
    'result': <String, dynamic>{},
  });

  if (message is! JsonRpcResponse) {
    throw StateError('Expected JsonRpcResponse, got ${message.runtimeType}.');
  }
  if (message.id != 'request-1') {
    throw StateError('Expected string response ID to be preserved.');
  }
  if (message.toJson()['id'] != 'request-1') {
    throw StateError('Expected serialized response ID to stay a string.');
  }
}

Future<void> _preservesNumericResponseId() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'id': 1.5,
    'result': <String, dynamic>{},
  });

  if (message is! JsonRpcResponse) {
    throw StateError('Expected JsonRpcResponse, got ${message.runtimeType}.');
  }
  if (message.id != 1.5) {
    throw StateError('Expected numeric response ID to be preserved.');
  }
  if (message.toJson()['id'] != 1.5) {
    throw StateError('Expected serialized response ID to stay numeric.');
  }
}

JsonRpcResponse _expectSingleErrorFreeResponse(
  List<JsonRpcMessage> messages, {
  required RequestId id,
}) {
  if (messages.length != 1) {
    throw StateError('Expected one response, got ${messages.length}.');
  }
  final message = messages.single;
  if (message is! JsonRpcResponse) {
    throw StateError('Expected JsonRpcResponse, got ${message.runtimeType}.');
  }
  if (message.id != id) {
    throw StateError('Expected response ID $id, got ${message.id}.');
  }
  return message;
}

JsonRpcError _expectSingleError(
  List<JsonRpcMessage> messages, {
  required RequestId id,
  required int code,
  required String messageContains,
}) {
  if (messages.length != 1) {
    throw StateError('Expected one error response, got ${messages.length}.');
  }
  final message = messages.single;
  if (message is! JsonRpcError) {
    throw StateError('Expected JsonRpcError, got ${message.runtimeType}.');
  }
  if (message.id != id) {
    throw StateError('Expected error ID $id, got ${message.id}.');
  }
  if (message.error.code != code) {
    throw StateError('Expected error code $code, got ${message.error.code}.');
  }
  if (!message.error.message.contains(messageContains)) {
    throw StateError(
      "Expected error message to contain '$messageContains', got "
      "'${message.error.message}'.",
    );
  }
  return message;
}

Future<void> _preservesStringProgressToken() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'method': Method.notificationsProgress,
    'params': <String, dynamic>{
      'progressToken': 'progress-1',
      'progress': 1,
      'total': 2,
    },
  });

  if (message is! JsonRpcProgressNotification) {
    throw StateError(
      'Expected JsonRpcProgressNotification, got ${message.runtimeType}.',
    );
  }
  if (message.progressParams.progressToken != 'progress-1') {
    throw StateError('Expected string progress token to be preserved.');
  }
  if (message.toJson()['params']['progressToken'] != 'progress-1') {
    throw StateError('Expected serialized progress token to stay a string.');
  }
}

Future<void> _preservesNumericProgressToken() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'method': Method.notificationsProgress,
    'params': <String, dynamic>{
      'progressToken': 1.5,
      'progress': 1,
      'total': 2,
    },
  });

  if (message is! JsonRpcProgressNotification) {
    throw StateError(
      'Expected JsonRpcProgressNotification, got ${message.runtimeType}.',
    );
  }
  if (message.progressParams.progressToken != 1.5) {
    throw StateError('Expected numeric progress token to be preserved.');
  }
  if (message.toJson()['params']['progressToken'] != 1.5) {
    throw StateError('Expected serialized progress token to stay numeric.');
  }
}

Future<void> _advertisesLatestProtocolVersion() async {
  if (latestProtocolVersion != '2025-11-25') {
    throw StateError(
      'Expected latestProtocolVersion 2025-11-25, got $latestProtocolVersion.',
    );
  }
  if (supportedProtocolVersions.first != latestProtocolVersion) {
    throw StateError('Expected latestProtocolVersion to be advertised first.');
  }
  if (!supportedProtocolVersions.contains('2025-11-25')) {
    throw StateError('Expected supported versions to include 2025-11-25.');
  }
}

void _expectThrowsFormatException(void Function() callback) {
  try {
    callback();
  } on FormatException {
    return;
  }

  throw StateError('Expected FormatException.');
}

void _expectFormatExceptionForPayload(Map<String, dynamic> message) {
  _expectThrowsFormatException(() => JsonRpcMessage.fromJson(message));
}

void _expectRequestIdRoundTrip(Map<String, dynamic> message) {
  final parsed = JsonRpcMessage.fromJson(message);
  if (parsed is! JsonRpcRequest) {
    throw StateError('Expected JsonRpcRequest, got ${parsed.runtimeType}.');
  }
  _expectIdRoundTrip(parsed.id, message['id'], parsed.toJson());
}

void _expectResponseIdRoundTrip(Map<String, dynamic> message) {
  final parsed = JsonRpcMessage.fromJson(message);
  if (parsed is! JsonRpcResponse) {
    throw StateError('Expected JsonRpcResponse, got ${parsed.runtimeType}.');
  }
  _expectIdRoundTrip(parsed.id, message['id'], parsed.toJson());
}

void _expectErrorIdRoundTrip(Map<String, dynamic> message) {
  final parsed = JsonRpcMessage.fromJson(message);
  if (parsed is! JsonRpcError) {
    throw StateError('Expected JsonRpcError, got ${parsed.runtimeType}.');
  }
  _expectIdRoundTrip(parsed.id, message['id'], parsed.toJson());
}

void _expectProgressTokenRoundTrip(Map<String, dynamic> message) {
  final parsed = JsonRpcMessage.fromJson(message);
  if (parsed is! JsonRpcProgressNotification) {
    throw StateError(
      'Expected JsonRpcProgressNotification, got ${parsed.runtimeType}.',
    );
  }
  final token = message['params']['progressToken'];
  if (parsed.progressParams.progressToken != token) {
    throw StateError('Expected progress token $token, got '
        '${parsed.progressParams.progressToken}.');
  }
  if (parsed.toJson()['params']['progressToken'] != token) {
    throw StateError('Expected serialized progress token to preserve $token.');
  }
}

void _expectIdRoundTrip(
    RequestId actualId, Object expectedId, Map<String, dynamic> json) {
  if (actualId != expectedId) {
    throw StateError('Expected ID $expectedId, got $actualId.');
  }
  if (json['id'] != expectedId) {
    throw StateError('Expected serialized ID to preserve $expectedId.');
  }
}
