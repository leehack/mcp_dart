import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mcp_dart/mcp_dart.dart';

const String _fixtureSuite = 'fixture';
const String _specSuite = 'spec';
const String _allSuites = 'all';
const String _serverDiscoverMethod = 'server/discover';
const String _stableProtocolVersion2026_07_28 = '2026-07-28';
const String _protocolVersionMetaKey =
    'io.modelcontextprotocol/protocolVersion';
const String _clientInfoMetaKey = 'io.modelcontextprotocol/clientInfo';
const String _clientCapabilitiesMetaKey =
    'io.modelcontextprotocol/clientCapabilities';
const String _resultTypeComplete = 'complete';
const String _resultTypeInputRequired = 'input_required';
const String _resultTypeFutureExtension = 'future_extension';
const String _cacheScopePrivate = 'private';
const String _tasksExtensionId = 'io.modelcontextprotocol/tasks';
const String _methodTasksGet = 'tasks/get';
const String _methodTasksUpdate = 'tasks/update';
const String _methodSubscriptionsListen = 'subscriptions/listen';
const String _methodNotificationsTasksStatus = 'notifications/tasks/status';
final int _headerMismatchCode = ErrorCode.headerMismatch.value;
final int _unsupportedProtocolVersionCode =
    ErrorCode.unsupportedProtocolVersion.value;

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

class _MissingCapabilityScenario {
  final String name;
  final ClientCapabilities capabilities;
  final String method;
  final Map<String, dynamic> requiredCapabilities;

  const _MissingCapabilityScenario({
    required this.name,
    required this.capabilities,
    required this.method,
    required this.requiredCapabilities,
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
            name: 'jsonrpc.rejects-non-string-method',
            description:
                'Rejects JSON-RPC requests whose method member is not a string.',
            check: _rejectsNonStringJsonRpcMethod,
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
            name: 'jsonrpc.rejects-method-response-envelope',
            description:
                'Rejects JSON-RPC envelopes that combine request/notification method fields with response result or error fields.',
            check: _rejectsMethodResponseJsonRpcEnvelope,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-malformed-error-object',
            description:
                'Rejects JSON-RPC error responses whose error member is malformed.',
            check: _rejectsMalformedJsonRpcErrorObject,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-null-error-response-id',
            description:
                'Rejects JSON-RPC error responses whose id member is explicitly null.',
            check: _rejectsNullJsonRpcErrorResponseId,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.accepts-omitted-error-response-id',
            description:
                'Parses and serializes JSON-RPC error responses that omit the optional id member.',
            check: _acceptsOmittedJsonRpcErrorResponseId,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-null-params-member',
            description:
                'Rejects JSON-RPC request and notification envelopes whose params member is null.',
            check: _rejectsNullJsonRpcParamsMember,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'tools-call.requires-params',
            description:
                'Rejects tools/call requests that omit the required params object.',
            check: _requiresCallToolRequestParams,
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
            name: 'jsonrpc.preserves-integer-response-id',
            description:
                'Parses and serializes successful responses with integer JSON-RPC IDs.',
            check: _preservesIntegerResponseId,
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
            name: 'jsonrpc.preserves-integer-progress-token',
            description:
                'Parses and serializes progress notifications with integer progress tokens.',
            check: _preservesIntegerProgressToken,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'jsonrpc.rejects-fractional-ids-and-progress-tokens',
            description:
                'Rejects fractional JSON-RPC request IDs, response IDs, and progress tokens.',
            check: _rejectsFractionalIdsAndProgressTokens,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name: 'protocol-version.advertises-latest-2026-07-28',
            description:
                'Advertises MCP 2026-07-28 as the latest supported protocol version.',
            check: _advertisesLatestProtocolVersion,
          ),
          _ConformanceCase(
            suite: _fixtureSuite,
            name:
                'protocol-version.stable-profile-advertises-2026-07-28',
            description:
                'Advertises MCP 2026-07-28 from the default stable SDK profile.',
            check: _stableProfileAdvertises2026ProtocolVersion,
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
            name: 'lifecycle.gates-until-initialized-notification',
            description:
                'Keeps normal operation requests gated until notifications/initialized is received.',
            check: _gatesUntilInitializedNotification,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'lifecycle.does-not-cancel-initialize',
            description:
                'Does not send notifications/cancelled for initialize request cancellation.',
            check: _doesNotCancelInitializeRequest,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'cancellation.requires-request-id',
            description:
                'Rejects notifications/cancelled payloads without a requestId.',
            check: _requiresCancellationRequestId,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'server-discover.requires-request-meta',
            description:
                'Rejects server/discover requests that omit params._meta request metadata.',
            check: _serverDiscoverRequiresRequestMeta,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'server-discover.returns-supported-capabilities',
            description:
                'Returns complete server/discover results with supported protocol versions.',
            check: _serverDiscoverReturnsSupportedCapabilities,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'protocol-version.rejects-unsupported-stateless-version',
            description:
                'Rejects unsupported stateless protocol versions with supported/requested error data.',
            check: _rejectsUnsupportedStatelessProtocolVersion,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.requires-complete-request-meta',
            description:
                'Rejects 2026 stateless requests whose _meta omits required client identity or capability fields.',
            check: _statelessRequestsRequireCompleteRequestMeta,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'protocol-version.http-modern-400-retries-discovery',
            description:
                'Retries server/discover with an advertised version after HTTP 400 UnsupportedProtocolVersion without falling back to initialize.',
            check: _httpModernProtocolErrorsRetryDiscovery,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'capabilities.http-modern-400-does-not-fallback',
            description:
                'Surfaces HTTP 400 MissingRequiredClientCapability errors without falling back to initialize.',
            check: _httpModernMissingCapabilityErrorsDoNotFallback,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'protocol-version.initialize-negotiates-stateful-version',
            description:
                'Keeps initialize negotiation on stateful MCP versions even when the latest stateless version is preferred.',
            check: _initializeNegotiatesStatefulProtocolVersion,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'capabilities.stateless-does-not-infer-initialize-extensions',
            description:
                'Requires 2026 stateless requests to declare extension capabilities per request instead of inheriting initialize capabilities.',
            check: _statelessDoesNotInferInitializeExtensions,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.rejects-mismatched-routing-headers',
            description:
                'Rejects 2026 Streamable HTTP requests whose routing headers disagree with the JSON-RPC body.',
            check: _rejectsMismatchedStatelessHttpRoutingHeaders,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.requires-routing-headers',
            description:
                'Requires 2026 Streamable HTTP requests to include protocol and method routing headers.',
            check: _requiresStatelessHttpRoutingHeaders,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.rejects-non-post-methods',
            description:
                'Returns HTTP 405 for 2026 stateless Streamable HTTP methods other than POST.',
            check: _rejectsStatelessHttpNonPostMethods,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.rejects-batch-payloads',
            description:
                'Rejects 2026 stateless Streamable HTTP POST bodies that contain more than one JSON-RPC message.',
            check: _rejectsStatelessHttpBatchPayloads,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.task-requests-require-name-header',
            description:
                'Requires 2026 task lifecycle requests to route with Mcp-Name task IDs.',
            check: _taskRequestsRequireStatelessHttpNameHeader,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.validates-parameter-headers',
            description:
                'Requires and matches 2026 Mcp-Param routing headers for configured tool arguments.',
            check: _validatesStatelessHttpParameterHeaders,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.omits-unsafe-numeric-parameter-headers',
            description:
                'Mirrors finite numeric x-mcp-header values while omitting unsafe integers.',
            check: _omitsUnsafeNumericParameterHeaders,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.encodes-parameter-header-values',
            description:
                'Encodes non-plain 2026 Mcp-Param string header values while preserving plain strings.',
            check: _encodesStatelessHttpParameterHeaderValues,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.accepts-response-posts',
            description:
                'Accepts 2026 JSON-RPC response POSTs without request-body metadata.',
            check: _acceptsStatelessHttpResponsePosts,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.omits-session-header-after-initialize',
            description:
                'Omits Mcp-Session-Id on 2026 stateless responses even after stateful initialization.',
            check: _statelessHttpOmitsSessionHeaderAfterInitialize,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-http.task-subscription-requires-client-capability',
            description:
                'Returns MissingRequiredClientCapability for stateless task subscriptions when the client did not advertise the task extension.',
            check: _taskSubscriptionRequiresClientCapability,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.related-task-uses-explicit-id-across-transports',
            description:
                'Processes related task operations across separate transports using explicit task IDs.',
            check: _relatedTaskUsesExplicitIdAcrossTransports,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.ignores-legacy-task-parameter',
            description:
                'Ignores legacy tools/call task parameters on 2026 stateless requests.',
            check: _statelessIgnoresLegacyTaskParameter,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless-client.rejects-legacy-task-options',
            description:
                'Rejects legacy RequestOptions.task before sending 2026 stateless requests.',
            check: _statelessClientRejectsLegacyTaskOptions,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.adds-result-type-and-cache-defaults',
            description:
                'Adds 2026 complete resultType and cache defaults for all cacheable stateless results.',
            check: _statelessAddsResultTypeAndCacheDefaults,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'tools-list.stateless-returns-deterministic-order',
            description:
                'Returns 2026 stateless tools/list results in deterministic name order.',
            check: _statelessToolsListReturnsDeterministicOrder,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'tools-list.stateless-omits-legacy-execution',
            description:
                'Omits stable-only Tool.execution metadata from 2026 stateless tools/list results.',
            check: _statelessToolsListOmitsLegacyExecution,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'resources.missing-resource-error-code-by-version',
            description:
                'Uses legacy ResourceNotFound for stable resource misses and InvalidParams for 2026 stateless resource misses.',
            check: _missingResourceErrorCodeByVersion,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.rejects-unrecognized-result-type',
            description:
                'Rejects 2026 stateless responses with unrecognized resultType values.',
            check: _statelessRejectsUnrecognizedResultType,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'mrtr.input-required-supported-requests',
            description:
                'Allows input_required results on tools/call, prompts/get, and resources/read.',
            check: _mrtrInputRequiredSupportedRequests,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'mrtr.rejects-unsupported-input-required-results',
            description:
                'Rejects input_required results on methods outside the MRTR allowlist.',
            check: _mrtrRejectsUnsupportedInputRequiredResults,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'mrtr.input-requests-require-client-capabilities',
            description:
                'Rejects MRTR inputRequests whose client capabilities were not declared.',
            check: _mrtrInputRequestsRequireClientCapabilities,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.rejects-removed-core-rpcs',
            description:
                'Rejects initialize, ping, logging/setLevel, and resource subscription RPCs in stateless MCP.',
            check: _rejectsRemovedStatelessCoreRpcs,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'stateless.rejects-removed-core-notifications',
            description:
                'Rejects initialized, roots/list_changed, and legacy task status notifications in stateless MCP.',
            check: _rejectsRemovedStatelessCoreNotifications,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'logging.stateless-requires-request-log-level',
            description:
                'Sends stateless logging notifications only when the request opts in with io.modelcontextprotocol/logLevel.',
            check: _statelessLoggingRequiresRequestLogLevel,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name:
                'tasks-extension.lifecycle-methods-do-not-require-repeated-capability',
            description:
                'Does not reject task lifecycle requests solely because the request omits repeated task extension capability metadata.',
            check: _taskLifecycleMethodsAllowResumedClientCapability,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'tasks-extension.task-store-uses-extension-result-shapes',
            description:
                'Serializes built-in task-store tasks/get and tasks/cancel responses in the MCP Tasks extension wire shape.',
            check: _taskStoreUsesTaskExtensionResultShapes,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'tasks-extension.call-tool-result-cannot-spoof-task-result',
            description:
                'Rejects CallToolResult.extra attempts to spoof resultType task.',
            check: _callToolResultCannotSpoofTaskResult,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'tasks-extension.task-result-requires-client-extension',
            description:
                'Rejects resultType task unless the tools/call request negotiated the tasks extension.',
            check: _taskResultRequiresClientExtension,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'subscriptions-listen.task-ids-require-client-capability',
            description:
                'Rejects task-status subscriptions when the client did not advertise the task extension.',
            check: _subscriptionTaskIdsRequireClientCapability,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'subscriptions-listen.requires-request-meta',
            description:
                'Rejects subscriptions/listen requests that omit params._meta request metadata.',
            check: _subscriptionsListenRequiresRequestMeta,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name:
                'subscriptions-listen.resource-subscriptions-require-capability',
            description:
                'Acknowledges resource subscriptions only when resources.subscribe is advertised.',
            check: _subscriptionsListenRequiresResourceSubscribeCapability,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'subscriptions-acknowledged.rejects-wrapper-mismatch',
            description:
                'Rejects notifications/subscriptions/acknowledged wrappers with mismatched JSON-RPC constants.',
            check: _subscriptionsAcknowledgedRejectsWrapperMismatch,
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
            name: 'capabilities.rejects-unnegotiated-sampling-context',
            description:
                'Rejects deprecated sampling includeContext values when sampling.context was not negotiated.',
            check: _rejectsUnnegotiatedSamplingContext,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'capabilities.unadvertised-peer-methods-use-method-not-found',
            description:
                'Uses MethodNotFound for MCP methods whose peer capability was not advertised.',
            check: _unadvertisedPeerMethodsUseMethodNotFound,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'capabilities.task-scoped-peer-methods-use-method-not-found',
            description:
                'Uses MethodNotFound for task-scoped MCP requests whose peer task capability was not advertised.',
            check: _taskScopedPeerMethodsUseMethodNotFound,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'capabilities.stateless-omits-legacy-task-capabilities',
            description:
                'Omits legacy task and removed roots.listChanged capability fields from 2026 stateless metadata.',
            check: _statelessOmitsLegacyTaskCapabilities,
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
            name: 'elicitation.accepts-numeric-number-schema-keywords',
            description:
                'Accepts finite numeric default/minimum/maximum keywords in elicitation number schemas.',
            check: _acceptsNumericElicitationNumberSchemaKeywords,
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
                'Rejects progress notifications whose progressToken is not a string or integer.',
            check: _rejectsMalformedProgressToken,
          ),
          _ConformanceCase(
            suite: _specSuite,
            name: 'progress.dispatches-integer-progress-token',
            description:
                'Dispatches progress notifications for integer progress tokens.',
            check: _dispatchesIntegerProgressToken,
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

  /// Runs spec-critical raw-wire behavior checks.
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
  final integerId = random.nextInt(1000000);
  final stringId = 'req-${random.nextInt(1000000)}';
  final progressToken = random.nextBool() ? integerId : 'progress-$integerId';

  return switch (random.nextInt(6)) {
    0 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.invalid-version.$index',
        description:
            'Generated request with an invalid JSON-RPC version is rejected.',
        message: <String, dynamic>{
          'jsonrpc': '2.${random.nextInt(9) + 1}',
          'id': random.nextBool() ? integerId : stringId,
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
          'id': random.nextBool() ? integerId : stringId,
          'params': <String, dynamic>{'noise': random.nextInt(100)},
        },
        expectation: _expectFormatExceptionForPayload,
      ),
    2 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.request-id.$index',
        description: 'Generated requests preserve string-or-integer IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? integerId : stringId,
          'method': Method.ping,
        },
        expectation: _expectRequestIdRoundTrip,
      ),
    3 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.response-id.$index',
        description: 'Generated responses preserve string-or-integer IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? integerId : stringId,
          'result': <String, dynamic>{},
        },
        expectation: _expectResponseIdRoundTrip,
      ),
    4 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.progress-token.$index',
        description:
            'Generated progress notifications preserve string-or-integer progress tokens.',
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
        description:
            'Generated error responses preserve string-or-integer IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? integerId : stringId,
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

