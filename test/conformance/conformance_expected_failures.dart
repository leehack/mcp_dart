import 'dart:convert';
import 'dart:io';

class ConformanceFailureDiagnostic {
  const ConformanceFailureDiagnostic({
    required this.scenario,
    required this.checkId,
    required this.status,
    required this.errorMessage,
    required this.fieldIssue,
  });

  factory ConformanceFailureDiagnostic.fromExpectedJson(
    Map<String, dynamic> json,
  ) {
    const supportedKeys = {
      'scenario',
      'checkId',
      'status',
      'errorMessage',
      'fieldIssue',
    };
    final unsupportedKeys = json.keys.toSet().difference(supportedKeys);
    if (unsupportedKeys.isNotEmpty) {
      throw FormatException(
        'Unsupported expected-failure fields: '
        '${unsupportedKeys.toList()..sort()}',
      );
    }

    final scenario = json['scenario'];
    final checkId = json['checkId'];
    final status = json['status'];
    final errorMessage = json['errorMessage'];
    final fieldIssue = json['fieldIssue'];
    if (scenario is! String || scenario.isEmpty) {
      throw const FormatException(
        'Expected-failure scenario must be a non-empty string.',
      );
    }
    if (checkId is! String || checkId.isEmpty) {
      throw const FormatException(
        'Expected-failure checkId must be a non-empty string.',
      );
    }
    if (status != 'FAILURE') {
      throw const FormatException(
        'Expected-failure status must be FAILURE.',
      );
    }
    if (errorMessage is! String || errorMessage.isEmpty) {
      throw const FormatException(
        'Expected-failure errorMessage must be a non-empty string.',
      );
    }
    if (fieldIssue != null && fieldIssue is! String) {
      throw const FormatException(
        'Expected-failure fieldIssue must be a string when present.',
      );
    }

    return ConformanceFailureDiagnostic(
      scenario: scenario,
      checkId: checkId,
      status: status as String,
      errorMessage: errorMessage,
      fieldIssue: fieldIssue as String?,
    );
  }

  final String scenario;
  final String checkId;
  final String status;
  final String? errorMessage;
  final String? fieldIssue;

  String get description {
    final issue = fieldIssue == null ? '' : ' [$fieldIssue]';
    return '$checkId$issue: $status'
        '${errorMessage == null ? '' : ' ($errorMessage)'}';
  }

  Map<String, dynamic> toJson() => {
        'scenario': scenario,
        'checkId': checkId,
        'status': status,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (fieldIssue != null) 'fieldIssue': fieldIssue,
      };

  @override
  bool operator ==(Object other) =>
      other is ConformanceFailureDiagnostic &&
      scenario == other.scenario &&
      checkId == other.checkId &&
      status == other.status &&
      errorMessage == other.errorMessage &&
      fieldIssue == other.fieldIssue;

  @override
  int get hashCode => Object.hash(
        scenario,
        checkId,
        status,
        errorMessage,
        fieldIssue,
      );
}

class ConformanceFailureComparison {
  const ConformanceFailureComparison({
    required this.missing,
    required this.unexpected,
  });

  final List<ConformanceFailureDiagnostic> missing;
  final List<ConformanceFailureDiagnostic> unexpected;

  bool get matches => missing.isEmpty && unexpected.isEmpty;
}

Future<List<ConformanceFailureDiagnostic>> readExpectedConformanceFailures(
  String path,
) async {
  final file = File(path);
  if (!await file.exists()) {
    return const [];
  }

  final failures = <ConformanceFailureDiagnostic>[];
  final lines = await file.readAsLines();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Expected-failure entry must be a JSON object.',
        );
      }
      failures.add(
        ConformanceFailureDiagnostic.fromExpectedJson(decoded),
      );
    } on FormatException catch (error) {
      throw FormatException(
        '$path:${index + 1}: ${error.message}',
        error.source,
        error.offset,
      );
    }
  }
  return failures;
}

