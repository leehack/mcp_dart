## 0.6.0

- Web Platform Support: StreamableHttpClientTransport now works in web browsers
- Replaced `dart:io` dependencies with cross-platform packages (`package:http`
  and `package:eventflux`)
- Added comprehensive web test suite with browser-based validation
- Added multi-platform test runner and VS Code integration
- Enabled browser-based MCP client applications
- Maintained 100% backward compatibility with existing VM-based applications

## 0.5.1

- Add support for OutputScheme (<https://modelcontextprotocol.io/specification/draft/server/tools#output-schema>)

## 0.5.0

- Protocol version 2025-03-26

## 0.4.3

- Fix SSE behavior on StreamableHTTP
- Added sendNotification and sendRequest to extra for server callbacks

## 0.4.2

- Add Tool Annotation
- Remove additionalProperties from all models
- Add AudioContent

## 0.4.1

- Add IOStreamTransport to connect a client and server via dart streams in a single application

## 0.4.0

- Add support for StreamableHTTP client
- Add support for StreamableHTTP server

## 0.3.6

- Improve pub.dev points

## 0.3.5

- Lower min dart sdk to 3.0.0

## 0.3.4

- Fix Sampling result parsing error

## 0.3.3

- Add Gemini MCP Client Example
- Add Anthropic MCP Client Example
- Add Weather MCP Server Example

## 0.3.2

- Add SSE Server Manager for easier SSE server implementation

## 0.3.1

- Add Client support (stdio)
- Add resource and prompts example to stdio server and client

## 0.3.0

- Full refactor of the codebase to match it with the Typescript SDK implementation.

## 0.2.0

- Make it no need to call trasnport.connect()

## 0.1.1

- Add examples visible in pub.dev

## 0.1.0

- Add SSE support

## 0.0.2

- Expose more types

## 0.0.1

- Initial version.
