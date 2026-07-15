import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/client/streamable_https.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// A simple mock implementation of OAuthClientProvider for testing
class MockOAuthClientProvider implements OAuthClientProvider {
  final bool returnTokens;
  bool didRedirectToAuthorization = false;
  Function? redirectToAuthorizationCb;

  MockOAuthClientProvider({this.returnTokens = true});

  @override
  Future<OAuthTokens?> tokens() async {
    if (returnTokens) {
      return OAuthTokens(accessToken: 'test-access-token');
    }
    return null;
  }

  @override
  Future<void> redirectToAuthorization() async {
    if (redirectToAuthorizationCb != null) {
      redirectToAuthorizationCb!();
    } else {
      didRedirectToAuthorization = true;
    }
  }

  void registerRedirectToAuthorization(Function callback) {
    redirectToAuthorizationCb = callback;
  }
}

class _BlockingOAuthClientProvider implements OAuthClientProvider {
  final Completer<void> tokensRequested = Completer<void>();
  final Completer<void> releaseTokens = Completer<void>();

  @override
  Future<OAuthTokens?> tokens() async {
    if (!tokensRequested.isCompleted) {
      tokensRequested.complete();
    }
    await releaseTokens.future;
    return OAuthTokens(accessToken: 'test-access-token');
  }

  @override
  Future<void> redirectToAuthorization() async {}
}

class _BlockingRedirectOAuthClientProvider implements OAuthClientProvider {
  final Completer<void> redirectStarted = Completer<void>();
  final Completer<void> releaseRedirect = Completer<void>();

  @override
  Future<OAuthTokens?> tokens() async =>
      OAuthTokens(accessToken: 'test-access-token');

  @override
  Future<void> redirectToAuthorization() async {
    if (!redirectStarted.isCompleted) {
      redirectStarted.complete();
    }
    await releaseRedirect.future;
  }
}

class _CancellationTestProtocol extends Protocol {
  _CancellationTestProtocol() : super(const ProtocolOptions());

  @override
  void assertCapabilityForMethod(String method) {}

  @override
  void assertNotificationCapability(String method) {}

  @override
  void assertRequestHandlerCapability(String method) {}

  @override
  void assertTaskCapability(String method) {}

  @override
  void assertTaskHandlerCapability(String method) {}
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met within $timeout.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class DiscoveryOAuthClientProvider implements OAuthAuthorizationCodeProvider {
  @override
  final String clientId;

  @override
  final Uri redirectUri;

  @override
  final String? clientSecret;

  @override
  final List<String> scopes;

  OAuthTokens? storedTokens;
  Uri? authorizationUri;
  int legacyRedirects = 0;
  final Future<void> Function(Uri authorizationUri)? onAuthorizationUrl;
  final Future<void> Function(OAuthTokens tokens)? onSaveTokens;

  DiscoveryOAuthClientProvider({
    this.clientId = 'client-1',
    required this.redirectUri,
    this.clientSecret,
    this.scopes = const ['tools:read'],
    this.onAuthorizationUrl,
    this.onSaveTokens,
  });

  @override
  Future<OAuthTokens?> tokens() async => storedTokens;

  @override
  Future<void> redirectToAuthorization() async {
    legacyRedirects += 1;
  }

  @override
  Future<void> redirectToAuthorizationUrl(Uri authorizationUri) async {
    this.authorizationUri = authorizationUri;
    await onAuthorizationUrl?.call(authorizationUri);
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    await onSaveTokens?.call(tokens);
    storedTokens = tokens;
  }
}

Future<HttpServer> _startOAuthServerWithOmittedTokenAuthMetadata({
  Future<void> Function(HttpRequest request)? onTokenRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;

  server.listen((request) async {
    switch (request.uri.path) {
      case '/mcp':
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer resource_metadata="http://localhost:$port/.well-known/oauth-protected-resource/mcp"',
          );
        await request.response.close();
        break;
      case '/.well-known/oauth-protected-resource/mcp':
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'resource': 'http://localhost:$port/mcp',
              'authorization_servers': ['http://localhost:$port/auth'],
            }),
          );
        await request.response.close();
        break;
      case '/.well-known/oauth-authorization-server/auth':
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'issuer': 'http://localhost:$port/auth',
              'authorization_endpoint': 'http://localhost:$port/authorize',
              'token_endpoint': 'http://localhost:$port/token',
              'code_challenge_methods_supported': ['S256'],
            }),
          );
        await request.response.close();
        break;
      case '/token':
        final handler = onTokenRequest;
        if (handler == null) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } else {
          await handler(request);
        }
        break;
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  });

  return server;
}

Map<String, dynamic> _statelessMeta() => buildProtocolRequestMeta(
      protocolVersion: previewProtocolVersion,
      clientInfo: const Implementation(name: 'TestClient', version: '1.0.0'),
      clientCapabilities: const ClientCapabilities(),
    );

