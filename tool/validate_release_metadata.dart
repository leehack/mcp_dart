import 'dart:io';

import 'release/release_metadata_validator.dart';

void main(List<String> args) {
  String? packageName;
  String? tag;

  for (var index = 0; index < args.length; index += 1) {
    switch (args[index]) {
      case '--package':
        if (index + 1 >= args.length) {
          _usageError('--package requires mcp_dart or mcp_dart_cli.');
        }
        packageName = args[++index];
      case '--tag':
        if (index + 1 >= args.length) {
          _usageError('--tag requires a release tag.');
        }
        tag = args[++index];
      case '--help':
      case '-h':
        _printUsage();
        return;
      default:
        _usageError('Unknown argument: ${args[index]}');
    }
  }

  if (packageName == null) {
    _usageError('--package is required.');
  }

  ReleasePackage package;
  try {
    package = ReleasePackage.parse(packageName);
  } on FormatException catch (error) {
    _usageError(error.message);
  }

  final script = File(Platform.script.toFilePath()).absolute;
  final repoRoot = script.parent.parent;
  final result = ReleaseMetadataValidator(repoRoot).validate(
    package: package,
    tag: tag,
  );

  if (!result.isValid) {
    stderr.writeln(
      'Release metadata validation failed for ${result.package.packageName} '
      '${result.version}:',
    );
    for (final error in result.errors) {
      stderr.writeln(' - $error');
    }
    exitCode = 65;
    return;
  }

  final channel = result.isPrerelease ? 'prerelease' : 'stable';
  stdout.writeln(
    'Release metadata is consistent for ${result.package.packageName} '
    '${result.version} ($channel).',
  );
  if (result.isPrerelease) {
    stdout.writeln(
      'Final-spec acknowledgements are deferred for this prerelease.',
    );
  }
}

Never _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exit(64);
}

void _printUsage() {
  stdout.writeln('''
Usage: dart tool/validate_release_metadata.dart \\
  --package <mcp_dart|mcp_dart_cli> [--tag <release-tag>]

Checks package/version/tag alignment, coordinated SDK/CLI metadata, protocol
compatibility constants, pinned release inputs, and stable-only day-0 gates.
Prereleases validate current metadata without requiring final specification
acknowledgements.
''');
}
