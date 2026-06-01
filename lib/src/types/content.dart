import 'validation.dart';

Map<String, dynamic>? _asJsonObjectOrNull(
  dynamic value, [
  String field = 'object',
]) {
  if (value == null) {
    return null;
  }
  return readJsonObject(value, field);
}

Map<String, dynamic> _asJsonObject(
  dynamic value, [
  String field = 'object',
]) {
  final map = _asJsonObjectOrNull(value, field);
  if (map == null) {
    throw FormatException('$field must be a JSON object');
  }
  return map;
}

String _readRequiredString(Object? value, String field) {
  if (value is String) {
    return value;
  }
  throw FormatException('$field must be a string');
}

bool _isAbsoluteUri(String value) {
  return Uri.tryParse(value)?.hasScheme ?? false;
}

String _readRequiredAbsoluteUriString(Object? value, String field) {
  final result = _readRequiredString(value, field);
  if (!_isAbsoluteUri(result)) {
    throw FormatException('$field must be an absolute URI');
  }
  return result;
}

void _validateAbsoluteUriString(String value, String field) {
  if (!_isAbsoluteUri(value)) {
    throw ArgumentError.value(value, field, 'must be an absolute URI');
  }
}

String _absoluteUriForJson(String value, String field) {
  validateAbsoluteUriString(value, field);
  return value;
}

String _base64ForJson(String value, String field) {
  validateBase64String(value, field);
  return value;
}

String? _readOptionalPresentString(
  Map<String, dynamic> json,
  String key,
  String field,
) {
  if (!json.containsKey(key)) {
    return null;
  }
  return _readRequiredString(json[key], field);
}

List<String>? _readOptionalPresentStringList(
  Map<String, dynamic> json,
  String key,
  String field,
) {
  if (!json.containsKey(key)) {
    return null;
  }
  final value = json[key];
  if (value is! List) {
    throw FormatException('$field must be a list of strings');
  }

  return [
    for (final item in value)
      if (item is String)
        item
      else
        throw FormatException('$field items must be strings'),
  ];
}

/// Allowed audience values for content/resource annotations.
enum AnnotationAudience { user, assistant }

/// Optional annotations that can be attached to content and resources.
class Annotations {
  /// Intended audiences for this content.
  final List<AnnotationAudience>? audience;

  /// Relative importance (0.0 to 1.0).
  final double? priority;

  /// ISO 8601 timestamp when this content was last modified.
  final String? lastModified;

  const Annotations({
    this.audience,
    this.priority,
    this.lastModified,
  }) : assert(
          priority == null || (priority >= 0 && priority <= 1),
          'priority must be between 0 and 1',
        );

