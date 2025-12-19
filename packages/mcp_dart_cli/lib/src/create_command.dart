import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'template_resolver.dart';

class CreateCommand extends Command<int> {
  @override
  final name = 'create';

  @override
  final description = 'Creates a new MCP server project.';

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
    if (argResults!.rest.isEmpty) {
      _logger.err('Usage: mcp_dart create <project_name> [arguments]');
      return ExitCode.usage.code;
    }

    final projectName = argResults!.rest.first;
    final directory = Directory(projectName);

    if (directory.existsSync()) {
      _logger.err('Error: Directory "$projectName" already exists.');
      return ExitCode.cantCreate.code;
    }

    final templateArg = argResults!['template'] as String;
    final brick = _resolveBrick(templateArg);

    final generator = await MasonGenerator.fromBrick(brick);
    final progress = _logger.progress('Creating $projectName');

    await generator.generate(
      DirectoryGeneratorTarget(directory),
      vars: <String, dynamic>{'name': projectName},
    );
    progress.complete();

    _logger.info('Running dart pub get...');
    var result = await Process.run(
      'dart',
      ['pub', 'get'],
      workingDirectory: directory.path,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      _logger.err('Error running pub get:');
      _logger.err(result.stderr.toString());
      return result.exitCode;
    }

    // Auto-add mcp_dart to ensure latest version
    _logger.info('Adding latest mcp_dart dependency...');
    result = await Process.run(
      'dart',
      ['pub', 'add', 'mcp_dart'],
      workingDirectory: directory.path,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      _logger.err('Error adding mcp_dart:');
      _logger.err(result.stderr.toString());
      return result.exitCode;
    }

    _logger.success('\nSuccess! Created $projectName.');
    _logger.info('Run your server with:');
    _logger.info('  cd $projectName');
    _logger.info('  dart run bin/server.dart');

    return ExitCode.success.code;
  }

  Brick _resolveBrick(String template) {
    const resolver = TemplateResolver();
    return resolver.resolve(template).toBrick();
  }
}
