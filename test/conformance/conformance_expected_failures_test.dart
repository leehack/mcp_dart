import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'conformance_expected_failures.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mcp-conformance-expected-failures-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('reads comment-friendly exact JSON diagnostics', () async {
    final file = File('${temporaryDirectory.path}/expected.txt');
    await file.writeAsString(
      '# pinned referee drift\n'
      '${jsonEncode(_missingClientInfo.toJson())}\n',
    );

    final failures = await readExpectedConformanceFailures(file.path);

    expect(failures, [_missingClientInfo]);
  });

  test('rejects unsupported expected-failure fields', () async {
    final file = File('${temporaryDirectory.path}/expected.txt');
    await file.writeAsString(
      '{"scenario":"server-stateless","checkId":"check",'
      '"status":"FAILURE","errorMessage":"known","typo":true}\n',
    );

    await expectLater(
      readExpectedConformanceFailures(file.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported expected-failure fields'),
        ),
      ),
    );
  });

  test('reads every non-success and non-skipped check diagnostic', () async {
    final output = Directory('${temporaryDirectory.path}/output/nested');
    await output.create(recursive: true);
    await File('${output.path}/checks.json').writeAsString(
      jsonEncode([
        {
          'id': 'passing-check',
          'status': 'SUCCESS',
        },
        {
          'id': 'skipped-check',
          'status': 'SKIPPED',
        },
        {
          'id': _missingClientInfo.checkId,
          'status': _missingClientInfo.status,
          'errorMessage': _missingClientInfo.errorMessage,
          'details': {'fieldIssue': _missingClientInfo.fieldIssue},
        },
        {
          'id': 'unexpected-error',
          'status': 'ERROR',
          'errorMessage': 'referee crashed',
        },
      ]),
    );

    final failures = await readConformanceFailureDiagnostics(
      outputDirectory: Directory('${temporaryDirectory.path}/output'),
      scenario: 'server-stateless',
    );

    expect(
      failures,
      [
        _missingClientInfo,
        const ConformanceFailureDiagnostic(
          scenario: 'server-stateless',
          checkId: 'unexpected-error',
          status: 'ERROR',
          errorMessage: 'referee crashed',
          fieldIssue: null,
        ),
      ],
    );
  });

  test('matches only the complete diagnostic multiset from exit 1', () {
    expect(
      isExpectedConformanceFailure(
        timedOut: false,
        exitCode: 1,
        diagnosticReadError: null,
        expected: const [_missingClientInfo],
        actual: const [_missingClientInfo],
      ),
      isTrue,
    );
    expect(
      isExpectedConformanceFailure(
        timedOut: false,
        exitCode: 1,
        diagnosticReadError: null,
        expected: const [_missingClientInfo],
        actual: const [_missingClientInfo, _unrelatedFailure],
      ),
      isFalse,
    );
    expect(
      isExpectedConformanceFailure(
        timedOut: false,
        exitCode: 1,
        diagnosticReadError: null,
        expected: const [_missingClientInfo, _unrelatedFailure],
        actual: const [_missingClientInfo],
      ),
      isFalse,
    );
    expect(
      isExpectedConformanceFailure(
        timedOut: false,
        exitCode: 2,
        diagnosticReadError: null,
        expected: const [_missingClientInfo],
        actual: const [_missingClientInfo],
      ),
      isFalse,
    );
  });

  test('never accepts a timeout or unreadable diagnostics', () {
    expect(
      isExpectedConformanceFailure(
        timedOut: true,
        exitCode: null,
        diagnosticReadError: null,
        expected: const [_missingClientInfo],
        actual: const [],
      ),
      isFalse,
    );
    expect(
      isExpectedConformanceFailure(
        timedOut: false,
        exitCode: 1,
        diagnosticReadError: 'missing checks.json',
        expected: const [_missingClientInfo],
        actual: const [_missingClientInfo],
      ),
      isFalse,
    );
  });
}

const _missingClientInfo = ConformanceFailureDiagnostic(
  scenario: 'server-stateless',
  checkId: 'sep-2575-request-meta-invalid-missing-client-info',
  status: 'FAILURE',
  errorMessage: 'Expected error code -32602, got undefined',
  fieldIssue: 'missing-client-info',
);

const _unrelatedFailure = ConformanceFailureDiagnostic(
  scenario: 'server-stateless',
  checkId: 'unrelated-check',
  status: 'FAILURE',
  errorMessage: 'Unrelated regression',
  fieldIssue: null,
);
