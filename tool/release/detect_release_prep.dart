import 'dart:io';

import 'release_prep_plan.dart';

void main(List<String> args) {
  String? baseSha;
  String? githubOutputPath;
  for (var index = 0; index < args.length; index += 1) {
    switch (args[index]) {
      case '--base-sha':
        baseSha = _value(args, ++index, '--base-sha');
      case '--github-output':
        githubOutputPath = _value(args, ++index, '--github-output');
      case '--help':
      case '-h':
        _printUsage();
        return;
      default:
        _usageError('Unknown argument: ${args[index]}');
    }
  }
  if (baseSha == null) {
    _usageError('--base-sha is required.');
  }
  if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(baseSha)) {
    _usageError('--base-sha must be a full 40-character commit SHA.');
  }

  try {
    final plan = ReleasePrepPlan.detect(
      baseSdkPubspec: _gitFile(baseSha, 'pubspec.yaml'),
      headSdkPubspec: File('pubspec.yaml').readAsStringSync(),
      baseCliPubspec: _gitFile(
        baseSha,
        'packages/mcp_dart_cli/pubspec.yaml',
      ),
      headCliPubspec: File(
        'packages/mcp_dart_cli/pubspec.yaml',
      ).readAsStringSync(),
    );
    final output = <String, String>{
      'packages': plan.packagesJson,
      'release_sdk': plan.packageNames.contains('mcp_dart').toString(),
      'release_cli': plan.packageNames.contains('mcp_dart_cli').toString(),
      'channel': plan.channel.name,
      'sdk_version': plan.sdkVersion,
      'cli_version': plan.cliVersion,
    };
    for (final entry in output.entries) {
      stdout.writeln('${entry.key}=${entry.value}');
    }
    if (githubOutputPath != null) {
      File(githubOutputPath).writeAsStringSync(
        output.entries.map((entry) => '${entry.key}=${entry.value}\n').join(),
        mode: FileMode.append,
      );
    }
  } on Object catch (error) {
    stderr.writeln('Invalid release-prep change: $error');
    exitCode = 65;
  }
}

String _gitFile(String sha, String path) {
  final result = Process.runSync('git', ['show', '$sha:$path']);
  if (result.exitCode != 0) {
    throw StateError('Could not read $path at $sha: ${result.stderr}');
  }
  return result.stdout as String;
}

String _value(List<String> args, int index, String option) {
  if (index >= args.length) {
    _usageError('$option requires a value.');
  }
  return args[index];
}

Never _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exit(64);
}

void _printUsage() {
  stdout.writeln('''
Usage: dart tool/release/detect_release_prep.dart \\
  --base-sha <40-character-sha> [--github-output <path>]

Compares package versions at the PR base with the checked-out release-prep
commit and reports which packages should be released and on which channel.
''');
}
