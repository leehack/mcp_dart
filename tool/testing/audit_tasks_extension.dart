import 'dart:convert';
import 'dart:io';

const _expectedStatuses = <String>{
  'working',
  'input_required',
  'completed',
  'failed',
  'cancelled',
};

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/testing/audit_tasks_extension.dart '
      '<ext-tasks-checkout>',
    );
    exitCode = 64;
    return;
  }

  final root = Directory(arguments.single);
  final schemaFile = File('${root.path}/schema/draft/schema.json');
  final typesFile = File('${root.path}/schema/draft/schema.ts');
  final specificationFile = File(
    '${root.path}/specification/draft/tasks.md',
  );
  final failures = <String>[];
  if (!schemaFile.existsSync() ||
      !typesFile.existsSync() ||
      !specificationFile.existsSync()) {
    stderr.writeln('Tasks checkout is missing its draft schema or prose.');
    exitCode = 66;
    return;
  }

  final schema = jsonDecode(schemaFile.readAsStringSync());
  if (schema is! Map<String, dynamic>) {
    stderr.writeln('Tasks schema root must be a JSON object.');
    exitCode = 65;
    return;
  }
  final definitions = schema[r'$defs'];
  if (definitions is! Map<String, dynamic>) {
    stderr.writeln(r'Tasks schema must contain a $defs object.');
    exitCode = 65;
    return;
  }

  void expectEqual(Object? actual, Object? expected, String label) {
    if (!_jsonEqual(actual, expected)) {
      failures.add('$label changed: expected $expected, got $actual');
    }
  }

  Map<String, dynamic>? definition(String name) {
    final value = definitions[name];
    if (value is! Map<String, dynamic>) {
      failures.add('Missing Tasks schema definition $name.');
      return null;
    }
    return value;
  }

  Object? at(Map<String, dynamic>? value, List<String> path) {
    Object? current = value;
    for (final segment in path) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[segment];
    }
    return current;
  }

  for (final entry in const {
    'GetTaskRequest': 'tasks/get',
    'UpdateTaskRequest': 'tasks/update',
    'CancelTaskRequest': 'tasks/cancel',
    'TaskStatusNotification': 'notifications/tasks',
  }.entries) {
    expectEqual(
      at(definition(entry.key), const ['properties', 'method', 'const']),
      entry.value,
      '${entry.key}.method',
    );
  }

  final task = definition('Task');
  final statusAlternatives = at(task, const ['properties', 'status', 'anyOf']);
  final statuses = statusAlternatives is List
      ? statusAlternatives
          .whereType<Map>()
          .map((value) => value['const'])
          .whereType<String>()
          .toSet()
      : <String>{};
  expectEqual(statuses, _expectedStatuses, 'Task statuses');
  expectEqual(
    at(task, const ['properties', 'taskId', 'type']),
    'string',
    'Task.taskId type',
  );
  expectEqual(
    at(task, const ['properties', 'ttlMs', 'anyOf']),
    const [
      {'type': 'number'},
      {'type': 'null'},
    ],
    'Task.ttlMs provisional schema',
  );
  expectEqual(
    at(task, const ['properties', 'pollIntervalMs', 'type']),
    'number',
    'Task.pollIntervalMs provisional schema',
  );
  expectEqual(
    at(definition('FailedTask'), const ['properties', 'error']),
    const {
      'type': 'object',
      'propertyNames': {'type': 'string'},
      'additionalProperties': <String, dynamic>{},
    },
    'FailedTask.error provisional schema',
  );

  final types = typesFile.readAsStringSync();
  final specification = specificationFile.readAsStringSync();
  for (final source in [types, specification]) {
    if (!source.contains('io.modelcontextprotocol/tasks')) {
      failures.add('Tasks extension identifier is missing from a source.');
    }
    if (!source.contains('integer milliseconds') ||
        !source.contains('ttlMs: number | null') ||
        !source.contains('pollIntervalMs?: number')) {
      failures.add(
        'Tasks timing prose/type ambiguity changed and needs SDK review.',
      );
    }
    if (!source.contains('JSON-RPC error') ||
        (!source.contains('error: { [key: string]: unknown }') &&
            !source.contains('error: JSONObject'))) {
      failures.add(
        'Tasks failed-state prose/type shape changed and needs SDK review.',
      );
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Pinned Tasks extension contract audit failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Pinned Tasks extension contract audit passed: methods, statuses, '
    'routing identity, and provisional high-risk shapes are unchanged.',
  );
}

bool _jsonEqual(Object? first, Object? second) {
  if (first is Set && second is Set) {
    return first.length == second.length && first.containsAll(second);
  }
  if (first is List && second is List) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (!_jsonEqual(first[index], second[index])) {
        return false;
      }
    }
    return true;
  }
  if (first is Map && second is Map) {
    if (first.length != second.length) {
      return false;
    }
    for (final key in first.keys) {
      if (!second.containsKey(key) || !_jsonEqual(first[key], second[key])) {
        return false;
      }
    }
    return true;
  }
  return first == second;
}
