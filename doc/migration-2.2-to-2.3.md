# Upgrading from mcp_dart 2.2 to 2.3

This guide covers applications upgrading from the latest `2.2` patch,
`mcp_dart 2.2.2`, to `mcp_dart 2.3`. Projects still on `2.2.0` or `2.2.1`
also receive the fixes documented in the intervening changelog entries.

## Short version

Most applications can update the package constraint without changing source
code. The 2.3 SDK preserves the 2.2.2 registration callbacks, public
interfaces, subclass overrides, request metadata, logging helpers, and
`StartSseOptions` API.

The automated public API comparison and checked-in compile fixtures report no
known source incompatibility in the stable 2.2.2 API. This does not cover
imports from undeclared transitive dependencies or reliance on permissive
runtime behavior.

The upgrade is source-compatible, but some defaults and validation behavior
change:

| Area | What changes in 2.3 |
| --- | --- |
| Dart SDK | The SDK requires Dart 3.4 or newer. The separate `mcp_dart_cli` package requires Dart 3.12; SDK-only applications do not inherit that requirement. |
| HTTP dependency | `mcp_dart` requires `http ^1.5.0`. Normal `^1.4.0` constraints remain compatible, but pins below 1.5 must be updated. |
| Protocol negotiation | Clients and servers default to `McpProtocol.stable`, which prefers MCP 2026-07-28 and falls back to legacy initialization. |
| Stdio recovery | Stateless stdio clients restart an unexpectedly terminated child by default. |
| Validation | OAuth metadata, JSON Schema, structured tool results, and malformed MCP messages are validated more strictly. |
| Tool errors | Schema-invalid tool arguments return `CallToolResult(isError: true)` under MCP 2025-11-25 and 2026-07-28 instead of throwing JSON-RPC `invalidParams`. |

If an application requires the 2.2 initialization-only negotiation behavior,
select `McpProtocol.legacy` during the rollout. This restores the protocol
lifecycle, not the permissive validation or OAuth behavior of the older SDK.

## Update the dependency

Update `pubspec.yaml`:

```yaml
environment:
  sdk: ^3.4.0

dependencies:
  mcp_dart: ^2.3.0
```

Then resolve and verify the project:

```bash
dart pub get
dart analyze
dart test
```

Any direct or transitive constraint that excludes `http` 1.5 must be loosened.
A normal caret constraint such as `http: ^1.4.0` already permits 1.5 and does
not need to change.

The SDK no longer depends on the `json_schema` or `quiver` packages. No change
is needed when using JSON Schema through `package:mcp_dart/mcp_dart.dart`. If an
application imported either transitive dependency directly, declare that
package as a direct application dependency or migrate to the SDK's exported
validation API.

## Choose the protocol rollout behavior

Existing constructors continue to compile:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
);

final server = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
);
```

In 2.3, those constructors use `McpProtocol.stable`. A client first attempts
MCP 2026-07-28 `server/discover` and falls back to the legacy `initialize`
flow when the peer identifies itself as legacy. On body-only transports such
as stdio, a silent discovery probe is bounded to five seconds. Servers accept
both the stateless and initialization-era profiles.

To retain the initialization-only negotiation behavior while upgrading the
SDK:

```dart
final client = McpClient(
  const Implementation(name: 'my-client', version: '1.0.0'),
  options: const McpClientOptions(protocol: McpProtocol.legacy),
);

final server = McpServer(
  const Implementation(name: 'my-server', version: '1.0.0'),
  options: const McpServerOptions(protocol: McpProtocol.legacy),
);
```

Use `McpProtocol.require2026` only when connecting to a legacy peer should be a
configuration error. See the [MCP 2026-07-28 transition guide](mcp-2026-07-28.md)
for error-specific fallback rules and stateless-only APIs. Neither
`McpProtocol.legacy` nor an explicit legacy version disables the stricter
schema, OAuth, or malformed-message validation in 2.3.

## Review observable behavior changes

### Stdio child recovery

After a successful stateless connection, `StdioClientTransport` now restarts a
child process that terminates unexpectedly. Active `subscriptions/listen`
requests are restored, but ordinary in-flight requests are never replayed.
Initialization-era sessions still close because their lifecycle cannot be
restored safely. Recovery reports failures through
`StdioClientTransport.onerror` and stops after five restarts within 30 seconds.

Set the previous close-on-exit behavior explicitly when required:

```dart
final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'my_server',
    restartOnUnexpectedExit: false,
  ),
);
```

### Tool validation and structured results

For MCP 2025-11-25 and 2026-07-28, tool arguments that do not satisfy a
registered `inputSchema` now complete at the JSON-RPC layer and return a tool
error result. Clients that previously caught `McpError` with
`ErrorCode.invalidParams` for this case should inspect the result:

```dart
final result = await client.callTool(
  const CallToolRequest(name: 'search'),
);

