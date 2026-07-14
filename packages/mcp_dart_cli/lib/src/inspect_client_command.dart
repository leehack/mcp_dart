import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

import 'inspectors/inspection_report.dart';
import 'version.dart' as cli_version;

/// Runs a stdio MCP server harness that inspects the client connecting to it.
class InspectClientCommand extends Command<int> {
  /// Creates a client inspector command.
  InspectClientCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'report',
        help:
            'Path to write the JSON inspection report. Required because stdout is reserved for MCP.',
      )
      ..addOption(
        'idle-timeout-ms',
        defaultsTo: '1500',
        help:
            'Milliseconds to wait after the last client message before writing the report.',
      )
      ..addOption(
        'max-runtime-ms',
        defaultsTo: '30000',
        help: 'Maximum milliseconds to keep the inspector server running.',
      )
      ..addFlag(
        'active-probes',
        defaultsTo: false,
        negatable: false,
        help:
            'Actively call advertised legacy roots, sampling, and elicitation capabilities.',
      );
  }

  final Logger _logger;

  @override
  final String name = 'inspect-client';

  @override
  final String description =
      'Runs a stdio MCP test server that inspects a client or agent host.';

  @override
  String get invocation => 'mcp_dart inspect-client --report <path> [options]';

  @override
  Future<int> run() async {
    final reportPath = argResults?['report'] as String?;
    if (reportPath == null || reportPath.trim().isEmpty) {
      _logger.err('--report is required for inspect-client.');
      return ExitCode.usage.code;
    }

    final idleTimeout = _parseDurationOption('idle-timeout-ms');
    final maxRuntime = _parseDurationOption('max-runtime-ms');
    if (idleTimeout == null || maxRuntime == null) {
      return ExitCode.usage.code;
    }

    final harness = ClientInspectorHarness(
      reportFile: File(reportPath),
      idleTimeout: idleTimeout,
      maxRuntime: maxRuntime,
      activeProbes: argResults?['active-probes'] as bool? ?? false,
    );
    final report = await harness.run();
    return report.passed ? ExitCode.success.code : ExitCode.software.code;
  }

  Duration? _parseDurationOption(String name) {
    final value = int.tryParse(argResults?[name] as String? ?? '');
    if (value == null || value < 1) {
      _logger.err('--$name must be a positive integer.');
      return null;
    }
    return Duration(milliseconds: value);
  }
}

/// Stdio server harness used to inspect MCP clients.
class ClientInspectorHarness {
  static const Set<String> _statelessRemovedRequestMethods = <String>{
    Method.initialize,
    Method.ping,
    Method.loggingSetLevel,
    Method.resourcesSubscribe,
    Method.resourcesUnsubscribe,
    Method.tasksList,
    Method.tasksResult,
  };
  static const Set<String> _statelessRemovedNotificationMethods = <String>{
    Method.notificationsInitialized,
    Method.notificationsRootsListChanged,
    Method.notificationsTasksStatus,
  };

  /// Creates a client inspector harness.
  ClientInspectorHarness({
    required this.reportFile,
    required this.idleTimeout,
    required this.maxRuntime,
    this.activeProbes = false,
    Stream<String>? clientLines,
    FutureOr<void> Function(String line)? writeLine,
  }) : _clientLines = clientLines,
       _writeLine = writeLine;

  /// Report destination.
  final File reportFile;

  /// Idle timeout after the last message.
  final Duration idleTimeout;

  /// Maximum runtime for the harness.
  final Duration maxRuntime;

  /// Whether to call advertised legacy client capabilities.
  ///
  /// Disabled by default because roots may expose local paths, sampling may
  /// incur model cost, and elicitation may open user interface.
  final bool activeProbes;

  final Stream<String>? _clientLines;
  final FutureOr<void> Function(String line)? _writeLine;

