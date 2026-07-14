/// Local protected-resource example for MCP Streamable HTTP.
///
/// The SDK publishes OAuth Protected Resource Metadata and bearer challenges;
/// the application remains responsible for validating access tokens. This
/// example deliberately accepts one exact, pre-provisioned token from the
/// environment so the HTTP behavior can be exercised without pretending to be
/// an authorization server.
///
/// Do not deploy this static-token validator. Production code must validate a
/// token's signature or introspection response, issuer, audience/resource,
/// expiry, and required scopes with a trusted authorization server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

const _defaultPort = 3000;
const _defaultScope = 'tools:read';

/// Returns whether [authorization] contains exactly [expectedToken].
///
/// This helper exists only for the local static-token example. It fails closed
/// for missing, malformed, or empty credentials.
bool isExpectedBearerToken(String? authorization, String expectedToken) {
  if (expectedToken.isEmpty || authorization == null) {
    return false;
  }
  return _constantTimeEquals(authorization, 'Bearer $expectedToken');
}

bool _constantTimeEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  final length = leftBytes.length > rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  var difference = leftBytes.length ^ rightBytes.length;

  for (var index = 0; index < length; index++) {
    final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
    final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= leftByte ^ rightByte;
  }

  return difference == 0;
}

McpServer createProtectedMcpServer() {
  final server = McpServer(
    const Implementation(name: 'oauth-resource-example', version: '1.0.0'),
  );

  server.registerTool(
    'greet',
    description: 'Return a greeting for the supplied name.',
    inputSchema: JsonSchema.object(
      properties: {
        'name': JsonSchema.string(description: 'Name to greet'),
      },
      required: ['name'],
    ),
    callback: (arguments, extra) async {
      final name = arguments['name'] as String? ?? 'world';
      return CallToolResult.fromContent(
        [TextContent(text: 'Hello, $name!')],
      );
    },
  );

  return server;
}

Future<void> main() async {
  final expectedToken = Platform.environment['MCP_BEARER_TOKEN'];
  if (expectedToken == null || expectedToken.isEmpty) {
    stderr.writeln('Set MCP_BEARER_TOKEN to a local development token.');
    exitCode = 64;
    return;
  }

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? _defaultPort;
  final resource = Uri.parse(
    Platform.environment['MCP_RESOURCE_URI'] ?? 'http://localhost:$port/mcp',
  );
  final authorizationServer = Uri.parse(
    Platform.environment['MCP_AUTHORIZATION_SERVER'] ??
        'https://auth.example.com',
  );
  final scope = Platform.environment['MCP_SCOPE'] ?? _defaultScope;

  if (!resource.isAbsolute ||
      resource.path.isEmpty ||
      resource.path == '/' ||
      !authorizationServer.isAbsolute) {
    stderr.writeln(
      'MCP_RESOURCE_URI must be an absolute endpoint URI, and '
      'MCP_AUTHORIZATION_SERVER must be absolute.',
    );
    exitCode = 64;
    return;
  }

  final metadataUri = resource.replace(
    path: '/.well-known/oauth-protected-resource${resource.path}',
    query: null,
    fragment: null,
  );

  final server = StreamableMcpServer(
    serverFactory: (sessionId) => createProtectedMcpServer(),
    host: 'localhost',
    port: port,
    path: resource.path,
    authenticationHandler: (request) {
      final authorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      if (isExpectedBearerToken(authorization, expectedToken)) {
        return const StreamableMcpAuthenticationResult.allow();
      }
      return const StreamableMcpAuthenticationResult.unauthorized(
        errorDescription: 'A valid bearer token is required',
      );
    },
    oauthProtectedResource: OAuthProtectedResourceOptions(
      metadata: OAuthProtectedResourceMetadata(
        resource: resource,
        authorizationServers: [authorizationServer],
        scopesSupported: [scope],
      ),
      metadataUri: metadataUri,
      scope: scope,
    ),
  );

  await server.start();
  stdout.writeln('Protected MCP endpoint: $resource');
  stdout.writeln('Protected-resource metadata: $metadataUri');
  stdout.writeln(
    'Local-only static token validation is enabled. '
    'Use a real token verifier in production.',
  );

  await Completer<void>().future;
}
