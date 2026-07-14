# Protected-resource quick start

This smoke test exercises the MCP server's protected-resource metadata and
bearer challenge without pretending to run an OAuth authorization server.

## Start the local server

```bash
export MCP_BEARER_TOKEN=local-secret
export MCP_AUTHORIZATION_SERVER=https://auth.example.com
dart run example/authentication/oauth_server_example.dart
```

The endpoint is `http://localhost:3000/mcp`. The static token is a local fixture
only.

## Inspect metadata

```bash
curl http://localhost:3000/.well-known/oauth-protected-resource/mcp
```

The JSON document identifies the MCP resource, authorization server, bearer
method, and supported scope.

## Inspect the challenge

Send an unauthenticated request:

```bash
curl -i -X POST http://localhost:3000/mcp
```

The response is `401 Unauthorized` and its `WWW-Authenticate` header includes
the protected-resource metadata URL and required scope. Supplying an exact
`Authorization: Bearer local-secret` header passes the authentication callback;
the request must still be a valid MCP request to receive an MCP result.

## Use a different public resource URI

When testing reverse-proxy metadata locally, set the public URI explicitly:

```bash
export MCP_RESOURCE_URI=https://mcp.example.com/mcp
export MCP_AUTHORIZATION_SERVER=https://auth.example.com
export MCP_SCOPE=tools:read
```

The server still binds to localhost. These values only change published
metadata and challenges.

## Next step

Replace the static comparison with a verifier that checks token signature or
introspection, issuer, exact resource audience, expiry, and scopes. See
[OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md).