  final InspectionCheckBuilder _checks = InspectionCheckBuilder();
  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  final Set<String> _observedMethods = <String>{};
  final Map<Object?, _ActiveProbe> _pendingActiveProbes =
      <Object?, _ActiveProbe>{};
  final List<Map<String, dynamic>> _activeProbeResults =
      <Map<String, dynamic>>[];
  final Stopwatch _stopwatch = Stopwatch();
  final Completer<void> _done = Completer<void>();
  Future<void> _stdoutWriteQueue = Future<void>.value();

  StreamSubscription<String>? _stdinSubscription;
  Timer? _idleTimer;
  Timer? _maxTimer;
  Map<String, dynamic>? _clientInfo;
  Map<String, dynamic>? _clientCapabilities;
  String? _clientProtocolVersion;
  String? _firstMethod;
  bool _sawAnyMessage = false;
  bool _sawDiscover = false;
  bool _sawInitialize = false;
  bool _sawInitialized = false;
  bool _operationBeforeInitialized = false;
  bool _malformedMessage = false;
  bool _sentActiveProbes = false;
  final List<String> _statelessMetadataErrors = <String>[];
  final Set<String> _statelessRemovedMethods = <String>{};
  int _nextActiveProbeId = 1000;

  /// Runs the harness until stdin closes or a timeout expires.
  Future<InspectionReport> run() async {
    _stopwatch.start();
    _maxTimer = Timer(maxRuntime, _finish);

    final clientLines =
        _clientLines ??
        stdin.transform(utf8.decoder).transform(const LineSplitter());
    _stdinSubscription = clientLines.listen(
      _handleLine,
      onError: (Object error) {
        _malformedMessage = true;
        _messages.add(<String, dynamic>{
          'direction': 'client_to_server',
          'error': 'stdin read error: $error',
        });
        _finish();
      },
      onDone: _finish,
      cancelOnError: false,
    );

    await _done.future;
    await _stdoutWriteQueue;
    await _stdinSubscription?.cancel();
    _idleTimer?.cancel();
    _maxTimer?.cancel();
    _stopwatch.stop();

    final report = _buildReport();
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    return report;
  }