class _ConformanceProtocol extends Protocol {
  _ConformanceProtocol() : super(null);

  @override
  void assertCapabilityForMethod(String method) {}

  @override
  void assertNotificationCapability(String method) {}

  @override
  void assertRequestHandlerCapability(String method) {}

  @override
  void assertTaskCapability(String method) {}

  @override
  void assertTaskHandlerCapability(String method) {}
}

class _DiscoveringConformanceTransport extends Transport
    implements ProtocolVersionAwareTransport {
  _DiscoveringConformanceTransport({
    required this.toolsListResult,
    Map<String, dynamic>? capabilities,
    this.toolsCallResult,
  }) : capabilities = capabilities ??
            const <String, dynamic>{
              'tools': <String, dynamic>{},
            };

  final Map<String, dynamic> toolsListResult;
  final Map<String, dynamic> capabilities;
  final Map<String, dynamic>? toolsCallResult;
  final List<JsonRpcMessage> sentMessages = <JsonRpcMessage>[];

  @override
  String? protocolVersion;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {}

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);

    if (message is JsonRpcRequest && message.method == _serverDiscoverMethod) {
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: <String, dynamic>{
            'resultType': _resultTypeComplete,
            'supportedVersions': const <String>[
              _stableProtocolVersion2026_07_28,
            ],
            'capabilities': capabilities,
            'serverInfo': const <String, dynamic>{
              'name': 'conformance-server',
              'version': '1.0.0',
            },
            'ttlMs': 0,
            'cacheScope': _cacheScopePrivate,
          },
        ),
      );
      return;
    }

    final toolsCallResult = this.toolsCallResult;
    if (message is JsonRpcRequest &&
        message.method == Method.toolsCall &&
        toolsCallResult != null) {
      onmessage?.call(
        JsonRpcResponse(id: message.id, result: toolsCallResult),
      );
      return;
    }

    if (message is JsonRpcRequest && message.method == Method.toolsList) {
      onmessage?.call(
        JsonRpcResponse(id: message.id, result: toolsListResult),
      );
    }
  }

  @override
  Future<void> close() async {
    onclose?.call();
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

bool _stringListEquals(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) {
      return false;
    }
  }
  return true;
}

JsonRpcInitializeRequest _initializeRequest({
  RequestId id = 1,
  ClientCapabilities capabilities = const ClientCapabilities(),
}) {
  return JsonRpcInitializeRequest(
    id: id,
    initParams: InitializeRequest(
      protocolVersion: stableProtocolVersion2025_11_25,
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
      protocolVersion: stableProtocolVersion2025_11_25,
      capabilities: capabilities,
      serverInfo: const Implementation(
        name: 'conformance-server',
        version: '1.0.0',
      ),
    ).toJson(),
  );
}

Map<String, dynamic> _statelessRequestMeta({
  String protocolVersion = _stableProtocolVersion2026_07_28,
  ClientCapabilities capabilities = const ClientCapabilities(),
}) {
  return <String, dynamic>{
    _protocolVersionMetaKey: protocolVersion,
    _clientInfoMetaKey: const Implementation(
      name: 'conformance-client',
      version: '1.0.0',
    ).toJson(),
    _clientCapabilitiesMetaKey: capabilities.toJson(
      omitLegacyTasks: isStatelessProtocolVersion(protocolVersion),
      omitLegacyRootsListChanged: isStatelessProtocolVersion(protocolVersion),
    ),
  };
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
  _ConformanceTransport transport, {
  ServerCapabilities serverCapabilities = const ServerCapabilities(),
}) async {
  final connectFuture = client.connect(transport);
  await _settle();

  final discoverRequests = transport.sentMessages
      .whereType<JsonRpcRequest>()
      .where((request) => request.method == _serverDiscoverMethod)
      .toList();
  for (final discoverRequest in discoverRequests) {
    transport.emit(
      JsonRpcError(
        id: discoverRequest.id,
        error: JsonRpcErrorData(
          code: ErrorCode.methodNotFound.value,
          message: 'Method not found',
        ),
      ),
    );
  }
  if (discoverRequests.isNotEmpty) {
    await _settle();
  }

  final initializeRequests = transport.sentMessages
      .whereType<JsonRpcRequest>()
      .where((request) => request.method == Method.initialize)
      .toList();
  if (initializeRequests.length != 1) {
    throw StateError('Expected client to send exactly one initialize request.');
  }
  final initializeRequest = initializeRequests.single;

  transport.emit(
    _initializeResponse(
      id: initializeRequest.id,
      capabilities: serverCapabilities,
    ),
  );
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

Future<void> _gatesUntilInitializedNotification() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  var handlerCallCount = 0;
  server.registerTool(
    'probe',
    callback: (args, extra) async {
      handlerCallCount += 1;
      return const CallToolResult(
        content: <Content>[TextContent(text: 'ok')],
      );
    },
  );

  await server.connect(transport);
  transport.emit(_initializeRequest());
  await _settle();
  _expectSingleErrorFreeResponse(transport.sentMessages, id: 1);

  transport.sentMessages.clear();
  transport.emit(
    const JsonRpcCallToolRequest(
      id: 101,
      params: <String, dynamic>{
        'name': 'probe',
        'arguments': <String, dynamic>{},
      },
    ),
  );
  await _settle();

  if (handlerCallCount != 0) {
    throw StateError('Tool handler ran before notifications/initialized.');
  }
  _expectSingleError(
    transport.sentMessages,
    id: 101,
    code: ErrorCode.invalidRequest.value,
    messageContains: 'notifications/initialized',
  );

  transport.sentMessages.clear();
  transport.emit(const JsonRpcInitializedNotification());
  transport.emit(
    const JsonRpcCallToolRequest(
      id: 102,
      params: <String, dynamic>{
        'name': 'probe',
        'arguments': <String, dynamic>{},
      },
    ),
  );
  await _settle();

  if (handlerCallCount != 1) {
    throw StateError(
        'Tool handler did not run after initialized notification.');
  }
  _expectSingleErrorFreeResponse(transport.sentMessages, id: 102);
  await server.close();
}

Future<void> _doesNotCancelInitializeRequest() async {
  final transport = _ConformanceTransport();
  final protocol = _ConformanceProtocol();
  await protocol.connect(transport);

  final controller = BasicAbortController();
  final requestFuture = protocol.request<InitializeResult>(
    _initializeRequest(),
    InitializeResult.fromJson,
    RequestOptions(
      signal: controller.signal,
      timeoutEnabled: false,
    ),
  );
  await _settle();

  final initializeRequests = transport.sentMessages
      .whereType<JsonRpcRequest>()
      .where((request) => request.method == Method.initialize)
      .toList();
  if (initializeRequests.length != 1) {
    throw StateError(
      'Expected one initialize request, got ${initializeRequests.length}.',
    );
  }

  controller.abort('cancel initialize');
  try {
    await requestFuture.timeout(const Duration(seconds: 1));
    throw StateError(
        'Expected initialize request cancellation to fail locally.');
  } catch (error) {
    if (!error.toString().contains('cancel initialize')) {
      throw StateError(
        'Expected initialize cancellation reason, got $error.',
      );
    }
  }
  await _settle();

  final cancellations =
      transport.sentMessages.whereType<JsonRpcCancelledNotification>().toList();
  if (cancellations.isNotEmpty) {
    throw StateError(
      'Expected no cancellation notification for initialize, got $cancellations.',
    );
  }

  await protocol.close();
}

Future<void> _requiresCancellationRequestId() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsCancelled,
      'params': <String, dynamic>{
        'reason': 'missing request id',
      },
    }),
  );

  try {
    const CancelledNotification(
      requestId: null,
      reason: 'missing request id',
    ).toJson();
  } on FormatException {
    return;
  }

  throw StateError(
      'Expected CancelledNotification.toJson to require requestId.');
}

Future<void> _serverDiscoverRequiresRequestMeta() async {
  for (final message in [
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'discover-1',
      'method': _serverDiscoverMethod,
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'discover-1',
      'method': _serverDiscoverMethod,
      '_meta': <String, dynamic>{
        _protocolVersionMetaKey: _stableProtocolVersion2026_07_28,
      },
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'discover-1',
      'method': _serverDiscoverMethod,
      'params': <String, dynamic>{},
    },
  ]) {
    _expectThrowsFormatException(() => JsonRpcMessage.fromJson(message));
  }

  final parsed = JsonRpcMessage.fromJson(<String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'id': 'discover-1',
    'method': _serverDiscoverMethod,
    'params': <String, dynamic>{
      '_meta': <String, dynamic>{
        _protocolVersionMetaKey: _stableProtocolVersion2026_07_28,
        _clientInfoMetaKey: <String, dynamic>{
          'name': 'client',
          'version': '1.0.0',
        },
        _clientCapabilitiesMetaKey: <String, dynamic>{},
      },
    },
  });
  if (parsed is! JsonRpcRequest) {
    throw StateError(
      'Expected JsonRpcRequest, got ${parsed.runtimeType}.',
    );
  }
  if (parsed.meta?[_protocolVersionMetaKey] !=
      _stableProtocolVersion2026_07_28) {
    throw StateError('Expected server/discover metadata to be preserved.');
  }
}

Future<void> _serverDiscoverReturnsSupportedCapabilities() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
      instructions: 'Conformance server.',
    ),
  );

  await server.connect(transport);
  transport.emit(
    JsonRpcRequest(
      id: 'discover-1',
      method: _serverDiscoverMethod,
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  final response = _expectSingleErrorFreeResponse(
    transport.sentMessages,
    id: 'discover-1',
  );
  final result = response.result;
  if (result['resultType'] != _resultTypeComplete) {
    throw StateError('Expected complete server/discover result.');
  }
  final supportedVersions = result['supportedVersions'];
  if (supportedVersions is! List ||
      !supportedVersions.contains(_stableProtocolVersion2026_07_28)) {
    throw StateError(
      'Expected server/discover to include $_stableProtocolVersion2026_07_28.',
    );
  }
  final serverInfo = result['serverInfo'];
  if (serverInfo is! Map || serverInfo['name'] != 'server') {
    throw StateError('Expected server/discover to include server identity.');
  }
  if (result['instructions'] != 'Conformance server.') {
    throw StateError('Expected server/discover to include instructions.');
  }
  final capabilities = result['capabilities'];
  if (capabilities is! Map || capabilities['tools'] is! Map) {
    throw StateError('Expected server/discover to include tool capabilities.');
  }

  await server.close();
}

Future<void> _rejectsUnsupportedStatelessProtocolVersion() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
    ),
  );

  await server.connect(transport);
  transport.emit(
    JsonRpcRequest(
      id: 'unsupported-version',
      method: _serverDiscoverMethod,
      meta: _statelessRequestMeta(protocolVersion: '1900-01-01'),
    ),
  );
  await _settle();

  final error = _expectSingleError(
    transport.sentMessages,
    id: 'unsupported-version',
    code: _unsupportedProtocolVersionCode,
    messageContains: 'Unsupported protocol version',
  );
  _expectUnsupportedProtocolVersionData(error, requested: '1900-01-01');

  await server.close();
}

Future<void> _statelessRequestsRequireCompleteRequestMeta() async {
  final scenarios = <({String id, Map<String, dynamic> meta, String missing})>[
    (
      id: 'missing-client-info',
      meta: <String, dynamic>{
        _protocolVersionMetaKey: _stableProtocolVersion2026_07_28,
        _clientCapabilitiesMetaKey: <String, dynamic>{},
      },
      missing: _clientInfoMetaKey,
    ),
    (
      id: 'missing-client-capabilities',
      meta: <String, dynamic>{
        _protocolVersionMetaKey: _stableProtocolVersion2026_07_28,
        _clientInfoMetaKey: <String, dynamic>{
          'name': 'client',
          'version': '1.0.0',
        },
      },
      missing: _clientCapabilitiesMetaKey,
    ),
  ];

  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
    ),
  );

  await server.connect(transport);
  for (final scenario in scenarios) {
    transport.emit(
      JsonRpcListToolsRequest(
        id: scenario.id,
        meta: scenario.meta,
      ),
    );
    await _settle();

    _expectSingleError(
      transport.sentMessages,
      id: scenario.id,
      code: ErrorCode.invalidParams.value,
      messageContains: scenario.missing,
    );
    transport.sentMessages.clear();
  }
  await server.close();
}

Future<void> _httpModernProtocolErrorsRetryDiscovery() async {
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final receivedMethods = <String>[];

  late final StreamSubscription<HttpRequest> serverSubscription;
  serverSubscription = httpServer.listen((request) {
    unawaited(() async {
      try {
        final bodyText = await utf8.decodeStream(request);
        final body = jsonDecode(bodyText) as Map<String, dynamic>;
        final id = body['id'];
        final method = body['method'];
        if (method is String) {
          receivedMethods.add(method);
        }

        request.response.headers.contentType = ContentType.json;

        if (method == _serverDiscoverMethod) {
          final params = body['params'];
          final meta = params is Map ? params['_meta'] : null;
          final requestedVersion =
              meta is Map ? meta[_protocolVersionMetaKey] : null;

          if (requestedVersion == '1900-01-01') {
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write(
              jsonEncode(
                JsonRpcError(
                  id: id,
                  error: JsonRpcErrorData(
                    code: ErrorCode.unsupportedProtocolVersion.value,
                    message: 'Unsupported protocol version',
                    data: const <String, dynamic>{
                      'supported': <String>[_stableProtocolVersion2026_07_28],
                      'requested': '1900-01-01',
                    },
                  ),
                ).toJson(),
              ),
            );
          } else {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(
              jsonEncode(
                JsonRpcResponse(
                  id: id,
                  result: const <String, dynamic>{
                    'resultType': _resultTypeComplete,
                    'supportedVersions': <String>[
                      _stableProtocolVersion2026_07_28,
                    ],
                    'capabilities': <String, dynamic>{
                      'tools': <String, dynamic>{},
                    },
                    'serverInfo': <String, dynamic>{
                      'name': 'modern-http-server',
                      'version': '1.0.0',
                    },
                    'ttlMs': 0,
                    'cacheScope': _cacheScopePrivate,
                  },
                ).toJson(),
              ),
            );
          }
        } else if (method == Method.initialize) {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(
            jsonEncode(_initializeResponse(id: id).toJson()),
          );
        } else {
          request.response.statusCode = HttpStatus.accepted;
        }
      } finally {
        await request.response.close();
      }
    }());
  });

  final transport = StreamableHttpClientTransport(
    Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
  );
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
      protocolVersion: '1900-01-01',
      useServerDiscover: true,
    ),
  );

  try {
    await client.connect(transport);
    if (receivedMethods.contains(Method.initialize)) {
      throw StateError(
        'Modern HTTP 400 JSON-RPC errors must not trigger initialize fallback.',
      );
    }
    if (client.getProtocolVersion() != _stableProtocolVersion2026_07_28) {
      throw StateError(
        'Expected retry to negotiate $_stableProtocolVersion2026_07_28, '
        'got ${client.getProtocolVersion()}.',
      );
    }
    if (receivedMethods
            .where((method) => method == _serverDiscoverMethod)
            .length !=
        2) {
      throw StateError(
        'Expected two server/discover attempts, got $receivedMethods.',
      );
    }
  } finally {
    await client.close();
    await serverSubscription.cancel();
    await httpServer.close(force: true);
  }
}

