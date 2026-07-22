import 'dart:io';

import 'release_link_manager.dart';

void main(List<String> args) {
  String? packageName;
  String? rootPath;
  String? expectedRef;
  var checkOnly = false;

  for (var index = 0; index < args.length; index += 1) {
    switch (args[index]) {
      case '--package':
        packageName = _value(args, ++index, '--package');
      case '--root':
        rootPath = _value(args, ++index, '--root');
      case '--ref':
        expectedRef = _value(args, ++index, '--ref');
      case '--check':
        checkOnly = true;
      case '--help':
      case '-h':
        _printUsage();
        return;
      default:
        _usageError('Unknown argument: ${args[index]}');
    }
  }

  if (packageName == null || rootPath == null || expectedRef == null) {
    _usageError('--package, --root, and --ref are required.');
  }

  try {
    final manager = ReleaseLinkManager(
      packageRoot: Directory(rootPath),
      package: ReleasePackage.parse(packageName),
    );
    final result =
        checkOnly ? manager.check(expectedRef) : manager.update(expectedRef);
    if (!result.isValid) {
      stderr.writeln('Release-link validation failed:');
      for (final issue in result.issues) {
        stderr.writeln(' - $issue');
      }
      exitCode = 65;
      return;
    }
    if (checkOnly) {
      stdout.writeln(
        'Release-facing links use $expectedRef for ${manager.package.packageName}.',
      );
    } else if (result.changedFiles.isEmpty) {
      stdout.writeln('Release-facing links already use $expectedRef.');
    } else {
      stdout.writeln(
        'Updated ${result.changedFiles.length} release-facing file(s) to '
        '$expectedRef:',
      );
      for (final path in result.changedFiles) {
        stdout.writeln(' - $path');
      }
    }
  } on Object catch (error) {
    stderr.writeln('Could not update release links: $error');
    exitCode = 65;
  }
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
Usage: dart tool/release/update_release_links.dart \\
  --package <mcp_dart|mcp_dart_cli> \\
  --root <package-root> \\
  --ref <main|release-tag> [--check]

Checked-in release-facing links use main. Release workflows copy a package to
a staging directory and rewrite that copy to its immutable release tag.
''');
}