void main() {
  late HttpServer testServer;
  late int serverPort;
  late Uri serverUrl;
  final testSessionId = 'test-session-id';

  // Map to track active SSE connections by request hash
  final connections = <int, HttpResponse>{};
  final currentSseConnections = <HttpResponse>[];

  /// Set up the test HTTP server before all tests
  setUpAll(() async {
    try {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;
      serverUrl = Uri.parse('http://localhost:$serverPort/mcp');

      testServer.listen((request) async {
        final method = request.method;
        final path = request.uri.path;

        if (path == '/mcp') {
          if (method == 'GET') {
            // Handle SSE connection requests
            request.response.headers.add('Content-Type', 'text/event-stream');
            request.response.headers.add('Cache-Control', 'no-cache');
            request.response.headers.add('Connection', 'keep-alive');
            request.response.headers.add('mcp-session-id', testSessionId);

            // Critical for SSE: disable buffering and compression
            request.response.bufferOutput = false;
            request.response.headers.set('Content-Encoding', 'identity');

            // Keep the connection open by sending a comment right away
            request.response.write(': connected\n\n');
            await request.response.flush();
            print('SSE connection established with client');

            // Remember the response to send events later in tests
            currentSseConnections.add(request.response);

            // Initialize events map for this connection
            connections[request.hashCode] = request.response;

            // Don't close the response - it stays open for SSE
          } else if (method == 'POST') {
            // Handle message sending
            final requestBody = await utf8.decoder.bind(request).join();
            Map<String, dynamic> requestData;
            try {
              requestData = jsonDecode(requestBody);
            } catch (e) {
              request.response.statusCode = HttpStatus.badRequest;
              request.response.write('Invalid JSON');
              await request.response.close();
              return;
            }

            // Handle special test scenarios
            if (requestData['method'] == 'test/initialized') {
              // For initialization notification, return Accepted (202)
              request.response.statusCode = HttpStatus.accepted;
              request.response.headers.set('mcp-session-id', testSessionId);
              await request.response.close();
            } else if (requestData['id'] != null) {
              // For requests, return a response
              final id = requestData['id'];
              final response = JsonRpcResponse(
                id: id,
                result: {'success': true, 'echo': requestData['params']},
              );

              request.response.headers.contentType = ContentType.json;
              request.response.statusCode = HttpStatus.ok;
              request.response.headers.set('mcp-session-id', testSessionId);
              request.response.write(jsonEncode(response.toJson()));
              await request.response.close();
            } else {
              // For other notifications
              request.response.statusCode = HttpStatus.accepted;
              request.response.headers.set('mcp-session-id', testSessionId);
              await request.response.close();
            }
          } else if (method == 'DELETE') {
            // Handle session termination
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.methodNotAllowed;
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      print("FATAL: Failed to start test server: $e");
      fail("Failed to start test server: $e");
    }
  });

  /// Clean up resources after all tests complete
  tearDownAll(() async {
    print("Stopping test server...");
    for (final connection in connections.values) {
      await connection.close();
    }
    await testServer.close(force: true);
    print("Test server stopped.");
  });

  // Helper function to send an SSE event through the active connections

  group('StreamableHttpClientTransport', () {
    late StreamableHttpClientTransport transport;

    setUp(() {
      currentSseConnections.clear();
    });

    tearDown(() async {
      try {
        await transport.close();
      } catch (e) {
        // Ignore errors during teardown
      }
    });

    test('constructor initializes with default options', () {
      transport = StreamableHttpClientTransport(serverUrl);
      expect(transport, isNotNull);
    });

    test('constructor accepts custom options', () {
      final mockAuthProvider = MockOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: StreamableHttpClientTransportOptions(
          authProvider: mockAuthProvider,
          requestInit: {
            'headers': {'test-header': 'test-value'},
          },
          reconnectionOptions: const StreamableHttpReconnectionOptions(
            maxReconnectionDelay: 5000,
            initialReconnectionDelay: 500,
            reconnectionDelayGrowFactor: 2.0,
            maxRetries: 3,
          ),
          sessionId: 'custom-session-id',
        ),
      );
      expect(transport, isNotNull);
    });

    test('client discovery omits preconfigured session before fallback init',
        () async {
      final preconfiguredSessionId = 'preconfigured-session-id';
      final capturedSessionHeaders = <String?>[];
      final capturedRequests = <Map<String, dynamic>>[];
      var initializeCount = 0;
      var initializedNotificationCount = 0;

      final initServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => initServer.close(force: true));
      final initUrl = Uri.parse('http://localhost:${initServer.port}/mcp');

      initServer.listen((request) async {
        if (request.uri.path != '/mcp') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method == 'GET') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        capturedSessionHeaders.add(request.headers.value('mcp-session-id'));
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        capturedRequests.add(json);

        if (json['method'] == 'initialize') {
          initializeCount += 1;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers
              .set('mcp-session-id', preconfiguredSessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(
                id: json['id'],
                result: const InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: ServerCapabilities(
                    logging: {'supported': true},
                  ),
                  serverInfo: Implementation(
                    name: 'PreconfiguredSessionServer',
                    version: '1.0.0',
                  ),
                  instructions: 'Initialized with preconfigured session',
                ).toJson(),
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'notifications/initialized') {
          initializedNotificationCount += 1;
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers
              .set('mcp-session-id', preconfiguredSessionId);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(
        initUrl,
        opts: StreamableHttpClientTransportOptions(
          sessionId: preconfiguredSessionId,
        ),
      );

      await client.connect(transport);

      expect(initializeCount, 1);
      expect(initializedNotificationCount, 1);
      expect(capturedSessionHeaders, [
        null,
        preconfiguredSessionId,
        preconfiguredSessionId,
      ]);
      final discoverRequest = capturedRequests.first;
      expect(discoverRequest['method'], Method.serverDiscover);
      final discoverParams = discoverRequest['params'] as Map<String, dynamic>;
      final discoverMeta = discoverParams['_meta'] as Map<String, dynamic>;
      expect(
        discoverMeta[McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );
      expect(client.getServerCapabilities()?.logging, isNotNull);
      expect(client.getServerVersion()?.name, 'PreconfiguredSessionServer');
      expect(
        client.getInstructions(),
        'Initialized with preconfigured session',
      );
    });

    test('client does not fall back after a non-400 discovery response',
        () async {
      var initializeCount = 0;
      final errorServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => errorServer.close(force: true));
      final errorUrl = Uri.parse('http://localhost:${errorServer.port}/mcp');

      errorServer.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['method'] == Method.initialize) {
          initializeCount += 1;
        }

        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              JsonRpcError(
                id: json['id'],
                error: const JsonRpcErrorData(
                  code: -32099,
                  message: 'Temporary outage',
                ),
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(errorUrl);

      await expectLater(
        client.connect(transport),
        throwsA(
          isA<McpError>().having((error) => error.code, 'code', 0).having(
                (error) => error.message,
                'message',
                contains('HTTP 503'),
              ),
        ),
      );
      expect(initializeCount, 0);
    });

    test(
        'client connect retries initialization without stale session ID after 404',
        () async {
      const staleSessionId = 'stale-session-id';
      const newSessionId = 'new-session-id';
      final initializeSessionHeaders = <String?>[];
      final initializedSessionHeaders = <String?>[];
      var initializeCount = 0;
      var initializedNotificationCount = 0;

      final retryServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => retryServer.close(force: true));
      final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');

      retryServer.listen((request) async {
        if (request.uri.path != '/mcp') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final sessionHeader = request.headers.value('mcp-session-id');
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['method'] == 'initialize') {
          initializeSessionHeaders.add(sessionHeader);
          if (sessionHeader == staleSessionId) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Session not found');
            await request.response.close();
            return;
          }

          initializeCount += 1;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', newSessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(
                id: json['id'],
                result: const InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'RetrySessionServer',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'notifications/initialized') {
          initializedNotificationCount += 1;
          initializedSessionHeaders.add(sessionHeader);
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set('mcp-session-id', newSessionId);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(
        retryUrl,
        opts: const StreamableHttpClientTransportOptions(
          sessionId: staleSessionId,
        ),
      );

      await client.connect(transport);

      expect(initializeCount, 1);
      expect(initializedNotificationCount, 1);
      expect(initializeSessionHeaders, [staleSessionId, null]);
      expect(initializedSessionHeaders, [newSessionId]);
      expect(transport.sessionId, newSessionId);
      expect(client.getServerVersion()?.name, 'RetrySessionServer');
    });

    test('client request starts fresh session after stale session 404',
        () async {
      const initialSessionId = 'initial-session-id';
      const replacementSessionId = 'replacement-session-id';
      final initializeSessionHeaders = <String?>[];
      final initializedSessionHeaders = <String?>[];
      final pingSessionHeaders = <String?>[];
      var initializeCount = 0;
      var pingCount = 0;

      final retryServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => retryServer.close(force: true));
      final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');

      retryServer.listen((request) async {
        if (request.uri.path != '/mcp') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final sessionHeader = request.headers.value('mcp-session-id');
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['method'] == 'initialize') {
          initializeCount += 1;
          initializeSessionHeaders.add(sessionHeader);
          final sessionId =
              initializeCount == 1 ? initialSessionId : replacementSessionId;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', sessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(
                id: json['id'],
                result: InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: const ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'RetrySessionServer$initializeCount',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'notifications/initialized') {
          initializedSessionHeaders.add(sessionHeader);
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set(
            'mcp-session-id',
            initializeCount == 1 ? initialSessionId : replacementSessionId,
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'custom/ping') {
          pingCount += 1;
          pingSessionHeaders.add(sessionHeader);
          if (pingCount == 1) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Session not found');
            await request.response.close();
            return;
          }

          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', replacementSessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(id: json['id'], result: const {}).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(retryUrl);

      await client.connect(transport);
      final result = await client.request<EmptyResult>(
        const JsonRpcRequest(id: 123, method: 'custom/ping'),
        (_) => const EmptyResult(),
      );

      expect(result, isA<EmptyResult>());
      expect(initializeCount, 2);
      expect(pingCount, 2);
      expect(initializeSessionHeaders, [null, null]);
      expect(
        initializedSessionHeaders,
        [initialSessionId, replacementSessionId],
      );
      expect(pingSessionHeaders, [initialSessionId, replacementSessionId]);
      expect(transport.sessionId, replacementSessionId);
      expect(client.getServerVersion()?.name, 'RetrySessionServer2');
    });

    test('client stale session recovery retries original request only once',
        () async {
      const initialSessionId = 'initial-session-id';
      const replacementSessionId = 'replacement-session-id';
      final initializeSessionHeaders = <String?>[];
      final pingSessionHeaders = <String?>[];
      var initializeCount = 0;
      var initializedNotificationCount = 0;
      var pingCount = 0;

      final retryServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => retryServer.close(force: true));
      final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');

      retryServer.listen((request) async {
        if (request.uri.path != '/mcp') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final sessionHeader = request.headers.value('mcp-session-id');
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['method'] == 'initialize') {
          initializeCount += 1;
          initializeSessionHeaders.add(sessionHeader);
          final sessionId =
              initializeCount == 1 ? initialSessionId : replacementSessionId;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', sessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(
                id: json['id'],
                result: InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: const ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'RetrySessionServer$initializeCount',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'notifications/initialized') {
          initializedNotificationCount += 1;
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set(
            'mcp-session-id',
            initializeCount == 1 ? initialSessionId : replacementSessionId,
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'custom/ping') {
          pingCount += 1;
          pingSessionHeaders.add(sessionHeader);
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Session not found');
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(retryUrl);

      await client.connect(transport);
      await expectLater(
        client.request<EmptyResult>(
          const JsonRpcRequest(id: 124, method: 'custom/ping'),
          (_) => const EmptyResult(),
        ),
        throwsA(isA<StaleSessionError>()),
      );

      expect(initializeCount, 2);
      expect(initializedNotificationCount, 2);
      expect(pingCount, 2);
      expect(initializeSessionHeaders, [null, null]);
      expect(pingSessionHeaders, [initialSessionId, replacementSessionId]);
      expect(transport.sessionId, isNull);
      expect(client.getServerVersion()?.name, 'RetrySessionServer2');
    });

    test('concurrent stale session requests share one fresh session', () async {
      const initialSessionId = 'initial-session-id';
      const replacementSessionId = 'replacement-session-id';
      final initializeSessionHeaders = <String?>[];
      final initializedSessionHeaders = <String?>[];
      final pingSessionHeaders = <String?>[];
      final staleRequestsReceived = Completer<void>();
      var initializeCount = 0;
      var stalePingCount = 0;
      var successfulPingCount = 0;

      final retryServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => retryServer.close(force: true));
      final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');

      retryServer.listen((request) async {
        if (request.uri.path != '/mcp') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final sessionHeader = request.headers.value('mcp-session-id');
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['method'] == 'initialize') {
          initializeCount += 1;
          initializeSessionHeaders.add(sessionHeader);
          final sessionId =
              initializeCount == 1 ? initialSessionId : replacementSessionId;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', sessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(
                id: json['id'],
                result: InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: const ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'RetrySessionServer$initializeCount',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'notifications/initialized') {
          initializedSessionHeaders.add(sessionHeader);
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set(
            'mcp-session-id',
            initializeCount == 1 ? initialSessionId : replacementSessionId,
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'custom/ping') {
          pingSessionHeaders.add(sessionHeader);
          if (sessionHeader == initialSessionId) {
            stalePingCount += 1;
            if (stalePingCount == 2 && !staleRequestsReceived.isCompleted) {
              staleRequestsReceived.complete();
            }
            await staleRequestsReceived.future;
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Session not found');
            await request.response.close();
            return;
          }

          successfulPingCount += 1;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', replacementSessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(id: json['id'], result: const {}).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(retryUrl);

      await client.connect(transport);
      final results = await Future.wait([
        client.request<EmptyResult>(
          const JsonRpcRequest(id: 201, method: 'custom/ping'),
          (_) => const EmptyResult(),
        ),
        client.request<EmptyResult>(
          const JsonRpcRequest(id: 202, method: 'custom/ping'),
          (_) => const EmptyResult(),
        ),
      ]);

      expect(results, everyElement(isA<EmptyResult>()));
      expect(initializeCount, 2);
      expect(stalePingCount, 2);
      expect(successfulPingCount, 2);
      expect(initializeSessionHeaders, [null, null]);
      expect(
        initializedSessionHeaders,
        [initialSessionId, replacementSessionId],
      );
      expect(
        pingSessionHeaders,
        [
          initialSessionId,
          initialSessionId,
          replacementSessionId,
          replacementSessionId,
        ],
      );
      expect(transport.sessionId, replacementSessionId);
      expect(client.getServerVersion()?.name, 'RetrySessionServer2');
    });

    test('GET SSE stale session 404 stops reconnect and refreshes on request',
        () async {
      const initialSessionId = 'initial-session-id';
      const replacementSessionId = 'replacement-session-id';
      final getSessionHeaders = <String?>[];
      final initializeSessionHeaders = <String?>[];
      final initializedSessionHeaders = <String?>[];
      final pingSessionHeaders = <String?>[];
      final errors = <Error>[];
      final firstGetClosed = Completer<void>();
      final staleGetReceived = Completer<void>();
      var initializeCount = 0;
      var getCount = 0;
      var pingCount = 0;

      final retryServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => retryServer.close(force: true));
      final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');

      retryServer.listen((request) async {
        if (request.uri.path != '/mcp') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final sessionHeader = request.headers.value('mcp-session-id');

        if (request.method == 'GET') {
          getCount += 1;
          getSessionHeaders.add(sessionHeader);
          if (getCount == 1) {
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.set('mcp-session-id', initialSessionId);
            request.response.write('id: first\n');
            request.response.write(
              'data: {"jsonrpc":"2.0","method":"notifications/test"}\n\n',
            );
            await request.response.close();
            firstGetClosed.complete();
            return;
          }

          if (sessionHeader == replacementSessionId) {
            request.response.statusCode = HttpStatus.methodNotAllowed;
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Session not found');
          await request.response.close();
          if (!staleGetReceived.isCompleted) {
            staleGetReceived.complete();
          }
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['method'] == 'initialize') {
          initializeCount += 1;
          initializeSessionHeaders.add(sessionHeader);
          final sessionId =
              initializeCount == 1 ? initialSessionId : replacementSessionId;
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', sessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(
                id: json['id'],
                result: InitializeResult(
                  protocolVersion: latestInitializationProtocolVersion,
                  capabilities: const ServerCapabilities(),
                  serverInfo: Implementation(
                    name: 'RetrySessionServer$initializeCount',
                    version: '1.0.0',
                  ),
                ).toJson(),
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'notifications/initialized') {
          initializedSessionHeaders.add(sessionHeader);
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.set(
            'mcp-session-id',
            initializeCount == 1 ? initialSessionId : replacementSessionId,
          );
          await request.response.close();
          return;
        }

        if (json['method'] == 'custom/ping') {
          pingCount += 1;
          pingSessionHeaders.add(sessionHeader);
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('mcp-session-id', replacementSessionId);
          request.response.write(
            jsonEncode(
              JsonRpcResponse(id: json['id'], result: const {}).toJson(),
            ),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final client = McpClient(
        const Implementation(name: 'TestClient', version: '1.0.0'),
      );
      transport = StreamableHttpClientTransport(
        retryUrl,
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 3,
          ),
        ),
      );
      transport.onerror = errors.add;
      client.onerror = errors.add;

      await client.connect(transport);
      await firstGetClosed.future.timeout(const Duration(seconds: 5));
      await staleGetReceived.future.timeout(const Duration(seconds: 5));
      await Future.delayed(const Duration(milliseconds: 80));

      expect(getCount, 2);
      expect(getSessionHeaders, [initialSessionId, initialSessionId]);
      expect(transport.sessionId, isNull);
      expect(errors.whereType<StaleSessionError>(), hasLength(1));

      final result = await client.request<EmptyResult>(
        const JsonRpcRequest(id: 203, method: 'custom/ping'),
        (_) => const EmptyResult(),
      );

      expect(result, isA<EmptyResult>());
      expect(initializeCount, 2);
      expect(pingCount, 1);
      expect(initializeSessionHeaders, [null, null]);
      expect(
        initializedSessionHeaders,
        [initialSessionId, replacementSessionId],
      );
      expect(pingSessionHeaders, [replacementSessionId]);
      expect(transport.sessionId, replacementSessionId);
      expect(client.getServerVersion()?.name, 'RetrySessionServer2');
    });

    test('send reports retry failure only once after stale session 404',
        () async {
      const staleSessionId = 'stale-session-id';
      var requestCount = 0;
      final errors = <Error>[];

      final retryServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => retryServer.close(force: true));
      final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');

      retryServer.listen((request) async {
        requestCount += 1;
        await request.drain<void>();
        request.response.statusCode = requestCount == 1
            ? HttpStatus.notFound
            : HttpStatus.internalServerError;
        request.response.write(
          requestCount == 1 ? 'Session not found' : 'Retry failed',
        );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        retryUrl,
        opts: const StreamableHttpClientTransportOptions(
          sessionId: staleSessionId,
        ),
      );
      transport.onerror = errors.add;
      await transport.start();

      await expectLater(
        transport.send(
          JsonRpcRequest(
            id: 1,
            method: 'initialize',
            params: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
            ).toJson(),
          ),
        ),
        throwsA(isA<McpError>()),
      );

      expect(requestCount, 2);
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('Retry failed'));
      expect(transport.sessionId, isNull);
    });

    test('start initializes the transport', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();
      expect(transport, isNotNull);
    });

    test('send method sends a JsonRpcMessage', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      final request = const JsonRpcRequest(
        id: 123,
        method: 'test/method',
        params: {'data': 'test-data'},
      );

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        completer.complete(message);
      };

      await transport.send(request);

      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('No response received'),
      );

      expect(response, isA<JsonRpcResponse>());
      expect((response as JsonRpcResponse).id, equals(123));
      expect(response.result['success'], isTrue);
      expect(response.result['echo']['data'], equals('test-data'));
    });

    test('non-initialize responses cannot assign a session ID', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.set('mcp-session-id', 'unexpected-session')
          ..write(
            jsonEncode(
              const JsonRpcResponse(
                id: 1,
                result: {'ok': true},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      await transport.send(
        const JsonRpcRequest(id: 1, method: 'test/session'),
      );
      expect(transport.sessionId, isNull);
    });

    test('non-initialize responses cannot replace a session ID', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.set('mcp-session-id', 'replacement-session')
          ..write(
            jsonEncode(
              const JsonRpcResponse(
                id: 1,
                result: {'ok': true},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      await expectLater(
        transport.send(
          const JsonRpcRequest(id: 1, method: 'test/session'),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.invalidRequest.value,
          ),
        ),
      );
      expect(transport.sessionId, testSessionId);
    });

    test('send adds 2026 stateless HTTP metadata headers', () async {
      final capturedHeaders = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        capturedHeaders['protocolVersion'] =
            request.headers.value('mcp-protocol-version');
        capturedHeaders['method'] = request.headers.value('mcp-method');
        capturedHeaders['name'] = request.headers.value('mcp-name');
        capturedHeaders['session'] = request.headers.value('mcp-session-id');
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('mcp-session-id', 'ignored-stateless-session')
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              const JsonRpcResponse(
                id: 1,
                result: {'content': []},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {
              'Mcp-Session-Id': 'custom-session',
            },
          },
          sessionId: 'legacy-session',
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = completer.complete;

      await transport.send(
        JsonRpcCallToolRequest(
          id: 1,
          params: const {
            'name': 'echo',
            'arguments': {'message': 'hello'},
          },
          meta: _statelessMeta(),
        ),
      );
      await completer.future.timeout(const Duration(seconds: 5));

      expect(
        capturedHeaders['protocolVersion'],
        previewProtocolVersion,
      );
      expect(capturedHeaders['method'], Method.toolsCall);
      expect(capturedHeaders['name'], 'echo');
      expect(capturedHeaders['session'], isNull);
      expect(transport.sessionId, 'legacy-session');
    });

    test('stateless cancellation before headers sends no HTTP request',
        () async {
      var postRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              const JsonRpcResponse(id: 0, result: {}).toJson(),
            ),
          );
        await request.response.close();
      });

      final authProvider = _BlockingOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      final transportErrors = <Error>[];
      transport.onerror = transportErrors.add;
      final protocol = _CancellationTestProtocol();
      addTearDown(protocol.close);
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final requestFuture = protocol.request<EmptyResult>(
        JsonRpcRequest(
          id: -1,
          method: 'test/before-headers',
          meta: _statelessMeta(),
        ),
        EmptyResult.fromJson,
        RequestOptions(
          signal: controller.signal,
          timeoutEnabled: false,
        ),
      );

      await authProvider.tokensRequested.future.timeout(
        const Duration(seconds: 5),
      );
      controller.abort('cancel before headers');
      await expectLater(
        requestFuture,
        throwsA(
          predicate<Object?>(
            (error) => error.toString().contains('cancel before headers'),
          ),
        ),
      );

      await _waitUntil(() => !transport.canCancelRequest(0));
      expect(authProvider.releaseTokens.isCompleted, isFalse);
      expect(postRequests, 0);

      authProvider.releaseTokens.completeError(
        StateError('late token lookup failure'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transportErrors, isEmpty);
    });

    test('close interrupts stateless request while OAuth tokens never return',
        () async {
      var postRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              const JsonRpcResponse(id: 17, result: {}).toJson(),
            ),
          );
        await request.response.close();
      });

      final authProvider = _BlockingOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(
          JsonRpcRequest(
            id: 17,
            method: 'test/close-before-headers',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await authProvider.tokensRequested.future.timeout(
        const Duration(seconds: 5),
      );

      await transport.close().timeout(const Duration(seconds: 5));
      await sendExpectation.timeout(const Duration(seconds: 5));
      await _waitUntil(() => !transport.canCancelRequest(17));

      expect(authProvider.releaseTokens.isCompleted, isFalse);
      expect(postRequests, 0);
    });

    test('stateless cancellation interrupts an open 401 response body',
        () async {
      var postRequests = 0;
      final challengeStarted = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..bufferOutput = false
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer realm="test"',
          )
          ..write('challenge body remains open');
        await request.response.flush();
        if (!challengeStarted.isCompleted) {
          challengeStarted.complete();
        }
        try {
          await request.response.done;
        } catch (_) {
          // Request cancellation closes the challenge response stream.
        }
      });

      final authProvider = MockOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      final transportErrors = <Error>[];
      transport.onerror = transportErrors.add;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(
          JsonRpcRequest(
            id: 18,
            method: 'test/cancel-401-body',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(isA<http.RequestAbortedException>()),
      );
      await challengeStarted.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      await transport.cancelRequest(18);
      await sendExpectation.timeout(const Duration(seconds: 5));
      await _waitUntil(() => !transport.canCancelRequest(18));

      expect(postRequests, 1);
      expect(authProvider.didRedirectToAuthorization, isFalse);
      expect(transportErrors, isEmpty);
    });

    test('stateless cancellation aborts a hanging OAuth discovery request',
        () async {
      var mcpRequests = 0;
      var metadataRequests = 0;
      final metadataStarted = Completer<void>();
      final releaseMetadata = Completer<void>();
      final metadataFinished = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseMetadata.isCompleted) {
          releaseMetadata.complete();
        }
      });
      final port = server.port;
      server.listen((request) async {
        switch (request.uri.path) {
          case '/mcp':
            mcpRequests += 1;
            await request.drain<void>();
            request.response
              ..statusCode = HttpStatus.unauthorized
              ..headers.set(
                HttpHeaders.wwwAuthenticateHeader,
                'Bearer resource_metadata="http://localhost:$port/metadata"',
              );
            await request.response.close();
            break;
          case '/metadata':
            metadataRequests += 1;
            request.response
              ..statusCode = HttpStatus.ok
              ..bufferOutput = false
              ..headers.contentType = ContentType.json
              ..write('{"resource":');
            await request.response.flush();
            if (!metadataStarted.isCompleted) {
              metadataStarted.complete();
            }
            await releaseMetadata.future;
            try {
              request.response.write(
                '"http://localhost:$port/mcp",'
                '"authorization_servers":[]}',
              );
              await request.response.close();
            } catch (_) {
              // The guarded OAuth request is aborted with its MCP request.
            } finally {
              if (!metadataFinished.isCompleted) {
                metadataFinished.complete();
              }
            }
            break;
          default:
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
        }
      });

      final authProvider = DiscoveryOAuthClientProvider(
        redirectUri: Uri.parse('http://localhost/callback'),
      );
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:$port/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      final transportErrors = <Error>[];
      transport.onerror = transportErrors.add;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(
          JsonRpcRequest(
            id: 19,
            method: 'test/cancel-oauth-discovery',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(isA<http.RequestAbortedException>()),
      );
      await metadataStarted.future.timeout(const Duration(seconds: 5));

      await transport.cancelRequest(19);
      await sendExpectation.timeout(const Duration(seconds: 5));
      await _waitUntil(() => !transport.canCancelRequest(19));

      expect(mcpRequests, 1);
      expect(metadataRequests, 1);
      expect(authProvider.authorizationUri, isNull);
      expect(transportErrors, isEmpty);

      releaseMetadata.complete();
      await metadataFinished.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(authProvider.authorizationUri, isNull);
      expect(transportErrors, isEmpty);
    });

    test('close interrupts a request blocked in the 401 redirect callback',
        () async {
      var postRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer realm="test"',
          );
        await request.response.close();
      });

      final authProvider = _BlockingRedirectOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(
          JsonRpcRequest(
            id: 20,
            method: 'test/close-oauth-redirect',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await authProvider.redirectStarted.future.timeout(
        const Duration(seconds: 5),
      );

      await transport.close().timeout(const Duration(seconds: 5));
      await sendExpectation.timeout(const Duration(seconds: 5));
      await _waitUntil(() => !transport.canCancelRequest(20));

      expect(authProvider.releaseRedirect.isCompleted, isFalse);
      expect(postRequests, 1);
    });

    test('concurrent cancelled OAuth redirects do not resurrect pending state',
        () async {
      final server = await _startOAuthServerWithOmittedTokenAuthMetadata();
      addTearDown(() => server.close(force: true));
      final redirectStarted = Completer<void>();
      final redirectReleases = [Completer<void>(), Completer<void>()];
      final redirectUris = <Uri>[];
      final authProvider = DiscoveryOAuthClientProvider(
        clientSecret: 'test-secret',
        redirectUri: Uri.parse('http://localhost/callback'),
        onAuthorizationUrl: (authorizationUri) async {
          final index = redirectUris.length;
          redirectUris.add(authorizationUri);
          if (redirectUris.length == 2 && !redirectStarted.isCompleted) {
            redirectStarted.complete();
          }
          await redirectReleases[index].future;
        },
      );
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      Future<void> startRequest(int id) => expectLater(
            transport.send(
              JsonRpcRequest(
                id: id,
                method: 'test/concurrent-oauth-$id',
                meta: _statelessMeta(),
              ),
            ),
            throwsA(isA<http.RequestAbortedException>()),
          );

      final firstRequest = startRequest(21);
      await _waitUntil(() => redirectUris.length == 1);
      final secondRequest = startRequest(22);
      await redirectStarted.future.timeout(const Duration(seconds: 5));

      await transport.cancelRequest(21);
      await firstRequest.timeout(const Duration(seconds: 5));
      await transport.cancelRequest(22);
      await secondRequest.timeout(const Duration(seconds: 5));
      await _waitUntil(
        () =>
            !transport.canCancelRequest(21) && !transport.canCancelRequest(22),
      );

      // With no live pending flow this follows the compatibility auth path.
      // A stale A or B pending flow would instead reject the missing state.
      await transport.finishAuth('unused-code');

      for (final release in redirectReleases) {
        release.complete();
      }
      await Future<void>.delayed(Duration.zero);
      await transport.finishAuth('unused-code');
    });

    test('redirect callback can finish authorization before returning',
        () async {
      var tokenRequests = 0;
      final server = await _startOAuthServerWithOmittedTokenAuthMetadata(
        onTokenRequest: (request) async {
          tokenRequests += 1;
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'access_token': 'reentrant-token'}));
          await request.response.close();
        },
      );
      addTearDown(() => server.close(force: true));
      late StreamableHttpClientTransport oauthTransport;
      late DiscoveryOAuthClientProvider authProvider;
      authProvider = DiscoveryOAuthClientProvider(
        clientSecret: 'test-secret',
        redirectUri: Uri.parse('http://localhost/callback'),
        onAuthorizationUrl: (authorizationUri) async {
          await oauthTransport.finishAuth(
            'reentrant-code',
            state: authorizationUri.queryParameters['state'],
          );
        },
      );
      oauthTransport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      transport = oauthTransport;
      await transport.start();

      await expectLater(
        transport.send(
          JsonRpcRequest(
            id: 23,
            method: 'test/reentrant-finish-auth',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(isA<UnauthorizedError>()),
      );

      expect(tokenRequests, 1);
      expect(authProvider.storedTokens?.accessToken, 'reentrant-token');
    });

    test('close interrupts finishAuth while token response remains open',
        () async {
      final tokenStarted = Completer<void>();
      final releaseToken = Completer<void>();
      final tokenFinished = Completer<void>();
      final server = await _startOAuthServerWithOmittedTokenAuthMetadata(
        onTokenRequest: (request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.ok
            ..bufferOutput = false
            ..headers.contentType = ContentType.json
            ..write('{"access_token":');
          await request.response.flush();
          if (!tokenStarted.isCompleted) {
            tokenStarted.complete();
          }
          await releaseToken.future;
          try {
            request.response.write('"late-token"}');
            await request.response.close();
          } catch (_) {
            // Closing the transport aborts the token response body.
          } finally {
            if (!tokenFinished.isCompleted) {
              tokenFinished.complete();
            }
          }
        },
      );
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseToken.isCompleted) {
          releaseToken.complete();
        }
      });
      final authProvider = DiscoveryOAuthClientProvider(
        clientSecret: 'test-secret',
        redirectUri: Uri.parse('http://localhost/callback'),
      );
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();
      await expectLater(
        transport.send(
          JsonRpcRequest(
            id: 24,
            method: 'test/prepare-token-close',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(isA<UnauthorizedError>()),
      );
      final authorizationUri = authProvider.authorizationUri!;

      final finishExpectation = expectLater(
        transport.finishAuth(
          'blocked-token-code',
          state: authorizationUri.queryParameters['state'],
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await tokenStarted.future.timeout(const Duration(seconds: 5));

      await transport.close().timeout(const Duration(seconds: 5));
      await finishExpectation.timeout(const Duration(seconds: 5));
      expect(releaseToken.isCompleted, isFalse);
      expect(authProvider.storedTokens, isNull);

      releaseToken.complete();
      await tokenFinished.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(authProvider.storedTokens, isNull);
    });

    test('close interrupts finishAuth while saveTokens never returns',
        () async {
      final saveStarted = Completer<void>();
      final releaseSave = Completer<void>();
      final server = await _startOAuthServerWithOmittedTokenAuthMetadata(
        onTokenRequest: (request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'access_token': 'unsaved-token'}));
          await request.response.close();
        },
      );
      addTearDown(() => server.close(force: true));
      final authProvider = DiscoveryOAuthClientProvider(
        clientSecret: 'test-secret',
        redirectUri: Uri.parse('http://localhost/callback'),
        onSaveTokens: (_) async {
          if (!saveStarted.isCompleted) {
            saveStarted.complete();
          }
          await releaseSave.future;
        },
      );
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();
      await expectLater(
        transport.send(
          JsonRpcRequest(
            id: 25,
            method: 'test/prepare-save-close',
            meta: _statelessMeta(),
          ),
        ),
        throwsA(isA<UnauthorizedError>()),
      );
      final authorizationUri = authProvider.authorizationUri!;

      final finishExpectation = expectLater(
        transport.finishAuth(
          'blocked-save-code',
          state: authorizationUri.queryParameters['state'],
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await saveStarted.future.timeout(const Duration(seconds: 5));

      await transport.close().timeout(const Duration(seconds: 5));
      await finishExpectation.timeout(const Duration(seconds: 5));
      expect(releaseSave.isCompleted, isFalse);
      expect(authProvider.storedTokens, isNull);

      releaseSave.completeError(StateError('late save failure'));
      await Future<void>.delayed(Duration.zero);
      expect(authProvider.storedTokens, isNull);
    });

    test('close interrupts legacy GET before OAuth tokens return', () async {
      var getRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
        }
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });

      final authProvider = _BlockingOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      final sendExpectation = expectLater(
        transport.send(
          const JsonRpcRequest(id: 26, method: 'test/resume-blocked-token'),
          resumptionToken: 'cursor-26',
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await authProvider.tokensRequested.future.timeout(
        const Duration(seconds: 5),
      );

      await transport.close().timeout(const Duration(seconds: 5));
      await sendExpectation.timeout(const Duration(seconds: 5));

      expect(authProvider.releaseTokens.isCompleted, isFalse);
      expect(getRequests, 0);
    });

    test('close interrupts legacy GET blocked in 401 redirect', () async {
      var getRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
        }
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer realm="test"',
          );
        await request.response.close();
      });

      final authProvider = _BlockingRedirectOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      final sendExpectation = expectLater(
        transport.send(
          const JsonRpcRequest(id: 27, method: 'test/resume-blocked-redirect'),
          resumptionToken: 'cursor-27',
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await authProvider.redirectStarted.future.timeout(
        const Duration(seconds: 5),
      );

      await transport.close().timeout(const Duration(seconds: 5));
      await sendExpectation.timeout(const Duration(seconds: 5));

      expect(authProvider.releaseRedirect.isCompleted, isFalse);
      expect(getRequests, 1);
    });

    test('close interrupts DELETE before OAuth tokens return', () async {
      var deleteRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'DELETE') {
          deleteRequests += 1;
        }
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      final authProvider = _BlockingOAuthClientProvider();
      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          authProvider: authProvider,
          sessionId: 'delete-session',
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      final terminationExpectation = expectLater(
        transport.terminateSession(),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await authProvider.tokensRequested.future.timeout(
        const Duration(seconds: 5),
      );

      await transport.close().timeout(const Duration(seconds: 5));
      await terminationExpectation.timeout(const Duration(seconds: 5));

      expect(authProvider.releaseTokens.isCompleted, isFalse);
      expect(deleteRequests, 0);
    });

    test('close interrupts DELETE while its response body remains open',
        () async {
      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      final serverFinished = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseDelete.isCompleted) {
          releaseDelete.complete();
        }
      });
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..bufferOutput = false
          ..write('open delete response');
        await request.response.flush();
        if (!deleteStarted.isCompleted) {
          deleteStarted.complete();
        }
        await releaseDelete.future;
        try {
          await request.response.close();
        } catch (_) {
          // Closing the transport aborts the DELETE response body.
        } finally {
          if (!serverFinished.isCompleted) {
            serverFinished.complete();
          }
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          sessionId: 'delete-body-session',
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      final terminationExpectation = expectLater(
        transport.terminateSession(),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await deleteStarted.future.timeout(const Duration(seconds: 5));

      await transport.close().timeout(const Duration(seconds: 5));
      await terminationExpectation.timeout(const Duration(seconds: 5));
      expect(releaseDelete.isCompleted, isFalse);

      releaseDelete.complete();
      await serverFinished.future.timeout(const Duration(seconds: 5));
    });

    test(
        'stateless SSE cancellation preserves a concurrent request and recovery',
        () async {
      var postRequests = 0;
      var cancellationNotifications = 0;
      final slowStreamReady = Completer<void>();
      final progressReceived = Completer<void>();
      final allowLateFrames = Completer<void>();
      final lateFramesAttempted = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['method'] == Method.notificationsCancelled) {
          cancellationNotifications += 1;
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }

        if (body['method'] == 'test/slow') {
          final params = body['params'] as Map<String, dynamic>;
          final meta = params['_meta'] as Map<String, dynamic>;
          final progressToken = meta['progressToken']!;
          request.response
            ..statusCode = HttpStatus.ok
            ..bufferOutput = false
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write(
              'data: ${jsonEncode(
                JsonRpcProgressNotification(
                  progressParams: ProgressNotification(
                    progressToken: progressToken,
                    progress: 1,
                  ),
                ).toJson(),
              )}\n\n',
            );
          await request.response.flush();
          if (!slowStreamReady.isCompleted) {
            slowStreamReady.complete();
          }
          await allowLateFrames.future;
          try {
            request.response
              ..write(
                'data: ${jsonEncode(
                  JsonRpcProgressNotification(
                    progressParams: ProgressNotification(
                      progressToken: progressToken,
                      progress: 2,
                    ),
                  ).toJson(),
                )}\n\n',
              )
              ..write(
                'data: ${jsonEncode(
                  JsonRpcResponse(
                    id: body['id'] as int,
                    result: const {'resultType': resultTypeComplete},
                  ).toJson(),
                )}\n\n',
              );
            await request.response.close();
          } catch (_) {
            // The cancelled response may already be closed by the client.
          } finally {
            if (!lateFramesAttempted.isCompleted) {
              lateFramesAttempted.complete();
            }
          }
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              JsonRpcResponse(
                id: body['id'] as int,
                result: const {'resultType': resultTypeComplete},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      final transportErrors = <Error>[];
      transport.onerror = transportErrors.add;
      final protocol = _CancellationTestProtocol();
      addTearDown(protocol.close);
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final progressUpdates = <num>[];
      final slowRequest = protocol.request<EmptyResult>(
        JsonRpcRequest(
          id: -1,
          method: 'test/slow',
          meta: _statelessMeta(),
        ),
        EmptyResult.fromJson,
        RequestOptions(
          signal: controller.signal,
          timeoutEnabled: false,
          onprogress: (progress) {
            progressUpdates.add(progress.progress);
            if (!progressReceived.isCompleted) {
              progressReceived.complete();
            }
          },
        ),
      );
      await slowStreamReady.future.timeout(const Duration(seconds: 5));
      await progressReceived.future.timeout(const Duration(seconds: 5));
      expect(progressUpdates, [1]);

      final sibling = await protocol
          .request<EmptyResult>(
            JsonRpcRequest(
              id: -1,
              method: 'test/sibling',
              meta: _statelessMeta(),
            ),
            EmptyResult.fromJson,
            const RequestOptions(timeout: Duration(seconds: 5)),
          )
          .timeout(const Duration(seconds: 5));
      expect(sibling, isA<EmptyResult>());

      controller.abort('cancel SSE request');
      await expectLater(
        slowRequest,
        throwsA(
          predicate<Object?>(
            (error) => error.toString().contains('cancel SSE request'),
          ),
        ),
      );
      await _waitUntil(() => !transport.canCancelRequest(0));
      allowLateFrames.complete();
      await lateFramesAttempted.future.timeout(const Duration(seconds: 5));

      final recovered = await protocol
          .request<EmptyResult>(
            JsonRpcRequest(
              id: -1,
              method: 'test/recovered',
              meta: _statelessMeta(),
            ),
            EmptyResult.fromJson,
            const RequestOptions(timeout: Duration(seconds: 5)),
          )
          .timeout(const Duration(seconds: 5));
      expect(recovered, isA<EmptyResult>());
      expect(postRequests, 3);
      expect(cancellationNotifications, 0);
      expect(transportErrors, isEmpty);
      expect(progressUpdates, [1]);
    });

    test('stateless timeout aborts its active SSE response stream', () async {
      var postRequests = 0;
      var cancellationNotifications = 0;
      final progressReceived = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['method'] == Method.notificationsCancelled) {
          cancellationNotifications += 1;
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }

        final params = body['params'] as Map<String, dynamic>;
        final meta = params['_meta'] as Map<String, dynamic>;
        final progressToken = meta['progressToken']!;
        request.response
          ..statusCode = HttpStatus.ok
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'data: ${jsonEncode(
              JsonRpcProgressNotification(
                progressParams: ProgressNotification(
                  progressToken: progressToken,
                  progress: 1,
                ),
              ).toJson(),
            )}\n\n',
          );
        await request.response.flush();
        try {
          await request.response.done;
        } catch (_) {
          // The request timeout closes this response stream.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      final transportErrors = <Error>[];
      transport.onerror = transportErrors.add;
      final protocol = _CancellationTestProtocol();
      addTearDown(protocol.close);
      await protocol.connect(transport);

      final request = protocol.request<EmptyResult>(
        JsonRpcRequest(
          id: -1,
          method: 'test/timeout',
          meta: _statelessMeta(),
        ),
        EmptyResult.fromJson,
        RequestOptions(
          timeout: const Duration(milliseconds: 250),
          resetTimeoutOnProgress: true,
          onprogress: (_) {
            if (!progressReceived.isCompleted) {
              progressReceived.complete();
            }
          },
        ),
      );
      await progressReceived.future.timeout(const Duration(seconds: 5));

      await expectLater(
        request,
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.requestTimeout.value,
          ),
        ),
      );
      await _waitUntil(() => !transport.canCancelRequest(0));
      expect(postRequests, 1);
      expect(cancellationNotifications, 0);
      expect(transportErrors, isEmpty);
    });

    test('stateless subscription cancellation closes only its listen POST',
        () async {
      final observedMethods = <String>[];
      var cancellationNotifications = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        final method = body['method'] as String;
        observedMethods.add(method);

        if (method == Method.notificationsCancelled) {
          cancellationNotifications += 1;
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }

        if (method == Method.serverDiscover) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                JsonRpcResponse(
                  id: body['id'] as int,
                  result: const DiscoverResult(
                    supportedVersions: [previewProtocolVersion],
                    capabilities: ServerCapabilities(
                      tools: ServerCapabilitiesTools(listChanged: true),
                    ),
                    serverInfo: Implementation(
                      name: 'subscription-test-server',
                      version: '1.0.0',
                    ),
                    ttlMs: 0,
                    cacheScope: CacheScope.private,
                  ).toJson(),
                ).toJson(),
              ),
            );
          await request.response.close();
          return;
        }

        if (method == Method.subscriptionsListen) {
          final subscriptionId = body['id'] as int;
          final acknowledged = JsonRpcSubscriptionsAcknowledgedNotification(
            acknowledgedParams: const SubscriptionsAcknowledgedNotification(
              notifications: SubscriptionFilter(toolsListChanged: true),
            ),
            meta: {McpMetaKey.subscriptionId: subscriptionId},
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..bufferOutput = false
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write(
              'data: ${jsonEncode(acknowledged.toJson())}\n\n',
            );
          await request.response.flush();
          try {
            await request.response.done;
          } catch (_) {
            // The subscription handle closes this request response stream.
          }
          return;
        }

        if (method == Method.toolsList) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                JsonRpcResponse(
                  id: body['id'] as int,
                  result: {
                    'resultType': resultTypeComplete,
                    ...const ListToolsResult(tools: []).toJson(),
                    'ttlMs': 0,
                    'cacheScope': CacheScope.private,
                  },
                ).toJson(),
              ),
            );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      );
      final client = McpClient(
        const Implementation(name: 'subscription-test', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );
      addTearDown(client.close);
      await client.connect(transport);

      final subscription = client.listenSubscriptions(
        const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
      );
      final acknowledged = await subscription.acknowledged.timeout(
        const Duration(seconds: 5),
      );
      expect(acknowledged.notifications.toolsListChanged, isTrue);

      subscription.cancel('subscription complete');
      await subscription.done.timeout(const Duration(seconds: 5));
      await _waitUntil(
        () => !transport.canCancelRequest(subscription.id),
      );

      final tools =
          await client.listTools().timeout(const Duration(seconds: 5));
      expect(tools.tools, isEmpty);
      expect(cancellationNotifications, 0);
      expect(observedMethods, [
        Method.serverDiscover,
        Method.subscriptionsListen,
        Method.toolsList,
      ]);
    });

    test('stateless terminal SSE response wins a later cancellation', () async {
      var postRequests = 0;
      var cancellationNotifications = 0;
      final streamReady = Completer<void>();
      final releaseTerminalResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        postRequests += 1;
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['method'] == Method.notificationsCancelled) {
          cancellationNotifications += 1;
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(': request stream ready\n\n');
        await request.response.flush();
        if (!streamReady.isCompleted) {
          streamReady.complete();
        }
        await releaseTerminalResponse.future;
        request.response.write(
          'data: ${jsonEncode(
            JsonRpcResponse(
              id: body['id'] as int,
              result: const {'resultType': resultTypeComplete},
            ).toJson(),
          )}\n\n',
        );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      final transportErrors = <Error>[];
      transport.onerror = transportErrors.add;
      final protocol = _CancellationTestProtocol();
      addTearDown(protocol.close);
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final request = protocol.request<EmptyResult>(
        JsonRpcRequest(
          id: -1,
          method: 'test/terminal-race',
          meta: _statelessMeta(),
        ),
        EmptyResult.fromJson,
        RequestOptions(
          signal: controller.signal,
          timeoutEnabled: false,
        ),
      );
      await streamReady.future.timeout(const Duration(seconds: 5));
      releaseTerminalResponse.complete();

      expect(
        await request.timeout(const Duration(seconds: 5)),
        isA<EmptyResult>(),
      );
      controller.abort('too late');
      await _waitUntil(() => !transport.canCancelRequest(0));

      expect(postRequests, 1);
      expect(cancellationNotifications, 0);
      expect(transportErrors, isEmpty);
    });

    test('terminal SSE response closes an open body and drops same-chunk data',
        () async {
      final releaseBody = Completer<void>();
      final serverFinished = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseBody.isCompleted) {
          releaseBody.complete();
        }
      });
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        final terminal = JsonRpcResponse(
          id: body['id'] as int,
          result: const {'resultType': resultTypeComplete},
        );
        const lateNotification = JsonRpcNotification(
          method: 'notifications/late-after-terminal',
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'data: ${jsonEncode(terminal.toJson())}\n\n'
            'data: ${jsonEncode(lateNotification.toJson())}\n\n',
          );
        await request.response.flush();
        await releaseBody.future;
        try {
          await request.response.close();
        } catch (_) {
          // Terminal response cleanup may already close the client stream.
        } finally {
          if (!serverFinished.isCompleted) {
            serverFinished.complete();
          }
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      final messages = <JsonRpcMessage>[];
      transport.onmessage = messages.add;
      await transport.start();

      await transport
          .send(
            JsonRpcRequest(
              id: 28,
              method: 'test/open-terminal-body',
              meta: _statelessMeta(),
            ),
          )
          .timeout(const Duration(seconds: 5));

      expect(transport.canCancelRequest(28), isFalse);
      expect(messages, hasLength(1));
      expect(messages.single, isA<JsonRpcResponse>());

      releaseBody.complete();
      await serverFinished.future.timeout(const Duration(seconds: 5));
    });

    test('MCP 2025-11-25 cancellation retains its JSON-RPC notification',
        () async {
      final observedMethods = <String>[];
      final requestStarted = Completer<void>();
      final cancellationReceived = Completer<JsonRpcCancelledNotification>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        final message = JsonRpcMessage.fromJson(body);
        final method = switch (message) {
          JsonRpcRequest(:final method) => method,
          JsonRpcNotification(:final method) => method,
          _ => '',
        };
        observedMethods.add(method);

        if (message is JsonRpcCancelledNotification) {
          if (!cancellationReceived.isCompleted) {
            cancellationReceived.complete(message);
          }
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }

        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        await cancellationReceived.future;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              JsonRpcResponse(
                id: (message as JsonRpcRequest).id,
                result: const {},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      final protocol = _CancellationTestProtocol();
      addTearDown(protocol.close);
      await protocol.connect(transport);

      final controller = BasicAbortController();
      final request = protocol.request<EmptyResult>(
        const JsonRpcRequest(id: -1, method: 'test/legacy-cancel'),
        EmptyResult.fromJson,
        RequestOptions(
          signal: controller.signal,
          timeoutEnabled: false,
        ),
      );
      await requestStarted.future.timeout(const Duration(seconds: 5));
      controller.abort('legacy request cancelled');

      await expectLater(
        request,
        throwsA(
          predicate<Object?>(
            (error) => error.toString().contains('legacy request cancelled'),
          ),
        ),
      );
      final cancellation = await cancellationReceived.future.timeout(
        const Duration(seconds: 5),
      );
      expect(cancellation.cancelParams.requestId, 0);
      expect(
        cancellation.cancelParams.reason,
        contains('legacy request cancelled'),
      );
      expect(observedMethods, [
        'test/legacy-cancel',
        Method.notificationsCancelled,
      ]);
    });

    test('send derives 2026 stateless HTTP headers from nested metadata',
        () async {
      final capturedHeaders = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        capturedHeaders['protocolVersion'] =
            request.headers.value('mcp-protocol-version');
        capturedHeaders['method'] = request.headers.value('mcp-method');
        capturedHeaders['name'] = request.headers.value('mcp-name');
        capturedHeaders['session'] = request.headers.value('mcp-session-id');
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              JsonRpcResponse(
                id: body['id'],
                result: const {'content': []},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          sessionId: 'legacy-session',
        ),
      );
      await transport.start();

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = completer.complete;

      await transport.send(
        const JsonRpcRequest(
          id: 1,
          method: Method.toolsCall,
          params: {
            'name': 'echo',
            'arguments': {'message': 'hello'},
            '_meta': {
              McpMetaKey.protocolVersion: previewProtocolVersion,
            },
          },
        ),
      );
      await completer.future.timeout(const Duration(seconds: 5));

      expect(
        capturedHeaders['protocolVersion'],
        previewProtocolVersion,
      );
      expect(capturedHeaders['method'], Method.toolsCall);
      expect(capturedHeaders['name'], 'echo');
      expect(capturedHeaders['session'], isNull);
    });

    test('send maps 2026 stateless headers for standard request types',
        () async {
      final capturedHeaders = <Map<String, String?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        capturedHeaders.add({
          'method': request.headers.value('mcp-method'),
          'name': request.headers.value('mcp-name'),
        });
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        final id = body['id'];
        if (id == null) {
          request.response.statusCode = HttpStatus.accepted;
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                JsonRpcResponse(id: id, result: const {}).toJson(),
              ),
            );
        }
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final responses = <JsonRpcMessage>[];
      transport.onmessage = responses.add;

      await transport.send(
        JsonRpcReadResourceRequest(
          id: 1,
          readParams: const ReadResourceRequest(uri: 'file:///notes.md'),
          meta: _statelessMeta(),
        ),
      );
      await transport.send(
        JsonRpcGetPromptRequest(
          id: 2,
          getParams: const GetPromptRequest(name: 'summarize'),
          meta: _statelessMeta(),
        ),
      );
      await transport.send(
        JsonRpcNotification(
          method: Method.notificationsCancelled,
          params: const {'requestId': 1},
          meta: _statelessMeta(),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(responses, hasLength(2));
      expect(capturedHeaders, hasLength(3));
      expect(capturedHeaders[0], {
        'method': Method.resourcesRead,
        'name': 'file:///notes.md',
      });
      expect(capturedHeaders[1], {
        'method': Method.promptsGet,
        'name': 'summarize',
      });
      expect(capturedHeaders[2], {
        'method': Method.notificationsCancelled,
        'name': null,
      });
    });

    test('send adds 2026 stateless task name header', () async {
      final capturedHeaders = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        capturedHeaders['protocolVersion'] =
            request.headers.value('mcp-protocol-version');
        capturedHeaders['method'] = request.headers.value('mcp-method');
        capturedHeaders['name'] = request.headers.value('mcp-name');
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              const JsonRpcResponse(
                id: 1,
                result: {'resultType': resultTypeComplete},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = completer.complete;

      await transport.send(
        JsonRpcUpdateTaskRequest(
          id: 1,
          updateParams: const UpdateTaskRequest(
            taskId: 'task-1',
            inputResponses: {},
          ),
          meta: _statelessMeta(),
        ),
      );
      await completer.future.timeout(const Duration(seconds: 5));

      expect(
        capturedHeaders['protocolVersion'],
        previewProtocolVersion,
      );
      expect(capturedHeaders['method'], Method.tasksUpdate);
      expect(capturedHeaders['name'], 'task-1');
    });

    test('stateless SSE responses reject server-initiated requests', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        final serverRequest = const JsonRpcRequest(
          id: 99,
          method: Method.rootsList,
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ${jsonEncode(serverRequest.toJson())}\n\n');
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final errorCompleter = Completer<Error>();
      final messages = <JsonRpcMessage>[];
      transport
        ..onmessage = messages.add
        ..onerror = (error) {
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(error);
          }
        };

      await expectLater(
        transport.send(
          JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );

      final error = await errorCompleter.future.timeout(
        const Duration(seconds: 5),
      );
      expect(error, isA<McpError>());
      expect((error as McpError).code, ErrorCode.invalidRequest.value);
      expect(error.message, contains('input_required'));
      expect(messages, isEmpty);
    });

    test(
        'completed stateful POST SSE streams preserve matching IDs and do not reconnect',
        () async {
      var getRequests = 0;
      var postRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        postRequests += 1;
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        final id = body['id'];
        final response = id == 1
            ? JsonRpcResponse(id: id, result: const {'ok': true})
            : JsonRpcError(
                id: id,
                error: JsonRpcErrorData(
                  code: ErrorCode.internalError.value,
                  message: 'expected test error',
                ),
              );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write('data: ${jsonEncode(response.toJson())}\n\n');
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 2,
          ),
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final firstMessageReceived = Completer<JsonRpcMessage>();
      final secondMessageReceived = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        if (!firstMessageReceived.isCompleted) {
          firstMessageReceived.complete(message);
        } else if (!secondMessageReceived.isCompleted) {
          secondMessageReceived.complete(message);
        }
      };

      await transport.send(const JsonRpcRequest(id: 1, method: 'test/one'));
      final firstMessage = await firstMessageReceived.future.timeout(
        const Duration(seconds: 5),
      );
      await transport.send(const JsonRpcRequest(id: 2, method: 'test/two'));
      final secondMessage = await secondMessageReceived.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(postRequests, 2);
      expect(firstMessage, isA<JsonRpcResponse>());
      expect(secondMessage, isA<JsonRpcError>());
      expect((firstMessage as JsonRpcResponse).id, 1);
      expect((secondMessage as JsonRpcError).id, 2);
      expect(getRequests, 0);
    });

    test('mismatched SSE response IDs do not settle or rewrite a request',
        () async {
      final mismatchSent = Completer<void>();
      final releaseMatchingResponse = Completer<void>();
      final protocolError = Completer<Error>();
      final messages = <JsonRpcMessage>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseMatchingResponse.isCompleted) {
          releaseMatchingResponse.complete();
        }
      });
      server.listen((request) async {
        await request.drain<void>();
        final mismatchedResponse = jsonEncode(
          const JsonRpcResponse(
            id: 999,
            result: {'mismatched': true},
          ).toJson(),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..bufferOutput = false
          ..write('data: $mismatchedResponse\n\n');
        await request.response.flush();
        if (!mismatchSent.isCompleted) {
          mismatchSent.complete();
        }

        await releaseMatchingResponse.future;
        final matchingResponse = jsonEncode(
          const JsonRpcResponse(
            id: 1,
            result: {'matched': true},
          ).toJson(),
        );
        request.response.write('data: $matchingResponse\n\n');
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport
        ..onmessage = messages.add
        ..onerror = (error) {
          if (!protocolError.isCompleted) {
            protocolError.complete(error);
          }
        };

      var sendSettled = false;
      final sendFuture = transport
          .send(const JsonRpcRequest(id: 1, method: 'test/correlate'))
          .whenComplete(() => sendSettled = true);
      await mismatchSent.future.timeout(const Duration(seconds: 5));
      final error = await protocolError.future.timeout(
        const Duration(seconds: 5),
      );

      expect(sendSettled, isFalse);
      expect(messages.single, isA<JsonRpcResponse>());
      expect((messages.single as JsonRpcResponse).id, 999);
      expect(error, isA<McpError>());
      expect((error as McpError).code, ErrorCode.invalidRequest.value);

      releaseMatchingResponse.complete();
      await sendFuture.timeout(const Duration(seconds: 5));
      expect(
        messages.whereType<JsonRpcResponse>().map((message) => message.id),
        [999, 1],
      );
    });

    test('interrupted stateful POST SSE streams reconnect', () async {
      var getRequests = 0;
      String? lastEventId;
      final messages = <JsonRpcMessage>[];
      final resumptionTokens = <String>[];
      final terminalResponse = Completer<JsonRpcResponse>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
          lastEventId = request.headers.value('last-event-id');
          final response = jsonEncode(
            const JsonRpcResponse(
              id: 1,
              result: {'ok': true},
            ).toJson(),
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('mcp-session-id', testSessionId)
            ..write(
              'id: checkpoint-2\n'
              'data: ${jsonEncode(const JsonRpcNotification(method: 'test/resumed-two').toJson())}\n\n'
              'id: checkpoint-3\n'
              'data: ${jsonEncode(const JsonRpcNotification(method: 'test/resumed-three').toJson())}\n\n'
              'id: checkpoint-4\n'
              'data: $response\n\n',
            );
          await request.response.close();
          return;
        }

        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'id: checkpoint-1\n\n'
            'id: ignored\u0000token\n\n'
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/initial').toJson())}\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 2,
          ),
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = (message) {
        messages.add(message);
        if (message is JsonRpcResponse && !terminalResponse.isCompleted) {
          terminalResponse.complete(message);
        }
      };

      await transport.send(
        const JsonRpcRequest(id: 1, method: 'test/one'),
        onResumptionToken: resumptionTokens.add,
      );
      final response = await terminalResponse.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(getRequests, 1);
      expect(lastEventId, 'checkpoint-1');
      expect(response.id, 1);
      expect(resumptionTokens, [
        'checkpoint-1',
        'checkpoint-2',
        'checkpoint-3',
        'checkpoint-4',
      ]);
      expect(
        messages.map(
          (message) => switch (message) {
            JsonRpcNotification(:final method) => method,
            JsonRpcResponse() => 'response',
            _ => 'unexpected',
          },
        ),
        ['test/initial', 'test/resumed-two', 'test/resumed-three', 'response'],
      );
    });

    test('interrupted POST SSE without an event ID does not reconnect',
        () async {
      var getRequests = 0;
      var postRequests = 0;
      final resumptionTokens = <String>[];
      final terminalResponse = Completer<JsonRpcResponse>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        postRequests += 1;
        final requestId = body['id'];
        final payload = switch (requestId) {
          1 => 'id: checkpoint-1\n\n'
              'id:\n\n'
              'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress-one').toJson())}\n\n',
          2 => 'id: checkpoint-2\n\n'
              'id\n\n'
              'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress-two').toJson())}\n\n',
          _ => 'data: ${jsonEncode(
              JsonRpcResponse(
                id: requestId,
                result: const {'ok': true},
              ).toJson(),
            )}\n\n',
        };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(payload);
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 2,
          ),
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = (message) {
        if (message is JsonRpcResponse && !terminalResponse.isCompleted) {
          terminalResponse.complete(message);
        }
      };

      final connectionClosed = throwsA(
        isA<McpError>().having(
          (error) => error.code,
          'code',
          ErrorCode.connectionClosed.value,
        ),
      );
      await expectLater(
        transport.send(
          const JsonRpcRequest(id: 1, method: 'test/one'),
          onResumptionToken: resumptionTokens.add,
        ),
        connectionClosed,
      );
      await expectLater(
        transport.send(
          const JsonRpcRequest(id: 2, method: 'test/two'),
          onResumptionToken: resumptionTokens.add,
        ),
        connectionClosed,
      );
      await transport.send(const JsonRpcRequest(id: 3, method: 'test/three'));
      final response = await terminalResponse.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(postRequests, 3);
      expect(getRequests, 0);
      expect(resumptionTokens, ['checkpoint-1', '', 'checkpoint-2', '']);
      expect(response.id, 3);
    });

    test('stateless POST SSE never reconnects even with an event ID', () async {
      var getRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'id: must-not-resume\n'
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 2,
          ),
        ),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      await expectLater(
        transport.send(
          JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(getRequests, 0);
    });

    test('empty resumption tokens fail without sending a request', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests += 1;
        await request.drain<void>();
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      await expectLater(
        transport.send(
          const JsonRpcRequest(id: 1, method: 'test/resume'),
          resumptionToken: '',
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(requests, 0);
    });

    test('resumption after close fails without sending a request', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests += 1;
        await request.drain<void>();
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      await transport.close();

      await expectLater(
        transport.send(
          const JsonRpcRequest(id: 1, method: 'test/resume'),
          resumptionToken: 'checkpoint-1',
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(requests, 0);
    });

    test('stateless resumption after close fails without sending a request',
        () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests += 1;
        await request.drain<void>();
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();
      await transport.close();

      await expectLater(
        transport.send(
          JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
          resumptionToken: 'checkpoint-1',
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(requests, 0);
    });

    test('stateless transports reject resumption without sending a request',
        () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests += 1;
        await request.drain<void>();
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      await expectLater(
        transport.send(
          JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
          resumptionToken: 'checkpoint-1',
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.invalidRequest.value,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(requests, 0);
    });

    test('resumption rejects a GET response that is not an SSE stream',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      await expectLater(
        transport.send(
          const JsonRpcRequest(id: 1, method: 'test/resume'),
          resumptionToken: 'checkpoint-1',
        ),
        throwsA(
          isA<StreamableHttpError>()
              .having((error) => error.code, 'code', HttpStatus.ok)
              .having(
                (error) => error.message,
                'message',
                contains('Expected text/event-stream'),
              ),
        ),
      );
    });

    test('resumption cancels an unexpected GET response body', () async {
      final responseStarted = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseResponse.isCompleted) {
          releaseResponse.complete();
        }
      });
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.text
          ..write('temporarily unavailable');
        await request.response.flush();
        if (!responseStarted.isCompleted) {
          responseStarted.complete();
        }
        await releaseResponse.future;
        try {
          await request.response.close();
        } on Object {
          // The expected client-side cancellation may close the socket first.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(
          const JsonRpcRequest(id: 1, method: 'test/resume'),
          resumptionToken: 'checkpoint-1',
        ),
        throwsA(
          isA<StreamableHttpError>().having(
            (error) => error.code,
            'code',
            HttpStatus.serviceUnavailable,
          ),
        ),
      );
      await responseStarted.future.timeout(const Duration(seconds: 5));
      await sendExpectation.timeout(const Duration(seconds: 1));

      releaseResponse.complete();
    });

    test('requests cancel an unexpected POST response body', () async {
      final responseStarted = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseResponse.isCompleted) {
          releaseResponse.complete();
        }
      });
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..bufferOutput = false
          ..write('unexpected response');
        await request.response.flush();
        if (!responseStarted.isCompleted) {
          responseStarted.complete();
        }
        await releaseResponse.future;
        try {
          await request.response.close();
        } on Object {
          // The expected client-side cancellation may close the socket first.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/unexpected')),
        throwsA(
          isA<StreamableHttpError>().having(
            (error) => error.code,
            'code',
            -1,
          ),
        ),
      );
      await responseStarted.future.timeout(const Duration(seconds: 5));
      await sendExpectation.timeout(const Duration(seconds: 1));

      releaseResponse.complete();
    });

    test('close fails an active request-scoped SSE send', () async {
      final streamOpened = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseResponse.isCompleted) {
          releaseResponse.complete();
        }
      });
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
          );
        await request.response.flush();
        if (!streamOpened.isCompleted) {
          streamOpened.complete();
        }
        await releaseResponse.future;
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final sendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/pending')),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await streamOpened.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await transport.close();
      releaseResponse.complete();
      await sendExpectation;
    });

    test('close fails a request waiting in reconnection backoff', () async {
      var getRequests = 0;
      final progressReceived = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'GET') {
          getRequests += 1;
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'retry: 5000\n'
            'id: pending-checkpoint\n'
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = (message) {
        if (message is JsonRpcNotification && !progressReceived.isCompleted) {
          progressReceived.complete();
        }
      };

      final sendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/pending')),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await progressReceived.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(getRequests, 0);

      await transport.close();
      await sendExpectation.timeout(const Duration(seconds: 1));
      expect(getRequests, 0);
    });

    test('resumed streams that repeatedly end exhaust max retries', () async {
      var getRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'GET') {
          getRequests += 1;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('mcp-session-id', testSessionId)
            ..write(
              'id: checkpoint-${getRequests + 1}\n'
              'data: ${jsonEncode(JsonRpcNotification(method: 'test/resumed-$getRequests').toJson())}\n\n',
            );
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'id: checkpoint-1\n'
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 2,
          ),
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      await expectLater(
        transport
            .send(const JsonRpcRequest(id: 1, method: 'test/pending'))
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      expect(getRequests, 2);
    });

    test('a resumed request stops after an empty SSE event ID', () async {
      var getRequests = 0;
      final resumptionTokens = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'GET') {
          getRequests += 1;
          expect(
            request.headers.value('last-event-id'),
            'checkpoint-1',
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('mcp-session-id', testSessionId)
            ..write('id:\n\n');
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'id: checkpoint-1\n'
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 3,
          ),
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      await expectLater(
        transport
            .send(
              const JsonRpcRequest(id: 1, method: 'test/pending'),
              onResumptionToken: resumptionTokens.add,
            )
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      expect(getRequests, 1);
      expect(resumptionTokens, ['checkpoint-1', '']);
    });

    test('session reset fails a request opening its resumed GET', () async {
      final getReceived = Completer<void>();
      final releaseGetResponse = Completer<void>();
      final finishGetResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseGetResponse.isCompleted) {
          releaseGetResponse.complete();
        }
        if (!finishGetResponse.isCompleted) {
          finishGetResponse.complete();
        }
      });
      server.listen((request) async {
        if (request.method == 'GET') {
          await request.drain<void>();
          if (!getReceived.isCompleted) {
            getReceived.complete();
          }
          await releaseGetResponse.future;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('mcp-session-id', testSessionId)
            ..write(
              'data: ${jsonEncode(const JsonRpcNotification(method: 'test/resumed').toJson())}\n\n',
            );
          await request.response.flush();
          await finishGetResponse.future;
          await request.response.close();
          return;
        }

        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['id'] == 1) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('mcp-session-id', testSessionId)
            ..write(
              'retry: 0\n'
              'id: pending-checkpoint\n'
              'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
            );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final originalSendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/pending')),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await getReceived.future.timeout(const Duration(seconds: 5));

      await expectLater(
        transport.send(const JsonRpcRequest(id: 2, method: 'test/reset')),
        throwsA(isA<StaleSessionError>()),
      );
      releaseGetResponse.complete();

      await originalSendExpectation.timeout(const Duration(seconds: 1));
      finishGetResponse.complete();
    });

    test('session reset rejects a late request-scoped POST response', () async {
      final heldPostReceived = Completer<void>();
      final releaseHeldPost = Completer<void>();
      final finishHeldPost = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseHeldPost.isCompleted) {
          releaseHeldPost.complete();
        }
        if (!finishHeldPost.isCompleted) {
          finishHeldPost.complete();
        }
      });
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['id'] != 1) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (!heldPostReceived.isCompleted) {
          heldPostReceived.complete();
        }
        await releaseHeldPost.future;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/late').toJson())}\n\n',
          );
        await request.response.flush();
        await finishHeldPost.future;
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final heldSendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/held')),
        throwsA(isA<StaleSessionError>()),
      );
      await heldPostReceived.future.timeout(const Duration(seconds: 5));

      await expectLater(
        transport.send(const JsonRpcRequest(id: 2, method: 'test/reset')),
        throwsA(isA<StaleSessionError>()),
      );

      await heldSendExpectation.timeout(const Duration(seconds: 1));
      expect(transport.sessionId, isNull);
      releaseHeldPost.complete();
      finishHeldPost.complete();
    });

    test('session reset aborts a request waiting on its response body',
        () async {
      final bodyStarted = Completer<void>();
      final releaseBody = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseBody.isCompleted) {
          releaseBody.complete();
        }
      });
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['id'] != 1) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.set('mcp-session-id', testSessionId)
          ..write('{"jsonrpc":"2.0","id":1,"result":');
        await request.response.flush();
        if (!bodyStarted.isCompleted) {
          bodyStarted.complete();
        }
        await releaseBody.future;
        try {
          request.response.write('{"ok":true}}');
          await request.response.close();
        } on Object {
          // The expected client-side abort may close the socket first.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final heldSendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/held-body')),
        throwsA(isA<StaleSessionError>()),
      );
      await bodyStarted.future.timeout(const Duration(seconds: 5));

      await expectLater(
        transport.send(const JsonRpcRequest(id: 2, method: 'test/reset')),
        throwsA(isA<StaleSessionError>()),
      );
      await heldSendExpectation.timeout(const Duration(seconds: 1));
      expect(transport.sessionId, isNull);

      releaseBody.complete();
    });

    test('session reset suppresses a late terminal SSE callback', () async {
      final streamOpened = Completer<void>();
      final releaseTerminal = Completer<void>();
      final messages = <JsonRpcMessage>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseTerminal.isCompleted) {
          releaseTerminal.complete();
        }
      });
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['id'] != 1) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'data: ${jsonEncode(const JsonRpcNotification(method: 'test/progress').toJson())}\n\n',
          );
        await request.response.flush();
        if (!streamOpened.isCompleted) {
          streamOpened.complete();
        }
        await releaseTerminal.future;
        try {
          final terminalResponse = jsonEncode(
            const JsonRpcResponse(
              id: 1,
              result: {'ok': true},
            ).toJson(),
          );
          request.response.write('data: $terminalResponse\n\n');
          await request.response.close();
        } on Object {
          // The expected client-side abort may close the socket first.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = messages.add;

      final heldSendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/held-sse')),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await streamOpened.future.timeout(const Duration(seconds: 5));

      await expectLater(
        transport.send(const JsonRpcRequest(id: 2, method: 'test/reset')),
        throwsA(isA<StaleSessionError>()),
      );
      await heldSendExpectation.timeout(const Duration(seconds: 1));
      releaseTerminal.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        messages.whereType<JsonRpcResponse>(),
        isEmpty,
      );
    });

    test('throwing resumption callbacks do not strand terminal responses',
        () async {
      final callbackError = Completer<Error>();
      final responseReceived = Completer<JsonRpcMessage>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        final terminalResponse = jsonEncode(
          const JsonRpcResponse(
            id: 1,
            result: {'ok': true},
          ).toJson(),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'id: checkpoint-1\n'
            'data: $terminalResponse\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport
        ..onmessage = responseReceived.complete
        ..onerror = (error) {
          if (!callbackError.isCompleted) {
            callbackError.complete(error);
          }
        };

      await transport.send(
        const JsonRpcRequest(id: 1, method: 'test/terminal'),
        onResumptionToken: (_) => throw StateError('callback failed'),
      );

      expect(
        await responseReceived.future.timeout(const Duration(seconds: 5)),
        isA<JsonRpcResponse>(),
      );
      expect(
        await callbackError.future.timeout(const Duration(seconds: 5)),
        isA<StateError>(),
      );
    });

    test('session termination aborts an in-flight request', () async {
      final postReceived = Completer<void>();
      final releasePost = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releasePost.isCompleted) {
          releasePost.complete();
        }
      });
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'DELETE') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (!postReceived.isCompleted) {
          postReceived.complete();
        }
        await releasePost.future;
        try {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..headers.set('mcp-session-id', testSessionId)
            ..write(
              jsonEncode(
                const JsonRpcResponse(
                  id: 1,
                  result: {'ok': true},
                ).toJson(),
              ),
            );
          await request.response.close();
        } on Object {
          // The expected client-side abort may close the socket first.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();

      final heldSendExpectation = expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/held')),
        throwsA(isA<StaleSessionError>()),
      );
      await postReceived.future.timeout(const Duration(seconds: 5));

      await transport.terminateSession();
      await heldSendExpectation.timeout(const Duration(seconds: 1));
      expect(transport.sessionId, isNull);

      releasePost.complete();
    });

    test('late session termination cannot clear a replacement session',
        () async {
      const replacementSessionId = 'replacement-session';
      final deleteReceived = Completer<void>();
      final releaseDelete = Completer<void>();
      final responseReceived = Completer<JsonRpcMessage>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() {
        if (!releaseDelete.isCompleted) {
          releaseDelete.complete();
        }
      });
      server.listen((request) async {
        if (request.method == 'DELETE') {
          await request.drain<void>();
          if (!deleteReceived.isCompleted) {
            deleteReceived.complete();
          }
          await releaseDelete.future;
          try {
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          } on Object {
            // The stale-session abort may close the socket first.
          }
          return;
        }

        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        if (body['method'] == 'test/reset') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.set('mcp-session-id', replacementSessionId)
          ..write(
            jsonEncode(
              const JsonRpcResponse(
                id: 2,
                result: {'initialized': true},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = responseReceived.complete;

      final terminationExpectation = expectLater(
        transport.terminateSession(),
        throwsA(isA<StaleSessionError>()),
      );
      await deleteReceived.future.timeout(const Duration(seconds: 5));

      await expectLater(
        transport.send(const JsonRpcRequest(id: 1, method: 'test/reset')),
        throwsA(isA<StaleSessionError>()),
      );
      await transport.send(
        const JsonRpcRequest(id: 2, method: 'initialize'),
      );
      await responseReceived.future.timeout(const Duration(seconds: 5));
      expect(transport.sessionId, replacementSessionId);

      releaseDelete.complete();
      await terminationExpectation.timeout(const Duration(seconds: 1));
      expect(transport.sessionId, replacementSessionId);
    });

    test('terminal responses settle sends when onmessage throws', () async {
      final callbackError = Completer<Error>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        final response = JsonRpcResponse(
          id: body['id'],
          result: const {'ok': true},
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write(
            'data: ${jsonEncode(response.toJson())}\n\n',
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = (_) {
        throw StateError('expected callback failure');
      };
      transport.onerror = (error) {
        if (!callbackError.isCompleted) {
          callbackError.complete(error);
        }
      };

      await transport.send(
        const JsonRpcRequest(id: 1, method: 'test/callback'),
      );
      final error = await callbackError.future.timeout(
        const Duration(seconds: 5),
      );
      expect(error, isA<StateError>());
    });

    test('throwing onerror cannot strand a malformed final SSE event',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write('data: {"jsonrpc":\n\n');
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onerror = (_) => throw StateError('callback failed');

      await expectLater(
        transport
            .send(const JsonRpcRequest(id: 1, method: 'test/malformed'))
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
    });

    test('throwing onerror cannot strand an errored SSE response', () async {
      final progressReceived = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        final progress = jsonEncode(
          const JsonRpcNotification(method: 'test/progress').toJson(),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..contentLength = 4096
          ..bufferOutput = false
          ..write('data: $progress\n\n');
        try {
          await request.response.close();
        } on Object {
          // Closing before contentLength bytes induces the client stream error.
        }
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport
        ..onmessage = (message) {
          if (message is JsonRpcNotification && !progressReceived.isCompleted) {
            progressReceived.complete();
          }
        }
        ..onerror = (_) => throw StateError('callback failed');

      final sendExpectation = expectLater(
        transport
            .send(const JsonRpcRequest(id: 1, method: 'test/stream-error'))
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.connectionClosed.value,
          ),
        ),
      );
      await progressReceived.future.timeout(const Duration(seconds: 2));
      await sendExpectation;
    });

    test('resumed POST SSE errors keep the original request ID', () async {
      var getRequests = 0;
      String? lastEventId;
      final terminalError = Completer<JsonRpcError>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          getRequests += 1;
          lastEventId = request.headers.value('last-event-id');
          final error = jsonEncode(
            const JsonRpcError(
              id: 7,
              error: JsonRpcErrorData(
                code: -32001,
                message: 'resumed failure',
                data: {'reason': 'expected'},
              ),
            ).toJson(),
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('mcp-session-id', testSessionId)
            ..write('data: $error\n\n');
          await request.response.close();
          return;
        }

        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('mcp-session-id', testSessionId)
          ..write('id: checkpoint-error\n\n');
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 10,
            maxReconnectionDelay: 10,
            reconnectionDelayGrowFactor: 1,
            maxRetries: 2,
          ),
        ),
      )..protocolVersion = stableProtocolVersion;
      await transport.start();
      transport.onmessage = (message) {
        if (message is JsonRpcError && !terminalError.isCompleted) {
          terminalError.complete(message);
        }
      };

      await transport.send(const JsonRpcRequest(id: 7, method: 'test/error'));
      final error = await terminalError.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(getRequests, 1);
      expect(lastEventId, 'checkpoint-error');
      expect(error.id, 7);
      expect(error.error.code, -32001);
      expect(error.error.message, 'resumed failure');
      expect(error.error.data, {'reason': 'expected'});
    });

    test('stateless JSON responses reject server-initiated requests', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        final serverRequest = const JsonRpcRequest(
          id: 99,
          method: Method.rootsList,
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode([serverRequest.toJson()]));
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )..protocolVersion = previewProtocolVersion;
      await transport.start();

      final errorCompleter = Completer<Error>();
      final messages = <JsonRpcMessage>[];
      transport
        ..onmessage = messages.add
        ..onerror = (error) {
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(error);
          }
        };

      await transport.send(
        JsonRpcListToolsRequest(id: 1, meta: _statelessMeta()),
      );

      final error = await errorCompleter.future.timeout(
        const Duration(seconds: 5),
      );
      expect(error, isA<McpError>());
      expect((error as McpError).code, ErrorCode.invalidRequest.value);
      expect(error.message, contains('inputRequests'));
      expect(messages, isEmpty);
    });

    test('send mirrors mapped tool parameters into 2026 stateless headers',
        () async {
      final capturedHeaders = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        capturedHeaders['region'] = request.headers.value('mcp-param-region');
        capturedHeaders['greeting'] =
            request.headers.value('mcp-param-greeting');
        capturedHeaders['limit'] = request.headers.value('mcp-param-limit');
        capturedHeaders['rounded'] = request.headers.value('mcp-param-rounded');
        capturedHeaders['unsafe'] = request.headers.value('mcp-param-unsafe');
        capturedHeaders['ratio'] = request.headers.value('mcp-param-ratio');
        capturedHeaders['dryRun'] = request.headers.value('mcp-param-dry-run');
        capturedHeaders['text'] = request.headers.value('mcp-param-text');
        capturedHeaders['payload'] = request.headers.value('mcp-param-payload');
        capturedHeaders['sentinel'] =
            request.headers.value('mcp-param-sentinel');
        capturedHeaders['tenant'] = request.headers.value('mcp-param-tenant');
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              const JsonRpcResponse(
                id: 1,
                result: {'content': []},
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      transport = StreamableHttpClientTransport(
        Uri.parse('http://localhost:${server.port}/mcp'),
      )
        ..protocolVersion = previewProtocolVersion
        ..setToolParameterHeaderMappings(
          {
            'execute_sql': {
              'region': 'Region',
              'greeting': 'Greeting',
              'limit': 'Limit',
              'rounded': 'Rounded',
              'unsafe': 'Unsafe',
              'ratio': 'Ratio',
              'dryRun': 'Dry-Run',
              'text': 'Text',
              'payload': 'Payload',
              'sentinel': 'Sentinel',
              '/auth/tenant': 'Tenant',
            },
          },
        );
      await transport.start();

      final completer = Completer<JsonRpcMessage>();
      transport.onmessage = completer.complete;

      await transport.send(
        JsonRpcCallToolRequest(
          id: 1,
          params: const {
            'name': 'execute_sql',
            'arguments': {
              'region': 'us-west1',
              'greeting': 'Hello, 世界',
              'limit': 42,
              'rounded': 42.0,
              'unsafe': 9007199254740992,
              'ratio': 1.5,
              'dryRun': false,
              'text': ' padded ',
              'payload': {'nested': true},
              'sentinel': '=?base64?YWJj?=',
              'auth': {'tenant': 'acme'},
            },
          },
          meta: _statelessMeta(),
        ),
      );
      await completer.future.timeout(const Duration(seconds: 5));

      expect(capturedHeaders['region'], 'us-west1');
      expect(
        capturedHeaders['greeting'],
        '=?base64?${base64Encode(utf8.encode('Hello, 世界'))}?=',
      );
      expect(capturedHeaders['limit'], '42');
      expect(capturedHeaders['rounded'], '42');
      expect(capturedHeaders['unsafe'], isNull);
      expect(capturedHeaders['ratio'], isNull);
      expect(capturedHeaders['dryRun'], 'false');
      expect(capturedHeaders['text'], '=?base64?IHBhZGRlZCA=?=');
      expect(capturedHeaders['payload'], isNull);
      expect(
        capturedHeaders['sentinel'],
        '=?base64?${base64Encode(utf8.encode('=?base64?YWJj?='))}?=',
      );
      expect(capturedHeaders['tenant'], 'acme');
    });

    test('send with initialized notification triggers SSE establishment',
        () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      final notification = const JsonRpcInitializedNotification();

      await transport.send(notification);

      // Wait a moment for the GET request to be established
      await Future.delayed(const Duration(milliseconds: 500));

      // If a connection was established, currentSseConnections should have an entry
      expect(currentSseConnections.isEmpty, isFalse);
    });

    test('close method terminates the transport', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      final closeCompleter = Completer<void>();
      transport.onclose = () {
        closeCompleter.complete();
      };

      await transport.close();

      await closeCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('onclose not called'),
      );
    });

    test('close method is idempotent', () async {
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      var closeCallbacks = 0;
      transport.onclose = () {
        closeCallbacks += 1;
      };

      await transport.close();
      await transport.close();

      expect(closeCallbacks, 1);
    });

    test(
      '_getNextReconnectionDelay implements exponential backoff',
      () async {
        // Set up a reconnection simulation flag

        // Create a new transport with specialized reconnection options
        transport = StreamableHttpClientTransport(
          serverUrl,
          opts: const StreamableHttpClientTransportOptions(
            reconnectionOptions: StreamableHttpReconnectionOptions(
              initialReconnectionDelay: 100, // Very short to make test faster
              reconnectionDelayGrowFactor: 1.1,
              maxReconnectionDelay: 500,
              maxRetries: 10, // Plenty of retries
            ),
          ),
        );

        await transport.start();

        // We'll test the algorithm by sending a notification
        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        // Wait for SSE connection to establish
        await Future.delayed(const Duration(milliseconds: 500));

        // Make sure we have at least one connection before proceeding
        if (currentSseConnections.isEmpty) {
          fail('Initial connection was not established');
        }

        // Close all current connections to simulate a disconnect
        for (var connection in List<HttpResponse>.from(currentSseConnections)) {
          try {
            await connection.close();
          } catch (e) {
            print('Error closing connection: $e');
          }
        }
        currentSseConnections.clear();

        // Wait for the client to attempt reconnection
        await Future.delayed(const Duration(seconds: 2));

        // After the delay, manually "accept" a new connection by sending another notification
        await transport.send(notification);

        // Wait for the new connection to establish
        await Future.delayed(const Duration(milliseconds: 500));

        // Now we should have a new connection
        expect(
          currentSseConnections.isNotEmpty,
          isTrue,
          reason: 'New connection should be established after reconnection',
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'respects SSE retry field when reconnecting',
      () async {
        final retryServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final retryUrl = Uri.parse('http://localhost:${retryServer.port}/mcp');
        final retrySessionId = 'retry-session-id';

        DateTime? firstGetAt;
        DateTime? secondGetAt;
        int getCount = 0;

        retryServer.listen((request) async {
          if (request.uri.path != '/mcp') {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }

          if (request.method == 'POST') {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;

            request.response.headers.set('mcp-session-id', retrySessionId);
            if (json['method'] == 'notifications/initialized') {
              request.response.statusCode = HttpStatus.accepted;
              await request.response.close();
              return;
            }

            request.response.headers.contentType = ContentType.json;
            request.response.statusCode = HttpStatus.ok;
            request.response.write(
              jsonEncode(
                JsonRpcResponse(
                  id: json['id'],
                  result: const {'success': true},
                ).toJson(),
              ),
            );
            await request.response.close();
            return;
          }

          if (request.method == 'GET') {
            request.response.headers.add('Content-Type', 'text/event-stream');
            request.response.headers.add('Cache-Control', 'no-cache');
            request.response.headers.add('Connection', 'keep-alive');
            request.response.headers.add('mcp-session-id', retrySessionId);

            getCount += 1;
            if (getCount == 1) {
              firstGetAt = DateTime.now();
              request.response.write('retry: 1200\n\n');
              await request.response.flush();
              await request.response.close();
              return;
            }

            if (getCount == 2) {
              secondGetAt = DateTime.now();
              request.response.write(': connected\n\n');
              await request.response.flush();
              await Future.delayed(const Duration(milliseconds: 300));
              await request.response.close();
              return;
            }

            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        });

        final retryTransport = StreamableHttpClientTransport(retryUrl);
        try {
          await retryTransport.start();
          await retryTransport.send(const JsonRpcInitializedNotification());

          final deadline = DateTime.now().add(const Duration(seconds: 6));
          while (secondGetAt == null && DateTime.now().isBefore(deadline)) {
            await Future.delayed(const Duration(milliseconds: 50));
          }

          expect(firstGetAt, isNotNull);
          expect(secondGetAt, isNotNull);

          final reconnectDelayMs =
              secondGetAt!.difference(firstGetAt!).inMilliseconds;
          expect(reconnectDelayMs, greaterThanOrEqualTo(1000));
        } finally {
          await retryTransport.close();
          await retryServer.close(force: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'receives SSE events',
      () async {
        transport = StreamableHttpClientTransport(serverUrl);

        // Set up the message handler first
        final messageCompleter = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          print('Transport received message: ${jsonEncode(message.toJson())}');
          messageCompleter.complete(message);
        };

        transport.onerror = (error) {
          print('Transport error: $error');
        };

        await transport.start();

        // Send initialization notification to establish SSE connection
        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        // Wait for SSE connection to be established
        await Future.delayed(const Duration(milliseconds: 1000));

        if (currentSseConnections.isEmpty) {
          fail('No SSE connections established');
        }

        print(
          'About to send SSE event, active connections: ${currentSseConnections.length}',
        );

        // Send a valid JSON-RPC notification via SSE using proper SSE format
        for (final connection
            in List<HttpResponse>.from(currentSseConnections)) {
          try {
            final message = const JsonRpcNotification(
              method: 'notifications/initialized',
            );

            final data = jsonEncode(message.toJson());
            print('Sending SSE event with data: $data');

            // Send data with proper SSE format in a single write operation
            // This avoids the header already sent error
            connection.write('data: $data\n\n');
            await connection.flush();
            print('Sent SSE event');
          } catch (e) {
            print('Error sending SSE event: $e');
            fail('Failed to send SSE event: $e');
          }
        }

        // Wait for the message with a longer timeout
        final message = await messageCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('*** TIMEOUT: No message received via SSE after 5 seconds');
            throw TimeoutException('No message received via SSE');
          },
        );

        expect(message, isA<JsonRpcNotification>());
        expect(
          (message as JsonRpcNotification).method,
          equals('notifications/initialized'),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'authentication flow works',
      () async {
        // Create a mock auth provider that specifically implements the required behavior
        final mockAuthProvider = MockOAuthClientProvider(returnTokens: false);

        // Override the standard method to ensure it redirects
        mockAuthProvider.registerRedirectToAuthorization(() async {
          mockAuthProvider.didRedirectToAuthorization = true;
          print('Mock redirected to authorization!');
        });

        transport = StreamableHttpClientTransport(
          serverUrl,
          opts: StreamableHttpClientTransportOptions(
            authProvider: mockAuthProvider,
          ),
        );

        await transport.start();

        final request = const JsonRpcRequest(
          id: 123,
          method: 'test/method',
          params: {'data': 'test-data'},
        );

        // Set up an error handler to verify errors
        final errorCompleter = Completer<Error>();
        transport.onerror = (error) {
          print('Auth test error: $error');
          errorCompleter.complete(error);
        };

        try {
          // This should trigger auth flow and eventually throw
          await transport.send(request);

          // If we get here, we should check the auth provider state
          if (!mockAuthProvider.didRedirectToAuthorization) {
            fail('Auth provider did not redirect to authorization');
          }
        } catch (e) {
          print('Auth test caught exception: $e');
          // This is expected since we're using a mock that doesn't return tokens
        }

        // Verify the auth provider was called to redirect
        expect(
          mockAuthProvider.didRedirectToAuthorization,
          isTrue,
          reason: 'Auth provider should have redirected to authorization',
        );

        // For the second part of the test, use a new transport that succeeds
        final successAuthProvider = MockOAuthClientProvider(returnTokens: true);
        transport = StreamableHttpClientTransport(
          serverUrl,
          opts: StreamableHttpClientTransportOptions(
            authProvider: successAuthProvider,
          ),
        );
        await transport.start();

        // Set up the message handler
        final completer = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          completer.complete(message);
        };

        // Send the request with the authenticated transport
        await transport.send(request);

        // Verify we get a successful response
        final response = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('No response received after auth'),
        );

        expect(response, isA<JsonRpcResponse>());
        expect((response as JsonRpcResponse).id, equals(123));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('terminateSession sends DELETE request', () async {
      transport = StreamableHttpClientTransport(
        serverUrl,
        opts: StreamableHttpClientTransportOptions(
          sessionId: testSessionId,
        ),
      );
      await transport.start();

      // Now terminate the session
      await transport.terminateSession();

      // Since the session was terminated, a successful result implies the
      // server received and processed our DELETE request
      expect(true, isTrue);
    });

    test(
      'handles CRLF line endings in SSE events',
      () async {
        transport = StreamableHttpClientTransport(serverUrl);

        final messageCompleter = Completer<JsonRpcMessage>();
        transport.onmessage = (message) {
          print('Transport received message: ${jsonEncode(message.toJson())}');
          messageCompleter.complete(message);
        };

        transport.onerror = (error) {
          print('Transport error: $error');
        };

        await transport.start();

        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

        await Future.delayed(const Duration(milliseconds: 1000));

        if (currentSseConnections.isEmpty) {
          fail('No SSE connections established');
        }

        print(
          'About to send SSE event, active connections: ${currentSseConnections.length}',
        );

        for (final connection
            in List<HttpResponse>.from(currentSseConnections)) {
          try {
            final message = const JsonRpcNotification(
              method: 'notifications/initialized',
            );

            final data = jsonEncode(message.toJson());
            print('Sending SSE event with data: $data');

            connection.write('event: message\r\n');
            connection.write('data: $data\r\n\r\n');
            await connection.flush();
            print('Sent SSE event');
          } catch (e) {
            print('Error sending SSE event: $e');
            fail('Failed to send SSE event: $e');
          }
        }

        final message = await messageCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('*** TIMEOUT: No message received via SSE after 5 seconds');
            throw TimeoutException('No message received via SSE');
          },
        );

        expect(message, isA<JsonRpcNotification>());
        expect(
          (message as JsonRpcNotification).method,
          equals('notifications/initialized'),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    group('OAuth Discovery', () {
      Future<void> expectClientRegistrationSelection({
        required String clientId,
        required bool expectsDynamicRegistration,
      }) async {
        final oauthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => oauthServer.close(force: true));
        final oauthPort = oauthServer.port;
        var registrationRequests = 0;

        oauthServer.listen((request) async {
          switch (request.uri.path) {
            case '/mcp':
              request.response
                ..statusCode = HttpStatus.unauthorized
                ..headers.set(
                  HttpHeaders.wwwAuthenticateHeader,
                  'Bearer resource_metadata="http://localhost:$oauthPort/.well-known/oauth-protected-resource/mcp"',
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-protected-resource/mcp':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'resource': 'http://localhost:$oauthPort/mcp',
                    'authorization_servers': [
                      'http://localhost:$oauthPort/auth',
                    ],
                  }),
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-authorization-server/auth':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'issuer': 'http://localhost:$oauthPort/auth',
                    'authorization_endpoint':
                        'http://localhost:$oauthPort/authorize',
                    'token_endpoint': 'http://localhost:$oauthPort/token',
                    'registration_endpoint':
                        'http://localhost:$oauthPort/register',
                    'code_challenge_methods_supported': ['S256'],
                    'token_endpoint_auth_methods_supported': ['none'],
                    'client_id_metadata_document_supported': true,
                  }),
                );
              await request.response.close();
              break;
            case '/register':
              registrationRequests += 1;
              await utf8.decoder.bind(request).join();
              request.response
                ..statusCode = HttpStatus.created
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'client_id': 'registered-client',
                    'token_endpoint_auth_method': 'none',
                  }),
                );
              await request.response.close();
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
          }
        });

        final authProvider = DiscoveryOAuthClientProvider(
          clientId: clientId,
          redirectUri: Uri.parse('http://localhost/callback'),
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$oauthPort/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 75, method: 'test/method'),
          ),
          throwsA(isA<UnauthorizedError>()),
        );

        expect(registrationRequests, expectsDynamicRegistration ? 1 : 0);
        expect(
          authProvider.authorizationUri?.queryParameters['client_id'],
          expectsDynamicRegistration ? 'registered-client' : clientId,
        );
      }

      test('parses bearer challenge parameters', () {
        final challenge = OAuthBearerChallengeParameters.fromHeader(
          r'Bearer resource_metadata="https://mcp.example/.well-known/oauth-protected-resource/mcp", scope="tools:\"read\"\\admin", error="insufficient_scope"',
        );

        expect(
          challenge?.resourceMetadata.toString(),
          'https://mcp.example/.well-known/oauth-protected-resource/mcp',
        );
        expect(challenge?.scope, r'tools:"read"\admin');
        expect(challenge?.error, 'insufficient_scope');
      });

      test('ignores invalid bearer challenge resource metadata', () {
        final challenge = OAuthBearerChallengeParameters.fromHeader(
          r'Bearer resource_metadata="http://[", scope="tools:read"',
        );

        expect(challenge, isNotNull);
        expect(challenge?.resourceMetadata, isNull);
        expect(challenge?.scope, 'tools:read');
      });

      for (final clientId in [
        'http://client.example/client.json',
        'https://client.example',
        'https://client.example/',
      ]) {
        test('does not treat $clientId as a client ID metadata document',
            () async {
          await expectClientRegistrationSelection(
            clientId: clientId,
            expectsDynamicRegistration: true,
          );
        });
      }

      test('uses an HTTPS client ID with a path as a metadata document',
          () async {
        await expectClientRegistrationSelection(
          clientId: 'https://client.example/client.json',
          expectsDynamicRegistration: false,
        );
      });

      test('normalizes and tries path issuer metadata in MCP priority order',
          () async {
        final oauthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => oauthServer.close(force: true));
        final oauthPort = oauthServer.port;
        final discoveryPaths = <String>[];
        final discoveryQueries = <String>[];

        oauthServer.listen((request) async {
          switch (request.uri.path) {
            case '/mcp':
              request.response
                ..statusCode = HttpStatus.unauthorized
                ..headers.set(
                  HttpHeaders.wwwAuthenticateHeader,
                  'Bearer resource_metadata="http://localhost:$oauthPort/.well-known/oauth-protected-resource/mcp"',
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-protected-resource/mcp':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'resource': 'http://localhost:$oauthPort/mcp',
                    'authorization_servers': [
                      'http://localhost:$oauthPort/tenant1/?source=config',
                    ],
                  }),
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-authorization-server/tenant1':
            case '/.well-known/openid-configuration/tenant1':
            case '/tenant1/.well-known/openid-configuration':
              discoveryPaths.add(request.uri.path);
              discoveryQueries.add(request.uri.query);
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
              break;
            case '/tenant1/.well-known/oauth-authorization-server':
              discoveryPaths.add(request.uri.path);
              discoveryQueries.add(request.uri.query);
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'issuer':
                        'http://localhost:$oauthPort/tenant1/?source=config',
                    'authorization_endpoint':
                        'http://localhost:$oauthPort/authorize',
                    'token_endpoint': 'http://localhost:$oauthPort/token',
                    'code_challenge_methods_supported': ['S256'],
                    'token_endpoint_auth_methods_supported': ['none'],
                  }),
                );
              await request.response.close();
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
          }
        });

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$oauthPort/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 76, method: 'test/method'),
          ),
          throwsA(isA<UnauthorizedError>()),
        );

        expect(authProvider.authorizationUri, isNotNull);
        expect(discoveryPaths, [
          '/.well-known/oauth-authorization-server/tenant1',
          '/.well-known/openid-configuration/tenant1',
          '/tenant1/.well-known/openid-configuration',
          '/tenant1/.well-known/oauth-authorization-server',
        ]);
        expect(discoveryQueries, ['', '', '', '']);
      });

      test('rejects untrusted cross-origin OAuth discovery URLs', () async {
        final oauthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => oauthServer.close(force: true));
        oauthServer.listen((request) async {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer resource_metadata="https://untrusted.example/metadata"',
            );
          await request.response.close();
        });

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:${oauthServer.port}/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 76, method: 'test/method'),
          ),
          throwsA(
            isA<UnauthorizedError>().having(
              (error) => error.message,
              'message',
              contains('untrusted cross-origin'),
            ),
          ),
        );
        expect(authProvider.authorizationUri, isNull);
      });

      test(
          'rejects unsupported advertised token endpoint authentication methods',
          () async {
        final oauthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => oauthServer.close(force: true));
        final oauthPort = oauthServer.port;
        var tokenRequests = 0;

        oauthServer.listen((request) async {
          switch (request.uri.path) {
            case '/mcp':
              request.response
                ..statusCode = HttpStatus.unauthorized
                ..headers.set(
                  HttpHeaders.wwwAuthenticateHeader,
                  'Bearer resource_metadata="http://localhost:$oauthPort/.well-known/oauth-protected-resource/mcp"',
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-protected-resource/mcp':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'resource': 'http://localhost:$oauthPort/mcp',
                    'authorization_servers': [
                      'http://localhost:$oauthPort/auth',
                    ],
                  }),
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-authorization-server/auth':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'issuer': 'http://localhost:$oauthPort/auth',
                    'authorization_endpoint':
                        'http://localhost:$oauthPort/authorize',
                    'token_endpoint': 'http://localhost:$oauthPort/token',
                    'code_challenge_methods_supported': ['S256'],
                    'token_endpoint_auth_methods_supported': [
                      'private_key_jwt',
                    ],
                  }),
                );
              await request.response.close();
              break;
            case '/token':
              tokenRequests += 1;
              request.response.statusCode = HttpStatus.internalServerError;
              await request.response.close();
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
          }
        });

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
          clientSecret: 'configured-secret',
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$oauthPort/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 77, method: 'test/method'),
          ),
          throwsA(
            isA<UnauthorizedError>().having(
              (error) => error.message,
              'message',
              contains(
                'does not advertise a supported token endpoint '
                'authentication method',
              ),
            ),
          ),
        );
        expect(authProvider.authorizationUri, isNull);
        expect(tokenRequests, 0);
      });

      test('rejects unsupported dynamic registration auth methods', () async {
        final oauthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => oauthServer.close(force: true));
        final oauthPort = oauthServer.port;
        Map<String, dynamic>? registrationRequest;
        var tokenRequests = 0;

        oauthServer.listen((request) async {
          switch (request.uri.path) {
            case '/mcp':
              request.response
                ..statusCode = HttpStatus.unauthorized
                ..headers.set(
                  HttpHeaders.wwwAuthenticateHeader,
                  'Bearer resource_metadata="http://localhost:$oauthPort/.well-known/oauth-protected-resource/mcp"',
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-protected-resource/mcp':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'resource': 'http://localhost:$oauthPort/mcp',
                    'authorization_servers': [
                      'http://localhost:$oauthPort/auth',
                    ],
                  }),
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-authorization-server/auth':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'issuer': 'http://localhost:$oauthPort/auth',
                    'authorization_endpoint':
                        'http://localhost:$oauthPort/authorize',
                    'token_endpoint': 'http://localhost:$oauthPort/token',
                    'registration_endpoint':
                        'http://localhost:$oauthPort/register',
                    'code_challenge_methods_supported': ['S256'],
                    'token_endpoint_auth_methods_supported': [
                      'client_secret_post',
                    ],
                  }),
                );
              await request.response.close();
              break;
            case '/register':
              final body = await utf8.decoder.bind(request).join();
              registrationRequest = jsonDecode(body) as Map<String, dynamic>;
              request.response
                ..statusCode = HttpStatus.created
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'client_id': 'registered-client',
                    'client_secret': 'registered-secret',
                    'token_endpoint_auth_method': 'private_key_jwt',
                  }),
                );
              await request.response.close();
              break;
            case '/token':
              tokenRequests += 1;
              request.response.statusCode = HttpStatus.internalServerError;
              await request.response.close();
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
          }
        });

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
          clientSecret: 'configured-secret',
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:$oauthPort/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 78, method: 'test/method'),
          ),
          throwsA(
            isA<UnauthorizedError>().having(
              (error) => error.message,
              'message',
              contains(
                'unsupported token_endpoint_auth_method "private_key_jwt"',
              ),
            ),
          ),
        );
        expect(
          registrationRequest?['token_endpoint_auth_method'],
          'client_secret_post',
        );
        expect(authProvider.authorizationUri, isNull);
        expect(tokenRequests, 0);
      });

      test(
          'defaults omitted token endpoint auth metadata to client_secret_basic',
          () async {
        var tokenRequests = 0;
        String? tokenAuthorization;
        Map<String, String>? tokenForm;
        final oauthServer = await _startOAuthServerWithOmittedTokenAuthMetadata(
          onTokenRequest: (request) async {
            tokenRequests += 1;
            tokenAuthorization =
                request.headers.value(HttpHeaders.authorizationHeader);
            tokenForm = Uri.splitQueryString(
              await utf8.decoder.bind(request).join(),
            );
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'access_token': 'exchanged-token',
                  'token_type': 'Bearer',
                }),
              );
            await request.response.close();
          },
        );
        addTearDown(() => oauthServer.close(force: true));

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
          clientSecret: 'configured-secret',
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:${oauthServer.port}/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 79, method: 'test/method'),
          ),
          throwsA(isA<UnauthorizedError>()),
        );

        final authorizationUri = authProvider.authorizationUri;
        expect(authorizationUri, isNotNull);
        await oauthTransport.finishAuth(
          'auth-code',
          state: authorizationUri!.queryParameters['state'],
        );

        expect(tokenRequests, 1);
        expect(
          tokenAuthorization,
          'Basic ${base64Encode(utf8.encode('client-1:configured-secret'))}',
        );
        expect(tokenForm?['client_secret'], isNull);
        expect(authProvider.storedTokens?.accessToken, 'exchanged-token');
      });

      test('fails before redirect when omitted auth metadata needs a secret',
          () async {
        var tokenRequests = 0;
        final oauthServer = await _startOAuthServerWithOmittedTokenAuthMetadata(
          onTokenRequest: (request) async {
            tokenRequests += 1;
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          },
        );
        addTearDown(() => oauthServer.close(force: true));

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
        );
        final oauthTransport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:${oauthServer.port}/mcp'),
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        await expectLater(
          oauthTransport.send(
            const JsonRpcRequest(id: 80, method: 'test/method'),
          ),
          throwsA(
            isA<UnauthorizedError>().having(
              (error) => error.message,
              'message',
              contains(
                'requires client_secret_basic but no client secret is '
                'available',
              ),
            ),
          ),
        );
        expect(authProvider.authorizationUri, isNull);
        expect(tokenRequests, 0);
      });

      test('discovers metadata, redirects with PKCE, and exchanges tokens',
          () async {
        final oauthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => oauthServer.close(force: true));
        final oauthPort = oauthServer.port;
        final oauthUrl = Uri.parse('http://localhost:$oauthPort/mcp');
        var tokenExchangeSeen = false;

        oauthServer.listen((request) async {
          switch (request.uri.path) {
            case '/mcp':
              if (request.headers.value(HttpHeaders.authorizationHeader) ==
                  'Bearer exchanged-token') {
                request.response
                  ..statusCode = HttpStatus.ok
                  ..headers.contentType = ContentType.json
                  ..write(
                    jsonEncode(
                      const JsonRpcResponse(
                        id: 77,
                        result: {'ok': true},
                      ).toJson(),
                    ),
                  );
              } else {
                request.response
                  ..statusCode = HttpStatus.unauthorized
                  ..headers.set(
                    HttpHeaders.wwwAuthenticateHeader,
                    'Bearer resource_metadata="http://localhost:$oauthPort/.well-known/oauth-protected-resource/mcp", scope="tools:read"',
                  )
                  ..write('Unauthorized');
              }
              await request.response.close();
              break;
            case '/.well-known/oauth-protected-resource/mcp':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'resource': 'http://localhost:$oauthPort/mcp',
                    'authorization_servers': [
                      'http://localhost:$oauthPort/auth',
                    ],
                    'scopes_supported': ['tools:read'],
                  }),
                );
              await request.response.close();
              break;
            case '/.well-known/oauth-authorization-server/auth':
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'issuer': 'http://localhost:$oauthPort/auth',
                    'authorization_endpoint':
                        'http://localhost:$oauthPort/authorize',
                    'token_endpoint': 'http://localhost:$oauthPort/token',
                    'code_challenge_methods_supported': ['S256'],
                    'token_endpoint_auth_methods_supported': ['none'],
                  }),
                );
              await request.response.close();
              break;
            case '/token':
              final body = await utf8.decoder.bind(request).join();
              final form = Uri.splitQueryString(body);
              expect(form['grant_type'], 'authorization_code');
              expect(form['code'], 'auth-code');
              expect(form['client_id'], 'client-1');
              expect(form['redirect_uri'], 'http://localhost/callback');
              expect(form['resource'], 'http://localhost:$oauthPort/mcp');
              expect(form['code_verifier'], isNotEmpty);
              tokenExchangeSeen = true;
              request.response
                ..statusCode = HttpStatus.ok
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'access_token': 'exchanged-token',
                    'refresh_token': 'refresh-token',
                    'token_type': 'Bearer',
                    'expires_in': 3600.0,
                    'scope': 'tools:read',
                  }),
                );
              await request.response.close();
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
          }
        });

        final authProvider = DiscoveryOAuthClientProvider(
          redirectUri: Uri.parse('http://localhost/callback'),
        );
        final oauthTransport = StreamableHttpClientTransport(
          oauthUrl,
          opts: StreamableHttpClientTransportOptions(
            authProvider: authProvider,
          ),
        );
        addTearDown(oauthTransport.close);
        await oauthTransport.start();

        final request = const JsonRpcRequest(id: 77, method: 'test/method');
        await expectLater(
          oauthTransport.send(request),
          throwsA(isA<UnauthorizedError>()),
        );

        final authorizationUri = authProvider.authorizationUri;
        expect(authorizationUri, isNotNull);
        expect(authorizationUri!.path, '/authorize');
        expect(authorizationUri.queryParameters['response_type'], 'code');
        expect(authorizationUri.queryParameters['client_id'], 'client-1');
        expect(
          authorizationUri.queryParameters['redirect_uri'],
          'http://localhost/callback',
        );
        expect(
          authorizationUri.queryParameters['resource'],
          oauthUrl.toString(),
        );
        expect(authorizationUri.queryParameters['scope'], 'tools:read');
        expect(
          authorizationUri.queryParameters['code_challenge_method'],
          'S256',
        );
        expect(authorizationUri.queryParameters['code_challenge'], isNotEmpty);
        expect(authProvider.legacyRedirects, 0);

        await expectLater(
          oauthTransport.finishAuth('auth-code'),
          throwsA(
            isA<UnauthorizedError>().having(
              (error) => error.message,
              'message',
              contains('required state'),
            ),
          ),
        );
        expect(tokenExchangeSeen, isFalse);

        await expectLater(
          oauthTransport.finishAuth('auth-code', state: 'wrong-state'),
          throwsA(
            isA<UnauthorizedError>().having(
              (error) => error.message,
              'message',
              contains('state mismatch'),
            ),
          ),
        );
        expect(tokenExchangeSeen, isFalse);

        await oauthTransport.finishAuth(
          'auth-code',
          state: authorizationUri.queryParameters['state'],
        );
        expect(tokenExchangeSeen, isTrue);
        expect(authProvider.storedTokens?.accessToken, 'exchanged-token');
        expect(authProvider.storedTokens, isA<OAuthAuthorizationCodeTokens>());
        final storedTokens =
            authProvider.storedTokens as OAuthAuthorizationCodeTokens;
        expect(storedTokens.tokenType, 'Bearer');
        expect(storedTokens.expiresIn, 3600);
        expect(storedTokens.scope, 'tools:read');

        final completer = Completer<JsonRpcMessage>();
        oauthTransport.onmessage = completer.complete;
        await oauthTransport.send(request);
        final response = await completer.future.timeout(
          const Duration(seconds: 3),
        );
        expect(response, isA<JsonRpcResponse>());
        expect((response as JsonRpcResponse).result['ok'], isTrue);
      });
    });

    group('Error Handling and Edge Cases', () {
      test('handles finishAuth without auth provider', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        // Calling finishAuth without authProvider should throw
        expect(
          () async => await transport.finishAuth('test-code'),
          throwsA(isA<UnauthorizedError>()),
        );
      });

      test('start throws error if already started', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        // Starting again should throw
        expect(
          () async => await transport.start(),
          throwsA(isA<McpError>()),
        );
      });

      test('sessionId is tracked correctly', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        expect(transport.sessionId, isNull);

        // Only an initialize response can assign the session ID.
        await transport.send(
          const JsonRpcRequest(id: 1, method: 'initialize'),
        );

        await Future.delayed(const Duration(milliseconds: 500));

        // Session ID should be set from server
        expect(transport.sessionId, isNotNull);
      });

      test('terminateSession with no session does nothing', () async {
        transport = StreamableHttpClientTransport(serverUrl);
        await transport.start();

        // Should complete without error
        await transport.terminateSession();
        expect(true, isTrue);
      });

      test('stateless protocol does not send DELETE for session termination',
          () async {
        var deleteRequests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          if (request.method == 'DELETE') {
            deleteRequests += 1;
          }
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
        });

        transport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:${server.port}/mcp'),
          opts: const StreamableHttpClientTransportOptions(
            sessionId: 'legacy-session',
          ),
        );
        transport.protocolVersion = previewProtocolVersion;
        await transport.start();

        await transport.terminateSession();

        expect(deleteRequests, 0);
        expect(transport.sessionId, isNull);
      });

      test('stateless protocol does not open legacy GET SSE after initialized',
          () async {
        var getRequests = 0;
        var postRequests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          if (request.method == 'GET') {
            getRequests += 1;
            request.response.statusCode = HttpStatus.methodNotAllowed;
            await request.response.close();
            return;
          }

          if (request.method == 'POST') {
            postRequests += 1;
            request.response.statusCode = HttpStatus.accepted;
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        });

        transport = StreamableHttpClientTransport(
          Uri.parse('http://localhost:${server.port}/mcp'),
        );
        transport.protocolVersion = previewProtocolVersion;
        await transport.start();

        await transport.send(const JsonRpcInitializedNotification());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(postRequests, 1);
        expect(getRequests, 0);
      });

      test('handles error callback configuration', () async {
        transport = StreamableHttpClientTransport(serverUrl);

        transport.onerror = (error) {
          // Error callback configured
        };

        await transport.start();

        // Error callback should be configured
        expect(transport.onerror, isNotNull);
      });

      test('handles onclose callback configuration', () async {
        transport = StreamableHttpClientTransport(serverUrl);

        var oncloseCalled = false;
        transport.onclose = () {
          oncloseCalled = true;
        };

        await transport.start();
        await transport.close();

        expect(oncloseCalled, isTrue);
      });
    });
  });
}