  void _handleLine(String line) {
    _sawAnyMessage = true;
    _resetIdleTimer();

    if (line.trim().isEmpty) {
      _malformedMessage = true;
      _messages.add(<String, dynamic>{
        'direction': 'client_to_server',
        'error': 'empty stdio line',
      });
      return;
    }

    Map<String, dynamic> json;
    late JsonRpcMessage message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('JSON-RPC message must be an object.');
      }
      json = decoded.cast<String, dynamic>();
      message = JsonRpcMessage.fromJson(json);
    } catch (error) {
      _malformedMessage = true;
      _messages.add(<String, dynamic>{
        'direction': 'client_to_server',
        'error': 'malformed JSON-RPC: $error',
        'raw': line,
      });
      _sendError(null, ErrorCode.parseError.value, 'Invalid JSON-RPC message.');
      return;
    }

    final method = json['method'];
    if (method is String) {
      _observedMethods.add(method);
      _firstMethod ??= method;
    }
    _messages.add(<String, dynamic>{
      'direction': 'client_to_server',
      'message': json,
    });

    if (_sawInitialize &&
        !_sawInitialized &&
        method is String &&
        method != Method.notificationsInitialized) {
      _operationBeforeInitialized = true;
    }

    if (method == null && json.containsKey('id')) {
      _handleResponse(json);
    } else if (json.containsKey('id') && method is String) {
      _handleRequest(json, method, message as JsonRpcRequest);
    } else if (method is String) {
      _handleNotification(json, method);
    }
  }

  void _handleRequest(
    Map<String, dynamic> request,
    String method,
    JsonRpcRequest parsedRequest,
  ) {
    final id = request['id'];
    if (method == Method.initialize) {
      _sawInitialize = true;
    }
    if (_sawDiscover && method != Method.serverDiscover) {
      final metadataError = _validateStatelessRequestMetadata(parsedRequest);
      if (metadataError != null) {
        _recordStatelessMetadataError(method, metadataError);
        _sendError(
          id,
          metadataError.code,
          metadataError.message,
          data: metadataError.data,
        );
        return;
      }
      if (_statelessRemovedRequestMethods.contains(method)) {
        _statelessRemovedMethods.add(method);
        _sendError(
          id,
          ErrorCode.methodNotFound.value,
          '$method is not part of MCP stateless protocol versions.',
        );
        return;
      }
    }

    switch (method) {
      case Method.serverDiscover:
        _handleDiscover(parsedRequest);
        break;
      case Method.initialize:
        _handleInitialize(request);
        break;
      case Method.ping:
        _sendCompleteResult(id, const <String, dynamic>{});
        break;
      case Method.toolsList:
        _sendCompleteResult(id, _toolsListResult(), cacheable: true);
        break;
      case Method.toolsCall:
        _handleToolCall(id, request['params']);
        break;
      case Method.resourcesList:
        _sendCompleteResult(id, _resourcesListResult(), cacheable: true);
        break;
      case Method.resourcesTemplatesList:
        _sendCompleteResult(
          id,
          _resourceTemplatesListResult(),
          cacheable: true,
        );
        break;
      case Method.resourcesRead:
        _sendCompleteResult(
          id,
          _resourceReadResult(request['params']),
          cacheable: true,
        );
        break;
      case Method.promptsList:
        _sendCompleteResult(id, _promptsListResult(), cacheable: true);
        break;
      case Method.promptsGet:
        _sendCompleteResult(id, _promptGetResult(request['params']));
        break;
      default:
        _sendError(
          id,
          ErrorCode.methodNotFound.value,
          'Inspector harness does not implement $method.',
        );
    }
  }

  void _handleDiscover(JsonRpcRequest request) {
    final metadataError = _validateStatelessRequestMetadata(request);
    if (metadataError != null) {
      _recordStatelessMetadataError(Method.serverDiscover, metadataError);
      _sendError(
        request.id,
        metadataError.code,
        metadataError.message,
        data: metadataError.data,
      );
      return;
    }

    _sawDiscover = true;
    _captureStatelessClientMetadata(request.meta!);
    _sendResult(
      request.id,
      const DiscoverResult(
        supportedVersions: <String>[previewProtocolVersion],
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          resources: ServerCapabilitiesResources(),
          prompts: ServerCapabilitiesPrompts(),
        ),
        serverInfo: Implementation(
          name: 'mcp_dart_client_inspector',
          version: cli_version.packageVersion,
        ),
        instructions:
            'This is an MCP client inspector harness. Use tools/list and tools/call echo to exercise client behavior.',
        ttlMs: 0,
        cacheScope: CacheScope.private,
      ).toJson(),
    );
  }

  McpError? _validateStatelessRequestMetadata(JsonRpcRequest request) {
    final meta = request.meta;
    final requestedVersion = meta?[McpMetaKey.protocolVersion];
    if (requestedVersion is! String || requestedVersion.isEmpty) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Missing required request metadata: ${McpMetaKey.protocolVersion}',
      );
    }
    if (requestedVersion != previewProtocolVersion) {
      return McpError(
        ErrorCode.unsupportedProtocolVersion.value,
        'Unsupported protocol version',
        <String, dynamic>{
          'supported': const <String>[previewProtocolVersion],
          'requested': requestedVersion,
        },
      );
    }

    final clientInfo = meta?[McpMetaKey.clientInfo];
    if (clientInfo is! Map) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Missing required request metadata: ${McpMetaKey.clientInfo}',
      );
    }
    final clientCapabilities = meta?[McpMetaKey.clientCapabilities];
    if (clientCapabilities is! Map) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Missing required request metadata: '
        '${McpMetaKey.clientCapabilities}',
      );
    }

    try {
      Implementation.fromJson(clientInfo.cast<String, dynamic>());
      ClientCapabilities.fromJson(
        clientCapabilities.cast<String, dynamic>(),
      );
    } catch (error) {
      return McpError(
        ErrorCode.invalidParams.value,
        'Invalid stateless request metadata.',
        error.toString(),
      );
    }
    return null;
  }

  void _captureStatelessClientMetadata(Map<String, dynamic> meta) {
    _clientProtocolVersion = meta[McpMetaKey.protocolVersion] as String;
    _clientInfo = (meta[McpMetaKey.clientInfo] as Map).cast<String, dynamic>();
    _clientCapabilities =
        (meta[McpMetaKey.clientCapabilities] as Map).cast<String, dynamic>();
  }

  void _recordStatelessMetadataError(String method, McpError error) {
    if (error.code == ErrorCode.unsupportedProtocolVersion.value) {
      // Version rejection is part of modern negotiation. A conforming client
      // may retry with the supported version advertised by the harness.
      return;
    }
    _statelessMetadataErrors.add('$method: ${error.message}');
  }

  void _handleInitialize(Map<String, dynamic> request) {
    _sawInitialize = true;
    final params = request['params'];
    if (params is Map<String, dynamic>) {
      _clientProtocolVersion = params['protocolVersion'] as String?;
      _clientCapabilities =
          (params['capabilities'] as Map?)?.cast<String, dynamic>();
      _clientInfo = (params['clientInfo'] as Map?)?.cast<String, dynamic>();
    }

    _sendResult(request['id'], <String, dynamic>{
      'protocolVersion': _chooseProtocolVersion(_clientProtocolVersion),
      'capabilities': <String, dynamic>{
        'tools': <String, dynamic>{'listChanged': false},
        'resources': <String, dynamic>{},
        'prompts': <String, dynamic>{'listChanged': false},
      },
      'serverInfo': <String, dynamic>{
        'name': 'mcp_dart_client_inspector',
        'version': cli_version.packageVersion,
      },
      'instructions':
          'This is an MCP client inspector harness. Use tools/list and tools/call echo to exercise client behavior.',
    });
  }

  void _handleNotification(Map<String, dynamic> notification, String method) {
    if (_sawDiscover && _statelessRemovedNotificationMethods.contains(method)) {
      _statelessRemovedMethods.add(method);
    }
    if (method == Method.notificationsInitialized) {
      _sawInitialized = true;
      if (activeProbes) {
        _sendActiveProbes();
      }
    }
  }

  void _handleResponse(Map<String, dynamic> response) {
    final probe = _pendingActiveProbes.remove(response['id']);
    if (probe == null) return;

    _activeProbeResults.add(<String, dynamic>{
      'id': probe.id,
      'method': probe.method,
      if (response.containsKey('result')) 'result': response['result'],
      if (response.containsKey('error')) 'error': response['error'],
    });
  }

  void _sendActiveProbes() {
    if (_sentActiveProbes) return;
    _sentActiveProbes = true;

    if (_clientCapabilities == null) return;
    if (_clientCapabilities!.containsKey('roots')) {
      _sendProbe(
        'client.roots.list',
        Method.rootsList,
        const <String, dynamic>{},
      );
    }
    if (_clientCapabilities!.containsKey('sampling')) {
      _sendProbe(
        'client.sampling.create-message',
        Method.samplingCreateMessage,
        const <String, dynamic>{
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'role': 'user',
              'content': <String, dynamic>{
                'type': 'text',
                'text': 'MCP inspector sampling probe',
              },
            },
          ],
          'maxTokens': 1,
        },
      );
    }
    if (_clientCapabilities!.containsKey('elicitation')) {
      _sendProbe(
        'client.elicitation.create',
        Method.elicitationCreate,
        const <String, dynamic>{
          'mode': 'form',
          'message': 'MCP inspector elicitation probe',
          'requestedSchema': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'confirmed': <String, dynamic>{'type': 'boolean'},
            },
          },
        },
      );
    }
  }

  void _sendProbe(String id, String method, Map<String, dynamic> params) {
    final requestId = _nextActiveProbeId++;
    _pendingActiveProbes[requestId] = _ActiveProbe(id, method);
    _send(<String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': requestId,
      'method': method,
      if (params.isNotEmpty) 'params': params,
    });
  }

  void _handleToolCall(Object? id, Object? params) {
    final paramsMap = params is Map ? params.cast<String, dynamic>() : null;
    final name = paramsMap?['name'];
    if (name != 'echo') {
      _sendError(id, ErrorCode.invalidParams.value, 'Unknown tool: $name.');
      return;
    }

    final arguments = paramsMap?['arguments'];
    final argumentMap =
        arguments is Map ? arguments.cast<String, dynamic>() : null;
    final message = argumentMap?['message']?.toString() ?? '';
    _sendCompleteResult(id, <String, dynamic>{
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': message},
      ],
      'structuredContent': <String, dynamic>{'message': message},
      'isError': false,
    });
  }

  void _sendCompleteResult(
    Object? id,
    Map<String, dynamic> result, {
    bool cacheable = false,
  }) {
    if (!_sawDiscover) {
      _sendResult(id, result);
      return;
    }

    _sendResult(id, <String, dynamic>{
      'resultType': resultTypeComplete,
      ...result,
      if (cacheable) 'ttlMs': 0,
      if (cacheable) 'cacheScope': CacheScope.private,
    });
  }

  Map<String, dynamic> _toolsListResult() => <String, dynamic>{
    'tools': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'echo',
        'title': 'Echo',
        'description': 'Echoes a message so MCP clients can be inspected.',
        'inputSchema': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'message': <String, dynamic>{
              'type': 'string',
              'description': 'Message to echo.',
            },
          },
          'required': <String>['message'],
        },
        'outputSchema': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'message': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['message'],
        },
      },
    ],
  };

  Map<String, dynamic> _resourcesListResult() => <String, dynamic>{
    'resources': <Map<String, dynamic>>[
      <String, dynamic>{
        'uri': 'inspector://status',
        'name': 'Inspector Status',
        'description': 'A resource exposed by the MCP client inspector.',
        'mimeType': 'text/plain',
      },
    ],
  };

  Map<String, dynamic> _resourceTemplatesListResult() => <String, dynamic>{
    'resourceTemplates': <Map<String, dynamic>>[
      <String, dynamic>{
        'uriTemplate': 'inspector://echo/{message}',
        'name': 'Inspector Echo Resource',
        'description': 'Parameterized test resource for MCP clients.',
        'mimeType': 'text/plain',
      },
    ],
  };

  Map<String, dynamic> _resourceReadResult(Object? params) {
    final paramsMap = params is Map ? params.cast<String, dynamic>() : null;
    final uri = paramsMap?['uri']?.toString() ?? 'inspector://status';
    return <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'uri': uri,
          'mimeType': 'text/plain',
          'text': 'mcp_dart client inspector resource: $uri',
        },
      ],
    };
  }

  Map<String, dynamic> _promptsListResult() => <String, dynamic>{
    'prompts': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'inspector-summary',
        'title': 'Inspector Summary',
        'description': 'Prompt exposed by the MCP client inspector.',
        'arguments': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'topic',
            'description': 'Topic to summarize.',
            'required': false,
          },
        ],
      },
    ],
  };

  Map<String, dynamic> _promptGetResult(Object? params) {
    final paramsMap = params is Map ? params.cast<String, dynamic>() : null;
    final arguments = paramsMap?['arguments'];
    final argumentMap =
        arguments is Map ? arguments.cast<String, dynamic>() : null;
    final topic = argumentMap?['topic']?.toString() ?? 'MCP client behavior';
    return <String, dynamic>{
      'description': 'Inspector prompt for $topic.',
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <String, dynamic>{
            'type': 'text',
            'text': 'Summarize observed behavior for $topic.',
          },
        },
      ],
    };
  }

  String _chooseProtocolVersion(String? requested) {
    if (requested != null && legacyProtocolVersions.contains(requested)) {
      return requested;
    }
    return latestInitializationProtocolVersion;
  }

  void _sendResult(Object? id, Map<String, dynamic> result) {
    _send(<String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': id,
      'result': result,
    });
  }

  void _sendError(
    Object? id,
    int code,
    String message, {
    Object? data,
  }) {
    _send(<String, dynamic>{
      'jsonrpc': jsonRpcVersion,
      'id': id,
      'error': <String, dynamic>{
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
    });
  }

  void _send(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    _stdoutWriteQueue = _stdoutWriteQueue.then((_) async {
      try {
        final writeLine = _writeLine;
        if (writeLine == null) {
          stdout.writeln(encoded);
          await stdout.flush();
        } else {
          await writeLine(encoded);
        }
      } catch (error) {
        _messages.add(<String, dynamic>{
          'direction': 'server_to_client',
          'error': 'stdout write error: $error',
          'message': message,
        });
        _finish();
      }
    });
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _finish);
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  InspectionReport _buildReport() {
    _checks.pass(
      'transport.stdio',
      'Inspector ran over newline-delimited stdio.',
    );

    if (_sawAnyMessage) {
      _checks.pass('client.connected', 'Client sent MCP traffic.');
    } else {
      _checks.fail('client.connected', 'No MCP client traffic was observed.');
    }

    if (_malformedMessage) {
      _checks.fail(
        'jsonrpc.well-formed',
        'Client sent at least one malformed JSON-RPC message.',
      );
    } else if (_sawAnyMessage) {
      _checks.pass(
        'jsonrpc.well-formed',
        'All observed client messages were valid JSON-RPC envelopes.',
      );
    }

    if (_observedMethods.contains(Method.serverDiscover)) {
      _checkStatelessLifecycle();
    } else {
      _checkLegacyLifecycle();
    }

    _checkClientMetadata();
    _checkObservedOperations();
    _checkActiveProbes();

    return InspectionReport(
      kind: 'client',
      target: 'stdio client connection',
      metadata: <String, dynamic>{
        'durationMs': _stopwatch.elapsedMilliseconds,
        if (_clientProtocolVersion != null)
          'protocolVersion': _clientProtocolVersion,
        if (_clientInfo != null) 'clientInfo': _clientInfo,
        if (_clientCapabilities != null) 'capabilities': _clientCapabilities,
        'observedMethods': _observedMethods.toList()..sort(),
        'activeProbesEnabled': activeProbes,
        'activeProbes': _activeProbeResults,
      },
      inventory: <String, dynamic>{
        'serverHarness': <String, dynamic>{
          'tools': (_toolsListResult()['tools'] as List).cast<dynamic>(),
          'resources':
              (_resourcesListResult()['resources'] as List).cast<dynamic>(),
          'resourceTemplates':
              (_resourceTemplatesListResult()['resourceTemplates'] as List)
                  .cast<dynamic>(),
          'prompts': (_promptsListResult()['prompts'] as List).cast<dynamic>(),
        },
        'messages': _messages,
      },
      checks: _checks.checks,
    );
  }

  void _checkStatelessLifecycle() {
    if (_firstMethod == Method.serverDiscover) {
      _checks.pass(
        'lifecycle.discover-first',
        'Client sent server/discover before other MCP methods.',
      );
    } else {
      _checks.fail(
        'lifecycle.discover-first',
        'Client did not send server/discover as its first MCP method.',
      );
    }

    if (_sawDiscover) {
      _checks.pass(
        'lifecycle.discover',
        'Client completed the stateless server/discover handshake.',
      );
    } else {
      _checks.fail(
        'lifecycle.discover',
        'Client did not complete a valid server/discover handshake.',
      );
    }

    if (_sawInitialize) {
      _checks.fail(
        'lifecycle.stateless-no-initialize',
        'Client sent legacy initialize after entering stateless MCP.',
      );
    } else {
      _checks.pass(
        'lifecycle.stateless-no-initialize',
        'Client did not send legacy initialize in stateless MCP.',
      );
    }

    if (_sawInitialized) {
      _checks.fail(
        'lifecycle.stateless-no-initialized-notification',
        'Client sent removed notifications/initialized in stateless MCP.',
      );
    } else {
      _checks.pass(
        'lifecycle.stateless-no-initialized-notification',
        'Client did not send notifications/initialized in stateless MCP.',
      );
    }

    if (_statelessMetadataErrors.isEmpty && _sawDiscover) {
      _checks.pass(
        'lifecycle.stateless-request-metadata',
        'Client supplied required metadata on stateless requests.',
      );
    } else {
      _checks.fail(
        'lifecycle.stateless-request-metadata',
        'Client sent invalid stateless request metadata.',
        details: <String, dynamic>{'errors': _statelessMetadataErrors},
      );
    }

    if (_statelessRemovedMethods.isEmpty) {
      _checks.pass(
        'lifecycle.stateless-removed-methods',
        'Client did not send methods removed from stateless MCP.',
      );
    } else {
      _checks.fail(
        'lifecycle.stateless-removed-methods',
        'Client sent methods removed from stateless MCP.',
        details: <String, dynamic>{
          'methods': _statelessRemovedMethods.toList()..sort(),
        },
      );
    }
  }

  void _checkLegacyLifecycle() {
    if (_firstMethod == Method.initialize && _sawInitialize) {
      _checks.pass(
        'lifecycle.initialize-first',
        'Client sent initialize before other MCP methods.',
      );
    } else {
      _checks.fail(
        'lifecycle.initialize-first',
        'Client did not send initialize as its first MCP method.',
      );
    }

    if (!_sawInitialize) {
      _checks.fail('lifecycle.initialize', 'Client never sent initialize.');
      return;
    }

    if (_sawInitialized) {
      _checks.pass(
        'lifecycle.initialized-notification',
        'Client sent notifications/initialized after initialize.',
      );
    } else {
      _checks.fail(
        'lifecycle.initialized-notification',
        'Client did not send notifications/initialized before disconnecting.',
      );
    }

    if (_operationBeforeInitialized) {
      _checks.fail(
        'lifecycle.operation-after-initialized',
        'Client sent an operation before notifications/initialized.',
      );
    } else if (_sawInitialized) {
      _checks.pass(
        'lifecycle.operation-after-initialized',
        'Client waited for initialization before normal operations.',
      );
    }
  }

  void _checkClientMetadata() {
    final stateless = _observedMethods.contains(Method.serverDiscover);

    if (_clientProtocolVersion == null || _clientProtocolVersion!.isEmpty) {
      _checks.fail(
        'lifecycle.protocol-version',
        stateless
            ? 'server/discover request protocol metadata is missing.'
            : 'initialize.params.protocolVersion is missing.',
      );
    } else if (stateless && _clientProtocolVersion == previewProtocolVersion) {
      _checks.pass(
        'lifecycle.protocol-version',
        'Client requested supported stateless protocol version '
            '$_clientProtocolVersion.',
      );
    } else if (!stateless &&
        legacyProtocolVersions.contains(_clientProtocolVersion)) {
      _checks.pass(
        'lifecycle.protocol-version',
        'Client requested supported initialization protocol version '
            '$_clientProtocolVersion.',
      );
    } else {
      _checks.warning(
        'lifecycle.protocol-version',
        stateless
            ? 'Client requested unsupported stateless protocol version '
                '$_clientProtocolVersion.'
            : 'Client requested unsupported initialization protocol version '
                '$_clientProtocolVersion; inspector negotiated '
                '$latestInitializationProtocolVersion.',
      );
    }

    final name = _clientInfo?['name'];
    final version = _clientInfo?['version'];
    if (name is String &&
        name.trim().isNotEmpty &&
        version is String &&
        version.trim().isNotEmpty) {
      _checks.pass(
        'lifecycle.client-info',
        'Client provided implementation name and version.',
      );
    } else {
      _checks.fail(
        'lifecycle.client-info',
        stateless
            ? 'Stateless client metadata must include non-empty clientInfo name and version.'
            : 'initialize.params.clientInfo must include non-empty name and version.',
      );
    }

    if (_clientCapabilities != null) {
      _checks.pass(
        'lifecycle.client-capabilities',
        'Client provided a capabilities object.',
        details: _clientCapabilities,
      );
    } else {
      _checks.fail(
        'lifecycle.client-capabilities',
        stateless
            ? 'Stateless client capabilities metadata must be an object.'
            : 'initialize.params.capabilities must be an object.',
      );
    }
  }

  void _checkObservedOperations() {
    if (_observedMethods.contains(Method.toolsList)) {
      _checks.pass('tools.list', 'Client discovered tools.');
    } else {
      _checks.info(
        'tools.list',
        'Client did not call tools/list during the inspection window.',
      );
    }

    if (_observedMethods.contains(Method.toolsCall)) {
      _checks.pass('tools.call', 'Client called the echo tool.');
    } else {
      _checks.info(
        'tools.call',
        'Client did not call tools/call during the inspection window.',
      );
    }

    if (_observedMethods.contains(Method.resourcesList)) {
      _checks.pass('resources.list', 'Client discovered resources.');
    } else {
      _checks.info(
        'resources.list',
        'Client did not call resources/list during the inspection window.',
      );
    }

    if (_observedMethods.contains(Method.promptsList)) {
      _checks.pass('prompts.list', 'Client discovered prompts.');
    } else {
      _checks.info(
        'prompts.list',
        'Client did not call prompts/list during the inspection window.',
      );
    }
  }

  void _checkActiveProbes() {
    if (_sawDiscover) {
      _checkStatelessClientCapability(
        capability: 'roots',
        id: 'client.roots.list',
        label: 'roots/list',
      );
      _checkStatelessClientCapability(
        capability: 'sampling',
        id: 'client.sampling.create-message',
        label: 'sampling/createMessage',
      );
      _checkStatelessClientCapability(
        capability: 'elicitation',
        id: 'client.elicitation.create',
        label: 'elicitation/create',
      );
      return;
    }

    if (!activeProbes) {
      for (final entry in const <(String, String, String)>[
        ('roots', 'client.roots.list', 'roots/list'),
        (
          'sampling',
          'client.sampling.create-message',
          'sampling/createMessage',
        ),
        ('elicitation', 'client.elicitation.create', 'elicitation/create'),
      ]) {
        final (capability, id, label) = entry;
        if (_clientCapabilities?.containsKey(capability) ?? false) {
          _checks.info(
            id,
            'Client advertised $capability; active $label probing is disabled.',
          );
        } else {
          _checks.info(id, 'Client did not advertise $capability.');
        }
      }
      return;
    }

    _checkActiveProbe(
      capability: 'roots',
      id: 'client.roots.list',
      label: 'roots/list',
    );
    _checkActiveProbe(
      capability: 'sampling',
      id: 'client.sampling.create-message',
      label: 'sampling/createMessage',
    );
    _checkActiveProbe(
      capability: 'elicitation',
      id: 'client.elicitation.create',
      label: 'elicitation/create',
    );
  }

  void _checkStatelessClientCapability({
    required String capability,
    required String id,
    required String label,
  }) {
    if (_clientCapabilities?.containsKey(capability) ?? false) {
      _checks.info(
        id,
        'Client advertised $capability; stateless MCP carries $label through '
        'MRTR input requests instead of an active server-to-client probe.',
      );
    } else {
      _checks.info(id, 'Client did not advertise $capability.');
    }
  }

  void _checkActiveProbe({
    required String capability,
    required String id,
    required String label,
  }) {
    if (!(_clientCapabilities?.containsKey(capability) ?? false)) {
      _checks.info(id, 'Client did not advertise $capability.');
      return;
    }

    Map<String, dynamic>? result;
    for (final probeResult in _activeProbeResults) {
      if (probeResult['id'] == id) {
        result = probeResult;
        break;
      }
    }
    if (result == null) {
      _checks.fail(
        id,
        'Client advertised $capability but did not respond to $label.',
      );
      return;
    }
    if (result.containsKey('error')) {
      _checks.fail(
        id,
        'Client advertised $capability but returned an error for $label.',
        details: result,
      );
      return;
    }

    _checks.pass(id, 'Client handled active $label probe.', details: result);
  }
}

class _ActiveProbe {
  const _ActiveProbe(this.id, this.method);

  final String id;
  final String method;
}
