import 'content.dart';
import 'initialization.dart';
import 'resources.dart';
import 'tools.dart';

/// MCP extension identifier for UI capabilities.
const String mcpUiExtensionId = 'io.modelcontextprotocol/ui';

/// MIME type used by MCP Apps HTML resources.
const String mcpUiResourceMimeType = 'text/html;profile=mcp-app';

/// URI scheme used by MCP Apps UI resources.
const String mcpUiResourceUriScheme = 'ui';

/// Legacy `_meta` key used to point tools at a UI resource.
///
/// Prefer nested `_meta.ui.resourceUri`.
const String mcpUiLegacyResourceUriMetaKey = 'ui/resourceUri';

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

/// Typed capability settings for `io.modelcontextprotocol/ui`.
class McpUiExtensionCapability {
  /// MIME types supported by the host for UI resources.
  final List<String>? mimeTypes;

  /// Additional, extension-specific settings.
  final Map<String, dynamic>? extra;

  const McpUiExtensionCapability({
    this.mimeTypes,
    this.extra,
  });

  factory McpUiExtensionCapability.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json)..remove('mimeTypes');

    return McpUiExtensionCapability(
      mimeTypes: (json['mimeTypes'] as List?)?.whereType<String>().toList(),
      extra: extras.isEmpty ? null : extras,
    );
  }

  Map<String, dynamic> toJson() => {
        if (mimeTypes != null) 'mimeTypes': mimeTypes,
        ...?extra,
      };

  /// Returns true when [mimeType] is listed in [mimeTypes].
  bool supportsMimeType(String mimeType) {
    return mimeTypes?.contains(mimeType) ?? false;
  }
}

/// Creates a capabilities map augmented with MCP UI extension settings.
Map<String, Map<String, dynamic>> withMcpUiExtension({
  Map<String, Map<String, dynamic>>? extensions,
  List<String> mimeTypes = const [mcpUiResourceMimeType],
}) {
  final merged = Map<String, Map<String, dynamic>>.from(extensions ?? {});
  merged[mcpUiExtensionId] = McpUiExtensionCapability(
    mimeTypes: mimeTypes,
  ).toJson();
  return merged;
}

/// Typed representation of `_meta.ui` on tools.
class McpUiToolMeta {
  /// URI of the UI resource that should render tool output.
  final String? resourceUri;

  /// Optional visibility settings (typically `model`, `app`, or both).
  final List<String>? visibility;

  /// Additional unknown fields preserved for forward compatibility.
  final Map<String, dynamic>? extra;

  const McpUiToolMeta({
    this.resourceUri,
    this.visibility,
    this.extra,
  });

  factory McpUiToolMeta.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json)
      ..remove('resourceUri')
      ..remove('visibility');

    return McpUiToolMeta(
      resourceUri: json['resourceUri'] as String?,
      visibility: (json['visibility'] as List?)?.whereType<String>().toList(),
      extra: extras.isEmpty ? null : extras,
    );
  }

  /// Parses `_meta.ui` (or deprecated `_meta['ui/resourceUri']`) from tool meta.
  static McpUiToolMeta? fromToolMeta(Map<String, dynamic>? toolMeta) {
    if (toolMeta == null) {
      return null;
    }

    final uiMap = _asStringDynamicMap(toolMeta['ui']);
    if (uiMap != null) {
      return McpUiToolMeta.fromJson(uiMap);
    }

    final legacyResourceUri = toolMeta[mcpUiLegacyResourceUriMetaKey];
    if (legacyResourceUri is String) {
      return McpUiToolMeta(resourceUri: legacyResourceUri);
    }

    return null;
  }

  /// Converts this typed value into a nested tool `_meta` map.
  Map<String, dynamic> toToolMeta([Map<String, dynamic>? existingMeta]) {
    final merged = Map<String, dynamic>.from(existingMeta ?? {});
    merged['ui'] = toJson();
    return merged;
  }

  Map<String, dynamic> toJson() => {
        if (resourceUri != null) 'resourceUri': resourceUri,
        if (visibility != null) 'visibility': visibility,
        ...?extra,
      };

  /// Whether this tool should be visible to the model.
  bool get isVisibleToModel =>
      visibility == null || visibility!.contains('model');

  /// Whether this tool should be callable by apps.
  bool get isVisibleToApp => visibility == null || visibility!.contains('app');
}

/// CSP settings declared by `_meta.ui.csp`.
class McpUiCsp {
  final List<String>? connectDomains;
  final List<String>? resourceDomains;
  final List<String>? frameDomains;
  final List<String>? baseUriDomains;

  /// Additional unknown fields preserved for forward compatibility.
  final Map<String, dynamic>? extra;

  const McpUiCsp({
    this.connectDomains,
    this.resourceDomains,
    this.frameDomains,
    this.baseUriDomains,
    this.extra,
  });

  factory McpUiCsp.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json)
      ..remove('connectDomains')
      ..remove('resourceDomains')
      ..remove('frameDomains')
      ..remove('baseUriDomains');

    return McpUiCsp(
      connectDomains:
          (json['connectDomains'] as List?)?.whereType<String>().toList(),
      resourceDomains:
          (json['resourceDomains'] as List?)?.whereType<String>().toList(),
      frameDomains:
          (json['frameDomains'] as List?)?.whereType<String>().toList(),
      baseUriDomains:
          (json['baseUriDomains'] as List?)?.whereType<String>().toList(),
      extra: extras.isEmpty ? null : extras,
    );
  }

  Map<String, dynamic> toJson() => {
        if (connectDomains != null) 'connectDomains': connectDomains,
        if (resourceDomains != null) 'resourceDomains': resourceDomains,
        if (frameDomains != null) 'frameDomains': frameDomains,
        if (baseUriDomains != null) 'baseUriDomains': baseUriDomains,
        ...?extra,
      };
}

