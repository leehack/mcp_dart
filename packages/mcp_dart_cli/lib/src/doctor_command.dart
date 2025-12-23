import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'utils/mcp_connection.dart';
import 'utils/schema_utils.dart';

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
    bool allPassed = true;

    try {
      connection = await McpConnection.connectToLocalProject(_logger);
      _logger.success('[✓] Server started and connected');

      // Test Tools
      try {
        final tools = await connection.client.listTools();
        _logger.success('[✓] Listed ${tools.tools.length} tools');

        for (final tool in tools.tools) {
          try {
            final dummyArgs = generateDummyArguments(tool.inputSchema);
            await connection.client.callTool(
                CallToolRequest(name: tool.name, arguments: dummyArgs));
            _logger.detail(
                '    [✓] Tool "${tool.name}" executed successfully (dummy args)');
          } catch (e) {
            if (e is McpError && e.code == -32602) {
              // Invalid params is "success" in terms of reaching the tool
              _logger.detail(
                  '    [✓] Tool "${tool.name}" reachable (rejected dummy args)');
            } else {
              _logger.warn('    [!] Tool "${tool.name}" execution error: $e');
              // We don't fail the doctor for runtime errors in tools, just warn.
              // Unless we want to be strict. Let's be lenient for "doctor".
            }
          }
        }
      } catch (e) {
        _logger.err('[x] Failed to list tools: $e');
        allPassed = false;
      }

      // Test Resources
      try {
        final resources = await connection.client.listResources();
        _logger.success('[✓] Listed ${resources.resources.length} resources');
        for (final resource in resources.resources) {
          try {
            await connection.client
                .readResource(ReadResourceRequest(uri: resource.uri));
            _logger
                .detail('    [✓] Resource "${resource.uri}" read successfully');
          } catch (e) {
            _logger.warn('    [!] Resource "${resource.uri}" read error: $e');
          }
        }
      } catch (e) {
        _logger.err('[x] Failed to list resources: $e');
        allPassed = false;
      }

      // Test Prompts
      try {
        final prompts = await connection.client.listPrompts();
        _logger.success('[✓] Listed ${prompts.prompts.length} prompts');
        for (final prompt in prompts.prompts) {
          try {
            await connection.client
                .getPrompt(GetPromptRequest(name: prompt.name));
            _logger.detail(
                '    [✓] Prompt "${prompt.name}" retrieved successfully');
          } catch (e) {
            _logger.warn('    [!] Prompt "${prompt.name}" error: $e');
          }
        }
      } catch (e) {
        _logger.err('[x] Failed to list prompts: $e');
        allPassed = false;
      }
    } catch (e) {
      _logger.err('[x] Connection failed: $e');
      return false;
    } finally {
      await connection?.close();
    }

    return allPassed;
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
      return _Check(false,
          '[x] lib/mcp/mcp.dart not found (required for "serve" command)');
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

class _Check {
  final bool passed;
  final String message;

  _Check(this.passed, this.message);
}