Future<void> _httpModernMissingCapabilityErrorsDoNotFallback() async {
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final receivedMethods = <String>[];

  late final StreamSubscription<HttpRequest> serverSubscription;
  serverSubscription = httpServer.listen((request) {
    unawaited(() async {
      try {
        final bodyText = await utf8.decodeStream(request);
        final body = jsonDecode(bodyText) as Map<String, dynamic>;
        final id = body['id'];
        final method = body['method'];
        if (method is String) {
          receivedMethods.add(method);
        }

        request.response.headers.contentType = ContentType.json;

        if (method == _serverDiscoverMethod) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write(
            jsonEncode(
              JsonRpcError(
                id: id,
                error: JsonRpcErrorData(
                  code: ErrorCode.missingRequiredClientCapability.value,
                  message:
                      'Server requires the elicitation capability for this request',
                  data: const <String, dynamic>{
                    'requiredCapabilities': <String, dynamic>{
                      'elicitation': <String, dynamic>{},
                    },
                  },
                ),
              ).toJson(),
            ),
          );
        } else if (method == Method.initialize) {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(
            jsonEncode(_initializeResponse(id: id).toJson()),
          );
        } else {
          request.response.statusCode = HttpStatus.accepted;
        }
      } finally {
        await request.response.close();
      }
    }());
  });

  final transport = StreamableHttpClientTransport(
    Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
  );
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
      protocolVersion: _stableProtocolVersion2026_07_28,
      useServerDiscover: true,
    ),
  );

  try {
    await client.connect(transport);
    throw StateError('Expected missing capability error.');
  } on McpError catch (error) {
    if (error.code != ErrorCode.missingRequiredClientCapability.value) {
      throw StateError(
        'Expected missing client capability error code, got ${error.code}.',
      );
    }
    if (!error.message.contains('elicitation capability')) {
      throw StateError(
        'Expected missing elicitation capability message, got '
        "'${error.message}'.",
      );
    }
    final data = error.data;
    if (data is! Map ||
        data['requiredCapabilities'] is! Map ||
        (data['requiredCapabilities'] as Map)['elicitation'] is! Map) {
      throw StateError(
        'Expected requiredCapabilities.elicitation error data, got $data.',
      );
    }
    if (receivedMethods.contains(Method.initialize)) {
      throw StateError(
        'Modern HTTP 400 JSON-RPC errors must not trigger initialize fallback.',
      );
    }
    if (receivedMethods
            .where((method) => method == _serverDiscoverMethod)
            .length !=
        1) {
      throw StateError(
        'Expected one server/discover attempt, got $receivedMethods.',
      );
    }
  } finally {
    await client.close();
    await serverSubscription.cancel();
    await httpServer.close(force: true);
  }
}

Future<void> _initializeNegotiatesStatefulProtocolVersion() async {
  final serverTransport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
  );
  await server.connect(serverTransport);
  serverTransport.emit(
    JsonRpcInitializeRequest(
      id: 'draft-initialize',
      initParams: const InitializeRequest(
        protocolVersion: _stableProtocolVersion2026_07_28,
        capabilities: ClientCapabilities(),
        clientInfo: Implementation(name: 'client', version: '1.0.0'),
      ),
    ),
  );
  await _settle();

  final serverResponse = _expectSingleErrorFreeResponse(
    serverTransport.sentMessages,
    id: 'draft-initialize',
  );
  if (serverResponse.result['protocolVersion'] !=
      stableProtocolVersion2025_11_25) {
    throw StateError(
      'Expected initialize response protocolVersion '
      '$stableProtocolVersion2025_11_25, '
      'got ${serverResponse.result['protocolVersion']}.',
    );
  }
  if (serverResponse.result['protocolVersion'] ==
      _stableProtocolVersion2026_07_28) {
    throw StateError(
      'initialize must not negotiate a stateless protocol version.',
    );
  }
  await server.close();

  final clientTransport = _ConformanceTransport();
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
    ),
  );
  final connectFuture = client.connect(clientTransport);
  await _settle();

  final discoverRequest = clientTransport.sentMessages
      .whereType<JsonRpcRequest>()
      .singleWhere((request) => request.method == _serverDiscoverMethod);
  clientTransport.emit(
    JsonRpcError(
      id: discoverRequest.id,
      error: JsonRpcErrorData(
        code: ErrorCode.methodNotFound.value,
        message: 'Method not found',
      ),
    ),
  );
  await _settle();

  final initializeRequest = clientTransport.sentMessages
      .whereType<JsonRpcRequest>()
      .singleWhere((request) => request.method == Method.initialize);
  if (initializeRequest.params?['protocolVersion'] !=
      stableProtocolVersion2025_11_25) {
    throw StateError(
      'Expected fallback initialize request protocolVersion '
      '$stableProtocolVersion2025_11_25, got '
      '${initializeRequest.params?['protocolVersion']}.',
    );
  }
  if (initializeRequest.params?['protocolVersion'] ==
      _stableProtocolVersion2026_07_28) {
    throw StateError(
      'client fallback initialize must not send a stateless protocol version.',
    );
  }

  clientTransport.emit(_initializeResponse(id: initializeRequest.id));
  await connectFuture.timeout(const Duration(seconds: 1));
  await client.close();
}

Future<void> _statelessDoesNotInferInitializeExtensions() async {
  final transport = _ConformanceTransport();
  // Raw map parsing keeps this conformance case analyzable against the hosted
  // CLI package lower bound while still exercising the 2026 wire behavior.
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );

  await server.connect(transport);
  transport.emit(
    _initializeRequest(
      id: 'init',
      capabilities: const ClientCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );
  await _settle();
  _expectSingleErrorFreeResponse(transport.sentMessages, id: 'init');
  transport.sentMessages.clear();

  final request = JsonRpcMessage.fromJson(
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'stateless-subscribe',
      'method': _methodSubscriptionsListen,
      'params': <String, dynamic>{
        '_meta': _statelessRequestMeta(),
        'notifications': <String, dynamic>{
          'taskIds': <String>['task-1'],
        },
      },
    },
  );
  if (request is! JsonRpcRequest) {
    throw StateError(
      'Expected subscriptions/listen to parse as a request, got '
      '${request.runtimeType}.',
    );
  }

  transport.emit(request);
  await _settle();

  final error = _expectSingleError(
    transport.sentMessages,
    id: 'stateless-subscribe',
    code: ErrorCode.missingRequiredClientCapability.value,
    messageContains: 'Missing required client capability',
  );
  _expectMissingTasksExtensionCapabilityData(error.error.data);

  await server.close();
}

Future<void> _rejectsMismatchedStatelessHttpRoutingHeaders() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  try {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28)
      ..set('Mcp-Method', Method.toolsCall)
      ..set('Mcp-Name', 'wrong-tool');
    request.write(
      jsonEncode(
        <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 'http-header-mismatch',
          'method': Method.toolsCall,
          'params': <String, dynamic>{
            'name': 'actual-tool',
            'arguments': <String, dynamic>{},
            '_meta': _statelessRequestMeta(),
          },
        },
      ),
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Expected HTTP 400 for mismatched stateless routing headers, got '
        '${response.statusCode}.',
      );
    }
    if (responseBody['id'] != 'http-header-mismatch') {
      throw StateError(
        'Expected JSON-RPC error id http-header-mismatch, got '
        "${responseBody['id']}.",
      );
    }
    final error = responseBody['error'];
    if (error is! Map || error['code'] != _headerMismatchCode) {
      throw StateError('Expected HeaderMismatch error, got $error.');
    }
    final message = error['message'];
    if (message is! String || !message.contains('Mcp-Name header value')) {
      throw StateError('Expected Mcp-Name mismatch diagnostic, got $message.');
    }
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _requiresStatelessHttpRoutingHeaders() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  Future<void> expectHeaderMismatch(
    String id, {
    required void Function(HttpHeaders headers) addRoutingHeaders,
    required String messageFragment,
  }) async {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
    addRoutingHeaders(request.headers);
    request.write(
      jsonEncode(
        JsonRpcListToolsRequest(id: id, meta: _statelessRequestMeta()).toJson(),
      ),
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Expected HTTP 400 for missing stateless routing header, got '
        '${response.statusCode}: $responseBody.',
      );
    }
    if (responseBody['id'] != id) {
      throw StateError(
        'Expected JSON-RPC error id $id, got ${responseBody['id']}.',
      );
    }
    final error = responseBody['error'];
    if (error is! Map || error['code'] != _headerMismatchCode) {
      throw StateError('Expected HeaderMismatch error, got $error.');
    }
    final message = error['message'];
    if (message is! String || !message.contains(messageFragment)) {
      throw StateError(
        'Expected diagnostic containing $messageFragment, got $message.',
      );
    }
    if (response.headers.value('mcp-session-id') != null) {
      throw StateError(
        'Expected stateless header mismatch response to omit Mcp-Session-Id, '
        'got ${response.headers.value('mcp-session-id')}.',
      );
    }
  }

  try {
    await expectHeaderMismatch(
      'http-missing-protocol-header',
      addRoutingHeaders: (headers) {
        headers.set('Mcp-Method', Method.toolsList);
      },
      messageFragment: 'MCP-Protocol-Version header is required',
    );
    await expectHeaderMismatch(
      'http-missing-method-header',
      addRoutingHeaders: (headers) {
        headers.set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28);
      },
      messageFragment: 'Mcp-Method header is required',
    );
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _rejectsStatelessHttpNonPostMethods() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  Future<void> expectMethodNotAllowed(String method) async {
    final request = await httpClient.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers.set(
      'MCP-Protocol-Version',
      _stableProtocolVersion2026_07_28,
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

    if (response.statusCode != HttpStatus.methodNotAllowed) {
      throw StateError(
        'Expected HTTP 405 for stateless $method, got '
        '${response.statusCode}: $responseBody.',
      );
    }
    if (response.headers.value(HttpHeaders.allowHeader) != 'POST') {
      throw StateError(
        'Expected Allow: POST for stateless $method, got '
        '${response.headers.value(HttpHeaders.allowHeader)}.',
      );
    }
    final error = responseBody['error'];
    if (error is! Map || error['code'] != ErrorCode.connectionClosed.value) {
      throw StateError(
        'Expected stateless $method to return connection closed error, got '
        '$responseBody.',
      );
    }
    if (response.headers.value('mcp-session-id') != null) {
      throw StateError(
        'Expected stateless $method response to omit Mcp-Session-Id, got '
        '${response.headers.value('mcp-session-id')}.',
      );
    }
  }

  try {
    await expectMethodNotAllowed('GET');
    await expectMethodNotAllowed('DELETE');
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _rejectsStatelessHttpBatchPayloads() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
      rejectBatchJsonRpcPayloads: false,
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  try {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28);
    request.write(
      jsonEncode(
        <Map<String, dynamic>>[
          JsonRpcListToolsRequest(
            id: 'http-batch-tools-1',
            meta: _statelessRequestMeta(),
          ).toJson(),
          JsonRpcListToolsRequest(
            id: 'http-batch-tools-2',
            meta: _statelessRequestMeta(),
          ).toJson(),
        ],
      ),
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Expected HTTP 400 for stateless batch POST body, got '
        '${response.statusCode}: $responseBody.',
      );
    }
    if (responseBody.containsKey('id')) {
      throw StateError(
        'Expected batch-level JSON-RPC error to omit id, got $responseBody.',
      );
    }
    final error = responseBody['error'];
    if (error is! Map || error['code'] != ErrorCode.invalidRequest.value) {
      throw StateError('Expected InvalidRequest error, got $error.');
    }
    final message = error['message'];
    if (message is! String || !message.contains('must contain one')) {
      throw StateError(
        'Expected one-message diagnostic for stateless batch body, got '
        '$message.',
      );
    }
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _taskRequestsRequireStatelessHttpNameHeader() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
      enableJsonResponse: true,
    ),
  );
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  server.setRequestHandler<JsonRpcRequest>(
    _methodTasksUpdate,
    (request, extra) async => const EmptyResult(),
    (id, params, meta) => JsonRpcRequest(
      id: id,
      method: _methodTasksUpdate,
      params: params,
      meta: meta,
    ),
  );

  await server.connect(transport);
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  try {
    final missingNameRequest = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    missingNameRequest.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28)
      ..set('Mcp-Method', _methodTasksUpdate);
    missingNameRequest.write(
      jsonEncode(
        <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 'http-task-update-no-name',
          'method': _methodTasksUpdate,
          'params': <String, dynamic>{
            '_meta': _statelessRequestMeta(
              capabilities: const ClientCapabilities(
                extensions: <String, Map<String, dynamic>>{
                  _tasksExtensionId: <String, dynamic>{},
                },
              ),
            ),
            'taskId': 'task-1',
            'inputResponses': <String, dynamic>{},
          },
        },
      ),
    );

    final missingNameResponse = await missingNameRequest.close();
    final missingNameBody = jsonDecode(
      await utf8.decodeStream(missingNameResponse),
    ) as Map<String, dynamic>;

    if (missingNameResponse.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Expected HTTP 400 for task request without Mcp-Name, got '
        '${missingNameResponse.statusCode}: $missingNameBody.',
      );
    }
    final missingNameError = missingNameBody['error'];
    if (missingNameError is! Map ||
        missingNameError['code'] != _headerMismatchCode) {
      throw StateError(
        'Expected HeaderMismatch for missing task Mcp-Name, got '
        '$missingNameBody.',
      );
    }
    final missingNameMessage = missingNameError['message'];
    if (missingNameMessage is! String ||
        !missingNameMessage.contains('Mcp-Name header')) {
      throw StateError(
        'Expected missing Mcp-Name diagnostic, got $missingNameMessage.',
      );
    }

    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28)
      ..set('Mcp-Method', _methodTasksUpdate)
      ..set('Mcp-Name', 'task-1');
    request.write(
      jsonEncode(
        <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 'http-task-update-name',
          'method': _methodTasksUpdate,
          'params': <String, dynamic>{
            '_meta': _statelessRequestMeta(
              capabilities: const ClientCapabilities(
                extensions: <String, Map<String, dynamic>>{
                  _tasksExtensionId: <String, dynamic>{},
                },
              ),
            ),
            'taskId': 'task-1',
            'inputResponses': <String, dynamic>{},
          },
        },
      ),
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Expected HTTP 200 for task request with Mcp-Name, got '
        '${response.statusCode}: $responseBody.',
      );
    }
    if (responseBody['id'] != 'http-task-update-name') {
      throw StateError(
        'Expected JSON-RPC response id http-task-update-name, got '
        "${responseBody['id']}.",
      );
    }
    final result = responseBody['result'];
    if (result is! Map || result['resultType'] != _resultTypeComplete) {
      throw StateError('Expected complete task acknowledgement, got $result.');
    }
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await server.close();
  }
}