Future<List<ConformanceFailureDiagnostic>> readConformanceFailureDiagnostics({
  required Directory outputDirectory,
  required String scenario,
}) async {
  final checkFiles = <File>[];
  await for (final entity
      in outputDirectory.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.uri.pathSegments.last == 'checks.json') {
      checkFiles.add(entity);
    }
  }
  checkFiles.sort((left, right) => left.path.compareTo(right.path));
  if (checkFiles.length != 1) {
    throw StateError(
      'Expected exactly one checks.json under ${outputDirectory.path}, '
      'found ${checkFiles.length}.',
    );
  }

  final decoded = jsonDecode(await checkFiles.single.readAsString());
  if (decoded is! List) {
    throw FormatException(
      '${checkFiles.single.path} must contain a JSON array.',
    );
  }

  final failures = <ConformanceFailureDiagnostic>[];
  for (var index = 0; index < decoded.length; index++) {
    final entry = decoded[index];
    if (entry is! Map<String, dynamic>) {
      throw FormatException(
        '${checkFiles.single.path}: entry $index must be a JSON object.',
      );
    }
    final status = entry['status'];
    if (status == 'SUCCESS' || status == 'SKIPPED') {
      continue;
    }
    final checkId = entry['id'];
    final errorMessage = entry['errorMessage'];
    final details = entry['details'];
    final fieldIssue = details is Map ? details['fieldIssue'] : null;
    if (checkId is! String || checkId.isEmpty || status is! String) {
      throw FormatException(
        '${checkFiles.single.path}: entry $index has an invalid id or status.',
      );
    }
    if (errorMessage != null && errorMessage is! String) {
      throw FormatException(
        '${checkFiles.single.path}: entry $index has a non-string '
        'errorMessage.',
      );
    }
    if (fieldIssue != null && fieldIssue is! String) {
      throw FormatException(
        '${checkFiles.single.path}: entry $index has a non-string fieldIssue.',
      );
    }
    failures.add(
      ConformanceFailureDiagnostic(
        scenario: scenario,
        checkId: checkId,
        status: status,
        errorMessage: errorMessage as String?,
        fieldIssue: fieldIssue as String?,
      ),
    );
  }
  return failures;
}

ConformanceFailureComparison compareConformanceFailures(
  Iterable<ConformanceFailureDiagnostic> expected,
  Iterable<ConformanceFailureDiagnostic> actual,
) {
  final expectedCounts = _countDiagnostics(expected);
  final actualCounts = _countDiagnostics(actual);
  final missing = _difference(expectedCounts, actualCounts);
  final unexpected = _difference(actualCounts, expectedCounts);
  missing.sort((left, right) => left.description.compareTo(right.description));
  unexpected.sort(
    (left, right) => left.description.compareTo(right.description),
  );
  return ConformanceFailureComparison(
    missing: missing,
    unexpected: unexpected,
  );
}

bool isExpectedConformanceFailure({
  required bool timedOut,
  required int? exitCode,
  required String? diagnosticReadError,
  required Iterable<ConformanceFailureDiagnostic> expected,
  required Iterable<ConformanceFailureDiagnostic> actual,
}) {
  if (timedOut ||
      exitCode != 1 ||
      diagnosticReadError != null ||
      expected.isEmpty) {
    return false;
  }
  return compareConformanceFailures(expected, actual).matches;
}

Map<ConformanceFailureDiagnostic, int> _countDiagnostics(
  Iterable<ConformanceFailureDiagnostic> diagnostics,
) {
  final counts = <ConformanceFailureDiagnostic, int>{};
  for (final diagnostic in diagnostics) {
    counts.update(diagnostic, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

List<ConformanceFailureDiagnostic> _difference(
  Map<ConformanceFailureDiagnostic, int> left,
  Map<ConformanceFailureDiagnostic, int> right,
) {
  final difference = <ConformanceFailureDiagnostic>[];
  for (final entry in left.entries) {
    final count = entry.value - (right[entry.key] ?? 0);
    for (var index = 0; index < count; index++) {
      difference.add(entry.key);
    }
  }
  return difference;
}
