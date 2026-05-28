import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

/// Proxies stdio MCP traffic between a client and server while writing a trace.
class TraceCommand extends Command<int> {
  /// Creates a trace command.
  TraceCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'report',
        help:
            'Path to write the JSON trace report. Required because stdout is reserved for MCP traffic.',
      )
      ..addOption(
        'server-cwd',
        help: 'Working directory for the proxied server command.',
      )
      ..addMultiOption(
        'env',
        help: 'Environment variables for the server in KEY=VALUE format.',
      )
      ..addOption(
        'max-runtime-ms',
        defaultsTo: '300000',
        help: 'Maximum milliseconds to keep the proxy running.',
      )
      ..addFlag(
        'pretty',
        help: 'Pretty-print the JSON trace report.',
        defaultsTo: true,
      );
  }

  final Logger _logger;

  @override
  final String name = 'trace';

  @override
  final String description =
      'Runs a stdio MCP proxy that forwards traffic and records a JSON trace.';

  @override
  String get invocation =>
      'mcp_dart trace --report <path> [options] -- <server-command> ...';

  @override
  Future<int> run() async {
    final reportPath = argResults?['report'] as String?;
    if (reportPath == null || reportPath.trim().isEmpty) {
      _logger.err('--report is required for trace.');
      return ExitCode.usage.code;
    }
    final maxRuntimeMs = int.tryParse(
      argResults?['max-runtime-ms'] as String? ?? '',
    );
    if (maxRuntimeMs == null || maxRuntimeMs < 1) {
      _logger.err('--max-runtime-ms must be a positive integer.');
      return ExitCode.usage.code;
    }
    final env = _parseEnvArgs(argResults);
    if (env == null) return ExitCode.usage.code;

    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _logger.err('Missing proxied server command after --.');
      return ExitCode.usage.code;
    }

    final proxy = StdioTraceProxy(
      command: rest.first,
      args: rest.sublist(1),
      workingDirectory: argResults?['server-cwd'] as String?,
      environment: env,
      reportFile: File(reportPath),
      maxRuntime: Duration(milliseconds: maxRuntimeMs),
      pretty: argResults?['pretty'] as bool? ?? true,
    );

    try {
      await proxy.run();
      return proxy.failed ? ExitCode.software.code : ExitCode.success.code;
    } catch (error) {
      _logger.err('trace failed: $error');
      return ExitCode.software.code;
    }
  }

  Map<String, String>? _parseEnvArgs(ArgResults? results) {
    final envList = results?['env'] as List<String>? ?? const [];
    final env = <String, String>{};
    for (final entry in envList) {
      final separator = entry.indexOf('=');
      if (separator <= 0) {
        _logger.err('--env values must use KEY=VALUE syntax.');
        return null;
      }
      env[entry.substring(0, separator)] = entry.substring(separator + 1);
    }
    return env;
  }
}

/// Stdio proxy implementation used by [TraceCommand].
class StdioTraceProxy {
  /// Creates a stdio trace proxy.
  StdioTraceProxy({
    required this.command,
    required this.args,
    required this.workingDirectory,
    required this.environment,
    required this.reportFile,
    required this.maxRuntime,
    required this.pretty,
    Stream<String>? clientLines,
  }) : _clientLines = clientLines;

  /// Proxied server executable.
  final String command;

  /// Proxied server arguments.
  final List<String> args;

  /// Proxied server working directory.
  final String? workingDirectory;

  /// Extra environment for the proxied server.
  final Map<String, String> environment;

  /// Trace report destination.
  final File reportFile;

  /// Maximum proxy runtime.
  final Duration maxRuntime;

  /// Whether to pretty-print the report JSON.
  final bool pretty;

  final Stream<String>? _clientLines;

  final Stopwatch _stopwatch = Stopwatch();
  final List<Map<String, dynamic>> _events = <Map<String, dynamic>>[];
  final Map<String, int> _methodCounts = <String, int>{};
  final Completer<void> _done = Completer<void>();
  Future<void> _stdoutWriteQueue = Future<void>.value();
  Future<void> _serverStdinWriteQueue = Future<void>.value();

  Process? _server;
  StreamSubscription<String>? _clientSubscription;
  StreamSubscription<String>? _serverSubscription;
  StreamSubscription<List<int>>? _serverStderrSubscription;
  Timer? _maxTimer;
  bool _hadMalformedTraffic = false;
  bool _timedOut = false;
  int? _serverExitCode;

  /// Whether any malformed JSON-RPC traffic was observed.
  bool get hadMalformedTraffic => _hadMalformedTraffic;

  /// Whether the trace ended because the runtime limit fired.
  bool get timedOut => _timedOut;

