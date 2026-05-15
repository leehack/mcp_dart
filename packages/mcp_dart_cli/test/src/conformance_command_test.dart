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
          'jsonrpc.preserves-string-response-id',
          'jsonrpc.preserves-string-progress-token',
          'protocol-version.advertises-latest-2025-11-25',
        ]),
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
