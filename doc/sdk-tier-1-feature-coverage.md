# SDK Tier 1 feature coverage

This project-maintained inventory maps the published MCP SDK Tier 1
requirements to user-facing `mcp_dart` guides and examples. It is evidence for
a tier review, not a tier claim: the MCP SDK Working Group assigns tiers.

The inventory currently contains 48 non-experimental features. Features
removed or deprecated by MCP 2026-07-28 remain because the published
requirements still include them. Their examples explicitly select the MCP
2025-11-25 compatibility profile where required.

## Coverage summary

- All 48 features have prose documentation and runnable or near-runnable
  examples in current source.
- The deprecated legacy SSE client and server remain explicit compatibility
  surfaces. Both reference SEP-2596 and Streamable HTTP migration.
- Published `mcp_dart 2.5.0` includes `SseClientTransport`, so all 48 items
  have stable-package documentation and examples.
- Experimental Tasks and MCP Apps are documented separately and do not count
  toward the 48-feature Core inventory.

## Project-maintained feature inventory

| # | Feature | Documentation and example | Status |
| --- | --- | --- | --- |
| 1 | Tools - listing | [Client guide: list tools](client-guide.md#list-available-tools) | Covered |
| 2 | Tools - calling | [Client guide: call a tool](client-guide.md#call-a-tool) | Covered |
| 3 | Tools - text results | [Tools: text content](tools.md#text-content) | Covered |
| 4 | Tools - image results | [Tools: image content](tools.md#image-content) | Covered |
| 5 | Tools - audio results | [Tools: audio content](tools.md#audio-content) | Covered |
| 6 | Tools - embedded resources | [Tools: embedded resources](tools.md#embedded-resources) | Covered |
| 7 | Tools - error handling | [Tools: error handling](tools.md#error-handling) | Covered |
| 8 | Tools - change notifications | [Server guide: dynamic registration](server-guide.md#dynamic-capability-registration) and [notification routing](quick-reference.md#notifications-and-logging) | Covered |
| 9 | Resources - listing | [Client guide: list resources](client-guide.md#list-available-resources) | Covered |
| 10 | Resources - reading text | [Client guide: read a resource](client-guide.md#read-a-resource) | Covered |
| 11 | Resources - reading binary | [Server guide: binary resources](server-guide.md#binary-resources) | Covered |
| 12 | Resources - templates | [Server guide: resource with URI template](server-guide.md#resource-with-uri-template) | Covered |
| 13 | Resources - template reading | [Client guide: resource templates](client-guide.md#resource-templates) | Covered |
| 14 | Resources - subscribing | [Client guide: legacy subscriptions](client-guide.md#subscribe-to-resource-updates-mcp-2025-11-25) | Covered |
| 15 | Resources - unsubscribing | [Client guide: legacy subscriptions](client-guide.md#subscribe-to-resource-updates-mcp-2025-11-25) | Covered |
| 16 | Resources - change notifications | [Server guide: resource updates](server-guide.md#resource-updates) | Covered |
| 17 | Prompts - listing | [Client guide: list prompts](client-guide.md#list-available-prompts) | Covered |
| 18 | Prompts - getting simple | [Client guide: get a prompt](client-guide.md#get-a-prompt) | Covered |
| 19 | Prompts - getting with arguments | [Client guide: prompt arguments](client-guide.md#get-prompt-with-arguments) | Covered |
| 20 | Prompts - embedded resources | [Client guide: embedded prompt resources](client-guide.md#handle-embedded-resources-in-prompts) | Covered |
| 21 | Prompts - image content | [Quick reference: content types](quick-reference.md#content-types) | Covered |
| 22 | Prompts - change notifications | [Server guide: prompt capabilities](server-guide.md#prompt-capabilities) and [notification routing](quick-reference.md#notifications-and-logging) | Covered |
| 23 | Sampling - creating messages | [Client guide: sampling requests](client-guide.md#sampling-requests) | Covered |
| 24 | Elicitation - form mode | [MCP 2026-07-28 example](../example/mcp_2026_07_28/) and [legacy example](examples.md#server-initiated-user-input) | Covered |
| 25 | Elicitation - URL mode | [Legacy URL elicitation](#legacy-url-elicitation-and-completion) | Covered |
| 26 | Elicitation - schema validation | [Legacy elicitation example](examples.md#server-initiated-user-input) | Covered |
| 27 | Elicitation - default values | [Legacy elicitation example](examples.md#server-initiated-user-input) | Covered |
| 28 | Elicitation - enum values | [Legacy elicitation example](examples.md#server-initiated-user-input) | Covered |
| 29 | Elicitation - complete notification | [Legacy URL elicitation](#legacy-url-elicitation-and-completion) | Covered |
| 30 | Roots - listing | [Client guide: roots](client-guide.md#managing-roots) | Covered |
| 31 | Roots - change notifications | [Client guide: roots](client-guide.md#managing-roots) | Covered |
| 32 | Logging - sending log messages | [Quick reference: compatibility logging](quick-reference.md#notifications-and-logging) and [server observability](server-guide.md#observability-and-deprecated-protocol-logging) | Covered |
| 33 | Logging - setting level | [Client guide: set logging level](client-guide.md#set-logging-level-mcp-2025-11-25) | Covered |
| 34 | Completions - resource argument | [Client guide: completions](client-guide.md#completions) | Covered |
| 35 | Completions - prompt argument | [Client guide: completions](client-guide.md#completions) | Covered |
| 36 | Ping | [Quick reference: basic utilities](quick-reference.md#basic-utilities) | Covered |
| 37 | Streamable HTTP transport - client | [Transport guide: client setup](transports.md#client-setup-1) | Covered |
| 38 | Streamable HTTP transport - server | [Transport guide: high-level server](transports.md#high-level-streamable-http-server) | Covered |
| 39 | SSE transport - legacy client | [Transport guide: legacy SSE client](transports.md#legacy-client-setup) and [runnable client](../example/client_sse.dart) | Covered |
| 40 | SSE transport - legacy server | [Transport guide: legacy SSE](transports.md#legacy-sse-transport-deprecated) and [runnable server](../example/server_sse.dart) | Covered |
| 41 | stdio transport - client | [Transport guide: stdio client](transports.md#client-setup) and [runnable client](../example/client_stdio.dart) | Covered |
| 42 | stdio transport - server | [Transport guide: stdio server](transports.md#server-setup) and [runnable server](../example/server_stdio.dart) | Covered |
| 43 | Progress notifications | [Tools: progress](tools.md#progress-notifications) | Covered |
| 44 | Cancellation | [Tools: cancellation](tools.md#cancellation-support) and [client cancellation](quick-reference.md#basic-utilities) | Covered |
| 45 | Pagination | [Quick reference: basic utilities](quick-reference.md#basic-utilities) | Covered |
| 46 | Capability negotiation | [Client guide: capability negotiation](client-guide.md#capability-negotiation) | Covered |
| 47 | Protocol version negotiation | [Quick reference: protocol profile](quick-reference.md#protocol-profile) | Covered |
| 48 | JSON Schema 2020-12 support | [Tools: JSON Schema validation](tools.md#json-schema-validation) | Covered |

## Legacy URL elicitation and completion

URL elicitation lets an MCP 2025-11-25 server direct a user to a trusted URL
for an out-of-band interaction. Advertise and verify the client's URL
elicitation capability before use. An `accept` response grants consent to open
or navigate to the URL; it does not mean the out-of-band interaction has
finished. Send the completion notification only after the application verifies
that the interaction completed for the same authenticated subject and client
session that initiated it. MCP 2026-07-28 stateless URL elicitation does not use
that notification.

```dart
const elicitationId = 'authorization-1';
final initiatingSubject = authenticatedSubject;
final initiatingSessionId = authenticatedSessionId;

final result = await server.elicitInput(
  const ElicitRequest.url(
    message: 'Authorize access in your browser.',
    url: 'https://example.com/authorize',
    elicitationId: elicitationId,
  ),
);

if (result.accepted) {
  // This application-owned stream is completed by the trusted callback
  // endpoint, not by the client's consent response.
  await authorizationCompletions.firstWhere(
    (completion) =>
        completion.elicitationId == elicitationId &&
        completion.subject == initiatingSubject &&
        completion.sessionId == initiatingSessionId,
  );

  final notifyComplete =
      server.server.createElicitationCompletionNotifier(elicitationId);
  await notifyComplete();
}
```

## Review rule

Keep this table aligned with the canonical feature list in the official
conformance repository. A row may be marked covered only when linked
user-facing prose explains what, when, and how, and the linked material
contains runnable or near-runnable Dart. Tests and conformance fixtures are
supporting evidence, not documentation substitutes.
