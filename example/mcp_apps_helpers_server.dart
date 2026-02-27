import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final server = McpServer(
    const Implementation(
      name: 'mcp-apps-helpers-server',
      version: '1.0.0',
    ),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        resources: const ServerCapabilitiesResources(),
        tools: const ServerCapabilitiesTools(),
        extensions: withMcpUiExtension(),
      ),
    ),
  );

  const resourceUri = 'ui://weather/dashboard.html';

  registerAppTool(
    server,
    'weather/get_current',
    McpUiAppToolConfig(
      description: 'Get mock weather data for a location',
      inputSchema: JsonSchema.object(
        properties: {
          'location': JsonSchema.string(
            description: 'City name (for example: Seoul)',
          ),
        },
        required: ['location'],
      ),
      meta: const {
        'ui': {
          'resourceUri': resourceUri,
          'visibility': ['model', 'app'],
        },
      },
    ),
    (args, extra) async {
      final location = args['location'] as String;
      final weather = {
        'location': location,
        'temperatureC': 22,
        'condition': 'Partly Cloudy',
      };

      return CallToolResult(
        content: [
          TextContent(
            text:
                'Current weather for $location: ${weather['temperatureC']}C, ${weather['condition']}.',
          ),
        ],
        structuredContent: weather,
      );
    },
  );

  registerAppResource(
    server,
    'Weather Dashboard UI',
    resourceUri,
    const McpUiAppResourceConfig(
      description: 'MCP Apps HTML interface for weather tool results',
      meta: {
        'ui': {
          'csp': {
            'connectDomains': ['https://api.open-meteo.com'],
            'resourceDomains': ['https://cdn.jsdelivr.net'],
          },
          'prefersBorder': true,
        },
      },
    ),
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: mcpUiResourceMimeType,
            text: _dashboardHtml,
            meta: const McpUiResourceMeta(
              prefersBorder: true,
            ).toMeta(),
          ),
        ],
      );
    },
  );

  await server.connect(StdioServerTransport());
}

const String _dashboardHtml = '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Weather Dashboard</title>
  </head>
  <body>
    <h1>Weather Dashboard</h1>
    <p>This UI is served from <code>ui://weather/dashboard.html</code>.</p>
  </body>
</html>
''';
