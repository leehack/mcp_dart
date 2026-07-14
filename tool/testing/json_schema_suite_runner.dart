import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

typedef JsonSchemaSuiteSchemaAdapter = Object? Function(Object? schema);

class JsonSchemaSuiteConfig {
  final String dialect;
  final String usage;
  final int expectedFileCount;
  final int expectedGroupCount;
  final int expectedAssertionCount;
  final Set<String> expectedExternalReferenceGroups;
  final Set<String> expectedUnsupportedDialectGroups;
  final Map<String, String> expectedInvalidSchemaGroups;
  final JsonSchemaSuiteSchemaAdapter adaptSchema;

  const JsonSchemaSuiteConfig({
    required this.dialect,
    required this.usage,
    required this.expectedFileCount,
    required this.expectedGroupCount,
    required this.expectedAssertionCount,
    required this.expectedExternalReferenceGroups,
    required this.expectedUnsupportedDialectGroups,
    required this.expectedInvalidSchemaGroups,
    required this.adaptSchema,
  });
}

/// Runs one pinned mandatory JSON Schema Test Suite dialect.
///
/// Exclusion identities and aggregate counts are part of [config], so a
/// regression cannot silently broaden the unsupported surface.
void runJsonSchemaSuite(
  List<String> args,
  JsonSchemaSuiteConfig config,
) {
  if (args.length != 1) {
    stderr.writeln('usage: ${config.usage}');
    exitCode = 64;
    return;
  }

  final suiteRoot = Directory(args.single);
  if (!suiteRoot.existsSync()) {
    stderr.writeln(
      'JSON Schema Test Suite directory does not exist: ${suiteRoot.path}',
    );
    exitCode = 66;
    return;
  }

  final files = suiteRoot
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final failures = <String>[];
  var groups = 0;
  var assertions = 0;
  final externalReferenceGroupIds = <String>{};
  final unsupportedDialectGroupIds = <String>{};
  final invalidSchemaGroupIds = <String>{};

  for (final file in files) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) {
      failures.add('${file.path}: root must be an array');
      continue;
    }

    for (final rawGroup in decoded) {
      groups++;
      if (rawGroup is! Map) {
        failures.add('${file.path}: group $groups must be an object');
        continue;
      }
      final group = Map<String, dynamic>.from(rawGroup);
      final description = group['description'];
      final tests = group['tests'];
      if (description is! String || tests is! List) {
        failures.add('${file.path}: malformed group $groups');
        continue;
      }
      final groupId = '${file.uri.pathSegments.last} :: $description';

      final JsonSchema schema;
      try {
        schema = JsonSchema.fromJsonValue(
          config.adaptSchema(group['schema']),
        );
      } on Object catch (error) {
        failures.add('${file.path} :: $description :: schema parse: $error');
        continue;
      }

      for (final rawTest in tests) {
        if (rawTest is! Map) {
          failures.add('${file.path} :: $description :: malformed test');
          continue;
        }
        final test = Map<String, dynamic>.from(rawTest);
        final testDescription = test['description'];
        final expectedValid = test['valid'];
        if (testDescription is! String || expectedValid is! bool) {
          failures.add('${file.path} :: $description :: malformed test');
          continue;
        }

        Object? validationError;
        try {
          schema.validate(test['data']);
        } on Object catch (error) {
          validationError = error;
        }
        if (validationError case JsonSchemaValidationException(:final message)
            when message.startsWith('External ') &&
                message.contains(' is unresolved:')) {
          externalReferenceGroupIds.add(groupId);
          break;
        }
        if (validationError case JsonSchemaValidationException(:final message)
            when message.startsWith('Unsupported JSON Schema dialect:')) {
          unsupportedDialectGroupIds.add(groupId);
          break;
        }
        if (validationError case JsonSchemaValidationException(:final message)
            when message.startsWith('Invalid JSON Schema schema:')) {
          final expectedMessage = config.expectedInvalidSchemaGroups[groupId];
          if (expectedMessage != null && message.contains(expectedMessage)) {
            invalidSchemaGroupIds.add(groupId);
            break;
          }
          failures.add(
            '${file.path} :: $description :: schema compile: $message',
          );
          break;
        }

        assertions++;
        final actualValid = validationError == null;
        if (actualValid != expectedValid) {
          failures.add(
            '${file.path} :: $description :: $testDescription '
            '(expected ${expectedValid ? 'valid' : 'invalid'}, '
            'got ${actualValid ? 'valid' : validationError})',
          );
        }
      }
    }
  }

  _verifyPinnedCount(
    failures,
    dialect: config.dialect,
    label: 'files',
    actual: files.length,
    expected: config.expectedFileCount,
  );
  _verifyPinnedCount(
    failures,
    dialect: config.dialect,
    label: 'groups',
    actual: groups,
    expected: config.expectedGroupCount,
  );
  _verifyPinnedCount(
    failures,
    dialect: config.dialect,
    label: 'supported assertions',
    actual: assertions,
    expected: config.expectedAssertionCount,
  );
  _verifyPinnedSet(
    failures,
    dialect: config.dialect,
    label: 'external-reference groups',
    actual: externalReferenceGroupIds,
    expected: config.expectedExternalReferenceGroups,
  );
  _verifyPinnedSet(
    failures,
    dialect: config.dialect,
    label: 'unsupported-dialect groups',
    actual: unsupportedDialectGroupIds,
    expected: config.expectedUnsupportedDialectGroups,
  );
  _verifyPinnedSet(
    failures,
    dialect: config.dialect,
    label: 'intentionally-invalid-schema groups',
    actual: invalidSchemaGroupIds,
    expected: config.expectedInvalidSchemaGroups.keys.toSet(),
  );

  stdout.writeln(
    'dialect=${config.dialect} files=${files.length} groups=$groups '
    'assertions=$assertions '
    'external-reference-groups=${externalReferenceGroupIds.length} '
    'unsupported-dialect-groups=${unsupportedDialectGroupIds.length} '
    'intentionally-invalid-schema-groups=${invalidSchemaGroupIds.length} '
    'failures=${failures.length}',
  );
  for (final failure in failures) {
    stdout.writeln(failure);
  }
  _printIdentities('external', externalReferenceGroupIds);
  _printIdentities('unsupported-dialect', unsupportedDialectGroupIds);
  _printIdentities('intentionally-invalid', invalidSchemaGroupIds);
  if (failures.isNotEmpty) {
    exitCode = 1;
  }
}

void _verifyPinnedCount(
  List<String> failures, {
  required String dialect,
  required String label,
  required int actual,
  required int expected,
}) {
  if (actual != expected) {
    failures.add(
      'Pinned JSON Schema Test Suite $dialect $label changed: '
      'expected $expected, found $actual.',
    );
  }
}

void _verifyPinnedSet(
  List<String> failures, {
  required String dialect,
  required String label,
  required Set<String> actual,
  required Set<String> expected,
}) {
  final missing = expected.difference(actual).toList()..sort();
  final unexpected = actual.difference(expected).toList()..sort();
  if (missing.isEmpty && unexpected.isEmpty) {
    return;
  }

  failures.add(
    'Pinned JSON Schema Test Suite $dialect $label changed.'
    '${missing.isEmpty ? '' : '\nMissing: ${missing.join(' | ')}'}'
    '${unexpected.isEmpty ? '' : '\nUnexpected: ${unexpected.join(' | ')}'}',
  );
}

void _printIdentities(String label, Set<String> identities) {
  for (final identity in identities.toList()..sort()) {
    stdout.writeln('$label: $identity');
  }
}
