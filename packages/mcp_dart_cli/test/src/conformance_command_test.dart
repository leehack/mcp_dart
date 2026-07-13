import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/conformance_command.dart';
import 'package:mcp_dart_cli/src/conformance_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('ConformanceRunner', () {
    test('fixture suite covers initial JSON-RPC and protocol-version cases',
        () async {
      final result = await ConformanceRunner().runFixtureSuite();

      expect(result.passed, isTrue);
      expect(result.total, greaterThanOrEqualTo(5));
      expect(
        result.caseNames,
        containsAll(<String>[
          'jsonrpc.rejects-invalid-version',
          'jsonrpc.rejects-malformed-message',
          'jsonrpc.rejects-non-string-method',
          'jsonrpc.rejects-result-error-response',
          'jsonrpc.rejects-method-response-envelope',
          'jsonrpc.rejects-malformed-error-object',
          'jsonrpc.rejects-null-error-response-id',
          'jsonrpc.accepts-omitted-error-response-id',
          'jsonrpc.rejects-null-params-member',
          'tools-call.requires-params',
          'jsonrpc.preserves-string-response-id',
          'jsonrpc.preserves-integer-response-id',
          'jsonrpc.preserves-string-progress-token',
          'jsonrpc.preserves-integer-progress-token',
          'jsonrpc.rejects-fractional-ids-and-progress-tokens',
          'protocol-version.advertises-latest-2026-07-28',
          'protocol-version.stable-profile-advertises-2026-07-28',
        ]),
      );
    });

    test('spec suite covers high-risk wire cases across spec versions',
        () async {
      final result = await ConformanceRunner().runSpecSuite();

      expect(result.passed, isTrue);
      expect(result.total, greaterThanOrEqualTo(5));
      expect(
        result.caseNames,
        containsAll(<String>[
          'lifecycle.rejects-pre-initialize-request',
          'lifecycle.gates-until-initialized-notification',
          'lifecycle.does-not-cancel-initialize',
          'cancellation.requires-request-id',
          'server-discover.requires-request-meta',
          'server-discover.returns-supported-capabilities',
          'protocol-version.rejects-unsupported-stateless-version',
          'stateless.requires-complete-request-meta',
          'protocol-version.http-modern-400-retries-discovery',
          'capabilities.http-modern-400-does-not-fallback',
          'protocol-version.initialize-negotiates-stateful-version',
          'capabilities.stateless-does-not-infer-initialize-extensions',
          'stateless-http.rejects-mismatched-routing-headers',
          'stateless-http.requires-routing-headers',
          'stateless-http.rejects-non-post-methods',
          'stateless-http.rejects-batch-payloads',
          'stateless-http.task-requests-require-name-header',
          'stateless-http.validates-parameter-headers',
          'stateless-http.omits-unsafe-numeric-parameter-headers',
          'stateless-http.encodes-parameter-header-values',
          'stateless-http.accepts-response-posts',
          'stateless-http.task-subscription-requires-client-capability',
          'stateless-http.omits-session-header-after-initialize',
          'stateless.related-task-uses-explicit-id-across-transports',
          'stateless.ignores-legacy-task-parameter',
          'stateless.adds-result-type-and-cache-defaults',
          'tools-list.stateless-returns-deterministic-order',
          'resources.missing-resource-error-code-by-version',
          'stateless.rejects-unrecognized-result-type',
          'mrtr.input-required-supported-requests',
          'mrtr.rejects-unsupported-input-required-results',
          'mrtr.input-requests-require-client-capabilities',
          'stateless.rejects-removed-core-rpcs',
          'stateless.rejects-removed-core-notifications',
          'logging.stateless-requires-request-log-level',
          'tasks-extension.lifecycle-methods-do-not-require-repeated-capability',
          'tasks-extension.task-store-uses-extension-result-shapes',
          'tasks-extension.call-tool-result-cannot-spoof-task-result',
          'tasks-extension.task-result-requires-client-extension',
          'subscriptions-listen.task-ids-require-client-capability',
          'subscriptions-listen.requires-request-meta',
          'subscriptions-listen.resource-subscriptions-require-capability',
          'subscriptions-acknowledged.rejects-wrapper-mismatch',
          'capabilities.rejects-unnegotiated-sampling-tools',
          'capabilities.rejects-unnegotiated-sampling-context',
          'capabilities.unadvertised-peer-methods-use-method-not-found',
          'capabilities.task-scoped-peer-methods-use-method-not-found',
          'capabilities.stateless-omits-legacy-task-capabilities',
          'elicitation.rejects-invalid-form-url-union',
          'elicitation.accepts-numeric-number-schema-keywords',
          'tasks.strips-unnegotiated-related-task-metadata',
          'progress.rejects-malformed-progress-token',
          'progress.dispatches-integer-progress-token',
        ]),
      );
      expect(
        result.cases.map((testCase) => testCase.suite),
        everyElement('spec'),
      );
    });

    test('all suite combines fixture and spec cases', () async {
      final result = await ConformanceRunner().runAllSuites();

      expect(result.passed, isTrue);
      expect(result.caseNames, contains('jsonrpc.rejects-invalid-version'));
      expect(
        result.caseNames,
        contains('lifecycle.rejects-pre-initialize-request'),
      );
    });

    test('can filter fixture cases by exact name', () async {
      final result = await ConformanceRunner().runFixtureSuite(
        filter: 'jsonrpc.preserves-string-response-id',
      );

      expect(result.passed, isTrue);
      expect(result.total, 1);
      expect(result.caseNames, ['jsonrpc.preserves-string-response-id']);
    });

    test('deterministic fuzz suite exercises generated JSON-RPC envelopes',
        () async {
      final result = await ConformanceRunner().runFuzzSuite(
        iterations: 8,
        seed: 101,
      );

      expect(result.passed, isTrue);
      expect(result.total, 8);
      expect(result.caseNames.first, startsWith('fuzz.jsonrpc.'));
    });
  });

  group('ConformanceCommand', () {
    late Logger logger;
    late ConformanceCommand command;

    setUp(() {
      logger = MockLogger();
      command = ConformanceCommand(logger: logger);
    });

    test('has expected name and options', () {
      expect(command.name, 'conformance');
      expect(command.argParser.options.containsKey('suite'), isTrue);
      expect(command.argParser.options.containsKey('case'), isTrue);
      expect(command.argParser.options.containsKey('fuzz'), isTrue);
      expect(command.argParser.options.containsKey('iterations'), isTrue);
      expect(command.argParser.options.containsKey('json'), isTrue);
    });

    test('runs fixture suite and reports success summary', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run(['conformance']);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('Running MCP conformance fixture suite...'),
      ).called(1);
      verify(
        () => logger.success(any(that: contains('Conformance passed:'))),
      ).called(1);
    });

    test('runs spec suite and reports success summary', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run(['conformance', '--suite', 'spec']);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('Running MCP conformance spec suite...'),
      ).called(1);
      verify(
        () => logger.success(any(that: contains('Conformance passed:'))),
      ).called(1);
    });

    test('runs deterministic fuzz suite and reports success summary', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run([
        'conformance',
        '--fuzz',
        '--iterations',
        '4',
      ]);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('Running MCP conformance fuzz suite...'),
      ).called(1);
      verify(
        () => logger.success('Conformance passed: 4/4 cases.'),
      ).called(1);
    });

    test('does not log human output when json output is requested', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run(['conformance', '--json']);

      expect(exitCode, ExitCode.success.code);
      verifyNever(() => logger.info(any()));
      verifyNever(() => logger.success(any()));
    });

    test('returns usage code when --case is combined with fuzz mode', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run([
        'conformance',
        '--fuzz',
        '--case',
        'jsonrpc.preserves-string-response-id',
      ]);

      expect(exitCode, ExitCode.usage.code);
      verify(() => logger.err('--case cannot be combined with --fuzz.'))
          .called(1);
    });

    test('returns usage code when --suite is combined with fuzz mode',
        () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run([
        'conformance',
        '--fuzz',
        '--suite',
        'spec',
      ]);

      expect(exitCode, ExitCode.usage.code);
      verify(() => logger.err('--suite cannot be combined with --fuzz.'))
          .called(1);
    });

    test('returns usage code when filter matches no cases', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);

      final exitCode = await runner.run([
        'conformance',
        '--case',
        'missing.case',
      ]);

      expect(exitCode, ExitCode.usage.code);
      verify(() => logger.err('No conformance cases matched: missing.case'))
          .called(1);
    });
  });
}