  factory Annotations.fromJson(Map<String, dynamic> json) {
    return Annotations(
      audience: (json['audience'] as List<dynamic>?)
          ?.map((value) => AnnotationAudience.values.byName(value as String))
          .toList(),
      priority: readUnitDouble(json['priority'], 'Annotations.priority'),
      lastModified: json['lastModified'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    validateUnitDouble(priority, 'Annotations.priority');
    return {
      if (audience != null)
        'audience': audience!.map((value) => value.name).toList(),
      if (priority != null) 'priority': priority,
      if (lastModified != null) 'lastModified': lastModified,
    };
  }
}

/// Sealed class representing the contents of a specific resource or sub-resource.
sealed class ResourceContents {
  /// The URI of this resource content.
  final String uri;

  /// The MIME type, if known.
  final String? mimeType;

  /// Optional metadata associated with this resource content.
  final Map<String, dynamic>? meta;

  /// Additional unknown properties preserved for forward compatibility.
  final Map<String, dynamic>? extra;

  const ResourceContents({
    required this.uri,
    this.mimeType,
    this.meta,
    this.extra,
  });

  /// Creates a specific [ResourceContents] subclass from JSON.
  factory ResourceContents.fromJson(Map<String, dynamic> json) {
    final uri = readRequiredAbsoluteUriString(
      json['uri'],
      'ResourceContents.uri',
    );
    final mimeType = json['mimeType'] as String?;
    final meta = _asJsonObjectOrNull(
      json['_meta'],
      'ResourceContents._meta',
    );
    final extra = Map<String, dynamic>.from(json)
      ..removeWhere(
        (key, value) =>
            key == 'uri' ||
            key == 'mimeType' ||
            key == 'text' ||
            key == 'blob' ||
            key == '_meta',
      );

    final passthrough =
        extra.isEmpty ? null : readJsonObject(extra, 'ResourceContents.extra');

    if (json.containsKey('text')) {
      return TextResourceContents(
        uri: uri,
        mimeType: mimeType,
        text: json['text'] as String,
        meta: meta,
        extra: passthrough,
      );
    }
    if (json.containsKey('blob')) {
      return BlobResourceContents(
        uri: uri,
        mimeType: mimeType,
        blob: readRequiredBase64String(
          json['blob'],
          'BlobResourceContents.blob',
        ),
        meta: meta,
        extra: passthrough,
      );
    }
    return UnknownResourceContents(
      uri: uri,
      mimeType: mimeType,
      meta: meta,
      extra: passthrough,
    );
  }

  /// Converts resource contents to JSON.
  Map<String, dynamic> toJson() => {
        'uri': _absoluteUriForJson(uri, 'ResourceContents.uri'),
        if (mimeType != null) 'mimeType': mimeType,
        ...switch (this) {
          final TextResourceContents c => {'text': c.text},
          final BlobResourceContents c => {
              'blob': _base64ForJson(c.blob, 'BlobResourceContents.blob'),
            },
          UnknownResourceContents _ => {},
        },
        if (meta != null)
          '_meta': readJsonObject(meta, 'ResourceContents._meta'),
        if (extra != null) ...readJsonObject(extra, 'ResourceContents.extra'),
      };
}

/// Resource contents represented as text.
class TextResourceContents extends ResourceContents {
  /// The text content.
  final String text;

  const TextResourceContents({
    required super.uri,
    super.mimeType,
    super.meta,
    super.extra,
    required this.text,
  });
}

/// Resource contents represented as binary data (Base64 encoded).
class BlobResourceContents extends ResourceContents {
  /// Base64 encoded binary data.
  final String blob;

  const BlobResourceContents({
    required super.uri,
    super.mimeType,
    super.meta,
    super.extra,
    required this.blob,
  });
}

/// Represents unknown or passthrough resource content types.
class UnknownResourceContents extends ResourceContents {
  const UnknownResourceContents({
    required super.uri,
    super.mimeType,
    super.meta,
    super.extra,
  });
}

/// Theme hint for icon rendering.
enum IconTheme { light, dark }

/// A UI icon reference.
class McpIcon {
  /// URI for the icon image (HTTP(S) URL or data URI).
  final String src;

  /// Optional MIME type override.
  final String? mimeType;

  /// Optional supported sizes (for example: `48x48`, `96x96`, `any`).
  final List<String>? sizes;

  /// Optional preferred theme for the icon.
  final IconTheme? theme;

  const McpIcon({
    required this.src,
    this.mimeType,
    this.sizes,
    this.theme,
  });

  factory McpIcon.fromJson(Map<String, dynamic> json) {
    final themeString = _readOptionalPresentString(
      json,
      'theme',
      'McpIcon.theme',
    );
    final iconTheme = switch (themeString) {
      'light' => IconTheme.light,
      'dark' => IconTheme.dark,
      null => null,
      _ => throw const FormatException(
          'McpIcon.theme must be either "light" or "dark"',
        ),
    };

    return McpIcon(
      src: _readRequiredAbsoluteUriString(json['src'], 'McpIcon.src'),
      mimeType: _readOptionalPresentString(
        json,
        'mimeType',
        'McpIcon.mimeType',
      ),
      sizes: _readOptionalPresentStringList(json, 'sizes', 'McpIcon.sizes'),
      theme: iconTheme,
    );
  }

  Map<String, dynamic> toJson() {
    _validateAbsoluteUriString(src, 'McpIcon.src');

    return {
      'src': src,
      if (mimeType != null) 'mimeType': mimeType,
      if (sizes != null) 'sizes': sizes,
      if (theme != null) 'theme': theme!.name,
    };
  }
}

/// Base class for content parts within prompts or tool results.
sealed class Content {
  /// The type of the content part.
  final String type;

  const Content({
    required this.type,
  });

  factory Content.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'text' => TextContent.fromJson(json),
      'image' => ImageContent.fromJson(json),
      'audio' => AudioContent.fromJson(json),
      'resource_link' => ResourceLink.fromJson(json),
      'resource' => EmbeddedResource.fromJson(json),
      _ => UnknownContent(type: type ?? 'unknown'),
    };
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          final TextContent c => {
              'text': c.text,
              if (c.annotations != null) 'annotations': c.annotations!.toJson(),
              if (c.meta != null)
                '_meta': readJsonObject(c.meta, 'TextContent._meta'),
            },
          final ImageContent c => {
              'data': _base64ForJson(c.data, 'ImageContent.data'),
              'mimeType': c.mimeType,
              if (c.annotations != null) 'annotations': c.annotations!.toJson(),
              if (c.meta != null)
                '_meta': readJsonObject(c.meta, 'ImageContent._meta'),
            },
          final AudioContent c => {
              'data': _base64ForJson(c.data, 'AudioContent.data'),
              'mimeType': c.mimeType,
              if (c.annotations != null) 'annotations': c.annotations!.toJson(),
              if (c.meta != null)
                '_meta': readJsonObject(c.meta, 'AudioContent._meta'),
            },
          final ResourceLink c => {
              'uri': _absoluteUriForJson(c.uri, 'ResourceLink.uri'),
              'name': c.name,
              if (c.title != null) 'title': c.title,
              if (c.description != null) 'description': c.description,
              if (c.mimeType != null) 'mimeType': c.mimeType,
              if (c.size != null) 'size': c.size,
              if (c.icons != null)
                'icons': c.icons!.map((icon) => icon.toJson()).toList(),
              if (c.annotations != null)
                'annotations': readJsonObject(
                  c.annotations,
                  'ResourceLink.annotations',
                ),
              if (c.meta != null)
                '_meta': readJsonObject(c.meta, 'ResourceLink._meta'),
            },
          final EmbeddedResource c => {
              'resource': c.resource.toJson(),
              if (c.annotations != null) 'annotations': c.annotations!.toJson(),
              if (c.meta != null)
                '_meta': readJsonObject(c.meta, 'EmbeddedResource._meta'),
            },
          UnknownContent _ => {},
        },
      };
}

