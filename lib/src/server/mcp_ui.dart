import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/types.dart';

/// Tool configuration for [registerAppTool].
///
/// `meta` maps to the tool `_meta` payload and should include either:
/// - nested `ui.resourceUri` (preferred), or
/// - legacy `ui/resourceUri`.
class McpUiAppToolConfig {
  final String? title;
  final String? description;
  final ToolInputSchema? inputSchema;
  final ToolOutputSchema? outputSchema;
  final ToolAnnotations? annotations;
  final Map<String, dynamic> meta;

  const McpUiAppToolConfig({
    this.title,
    this.description,
    this.inputSchema,
    this.outputSchema,
    this.annotations,
    required this.meta,
  });
}

/// Resource configuration for [registerAppResource].
///
/// - [mimeType] defaults to [mcpUiResourceMimeType]
/// - [meta] maps to resource `_meta` in `resources/list`
class McpUiAppResourceConfig {
  final String? description;
  final String mimeType;
  final Map<String, dynamic>? meta;

  const McpUiAppResourceConfig({
    this.description,
    this.mimeType = mcpUiResourceMimeType,
    this.meta,
  });
}

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

Map<String, dynamic> _normalizeAppToolMeta(Map<String, dynamic> meta) {
  final normalized = Map<String, dynamic>.from(meta);
  final uiMeta = _asStringDynamicMap(normalized['ui']);
  final uiResourceUri = uiMeta?['resourceUri'];
  final legacyResourceUri = normalized[mcpUiLegacyResourceUriMetaKey];

  if (uiResourceUri is String && legacyResourceUri is! String) {
    normalized[mcpUiLegacyResourceUriMetaKey] = uiResourceUri;
    return normalized;
  }

  if (legacyResourceUri is String && uiResourceUri is! String) {
    final mergedUiMeta = Map<String, dynamic>.from(uiMeta ?? {});
    mergedUiMeta['resourceUri'] = legacyResourceUri;
    normalized['ui'] = mergedUiMeta;
  }

  return normalized;
}

/// Registers an app tool and normalizes MCP Apps metadata.
///
/// This mirrors the TypeScript `registerAppTool` helper behavior by ensuring
/// both metadata formats are present when possible:
/// - `_meta.ui.resourceUri` (preferred)
/// - `_meta['ui/resourceUri']` (legacy compatibility)
RegisteredTool registerAppTool(
  McpServer server,
  String name,
  McpUiAppToolConfig config,
  ToolFunction callback,
) {
  final normalizedMeta = _normalizeAppToolMeta(config.meta);

  return server.registerTool(
    name,
    title: config.title,
    description: config.description,
    inputSchema: config.inputSchema,
    outputSchema: config.outputSchema,
    annotations: config.annotations,
    meta: normalizedMeta,
    callback: callback,
  );
}

/// Registers an MCP Apps UI resource.
///
/// This mirrors the TypeScript `registerAppResource` helper behavior by
/// defaulting the resource MIME type to [mcpUiResourceMimeType].
RegisteredResource registerAppResource(
  McpServer server,
  String name,
  String uri,
  McpUiAppResourceConfig config,
  ReadResourceCallback readCallback,
) {
  return server.registerResource(
    name,
    uri,
    (
      description: config.description,
      mimeType: config.mimeType,
    ),
    readCallback,
    meta: config.meta,
  );
}

/// Returns MCP Apps extension settings from capabilities.
///
/// - Pass [ClientCapabilities] to inspect host/client support.
/// - Pass [ServerCapabilities] to inspect server support.
McpUiExtensionCapability? getUiCapability(Object? capabilities) {
  if (capabilities is ClientCapabilities) {
    return capabilities.mcpUiExtension;
  }
  if (capabilities is ServerCapabilities) {
    return capabilities.mcpUiExtension;
  }
  return null;
}
