# Authentication examples

These examples show how MCP Streamable HTTP authentication fits into a Dart
client or resource server. They are learning aids, not reusable identity or
credential-storage implementations.

> [!WARNING]
> The client examples use plaintext token files for local testing. Never ship
> those stores. Use a system keychain, platform secure storage, or an encrypted
> credential service.

## Choose an example

| Example | What it demonstrates | Important limit |
| --- | --- | --- |
| [`github_oauth_example.dart`](github_oauth_example.dart) | Browser authorization, PKCE S256, a localhost callback, state validation, token exchange, and MCP tool discovery | Provider-specific and plaintext storage |
| [`oauth_client_example.dart`](oauth_client_example.dart) | Generic PKCE request, callback-state validation, token exchange, refresh, and storage building blocks | Does not host a callback or target a real provider |
| [`oauth_server_example.dart`](oauth_server_example.dart) | Protected-resource metadata, bearer challenges, and a fail-closed authentication callback | Accepts one static local test token; it is not an authorization server |
| [`github_pat_example.dart`](github_pat_example.dart) | Supplying an existing GitHub token through `OAuthClientProvider` | Intended for local/personal testing |

## GitHub browser flow

Create a GitHub OAuth app whose callback is
`http://localhost:8080/callback`, then export its credentials:

```bash
export GITHUB_CLIENT_ID=your_client_id
export GITHUB_CLIENT_SECRET=your_client_secret
dart run example/authentication/github_oauth_example.dart
```

The example opens an authorization URL, listens on localhost, validates the
returned state, exchanges the code with its private PKCE verifier, stores the token in
`.github_oauth_tokens.json`, connects to the configured MCP endpoint, and lists
tools. It never prints the access token.

See [GITHUB_SETUP.md](GITHUB_SETUP.md) for setup and troubleshooting.

## Generic client building blocks

The generic example prepares an authorization request with PKCE S256 and the
MCP `resource` parameter. It persists the verifier privately and requires the
callback state when exchanging the returned code:

```dart
final request = await provider.createAuthorizationRequest();

// Your application opens request.authorizationUri and receives its callback.
final tokens = await provider.exchangeCodeForTokens(
  authorizationCode,
  state: returnedState,
);
```

The example deliberately does not implement the application-specific callback
listener or browser integration. Do not log `request.codeVerifier`.

For MCP discovery managed by the transport, implement
`OAuthAuthorizationCodeProvider`. `StreamableHttpClientTransport` can then
discover protected-resource and authorization-server metadata, build the PKCE
request, and exchange the callback code through
`finishAuth(code, state: returnedState)`. Cross-origin authorization servers
must be approved with a narrow `oauthUriValidator`; see the
[transport guide](../../doc/transports.md#streamable-http-authentication).

## Protected resource server

The server example uses the current high-level hooks:

- `OAuthProtectedResourceOptions` publishes protected-resource metadata.
- `authenticationHandler` returns allow, unauthorized, or insufficient-scope.
- The SDK formats the corresponding `WWW-Authenticate` challenge.

Run the local static-token demonstration:

```bash
export MCP_BEARER_TOKEN=local-secret
export MCP_AUTHORIZATION_SERVER=https://auth.example.com
dart run example/authentication/oauth_server_example.dart
```

This token is only a deterministic local fixture. A production resource server
must replace the equality check with signature verification or token
introspection and validate issuer, audience/resource, expiry, and scopes.

See [OAUTH_QUICK_START.md](OAUTH_QUICK_START.md) for a local smoke test and
[OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md) for the production boundary.

## Personal access token

```bash
export GITHUB_TOKEN=your_token
dart run example/authentication/github_pat_example.dart
```

Prefer the smallest permissions that support the operations you intend to run.
Never pass a token as a command-line argument on shared systems, because process
lists and shell history can expose it.

## Production checklist

- Use HTTPS and explicit `Host`/`Origin` allowlists.
- Keep client secrets and access tokens out of source control and logs.
- Use cryptographic randomness, PKCE S256, and exact redirect URI matching.
- Validate access-token signature or introspection, issuer, resource audience,
  expiry, and scopes at the resource server.
- Return `401` for missing or invalid credentials and `403` with
  `insufficient_scope` only for a valid token that lacks permission.
- Keep authorization-server responsibilities separate from the MCP resource
  server unless your application intentionally implements both roles.

The transport details and executable coverage are documented in
[`doc/transports.md`](../../doc/transports.md#streamable-http-authentication).
