import 'dart:io';

import 'package:mason/mason.dart';
import 'bricks/runner_script/brick.bundle.dart';

/// Generates the running script in the specified directory.
Future<void> generateRunnerScript(
  Directory outputDir,
  String packageName,
) async {
  // Use the pre-bundled brick to generate the runner script.
  final generator = await MasonGenerator.fromBundle(runnerScriptBundle);
  await generator.generate(
    DirectoryGeneratorTarget(outputDir),
    vars: {'packageName': packageName},
  );
}