Future<void> _validatesStatelessHttpParameterHeaders() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
      enableJsonResponse: true,
    ),
  );
  // Keep this dynamic so mcp_dart_cli remains analyzable against the published
  // mcp_dart lower bound until this SDK branch is released.
  (transport as dynamic).setToolParameterHeaderMappings(
    const <String, Map<String, String>>{
      'execute': <String, String>{
        'count': 'Count',
        'dryRun': 'Dry-Run',
        'region': 'Region',
      },
    },
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  transport.onmessage = (message) {
    if (message is JsonRpcCallToolRequest) {
      unawaited(
        transport.send(
          JsonRpcResponse(
            id: message.id,
            result: const CallToolResult(content: <Content>[]).toJson(),
          ),
        ),
      );
    }
  };

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  Future<Map<String, dynamic>> postToolCall({
    required String id,
    required Map<String, String> headers,
    Map<String, dynamic> arguments = const <String, dynamic>{
      'dryRun': false,
      'region': 'us-east1',
    },
  }) async {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28)
      ..set('Mcp-Method', Method.toolsCall)
      ..set('Mcp-Name', 'execute');
    headers.forEach(request.headers.set);
    request.write(
      jsonEncode(
        JsonRpcCallToolRequest(
          id: id,
          params: <String, dynamic>{
            'name': 'execute',
            'arguments': arguments,
          },
          meta: _statelessRequestMeta(),
        ).toJson(),
      ),
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
    return <String, dynamic>{
      'statusCode': response.statusCode,
      'body': responseBody,
    };
  }

  void expectHeaderMismatch(
    Map<String, dynamic> response, {
    required String id,
    required String messageFragment,
  }) {
    final statusCode = response['statusCode'];
    final responseBody = response['body'] as Map<String, dynamic>;
    if (statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Expected HTTP 400 for parameter header mismatch, got '
        '$statusCode: $responseBody.',
      );
    }
    if (responseBody['id'] != id) {
      throw StateError(
        'Expected JSON-RPC error id $id, got ${responseBody['id']}.',
      );
    }
    final error = responseBody['error'];
    if (error is! Map || error['code'] != _headerMismatchCode) {
      throw StateError('Expected HeaderMismatch error, got $error.');
    }
    final message = error['message'];
    if (message is! String || !message.contains(messageFragment)) {
      throw StateError(
        'Expected diagnostic containing $messageFragment, got $message.',
      );
    }
  }

  try {
    expectHeaderMismatch(
      await postToolCall(
        id: 'http-missing-param-header',
        headers: const <String, String>{
          'Mcp-Param-Region': 'us-east1',
        },
      ),
      id: 'http-missing-param-header',
      messageFragment: 'Mcp-Param-Dry-Run header is required',
    );

    expectHeaderMismatch(
      await postToolCall(
        id: 'http-mismatched-param-header',
        headers: const <String, String>{
          'Mcp-Param-Dry-Run': 'true',
          'Mcp-Param-Region': 'us-east1',
        },
      ),
      id: 'http-mismatched-param-header',
      messageFragment: "body argument 'dryRun'",
    );

    final success = await postToolCall(
      id: 'http-matched-param-headers',
      arguments: const <String, dynamic>{
        'count': 42,
        'dryRun': false,
        'region': 'us-east1',
      },
      headers: const <String, String>{
        'Mcp-Param-Count': '42',
        'Mcp-Param-Dry-Run': 'false',
        'Mcp-Param-Region': 'us-east1',
      },
    );
    final statusCode = success['statusCode'];
    final responseBody = success['body'] as Map<String, dynamic>;
    if (statusCode != HttpStatus.ok) {
      throw StateError(
        'Expected HTTP 200 for matching parameter headers, got '
        '$statusCode: $responseBody.',
      );
    }
    if (responseBody['id'] != 'http-matched-param-headers') {
      throw StateError('Unexpected matched parameter response $responseBody.');
    }
    final result = responseBody['result'];
    if (result is! Map || result['content'] is! List) {
      throw StateError('Expected successful tool result, got $result.');
    }
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _omitsUnsafeNumericParameterHeaders() async {
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final receivedHeaders = Completer<Map<String, String?>>();
  final responseMessage = Completer<JsonRpcMessage>();
  final transport = StreamableHttpClientTransport(
    Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
  )..protocolVersion = _stableProtocolVersion2026_07_28;
  // Keep this dynamic so mcp_dart_cli remains analyzable against the published
  // mcp_dart lower bound until this SDK branch is released.
  (transport as dynamic).setToolParameterHeaderMappings(
    const <String, Map<String, String>>{
      'calculate': <String, String>{
        'limit': 'Limit',
        'ratio': 'Ratio',
        'unsafe': 'Unsafe',
      },
    },
  );

  final serverSubscription = httpServer.listen((request) async {
    if (!receivedHeaders.isCompleted) {
      receivedHeaders.complete(
        <String, String?>{
          'limit': request.headers.value('mcp-param-limit'),
          'ratio': request.headers.value('mcp-param-ratio'),
          'unsafe': request.headers.value('mcp-param-unsafe'),
        },
      );
    }
    await request.drain<void>();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(
          const JsonRpcResponse(
            id: 'number-headers',
            result: <String, dynamic>{
              'resultType': _resultTypeComplete,
              'content': <Object>[],
            },
          ).toJson(),
        ),
      );
    await request.response.close();
  });

  transport.onmessage = responseMessage.complete;
  await transport.start();

  try {
    await transport.send(
      JsonRpcCallToolRequest(
        id: 'number-headers',
        params: const <String, dynamic>{
          'name': 'calculate',
          'arguments': <String, dynamic>{
            'limit': 42,
            'ratio': 1.5,
            'unsafe': 9007199254740992,
          },
        },
        meta: _statelessRequestMeta(),
      ),
    );

    final headers = await receivedHeaders.future.timeout(
      const Duration(seconds: 5),
    );
    if (headers['limit'] != '42') {
      throw StateError(
        'Expected safe integer header 42, got ${headers['limit']}.',
      );
    }
    if (headers['ratio'] != '1.5') {
      throw StateError(
        'Expected fractional number header 1.5, got '
        "${headers['ratio']}.",
      );
    }
    if (headers['unsafe'] != null) {
      throw StateError(
        'Expected unsafe integer header to be omitted, got '
        "${headers['unsafe']}.",
      );
    }

    final response = await responseMessage.future.timeout(
      const Duration(seconds: 5),
    );
    if (response is! JsonRpcResponse || response.id != 'number-headers') {
      throw StateError('Expected JSON-RPC response, got $response.');
    }
  } finally {
    await transport.close();
    await serverSubscription.cancel();
    await httpServer.close(force: true);
  }
}

Future<void> _encodesStatelessHttpParameterHeaderValues() async {
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final receivedHeaders = Completer<Map<String, String?>>();
  final responseMessage = Completer<JsonRpcMessage>();
  final transport = StreamableHttpClientTransport(
    Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
  )..protocolVersion = _stableProtocolVersion2026_07_28;
  // Keep this dynamic so mcp_dart_cli remains analyzable against the published
  // mcp_dart lower bound until this SDK branch is released.
  (transport as dynamic).setToolParameterHeaderMappings(
    const <String, Map<String, String>>{
      'echo': <String, String>{
        'greeting': 'Greeting',
        'plain': 'Plain',
        'sentinel': 'Sentinel',
        'spaced': 'Spaced',
      },
    },
  );

  final serverSubscription = httpServer.listen((request) async {
    if (!receivedHeaders.isCompleted) {
      receivedHeaders.complete(
        <String, String?>{
          'greeting': request.headers.value('mcp-param-greeting'),
          'plain': request.headers.value('mcp-param-plain'),
          'sentinel': request.headers.value('mcp-param-sentinel'),
          'spaced': request.headers.value('mcp-param-spaced'),
        },
      );
    }
    await request.drain<void>();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(
          const JsonRpcResponse(
            id: 'encoded-headers',
            result: <String, dynamic>{
              'resultType': _resultTypeComplete,
              'content': <Object>[],
            },
          ).toJson(),
        ),
      );
    await request.response.close();
  });

  transport.onmessage = responseMessage.complete;
  await transport.start();

  String encodedHeaderValue(String value) =>
      '=?base64?${base64Encode(utf8.encode(value))}?=';

  final nonAsciiGreeting = 'Hello, ${String.fromCharCodes(
    const <int>[0x4e16, 0x754c],
  )}';

  try {
    await transport.send(
      JsonRpcCallToolRequest(
        id: 'encoded-headers',
        params: <String, dynamic>{
          'name': 'echo',
          'arguments': <String, dynamic>{
            'greeting': nonAsciiGreeting,
            'plain': 'us-east1',
            'sentinel': '=?base64?literal?=',
            'spaced': ' padded ',
          },
        },
        meta: _statelessRequestMeta(),
      ),
    );

    final headers = await receivedHeaders.future.timeout(
      const Duration(seconds: 5),
    );
    final expectedGreeting = encodedHeaderValue(nonAsciiGreeting);
    if (headers['greeting'] != expectedGreeting) {
      throw StateError(
        'Expected non-ASCII string header $expectedGreeting, got '
        "${headers['greeting']}.",
      );
    }
    if (headers['plain'] != 'us-east1') {
      throw StateError(
        'Expected plain string header us-east1, got ${headers['plain']}.',
      );
    }
    final expectedSentinel = encodedHeaderValue('=?base64?literal?=');
    if (headers['sentinel'] != expectedSentinel) {
      throw StateError(
        'Expected sentinel-looking string header $expectedSentinel, got '
        "${headers['sentinel']}.",
      );
    }
    final expectedSpaced = encodedHeaderValue(' padded ');
    if (headers['spaced'] != expectedSpaced) {
      throw StateError(
        'Expected trim-sensitive string header $expectedSpaced, got '
        "${headers['spaced']}.",
      );
    }

    final response = await responseMessage.future.timeout(
      const Duration(seconds: 5),
    );
    if (response is! JsonRpcResponse || response.id != 'encoded-headers') {
      throw StateError('Expected JSON-RPC response, got $response.');
    }
  } finally {
    await transport.close();
    await serverSubscription.cancel();
    await httpServer.close(force: true);
  }
}

Future<void> _acceptsStatelessHttpResponsePosts() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
      enableJsonResponse: true,
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();
  final receivedMessage = Completer<JsonRpcMessage>();

  transport.onmessage = receivedMessage.complete;

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  try {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28);
    request.write(
      jsonEncode(
        const JsonRpcResponse(
          id: 'http-input-response',
          result: <String, dynamic>{'ok': true},
        ).toJson(),
      ),
    );

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode != HttpStatus.accepted) {
      throw StateError(
        'Expected HTTP 202 for stateless response POST, got '
        '${response.statusCode}: $responseBody.',
      );
    }
    if (responseBody.isNotEmpty) {
      throw StateError(
        'Expected empty stateless response POST body, got $responseBody.',
      );
    }

    final message = await receivedMessage.future.timeout(
      const Duration(seconds: 5),
    );
    if (message is! JsonRpcResponse) {
      throw StateError(
        'Expected server transport to receive JsonRpcResponse, got '
        '${message.runtimeType}.',
      );
    }
    if (message.id != 'http-input-response' || message.result['ok'] != true) {
      throw StateError('Unexpected stateless response POST message $message.');
    }
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _statelessHttpOmitsSessionHeaderAfterInitialize() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => 'stateful-session-id',
      enableDnsRebindingProtection: false,
      enableJsonResponse: true,
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  transport.onmessage = (message) {
    if (message is JsonRpcInitializeRequest) {
      unawaited(
        transport.send(
          JsonRpcResponse(
            id: message.id,
            result: const InitializeResult(
              protocolVersion: stableProtocolVersion2025_11_25,
              capabilities: ServerCapabilities(),
              serverInfo: Implementation(
                name: 'conformance-server',
                version: '1.0.0',
              ),
            ).toJson(),
          ),
        ),
      );
    } else if (message is JsonRpcListToolsRequest) {
      unawaited(
        transport.send(
          JsonRpcResponse(
            id: message.id,
            result: const ListToolsResult(tools: <Tool>[]).toJson(),
          ),
        ),
      );
    }
  };

  await transport.start();
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  try {
    final initRequest = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    initRequest.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
    initRequest.write(
      jsonEncode(
        JsonRpcInitializeRequest(
          id: 'initialize-session',
          initParams: const InitializeRequest(
            protocolVersion: stableProtocolVersion2025_11_25,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'client', version: '1.0.0'),
          ),
        ).toJson(),
      ),
    );

    final initResponse = await initRequest.close();
    await utf8.decodeStream(initResponse);
    final sessionId = initResponse.headers.value('mcp-session-id');
    if (initResponse.statusCode != HttpStatus.ok ||
        sessionId != 'stateful-session-id') {
      throw StateError(
        'Expected stateful initialize to create a session, got '
        '${initResponse.statusCode} with session $sessionId.',
      );
    }
    final confirmedSessionId = sessionId!;

    final statelessRequest = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    statelessRequest.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28)
      ..set('Mcp-Method', Method.toolsList)
      ..set('Mcp-Session-Id', confirmedSessionId);
    statelessRequest.write(
      jsonEncode(
        JsonRpcListToolsRequest(
          id: 'stateless-tools',
          meta: _statelessRequestMeta(),
        ).toJson(),
      ),
    );

    final statelessResponse = await statelessRequest.close();
    final responseBody = jsonDecode(await utf8.decodeStream(statelessResponse))
        as Map<String, dynamic>;
    if (statelessResponse.statusCode != HttpStatus.ok) {
      throw StateError(
        'Expected stateless request to succeed, got '
        '${statelessResponse.statusCode}: $responseBody.',
      );
    }
    if (statelessResponse.headers.value('mcp-session-id') != null) {
      throw StateError(
        'Expected stateless response to omit Mcp-Session-Id, got '
        '${statelessResponse.headers.value('mcp-session-id')}.',
      );
    }
    if (responseBody['id'] != 'stateless-tools') {
      throw StateError('Unexpected stateless response body $responseBody.');
    }
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await transport.close();
  }
}

Future<void> _taskSubscriptionRequiresClientCapability() async {
  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(
      sessionIdGenerator: () => null,
      enableDnsRebindingProtection: false,
    ),
  );
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final httpClient = HttpClient();

  await server.connect(transport);
  final serverSubscription = httpServer.listen((request) {
    unawaited(transport.handleRequest(request));
  });

  try {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${httpServer.port}/mcp'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set('MCP-Protocol-Version', _stableProtocolVersion2026_07_28)
      ..set('Mcp-Method', _methodSubscriptionsListen);
    request.write(
      jsonEncode(
        <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': 'http-task-subscription-capability',
          'method': _methodSubscriptionsListen,
          'params': <String, dynamic>{
            '_meta': _statelessRequestMeta(),
            'notifications': <String, dynamic>{
              'taskIds': <String>['task-1'],
            },
          },
        },
      ),
    );

    final response = await request.close();
    final responseBody =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;

    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Expected HTTP 400 for missing stateless task extension capability, got '
        '${response.statusCode}.',
      );
    }
    if (responseBody['id'] != 'http-task-subscription-capability') {
      throw StateError(
        'Expected JSON-RPC error id http-task-subscription-capability, got '
        "${responseBody['id']}.",
      );
    }
    final error = responseBody['error'];
    if (error is! Map ||
        error['code'] != ErrorCode.missingRequiredClientCapability.value) {
      throw StateError(
        'Expected MissingRequiredClientCapability error, got $error.',
      );
    }
    if (!'${error['message']}'.contains('Missing required client capability')) {
      throw StateError(
        'Expected MissingRequiredClientCapability message, '
        'got ${error['message']}.',
      );
    }
    _expectMissingTasksExtensionCapabilityData(error['data']);
  } finally {
    httpClient.close(force: true);
    await serverSubscription.cancel();
    await httpServer.close(force: true);
    await server.close();
  }
}

