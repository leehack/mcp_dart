import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

import 'runner_script_generator.dart';
import 'utils/pubspec_utils.dart';

class ServeCommand extends Command<int> {
  @override
  final name = 'serve';

  @override
  final description = 'Runs the MCP server in the current directory.';

  ServeCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'transport',
      abbr: 't',
      allowed: ['stdio', 'http'],
      defaultsTo: 'stdio',
      help: 'Transport type to use.',
    );
    argParser.addOption(
      'host',
      defaultsTo: '127.0.0.1',
      help: 'Host for HTTP transport.',
    );
    argParser.addOption(
      'port',
      abbr: 'p',
      defaultsTo: '3000',
      help: 'Port for HTTP transport.',
    );
    argParser.addFlag(
      'watch',
      defaultsTo: false,
      help: 'Restart the server on file changes.',
    );
  }

  final Logger _logger;

  @override
  Future<int> run() async {
    final watch = argResults!['watch'] as bool;
    final transport = argResults!['transport'] as String;
    if (watch && transport != 'http') {
      _logger.err('Error: --watch requires --transport http.');
      return ExitCode.usage.code;
    }

    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      _logger.err('Error: pubspec.yaml not found in current directory.');
      return ExitCode.usage.code;
    }

    final packageName = await readPackageNameFromPubspec(pubspecFile);

    if (packageName == null) {
      _logger.err('Error: Could not determine package name from pubspec.yaml.');
      return ExitCode.config.code;
    }

    // Verify lib/mcp/mcp.dart exists
    final mcpFile = File(p.join('lib', 'mcp', 'mcp.dart'));
    if (!mcpFile.existsSync()) {
      _logger.err('Error: lib/mcp/mcp.dart not found.');
      _logger.err(
        'Ensure your project follows the MCP server structure and exports createMcpServer().',
      );
      return ExitCode.config.code;
    }

    final dotDartToolDir = Directory(p.join('.dart_tool', 'mcp_dart'));
    if (!dotDartToolDir.existsSync()) {
      dotDartToolDir.createSync(recursive: true);
    }

    // Generate the runner script using Mason
    await generateRunnerScript(dotDartToolDir, packageName);
    final runnerFile = File(p.join(dotDartToolDir.path, 'runner.dart'));

    final args = argResults!.arguments
        .where((arg) => arg != '--watch')
        .toList();

    Process? process;
    bool isRestarting = false;

    Future<void> startServer() async {
      if (process != null) {
        if (transport == 'http') {
          _logger.info('Restarting server...');
        }
        process!.kill();
        await process!.exitCode;
      } else {
        if (transport == 'http') {
          _logger.info('Starting MCP server ($packageName)...');
        }
      }

      process = await Process.start(
        'dart',
        ['run', runnerFile.path, ...args],
        mode: transport == 'stdio'
            ? ProcessStartMode.inheritStdio
            : ProcessStartMode.normal,
      );
      if (transport == 'http') {
        process!.stdout.transform(utf8.decoder).listen(stdout.write);
        process!.stderr.transform(utf8.decoder).listen(stderr.write);
      }

      // ignore: unawaited_futures
      process!.exitCode.then((code) {
        if (!isRestarting && code != 0 && code != -15) {
          // -15 is specific to kill signal
          _logger.err('Server exited with code $code');
          if (!watch) exit(code);
        }
      });
    }

    await startServer();

    if (watch) {
      final watcher = DirectoryWatcher(p.join(Directory.current.path, 'lib'));
      _logger.info('Watching for changes in lib/...');

      watcher.events
          .debounce(const Duration(milliseconds: 500))
          .asyncMap((_) async {
            isRestarting = true;
            try {
              await startServer();
            } finally {
              isRestarting = false;
            }
          })
          .listen(null);

      // Keep the command running
      final complexCompleter = Completer<int>();
      ProcessSignal.sigint.watch().listen((_) {
        process?.kill();
        complexCompleter.complete(0);
      });
      return complexCompleter.future;
    } else {
      final exitCode = await process!.exitCode;
      return exitCode;
    }
  }
}
