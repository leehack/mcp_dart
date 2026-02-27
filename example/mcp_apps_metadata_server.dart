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
    'weather_get_current',
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
        'resourceUri': 'ui://weather/dashboard',
        'visibility': ['model', 'app'],
      },
      'ui/resourceUri': 'ui://weather/dashboard',
    },
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
          const ResourceLink(
            uri: 'ui://weather/dashboard',
            name: 'Weather Dashboard UI',
            description: 'Interactive MCP app weather dashboard',
            mimeType: mcpUiResourceMimeType,
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
        color-scheme: light dark;
        font-family: "SF Pro Display", "Segoe UI", "Helvetica Neue", sans-serif;
      }

      body {
        margin: 0;
        padding: 14px;
        background: radial-gradient(circle at top right, #2563eb 0%, #1e293b 45%, #0f172a 100%);
        color: #e2e8f0;
      }

      .card {
        border: 1px solid rgba(148, 163, 184, 0.35);
        border-radius: 14px;
        padding: 14px;
        background: rgba(15, 23, 42, 0.7);
        box-shadow: 0 12px 30px rgba(2, 6, 23, 0.35);
      }

      h1 {
        margin: 0;
        font-size: 18px;
        letter-spacing: 0.02em;
      }

      p {
        margin: 0;
      }

      .badge {
        display: inline-block;
        margin-top: 8px;
        margin-bottom: 14px;
        padding: 4px 8px;
        border-radius: 999px;
        border: 1px solid rgba(125, 211, 252, 0.4);
        color: #bae6fd;
        background: rgba(12, 74, 110, 0.35);
        font-size: 11px;
      }

      .metric {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 6px;
        margin-bottom: 8px;
        font-size: 14px;
      }

      .metric span:last-child {
        font-weight: 600;
        color: #f8fafc;
      }

      .status {
        margin-top: 10px;
        font-size: 12px;
        color: #bfdbfe;
      }

      code {
        font-family: "SF Mono", ui-monospace, monospace;
        font-size: 11px;
        color: #bfdbfe;
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Weather Dashboard</h1>
      <p class="badge">MCP APP RESOURCE · <code>ui://weather/dashboard</code></p>

      <div class="metric">
        <span>Location</span>
        <span id="location">Unknown</span>
      </div>
      <div class="metric">
        <span>Temperature</span>
        <span id="temperature">-- C</span>
      </div>
      <div class="metric">
        <span>Condition</span>
        <span id="condition">Waiting for tool result</span>
      </div>

      <p class="status" id="status">Connecting to host...</p>
    </div>

    <script>
      (() => {
        const locationEl = document.getElementById('location');
        const temperatureEl = document.getElementById('temperature');
        const conditionEl = document.getElementById('condition');
        const statusEl = document.getElementById('status');

        const state = {
          location: 'Unknown',
          temperatureC: '--',
          condition: 'Waiting for tool result',
        };

        let nextId = 1;
        const pending = new Map();

        const render = () => {
          locationEl.textContent = state.location;
          temperatureEl.textContent = state.temperatureC + ' C';
          conditionEl.textContent = state.condition;
        };

        const setStatus = (message) => {
          statusEl.textContent = message;
        };

        const notify = (method, params) => {
          const payload = { jsonrpc: '2.0', method };
          if (params !== undefined) {
            payload.params = params;
          }
          window.parent.postMessage(payload, '*');
        };

        const request = (method, params) => {
          const id = nextId;
          nextId += 1;

          const payload = { jsonrpc: '2.0', id, method };
          if (params !== undefined) {
            payload.params = params;
          }

          window.parent.postMessage(payload, '*');

          return new Promise((resolve, reject) => {
            pending.set(id, { resolve, reject });
          });
        };

        const sendLog = (message) => {
          notify('notifications/message', {
            level: 'info',
            logger: 'mcp_dart_weather_dashboard',
            data: message,
          });
        };

        window.addEventListener('message', (event) => {
          const message = event.data;
          if (!message || typeof message !== 'object') {
            return;
          }

          if (
            Object.prototype.hasOwnProperty.call(message, 'id') &&
            pending.has(message.id)
          ) {
            const callbacks = pending.get(message.id);
            pending.delete(message.id);

            if (message.error) {
              callbacks.reject(message.error);
            } else {
              callbacks.resolve(message.result);
            }
            return;
          }

          if (message.method === 'ui/notifications/tool-input') {
            const args = message.params && message.params.arguments;
            if (args && typeof args.location === 'string') {
              state.location = args.location;
              render();
              setStatus('Tool input received for ' + state.location + '.');
            }
            return;
          }

          if (message.method === 'ui/notifications/tool-result') {
            const result = message.params || {};
            const weather = result.structuredContent || {};

            if (typeof weather.location === 'string') {
              state.location = weather.location;
            }
            if (typeof weather.temperatureC === 'number') {
              state.temperatureC = String(weather.temperatureC);
            }
            if (typeof weather.condition === 'string') {
              state.condition = weather.condition;
            }

            render();
            setStatus('Tool result rendered from MCP host notifications.');
            sendLog('tool-result rendered for ' + state.location);
          }
        });

        const initialize = async () => {
          render();

          try {
            await request('ui/initialize', {
              protocolVersion: '2026-01-26',
              appInfo: {
                name: 'mcp-dart-weather-dashboard',
                version: '1.0.0',
              },
              appCapabilities: {},
            });

            notify('ui/notifications/initialized');
            notify('ui/notifications/size-changed', {
              width: Math.ceil(document.documentElement.getBoundingClientRect().width),
              height: Math.ceil(document.documentElement.getBoundingClientRect().height),
            });

            setStatus('Connected. Waiting for host tool events...');
            sendLog('weather dashboard MCP app initialized');
          } catch (error) {
            setStatus('Initialization failed. See host logs.');
          }
        };

        initialize();
      })();
    </script>
  </body>
</html>
''';