Future<void> _relatedTaskUsesExplicitIdAcrossTransports() async {
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );
  var handlerCalls = 0;
  final seenTaskIds = <String>[];
  final errors = <Error>[];
  server.onerror = errors.add;
  server.setRequestHandler<JsonRpcRequest>(
    _methodTasksUpdate,
    (request, extra) async {
      if (extra.sessionId != null) {
        throw StateError('Stateless task request unexpectedly had a session.');
      }
      final params = request.params;
      if (params == null) {
        throw StateError('Expected task update params.');
      }
      final taskId = params['taskId'];
      if (taskId is! String) {
        throw StateError('Expected task update params to include taskId.');
      }
      final inputResponses = params['inputResponses'];
      if (inputResponses is! Map || inputResponses.isNotEmpty) {
        throw StateError('Expected empty task inputResponses.');
      }
      handlerCalls += 1;
      seenTaskIds.add(taskId);
      return const EmptyResult();
    },
    (id, params, meta) => JsonRpcRequest(
      id: id,
      method: _methodTasksUpdate,
      params: params,
      meta: meta,
    ),
  );

  Future<Map<String, dynamic>> updateTaskOverNewTransport(int id) async {
    final transport = _ConformanceTransport();
    await server.connect(transport);
    transport.emit(
      JsonRpcRequest(
        id: id,
        method: _methodTasksUpdate,
        params: const <String, dynamic>{
          'taskId': 'task-connection',
          'inputResponses': <String, dynamic>{},
        },
        meta: _statelessRequestMeta(
          capabilities: const ClientCapabilities(
            extensions: <String, Map<String, dynamic>>{
              _tasksExtensionId: <String, dynamic>{},
            },
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (transport.sentMessages.isEmpty && errors.isNotEmpty) {
      throw StateError('Server errors: $errors.');
    }
    final response = _expectSingleErrorFreeResponse(
      transport.sentMessages,
      id: id,
    );
    await server.close();
    return response.result;
  }

  try {
    final firstResult = await updateTaskOverNewTransport(201);
    final secondResult = await updateTaskOverNewTransport(202);

    if (seenTaskIds.length != 2 ||
        seenTaskIds.any((taskId) => taskId != 'task-connection')) {
      throw StateError(
        'Expected both task updates to use the explicit task ID, got '
        '$seenTaskIds.',
      );
    }
    if (firstResult['resultType'] != _resultTypeComplete ||
        secondResult['resultType'] != _resultTypeComplete) {
      throw StateError(
        'Expected stateless task updates to receive complete acknowledgements, '
        'got $firstResult and $secondResult.',
      );
    }
    if (handlerCalls != 2) {
      throw StateError('Expected two task handler calls, got $handlerCalls.');
    }
  } finally {
    await server.close();
  }
}

Future<void> _statelessIgnoresLegacyTaskParameter() async {
  final transport = _ConformanceTransport();
  RequestHandlerExtra? receivedExtra;
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        tasks: ServerCapabilitiesTasks(
          requests: ServerCapabilitiesTasksRequests(
            tools: ServerCapabilitiesTasksTools(
              call: ServerCapabilitiesTasksToolsCall(),
            ),
          ),
        ),
      ),
    ),
  );
  server.setRequestHandler<JsonRpcCallToolRequest>(
    Method.toolsCall,
    (request, extra) async {
      receivedExtra = extra;
      return const CallToolResult(
        content: <Content>[TextContent(text: 'ok')],
      );
    },
    (id, params, meta) => JsonRpcCallToolRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsCall,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );

  await server.connect(transport);
  transport.emit(
    JsonRpcCallToolRequest(
      id: 'legacy-task-param',
      params: <String, dynamic>{
        ...const CallToolRequest(name: 'legacy-task').toJson(),
        'task': <String, dynamic>{'ttl': 1000},
      },
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  final response = _expectSingleErrorFreeResponse(
    transport.sentMessages,
    id: 'legacy-task-param',
  );
  if (response.result['resultType'] != _resultTypeComplete ||
      receivedExtra?.taskRequestedTtl != null) {
    throw StateError(
      'Expected stateless request to ignore legacy task parameter; result '
      '${response.result}, taskRequestedTtl '
      '${receivedExtra?.taskRequestedTtl}.',
    );
  }

  await server.close();
}

Future<void> _statelessClientRejectsLegacyTaskOptions() async {
  final transport = _DiscoveringConformanceTransport(
    toolsListResult: const <String, dynamic>{
      'resultType': _resultTypeComplete,
      'tools': <dynamic>[],
      'ttlMs': 0,
      'cacheScope': CacheScope.private,
    },
    toolsCallResult: const <String, dynamic>{
      'resultType': _resultTypeComplete,
      'content': <dynamic>[],
    },
  );
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
    ),
  );

  await client.connect(transport);
  final sentBeforeCall = transport.sentMessages.length;

  try {
    await client.callTool(
      const CallToolRequest(name: 'legacy-task'),
      options: const RequestOptions(task: TaskCreation(ttl: 1000)),
    );
  } on McpError catch (error) {
    if (error.code != ErrorCode.invalidRequest.value ||
        !error.message.contains('RequestOptions.task')) {
      throw StateError(
        'Expected InvalidRequest for RequestOptions.task, got '
        '${error.code}: ${error.message}.',
      );
    }
    final toolsCallRequests = transport.sentMessages
        .skip(sentBeforeCall)
        .whereType<JsonRpcRequest>()
        .where((request) => request.method == Method.toolsCall)
        .toList();
    if (toolsCallRequests.isNotEmpty) {
      throw StateError(
        'Expected no stateless tools/call request after legacy task option, '
        'got ${toolsCallRequests.single.toJson()}.',
      );
    }
    await client.close();
    return;
  }

  await client.close();
  throw StateError('Expected stateless client to reject RequestOptions.task.');
}

Future<void> _statelessAddsResultTypeAndCacheDefaults() async {
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        prompts: ServerCapabilitiesPrompts(),
        resources: ServerCapabilitiesResources(),
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );
  server.setRequestHandler<JsonRpcListToolsRequest>(
    Method.toolsList,
    (request, extra) async => const ListToolsResult(
      tools: <Tool>[],
      ttlMs: 300000,
      cacheScope: CacheScope.public,
    ),
    (id, params, meta) => JsonRpcListToolsRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsList,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );
  server.setRequestHandler<JsonRpcListPromptsRequest>(
    Method.promptsList,
    (request, extra) async => const ListPromptsResult(prompts: <Prompt>[]),
    (id, params, meta) => JsonRpcListPromptsRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.promptsList,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );
  server.setRequestHandler<JsonRpcListResourcesRequest>(
    Method.resourcesList,
    (request, extra) async => const ListResourcesResult(
      resources: <Resource>[],
    ),
    (id, params, meta) => JsonRpcListResourcesRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesList,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );
  server.setRequestHandler<JsonRpcListResourceTemplatesRequest>(
    Method.resourcesTemplatesList,
    (request, extra) async => const ListResourceTemplatesResult(
      resourceTemplates: <ResourceTemplate>[],
    ),
    (id, params, meta) => JsonRpcListResourceTemplatesRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesTemplatesList,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );
  server.setRequestHandler<JsonRpcReadResourceRequest>(
    Method.resourcesRead,
    (request, extra) async => const ReadResourceResult(
      contents: <ResourceContents>[
        TextResourceContents(uri: 'file:///a.txt', text: 'a'),
      ],
    ),
    (id, params, meta) => JsonRpcReadResourceRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesRead,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );

  await server.connect(transport);
  final requests = <JsonRpcRequest>[
    JsonRpcListToolsRequest(
      id: 'tools-list',
      meta: _statelessRequestMeta(),
    ),
    JsonRpcListPromptsRequest(
      id: 'prompts-list',
      meta: _statelessRequestMeta(),
    ),
    JsonRpcListResourcesRequest(
      id: 'resources-list',
      meta: _statelessRequestMeta(),
    ),
    JsonRpcListResourceTemplatesRequest(
      id: 'resource-templates-list',
      meta: _statelessRequestMeta(),
    ),
    JsonRpcReadResourceRequest(
      id: 'resources-read',
      readParams: const ReadResourceRequest(uri: 'file:///a.txt'),
      meta: _statelessRequestMeta(),
    ),
  ];
  for (final request in requests) {
    transport.emit(request);
    await _settle();
  }

  final responses = transport.sentMessages.cast<JsonRpcResponse>().toList();
  if (responses.length != requests.length) {
    throw StateError(
      'Expected ${requests.length} cacheable responses, got '
      '${responses.length}: ${transport.sentMessages}.',
    );
  }

  for (final response in responses) {
    final result = response.result;
    if (result['resultType'] != _resultTypeComplete) {
      throw StateError(
        'Expected stateless ${response.id} resultType complete, got $result.',
      );
    }
  }

  final toolsResult = responses.first.result;
  if (toolsResult['ttlMs'] != 300000 ||
      toolsResult['cacheScope'] != CacheScope.public) {
    throw StateError(
      'Expected explicit tools/list cache hints to be preserved, got '
      '$toolsResult.',
    );
  }

  for (final response in responses.skip(1)) {
    final result = response.result;
    if (result['ttlMs'] != 0 || result['cacheScope'] != _cacheScopePrivate) {
      throw StateError(
        'Expected stateless ${response.id} cache defaults, got $result.',
      );
    }
  }

  await server.close();
}

Future<void> _statelessToolsListReturnsDeterministicOrder() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );
  for (final name in const <String>['zeta', 'alpha', 'middle']) {
    server.registerTool(
      name,
      callback: (args, extra) async {
        return const CallToolResult(
          content: <Content>[TextContent(text: 'ok')],
        );
      },
    );
  }

  await server.connect(transport);
  transport.emit(
    JsonRpcListToolsRequest(
      id: 'tools-order',
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  final response = _expectSingleErrorFreeResponse(
    transport.sentMessages,
    id: 'tools-order',
  );
  final tools = response.result['tools'];
  if (tools is! List) {
    throw StateError('Expected tools/list result tools array, got $tools.');
  }
  final names = tools.map((tool) {
    if (tool is! Map) {
      throw StateError('Expected tool object, got $tool.');
    }
    final name = tool['name'];
    if (name is! String) {
      throw StateError('Expected tool name string, got $tool.');
    }
    return name;
  }).toList(growable: false);
  const expectedNames = <String>['alpha', 'middle', 'zeta'];
  if (!_stringListEquals(names, expectedNames)) {
    throw StateError(
      'Expected deterministic tools/list order $expectedNames, got $names.',
    );
  }

  await server.close();
}

Future<void> _statelessToolsListOmitsLegacyExecution() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );
  server.server.setRequestHandler<JsonRpcListToolsRequest>(
    Method.toolsList,
    (request, extra) async => const ListToolsResult(
      tools: <Tool>[
        Tool(
          name: 'task-tool',
          inputSchema: JsonObject(),
          execution: ToolExecution(taskSupport: 'required'),
        ),
      ],
    ),
    (id, params, meta) => JsonRpcListToolsRequest(
      id: id,
      params: params,
      meta: meta,
    ),
  );

  await server.connect(transport);
  transport.emit(
    JsonRpcListToolsRequest(
      id: 'tools-execution',
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  final response = _expectSingleErrorFreeResponse(
    transport.sentMessages,
    id: 'tools-execution',
  );
  final tools = response.result['tools'];
  if (tools is! List || tools.length != 1 || tools.single is! Map) {
    throw StateError('Expected one tool object, got $tools.');
  }
  final tool = tools.single as Map;
  if (tool.containsKey('execution')) {
    throw StateError(
      'Expected stateless tools/list to omit legacy execution, got $tool.',
    );
  }

  await server.close();
}

Future<void> _missingResourceErrorCodeByVersion() async {
  final legacyTransport = _ConformanceTransport();
  final legacyServer = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
  );
  legacyServer.registerResource(
    'Known Resource',
    'memory://known',
    null,
    (uri, extra) async => ReadResourceResult(
      contents: <ResourceContents>[
        TextResourceContents(uri: uri.toString(), text: 'known'),
      ],
    ),
  );

  await _initializeMcpServer(legacyServer, legacyTransport);
  legacyTransport.emit(
    JsonRpcReadResourceRequest(
      id: 'legacy-missing-resource',
      readParams: const ReadResourceRequest(uri: 'memory://missing'),
    ),
  );
  await _settle();

  var error = _expectSingleError(
    legacyTransport.sentMessages,
    id: 'legacy-missing-resource',
    code: ErrorCode.resourceNotFound.value,
    messageContains: 'Resource not found',
  );
  if (error.error.data is! Map ||
      (error.error.data as Map)['uri'] != 'memory://missing') {
    throw StateError(
      'Expected legacy missing resource URI in error data, got '
      '${error.error.data}.',
    );
  }
  await legacyServer.close();

  final statelessTransport = _ConformanceTransport();
  final statelessServer = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
    ),
  );
  statelessServer.registerResource(
    'Known Resource',
    'memory://known',
    null,
    (uri, extra) async => ReadResourceResult(
      contents: <ResourceContents>[
        TextResourceContents(uri: uri.toString(), text: 'known'),
      ],
    ),
  );

  await statelessServer.connect(statelessTransport);
  statelessTransport.emit(
    JsonRpcReadResourceRequest(
      id: 'stateless-missing-resource',
      readParams: const ReadResourceRequest(uri: 'memory://missing'),
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  error = _expectSingleError(
    statelessTransport.sentMessages,
    id: 'stateless-missing-resource',
    code: ErrorCode.invalidParams.value,
    messageContains: 'Resource not found',
  );
  if (error.error.data is! Map ||
      (error.error.data as Map)['uri'] != 'memory://missing') {
    throw StateError(
      'Expected stateless missing resource URI in error data, got '
      '${error.error.data}.',
    );
  }

  await statelessServer.close();
}

Future<void> _statelessRejectsUnrecognizedResultType() async {
  final transport = _DiscoveringConformanceTransport(
    toolsListResult: const <String, dynamic>{
      'resultType': _resultTypeFutureExtension,
      'tools': <Object>[],
      'ttlMs': 0,
      'cacheScope': _cacheScopePrivate,
    },
  );
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
    ),
  );

  try {
    await client.connect(transport);
    try {
      await client.listTools();
    } on McpError catch (error) {
      if (error.code != ErrorCode.internalError.value) {
        throw StateError(
          'Expected internal error for unrecognized resultType, got '
          '${error.code}.',
        );
      }
      final data = error.data.toString();
      if (!data.contains(
        'Unrecognized MCP resultType "$_resultTypeFutureExtension"',
      )) {
        throw StateError(
          'Expected unrecognized resultType diagnostic, got ${error.data}.',
        );
      }
      return;
    }

    throw StateError(
      'Expected unrecognized stateless resultType to be rejected.',
    );
  } finally {
    await client.close();
  }
}

Future<void> _mrtrInputRequiredSupportedRequests() async {
  final transport = _ConformanceTransport();
  // Raw protocol conformance needs the low-level server so resultType
  // validation is exercised directly at the JSON-RPC boundary.
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        prompts: ServerCapabilitiesPrompts(),
        resources: ServerCapabilitiesResources(),
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  server.setRequestHandler<JsonRpcCallToolRequest>(
    Method.toolsCall,
    (request, extra) async =>
        const InputRequiredResult(requestState: 'tool-state'),
    (id, params, meta) => JsonRpcCallToolRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsCall,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );
  server.setRequestHandler<JsonRpcGetPromptRequest>(
    Method.promptsGet,
    (request, extra) async =>
        const InputRequiredResult(requestState: 'prompt-state'),
    (id, params, meta) => JsonRpcGetPromptRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.promptsGet,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );
  server.setRequestHandler<JsonRpcReadResourceRequest>(
    Method.resourcesRead,
    (request, extra) async =>
        const InputRequiredResult(requestState: 'resource-state'),
    (id, params, meta) => JsonRpcReadResourceRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesRead,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );

  try {
    await server.connect(transport);

    final scenarios = <MapEntry<JsonRpcRequest, String>>[
      MapEntry<JsonRpcRequest, String>(
        JsonRpcCallToolRequest(
          id: 'mrtr-tool',
          params: const CallToolRequest(name: 'needs-input').toJson(),
          meta: _statelessRequestMeta(),
        ),
        'tool-state',
      ),
      MapEntry<JsonRpcRequest, String>(
        JsonRpcGetPromptRequest(
          id: 'mrtr-prompt',
          getParams: const GetPromptRequest(name: 'needs_input'),
          meta: _statelessRequestMeta(),
        ),
        'prompt-state',
      ),
      MapEntry<JsonRpcRequest, String>(
        JsonRpcReadResourceRequest(
          id: 'mrtr-resource',
          readParams: const ReadResourceRequest(uri: 'memory://needs-input'),
          meta: _statelessRequestMeta(),
        ),
        'resource-state',
      ),
    ];

    for (final scenario in scenarios) {
      transport.sentMessages.clear();
      transport.emit(scenario.key);
      await _settle();

      final response = _expectSingleErrorFreeResponse(
        transport.sentMessages,
        id: scenario.key.id,
      );
      if (response.result['resultType'] != _resultTypeInputRequired ||
          response.result['requestState'] != scenario.value) {
        throw StateError(
          'Expected ${scenario.key.method} to allow input_required with '
          'requestState ${scenario.value}, got ${response.result}.',
        );
      }
    }
  } finally {
    await server.close();
  }
}

