import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../../example/mcp_2026_07_28/server.dart' as strict_server;
import '../../example/streamable_https/client_streamable_https.dart'
    as streamable_example;

class _PreviewDiscoveryTransport extends Transport
    implements ProtocolVersionAwareTransport {
  bool closed = false;

  @override
  String? protocolVersion;

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (message is JsonRpcRequest && message.method == Method.serverDiscover) {
      onmessage?.call(
        JsonRpcResponse(
          id: message.id,
          result: const DiscoverResult(
            supportedVersions: [previewProtocolVersion],
            capabilities: ServerCapabilities(),
            serverInfo: Implementation(name: 'server', version: '1.0.0'),
            ttlMs: 0,
            cacheScope: CacheScope.private,
          ).toJson(),
        ),
      );
    }
  }

  @override
  Future<void> start() async {}
}

void main() {
  group('non-credentialed examples smoke tests', () {
    test('stdio client drives stdio server tools resources and prompts',
        () async {
      final result = await _runDart(['run', 'example/client_stdio.dart']);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Connected to server.'));
      expect(result.output, contains('Result: 15'));
      expect(result.output, contains('Sample log content'));
      expect(result.output, contains('Prompt result:'));
    });

    test('strict 2026 client completes an input_required retry', () async {
      final result = await _runDart([
        'run',
        'example/mcp_2026_07_28/client.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Negotiated protocol: 2026-07-28'));
      expect(result.output, contains('Subscription acknowledged:'));
      expect(result.output, contains('Subscription update:'));
      expect(result.output, contains('Subscription closed cleanly.'));
      expect(result.output, contains('Input requested:'));
      expect(result.output, contains('Structured result: Hello, Ada!'));
    });

    test('strict 2026 example rejects a mismatched MRTR response type', () {
      expect(
        () => strict_server.parseGreetingProfileResponse(
          InputResponse.fromResult(const ListRootsResult(roots: [])),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.invalidParams.value,
          ),
        ),
      );
    });

    test('Streamable HTTP example disconnects its stateless 2026 client',
        () async {
      final discoveryTransport = _PreviewDiscoveryTransport();
      final negotiatedClient = McpClient(
        const Implementation(name: 'client', version: '1.0.0'),
      );
      await negotiatedClient.connect(discoveryTransport);
      expect(negotiatedClient.getProtocolVersion(), previewProtocolVersion);

      streamable_example.client = negotiatedClient;
      streamable_example.transport = StreamableHttpClientTransport(
        Uri.parse('http://127.0.0.1:1/mcp'),
      );
      addTearDown(() async {
        await negotiatedClient.close();
        streamable_example.client = null;
        streamable_example.transport = null;
      });

      await streamable_example.disconnect();

      expect(discoveryTransport.closed, isTrue);
      expect(negotiatedClient.isConnected, isFalse);
      expect(streamable_example.client, isNull);
      expect(streamable_example.transport, isNull);
    });

    test(
      'browser server examples allow only documented CORS origins',
      () async {
        for (final script in [
          'example/simple_task_interactive_server.dart',
          'example/elicitation_http_server.dart',
        ]) {
          await _expectBrowserCorsPolicy(script);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('iostream example connects in process', () async {
      final result = await _runDart([
        'run',
        'example/iostream-client-server/simple.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Client setup complete.'));
      expect(result.output, contains('Available tools: (calculate)'));
    });

    test('required fields demo preserves schemas', () async {
      final result = await _runDart([
        'run',
        'example/required_fields_demo.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Required parameters: [operation, a, b]'));
      expect(result.output, contains('MCP server integration works!'));
    });

    test('CLI inspect invokes completions demo over stdio', () async {
      final result = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        '--tool',
        'echo',
        '--json-args',
        '{"message":"smoke"}',
        Platform.resolvedExecutable,
        'run',
        'example/completions_capability_demo.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('Connected to server!'));
      expect(result.output, contains('Echo: smoke'));
    });

    test('CLI inspect lists MCP Apps metadata server capabilities', () async {
      final result = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        Platform.resolvedExecutable,
        'run',
        'example/mcp_apps_metadata_server.dart',
      ]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('weather_get_current'));
      expect(result.output, contains('ui://weather/dashboard'));
      expect(result.output, contains('Prompts: (None)'));
      expect(result.output, isNot(contains('Failed to list capabilities')));
    });

    test('CLI inspect invokes MCP Apps helper server tool and resource',
        () async {
      final toolResult = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        '--tool',
        'weather_get_current',
        '--json-args',
        '{"location":"Seoul"}',
        Platform.resolvedExecutable,
        'run',
        'example/mcp_apps_helpers_server.dart',
      ]);

      expect(toolResult.exitCode, 0, reason: toolResult.output);
      expect(toolResult.output, contains('Current weather for Seoul'));
      expect(toolResult.output, contains('ui://weather/dashboard.html'));

      final resourceResult = await _runDart([
        'run',
        'packages/mcp_dart_cli/bin/mcp_dart.dart',
        'inspect',
        '--resource',
        'ui://weather/dashboard.html',
        Platform.resolvedExecutable,
        'run',
        'example/mcp_apps_helpers_server.dart',
      ]);

      expect(resourceResult.exitCode, 0, reason: resourceResult.output);
      expect(resourceResult.output, contains('MCP APP RESOURCE'));
      expect(resourceResult.output, contains('ui://weather/dashboard.html'));
    });
  });
}

