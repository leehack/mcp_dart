import 'dart:io';

/// Parses scenario names from `conformance list` output.
Set<String> parseConformanceScenarioNames(String output) {
  final scenarioLine = RegExp(r'^\s*-\s+(.+?)\s+\[[^\]]+\]\s*$');
  return {
    for (final line in output.split('\n'))
      if (scenarioLine.firstMatch(line) case final match?) match.group(1)!,
  };
}

/// Verifies that the checked-in scenario manifest matches the installed
/// official conformance package.
///
/// This prevents a package upgrade from silently adding, removing, or renaming
/// scenarios while the local runner continues to report a green partial list.
Future<void> verifyConformanceScenarioInventory({
  required String conformancePackage,
  required String role,
  required String specVersion,
  required Iterable<String> expectedScenarios,
  bool requireExactMatch = true,
}) async {
  if (role != 'client' && role != 'server') {
    throw ArgumentError.value(role, 'role', 'must be client or server');
  }

  final result = await Process.run(
    'npx',
    [
      '-y',
      conformancePackage,
      'list',
      '--$role',
      '--spec-version',
      specVersion,
    ],
    workingDirectory: Directory.current.path,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'Unable to list official $role conformance scenarios for MCP '
      '$specVersion (exit ${result.exitCode}).\n${result.stderr}',
    );
  }

  final actual = parseConformanceScenarioNames(result.stdout as String);
  if (actual.isEmpty) {
    throw StateError(
      'The official conformance package returned no parseable $role '
      'scenarios for MCP $specVersion.',
    );
  }

  final expected = expectedScenarios.toSet();
  final unlisted = expected.difference(actual).toList()..sort();
  final unclassified = requireExactMatch
      ? (actual.difference(expected).toList()..sort())
      : const <String>[];
  if (unlisted.isEmpty && unclassified.isEmpty) {
    return;
  }

  throw StateError(
    'Official MCP $specVersion $role conformance scenario inventory drifted. '
    'Update and review the checked-in manifest before running the suite.'
    '${unlisted.isEmpty ? '' : '\nMissing from package: ${unlisted.join(', ')}'}'
    '${unclassified.isEmpty ? '' : '\nUnclassified locally: ${unclassified.join(', ')}'}',
  );
}
