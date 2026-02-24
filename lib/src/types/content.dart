/// Sealed class representing the contents of a specific resource or sub-resource.
sealed class ResourceContents {
  /// The URI of this resource content.
  final String uri;

  /// The MIME type, if known.
  final String? mimeType;

  const ResourceContents({
    required this.uri,
    this.mimeType,
  });

  /// Creates a specific [ResourceContents] subclass from JSON.
  factory ResourceContents.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'] as String;
    final mimeType = json['mimeType'] as String?;
    if (json.containsKey('text')) {
      return TextResourceContents(
        uri: uri,
        mimeType: mimeType,
        text: json['text'] as String,
      );
    }
    if (json.containsKey('blob')) {
      return BlobResourceContents(
        uri: uri,
        mimeType: mimeType,
        blob: json['blob'] as String,
      );
    }
    return UnknownResourceContents(
      uri: uri,
      mimeType: mimeType,
    );
  }

  /// Converts resource contents to JSON.
  Map<String, dynamic> toJson() => {
        'uri': uri,
        if (mimeType != null) 'mimeType': mimeType,
        ...switch (this) {
          final TextResourceContents c => {'text': c.text},
          final BlobResourceContents c => {'blob': c.blob},
          UnknownResourceContents _ => {},
        },
      };
}

/// Resource contents represented as text.
class TextResourceContents extends ResourceContents {
  /// The text content.
  final String text;

  const TextResourceContents({
    required super.uri,
    super.mimeType,
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
    required this.blob,
  });
}

/// Represents unknown or passthrough resource content types.
class UnknownResourceContents extends ResourceContents {
  const UnknownResourceContents({
    required super.uri,
    super.mimeType,
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
    final themeString = json['theme'] as String?;
    final iconTheme = switch (themeString) {
      'light' => IconTheme.light,
      'dark' => IconTheme.dark,
      _ => null,
    };

    return McpIcon(
      src: json['src'] as String,
      mimeType: json['mimeType'] as String?,
      sizes: (json['sizes'] as List<dynamic>?)?.cast<String>(),
      theme: iconTheme,
    );
  }

  Map<String, dynamic> toJson() => {
        'src': src,
        if (mimeType != null) 'mimeType': mimeType,
        if (sizes != null) 'sizes': sizes,
        if (theme != null) 'theme': theme!.name,
      };
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
          final TextContent c => {'text': c.text},
          final ImageContent c => {
              'data': c.data,
              'mimeType': c.mimeType,
              if (c.theme != null) 'theme': c.theme,
            },
          final AudioContent c => {'data': c.data, 'mimeType': c.mimeType},
          final ResourceLink c => {
              'uri': c.uri,
              'name': c.name,
              if (c.title != null) 'title': c.title,
              if (c.description != null) 'description': c.description,
              if (c.mimeType != null) 'mimeType': c.mimeType,
              if (c.size != null) 'size': c.size,
              if (c.icons != null)
                'icons': c.icons!.map((icon) => icon.toJson()).toList(),
              if (c.annotations != null) 'annotations': c.annotations,
              if (c.meta != null) '_meta': c.meta,
            },
          final EmbeddedResource c => {'resource': c.resource.toJson()},
          UnknownContent _ => {},
        },
      };
}

/// Text content.
class TextContent extends Content {
  /// The text string.
  final String text;

  const TextContent({required this.text}) : super(type: 'text');

  factory TextContent.fromJson(Map<String, dynamic> json) {
    return TextContent(
      text: json['text'] as String,
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
  final String? theme;

  const ImageContent({
    required this.data,
    required this.mimeType,
    this.theme,
  }) : super(type: 'image');

  factory ImageContent.fromJson(Map<String, dynamic> json) {
    return ImageContent(
      data: json['data'] as String,
      mimeType: json['mimeType'] as String,
      theme: json['theme'] as String?,
    );
  }
}

class AudioContent extends Content {
  /// Base64 encoded audio data.
  final String data;

  /// MIME type of the audio (e.g., "audio/wav").
  final String mimeType;

  const AudioContent({
    required this.data,
    required this.mimeType,
  }) : super(type: 'audio');

  factory AudioContent.fromJson(Map<String, dynamic> json) {
    return AudioContent(
      data: json['data'] as String,
      mimeType: json['mimeType'] as String,
    );
  }
}

/// Content embedding a resource.
class EmbeddedResource extends Content {
  /// The embedded resource contents.
  final ResourceContents resource;

  const EmbeddedResource({required this.resource}) : super(type: 'resource');

  factory EmbeddedResource.fromJson(Map<String, dynamic> json) {
    return EmbeddedResource(
      resource: ResourceContents.fromJson(
        json['resource'] as Map<String, dynamic>,
      ),
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
      uri: json['uri'] as String,
      name: json['name'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      size: json['size'] as int?,
      icons: (json['icons'] as List<dynamic>?)
          ?.map((icon) => McpIcon.fromJson(icon as Map<String, dynamic>))
          .toList(),
      annotations: json['annotations'] as Map<String, dynamic>?,
      meta: json['_meta'] as Map<String, dynamic>?,
    );
  }
}

/// Represents unknown or passthrough content types.
class UnknownContent extends Content {
  const UnknownContent({required super.type});
}