Future<void> _mrtrRejectsUnsupportedInputRequiredResults() async {
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  server.setRequestHandler<JsonRpcListToolsRequest>(
    Method.toolsList,
    (request, extra) async =>
        const InputRequiredResult(requestState: 'list-state'),
    (id, params, meta) => JsonRpcListToolsRequest(
      id: id,
      params: params,
      meta: meta,
    ),
  );

  try {
    await server.connect(transport);
    transport.emit(
      JsonRpcListToolsRequest(
        id: 'mrtr-list-tools',
        meta: _statelessRequestMeta(),
      ),
    );
    await _settle();

    _expectSingleError(
      transport.sentMessages,
      id: 'mrtr-list-tools',
      code: ErrorCode.invalidParams.value,
      messageContains: 'InputRequiredResult',
    );
  } finally {
    await server.close();
  }
}

Future<void> _mrtrInputRequestsRequireClientCapabilities() async {
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  server.setRequestHandler<JsonRpcCallToolRequest>(
    Method.toolsCall,
    (request, extra) async {
      final inputRequest = switch (request.callParams.name) {
        'needs-form' => InputRequest.elicit(
            ElicitRequest.form(
              message: 'Enter name',
              requestedSchema: JsonSchema.object(
                properties: <String, JsonSchema>{
                  'name': JsonSchema.string(),
                },
                required: const <String>['name'],
              ),
            ),
          ),
        'needs-url' => InputRequest.elicit(
            const ElicitRequest.url(
              message: 'Open browser',
              url: 'https://example.com/authorize',
            ),
          ),
        'needs-roots' => InputRequest.listRoots(),
        'needs-sampling-tools' => InputRequest.createMessage(
            const CreateMessageRequest(
              messages: <SamplingMessage>[
                SamplingMessage(
                  role: SamplingMessageRole.user,
                  content: SamplingTextContent(text: 'Search'),
                ),
              ],
              maxTokens: 16,
              tools: <Tool>[
                Tool(name: 'lookup', inputSchema: JsonObject()),
              ],
            ),
          ),
        _ => throw StateError('Unknown tool ${request.callParams.name}'),
      };

      return InputRequiredResult(
        inputRequests: <String, InputRequest>{
          request.callParams.name: inputRequest,
        },
      );
    },
    (id, params, meta) => JsonRpcCallToolRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsCall,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );

  final missingCapabilityScenarios = <_MissingCapabilityScenario>[
    _MissingCapabilityScenario(
      name: 'needs-form',
      capabilities: const ClientCapabilities(),
      method: Method.elicitationCreate,
      requiredCapabilities: const <String, dynamic>{
        'elicitation': <String, dynamic>{
          'form': <String, dynamic>{},
        },
      },
    ),
    _MissingCapabilityScenario(
      name: 'needs-url',
      capabilities: const ClientCapabilities(
        elicitation: ClientElicitation.formOnly(),
      ),
      method: Method.elicitationCreate,
      requiredCapabilities: const <String, dynamic>{
        'elicitation': <String, dynamic>{
          'url': <String, dynamic>{},
        },
      },
    ),
    _MissingCapabilityScenario(
      name: 'needs-roots',
      capabilities: const ClientCapabilities(),
      method: Method.rootsList,
      requiredCapabilities: const <String, dynamic>{
        'roots': <String, dynamic>{},
      },
    ),
    _MissingCapabilityScenario(
      name: 'needs-sampling-tools',
      capabilities: const ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
      ),
      method: Method.samplingCreateMessage,
      requiredCapabilities: const <String, dynamic>{
        'sampling': <String, dynamic>{
          'tools': <String, dynamic>{},
        },
      },
    ),
  ];

  try {
    await server.connect(transport);

    for (final scenario in missingCapabilityScenarios) {
      transport.sentMessages.clear();
      transport.emit(
        JsonRpcCallToolRequest(
          id: scenario.name,
          params: CallToolRequest(name: scenario.name).toJson(),
          meta: _statelessRequestMeta(capabilities: scenario.capabilities),
        ),
      );
      await _settle();

      final error = _expectSingleError(
        transport.sentMessages,
        id: scenario.name,
        code: ErrorCode.missingRequiredClientCapability.value,
        messageContains: 'Missing required client capability',
      );
      final data = error.error.data;
      if (data is! Map ||
          data['inputRequest'] != scenario.name ||
          data['method'] != scenario.method ||
          !_mapsDeepEqual(
            data['requiredCapabilities'],
            scenario.requiredCapabilities,
          )) {
        throw StateError(
          'Expected missing client capability details for ${scenario.name}, '
          'got $data.',
        );
      }
    }

    transport.sentMessages.clear();
    transport.emit(
      JsonRpcCallToolRequest(
        id: 'mrtr-allowed-form',
        params: const CallToolRequest(name: 'needs-form').toJson(),
        meta: _statelessRequestMeta(
          capabilities: const ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      ),
    );
    await _settle();

    final allowedResponse = _expectSingleErrorFreeResponse(
      transport.sentMessages,
      id: 'mrtr-allowed-form',
    );
    if (allowedResponse.result['resultType'] != _resultTypeInputRequired) {
      throw StateError(
        'Expected declared form elicitation capability to allow MRTR input '
        'request, got ${allowedResponse.result}.',
      );
    }
  } finally {
    await server.close();
  }
}

Future<void> _callToolResultCannotSpoofTaskResult() async {
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );

  server.setRequestHandler<JsonRpcCallToolRequest>(
    Method.toolsCall,
    (request, extra) async => const CallToolResult(
      content: <Content>[TextContent(text: 'spoof')],
      extra: <String, dynamic>{
        'resultType': 'task',
        'taskId': 'spoofed-task',
      },
    ),
    (id, params, meta) => JsonRpcCallToolRequest.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.toolsCall,
        'params': params,
        if (meta != null) '_meta': meta,
      },
    ),
  );

  try {
    await server.connect(transport);
    transport.emit(
      JsonRpcCallToolRequest(
        id: 'spoof-task-result',
        params: const CallToolRequest(name: 'spoof').toJson(),
        meta: _statelessRequestMeta(
          capabilities: const ClientCapabilities(
            extensions: <String, Map<String, dynamic>>{
              _tasksExtensionId: <String, dynamic>{},
            },
          ),
        ),
      ),
    );
    await _settle();

    _expectSingleError(
      transport.sentMessages,
      id: 'spoof-task-result',
      code: ErrorCode.invalidParams.value,
      messageContains: 'CallToolResult cannot set MCP resultType',
    );
  } finally {
    await server.close();
  }
}

Future<void> _taskResultRequiresClientExtension() async {
  final transport = _DiscoveringConformanceTransport(
    capabilities: const <String, dynamic>{
      'tools': <String, dynamic>{},
      'extensions': <String, dynamic>{
        _tasksExtensionId: <String, dynamic>{},
      },
    },
    toolsListResult: const <String, dynamic>{
      'resultType': _resultTypeComplete,
      'tools': <Object>[],
      'ttlMs': 0,
      'cacheScope': _cacheScopePrivate,
    },
    toolsCallResult: const <String, dynamic>{
      'resultType': 'task',
      'taskId': 'task-without-client-extension',
      'status': 'working',
      'createdAt': '2026-07-28T00:00:00Z',
      'lastUpdatedAt': '2026-07-28T00:00:00Z',
      'ttlMs': null,
    },
  );
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
    ),
  );

  try {
    await client.connect(transport);
    try {
      await client.callTool(const CallToolRequest(name: 'delayed'));
    } on McpError catch (error) {
      if (error.code != ErrorCode.internalError.value) {
        throw StateError(
          'Expected internal error for unnegotiated task result, got '
          '${error.code}.',
        );
      }
      final data = error.data.toString();
      if (!data.contains('MCP resultType "task" is not valid for tools/call')) {
        throw StateError(
          'Expected unnegotiated task result diagnostic, got ${error.data}.',
        );
      }
      return;
    }

    throw StateError(
      'Expected unnegotiated task resultType to be rejected.',
    );
  } finally {
    await client.close();
  }
}

Future<void> _rejectsRemovedStatelessCoreRpcs() async {
  final transport = _ConformanceTransport();
  // Raw protocol conformance needs the low-level server so removed core RPCs
  // are not intercepted by high-level convenience handlers.
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
    ),
  );
  await server.connect(transport);

  final removedRequests = <JsonRpcRequest>[
    JsonRpcRequest(
      id: 1,
      method: Method.initialize,
      params: const <String, dynamic>{
        'protocolVersion': _stableProtocolVersion2026_07_28,
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{
          'name': 'client',
          'version': '1.0.0',
        },
      },
      meta: _statelessRequestMeta(),
    ),
    JsonRpcRequest(
      id: 2,
      method: Method.ping,
      meta: _statelessRequestMeta(),
    ),
    JsonRpcRequest(
      id: 3,
      method: Method.loggingSetLevel,
      params: const <String, dynamic>{'level': 'info'},
      meta: _statelessRequestMeta(),
    ),
    JsonRpcRequest(
      id: 4,
      method: Method.resourcesSubscribe,
      params: const <String, dynamic>{'uri': 'file:///tmp/example.txt'},
      meta: _statelessRequestMeta(),
    ),
    JsonRpcRequest(
      id: 5,
      method: Method.resourcesUnsubscribe,
      params: const <String, dynamic>{'uri': 'file:///tmp/example.txt'},
      meta: _statelessRequestMeta(),
    ),
  ];

  for (final request in removedRequests) {
    transport.sentMessages.clear();

    transport.emit(request);
    await _settle();

    _expectSingleError(
      transport.sentMessages,
      id: request.id,
      code: ErrorCode.methodNotFound.value,
      messageContains: request.method,
    );
  }

  await server.close();
}

Future<void> _rejectsRemovedStatelessCoreNotifications() async {
  final transport = _ConformanceTransport();
  final errors = <Error>[];
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
  )..onerror = errors.add;
  await server.connect(transport);

  final removedNotifications = <JsonRpcNotification>[
    _notificationFromWire(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsInitialized,
        'params': <String, dynamic>{
          '_meta': _statelessRequestMeta(),
        },
      },
    ),
    _notificationFromWire(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsRootsListChanged,
        'params': <String, dynamic>{
          '_meta': _statelessRequestMeta(),
        },
      },
    ),
    _notificationFromWire(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'method': _methodNotificationsTasksStatus,
        'params': <String, dynamic>{
          '_meta': _statelessRequestMeta(),
          'taskId': 'task-1',
          'status': 'working',
          'ttl': null,
          'createdAt': '2026-07-28T00:00:00Z',
          'lastUpdatedAt': '2026-07-28T00:00:00Z',
        },
      },
    ),
  ];

  for (final notification in removedNotifications) {
    errors.clear();
    transport.sentMessages.clear();

    transport.emit(notification);
    await _settle();

    _expectSingleProtocolError(
      errors,
      code: ErrorCode.methodNotFound.value,
      messageContains: notification.method,
    );
    if (transport.sentMessages.isNotEmpty) {
      throw StateError(
        'Removed stateless notification ${notification.method} sent a response.',
      );
    }
  }

  await server.close();
}

Future<void> _statelessLoggingRequiresRequestLogLevel() async {
  final transport = _ConformanceTransport();
  // Raw protocol conformance needs the low-level server so request-scoped
  // logging can be emitted from inside the registered handler.
  // ignore: deprecated_member_use
  late final Server server;
  // ignore: deprecated_member_use
  server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        logging: <String, dynamic>{},
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );
  server.setRequestHandler<JsonRpcListToolsRequest>(
    Method.toolsList,
    (request, extra) async {
      await server.sendLoggingMessage(
        const LoggingMessageNotification(
          level: LoggingLevel.debug,
          data: 'below-threshold',
        ),
        requestMeta: extra.meta,
      );
      await server.sendLoggingMessage(
        const LoggingMessageNotification(
          level: LoggingLevel.warning,
          data: 'threshold-match',
        ),
        requestMeta: extra.meta,
      );
      return const ListToolsResult(tools: <Tool>[]);
    },
    (id, params, meta) => JsonRpcListToolsRequest(
      id: id,
      params: params,
      meta: meta,
    ),
  );
  await server.connect(transport);

  transport.emit(
    JsonRpcListToolsRequest(
      id: 'without-log-level',
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  if (transport.sentMessages.length != 1 ||
      transport.sentMessages.single is! JsonRpcResponse) {
    throw StateError(
      'Expected only a tools/list response without stateless logLevel, got '
      '${transport.sentMessages}.',
    );
  }

  transport.sentMessages.clear();
  transport.emit(
    JsonRpcListToolsRequest(
      id: 'with-log-level',
      meta: <String, dynamic>{
        ..._statelessRequestMeta(),
        McpMetaKey.logLevel: 'warning',
      },
    ),
  );
  await _settle();

  final loggingNotifications = transport.sentMessages
      .whereType<JsonRpcNotification>()
      .where((message) => message.method == Method.notificationsMessage)
      .toList();
  if (loggingNotifications.length != 1) {
    throw StateError(
      'Expected exactly one threshold-matching stateless log notification, got '
      '$loggingNotifications.',
    );
  }
  final loggingParams = loggingNotifications.single.params;
  if (loggingParams?['level'] != LoggingLevel.warning.name ||
      loggingParams?['data'] != 'threshold-match') {
    throw StateError(
      'Expected warning threshold log notification, got '
      '$loggingParams.',
    );
  }
  final responses =
      transport.sentMessages.whereType<JsonRpcResponse>().toList();
  _expectSingleErrorFreeResponse(responses, id: 'with-log-level');

  await server.close();
}

Future<void> _taskLifecycleMethodsAllowResumedClientCapability() async {
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );
  await server.connect(transport);

  final requests = <JsonRpcRequest>[
    JsonRpcRequest(
      id: 'task-get',
      method: _methodTasksGet,
      params: const <String, dynamic>{'taskId': 'task-1'},
      meta: _statelessRequestMeta(),
    ),
    JsonRpcRequest(
      id: 'task-update',
      method: _methodTasksUpdate,
      params: const <String, dynamic>{
        'taskId': 'task-1',
        'inputResponses': <String, dynamic>{},
      },
      meta: _statelessRequestMeta(),
    ),
    JsonRpcRequest(
      id: 'task-cancel',
      method: Method.tasksCancel,
      params: const <String, dynamic>{'taskId': 'task-1'},
      meta: _statelessRequestMeta(),
    ),
  ];

  for (final request in requests) {
    transport.sentMessages.clear();
    transport.emit(request);
    await _settle();

    _expectSingleError(
      transport.sentMessages,
      id: request.id,
      code: ErrorCode.methodNotFound.value,
      messageContains: request.method,
    );
  }

  await server.close();
}

