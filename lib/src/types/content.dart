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
      'resource' => EmbeddedResource.fromJson(json),
      _ => UnknownContent(type: type ?? 'unknown'),
    };
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        ...switch (this) {
          final TextContent c => {'text': c.text},
          final ImageContent c => {'data': c.data, 'mimeType': c.mimeType},
          final AudioContent c => {'data': c.data, 'mimeType': c.mimeType},
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

  const ImageContent({
    required this.data,
    required this.mimeType,
  }) : super(type: 'image');

  factory ImageContent.fromJson(Map<String, dynamic> json) {
    return ImageContent(
      data: json['data'] as String,
      mimeType: json['mimeType'] as String,
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

/// Represents unknown or passthrough content types.
class UnknownContent extends Content {
  const UnknownContent({required super.type});
}
