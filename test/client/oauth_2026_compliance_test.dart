import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/client/oauth_client_platform_native.dart'
    as native_platform;
import 'package:mcp_dart/src/client/oauth_client_platform_web.dart'
    as web_platform;
import 'package:mcp_dart/src/client/streamable_https.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

class _LegacyStartSseOptions implements StartSseOptions {
  @override
  final String? resumptionToken;

  @override
  final void Function(String token)? onResumptionToken;

  @override
  final dynamic replayMessageId;

  @override
  final bool shouldReconnect;

  const _LegacyStartSseOptions({
    this.resumptionToken,
    this.onResumptionToken,
    this.replayMessageId,
    this.shouldReconnect = true,
  });
}

class _OAuthProvider implements OAuthAuthorizationCodeProvider {
  @override
  final String clientId;

  @override
  final String? clientSecret;

  @override
  final Uri redirectUri;

  OAuthTokens? storedTokens;
  Uri? authorizationUri;

  _OAuthProvider({
    required this.clientId,
    required this.redirectUri,
    this.clientSecret,
  });

  @override
  List<String> get scopes => const [];

  @override
  Future<void> redirectToAuthorization() async {}

  @override
  Future<void> redirectToAuthorizationUrl(Uri authorizationUri) async {
    this.authorizationUri = authorizationUri;
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    storedTokens = tokens;
  }

  @override
  Future<OAuthTokens?> tokens() async => storedTokens;
}

