import 'dart:io';

import 'release_link_manager.dart';
import 'release_notes.dart';

void main(List<String> args) {
  String? packageName;
  String? rootPath;
  String? expectedRef;
  String? outputPath;

  for (var index = 0; index < args.length; index += 1) {
    switch (args[index]) {
      case '--package':
        packageName = _value(args, ++index, '--package');
      case '--root':
        rootPath = _value(args, ++index, '--root');
      case '--ref':
        expectedRef = _value(args, ++index, '--ref');
      case '--output':
        outputPath = _value(args, ++index, '--output');
      case '--help':
      case '-h':
        _printUsage();
        return;
      default:
        _usageError('Unknown argument: ${args[index]}');
    }
  }

  if (packageName == null ||
      rootPath == null ||
      expectedRef == null ||
      outputPath == null) {
    _usageError('--package, --root, --ref, and --output are required.');
  }

  try {
    final package = ReleasePackage.parse(packageName);
    final packageRoot = Directory(rootPath);
    final manager = ReleaseLinkManager(
      packageRoot: packageRoot,
      package: package,
    );
    final changelog = File('${packageRoot.path}/CHANGELOG.md');
    if (!changelog.existsSync()) {
      throw FileSystemException('Missing package changelog.', changelog.path);
    }
    final notes = extractReleaseNotes(
      changelog: changelog.readAsStringSync(),
      version: manager.version,
    );
    final rendered = manager.rewriteText(notes, expectedRef);
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(rendered);
    stdout.writeln(
      'Prepared ${package.packageName} ${manager.version} release notes at '
      '${output.path}.',
    );
  } on Object catch (error) {
    stderr.writeln('Could not prepare release notes: $error');
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
Usage: dart tool/release/prepare_release_notes.dart \\
  --package <mcp_dart|mcp_dart_cli> \\
  --root <package-root> \\
  --ref <release-tag> \\
  --output <release-notes.md>

Extracts the package's exact-version changelog section, rewrites
same-repository source links to the immutable release tag, and writes the
GitHub release body.
''');
}