/// Permission settings declared by `_meta.ui.permissions`.
class McpUiPermissions {
  final bool camera;
  final bool microphone;
  final bool geolocation;
  final bool clipboardWrite;

  /// Additional unknown fields preserved for forward compatibility.
  final Map<String, dynamic>? extra;

  const McpUiPermissions({
    this.camera = false,
    this.microphone = false,
    this.geolocation = false,
    this.clipboardWrite = false,
    this.extra,
  });

  factory McpUiPermissions.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json)
      ..remove('camera')
      ..remove('microphone')
      ..remove('geolocation')
      ..remove('clipboardWrite');

    return McpUiPermissions(
      camera: json.containsKey('camera'),
      microphone: json.containsKey('microphone'),
      geolocation: json.containsKey('geolocation'),
      clipboardWrite: json.containsKey('clipboardWrite'),
      extra: extras.isEmpty ? null : extras,
    );
  }

  Map<String, dynamic> toJson() => {
        if (camera) 'camera': const <String, dynamic>{},
        if (microphone) 'microphone': const <String, dynamic>{},
        if (geolocation) 'geolocation': const <String, dynamic>{},
        if (clipboardWrite) 'clipboardWrite': const <String, dynamic>{},
        ...?extra,
      };
}

/// Typed representation of `_meta.ui` on resources and resource content.
class McpUiResourceMeta {
  final McpUiCsp? csp;
  final McpUiPermissions? permissions;
  final String? domain;
  final bool? prefersBorder;

  /// Additional unknown fields preserved for forward compatibility.
  final Map<String, dynamic>? extra;

  const McpUiResourceMeta({
    this.csp,
    this.permissions,
    this.domain,
    this.prefersBorder,
    this.extra,
  });

  factory McpUiResourceMeta.fromJson(Map<String, dynamic> json) {
    final cspMap = _asStringDynamicMap(json['csp']);
    final permissionsMap = _asStringDynamicMap(json['permissions']);

    final extras = Map<String, dynamic>.from(json)
      ..remove('csp')
      ..remove('permissions')
      ..remove('domain')
      ..remove('prefersBorder');

    return McpUiResourceMeta(
      csp: cspMap == null ? null : McpUiCsp.fromJson(cspMap),
      permissions: permissionsMap == null
          ? null
          : McpUiPermissions.fromJson(permissionsMap),
      domain: json['domain'] as String?,
      prefersBorder: json['prefersBorder'] as bool?,
      extra: extras.isEmpty ? null : extras,
    );
  }

  /// Parses `_meta.ui` from container metadata.
  static McpUiResourceMeta? fromMetaMap(Map<String, dynamic>? containerMeta) {
    final uiMap = _asStringDynamicMap(containerMeta?['ui']);
    if (uiMap == null) {
      return null;
    }
    return McpUiResourceMeta.fromJson(uiMap);
  }

  /// Converts this typed value into a nested `_meta` map.
  Map<String, dynamic> toMeta([Map<String, dynamic>? existingMeta]) {
    final merged = Map<String, dynamic>.from(existingMeta ?? {});
    merged['ui'] = toJson();
    return merged;
  }

  Map<String, dynamic> toJson() => {
        if (csp != null) 'csp': csp!.toJson(),
        if (permissions != null) 'permissions': permissions!.toJson(),
        if (domain != null) 'domain': domain,
        if (prefersBorder != null) 'prefersBorder': prefersBorder,
        ...?extra,
      };
}

extension ClientCapabilitiesMcpUi on ClientCapabilities {
  /// Typed access to client-side MCP UI extension settings.
  McpUiExtensionCapability? get mcpUiExtension {
    final json = extensions?[mcpUiExtensionId];
    if (json == null) {
      return null;
    }
    return McpUiExtensionCapability.fromJson(json);
  }

  /// True when client extension settings include [mimeType].
  bool supportsMcpUiMimeType([String mimeType = mcpUiResourceMimeType]) {
    return mcpUiExtension?.supportsMimeType(mimeType) ?? false;
  }
}

extension ServerCapabilitiesMcpUi on ServerCapabilities {
  /// Typed access to server-side MCP UI extension settings.
  McpUiExtensionCapability? get mcpUiExtension {
    final json = extensions?[mcpUiExtensionId];
    if (json == null) {
      return null;
    }
    return McpUiExtensionCapability.fromJson(json);
  }

  /// True when server extension settings include [mimeType].
  bool supportsMcpUiMimeType([String mimeType = mcpUiResourceMimeType]) {
    return mcpUiExtension?.supportsMimeType(mimeType) ?? false;
  }
}

extension ToolMcpUiMetaExtension on Tool {
  /// Typed access to `_meta.ui` metadata.
  McpUiToolMeta? get mcpUiMeta => McpUiToolMeta.fromToolMeta(meta);
}

extension ResourceMcpUiMetaExtension on Resource {
  /// Typed access to `_meta.ui` metadata.
  McpUiResourceMeta? get mcpUiMeta => McpUiResourceMeta.fromMetaMap(meta);
}

extension ResourceTemplateMcpUiMetaExtension on ResourceTemplate {
  /// Typed access to `_meta.ui` metadata.
  McpUiResourceMeta? get mcpUiMeta => McpUiResourceMeta.fromMetaMap(meta);
}

extension ResourceContentsMcpUiMetaExtension on ResourceContents {
  /// Typed access to `_meta.ui` metadata.
  McpUiResourceMeta? get mcpUiMeta => McpUiResourceMeta.fromMetaMap(meta);
}
