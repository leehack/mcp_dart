import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/agent_skill_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('AgentSkillsCommand', () {
    late Logger logger;

    setUp(() {
      logger = MockLogger();
    });

    test('installs bundled MCP developer skill', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final runner = CommandRunner<int>('mcp_dart', 'CLI')
        ..addCommand(AgentSkillsCommand(logger: logger));

      final result = await runner.run([
        'skills',
        'install',
        '--target',
        tempDir.path,
      ]);

      expect(result, equals(ExitCode.success.code));
      final skillFile = File(
        p.join(tempDir.path, 'mcp-developer', 'SKILL.md'),
      );
      expect(skillFile.existsSync(), isTrue);
      expect(skillFile.readAsStringSync(), contains('mcp_dart list-tools'));
    });

    test('does not overwrite existing skill unless forced', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final skillDir = Directory(p.join(tempDir.path, 'mcp-developer'))
        ..createSync(recursive: true);
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('custom');
      final runner = CommandRunner<int>('mcp_dart', 'CLI')
        ..addCommand(AgentSkillsCommand(logger: logger));

      final result = await runner.run([
        'skills',
        'install',
        '--target',
        tempDir.path,
      ]);

      expect(result, equals(ExitCode.config.code));
      expect(
        File(p.join(skillDir.path, 'SKILL.md')).readAsStringSync(),
        equals('custom'),
      );
    });
  });
}
