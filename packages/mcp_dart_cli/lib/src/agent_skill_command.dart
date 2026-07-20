import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;

/// Installs or prints bundled agent workflow skills for MCP development.
class AgentSkillsCommand extends Command<int> {
  /// Creates the agent skills command group.
  AgentSkillsCommand({Logger? logger, AgentSkillLoader? skillLoader})
    : _logger = logger ?? Logger(),
      _skillLoader = skillLoader ?? const AgentSkillLoader() {
    addSubcommand(_PrintAgentSkillCommand(skillLoader: _skillLoader));
    addSubcommand(
      _InstallAgentSkillCommand(logger: _logger, skillLoader: _skillLoader),
    );
  }

  final Logger _logger;
  final AgentSkillLoader _skillLoader;

  @override
  final name = 'skills';

  @override
  final description =
      'Installs or prints bundled agent workflow skills for MCP development.';
}

class _PrintAgentSkillCommand extends Command<int> {
  _PrintAgentSkillCommand({required this._skillLoader});

  final AgentSkillLoader _skillLoader;

  @override
  final name = 'print';

  @override
  final description = 'Prints the bundled MCP developer skill.';

  @override
  Future<int> run() async {
    stdout.write(await _skillLoader.loadMcpDeveloperSkill());
    return ExitCode.success.code;
  }
}

class _InstallAgentSkillCommand extends Command<int> {
  _InstallAgentSkillCommand({
    required this._logger,
    required this._skillLoader,
  }) {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help:
            'Skill root directory. Defaults to \$CODEX_HOME/skills or ~/.codex/skills.',
      )
      ..addOption(
        'name',
        defaultsTo: 'mcp-developer',
        help: 'Skill directory name to create under the target directory.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite an existing SKILL.md.',
        negatable: false,
      );
  }

  final Logger _logger;
  final AgentSkillLoader _skillLoader;

  @override
  final name = 'install';

  @override
  final description = 'Installs the bundled MCP developer skill.';

  @override
  Future<int> run() async {
    final targetRoot = argResults?['target'] as String? ?? _defaultSkillRoot();
    final skillName = argResults?['name'] as String? ?? 'mcp-developer';
    final force = argResults?['force'] as bool? ?? false;

    if (skillName.trim().isEmpty || skillName.contains(RegExp(r'[\\/]'))) {
      _logger.err('--name must be a single non-empty directory name.');
      return ExitCode.usage.code;
    }

    final skillDir = Directory(p.join(targetRoot, skillName));
    final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
    if (skillFile.existsSync() && !force) {
      _logger.err(
        '${skillFile.path} already exists. Re-run with --force to overwrite it.',
      );
      return ExitCode.config.code;
    }

    skillDir.createSync(recursive: true);
    skillFile.writeAsStringSync(await _skillLoader.loadMcpDeveloperSkill());
    _logger.success('Installed MCP developer skill at ${skillFile.path}');
    return ExitCode.success.code;
  }

  String _defaultSkillRoot() {
    final codexHome = Platform.environment['CODEX_HOME'];
    if (codexHome != null && codexHome.isNotEmpty) {
      return p.join(codexHome, 'skills');
    }

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return p.join(home, '.codex', 'skills');
  }
}

/// Loads bundled agent skill Markdown from package or standalone install files.
class AgentSkillLoader {
  /// Creates a loader for bundled agent skills.
  const AgentSkillLoader();

  static const _packageSkillUri =
      'package:mcp_dart_cli/src/skills/mcp-developer/SKILL.md';

  /// Loads the bundled MCP developer skill Markdown.
  Future<String> loadMcpDeveloperSkill() async {
    final packageUri = await Isolate.resolvePackageUri(
      Uri.parse(_packageSkillUri),
    );
    if (packageUri != null && packageUri.scheme == 'file') {
      final file = File.fromUri(packageUri);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }

    for (final file in _standaloneSkillCandidates()) {
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }

    throw StateError(
      'Bundled MCP developer skill markdown was not found. Reinstall mcp_dart_cli or rerun the standalone installer.',
    );
  }

  List<File> _standaloneSkillCandidates() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    return [
      File(p.join(executableDir, 'mcp-developer.SKILL.md')),
      File(
        p.normalize(
          p.join(
            executableDir,
            '..',
            'share',
            'mcp_dart',
            'skills',
            'mcp-developer',
            'SKILL.md',
          ),
        ),
      ),
      File(
        p.join(
          Directory.current.path,
          'lib',
          'src',
          'skills',
          'mcp-developer',
          'SKILL.md',
        ),
      ),
      File(
        p.join(
          Directory.current.path,
          'packages',
          'mcp_dart_cli',
          'lib',
          'src',
          'skills',
          'mcp-developer',
          'SKILL.md',
        ),
      ),
    ];
  }
}