Future<void> _taskStoreUsesTaskExtensionResultShapes() async {
  final store = InMemoryTaskStore();
  final completedTask = await store.createTask(
    const TaskCreation(ttl: 60000),
    'source-request',
    const <String, dynamic>{
      'method': Method.toolsCall,
      'params': <String, dynamic>{'name': 'long-running'},
    },
    null,
  );
  await store.storeTaskResult(
    completedTask.taskId,
    TaskStatus.completed,
    const CallToolResult(
      content: <Content>[TextContent(text: 'task complete')],
    ),
  );
  final workingTask = await store.createTask(
    const TaskCreation(ttl: null),
    'cancel-request',
    const <String, dynamic>{
      'method': Method.toolsCall,
      'params': <String, dynamic>{'name': 'cancel-me'},
    },
    null,
  );
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: _mcpServerOptionsWithTaskStore(
      capabilities: const ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
      taskStore: store,
    ),
  );

  try {
    await server.connect(transport);
    transport.emit(
      JsonRpcRequest(
        id: 'task-store-get',
        method: _methodTasksGet,
        params: <String, dynamic>{'taskId': completedTask.taskId},
        meta: _statelessRequestMeta(
          capabilities: const ClientCapabilities(
            extensions: <String, Map<String, dynamic>>{
              _tasksExtensionId: <String, dynamic>{},
            },
          ),
        ),
      ),
    );
    await _settle();

    final getResponse = _expectSingleErrorFreeResponse(
      transport.sentMessages,
      id: 'task-store-get',
    );
    final getResult = getResponse.result;
    if (getResult['resultType'] != _resultTypeComplete ||
        getResult['taskId'] != completedTask.taskId ||
        getResult['status'] != 'completed' ||
        getResult['ttlMs'] != 60000 ||
        getResult.containsKey('ttl') ||
        (getResult['result'] as Map<String, dynamic>?)?['content'] == null) {
      throw StateError(
        'Expected built-in tasks/get to use the task extension result shape, '
        'got $getResult.',
      );
    }

    transport.sentMessages.clear();
    transport.emit(
      JsonRpcRequest(
        id: 'task-store-cancel',
        method: Method.tasksCancel,
        params: <String, dynamic>{'taskId': workingTask.taskId},
        meta: _statelessRequestMeta(
          capabilities: const ClientCapabilities(
            extensions: <String, Map<String, dynamic>>{
              _tasksExtensionId: <String, dynamic>{},
            },
          ),
        ),
      ),
    );
    await _settle();

    final cancelResponse = _expectSingleErrorFreeResponse(
      transport.sentMessages,
      id: 'task-store-cancel',
    );
    if (cancelResponse.result.length != 1 ||
        cancelResponse.result['resultType'] != _resultTypeComplete) {
      throw StateError(
        'Expected built-in tasks/cancel to acknowledge with complete result, '
        'got ${cancelResponse.result}.',
      );
    }
    final cancelledTask = await store.getTask(workingTask.taskId);
    if (cancelledTask?.status != TaskStatus.cancelled) {
      throw StateError(
        'Expected task ${workingTask.taskId} to be cancelled, '
        'got ${cancelledTask?.status}.',
      );
    }
  } finally {
    await server.close();
    store.dispose();
  }
}

McpServerOptions _mcpServerOptionsWithTaskStore({
  required ServerCapabilities capabilities,
  required InMemoryTaskStore taskStore,
}) {
  // Keep this dynamic so mcp_dart_cli remains analyzable against the published
  // mcp_dart lower bound until this SDK branch is released.
  return Function.apply(
    McpServerOptions.new,
    const <Object?>[],
    <Symbol, Object?>{
      #capabilities: capabilities,
      #taskStore: taskStore,
      #protocol: McpProtocol.stable,
    },
  ) as McpServerOptions;
}

Future<void> _subscriptionTaskIdsRequireClientCapability() async {
  final transport = _ConformanceTransport();
  // Raw map parsing exercises the wire shape without depending on draft-only
  // subscription request symbols in the hosted CLI package analysis.
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(
        extensions: <String, Map<String, dynamic>>{
          _tasksExtensionId: <String, dynamic>{},
        },
      ),
    ),
  );
  await server.connect(transport);

  final request = JsonRpcMessage.fromJson(
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'task-subscription-capability',
      'method': _methodSubscriptionsListen,
      'params': <String, dynamic>{
        '_meta': _statelessRequestMeta(),
        'notifications': <String, dynamic>{
          'taskIds': <String>['task-1'],
        },
      },
    },
  );
  if (request is! JsonRpcRequest) {
    throw StateError(
      'Expected subscriptions/listen to parse as a request, got '
      '${request.runtimeType}.',
    );
  }

  transport.emit(request);
  await _settle();

  final error = _expectSingleError(
    transport.sentMessages,
    id: 'task-subscription-capability',
    code: ErrorCode.missingRequiredClientCapability.value,
    messageContains: 'Missing required client capability',
  );
  _expectMissingTasksExtensionCapabilityData(error.error.data);

  await server.close();
}

Future<void> _subscriptionsListenRequiresRequestMeta() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(
      <String, dynamic>{
        'jsonrpc': jsonRpcVersion,
        'id': 'missing-subscription-meta',
        'method': _methodSubscriptionsListen,
        'params': <String, dynamic>{
          'notifications': <String, dynamic>{
            'toolsListChanged': true,
          },
        },
      },
    ),
  );

  final parsed = JsonRpcMessage.fromJson(
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'subscription-meta',
      'method': _methodSubscriptionsListen,
      'params': <String, dynamic>{
        '_meta': _statelessRequestMeta(),
        'notifications': <String, dynamic>{
          'toolsListChanged': true,
        },
      },
    },
  );
  if (parsed is! JsonRpcRequest ||
      parsed.meta?[_protocolVersionMetaKey] !=
          _stableProtocolVersion2026_07_28) {
    throw StateError(
      'Expected subscriptions/listen request to preserve params._meta, got '
      '$parsed.',
    );
  }
}

Future<void> _subscriptionsListenRequiresResourceSubscribeCapability() async {
  final request = JsonRpcMessage.fromJson(
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 'resource-subscription-capability',
      'method': _methodSubscriptionsListen,
      'params': <String, dynamic>{
        '_meta': _statelessRequestMeta(),
        'notifications': <String, dynamic>{
          'resourceSubscriptions': <String>['file:///project/config.json'],
        },
      },
    },
  );
  if (request is! JsonRpcRequest) {
    throw StateError(
      'Expected subscriptions/listen to parse as a request, got '
      '${request.runtimeType}.',
    );
  }
  final notifications = request.params?['notifications'];
  if (notifications is! Map<String, dynamic>) {
    throw StateError(
      'Expected subscriptions/listen notifications object, got '
      '$notifications.',
    );
  }

  final unacknowledged = _acknowledgeResourceSubscriptions(
    notifications,
    resourcesSubscribe: false,
  );
  if (unacknowledged.containsKey('resourceSubscriptions')) {
    throw StateError(
      'Expected resourceSubscriptions to be omitted when resources.subscribe '
      'is not advertised, got $unacknowledged.',
    );
  }

  final acknowledged = _acknowledgeResourceSubscriptions(
    notifications,
    resourcesSubscribe: true,
  );
  final acknowledgedResources = acknowledged['resourceSubscriptions'];
  if (acknowledgedResources is! List ||
      acknowledgedResources.single != 'file:///project/config.json') {
    throw StateError(
      'Expected resourceSubscriptions to be acknowledged when '
      'resources.subscribe is advertised, got $acknowledged.',
    );
  }

  if (!_allowsResourceSubscription(
    'file:///project/config.json',
    <String>['file:///project'],
  )) {
    throw StateError(
      'Expected resourceSubscriptions to allow notifications for '
      'sub-resources of a subscribed URI.',
    );
  }
  if (_allowsResourceSubscription(
    'file:///project-other/config.json',
    <String>['file:///project'],
  )) {
    throw StateError(
      'Expected resourceSubscriptions to reject sibling resources that only '
      'share a string prefix.',
    );
  }
}

Future<void> _subscriptionsAcknowledgedRejectsWrapperMismatch() async {
  for (final message in const [
    <String, dynamic>{
      'jsonrpc': '1.0',
      'method': Method.notificationsSubscriptionsAcknowledged,
      'params': <String, dynamic>{
        'notifications': <String, dynamic>{},
      },
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsProgress,
      'params': <String, dynamic>{
        'notifications': <String, dynamic>{},
      },
    },
  ]) {
    _expectThrowsFormatException(
      () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson(message),
    );
  }

  final parsed = JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
    const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsSubscriptionsAcknowledged,
      'params': <String, dynamic>{
        'notifications': <String, dynamic>{
          'toolsListChanged': true,
        },
      },
    },
  );
  if (parsed.acknowledgedParams.notifications.toolsListChanged != true) {
    throw StateError('Expected acknowledged toolsListChanged to parse.');
  }
}

Map<String, dynamic> _acknowledgeResourceSubscriptions(
  Map<String, dynamic> notifications, {
  required bool resourcesSubscribe,
}) {
  if (!resourcesSubscribe) {
    return <String, dynamic>{};
  }

  final resourceSubscriptions = notifications['resourceSubscriptions'];
  if (resourceSubscriptions is! List ||
      resourceSubscriptions.any((value) => value is! String)) {
    return <String, dynamic>{};
  }

  return <String, dynamic>{
    'resourceSubscriptions': <String>[
      for (final value in resourceSubscriptions) value as String,
    ],
  };
}

bool _allowsResourceSubscription(String uri, List<String> subscribedUris) {
  for (final subscribedUri in subscribedUris) {
    if (uri == subscribedUri || _isSubResourceUri(uri, subscribedUri)) {
      return true;
    }
  }
  return false;
}

bool _isSubResourceUri(String uri, String subscribedUri) {
  final parsedUri = Uri.tryParse(uri);
  final parsedSubscribedUri = Uri.tryParse(subscribedUri);
  if (parsedUri == null || parsedSubscribedUri == null) {
    return false;
  }
  if (parsedUri.scheme != parsedSubscribedUri.scheme ||
      parsedUri.authority != parsedSubscribedUri.authority) {
    return false;
  }

  final subscribedPath = parsedSubscribedUri.path;
  final path = parsedUri.path;
  if (subscribedPath.isEmpty || !path.startsWith(subscribedPath)) {
    return false;
  }
  if (subscribedPath.endsWith('/')) {
    return true;
  }
  return path.length > subscribedPath.length &&
      path.codeUnitAt(subscribedPath.length) == 0x2f;
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
    code: ErrorCode.methodNotFound.value,
    messageContains: 'sampling.tools',
  );
  await client.close();
}

Future<void> _rejectsUnnegotiatedSamplingContext() async {
  final transport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
  );
  await server.connect(transport);
  transport.emit(
    _initializeRequest(
      capabilities: const ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
      ),
    ),
  );
  await _settle();
  _expectSingleErrorFreeResponse(transport.sentMessages, id: 1);
  transport.sentMessages.clear();
  transport.emit(const JsonRpcInitializedNotification());
  await _settle();
  transport.sentMessages.clear();

  _expectMcpError(
    () => server.createMessage(
      const CreateMessageRequest(
        messages: <SamplingMessage>[
          SamplingMessage(
            role: SamplingMessageRole.user,
            content: SamplingTextContent(text: 'Use server context'),
          ),
        ],
        includeContext: IncludeContext.thisServer,
        maxTokens: 4,
      ),
    ),
    code: ErrorCode.methodNotFound.value,
    messageContains: 'sampling context',
  );

  final samplingRequests = transport.sentMessages
      .whereType<JsonRpcRequest>()
      .where((message) => message.method == Method.samplingCreateMessage);
  if (samplingRequests.isNotEmpty) {
    throw StateError(
      'sampling/createMessage was sent without sampling.context capability.',
    );
  }
  await server.close();
}

Future<void> _unadvertisedPeerMethodsUseMethodNotFound() async {
  final clientTransport = _ConformanceTransport();
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
  );
  await _initializeClient(client, clientTransport);
  _expectMcpError(
    () => client.assertCapabilityForMethod(Method.toolsList),
    code: ErrorCode.methodNotFound.value,
    messageContains: 'tools',
  );
  await client.close();

  final statelessClientTransport = _DiscoveringConformanceTransport(
    toolsListResult: const <String, dynamic>{
      'resultType': _resultTypeComplete,
      'tools': <Object>[],
      'ttlMs': 0,
      'cacheScope': _cacheScopePrivate,
    },
  );
  final statelessClient = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
    ),
  );
  await statelessClient.connect(statelessClientTransport);
  statelessClientTransport.sentMessages.clear();
  statelessClientTransport.onmessage?.call(
    const JsonRpcListRootsRequest(id: 'roots-list'),
  );
  await _settle();
  _expectSingleError(
    statelessClientTransport.sentMessages,
    id: 'roots-list',
    code: ErrorCode.methodNotFound.value,
    messageContains: 'roots',
  );
  await statelessClient.close();

  final serverTransport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(),
    ),
  );
  await server.connect(serverTransport);
  serverTransport.emit(_initializeRequest());
  await _settle();
  _expectSingleErrorFreeResponse(serverTransport.sentMessages, id: 1);
  serverTransport.sentMessages.clear();
  serverTransport.emit(const JsonRpcInitializedNotification());
  await _settle();
  serverTransport.sentMessages.clear();
  _expectMcpError(
    () => server.assertCapabilityForMethod(Method.rootsList),
    code: ErrorCode.methodNotFound.value,
    messageContains: 'roots',
  );
  await server.close();
}

Future<void> _taskScopedPeerMethodsUseMethodNotFound() async {
  final clientTransport = _ConformanceTransport();
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
  );
  await _initializeClient(
    client,
    clientTransport,
    serverCapabilities: const ServerCapabilities(
      tools: ServerCapabilitiesTools(),
      tasks: ServerCapabilitiesTasks(),
    ),
  );
  _expectMcpError(
    () => client.assertTaskCapability(Method.toolsCall),
    code: ErrorCode.methodNotFound.value,
    messageContains: 'tasks.requests.tools.call',
  );
  await client.close();

  final serverTransport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
  );
  await server.connect(serverTransport);
  serverTransport.emit(
    _initializeRequest(
      capabilities: const ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
        tasks: ClientCapabilitiesTasks(),
      ),
    ),
  );
  await _settle();
  _expectSingleErrorFreeResponse(serverTransport.sentMessages, id: 1);
  serverTransport.sentMessages.clear();
  serverTransport.emit(const JsonRpcInitializedNotification());
  await _settle();
  _expectMcpError(
    () => server.assertTaskCapability(Method.samplingCreateMessage),
    code: ErrorCode.methodNotFound.value,
    messageContains: 'tasks.requests.sampling.createMessage',
  );
  await server.close();
}

