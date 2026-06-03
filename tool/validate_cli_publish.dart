import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final repoRoot = _repoRoot();
  final outputRoot = options.outputPath == null
      ? Directory.systemTemp.createTempSync('mcp_dart_cli_publish_')
      : Directory(options.outputPath!).absolute;

  if (outputRoot.existsSync()) {
    if (outputRoot.listSync().isNotEmpty) {
      stderr.writeln('Output directory must be empty: ${outputRoot.path}');
      exitCode = 64;
      return;
    }
  } else {
    outputRoot.createSync(recursive: true);
  }

  _ensureOutputOutsideRepo(repoRoot, outputRoot);
  _copyDirectory(repoRoot, outputRoot);

  final cliDir = Directory(
    _join(outputRoot.path, ['packages', 'mcp_dart_cli']),
  );

  if (options.usePublishedSdk) {
    final overrides = File(_join(cliDir.path, ['pubspec_overrides.yaml']));
    if (overrides.existsSync()) {
      overrides.deleteSync();
    }
  }

  stdout.writeln('Exported CLI publish tree to ${cliDir.path}');

  if (!options.runDryRun) {
    stdout.writeln('Run: cd ${cliDir.path} && dart pub publish --dry-run');
    return;
  }

  await _run(['dart', 'pub', 'get'], workingDirectory: cliDir.path);
  await _run(
    ['dart', 'pub', 'publish', '--dry-run'],
    workingDirectory: cliDir.path,
  );
}

Directory _repoRoot() {
  final script = File(Platform.script.toFilePath());
  return script.parent.parent.absolute;
}

void _ensureOutputOutsideRepo(Directory repoRoot, Directory outputRoot) {
  final repoPath = _normalized(repoRoot.path);
  final outputPath = _normalized(outputRoot.path);
  if (outputPath == repoPath || outputPath.startsWith('$repoPath/')) {
    stderr.writeln(
      'Output directory must be outside the repository so parent .pubignore '
      'files do not affect the nested CLI package archive.',
    );
    exit(64);
  }
}

void _copyDirectory(Directory source, Directory target) {
  for (final entity in source.listSync(followLinks: false)) {
    final name = _basename(entity.path);
    if (_excludedNames.contains(name)) {
      continue;
    }

    final targetPath = _join(target.path, [name]);
    if (entity is Directory) {
      final nextTarget = Directory(targetPath)..createSync();
      _copyDirectory(entity, nextTarget);
    } else if (entity is File) {
      entity.copySync(targetPath);
    } else if (entity is Link) {
      final link = Link(targetPath);
      link.createSync(entity.targetSync(), recursive: true);
    }
  }
}

Future<void> _run(
  List<String> command, {
  required String workingDirectory,
}) async {
  stdout.writeln('Running: ${command.join(' ')}');
  final process = await Process.start(
    command.first,
    command.sublist(1),
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  final stdoutDone = stdout.addStream(process.stdout);
  final stderrDone = stderr.addStream(process.stderr);
  final code = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);

  if (code != 0) {
    exit(code);
  }
}

String _join(String first, List<String> rest) {
  var result = first;
  for (final part in rest) {
    if (result.endsWith(Platform.pathSeparator)) {
      result = '$result$part';
    } else {
      result = '$result${Platform.pathSeparator}$part';
    }
  }
  return result;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _normalized(String path) {
  return Directory(path).absolute.path.replaceAll('\\', '/');
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run tool/validate_cli_publish.dart [options]

Exports packages/mcp_dart_cli outside the monorepo git/.pubignore context and
runs dart pub publish --dry-run from that exported package.

Options:
  --output <dir>       Export to an empty directory outside the repository.
  --published-sdk      Remove pubspec_overrides.yaml so the CLI resolves the
                       SDK version from pub.dev. Use after publishing mcp_dart.
  --no-dry-run         Export only; print the publish command.
  --help               Print this help.
''');
}

const _excludedNames = {
  '.dart_tool',
  '.git',
  'build',
  'coverage',
  'pubspec.lock',
};

class _Options {
  final String? outputPath;
  final bool runDryRun;
  final bool usePublishedSdk;
  final bool showHelp;

  const _Options({
    required this.outputPath,
    required this.runDryRun,
    required this.usePublishedSdk,
    required this.showHelp,
  });

  factory _Options.parse(List<String> args) {
    String? outputPath;
    var runDryRun = true;
    var usePublishedSdk = false;
    var showHelp = false;

    for (var i = 0; i < args.length; i += 1) {
      final arg = args[i];
      switch (arg) {
        case '--output':
          if (i + 1 >= args.length) {
            stderr.writeln('--output requires a directory path.');
            exit(64);
          }
          outputPath = args[++i];
        case '--published-sdk':
          usePublishedSdk = true;
        case '--no-dry-run':
          runDryRun = false;
        case '--help':
        case '-h':
          showHelp = true;
        default:
          stderr.writeln('Unknown option: $arg');
          exit(64);
      }
    }

    return _Options(
      outputPath: outputPath,
      runDryRun: runDryRun,
      usePublishedSdk: usePublishedSdk,
      showHelp: showHelp,
    );
  }
}
