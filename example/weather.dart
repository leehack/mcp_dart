// Dart porting of https://github.com/modelcontextprotocol/quickstart-resources/tree/main/weather-server-typescript
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

const String nwsApiBase = "https://api.weather.gov";
const String userAgent = "weather-app/1.0";

/// Helper function for making NWS API requests
Future<Map<String, dynamic>?> makeNWSRequest(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.set(HttpHeaders.acceptHeader, "application/geo+json");

    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        "HTTP error! status: ${response.statusCode}",
        uri: Uri.parse(url),
      );
    }

    final responseBody = await response.transform(utf8.decoder).join();
    return jsonDecode(responseBody) as Map<String, dynamic>;
  } catch (error) {
    stderr.writeln("Error making NWS request: $error");
    return null;
  } finally {
    client.close();
  }
}

/// Format alert data
String formatAlert(Map<String, dynamic> feature) {
  final props = feature['properties'] ?? {};
  return [
    "Event: ${props['event'] ?? 'Unknown'}",
    "Area: ${props['areaDesc'] ?? 'Unknown'}",
    "Severity: ${props['severity'] ?? 'Unknown'}",
    "Status: ${props['status'] ?? 'Unknown'}",
    "Headline: ${props['headline'] ?? 'No headline'}",
    "---",
  ].join("\n");
}

void main() async {
  final server = McpServer(Implementation(name: "weather", version: "1.0.0"));

  // Register "get-alerts" tool
  server.tool(
    "get-alerts",
    description: "Get weather alerts for a state",
    toolInputSchema: ToolInputSchema(
      properties: {
        "state": {
          "type": "string",
          "description": "Two-letter state code (e.g. CA, NY)",
        },
      },
      required: ["state"],
    ),
    icon: ImageContent(
      data:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNiAAAABgDNjd8qAAAAAElFTkSuQmCC",
      mimeType: "image/png",
    ),
    callback: ({args, meta, extra}) async {
      final state = (args?['state'] as String?)?.toUpperCase();
      if (state == null || state.length != 2) {
        return CallToolResult.fromContent(
          content: [TextContent(text: "Invalid state code provided.")],
          isError: true,
        );
      }

      final alertsUrl = "$nwsApiBase/alerts?area=$state";
      final alertsData = await makeNWSRequest(alertsUrl);

      if (alertsData == null) {
        return CallToolResult.fromContent(
          content: [TextContent(text: "Failed to retrieve alerts data.")],
        );
      }

      final features = alertsData['features'] as List<dynamic>? ?? [];
      if (features.isEmpty) {
        return CallToolResult.fromContent(
          content: [TextContent(text: "No active alerts for $state.")],
        );
      }

      final formattedAlerts =
          features.map((feature) => formatAlert(feature)).join("\n");
      final alertsText = "Active alerts for $state:\n\n$formattedAlerts";

      return CallToolResult.fromContent(
        content: [TextContent(text: alertsText)],
      );
    },
  );

  // Register "get-forecast" tool
  server.tool(
    "get-forecast",
    description: "Get weather forecast for a location",
    toolInputSchema: ToolInputSchema(
      properties: {
        "latitude": {
          "type": "number",
          "description": "Latitude of the location",
        },
        "longitude": {
          "type": "number",
          "description": "Longitude of the location",
        },
      },
      required: ["latitude", "longitude"],
    ),
    callback: ({args, meta, extra}) async {
      final latitude = args?['latitude'] as num?;
      final longitude = args?['longitude'] as num?;

      if (latitude == null || longitude == null) {
        return CallToolResult.fromContent(
          content: [TextContent(text: "Invalid latitude or longitude.")],
          isError: true,
        );
      }

      final pointsUrl =
          "$nwsApiBase/points/${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}";
      final pointsData = await makeNWSRequest(pointsUrl);

      if (pointsData == null) {
        return CallToolResult.fromContent(
          content: [
            TextContent(
              text:
                  "Failed to retrieve grid point data for coordinates: $latitude, $longitude. This location may not be supported by the NWS API (only US locations are supported).",
            ),
          ],
        );
      }

      final forecastUrl = pointsData['properties']?['forecast'] as String?;
      if (forecastUrl == null) {
        return CallToolResult.fromContent(
          content: [
            TextContent(
              text: "Failed to get forecast URL from grid point data.",
            ),
          ],
        );
      }

      final forecastData = await makeNWSRequest(forecastUrl);
      if (forecastData == null) {
        return CallToolResult.fromContent(
          content: [TextContent(text: "Failed to retrieve forecast data.")],
        );
      }

      final periods =
          forecastData['properties']?['periods'] as List<dynamic>? ?? [];
      if (periods.isEmpty) {
        return CallToolResult.fromContent(
          content: [TextContent(text: "No forecast periods available.")],
        );
      }

      final formattedForecast = periods.map((period) {
        final periodMap = period as Map<String, dynamic>;
        return [
          "${periodMap['name'] ?? 'Unknown'}:",
          "Temperature: ${periodMap['temperature'] ?? 'Unknown'}°${periodMap['temperatureUnit'] ?? 'F'}",
          "Wind: ${periodMap['windSpeed'] ?? 'Unknown'} ${periodMap['windDirection'] ?? ''}",
          "${periodMap['shortForecast'] ?? 'No forecast available'}",
          "---",
        ].join("\n");
      }).join("\n");

      final forecastText =
          "Forecast for $latitude, $longitude:\n\n$formattedForecast";

      return CallToolResult.fromContent(
        content: [TextContent(text: forecastText)],
      );
    },
  );

  // Start the server
  final transport = StdioServerTransport();
  await server.connect(transport);
  stderr.writeln("Weather MCP Server running on stdio");
}
