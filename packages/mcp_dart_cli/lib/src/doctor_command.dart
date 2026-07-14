import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'utils/mcp_connection.dart';

class DoctorCommand extends Command<int> {
  @override
  final name = 'doctor';

  @override
  final description = 'Show information about the created project.';

  final Logger _logger;

  DoctorCommand({Logger? logger}) : _logger = logger ?? Logger();

  @override
  Future<int> run() async {
    _logger.info('Running doctor...');

    final checks = <_Check>[];

    // 1. Check for pubspec.yaml
    checks.add(_checkPubspec());

    // 2. Check for mcp_dart dependency (if pubspec exists)
    if (File('pubspec.yaml').existsSync()) {
      checks.add(_checkMcpDartDependency());
    }

    // 3. Check for lib/mcp/mcp.dart
    checks.add(_checkEntrypoint());

    // 4. Check for analysis_options.yaml
    checks.add(_checkAnalysisOptions());

    // Report static check results first
    bool staticChecksPassed = true;
    for (final check in checks) {
      if (check.passed) {
        _logger.success(check.message);
      } else {
        _logger.err(check.message);
        staticChecksPassed = false;
      }
    }

    if (!staticChecksPassed) {
      _logger.info('');
      _logger.err('Static checks failed. Skipping dynamic verification.');
      return ExitCode.config.code;
    }

    // 5. Dynamic Verification
    _logger.info('');
    _logger.info('Running dynamic verification (starting server)...');
    try {
      final passed = await _runDynamicChecks();
      if (passed) {
        _logger.info('');
        _logger.success('No issues found! 🎉');
        return ExitCode.success.code;
      } else {
        _logger.info('');
        _logger.err('Issues found during dynamic verification.');
        return ExitCode.software.code;
      }
    } catch (e) {
      _logger.err('Failed to run dynamic checks: $e');
      return ExitCode.software.code;
    }
  }

  Future<bool> _runDynamicChecks() async {
    McpConnection? connection;

    try {
      connection = await McpConnection.connectToLocalProject(_logger);
      _logger.success('[✓] Server started and connected');
      return await verifyAdvertisedInventory(connection.client, _logger);
    } catch (e) {
      _logger.err('[x] Connection failed: $e');
      return false;
    } finally {
      await connection?.close();
    }
  }

  _Check _checkPubspec() {
    final file = File('pubspec.yaml');
    if (file.existsSync()) {
      return _Check(true, '[✓] pubspec.yaml exists');
    } else {
      return _Check(false, '[x] pubspec.yaml not found');
    }
  }

  _Check _checkMcpDartDependency() {
    try {
      final file = File('pubspec.yaml');
      final content = file.readAsStringSync();
      final yaml = loadYaml(content);
      final dependencies = yaml['dependencies'] as Map?;

      if (dependencies != null &&
          (dependencies.containsKey('mcp') ||
              dependencies.containsKey('mcp_dart'))) {
        return _Check(true, '[✓] mcp dependency found');
      }
      return _Check(false, '[x] mcp dependency not found in pubspec.yaml');
    } catch (e) {
      return _Check(false, '[x] Failed to parse pubspec.yaml: $e');
    }
  }

  _Check _checkEntrypoint() {
    final file = File(p.join('lib', 'mcp', 'mcp.dart'));
    if (file.existsSync()) {
      return _Check(true, '[✓] lib/mcp/mcp.dart exists');
    } else {
      return _Check(
        false,
        '[x] lib/mcp/mcp.dart not found (required for "serve" command)',
      );
    }
  }

  _Check _checkAnalysisOptions() {
    final file = File('analysis_options.yaml');
    if (file.existsSync()) {
      return _Check(true, '[✓] analysis_options.yaml exists');
    } else {
      return _Check(false, '[x] analysis_options.yaml not found');
    }
  }
}

/// Lists advertised MCP primitives without invoking tools or reading content.
///
/// Use `inspect-server --probe-config` when intentional, argument-bearing
/// operations are needed. `doctor` stays side-effect free after connecting.
Future<bool> verifyAdvertisedInventory(McpClient client, Logger logger) async {
  var allPassed = true;
  final capabilities = client.getServerCapabilities();

  if (capabilities?.tools != null) {
    try {
      final tools = await client.listTools();
      logger.success('[✓] Listed ${tools.tools.length} tools');
    } catch (e) {
      logger.err('[x] Failed to list tools: $e');
      allPassed = false;
    }
  }

  if (capabilities?.resources != null) {
    try {
      final resources = await client.listResources();
      logger.success('[✓] Listed ${resources.resources.length} resources');

      final templates = await client.listResourceTemplates();
      logger.success(
        '[✓] Listed ${templates.resourceTemplates.length} resource templates',
      );
    } catch (e) {
      logger.err('[x] Failed to list resources: $e');
      allPassed = false;
    }
  }

  if (capabilities?.prompts != null) {
    try {
      final prompts = await client.listPrompts();
      logger.success('[✓] Listed ${prompts.prompts.length} prompts');
    } catch (e) {
      logger.err('[x] Failed to list prompts: $e');
      allPassed = false;
    }
  }

  return allPassed;
}

class _Check {
  final bool passed;
  final String message;

  _Check(this.passed, this.message);
}
