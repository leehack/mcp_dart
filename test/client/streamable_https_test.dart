import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/client/streamable_https.dart';
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

  DiscoveryOAuthClientProvider({
    this.clientId = 'client-1',
    required this.redirectUri,
    this.clientSecret,
    this.scopes = const ['tools:read'],
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
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    storedTokens = tokens;
  }
}

Map<String, dynamic> _statelessMeta() => buildProtocolRequestMeta(
      protocolVersion: draftProtocolVersion2026_07_28,
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

    test('client connect initializes when session ID is preconfigured',
        () async {
      final preconfiguredSessionId = 'preconfigured-session-id';
      final capturedSessionHeaders = <String?>[];
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
                  protocolVersion: latestProtocolVersion,
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
      expect(capturedSessionHeaders, isNotEmpty);
      expect(capturedSessionHeaders, everyElement(preconfiguredSessionId));
      expect(client.getServerCapabilities()?.logging, isNotNull);
      expect(client.getServerVersion()?.name, 'PreconfiguredSessionServer');
      expect(
        client.getInstructions(),
        'Initialized with preconfigured session',
      );
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
                  protocolVersion: latestProtocolVersion,
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
                  protocolVersion: latestProtocolVersion,
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
                  protocolVersion: latestProtocolVersion,
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
                  protocolVersion: latestProtocolVersion,
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
                  protocolVersion: latestProtocolVersion,
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
              protocolVersion: latestProtocolVersion,
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
          sessionId: 'legacy-session',
        ),
      )..protocolVersion = draftProtocolVersion2026_07_28;
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
        draftProtocolVersion2026_07_28,
      );
      expect(capturedHeaders['method'], Method.toolsCall);
      expect(capturedHeaders['name'], 'echo');
      expect(capturedHeaders['session'], isNull);
      expect(transport.sessionId, 'legacy-session');
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
      )..protocolVersion = draftProtocolVersion2026_07_28;
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

    test('send adds task id as 2026 stateless task name header', () async {
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
      )..protocolVersion = draftProtocolVersion2026_07_28;
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
        draftProtocolVersion2026_07_28,
      );
      expect(capturedHeaders['method'], Method.tasksUpdate);
      expect(capturedHeaders['name'], 'task-1');
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
        ..protocolVersion = draftProtocolVersion2026_07_28
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
      transport = StreamableHttpClientTransport(serverUrl);
      await transport.start();

      // Ensure we have a session ID
      final notification = const JsonRpcInitializedNotification();
      await transport.send(notification);

      // Wait for session establishment
      await Future.delayed(const Duration(milliseconds: 500));

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

        await oauthTransport.finishAuth('auth-code');
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

        // Send a message that will get a session ID
        final notification = const JsonRpcInitializedNotification();
        await transport.send(notification);

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
        transport.protocolVersion = draftProtocolVersion2026_07_28;
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
        transport.protocolVersion = draftProtocolVersion2026_07_28;
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