/// Text content.
class TextContent extends Content {
  /// The text string.
  final String text;

  /// Optional annotations for the content block.
  final Annotations? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const TextContent({
    required this.text,
    this.annotations,
    this.meta,
  }) : super(type: 'text');

  factory TextContent.fromJson(Map<String, dynamic> json) {
    return TextContent(
      text: json['text'] as String,
      annotations: json['annotations'] == null
          ? null
          : Annotations.fromJson(
              _asJsonObject(json['annotations'], 'TextContent.annotations'),
            ),
      meta: _asJsonObjectOrNull(json['_meta'], 'TextContent._meta'),
    );
  }
}

/// Image content.
class ImageContent extends Content {
  /// Base64 encoded image data.
  final String data;

  /// MIME type of the image (e.g., "image/png").
  final String mimeType;

  /// Optional theme hint for legacy icon usage (`light` | `dark`).
  ///
  /// This field is parsed for backwards compatibility with older icon-shaped
  /// payloads. MCP ImageContent content blocks do not serialize `theme`; use
  /// [McpIcon.theme] for advertised icons.
  final String? theme;

  /// Optional annotations for the content block.
  final Annotations? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const ImageContent({
    required this.data,
    required this.mimeType,
    this.theme,
    this.annotations,
    this.meta,
  }) : super(type: 'image');