void main() {
  test('StartSseOptions retains the v2.2.2 implicit interface', () {
    final options = _LegacyStartSseOptions(
      resumptionToken: 'cursor',
      onResumptionToken: expectAsync1((token) => expect(token, 'next')),
      replayMessageId: 1,
      shouldReconnect: false,
    );

    expect(options.resumptionToken, 'cursor');
    expect(options.replayMessageId, 1);
    expect(options.shouldReconnect, isFalse);
    options.onResumptionToken?.call('next');
  });

  test('native and browser DCR platform helpers declare the right type', () {
    expect(native_platform.platformOAuthClientApplicationType, 'native');
    expect(web_platform.platformOAuthClientApplicationType, 'web');
  });

  test('protected-resource metadata requires authorization servers', () {
    expect(
      () => OAuthProtectedResourceMetadataDocument.fromJson({
        'resource': 'https://mcp.example/mcp',
        'authorization_servers': const [],
      }),
      throwsFormatException,
    );
    expect(
      () => OAuthProtectedResourceMetadataDocument.fromJson({
        'resource': 'https://mcp.example/mcp',
        'authorization_servers': const ['/relative-issuer'],
      }),
      throwsFormatException,
    );
    expect(
      () => OAuthProtectedResourceMetadataDocument.fromJson({
        'resource': 'https://mcp.example/mcp',
        'authorization_servers': const [7],
      }),
      throwsFormatException,
    );
  });

  test('protected-resource authorization servers remain growable and mutable',
      () {
    final metadata = OAuthProtectedResourceMetadataDocument.fromJson({
      'resource': 'https://mcp.example/mcp',
      'authorization_servers': const ['https://auth.example'],
    });

    metadata.authorizationServers[0] =
        Uri.parse('https://replacement-auth.example');
    metadata.authorizationServers.add(Uri.parse('https://backup-auth.example'));

    expect(
      metadata.authorizationServers,
      [
        Uri.parse('https://replacement-auth.example'),
        Uri.parse('https://backup-auth.example'),
      ],
    );
  });

  test('insufficient-scope authorization unions persisted token scope',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final port = server.port;
    String? authorizationHeader;
    server.listen((request) async {
      switch (request.uri.path) {
        case '/mcp':
          authorizationHeader =
              request.headers.value(HttpHeaders.authorizationHeader);
          request.response
            ..statusCode = HttpStatus.forbidden
            ..headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer error="insufficient_scope", scope="files:write", '
              'resource_metadata="http://localhost:$port/'
              '.well-known/oauth-protected-resource/mcp"',
            );
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
                'token_endpoint_auth_methods_supported': ['none'],
              }),
            );
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          break;
      }
      await request.response.close();
    });

    final provider = _OAuthProvider(
      clientId: 'pre-registered-client',
      redirectUri: Uri.parse('http://localhost/callback'),
    )..storedTokens = OAuthAuthorizationCodeTokens(
        accessToken: 'old-token',
        scope: 'files:read',
      );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:$port/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(transport.close);
    await transport.start();

    await expectLater(
      transport.send(const JsonRpcRequest(id: 7, method: 'test/method')),
      throwsA(isA<UnauthorizedError>()),
    );

    expect(authorizationHeader, 'Bearer old-token');
    expect(
      provider.authorizationUri?.queryParameters['scope']?.split(' '),
      unorderedEquals(['files:read', 'files:write']),
    );
  });

  test('preserves exact issuer identity during metadata validation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final port = server.port;
    server.listen((request) async {
      switch (request.uri.path) {
        case '/mcp':
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer resource_metadata="http://localhost:$port/'
              '.well-known/oauth-protected-resource/mcp"',
            );
          break;
        case '/.well-known/oauth-protected-resource/mcp':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'resource': 'http://localhost:$port/mcp',
                'authorization_servers': ['http://LOCALHOST:$port/auth'],
              }),
            );
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
                'token_endpoint_auth_methods_supported': ['none'],
              }),
            );
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          break;
      }
      await request.response.close();
    });

    final provider = _OAuthProvider(
      clientId: 'pre-registered-client',
      redirectUri: Uri.parse('http://localhost/callback'),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:$port/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(transport.close);
    await transport.start();

    await expectLater(
      transport.send(const JsonRpcRequest(id: 1, method: 'test/method')),
      throwsA(
        isA<UnauthorizedError>().having(
          (error) => error.message,
          'message',
          contains('does not exactly match'),
        ),
      ),
    );
    expect(provider.authorizationUri, isNull);
  });

  test('rejects a non-loopback plaintext redirect URI before discovery',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
      await request.response.close();
    });

    final provider = _OAuthProvider(
      clientId: 'pre-registered-client',
      redirectUri: Uri.parse('http://client.example/callback'),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:${server.port}/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(transport.close);
    await transport.start();

    await expectLater(
      transport.send(const JsonRpcRequest(id: 2, method: 'test/method')),
      throwsA(
        isA<UnauthorizedError>().having(
          (error) => error.message,
          'message',
          contains('redirect URI must use HTTPS or loopback HTTP'),
        ),
      ),
    );
  });

  test('does not reuse pre-registered credentials after issuer migration',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final port = server.port;
    var issuerName = 'auth-a';
    server.listen((request) async {
      switch (request.uri.path) {
        case '/mcp':
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer resource_metadata="http://localhost:$port/'
              '.well-known/oauth-protected-resource/mcp"',
            );
          break;
        case '/.well-known/oauth-protected-resource/mcp':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'resource': 'http://localhost:$port/mcp',
                'authorization_servers': [
                  'http://localhost:$port/$issuerName',
                ],
              }),
            );
          break;
        case '/.well-known/oauth-authorization-server/auth-a':
        case '/.well-known/oauth-authorization-server/auth-b':
          final issuer = request.uri.path.endsWith('auth-a')
              ? 'http://localhost:$port/auth-a'
              : 'http://localhost:$port/auth-b';
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'issuer': issuer,
                'authorization_endpoint': 'http://localhost:$port/authorize',
                'token_endpoint': 'http://localhost:$port/token',
                'code_challenge_methods_supported': ['S256'],
                'token_endpoint_auth_methods_supported': ['none'],
              }),
            );
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          break;
      }
      await request.response.close();
    });

    final provider = _OAuthProvider(
      clientId: 'pre-registered-client',
      redirectUri: Uri.parse('http://localhost/callback'),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:$port/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(transport.close);
    await transport.start();

    await expectLater(
      transport.send(const JsonRpcRequest(id: 4, method: 'test/method')),
      throwsA(isA<UnauthorizedError>()),
    );
    issuerName = 'auth-b';
    final migratedTransport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:$port/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(migratedTransport.close);
    await migratedTransport.start();
    await expectLater(
      migratedTransport.send(
        const JsonRpcRequest(id: 5, method: 'test/method'),
      ),
      throwsA(
        isA<UnauthorizedError>().having(
          (error) => error.message,
          'message',
          allOf(contains('bound to'), contains('cannot be reused')),
        ),
      ),
    );
  });

  test('does not send issuer-bound tokens to another resource', () async {
    final provider = _OAuthProvider(
      clientId: 'pre-registered-client',
      redirectUri: Uri.parse('https://client.example/callback'),
    )..storedTokens = OAuthIssuerBoundAuthorizationCodeTokens(
        accessToken: 'bound-token',
        authorizationServerIssuer: 'https://auth.example',
        resource: Uri.parse('https://mcp.example/mcp'),
      );
    final transport = StreamableHttpClientTransport(
      Uri.parse('https://other.example/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(transport.close);
    await transport.start();

    await expectLater(
      transport.send(const JsonRpcRequest(id: 6, method: 'test/method')),
      throwsA(
        isA<UnauthorizedError>().having(
          (error) => error.message,
          'message',
          contains('different protected resource'),
        ),
      ),
    );
  });

  test('form-encodes client_secret_basic credentials before Base64', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final port = server.port;
    String? tokenAuthorization;
    server.listen((request) async {
      switch (request.uri.path) {
        case '/mcp':
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Bearer resource_metadata="http://localhost:$port/'
              '.well-known/oauth-protected-resource/mcp"',
            );
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
                'token_endpoint_auth_methods_supported': [
                  'client_secret_basic',
                ],
              }),
            );
          break;
        case '/token':
          tokenAuthorization =
              request.headers.value(HttpHeaders.authorizationHeader);
          await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'access_token': 'access-token',
                'token_type': 'Bearer',
              }),
            );
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          break;
      }
      await request.response.close();
    });

    const clientId = 'client: id';
    const clientSecret = r'secret:% value';
    final provider = _OAuthProvider(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: Uri.parse('http://localhost/callback'),
    );
    final transport = StreamableHttpClientTransport(
      Uri.parse('http://localhost:$port/mcp'),
      opts: StreamableHttpClientTransportOptions(authProvider: provider),
    );
    addTearDown(transport.close);
    await transport.start();

    await expectLater(
      transport.send(const JsonRpcRequest(id: 3, method: 'test/method')),
      throwsA(isA<UnauthorizedError>()),
    );
    expect(provider.authorizationUri, isNotNull);
    // v2.2.2 callers may continue to validate the redirect independently and
    // exchange the authorization code through the exact legacy signature.
    // ignore: deprecated_member_use_from_same_package
    await transport.finishAuth('authorization-code');

    expect(
      tokenAuthorization,
      'Basic ${base64Encode(utf8.encode('client%3A+id:secret%3A%25+value'))}',
    );
    expect(
      provider.storedTokens,
      isA<OAuthIssuerBoundAuthorizationCodeTokens>(),
    );
    final tokens =
        provider.storedTokens as OAuthIssuerBoundAuthorizationCodeTokens;
    expect(tokens.authorizationServerIssuer, 'http://localhost:$port/auth');
    expect(tokens.resource.toString(), 'http://localhost:$port/mcp');
  });
}
