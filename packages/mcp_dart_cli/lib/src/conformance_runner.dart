import 'dart:math';

import 'package:mcp_dart/mcp_dart.dart';

/// Result of running one conformance case.
class ConformanceCaseResult {
  final String name;
  final String description;
  final bool passed;
  final String? diagnostic;

  const ConformanceCaseResult({
    required this.name,
    required this.description,
    required this.passed,
    this.diagnostic,
  });

  Map<String, dynamic> toJson() => {
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
  final String name;
  final String description;
  final _ConformanceCheck check;

  const _ConformanceCase({
    required this.name,
    required this.description,
    required this.check,
  });
}

/// Runs the built-in MCP conformance fixture checks.
class ConformanceRunner {
  final List<_ConformanceCase> _fixtureCases;

  ConformanceRunner()
      : _fixtureCases = <_ConformanceCase>[
          _ConformanceCase(
            name: 'jsonrpc.rejects-invalid-version',
            description:
                'Rejects JSON-RPC messages whose jsonrpc version is not 2.0.',
            check: _rejectsInvalidJsonRpcVersion,
          ),
          _ConformanceCase(
            name: 'jsonrpc.rejects-malformed-message',
            description:
                'Rejects JSON-RPC envelopes without a method, result, or error member.',
            check: _rejectsMalformedJsonRpcMessage,
          ),
          _ConformanceCase(
            name: 'jsonrpc.preserves-string-response-id',
            description:
                'Parses and serializes successful responses with string JSON-RPC IDs.',
            check: _preservesStringResponseId,
          ),
          _ConformanceCase(
            name: 'jsonrpc.preserves-string-progress-token',
            description:
                'Parses and serializes progress notifications with string progress tokens.',
            check: _preservesStringProgressToken,
          ),
          _ConformanceCase(
            name: 'protocol-version.advertises-latest-2025-11-25',
            description:
                'Advertises MCP 2025-11-25 as the latest supported protocol version.',
            check: _advertisesLatestProtocolVersion,
          ),
        ];

  /// Runs the built-in fixture suite.
  ///
  /// When [filter] is provided, only exact case-name matches run. Exact matching
  /// keeps CI diagnostics deterministic and prevents accidental broad filters.
  Future<ConformanceSuiteResult> runFixtureSuite({String? filter}) async {
    final selectedCases = filter == null
        ? _fixtureCases
        : _fixtureCases.where((testCase) => testCase.name == filter).toList();

    final results = <ConformanceCaseResult>[];
    for (final testCase in selectedCases) {
      try {
        await testCase.check();
        results.add(
          ConformanceCaseResult(
            name: testCase.name,
            description: testCase.description,
            passed: true,
          ),
        );
      } catch (error) {
        results.add(
          ConformanceCaseResult(
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
            name: fixture.name,
            description: fixture.description,
            passed: true,
          ),
        );
      } catch (error) {
        results.add(
          ConformanceCaseResult(
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
  final stringId = 'req-${random.nextInt(1000000)}';
  final progressToken = random.nextBool() ? numericId : 'progress-$numericId';

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
        description: 'Generated requests preserve string-or-integer IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? numericId : stringId,
          'method': Method.ping,
        },
        expectation: _expectRequestIdRoundTrip,
      ),
    3 => _GeneratedJsonRpcFixture(
        name: 'fuzz.jsonrpc.response-id.$index',
        description: 'Generated responses preserve string-or-integer IDs.',
        message: <String, dynamic>{
          'jsonrpc': jsonRpcVersion,
          'id': random.nextBool() ? numericId : stringId,
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
          'id': random.nextBool() ? numericId : stringId,
          'error': <String, dynamic>{
            'code': ErrorCode.invalidRequest.value,
            'message': 'generated invalid request',
          },
        },
        expectation: _expectErrorIdRoundTrip,
      ),
  };
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
