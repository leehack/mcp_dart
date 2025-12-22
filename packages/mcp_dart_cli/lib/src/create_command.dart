import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'template_resolver.dart';

typedef MasonGeneratorFromBrick = Future<MasonGenerator> Function(Brick brick);

class CreateCommand extends Command<int> {
  @override
  final name = 'create';

  @override
  final description = 'Creates a new MCP server project.';

  @override
  String get invocation =>
      'mcp_dart create <package_name> [project_path] [arguments]';

  CreateCommand({
    Logger? logger,
    @visibleForTesting MasonGeneratorFromBrick? generatorFromBrick,
  })  : _logger = logger ?? Logger(),
        _generatorFromBrick = generatorFromBrick ?? MasonGenerator.fromBrick {
    argParser.addOption(
      'template',
      help: 'The template to use. Can be a local path, a Git URL '
          '(url.git#ref:path), or a GitHub tree URL.',
      defaultsTo:
          'https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple',
    );
  }

  final Logger _logger;
  final MasonGeneratorFromBrick _generatorFromBrick;

  @override
  Future<int> run() async {
    final String packageName;
    final String projectPath;

    if (argResults!.rest.isEmpty) {
      packageName = _logger.prompt(
        'What is the project name?',
        defaultValue: 'mcp_server',
      );
      projectPath = packageName;
    } else {
      final firstArg = argResults!.rest.first;
      if (_isValidPackageName(firstArg)) {
        packageName = firstArg;
        projectPath =
            argResults!.rest.length > 1 ? argResults!.rest[1] : packageName;
      } else {
        projectPath = firstArg;
        packageName = _sanitizePackageName(
          p.basename(p.normalize(p.absolute(projectPath))),
        );
        _logger.info('Using inferred package name: $packageName');
      }
    }

    if (!_isValidPackageName(packageName)) {
      _logger.err(
        'Error: "$packageName" is not a valid package name.\n\n'
        'Package names should be all lowercase, with underscores to separate words, '
        'e.g. "mcp_server". Use only basic Latin letters and Arabic digits: [a-z0-9_]. '
        'Also, make sure the name is a valid Dart identifier -- that is, it '
        "doesn't start with digits and isn't a reserved word.",
      );
      return ExitCode.usage.code;
    }

    return await runGeneration(
      packageName: packageName,
      projectPath: projectPath,
      templateArg: argResults!['template'] as String,
    );
  }

  /// Extracted for testing purposes
  Future<int> runGeneration({
    required String packageName,
    required String projectPath,
    required String templateArg,
  }) async {
    final directory = Directory(projectPath);

    if (directory.existsSync() && directory.listSync().isNotEmpty) {
      _logger.err(
        'Error: Directory "$projectPath" already exists and is not empty.',
      );
      return ExitCode.cantCreate.code;
    }

    final brick = _resolveBrick(templateArg);

    final generator = await _generatorFromBrick(brick);
    final progress = _logger.progress('Creating $projectPath');

    await generator.generate(
      DirectoryGeneratorTarget(directory),
      vars: <String, dynamic>{'name': packageName},
    );
    progress.complete();

    await _runCommand(
      'dart',
      ['pub', 'get'],
      workingDirectory: directory.path,
      label: 'Running pub get',
    );

    // Auto-add mcp_dart to ensure latest version
    await _runCommand(
      'dart',
      ['pub', 'add', 'mcp_dart'],
      workingDirectory: directory.path,
      label: 'Adding mcp_dart dependency',
    );

    // Run dart format
    await _runCommand(
      'dart',
      ['format', '.'],
      workingDirectory: directory.path,
      label: 'Formatting code',
    );

    _logger.success('\nSuccess! Created $projectPath.');
    _logger.info('Run your server with:');
    if (projectPath != '.') {
      _logger.info('  cd $projectPath');
    }
    _logger.info('  dart run bin/server.dart');

    return ExitCode.success.code;
  }

  Future<void> _runCommand(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required String label,
  }) async {
    final progress = _logger.progress(label);
    try {
      final result = await runProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );

      if (result.exitCode != 0) {
        progress.fail();
        _logger.err('Error running $label:');
        _logger.err(result.stderr.toString());
        throw ProcessException(
          executable,
          arguments,
          result.stderr.toString(),
          result.exitCode,
        );
      }
      progress.complete();
    } catch (_) {
      progress.fail();
      rethrow;
    }
  }

  @visibleForTesting
  Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
  }

  bool _isValidPackageName(String name) {
    if (name.isEmpty) return false;
    return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name);
  }

  String _sanitizePackageName(String name) {
    var sanitized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (!RegExp(r'^[a-z]').hasMatch(sanitized)) {
      sanitized = 'mcp_$sanitized';
    }
    return sanitized.replaceAll(RegExp(r'_{2,}'), '_');
  }

  Brick _resolveBrick(String template) {
    const resolver = TemplateResolver();
    return resolver.resolve(template).toBrick();
  }
}
