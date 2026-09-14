import 'dart:io';

import 'smoke_programs.dart';

/// Compiles sequentially, outside the process-startup deadlines in tests.
Future<void> main() async {
  for (final source in smokePrograms) {
    final output = File('.dart_tool/smoke/$source.dill');
    await output.parent.create(recursive: true);
    final compiler = await Process.start(
      Platform.resolvedExecutable,
      ['compile', 'kernel', source, '-o', output.path],
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await compiler.exitCode;
    if (result != 0) {
      exitCode = result;
      return;
    }
  }
}
