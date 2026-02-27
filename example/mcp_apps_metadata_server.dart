import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  final server = McpServer(
    const Implementation(
      name: 'mcp-apps-metadata-server',
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

  const uiResourceMeta = McpUiResourceMeta(
    csp: McpUiCsp(
      connectDomains: ['https://api.open-meteo.com'],
      resourceDomains: ['https://cdn.jsdelivr.net'],
    ),
    prefersBorder: true,
  );

  server.registerResource(
    'Weather Dashboard UI',
    'ui://weather/dashboard',
    (
      description:
          'MCP Apps HTML interface that renders weather tool results in a dashboard',
      mimeType: mcpUiResourceMimeType,
    ),
    (uri, extra) async => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: mcpUiResourceMimeType,
          text: _dashboardHtml,
          meta: uiResourceMeta.toMeta(),
        ),
      ],
    ),
  );

  server.registerTool(
    'weather/get_current',
    description: 'Get mock weather data for a location',
    inputSchema: JsonSchema.object(
      properties: {
        'location': JsonSchema.string(
          description: 'City name (for example: Seoul)',
        ),
      },
      required: ['location'],
    ),
    meta: const McpUiToolMeta(
      resourceUri: 'ui://weather/dashboard',
      visibility: ['model', 'app'],
    ).toToolMeta(),
    callback: (args, extra) async {
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

  await server.connect(StdioServerTransport());
}

const String _dashboardHtml = '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Weather Dashboard</title>
    <style>
      :root {
        font-family: ui-sans-serif, system-ui, sans-serif;
        color-scheme: light dark;
      }

      body {
        margin: 0;
        padding: 16px;
      }

      .card {
        border: 1px solid #d1d5db;
        border-radius: 12px;
        padding: 12px;
      }

      h1 {
        margin: 0 0 8px;
        font-size: 18px;
      }

      p {
        margin: 0;
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Weather Dashboard</h1>
      <p>This UI is provided via <code>ui://weather/dashboard</code>.</p>
      <p>The host can pass tool input/result notifications to this app.</p>
    </div>
  </body>
</html>
''';