Future<void> _expectBrowserCorsPolicy(String script) async {
  final portProbe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = portProbe.port;
  await portProbe.close(force: true);

  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', script],
    environment: {
      ...Platform.environment,
      'PORT': '$port',
      'MCP_ALLOWED_ORIGIN': 'http://localhost:8080',
    },
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  try {
    final allowed = await _preflight(
      port,
      origin: 'http://localhost:8080',
      retryConnection: true,
    );
    expect(allowed.statusCode, HttpStatus.noContent, reason: script);
    expect(
      allowed.allowOrigin,
      'http://localhost:8080',
      reason: script,
    );
    expect(
      allowed.allowHeaders?.toLowerCase(),
      contains('mcp-protocol-version'),
      reason: script,
    );

    final rejected = await _preflight(
      port,
      origin: 'https://untrusted.example',
    );
    expect(rejected.statusCode, HttpStatus.forbidden, reason: script);
    expect(rejected.allowOrigin, isNull, reason: script);
  } finally {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (!Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        }
        return -1;
      },
    );
    await stdoutFuture;
    await stderrFuture;
  }
}

Future<_PreflightResult> _preflight(
  int port, {
  required String origin,
  bool retryConnection = false,
}) async {
  final client = HttpClient();
  try {
    final attempts = retryConnection ? 50 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final request = await client.openUrl(
          'OPTIONS',
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        request.headers
          ..set('Origin', origin)
          ..set('Access-Control-Request-Method', 'POST')
          ..set(
            'Access-Control-Request-Headers',
            'content-type,mcp-protocol-version,mcp-session-id',
          );
        final response = await request.close();
        final result = _PreflightResult(
          statusCode: response.statusCode,
          allowOrigin: response.headers.value('Access-Control-Allow-Origin'),
          allowHeaders: response.headers.value('Access-Control-Allow-Headers'),
        );
        await response.drain<void>();
        return result;
      } on SocketException {
        if (attempt + 1 == attempts) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('CORS preflight did not run.');
  } finally {
    client.close(force: true);
  }
}

class _PreflightResult {
  final int statusCode;
  final String? allowOrigin;
  final String? allowHeaders;

  const _PreflightResult({
    required this.statusCode,
    required this.allowOrigin,
    required this.allowHeaders,
  });
}

Future<_CommandResult> _runDart(List<String> args) {
  return _runCommand(
    Platform.resolvedExecutable,
    args,
    timeout: const Duration(seconds: 30),
  );
}

Future<_CommandResult> _runCommand(
  String executable,
  List<String> args, {
  required Duration timeout,
}) async {
  final process = await Process.start(executable, args);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill();
    exitCode = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (Platform.isWindows) {
          process.kill();
        } else {
          process.kill(ProcessSignal.sigkill);
        }
        return -1;
      },
    );
    return _CommandResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: '${await stderrFuture}Timed out after $timeout',
    );
  }

  return _CommandResult(
    exitCode: exitCode,
    stdout: await stdoutFuture,
    stderr: await stderrFuture,
  );
}

class _CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  String get output => [
        if (stdout.isNotEmpty) stdout,
        if (stderr.isNotEmpty) stderr,
      ].join('\n');
}