if (result.isError == true) {
  // Let the model or caller correct the tool arguments.
}
```

Unknown tools, malformed requests, and server failures remain JSON-RPC errors.
MCP 2025-06-18 and earlier sessions retain the previous `invalidParams`
behavior.

Invalid registered schemas, invalid server-produced output, or a successful
result missing required `structuredContent` are treated as server contract
failures and surface as JSON-RPC `internalError` under MCP 2025-11-25 and
2026-07-28. Test both successful and error tool results when an output schema
is registered. MCP 2026-07-28 additionally supports arrays, primitives, and
`null` as structured output through the stateless registration APIs; legacy
registrations retain object-root output compatibility.

Entries in `CallToolResult.extra` named `content`, `isError`, `_meta`, or
`structuredContent` no longer replace those protocol-owned fields. Pass those
values through their dedicated constructor parameters.

### JSON Schema validation

The public JSON Schema APIs remain available, but validation is now provided by
an SDK-owned offline validator. Draft 2020-12 and declared Draft 7 behavior are
supported, while malformed schemas and Draft 7 formats are diagnosed more
strictly. External-reference resolution and custom vocabularies remain outside
the SDK's supported validation scope; 2.3 does not remove supported external
resolution because the SDK did not provide it in 2.2.

Use the exported `JsonSchemaValidation.validate` extension when validation is
needed directly:

```dart
final schema = JsonSchema.object(
  properties: {'name': JsonSchema.string()},
  required: ['name'],
);

schema.validate({'name': 'example'});
```

Invalid definitions or instances throw `JsonSchemaValidationException`.

Run representative input and output schemas through tests before deploying,
especially if the application previously relied on an invalid schema being
accepted.

### OAuth redirects and metadata

The 2.2.2 `finishAuth(String)` method remains available for compatibility, but
it is deprecated because it cannot validate the authorization response's
`state` or issuer. New code should pass the full redirect data:

```dart
await transport.finishAuthRedirect(
  authorizationCode,
  state: returnedState,
  issuer: returnedIssuer,
);
```

OAuth discovery and token endpoints on another origin require an explicit
`oauthUriValidator`. Redirect URIs must use HTTPS or loopback HTTP. Metadata
factories also reject malformed or incomplete documents that 2.2.2 accepted.

Keep cross-origin approval narrow:

```dart
final options = StreamableHttpClientTransportOptions(
  oauthUriValidator: (uri, endpointKind) =>
      uri.scheme == 'https' && uri.host == 'auth.example.com',
);
```

An OAuth provider with a non-empty `clientId` is treated as pre-registered
client information. Return an empty `clientId` only when intentionally opting
into deprecated Dynamic Client Registration.

### Tasks

The existing `ProtocolOptions.taskStore` and `taskMessageQueue` APIs remain
available for MCP 2025-11-25 task augmentation. They may coexist with the
independent `io.modelcontextprotocol/tasks` extension, but they are not an
adapter for the extension's application-owned handlers or persistence.

Under MCP 2025-11-25, task-mode negotiation now happens before input-schema
validation. A task-required tool called without task augmentation continues to
return `methodNotFound`. A task-forbidden tool called with augmentation now
also returns `methodNotFound` instead of `invalidParams`. Earlier protocol
versions retain their previous behavior.

### Discovery identity

`DiscoverResult` is new in the 2.3 line, so this is not a break from the stable
2.2 API. Applications that used a 2.3 prerelease must account for anonymous MCP
2026-07-28 servers:

```dart
final discovery = await client.discoverServer();
final serverInfo = discovery.serverInfo;
if (serverInfo != null) {
  print('${serverInfo.name} ${serverInfo.version}');
}
```

## Deprecated APIs

The following APIs remain callable so applications can migrate gradually:

| Deprecated API | Replacement |
| --- | --- |
| `latestProtocolVersion` | `latestInitializationProtocolVersion` or `defaultProtocolVersion`, depending on intent |
| `supportedProtocolVersions` | `legacyProtocolVersions` or `allSupportedProtocolVersions` |
| `StreamableHttpClientTransport.finishAuth` | `finishAuthRedirect` |
| Legacy elicitation ID fields and completion notifications | MCP 2026-07-28 URL-mode elicitation and current result flow |

Deprecation warnings alone do not block the upgrade. The old protocol-version
constants intentionally retain their 2.2 values.

## Upgrade checklist

- Confirm the application uses Dart 3.4 or newer.
- Remove any `http` pin that prevents resolution of version 1.5 or newer.
- Run `dart pub get`, `dart analyze`, and the full test suite.
- Decide whether to use the default dual-era profile or temporarily select
  `McpProtocol.legacy`.
- Test startup against silent or legacy stdio peers; the first default-profile
  probe can take up to five seconds before fallback.
- Decide whether unexpected stateless stdio child exits should restart.
- Update callers that catch `invalidParams` for tool input-schema failures.
- Re-test registered input/output schemas and structured tool results.
- Re-test task-required and task-forbidden tool calls if task augmentation is
  enabled.
- Re-test OAuth discovery, redirect validation, and persisted credentials.
- Run analyzers and tests in nested example or Flutter packages that consume
  the SDK.

For protocol-specific behavior, continue with the
[MCP 2026-07-28 transition guide](mcp-2026-07-28.md). For migrations from other
SDKs or transports, see the [migration cookbooks](migration-cookbooks.md).
