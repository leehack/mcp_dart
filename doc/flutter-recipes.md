# Flutter Host and Client Recipes

`mcp_dart` can be used from Flutter apps as an MCP client, host, or local server wrapper. The right transport and lifecycle pattern depends on the target platform.

## Platform decision table

| Flutter target | Recommended transport | Notes |
| --- | --- | --- |
| Web | `StreamableHttpClientTransport` | Browser apps cannot spawn stdio processes. Serve MCP over HTTPS/Streamable HTTP and configure CORS/Origin controls. |
| Mobile | `StreamableHttpClientTransport` for remote servers; platform channels or app-managed processes for local helpers | Mobile apps should keep tokens in secure storage and reconnect on foreground/resume. |
| Desktop | `StdioClientTransport` for local helper processes; Streamable HTTP for remote services | Desktop hosts can launch local MCP servers, but must clean up child processes when windows close. |
| Tests/in-process demos | IO stream/custom transport | Useful for widget tests and integration harnesses that should not bind real ports. |

See the runnable Flutter web client in [`example/flutter_http_client/`](../example/flutter_http_client/) and the transport overview in [`doc/transports.md`](transports.md).

## Recipe: Flutter Web client for a Streamable HTTP server

Use Streamable HTTP for Flutter Web. Keep connection state in a service object and expose simple methods to the UI.

```dart
class McpClientController extends ChangeNotifier {
  McpClient? _client;
  StreamableHttpClientTransport? _transport;

  Future<void> connect(Uri serverUri) async {
    final client = McpClient(
      const Implementation(name: 'flutter-host', version: '1.0.0'),
      options: const McpClientOptions(protocol: McpProtocol.stable),
    );
    final transport = StreamableHttpClientTransport(serverUri);

    await client.connect(transport);

    _client = client;
    _transport = transport;
    notifyListeners();
  }

  Future<List<Tool>> listTools() async {
    final client = _client;
    if (client == null) {
      throw StateError('MCP client is not connected');
    }
    return (await client.listTools()).tools;
  }

  Future<void> disconnect() async {
    await _client?.close();
    _client = null;
    _transport = null;
    notifyListeners();
  }
}
```

Browser deployment checklist:

- Serve the MCP endpoint over HTTPS in production.
- Enable only the origins that should embed or call the server.
- Do not store bearer tokens in plain local storage; prefer short-lived tokens and platform/browser secure storage patterns where available.
- Surface connection errors in the UI so users can distinguish CORS, authentication, and MCP protocol failures.

## Recipe: Desktop Flutter host launching a local stdio server

Desktop apps can act as MCP hosts by spawning a server process over stdio.

```dart
final client = McpClient(
  const Implementation(name: 'desktop-host', version: '1.0.0'),
);

final transport = StdioClientTransport(
  const StdioServerParameters(
    command: 'dart',
    args: ['run', 'bin/my_mcp_server.dart'],
  ),
);

try {
  await client.connect(transport);
  final tools = await client.listTools();
  // Render tools in your Flutter UI.
} finally {
  await client.close(); // Also terminates the spawned stdio process.
}
```

Desktop lifecycle notes:

- Close the client when the window/app closes so the child process exits.
- Send server logs to stderr, not stdout; stdout is reserved for MCP JSON-RPC messages.
- Treat server executable paths as configuration, not hard-coded user-specific paths.

## Recipe: Mobile client for a remote MCP service

Mobile apps normally connect to remote MCP servers through Streamable HTTP. Put token acquisition and persistence behind a small auth provider/service boundary.

```dart
final transport = StreamableHttpClientTransport(
  Uri.parse('https://api.example.com/mcp'),
  opts: StreamableHttpClientTransportOptions(
    authProvider: authProvider,
  ),
);

final client = McpClient(
  const Implementation(name: 'mobile-client', version: '1.0.0'),
);

await client.connect(transport);
```

Mobile checklist:

- Use secure storage for refresh tokens and user-specific credentials.
- Cancel or pause long-running requests when the app enters the background if the result is no longer useful.
- Reconnect after network changes and app resume; session IDs can become stale.
- Keep tool invocations explicit in the UI when tools have side effects.

## Recipe: Host-side notifications and UI updates

Register notification handlers before connecting or immediately after client construction so UI state is ready for server events.

```dart
client.setNotificationHandler(
  'notifications/message',
  (notification) async {
    final params = notification.logParams;
    messages.add('${params.level}: ${params.data}');
    notifyListeners();
  },
  (params, meta) {
    if (params == null) {
      throw const FormatException(
        'Missing params for logging message notification',
      );
    }

    return JsonRpcLoggingMessageNotification(
      logParams: LoggingMessageNotification.fromJson(params),
      meta: meta,
    );
  },
);
```

The Flutter example service at [`example/flutter_http_client/lib/services/streamable_mcp_service.dart`](../example/flutter_http_client/lib/services/streamable_mcp_service.dart) shows a fuller ChangeNotifier-based pattern for connection state, notifications, tools, prompts, and resources.

## Recipe: Authentication and OAuth callbacks

For OAuth-protected remote servers, keep the OAuth flow outside widget code:

1. Create an `OAuthClientProvider` implementation or reuse one of the patterns in [`example/authentication/`](../example/authentication/). For MCP OAuth discovery, also implement `OAuthAuthorizationCodeProvider` so the transport can build the authorization URL and token exchange from server metadata.
2. Store tokens through a platform-appropriate secure storage layer.
3. Pass the provider to `StreamableHttpClientTransportOptions(authProvider: ...)`. If the authorization server uses a different origin, also supply a narrow `oauthUriValidator` that accepts only its expected HTTPS host.
4. Extract the authorization `code` and `state` from the browser/deep-link callback, then call `await transport.finishAuth(code, state: state, issuer: iss);`. Pass `iss` when the callback includes it. Missing or mismatched state is rejected before token exchange. If you disposed the transport after the failed attempt, recreate it with the same `authProvider` first.

For local development, a loopback callback can be convenient. For production mobile apps, prefer platform deep links/universal links and PKCE.

## Testing checklist

- Unit-test the service/controller without Flutter widgets where possible.
- Widget-test disconnected, connecting, connected, error, and notification states.
- For web, run at least one browser smoke test against a local Streamable HTTP server.
- For desktop stdio hosts, verify child process cleanup after `client.close()`.
- For auth flows, test expired-token and denied-consent paths, not only the happy path.

From the repository root, the checked-in Flutter Web example has a real Chrome
service integration that covers repeated tool requests, RPC-error recovery,
reconnect, and disconnect against the MCP 2026-07-28 conformance server. Its
ordinary Flutter test suite covers UI behavior with widget tests:

```bash
dart run tool/testing/run_flutter_web_example_e2e.dart
```