  factory ImageContent.fromJson(Map<String, dynamic> json) {
    return ImageContent(
      data: readRequiredBase64String(json['data'], 'ImageContent.data'),
      mimeType: json['mimeType'] as String,
      theme: json['theme'] as String?,
      annotations: json['annotations'] == null
          ? null
          : Annotations.fromJson(
              _asJsonObject(json['annotations'], 'ImageContent.annotations'),
            ),
      meta: _asJsonObjectOrNull(json['_meta'], 'ImageContent._meta'),
    );
  }
}

class AudioContent extends Content {
  /// Base64 encoded audio data.
  final String data;

  /// MIME type of the audio (e.g., "audio/wav").
  final String mimeType;

  /// Optional annotations for the content block.
  final Annotations? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const AudioContent({
    required this.data,
    required this.mimeType,
    this.annotations,
    this.meta,
  }) : super(type: 'audio');

  factory AudioContent.fromJson(Map<String, dynamic> json) {
    return AudioContent(
      data: readRequiredBase64String(json['data'], 'AudioContent.data'),
      mimeType: json['mimeType'] as String,
      annotations: json['annotations'] == null
          ? null
          : Annotations.fromJson(
              _asJsonObject(json['annotations'], 'AudioContent.annotations'),
            ),
      meta: _asJsonObjectOrNull(json['_meta'], 'AudioContent._meta'),
    );
  }
}

/// Content embedding a resource.
class EmbeddedResource extends Content {
  /// The embedded resource contents.
  final ResourceContents resource;

  /// Optional annotations for the embedded resource.
  final Annotations? annotations;

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const EmbeddedResource({
    required this.resource,
    this.annotations,
    this.meta,
  }) : super(type: 'resource');

  factory EmbeddedResource.fromJson(Map<String, dynamic> json) {
    return EmbeddedResource(
      resource: ResourceContents.fromJson(
        _asJsonObject(json['resource'], 'EmbeddedResource.resource'),
      ),
      annotations: json['annotations'] == null
          ? null
          : Annotations.fromJson(
              _asJsonObject(
                json['annotations'],
                'EmbeddedResource.annotations',
              ),
            ),
      meta: _asJsonObjectOrNull(json['_meta'], 'EmbeddedResource._meta'),
    );
  }
}

/// A resource reference that can be included in prompts or tool results.
class ResourceLink extends Content {
  /// URI of the linked resource.
  final String uri;

  /// Programmatic/logical name of the resource.
  final String name;

  /// Optional UI-oriented title.
  final String? title;

  /// Optional human-readable description.
  final String? description;

  /// Optional MIME type, if known.
  final String? mimeType;

  /// Optional resource byte size.
  final int? size;

  /// Optional set of UI icons for this resource.
  final List<McpIcon>? icons;

  /// Optional annotations.
  final Map<String, dynamic>? annotations;

  /// Parsed annotations view.
  Annotations? get parsedAnnotations =>
      annotations == null ? null : Annotations.fromJson(annotations!);

  /// Optional metadata.
  final Map<String, dynamic>? meta;

  const ResourceLink({
    required this.uri,
    required this.name,
    this.title,
    this.description,
    this.mimeType,
    this.size,
    this.icons,
    this.annotations,
    this.meta,
  }) : super(type: 'resource_link');

  factory ResourceLink.fromJson(Map<String, dynamic> json) {
    return ResourceLink(
      uri: readRequiredAbsoluteUriString(json['uri'], 'ResourceLink.uri'),
      name: json['name'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      size: readOptionalInteger(json['size'], 'ResourceLink.size'),
      icons: (json['icons'] as List<dynamic>?)
          ?.map((icon) => McpIcon.fromJson(_asJsonObject(icon)))
          .toList(),
      annotations: _asJsonObjectOrNull(
        json['annotations'],
        'ResourceLink.annotations',
      ),
      meta: _asJsonObjectOrNull(json['_meta'], 'ResourceLink._meta'),
    );
  }
}

/// Represents unknown or passthrough content types.
class UnknownContent extends Content {
  const UnknownContent({required super.type});
}