Future<void> _statelessOmitsLegacyTaskCapabilities() async {
  const clientCapabilities = ClientCapabilities(
    sampling: ClientCapabilitiesSampling(tools: true),
    roots: ClientCapabilitiesRoots(listChanged: true),
    tasks: ClientCapabilitiesTasks(
      cancel: true,
      list: true,
      requests: ClientCapabilitiesTasksRequests(
        sampling: ClientCapabilitiesTasksSampling(
          createMessage: ClientCapabilitiesTasksSamplingCreateMessage(),
        ),
      ),
    ),
    extensions: <String, Map<String, dynamic>>{
      _tasksExtensionId: <String, dynamic>{},
    },
  );
  if (!clientCapabilities.toJson().containsKey('tasks')) {
    throw StateError('Expected stable client capabilities to include tasks.');
  }

  final statelessMeta = _statelessRequestMeta(capabilities: clientCapabilities);
  final statelessCapabilities =
      statelessMeta[_clientCapabilitiesMetaKey] as Map<String, dynamic>;
  if (statelessCapabilities.containsKey('tasks')) {
    throw StateError(
      'Expected 2026 request metadata to omit legacy tasks capability, got '
      '$statelessCapabilities.',
    );
  }
  final statelessRoots = statelessCapabilities['roots'];
  if (statelessRoots is! Map || statelessRoots.containsKey('listChanged')) {
    throw StateError(
      'Expected 2026 request metadata to omit legacy roots.listChanged '
      'capability, got $statelessCapabilities.',
    );
  }
  final statelessExtensions = statelessCapabilities['extensions'];
  if (statelessExtensions is! Map ||
      statelessExtensions[_tasksExtensionId] is! Map) {
    throw StateError(
      'Expected 2026 request metadata to retain tasks extension, got '
      '$statelessCapabilities.',
    );
  }

  final legacyMeta = _statelessRequestMeta(
    protocolVersion: stableProtocolVersion2025_11_25,
    capabilities: clientCapabilities,
  );
  final legacyCapabilities =
      legacyMeta[_clientCapabilitiesMetaKey] as Map<String, dynamic>;
  if (!legacyCapabilities.containsKey('tasks')) {
    throw StateError(
      'Expected legacy request metadata to keep legacy tasks capability, got '
      '$legacyCapabilities.',
    );
  }
  final legacyRoots = legacyCapabilities['roots'];
  if (legacyRoots is! Map || legacyRoots['listChanged'] != true) {
    throw StateError(
      'Expected legacy request metadata to keep roots.listChanged capability, '
      'got $legacyCapabilities.',
    );
  }

  final clientTransport = _DiscoveringConformanceTransport(
    capabilities: const <String, dynamic>{
      'tools': <String, dynamic>{},
      'extensions': <String, dynamic>{
        _tasksExtensionId: <String, dynamic>{},
      },
    },
    toolsListResult: const <String, dynamic>{
      'resultType': _resultTypeComplete,
      'tools': <Object>[],
      'ttlMs': 0,
      'cacheScope': _cacheScopePrivate,
    },
  );
  final client = McpClient(
    const Implementation(name: 'client', version: '1.0.0'),
    options: const McpClientOptions(
      protocol: McpProtocol.stable,
      capabilities: clientCapabilities,
      useServerDiscover: true,
    ),
  );
  await client.connect(clientTransport);
  final discoverRequest = clientTransport.sentMessages
      .whereType<JsonRpcRequest>()
      .firstWhere((message) => message.method == _serverDiscoverMethod);
  final discoverClientCapabilities =
      discoverRequest.meta?[_clientCapabilitiesMetaKey] as Map<String, dynamic>;
  if (discoverClientCapabilities.containsKey('tasks')) {
    throw StateError(
      'Expected client-generated server/discover metadata to omit legacy '
      'tasks capability, got $discoverClientCapabilities.',
    );
  }
  await client.close();

  const serverCapabilities = ServerCapabilities(
    tools: ServerCapabilitiesTools(),
    tasks: ServerCapabilitiesTasks(
      list: true,
      cancel: true,
      requests: ServerCapabilitiesTasksRequests(
        tools: ServerCapabilitiesTasksTools(
          call: ServerCapabilitiesTasksToolsCall(),
        ),
      ),
    ),
    extensions: <String, Map<String, dynamic>>{
      _tasksExtensionId: <String, dynamic>{},
    },
  );
  if (!serverCapabilities.toJson().containsKey('tasks')) {
    throw StateError('Expected stable server capabilities to include tasks.');
  }

  final serverTransport = _ConformanceTransport();
  // ignore: deprecated_member_use
  final server = Server(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: serverCapabilities,
    ),
  );
  await server.connect(serverTransport);
  serverTransport.emit(
    JsonRpcServerDiscoverRequest(
      id: 'discover-capabilities',
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();
  final response = _expectSingleErrorFreeResponse(
    serverTransport.sentMessages,
    id: 'discover-capabilities',
  );
  final discoveredCapabilities =
      response.result['capabilities'] as Map<String, dynamic>;
  if (discoveredCapabilities.containsKey('tasks')) {
    throw StateError(
      'Expected server/discover result to omit legacy tasks capability, got '
      '$discoveredCapabilities.',
    );
  }
  final discoveredExtensions = discoveredCapabilities['extensions'];
  if (discoveredExtensions is! Map ||
      discoveredExtensions[_tasksExtensionId] is! Map) {
    throw StateError(
      'Expected server/discover result to retain tasks extension, got '
      '$discoveredCapabilities.',
    );
  }
  await server.close();
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

Future<void> _acceptsNumericElicitationNumberSchemaKeywords() async {
  final parsed = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'id': 104,
    'method': Method.elicitationCreate,
    'params': <String, dynamic>{
      'mode': 'form',
      'message': 'Configure ratio',
      'requestedSchema': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'ratio': <String, dynamic>{
            'type': 'number',
            'minimum': 0.1,
            'maximum': 0.9,
            'default': 0.5,
          },
        },
      },
      '_meta': <String, dynamic>{
        _protocolVersionMetaKey: _stableProtocolVersion2026_07_28,
      },
    },
  });
  if (parsed is! JsonRpcElicitRequest) {
    throw StateError(
        'Expected JsonRpcElicitRequest, got ${parsed.runtimeType}.');
  }

  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(<String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 104,
      'method': Method.elicitationCreate,
      'params': <String, dynamic>{
        'mode': 'form',
        'message': 'Configure ratio',
        'requestedSchema': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'ratio': <String, dynamic>{
              'type': 'number',
              'maximum': double.infinity,
            },
          },
        },
        '_meta': <String, dynamic>{
          _protocolVersionMetaKey: _stableProtocolVersion2026_07_28,
        },
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

Future<void> _dispatchesIntegerProgressToken() async {
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
          'progressToken': 15,
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
  if (progress.progressToken != 15) {
    throw StateError('Expected integer progress token to be preserved.');
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

Future<void> _rejectsNonStringJsonRpcMethod() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'method': 1,
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

Future<void> _rejectsMethodResponseJsonRpcEnvelope() async {
  final messages = <Map<String, dynamic>>[
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'method': 'unknown/request',
      'result': <String, dynamic>{'ok': true},
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'method': 'unknown/request',
      'error': <String, dynamic>{
        'code': ErrorCode.invalidRequest.value,
        'message': 'Invalid request',
      },
    },
  ];

  for (final message in messages) {
    _expectThrowsFormatException(() => JsonRpcMessage.fromJson(message));
  }
  _expectThrowsFormatException(
    () => JsonRpcError.fromJson(messages.last),
  );
  _expectThrowsFormatException(
    () => JsonRpcPingRequest.fromJson(messages.first),
  );
  _expectThrowsFormatException(
    () => JsonRpcProgressNotification.fromJson(<String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsProgress,
      'params': <String, dynamic>{
        'progressToken': 'progress-1',
        'progress': 1,
      },
      'error': <String, dynamic>{
        'code': ErrorCode.invalidRequest.value,
        'message': 'Invalid request',
      },
    }),
  );
}

Future<void> _rejectsMalformedJsonRpcErrorObject() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'error': <String, dynamic>{
        'code': 'not-a-number',
        'message': 'Invalid request',
      },
    }),
  );
}

Future<void> _rejectsNullJsonRpcErrorResponseId() async {
  _expectThrowsFormatException(
    () => JsonRpcMessage.fromJson(const <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': null,
      'error': <String, dynamic>{
        'code': -32600,
        'message': 'Invalid request',
      },
    }),
  );
}

Future<void> _acceptsOmittedJsonRpcErrorResponseId() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'error': <String, dynamic>{
      'code': -32600,
      'message': 'Invalid request',
    },
  });

  if (message is! JsonRpcError) {
    throw StateError('Expected JsonRpcError, got ${message.runtimeType}.');
  }
  if (message.id != null) {
    throw StateError('Expected omitted error response ID to stay absent.');
  }
  if (message.toJson().containsKey('id')) {
    throw StateError('Expected serialized error response to omit id.');
  }
}

Future<void> _rejectsNullJsonRpcParamsMember() async {
  for (final message in const [
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'method': Method.ping,
      'params': null,
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsInitialized,
      'params': null,
    },
  ]) {
    _expectThrowsFormatException(() => JsonRpcMessage.fromJson(message));
  }
}

Future<void> _requiresCallToolRequestParams() async {
  const message = <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'id': 'call-1',
    'method': Method.toolsCall,
  };

  _expectThrowsFormatException(() => JsonRpcCallToolRequest.fromJson(message));
  _expectThrowsFormatException(() => JsonRpcMessage.fromJson(message));
}

Future<void> _rejectsFractionalIdsAndProgressTokens() async {
  for (final message in const [
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1.5,
      'method': Method.ping,
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1.5,
      'result': <String, dynamic>{},
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1.5,
      'error': <String, dynamic>{
        'code': -32600,
        'message': 'Invalid request',
      },
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': 1,
      'method': Method.ping,
      'params': <String, dynamic>{
        '_meta': <String, dynamic>{'progressToken': 1.5},
      },
    },
    <String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'method': Method.notificationsProgress,
      'params': <String, dynamic>{
        'progressToken': 1.5,
        'progress': 1,
      },
    },
  ]) {
    _expectThrowsFormatException(() => JsonRpcMessage.fromJson(message));
  }
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

Future<void> _preservesIntegerResponseId() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'id': 15,
    'result': <String, dynamic>{},
  });

  if (message is! JsonRpcResponse) {
    throw StateError('Expected JsonRpcResponse, got ${message.runtimeType}.');
  }
  if (message.id != 15) {
    throw StateError('Expected integer response ID to be preserved.');
  }
  if (message.toJson()['id'] != 15) {
    throw StateError('Expected serialized response ID to stay an integer.');
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

void _expectMissingTasksExtensionCapabilityData(Object? data) {
  if (data is! Map) {
    throw StateError('Expected missing-capability error data, got $data.');
  }
  final requiredCapabilities = data['requiredCapabilities'];
  if (requiredCapabilities is! Map) {
    throw StateError(
      'Expected requiredCapabilities in missing-capability data, got $data.',
    );
  }
  final extensions = requiredCapabilities['extensions'];
  if (extensions is! Map || extensions[_tasksExtensionId] is! Map) {
    throw StateError(
      'Expected requiredCapabilities.extensions.$_tasksExtensionId, got $data.',
    );
  }
}

void _expectSingleProtocolError(
  List<Error> errors, {
  required int code,
  required String messageContains,
}) {
  if (errors.length != 1) {
    throw StateError('Expected one protocol error, got ${errors.length}.');
  }
  final error = errors.single;
  if (error is! McpError) {
    throw StateError('Expected McpError, got ${error.runtimeType}.');
  }
  if (error.code != code) {
    throw StateError('Expected error code $code, got ${error.code}.');
  }
  if (!error.message.contains(messageContains)) {
    throw StateError(
      "Expected error message to contain '$messageContains', got "
      "'${error.message}'.",
    );
  }
}

void _expectMcpError(
  void Function() callback, {
  required int code,
  required String messageContains,
}) {
  try {
    callback();
  } on McpError catch (error) {
    if (error.code != code) {
      throw StateError('Expected error code $code, got ${error.code}.');
    }
    if (!error.message.contains(messageContains)) {
      throw StateError(
        "Expected error message to contain '$messageContains', got "
        "'${error.message}'.",
      );
    }
    return;
  }

  throw StateError('Expected McpError.');
}

void _expectUnsupportedProtocolVersionData(
  JsonRpcError error, {
  required String requested,
}) {
  final data = error.error.data;
  if (data is! Map) {
    throw StateError('Expected unsupported version error data, got $data.');
  }
  final supported = data['supported'];
  if (supported is! List ||
      !supported.contains(_stableProtocolVersion2026_07_28) ||
      !supported.contains('2025-11-25')) {
    throw StateError(
      'Expected supported protocol versions in error data, got $supported.',
    );
  }
  if (data['requested'] != requested) {
    throw StateError(
      'Expected requested protocol version $requested, got '
      "${data['requested']}.",
    );
  }
}

JsonRpcNotification _notificationFromWire(Map<String, dynamic> json) {
  final message = JsonRpcMessage.fromJson(json);
  if (message is! JsonRpcNotification) {
    throw StateError(
      'Expected JsonRpcNotification, got ${message.runtimeType}.',
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

Future<void> _preservesIntegerProgressToken() async {
  final message = JsonRpcMessage.fromJson(const <String, dynamic>{
    'jsonrpc': jsonRpcVersion,
    'method': Method.notificationsProgress,
    'params': <String, dynamic>{
      'progressToken': 15,
      'progress': 1,
      'total': 2,
    },
  });

  if (message is! JsonRpcProgressNotification) {
    throw StateError(
      'Expected JsonRpcProgressNotification, got ${message.runtimeType}.',
    );
  }
  if (message.progressParams.progressToken != 15) {
    throw StateError('Expected integer progress token to be preserved.');
  }
  if (message.toJson()['params']['progressToken'] != 15) {
    throw StateError('Expected serialized progress token to stay an integer.');
  }
}

Future<void> _advertisesLatestProtocolVersion() async {
  if (latestProtocolVersion != stableProtocolVersion2026_07_28) {
    throw StateError(
      'Expected latestProtocolVersion $stableProtocolVersion2026_07_28, '
      'got $latestProtocolVersion.',
    );
  }
  if (supportedProtocolVersions.first != latestProtocolVersion) {
    throw StateError('Expected latestProtocolVersion to be advertised first.');
  }
  if (!supportedProtocolVersions.contains(stableProtocolVersion2025_11_25)) {
    throw StateError(
      'Expected supported versions to include '
      '$stableProtocolVersion2025_11_25.',
    );
  }
}

Future<void> _stableProfileAdvertises2026ProtocolVersion() async {
  final transport = _ConformanceTransport();
  final server = McpServer(
    const Implementation(name: 'server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.stable,
      capabilities: ServerCapabilities(),
    ),
  );

  await server.connect(transport);
  transport.emit(
    JsonRpcRequest(
      id: 'stable-version',
      method: _serverDiscoverMethod,
      meta: _statelessRequestMeta(),
    ),
  );
  await _settle();

  final response = _expectSingleErrorFreeResponse(
    transport.sentMessages,
    id: 'stable-version',
  );
  final supportedVersions = response.result['supportedVersions'];
  if (supportedVersions is! List) {
    throw StateError('Expected server/discover supportedVersions list.');
  }
  if (supportedVersions.firstOrNull != _stableProtocolVersion2026_07_28) {
    throw StateError(
      'Expected $_stableProtocolVersion2026_07_28 to be advertised first.',
    );
  }
  if (!supportedVersions.contains(_stableProtocolVersion2026_07_28)) {
    throw StateError(
      'Expected server/discover to advertise $_stableProtocolVersion2026_07_28.',
    );
  }

  await server.close();
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

bool _mapsDeepEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_mapsDeepEqual(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_mapsDeepEqual(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
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