  /// Whether the trace should be treated as failed.
  bool get failed => _hadMalformedTraffic || _timedOut;

  /// Runs the proxy until the client closes, the server exits, or timeout fires.
  Future<void> run() async {
    _stopwatch.start();
    _server = await Process.start(
      command,
      args,
      workingDirectory: workingDirectory,
      environment: environment.isEmpty ? null : environment,
      mode: ProcessStartMode.normal,
    );
    unawaited(_server!.exitCode.then((code) {
      _serverExitCode = code;
      _finish();
    }));

    _maxTimer = Timer(maxRuntime, () {
      _timedOut = true;
      _recordEvent(
        direction: 'proxy',
        raw: 'max runtime reached',
        extra: <String, dynamic>{'maxRuntimeMs': maxRuntime.inMilliseconds},
      );
      _finish();
    });

    final clientLines = _clientLines ??
        stdin.transform(utf8.decoder).transform(const LineSplitter());
    _clientSubscription = clientLines.listen(
      (line) => _forwardClientToServer(line),
      onError: (Object error) {
        _recordEvent(
          direction: 'client_to_proxy',
          raw: '',
          extra: <String, dynamic>{'error': error.toString()},
        );
        _finish();
      },
      onDone: _finish,
      cancelOnError: false,
    );
    _serverSubscription = _server!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) => _forwardServerToClient(line),
      onError: (Object error) {
        _recordEvent(
          direction: 'server_to_proxy',
          raw: '',
          extra: <String, dynamic>{'error': error.toString()},
        );
        _finish();
      },
      onDone: _finish,
      cancelOnError: false,
    );
    _serverStderrSubscription = _server!.stderr.listen((data) {
      stderr.add(data);
      _recordEvent(
        direction: 'server_stderr',
        raw: utf8.decode(data, allowMalformed: true),
      );
    });

    await _done.future;
    await _clientSubscription?.cancel();
    await _serverSubscription?.cancel();
    await _serverStderrSubscription?.cancel();
    _maxTimer?.cancel();

    if (_serverExitCode == null) {
      _server?.kill();
      _serverExitCode = await _server?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    }
    await _stdoutWriteQueue;
    await _serverStdinWriteQueue;
    _stopwatch.stop();
    await _writeReport();
  }

  void _forwardClientToServer(String line) {
    _recordEvent(direction: 'client_to_server', raw: line);
    _serverStdinWriteQueue = _serverStdinWriteQueue.then((_) async {
      try {
        _server?.stdin.writeln(line);
        await _server?.stdin.flush();
      } catch (error) {
        _recordEvent(
          direction: 'proxy',
          raw: 'server stdin write failed',
          extra: <String, dynamic>{'error': error.toString()},
        );
        _finish();
      }
    });
  }

  void _forwardServerToClient(String line) {
    _recordEvent(direction: 'server_to_client', raw: line);
    _stdoutWriteQueue = _stdoutWriteQueue.then((_) async {
      try {
        stdout.writeln(line);
        await stdout.flush();
      } catch (error) {
        _recordEvent(
          direction: 'proxy',
          raw: 'client stdout write failed',
          extra: <String, dynamic>{'error': error.toString()},
        );
        _finish();
      }
    });
  }

  void _recordEvent({
    required String direction,
    required String raw,
    Map<String, dynamic>? extra,
  }) {
    final event = <String, dynamic>{
      'tMs': _stopwatch.elapsedMilliseconds,
      'direction': direction,
      'raw': raw,
      if (extra != null) ...extra,
    };
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty &&
        (direction == 'client_to_server' || direction == 'server_to_client')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          throw const FormatException('JSON-RPC frame must be an object.');
        }
        final json = decoded.cast<String, dynamic>();
        JsonRpcMessage.fromJson(json);
        event['message'] = json;
        final method = json['method'];
        if (method is String) {
          event['method'] = method;
          _methodCounts[method] = (_methodCounts[method] ?? 0) + 1;
        }
        if (json.containsKey('id')) event['id'] = json['id'];
      } catch (error) {
        _hadMalformedTraffic = true;
        event['parseError'] = error.toString();
      }
    }
    _events.add(event);
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> _writeReport() async {
    final report = <String, dynamic>{
      'kind': 'trace',
      'target': [command, ...args].join(' '),
      'durationMs': _stopwatch.elapsedMilliseconds,
      'serverExitCode': _serverExitCode,
      'passed': !failed,
      'summary': <String, dynamic>{
        'eventCount': _events.length,
        'malformedTraffic': _hadMalformedTraffic,
        'timedOut': _timedOut,
        'methods': _methodCounts,
      },
      'events': _events,
    };
    await reportFile.parent.create(recursive: true);
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    await reportFile.writeAsString(encoder.convert(report));
  }
}
