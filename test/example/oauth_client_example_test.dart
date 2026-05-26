import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

import '../../example/authentication/oauth_client_example.dart';

void main() {
  group('OAuth client example PKCE flow', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mcp_oauth_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('builds authorization request with PKCE S256 and resource', () async {
      final storage = TokenStorage('${tempDir.path}/tokens.json');
      final config = _oauthConfig(
        authorizationEndpoint: Uri.parse(
          'https://auth.example.com/authorize?tenant=acme',
        ),
      );
      final provider = OAuth2Provider(config: config, storage: storage);

      final request = await provider.createAuthorizationRequest();
      final query = request.authorizationUri.queryParameters;

      expect(request.authorizationUri.toString(), isNot(contains(':443')));
      expect(query['tenant'], 'acme');
      expect(query['client_id'], config.clientId);
      expect(query['response_type'], 'code');
      expect(query['redirect_uri'], config.redirectUri.toString());
      expect(query['scope'], 'mcp.read mcp.write');
      expect(query['state'], request.state);
      expect(query['code_challenge_method'], 'S256');
      expect(query['resource'], config.serverUri);
      expect(await storage.getCodeVerifier(), request.codeVerifier);
      expect(await storage.getState(), request.state);
      expect(request.codeVerifier.length, greaterThanOrEqualTo(43));
      expect(
        request.codeChallenge,
        _pkceS256Challenge(request.codeVerifier),
      );
    });

    test('exchanges authorization code with PKCE verifier and resource',
        () async {
      final tokenEndpoint = await _TokenEndpoint.start();
      addTearDown(tokenEndpoint.close);

      final storage = TokenStorage('${tempDir.path}/tokens.json');
      final config = _oauthConfig(tokenEndpoint: tokenEndpoint.uri);
      final provider = OAuth2Provider(config: config, storage: storage);
      final authRequest = await provider.createAuthorizationRequest();

      final tokens = await provider.exchangeCodeForTokens('auth-code');

      expect(tokens, isNotNull);
      expect(tokens!.accessToken, 'access-token');
      expect(tokens.refreshToken, 'refresh-token');
      expect(await storage.getCodeVerifier(), isNull);

      final storedTokens = await storage.loadTokens();
      expect(storedTokens?.accessToken, 'access-token');

      expect(tokenEndpoint.lastForm, isNotNull);
      expect(
        tokenEndpoint.lastForm,
        containsPair('grant_type', 'authorization_code'),
      );
      expect(
        tokenEndpoint.lastForm,
        containsPair('code', 'auth-code'),
      );
      expect(
        tokenEndpoint.lastForm,
        containsPair('redirect_uri', config.redirectUri.toString()),
      );
      expect(
        tokenEndpoint.lastForm,
        containsPair('client_id', config.clientId),
      );
      expect(
        tokenEndpoint.lastForm,
        containsPair('client_secret', config.clientSecret),
      );
      expect(
        tokenEndpoint.lastForm,
        containsPair('code_verifier', authRequest.codeVerifier),
      );
      expect(
        tokenEndpoint.lastForm,
        containsPair('resource', config.serverUri),
      );
    });
  });
}

OAuthConfig _oauthConfig({
  Uri? authorizationEndpoint,
  Uri? tokenEndpoint,
}) {
  return OAuthConfig(
    clientId: 'client-id',
    clientSecret: 'client-secret',
    authorizationEndpoint: authorizationEndpoint ??
        Uri.parse('https://auth.example.com/authorize'),
    tokenEndpoint: tokenEndpoint ?? Uri.parse('https://auth.example.com/token'),
    scopes: const ['mcp.read', 'mcp.write'],
    redirectUri: Uri.parse('http://localhost:8080/callback'),
    serverUri: 'https://mcp.example.com/mcp',
  );
}

String _pkceS256Challenge(String verifier) {
  final digest = crypto.sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

class _TokenEndpoint {
  final HttpServer _server;
  Map<String, String>? lastForm;

  _TokenEndpoint._(this._server);

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/token');

  static Future<_TokenEndpoint> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = _TokenEndpoint._(server);
    server.listen(endpoint._handleRequest);
    return endpoint;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/token') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final body = await utf8.decodeStream(request);
    lastForm = Uri.splitQueryString(body);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_in': 3600,
        }),
      );
    await request.response.close();
  }
}
