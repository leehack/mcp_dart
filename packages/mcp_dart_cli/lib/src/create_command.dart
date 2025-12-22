import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'template_resolver.dart';

class CreateCommand extends Command<int> {
  @override
  final name = 'create';

  @override
  final description = 'Creates a new MCP server project.';

  @override
  String get invocation =>
      'mcp_dart create <package_name> [project_path] [arguments]';

  CreateCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'template',
      help: 'The template to use. Can be a local path, a Git URL '
          '(url.git#ref:path), or a GitHub tree URL.',
      defaultsTo:
          'https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple',
    );
  }

  final Logger _logger;

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
      packageName = argResults!.rest.first;
      projectPath =
          argResults!.rest.length > 1 ? argResults!.rest[1] : packageName;
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

    final directory = Directory(projectPath);

    if (directory.existsSync()) {
      _logger.err('Error: Directory "$projectPath" already exists.');
      return ExitCode.cantCreate.code;
    }

    final templateArg = argResults!['template'] as String;
    final brick = _resolveBrick(templateArg);

    final generator = await MasonGenerator.fromBrick(brick);
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
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: true,
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

  bool _isValidPackageName(String name) {
    if (name.isEmpty) return false;
    return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name);
  }

  Brick _resolveBrick(String template) {
    const resolver = TemplateResolver();
    return resolver.resolve(template).toBrick();
  }
}
